# Windows wrapper for MobileLibrary/OHOS/build-go-ohos.sh
# Does not touch persianray-ios/ios-awg-xray.
$ErrorActionPreference = "Stop"

$United = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Script = Join-Path $PSScriptRoot "build-go-ohos.sh"

function Find-OhosNative {
  $candidates = @(
    $env:OHOS_SDK_NATIVE,
    $env:OHOS_NDK_HOME,
    $(if ($env:OHOS_SDK) { Join-Path $env:OHOS_SDK "native" }),
    $env:OHOS_SDK,
    $(if ($env:HOS_SDK_HOME) { Join-Path $env:HOS_SDK_HOME "default\openharmony\native" }),
    $(if ($env:DEVECO_SDK_HOME) { Join-Path $env:DEVECO_SDK_HOME "default\openharmony\native" })
  )
  $searchRoots = @(
    "$env:LOCALAPPDATA\Huawei\Sdk",
    "$env:LOCALAPPDATA\OpenHarmony\Sdk",
    "${env:ProgramFiles}\Huawei\DevEco Studio\sdk"
  )
  foreach ($c in $candidates) {
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    if (Test-Path (Join-Path $c "llvm\bin\aarch64-unknown-linux-ohos-clang.exe")) { return $c }
    if (Test-Path (Join-Path $c "llvm\bin\aarch64-unknown-linux-ohos-clang")) { return $c }
    $nested = Join-Path $c "native"
    if (Test-Path (Join-Path $nested "llvm\bin\aarch64-unknown-linux-ohos-clang.exe")) { return $nested }
  }
  foreach ($root in $searchRoots) {
    if (-not (Test-Path $root)) { continue }
    $hit = Get-ChildItem -Path $root -Recurse -Filter "aarch64-unknown-linux-ohos-clang.exe" -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($hit) {
      return (Resolve-Path (Join-Path $hit.Directory.FullName "..\..")).Path
    }
  }
  return $null
}

$native = Find-OhosNative
if (-not $native) {
  Write-Error "HarmonyOS native NDK not found. Set OHOS_NDK_HOME to the folder that contains llvm\bin\aarch64-unknown-linux-ohos-clang."
}

$env:OHOS_NDK_HOME = $native
Write-Host "==> OHOS_NDK_HOME=$native"

$bash = $null
foreach ($b in @(
    "bash",
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
  )) {
  $cmd = Get-Command $b -ErrorAction SilentlyContinue
  if ($cmd) { $bash = $cmd.Source; break }
  if (Test-Path $b) { $bash = $b; break }
}
if (-not $bash) {
  Write-Error "Git Bash not found. Install Git for Windows, or run the GitHub Action harmonyos-persianray-core."
}

$drive = $Script.Substring(0, 1).ToLowerInvariant()
$unixScript = '/' + $drive + ($Script.Substring(2) -replace '\\', '/')
& $bash -eu $unixScript
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
