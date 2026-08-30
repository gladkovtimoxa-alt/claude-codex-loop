#!/usr/bin/env bash
# publish-memory.sh — публикация скила-памяти в его собственный репозиторий.
#
# Зачем скрипт, а не абзац в README. Процедура публикации уже описана словами,
# и это не помогло: 30.08 очевидный `git push <remote> main` из каталога скила
# был выполнен, целился не в тот репозиторий, а совет git слить удалённое начал
# переписывать 122 коммита — каталог исчез посреди операции. Правило лежало в
# памяти и не сработало, потому что память, которую надо ВСПОМНИТЬ, не работает
# в момент действия. Работает только та, которую надо ВЫПОЛНИТЬ.
#
# Скрипт делает весь цикл и отказывает кодом возврата:
#   0 — опубликовано и сверено (или публиковать было нечего)
#   1 — отказ до отправки: сломан JSONL, найден секрет, нет remote
#   2 — отправка прошла, но СВЕРКА НЕ СОШЛАСЬ — считать неопубликованным
#
# Использование:
#   scripts/publish-memory.sh                      # текущий скил, автоопределение
#   scripts/publish-memory.sh <каталог> <remote>   # явно
#   scripts/publish-memory.sh --all                # оба известных скила
#   DRY_RUN=1 scripts/publish-memory.sh            # всё кроме push и коммита

set -uo pipefail

CYAN=''; RED=''; GRN=''; OFF=''
if [ -t 1 ]; then CYAN=$'\033[36m'; RED=$'\033[31m'; GRN=$'\033[32m'; OFF=$'\033[0m'; fi
say(){ echo "${CYAN}==>${OFF} $*"; }
bad(){ echo "${RED}ОТКАЗ:${OFF} $*" >&2; }
ok(){ echo "${GRN}ok${OFF} $*"; }

DRY_RUN="${DRY_RUN:-0}"

# Реестр известных скилов: <каталог>|<remote>. Каталог — абсолютный.
REGISTRY=(
  "/c/Users/ass/Desktop/000/skills/claude-codex-loop|loop"
  "/c/Users/ass/Desktop/vpnyour-live/.claude/skills/vpnyour|skill"
)

# --- проверки, каждая отказывает сама -------------------------------------

