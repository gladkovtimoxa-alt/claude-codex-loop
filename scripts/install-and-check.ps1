# Установка APK и проверка, что приложение РЕАЛЬНО поднялось.
# Живой процесс не означает работающее приложение: релизная сборка при ошибке JS
# молча рисует пустой экран, без записи в logcat. Поэтому проверяем дерево UI.
param(
  [string]$Serial,
  [string]$Apk = 'C:\Users\ass\Desktop\000\app\android\app\build\outputs\apk\release\app-release.apk',
  [string]$Pkg = 'com.anonymous.assistant'
)

$ErrorActionPreference = 'Continue'
$env:PATH = 'C:\Users\ass\Desktop\Claude-Coder\tools\scoop\shims;' + $env:PATH

if (-not $Serial) { $Serial = (adb devices | Select-Object -Skip 1 | Where-Object { $_ -match 'device$' } | Select-Object -First 1).Split()[0] }
if (-not $Serial) { 'устройств нет'; exit 1 }

# Переустановка поверх сохраняет данные. Удаление стирает их вместе с моделью на 2.9 ГБ.
adb -s $Serial install -r $Apk 2>&1 | Select-Object -Last 1

adb -s $Serial shell am force-stop $Pkg
Start-Sleep -Seconds 3
adb -s $Serial logcat -c | Out-Null
adb -s $Serial shell monkey -p $Pkg -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
Start-Sleep -Seconds 40

$pid_ = (adb -s $Serial shell pidof $Pkg).Trim()
if (-not $pid_) { 'ПРОЦЕСС НЕ ЗАПУСТИЛСЯ'; exit 1 }

# Главная проверка: на экране действительно что-то есть
adb -s $Serial shell uiautomator dump /sdcard/_ui.xml 2>&1 | Out-Null
adb -s $Serial pull /sdcard/_ui.xml "$env:TEMP\_ui.xml" 2>&1 | Out-Null
adb -s $Serial shell rm /sdcard/_ui.xml 2>&1 | Out-Null

$xml = Get-Content "$env:TEMP\_ui.xml" -Raw -ErrorAction SilentlyContinue
$texts = [regex]::Matches($xml, 'text="([^"]{2,})"') | ForEach-Object { $_.Groups[1].Value }

"pid=$pid_  элементов с текстом: $($texts.Count)"
if ($texts.Count -eq 0) {
  'ПУСТОЙ ЭКРАН — приложение живёт, но ничего не рисует. Ищи ошибку в структуре навигации.'
  exit 1
}
$texts | Select-Object -First 8
'ОК'
