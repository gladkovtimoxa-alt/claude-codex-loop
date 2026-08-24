#!/usr/bin/env bash
# Поднять эмулятор как устройство класса «8 ГБ».
# Память задаётся И в config.ini, И флагом -memory: одного config.ini мало.
set -u
SDK="C:/Users/ass/AppData/Local/Android/Sdk"
export ANDROID_HOME="$SDK"
export ANDROID_AVD_HOME="C:/Users/ass/.android/avd"
AVD="${1:-agent34}"

# -memory ОБЯЗАН совпадать с hw.ramSize из config.ini конкретного AVD — сам
# config.ini недостаточен (см. data/defects.jsonl). Раньше -memory был захардкожен
# в 8192 для любого AVD, из-за чего приложение на всех классах видело 7.8 ГБ.
# Пробелы вокруг "=" в config.ini не гарантированы одинаковыми — допускаем оба вида.
RAM=$(grep -oP '^hw\.ramSize\s*=\s*\K[0-9]+' "$ANDROID_AVD_HOME/$AVD.avd/config.ini" 2>/dev/null)
RAM="${RAM:-2048}"

# Без окна и звука. GPU-хост вместо программного рендерера swiftshader:
# рисует на видеокарте (VRAM), а не грузит CPU — важно при параллельных инстансах.
"$SDK/emulator/emulator.exe" -avd "$AVD" \
  -no-window -no-audio -no-boot-anim \
  -gpu host -no-snapshot \
  -memory "$RAM" &

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
