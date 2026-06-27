#!/usr/bin/env python3
"""Раскладывает выгруженный draft-decisions.json по пер-тип файлам и перегенерит наборы.

Страница tools/draft_review.html выгружает один draft-decisions.json (id -> {approved,
comment}) по трём draft-наборам. Этот скрипт разносит ключи по префиксу id:
  sy_  → content/syllables-decisions.json
  mp_  → content/match_pairs-decisions.json
  wo_  → content/word_order-decisions.json
  ech_ → content/endings_choice-decisions.json
(merge, не перезапись), затем перегенерит наборы и пересобирает ассеты. draft
снимется автоматически, когда все задания набора получат решение.

Запуск:  python3 tools/apply_draft_decisions.py <путь к draft-decisions.json>
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")

PREFIX_FILE = {
    "sy": "syllables-decisions.json",
    "mp": "match_pairs-decisions.json",
    "wo": "word_order-decisions.json",
    "ech": "endings_choice-decisions.json",
}
REGEN = ["build_syllables.py", "build_match_pairs.py", "build_word_order.py",
         "build_endings_choice.py", "build_assets.py"]


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 tools/apply_draft_decisions.py "
                         "<draft-decisions.json>")
    incoming = json.load(open(sys.argv[1], encoding="utf-8"))

    # 1. разнести по префиксу
    buckets = {p: {} for p in PREFIX_FILE}
    unknown = []
    for k, v in incoming.items():
        pref = k.split("_")[0]
        if pref in buckets:
            buckets[pref][k] = v
        else:
            unknown.append(k)
    if unknown:
        print(f"⚠ пропущено {len(unknown)} ключей с неизвестным префиксом: "
              f"{unknown[:5]}{'…' if len(unknown) > 5 else ''}")

    # 2. merge в пер-тип файлы
    for pref, fname in PREFIX_FILE.items():
        new = buckets[pref]
        if not new:
            continue
        path = os.path.join(ROOT, "content", fname)
        cur = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
        cur.update(new)
        json.dump(cur, open(path, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=2)
        print(f"{fname}: +{len(new)} решений (всего {len(cur)})")

    # 3. перегенерить наборы + ассеты
    for script in REGEN:
        print(f"--- {script} ---")
        subprocess.run([sys.executable, os.path.join(HERE, script)], check=True)


if __name__ == "__main__":
    main()
