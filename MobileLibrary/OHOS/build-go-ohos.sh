#!/usr/bin/env bash
# One c-shared from AWG + Xray + Psiphon + USQUE (one Go runtime) for HarmonyOS NEXT.
# Copy of the iOS staging flow; does not use or modify persianray-ios/ios-awg-xray.
# OHOS_ARCH=arm64|x86_64|all  (default all). x86_64 is the DevEco emulator ABI.
set -euo pipefail

UNITED=$(cd "$(dirname "$0")/../.." && pwd)
AWG="$UNITED/awg-ios"
XRAY="$UNITED/xray-core"
LIBXRAY="$UNITED/libxray"
PSIPHON="$UNITED/psiphon-ios"
USQUE="$UNITED/usque-ios"

if [ ! -d "$PSIPHON" ]; then
  echo "Psiphon source missing. Put psiphon-ios at $UNITED/psiphon-ios" >&2
  exit 1
fi
if [ ! -f "$AWG/cmd/persianray/export.go" ]; then
  echo "bundled awg-ios missing: $AWG/cmd/persianray/export.go" >&2
  exit 1
fi
if [ ! -f "$XRAY/go.mod" ]; then
  echo "bundled xray-core missing: $XRAY/go.mod" >&2
  exit 1
fi
if [ ! -f "$LIBXRAY/go.mod" ]; then
  echo "bundled libxray missing: $LIBXRAY/go.mod" >&2
  exit 1
fi
if [ ! -f "$PSIPHON/MobileLibrary/psi/psi.go" ]; then
  echo "Psiphon bridge source missing: $PSIPHON/MobileLibrary/psi/psi.go" >&2
  exit 1
fi
if [ ! -f "$USQUE/mobile/mobile.go" ]; then
  echo "USQUE adapter source missing: $USQUE/mobile/mobile.go" >&2
  exit 1
fi

find_native() {
  local cand
  for cand in \
    "${OHOS_SDK_NATIVE:-}" \
    "${OHOS_NDK_HOME:-}" \
    "${OHOS_SDK:-}/native" \
    "${OHOS_SDK:-}" \
    "${HOS_SDK_HOME:-}/default/openharmony/native" \
    "${HOS_SDK_HOME:-}/native" \
    "${DEVECO_SDK_HOME:-}/default/openharmony/native" \
    "${DEVECO_SDK_HOME:-}/openharmony/native"
  do
    [ -n "$cand" ] || continue
    if [ -e "$cand/llvm/bin/aarch64-unknown-linux-ohos-clang" ] || \
       [ -e "$cand/llvm/bin/aarch64-unknown-linux-ohos-clang.exe" ] || \
       [ -e "$cand/llvm/bin/x86_64-unknown-linux-ohos-clang" ] || \
       [ -e "$cand/llvm/bin/x86_64-unknown-linux-ohos-clang.exe" ]; then
      printf '%s\n' "$cand"
      return 0
    fi
    if [ -e "$cand/native/llvm/bin/aarch64-unknown-linux-ohos-clang" ] || \
       [ -e "$cand/native/llvm/bin/x86_64-unknown-linux-ohos-clang" ] || \
       [ -e "$cand/native/llvm/bin/aarch64-unknown-linux-ohos-clang.exe" ]; then
      printf '%s\n' "$cand/native"
      return 0
    fi
  done
  return 1
}

NATIVE="$(find_native || true)"
if [ -z "$NATIVE" ]; then
  echo "HarmonyOS/OpenHarmony native NDK not found." >&2
  echo "Set OHOS_NDK_HOME to the folder that contains llvm/bin/aarch64-unknown-linux-ohos-clang" >&2
  exit 1
fi

echo "==> united=$UNITED"
echo "==> native=$NATIVE"

STAGE="$UNITED/.staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"

cp "$AWG/cmd/persianray/"*.go "$STAGE/"
rm -f "$STAGE/go.mod" "$STAGE/go.sum"
cp "$UNITED/xray_bridge.go" "$STAGE/"
cp "$UNITED/psiphon_bridge.go" "$STAGE/"
cp "$UNITED/usque_bridge.go" "$STAGE/"
cp "$UNITED/go.mod" "$STAGE/"
if [ -f "$UNITED/go.sum" ]; then
  cp "$UNITED/go.sum" "$STAGE/"
fi

python3 - "$STAGE/go.mod" "$AWG" "$XRAY" "$LIBXRAY" "$PSIPHON" "$USQUE" <<'PY'
import pathlib, sys
mod = pathlib.Path(sys.argv[1])
awg, xray, libx, psiphon, usque = (pathlib.Path(p).resolve().as_posix() for p in sys.argv[2:])
text = mod.read_text(encoding="utf-8")
repls = {
    "replace github.com/amnezia-vpn/amneziawg-go/v3 => ./awg-ios":
        f"replace github.com/amnezia-vpn/amneziawg-go/v3 => {awg}",
    "replace github.com/xtls/xray-core => ./xray-core":
        f"replace github.com/xtls/xray-core => {xray}",
    "replace github.com/xtls/libxray => ./libxray":
        f"replace github.com/xtls/libxray => {libx}",
    "replace github.com/Psiphon-Labs/psiphon-tunnel-core => ./psiphon-ios":
        f"replace github.com/Psiphon-Labs/psiphon-tunnel-core => {psiphon}",
    "replace github.com/Psiphon-Labs/quic-go => ./psiphon-ios/vendor/github.com/Psiphon-Labs/quic-go":
        f"replace github.com/Psiphon-Labs/quic-go => {psiphon}/vendor/github.com/Psiphon-Labs/quic-go",
    "replace github.com/Diniboy1123/usque => ./usque-ios":
        f"replace github.com/Diniboy1123/usque => {usque}",
    "replace github.com/tailscale/netlink => ./psiphon-ios/vendor/github.com/tailscale/netlink":
        f"replace github.com/tailscale/netlink => {psiphon}/vendor/github.com/tailscale/netlink",
}
for old, new in repls.items():
    if old not in text:
        raise SystemExit(f"go.mod missing line: {old}")
    text = text.replace(old, new)
