#!/usr/bin/env bash
# Надёжно ловит JS-логи (ReactNativeJS, [local-llm-timings] и т.п.) на РЕАЛЬНОМ
# устройстве, где кольцевой буфер logcat маленький (напр. 256КБ на MTK-телефонах)
# и системный спам вытесняет строки приложения за секунды.
#
# Ловушка, ради которой скрипт написан (defects.jsonl 2026-08-24):
#   grep по всему потоку logcat на реальном телефоне возвращал пусто, хотя
#   приложение живо — строки ReactNativeJS вытеснялись раньше, чем их прочитать.
#   Лечится увеличением буфера ДО теста и фильтром по тегу, а не grep по всему.
#
# Использование:
#   scripts/watch-jslog.sh <device_serial> [pattern] [seconds]
#   scripts/watch-jslog.sh V200000000000000877 local-llm-timings 240
#
# pattern по умолчанию: local-llm-timings   seconds по умолчанию: 180
set -euo pipefail

DEVICE="${1:?нужен серийник устройства (adb devices)}"
PATTERN="${2:-local-llm-timings}"
SECONDS_LIMIT="${3:-180}"

# 1) Увеличить буфер ДО теста — иначе на маленьком буфере логи вытесняются.
adb -s "$DEVICE" logcat -G 16M
# 2) Очистить, чтобы ловить только новое.
adb -s "$DEVICE" logcat -c
echo "Буфер увеличен до 16M, очищен. Слежу за '$PATTERN' до ${SECONDS_LIMIT}с..."

# 3) Фильтровать по тегу ReactNativeJS на стороне logcat (*:S глушит остальное),
#    затем grep по конкретному паттерну. Так системный спам не мешает.
timeout "$SECONDS_LIMIT" adb -s "$DEVICE" logcat ReactNativeJS:V '*:S' \
  | grep --line-buffered -i "$PATTERN" || true
echo "Слежение завершено."
