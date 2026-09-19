# HarmonyOS NEXT engine

`harmonyos-persianray-core` is a copy of `persianray-ios/ios-awg-xray`. Leave the iOS tree untouched. If the iOS engine changes, recopy into this folder and keep the `MobileLibrary/OHOS/` files.

Output: **one** Go runtime as `libpersianray_go.so` (AWG + Xray `CGoInvoke` + Psiphon + USQUE). HarmonyOS cannot load two Go runtimes in one HAP.

Official Go has no working `GOOS=openharmony` `c-shared` target. The build uses `GOOS=linux GOARCH=arm64` with the HarmonyOS/OpenHarmony clang (`aarch64-linux-ohos` + musl sysroot).

## 1. Test the app on a real phone (UI, now)

Connect is still stubbed. You can still run the HAP on hardware and tap through Home, Easy, Scanner, Configs, Settings, and the drawer.

1. Install **DevEco Studio** 6.x with HarmonyOS SDK **6.1.1 (API 24)**.
2. Use a **HarmonyOS NEXT** phone (not the old OpenHarmony/Java project).
3. On the phone: Settings → About → tap Build number → enable **Developer options** and **USB debugging**.
4. Plug in USB. In a terminal:

   ```bat
   hdc list targets
   ```

   You want one device id. If empty: `hdc kill` then unplug/replug, or allow the USB debugging prompt on the phone.
5. Open `persianray-harmonyos/` in DevEco.
6. Sign in with a **Huawei ID**. File → Project Structure → Signing Configs → **Automatically generate signature** (debug).
7. Select the phone in the device dropdown → **Run**.
8. Or install the HAP DevEco already built:

   ```bat
   hdc install entry\build\default\outputs\default\entry-default-signed.hap
   ```

   Preview in the IDE is not a substitute for a device: VPN/network APIs need hardware.

What you can verify today: splash, island tabs, drawer, Connect button state machine (stub), sheets. What you cannot verify until the `.so` is linked: a real tunnel.

## 2. GitHub Action (native `.so`)

Workflow: **`harmonyos-persianray-core`** (`workflow_dispatch`).

It does **not** replace local HAP signing. It only compiles the Go engine:

1. Push `harmonyos-persianray-core/` (this copy) to the repo that already has `.github/workflows/harmonyos-persianray-core.yml`.
2. GitHub → Actions → **harmonyos-persianray-core** → **Run workflow**.
3. Download artifact `libpersianray_go-ohos-arm64`.
4. Drop files into the HAP project:

   ```
   persianray-harmonyos/entry/libs/arm64-v8a/libpersianray_go.so
   persianray-harmonyos/entry/src/main/cpp/include/*.h
   ```

Do **not** add a second Go `.so`. Do not run the iOS `awg-xray-apple` job for this tree.

A later HAP job can use `hvigorw assembleHap`, but that needs Huawei debug/release certs (`*.p12`, `.cer`, `.p7b`) as GitHub secrets. Until those exist, assemble and install from DevEco.

## 3. Local `.so` build (optional)

Need Go **1.26.3**, Python 3, and the HarmonyOS native NDK (DevEco SDK `native/` or `OHOS_NDK_HOME`).

Git Bash / Linux / CI:

```bash
export OHOS_NDK_HOME="/path/to/sdk/default/openharmony/native"  # or the folder that contains llvm/
bash MobileLibrary/OHOS/build-go-ohos.sh
# → build/ohos-arm64/libpersianray_go.so
```

Windows (PowerShell), if Git Bash and the NDK are installed:

```powershell
.\MobileLibrary\OHOS\build-go-ohos.ps1
```

If `persianray-harmonyos` sits next to this folder, the script copies the `.so` and headers there automatically.