# JSONL обязан читаться ЦЕЛИКОМ: одна битая строка делает недоступной всю
# память, потому что читают её списком. Проверка идёт ДО коммита — один раз
# сломанный файл уже уехал в удалённый репозиторий именно потому, что
# проверяли после отправки.
check_jsonl(){
  local dir="$1" rc=0 f
  shopt -s nullglob
  for f in "$dir"/data/*.jsonl; do
    if ! python -c "
import json,sys
p=sys.argv[1]; n=0
for i,l in enumerate(open(p,encoding='utf-8'),1):
    if l.strip():
        try: json.loads(l)
        except Exception as e:
            print(f'  строка {i}: {e}'); sys.exit(1)
        n+=1
print(f'  {p}: {n} записей')
" "$f"; then bad "битый JSONL: $f"; rc=1; fi
  done
  shopt -u nullglob
  # родной валидатор скила, если есть
  if [ -f "$dir/scripts/validate-memory.py" ] && [ -f "$dir/data/defects.jsonl" ]; then
    python "$dir/scripts/validate-memory.py" "$dir/data/defects.jsonl" >/dev/null 2>&1 \
      || { bad "validate-memory.py вернул отказ"; rc=1; }
  fi
  return $rc
}

# Скил уезжает в ОТДЕЛЬНЫЙ репозиторий, и туда не должно попасть ничего из
# монорепо. Для vpnyour это критично: рядом лежит DEPLOY/ с SECRETS.md,
# SERVER-ACCESS.md и боевыми конфигами.
check_secrets(){
  local dir="$1" hits
  hits=$(find "$dir" -type f \
    \( -iname "SECRETS*" -o -iname "SERVER-ACCESS*" -o -name ".env" \
       -o -name "id_ed25519*" -o -name "*.pem" -o -name "*.key" \
       -o -iname "xray-config*.json" -o -iname "*client.conf" \) 2>/dev/null | wc -l)
  [ "$hits" -eq 0 ] || { bad "в каталоге скила найдены файлы, похожие на секреты ($hits)"; return 1; }
  # Содержимое, а не только имена. Два предостережения, оба пойманы опытом:
  #
  # 1. Паттерн собирается СКЛЕЙКОЙ, иначе проверка находит саму себя: первая
  #    версия отказала на этом файле, потому что искомый образец лежал в её же
  #    исходнике. Ложная тревога такого рода блокирует публикацию навсегда и
  #    выглядит как настоящая находка.
  # 2. Сам скрипт исключён из обхода по той же причине — защита в два слоя.
  local pat="PRIVATE"" KEY-----"
  local self; self=$(basename "${BASH_SOURCE[0]}")
  if grep -rlE "$pat|^[A-Za-z0-9+/]{43}=$" "$dir" --exclude="$self" >/dev/null 2>&1; then
    bad "в каталоге скила найден приватный ключ по содержимому:"
    grep -rlE "$pat|^[A-Za-z0-9+/]{43}=$" "$dir" --exclude="$self" 2>/dev/null | sed 's/^/    /' >&2
    return 1
  fi
  return 0
}

publish_one(){
  local dir="$1" remote="$2"
  say "скил: $dir  ->  remote '$remote'"

  [ -d "$dir" ] || { bad "каталога нет: $dir"; return 1; }

  local root prefix
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || { bad "не git: $dir"; return 1; }
  prefix=$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)

  # Главная защита. Пустой префикс = скил САМ себе репозиторий, и тогда
  # проекция не нужна; непустой = мы в подкаталоге, и обычный push целится
  # не туда. Отличить можно только так, глазами — нельзя.
  if [ -z "$prefix" ]; then
    bad "префикс пуст: каталог сам является корнем репозитория, проекция не нужна"
    return 1
  fi
  echo "    корень:   $root"
  echo "    префикс:  $prefix"

  git -C "$root" remote get-url "$remote" >/dev/null 2>&1 \
    || { bad "нет remote '$remote' в $root"; return 1; }

  say "проверка памяти до коммита"
  check_jsonl "$dir" || return 1
  say "проверка на секреты"
  check_secrets "$dir" || return 1
  ok "проверки пройдены"

  # Коммитим ТОЛЬКО каталог скила: в монорепо рядом лежит чужая незавершённая
  # работа, и `git commit -a` утащил бы её.
  if [ -n "$(git -C "$root" status --porcelain -- "$prefix")" ]; then
    say "есть изменения в скиле — коммичу"
    if [ "$DRY_RUN" = "1" ]; then
      echo "    DRY_RUN: git add '$prefix' && git commit"
    else
      git -C "$root" add -- "$prefix" || return 1
      # Сообщение можно и нужно задавать: MSG="..." publish-memory.sh
      # Автоматическое ставится только чтобы не блокировать публикацию, но
      # история памяти из таких строк нечитаема — при осмысленной правке
      # передавать своё.
      git -C "$root" commit -q -m "${MSG:-Память скила: обновление $(date '+%Y-%m-%d %H:%M')}" || return 1
      ok "коммит создан"
    fi
  else
    echo "    изменений в скиле нет"
  fi

  if [ "$DRY_RUN" = "1" ]; then echo "    DRY_RUN: subtree push пропущен"; return 0; fi

  say "отправка проекцией (обычный push залил бы весь монорепозиторий)"
  git -C "$root" subtree push --prefix="${prefix%/}" "$remote" main 2>&1 | tail -1

  # СВЕРКА. Не по `git log remote/main..HEAD` — на проекции хеши создаются
  # заново, и такое сравнение даёт один ответ при успехе и при провале.
  # Не грепом по строке — он уже соврал нулём из-за регистра.
  # Сравниваем ДЕРЕВО: совпадение tree-хешей означает побайтно одинаковое
  # содержимое и не зависит ни от кодировки, ни от регистра.
  say "сверка по дереву"
  git -C "$root" fetch -q "$remote" main || { bad "fetch не прошёл"; return 2; }
  local split_sha local_tree remote_tree
  split_sha=$(git -C "$root" subtree split --prefix="${prefix%/}" 2>/dev/null | tail -1)
  local_tree=$(git -C "$root" rev-parse "${split_sha}^{tree}" 2>/dev/null)
  remote_tree=$(git -C "$root" rev-parse "${remote}/main^{tree}" 2>/dev/null)
  echo "    локально: ${local_tree:-нет}"
  echo "    удалённо: ${remote_tree:-нет}"
  if [ -n "$local_tree" ] && [ "$local_tree" = "$remote_tree" ]; then
    ok "содержимое совпадает"
    return 0
  fi
  bad "деревья РАЗОШЛИСЬ — считать неопубликованным"
  return 2
}

# --- уборка за собой -------------------------------------------------------
# Скрипт не оставляет временных файлов; чистим лишь то, что могли оставить
# прошлые ручные починки памяти.
cleanup(){
  local dir="$1" n
  n=$(find "$dir" -name "*.bak-badescape-*" -type f 2>/dev/null | wc -l)
  if [ "$n" -gt 0 ]; then
    say "уборка: $n резервных копий от починки JSONL"
    find "$dir" -name "*.bak-badescape-*" -type f -delete
  fi
}

main(){
  local rc=0
  if [ "${1:-}" = "--all" ]; then
    for entry in "${REGISTRY[@]}"; do
      publish_one "${entry%%|*}" "${entry##*|}" || rc=$?
      cleanup "${entry%%|*}"
      echo
    done
  elif [ $# -ge 2 ]; then
    publish_one "$1" "$2" || rc=$?
    cleanup "$1"
  else
    # автоопределение: ищем текущий каталог в реестре
    local here found=""
    here=$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)
    for entry in "${REGISTRY[@]}"; do
      case "$here" in "${entry%%|*}"*) found="$entry"; break;; esac
    done
    [ -n "$found" ] || { bad "каталог $here не в реестре; укажите <каталог> <remote>"; exit 1; }
    publish_one "${found%%|*}" "${found##*|}" || rc=$?
    cleanup "${found%%|*}"
  fi
  echo
  case $rc in
    0) ok "ГОТОВО";;
    2) bad "ОТПРАВЛЕНО, НО НЕ СВЕРЕНО — проверить вручную";;
    *) bad "НЕ ОПУБЛИКОВАНО";;
  esac
  return $rc
}

main "$@"
