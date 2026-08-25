#!/usr/bin/env python3
"""Чинит невалидные JSON-escape в JSONL-памяти скила.

Повод: в data/defects.jsonl дважды записали windows-путь (C:\\Users\\...) и
регулярку (\\s*->\\s*\\{) с одиночными обратными слэшами. JSON такие escape
не принимает, и строка становится нечитаемой — а читатель падает целиком,
молча теряя всю память, а не одну запись.

Удваивает только те обратные слэши, которые не начинают допустимую
JSON-escape последовательность. Валидные записи не трогает.

    python scripts/fix-jsonl-escapes.py data/defects.jsonl [--dry-run]
"""
import json
import shutil
import sys
import datetime

VALID_ESCAPE_CHARS = set('"\\/bfnrtu')


def repair_line(line):
    """Вернуть строку с удвоенными «голыми» обратными слэшами."""
    out = []
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == '\\':
            nxt = line[i + 1] if i + 1 < len(line) else ''
            if nxt in VALID_ESCAPE_CHARS:
                out.append(ch)
                out.append(nxt)
                i += 2
                continue
            out.append('\\\\')
            i += 1
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    dry = '--dry-run' in sys.argv

    lines = open(path, encoding='utf-8').read().split('\n')
    result = []
    fixed = 0
    unfixable = 0

    for num, line in enumerate(lines, 1):
        if not line.strip():
            result.append(line)
            continue
        try:
            json.loads(line)
            result.append(line)
            continue
        except ValueError:
            pass

        candidate = repair_line(line)
        try:
            json.loads(candidate)
        except ValueError as exc:
            print('  строка %d: ПОЧИНИТЬ НЕ УДАЛОСЬ (%s)' % (num, exc))
            result.append(line)
            unfixable += 1
            continue
        print('  строка %d: починена' % num)
        result.append(candidate)
        fixed += 1

    if fixed and not dry:
        stamp = datetime.date.today().isoformat()
        backup = '%s.bak-badescape-%s' % (path, stamp)
        shutil.copyfile(path, backup)
        with open(path, 'w', encoding='utf-8', newline='\n') as fh:
            fh.write('\n'.join(result))
        print('бэкап: %s' % backup)

    print('починено: %d, не поддалось: %d%s'
          % (fixed, unfixable, ' (пробный прогон)' if dry else ''))
    return 1 if unfixable else 0


if __name__ == '__main__':
    sys.exit(main())
