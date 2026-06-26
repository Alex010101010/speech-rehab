#!/usr/bin/env python3
"""Генератор набора anagram (собрать слово из букв касанием).

Дано слово с перемешанными буквами — собрать в правильном порядке, нажимая
буквы по очереди (виджет OrderExercise, sep=''). Усложнение (L2-L3).

Слова — конкретные, 4-6 букв (объективные; ревью логопедом не требуется,
draft:false). Перезапуск: python3 tools/build_anagram.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "content", "json", "28_anagram.json")

PROMPT = "Соберите слово из букв: нажимайте буквы по порядку"

# конкретные слова, темы рыбалка/быт/природа/еда/животные
WORDS = [
    # 4 буквы → L2
    "рыба", "стол", "лиса", "коза", "роза", "сова", "нога", "рука",
    "мост", "лето", "зима", "море", "река", "гриб", "лист", "ключ",
    # 5-6 букв → L3
    "лодка", "книга", "масло", "ветка", "трава", "рыбак", "сапог",
    "берег", "корова", "молоко", "машина", "собака", "погода", "удочка",
]


def main():
    items = []
    for i, w in enumerate(WORDS, 1):
        items.append({
            "id": f"an_{i:03d}",
            "level": 2 if len(w) <= 4 else 3,
            "prompt": PROMPT,
            "tokens": list(w),
            "answer": w,
        })
    doc = {
        "type": "anagram",
        "title": "Соберите слово из букв",
        "section": "I. Понимание",
        "draft": False,  # объективные слова — ревью не требуется
        "count": len(items),
        "items": items,
    }
    open(OUT, "w", encoding="utf-8").write(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    print(f"anagram: {len(items)} заданий → {OUT}")


if __name__ == "__main__":
    main()
