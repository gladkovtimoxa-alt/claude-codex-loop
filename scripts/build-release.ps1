# Сборка автономного релизного APK.
# Запускать из PowerShell: из Git Bash cmd не находит рабочий каталог.
param(
  [string]$AppRoot = 'C:\Users\ass\Desktop\000\app',
  [switch]$WithX86  # добавить x86_64 для эмулятора
)

$ErrorActionPreference = 'Continue'
$env:JAVA_HOME = 'C:\Users\ass\Desktop\Claude-Coder\tools\scoop\apps\temurin17-jdk\current'
$env:ANDROID_HOME = 'C:\Users\ass\AppData\Local\Android\Sdk'
$env:PATH = "$env:JAVA_HOME\bin;C:\Users\ass\Desktop\Claude-Coder\tools\scoop\apps\nodejs-lts\current;" + $env:PATH

# Metro держит хендлы в node_modules и роняет Gradle на удалении .so
Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Set-Location "$AppRoot\android"

# MaxMetaspaceSize по умолчанию 256m — линтеру релиза этого мало
$jvm = '-Xmx4096m -XX:MaxMetaspaceSize=1024m'
$abi = if ($WithX86) { '-PreactNativeReleaseArchitectures=arm64-v8a,x86_64' } else { '' }

$out = & cmd /c ".\gradlew.bat assembleRelease --no-daemon --console=plain -Dorg.gradle.jvmargs=`"$jvm`" $abi 2>&1"
$code = $LASTEXITCODE

if ($code -ne 0) {
  $out | Select-String -Pattern 'What went wrong' -Context 0,5 |
    Select-Object -First 1 | ForEach-Object { $_.Line; $_.Context.PostContext }
  exit 1
}

$apk = "$AppRoot\android\app\build\outputs\apk\release\app-release.apk"
if (Test-Path $apk) {
  '{0:N1} MB  {1}' -f ((Get-Item $apk).Length / 1MB), (Get-Item $apk).LastWriteTime
}
