#!/usr/bin/env bash
# Запуск Codex с обязательными флагами.
# Промпт передаётся ФАЙЛОМ: в строке двойных кавычек bash попытается выполнить
# обратные кавычки внутри текста и всё сорвётся с unexpected EOF.
#
#   ./codex.sh задание.txt [read-only]
#
set -u
TASK_FILE="${1:?укажи файл с заданием}"
MODE="${2:-workspace-write}"

PROMPT=$(cat "$TASK_FILE")

cd "C:/Users/ass/Desktop/000" || exit 1

# tools.web_search=true обязателен: прямого интернета в песочнице нет,
# curl падает с SEC_E_NO_CREDENTIALS. Без флага Codex пишет по памяти.
codex exec \
  --skip-git-repo-check \
  -s "$MODE" \
  -m gpt-5.6-terra \
  -c model_reasoning_effort="high" \
  -c tools.web_search=true \
  "$PROMPT" < /dev/null
