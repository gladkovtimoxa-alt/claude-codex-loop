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
# Слэш перед этими буквами НЕВОЗМОЖНО починить автоматически: и "настоящий
# управляющий символ", и "windows-путь вида \bin, \temp, \new" выглядят
# одинаково. Молчаливая догадка уже испортила запись: System32\bash.exe
# превратилось в System32<backspace>ash.exe — файл стал валидным, а текст
# потерял букву. Тихая порча хуже явной ошибки разбора.
AMBIGUOUS = set('bfnrtu')


def repair_line(line):
    """Удвоить «голые» обратные слэши.

    Возвращает (строка, список неоднозначных позиций). Если список не пуст,
    чинить автоматически нельзя — нужна правка руками.
    """
    out = []
    ambiguous = []
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == '\\':
            nxt = line[i + 1] if i + 1 < len(line) else ''
            if nxt in VALID_ESCAPE_CHARS:
                if nxt in AMBIGUOUS:
                    ambiguous.append((i, line[max(0, i - 20):i + 20]))
                out.append(ch)
                out.append(nxt)
                i += 2
                continue
            out.append('\\\\')
            i += 1
            continue
        out.append(ch)
        i += 1
    return ''.join(out), ambiguous


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

        candidate, ambiguous = repair_line(line)
        try:
            json.loads(candidate)
        except ValueError as exc:
            print('  строка %d: ПОЧИНИТЬ НЕ УДАЛОСЬ (%s)' % (num, exc))
            result.append(line)
            unfixable += 1
            continue

        if ambiguous:
            print('  строка %d: ЧИНИТЬ АВТОМАТИЧЕСКИ НЕЛЬЗЯ' % num)
            for pos, around in ambiguous:
                print('     позиция %d: …%s…' % (pos, around))
            print('     слэш перед b/f/n/r/t/u: управляющий символ и windows-путь')
            print('     (\\bin, \\temp, \\new) выглядят одинаково. Править руками.')
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
