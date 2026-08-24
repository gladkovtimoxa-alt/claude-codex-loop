#!/usr/bin/env bash
# Поднять эмулятор как устройство класса «8 ГБ».
# Память задаётся И в config.ini, И флагом -memory: одного config.ini мало.
set -u
SDK="C:/Users/ass/AppData/Local/Android/Sdk"
export ANDROID_HOME="$SDK"
export ANDROID_AVD_HOME="C:/Users/ass/.android/avd"
AVD="${1:-agent34}"

# Без окна и звука: не мешает и не занимает видеокарту. Загрузка ~47 секунд.
"$SDK/emulator/emulator.exe" -avd "$AVD" \
  -no-window -no-audio -no-boot-anim \
  -gpu swiftshader_indirect -no-snapshot \
  -memory 8192 &

echo "жду загрузки..."
for i in $(seq 1 60); do
  sleep 5
  if [ "$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
    echo "готов за $((i*5)) c"
    adb -s emulator-5554 shell cat /proc/meminfo | head -1
    exit 0
  fi
done
echo "не загрузился"
exit 1
