#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Проверяет data/defects.jsonl перед коммитом.

Зачем. У этой памяти валидатора не было вовсе, хотя файл уже трижды
портился: heredoc съедал обратные слэши и делал JSON невалидным, а
починка вслепую однажды молча испортила данные (см. fix-jsonl-escapes.py).
Проверка обязана идти ДО коммита: один раз сломанная память уже уехала
в удалённый репозиторий, потому что проверяли после отправки.

Схема выведена из самих данных, а не придумана:
  found_at, found_by, symptom, first_hypothesis, real_cause, prevented_by

first_hypothesis и found_by намеренно НЕ обязательны, а лишь
предупреждают. Часть записей — это пометки вида «ОБЩЕЕ НАБЛЮДЕНИЕ,
не дефект» и решения владельца: у них не было ни гипотезы, ни того,
кто «нашёл». Требовать эти поля — значит заставить будущего себя
выдумывать их задним числом, то есть портить память ради зелёной
галочки. Валидатор обязан ловить поломку данных, а не принуждать
к выдумке.

Запуск:
    python scripts/validate-memory.py data/defects.jsonl

Код возврата 0 — можно коммитить, 1 — нельзя.
"""
from __future__ import print_function

import io
import json
import sys

REQUIRED = ("found_at", "symptom", "real_cause", "prevented_by")
OPTIONAL = ("first_hypothesis", "found_by")
KNOWN = set(REQUIRED) | set(OPTIONAL)


def main(path):
    errors = []
    warnings = []
    seen = {}
    count = 0

    with io.open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            raw = raw.strip()
            if not raw:
                continue
            count += 1

            try:
                row = json.loads(raw)
            except ValueError as exc:
                # Самая частая поломка: heredoc съел обратный слэш.
                errors.append("строка %d: невалидный JSON — %s" % (lineno, exc))
                continue

            if not isinstance(row, dict):
                errors.append("строка %d: ожидался объект" % lineno)
                continue

            for key in REQUIRED:
                if not str(row.get(key, "")).strip():
                    errors.append("строка %d: пустое обязательное поле %s" % (lineno, key))

            for key in OPTIONAL:
                if not str(row.get(key, "")).strip():
                    warnings.append("строка %d: пустое необязательное поле %s"
                                    % (lineno, key))

            unknown = set(row) - KNOWN
            if unknown:
                warnings.append("строка %d: неизвестные поля %s"
                                % (lineno, ", ".join(sorted(unknown))))

            symptom = str(row.get("symptom", "")).strip()
            if symptom:
                if symptom in seen:
                    errors.append("строка %d: дубль symptom (уже в строке %d)"
                                  % (lineno, seen[symptom]))
                else:
                    seen[symptom] = lineno

    for text in warnings:
        print("  ПРЕДУПРЕЖДЕНИЕ: " + text)
    for text in errors:
        print("  ОШИБКА: " + text)

    print("записей: %d, ошибок: %d, предупреждений: %d"
          % (count, len(errors), len(warnings)))

    if errors:
        print("НЕВАЛИДНО — коммитить нельзя")
        return 1

    print("ВАЛИДНО")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("использование: python scripts/validate-memory.py data/defects.jsonl")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