mod.write_text(text, encoding="utf-8")
PY

cd "$STAGE"
go mod edit -go=1.26.3

SYSROOT="$NATIVE/sysroot"
if [ ! -d "$SYSROOT" ]; then
  echo "sysroot missing: $SYSROOT" >&2
  exit 1
fi

tool() {
  local name="$1"
  if [ -x "$NATIVE/llvm/bin/${name}" ]; then
    printf '%s\n' "$NATIVE/llvm/bin/${name}"
    return 0
  fi
  if [ -x "$NATIVE/llvm/bin/${name}.exe" ]; then
    printf '%s\n' "$NATIVE/llvm/bin/${name}.exe"
    return 0
  fi
  return 1
}

build_one() {
  local arch="$1"
  local goarch clang clangxx target abi out
  case "$arch" in
    arm64)
      goarch=arm64
      target=aarch64-linux-ohos
      abi=arm64-v8a
      clang="$(tool aarch64-unknown-linux-ohos-clang)" || {
        echo "missing aarch64-unknown-linux-ohos-clang" >&2
        return 1
      }
      clangxx="$(tool aarch64-unknown-linux-ohos-clang++)" || clangxx="$clang"
      ;;
    x86_64)
      goarch=amd64
      target=x86_64-linux-ohos
      abi=x86_64
      clang="$(tool x86_64-unknown-linux-ohos-clang)" || {
        echo "missing x86_64-unknown-linux-ohos-clang (needed for the DevEco emulator)" >&2
        return 1
      }
      clangxx="$(tool x86_64-unknown-linux-ohos-clang++)" || clangxx="$clang"
      ;;
    *)
      echo "Unknown OHOS_ARCH=$arch (use arm64, x86_64, or all)" >&2
      return 1
      ;;
  esac

  out="$UNITED/build/ohos-${arch}"
  rm -rf "$out"
  mkdir -p "$out"

  export CGO_ENABLED=1
  export GOOS=linux
  export GOARCH="$goarch"
  export CC="$clang"
  export CXX="$clangxx"
  export AR="$(tool llvm-ar)"
  export CGO_CFLAGS="--target=$target --sysroot=$SYSROOT -fPIC -O2"
  export CGO_LDFLAGS="--target=$target --sysroot=$SYSROOT -fuse-ld=lld"

  echo "==> go build -buildmode=c-shared (linux/$goarch, $target)"
  echo "==> clang=$clang"
  go build -mod=mod -tags PSIPHON_DISABLE_INPROXY -buildmode=c-shared -trimpath \
    -ldflags "-s -w" \
    -o "$out/libpersianray_go.so" .

  cp "$UNITED/include/libawgxray.h" "$out/"
  cp "$UNITED/include/libawg.h" "$out/"
  cp "$UNITED/include/libxray.h" "$out/"
  cp "$UNITED/include/libusque.h" "$out/"
  rm -f "$out/libpersianray_go.h"

  if command -v nm >/dev/null 2>&1; then
    nm -D --defined-only "$out/libpersianray_go.so" > "$out/symbols.txt" || nm -D "$out/libpersianray_go.so" > "$out/symbols.txt"
    for symbol in \
      AwgStart \
      AwgStop \
      CGoInvoke \
      CGoFree \
      PRPsiphonStart \
      PRPsiphonStop \
      PRPsiphonNoticePoll \
      PRPsiphonSocksPort \
      PRUsqueInvoke \
      PRUsqueRegister \
      PRUsqueStart \
      PRUsqueStop \
      PRUsqueStopAll \
      PRUsqueStatus \
      PRUsqueIsReady \
      PRUsqueLastError \
      PRUsqueProbe \
      PRUsqueFree \
      PRUsqueIsStub; do
      grep -E "[[:space:]]${symbol}$" "$out/symbols.txt" >/dev/null || {
        echo "Missing required symbol: $symbol" >&2
        return 1
      }
    done
    echo "==> C ABI symbols ok ($arch)"
  fi

  APP="${HARMONYOS_APP:-}"
  if [ -z "$APP" ] && [ -d "$UNITED/../persianray-harmonyos" ]; then
    APP="$(cd "$UNITED/../persianray-harmonyos" && pwd)"
  fi
  if [ -n "$APP" ] && [ -d "$APP/entry" ]; then
    mkdir -p "$APP/entry/libs/$abi" "$APP/entry/src/main/cpp/include"
    cp "$out/libpersianray_go.so" "$APP/entry/libs/$abi/"
    cp "$out/"*.h "$APP/entry/src/main/cpp/include/"
    echo "==> copied into $APP/entry/libs/$abi"
  fi

  echo "==> $out/libpersianray_go.so"
}

ARCHS="${OHOS_ARCH:-all}"
if [ "$ARCHS" = "all" ]; then
  ARCHS="arm64 x86_64"
fi
built=""
for arch in $ARCHS; do
  if [ "$arch" = "x86_64" ] && [ "${OHOS_ARCH:-all}" = "all" ]; then
    if ! tool x86_64-unknown-linux-ohos-clang >/dev/null 2>&1; then
      echo "==> skip x86_64 (no x86_64-unknown-linux-ohos-clang in NDK)"
      continue
    fi
  fi
  build_one "$arch"
  built="$built $arch"
done
if [ -z "${built## }" ]; then
  echo "No libpersianray_go.so was built. Install the OpenHarmony native NDK and retry." >&2
  exit 1
fi
