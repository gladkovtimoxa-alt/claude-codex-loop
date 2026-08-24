#!/usr/bin/env bash
# Тап по элементу с заданным текстом — АТОМАРНО: дамп прямо перед тапом,
# никогда не по координатам из предыдущего дампа или из памяти.
#
# Причина существования этого скрипта: в сессии 2026-08-24 повторялся один и тот
# же дефект — тап по координатам, снятым с ПРЕДЫДУЩЕГО состояния экрана (после
# смены раскладки/после ответа модели/после прокрутки координаты сдвигались,
# и тап промахивался мимо, тратя минуты впустую на несуществующий ввод).
# Правило: НИКОГДА не переиспользуй координаты между вызовами. Всегда через
# этот скрипт или эквивалентную дамп-затем-тап пару в одной команде.
#
#   ./tap-by-text.sh <serial> "точный или частичный текст" [--partial]
#
# Без --partial ищет точное совпадение text="...". С --partial — вхождение
# подстроки (медленнее матчится, но переживает мелкие несовпадения текста).
set -u
SERIAL="${1:?укажи serial устройства}"
PATTERN="${2:?укажи текст элемента}"
MODE="${3:-}"

# Путь ОБЯЗАН быть Windows-стилем (C:/...), не /tmp/...: python3 здесь —
# нативный Windows-питон, а не MSYS, и не видит Unix-пути /tmp — молча не
# находит файл, скрипт молча врёт "не найдено" вместо реальной ошибки чтения.
DUMP="C:/Users/ass/AppData/Local/Temp/_tap_$$.xml"
MSYS_NO_PATHCONV=1 adb -s "$SERIAL" shell uiautomator dump /sdcard/_tap.xml >/dev/null 2>&1
MSYS_NO_PATHCONV=1 adb -s "$SERIAL" shell cat /sdcard/_tap.xml > "$DUMP" 2>/dev/null

# Ищет и text=, и content-desc=: кнопки-иконки (отправить, убрать, камера)
# часто без видимого текста, метка доступности — единственный якорь.
COORD=$(python3 - "$DUMP" "$PATTERN" "$MODE" <<'PY'
import re, sys, html
path, pattern, mode = sys.argv[1], sys.argv[2], sys.argv[3]
xml = open(path, encoding='utf-8', errors='ignore').read()
for m in re.finditer(r'<node[^>]*\bbounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*/?>', xml):
    node = m.group(0)
    tm = re.search(r'\btext="([^"]*)"', node)
    dm = re.search(r'\bcontent-desc="([^"]*)"', node)
    label = html.unescape((tm.group(1) if tm else '') or (dm.group(1) if dm else ''))
    if not label.strip():
        continue
    hit = (pattern in label) if mode == '--partial' else (label == pattern)
    if hit:
        x = (int(m.group(1)) + int(m.group(3))) // 2
        y = (int(m.group(2)) + int(m.group(4))) // 2
        print(f"{x} {y}")
        break
PY
)
rm -f "$DUMP"

if [ -z "$COORD" ]; then
  echo "НЕ НАЙДЕНО: текст '$PATTERN' отсутствует на текущем экране." >&2
  exit 1
fi

read -r X Y <<< "$COORD"
adb -s "$SERIAL" shell input tap "$X" "$Y"
echo "тап: '$PATTERN' -> ($X, $Y)"
