#!/usr/bin/env python3
"""Генератор набора auto_series (автоматизированные ряды — растормаживание речи).

Привычные автоматизированные ряды (счёт, дни недели, месяцы, сезоны, части
суток). Пациент видит начало ряда, продолжает ВСЛУХ, затем «Показать ряд»
проверяет/озвучивает целиком. Без оценки — это разминка/растормаживание
непроизвольной речи (грубая форма, МОНИКИ/Гришанина).

Контент объективный (последовательности) — валидация логопедом не нужна
(draft:false). Виджет — SeriesExercise. Перезапуск: python3 tools/build_auto_series.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "content", "json", "26_auto_series.json")

COUNT10 = ["один", "два", "три", "четыре", "пять",
           "шесть", "семь", "восемь", "девять", "десять"]
DAYS = ["понедельник", "вторник", "среда", "четверг",
        "пятница", "суббота", "воскресенье"]
MONTHS = ["январь", "февраль", "март", "апрель", "май", "июнь",
          "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
SEASONS = ["зима", "весна", "лето", "осень"]
PARTS = ["утро", "день", "вечер", "ночь"]

PROMPT = {
    "count": "Посчитайте дальше вслух, потом нажмите «Показать ряд»",
    "days": "Назовите дни недели по порядку вслух, потом «Показать ряд»",
    "months": "Назовите месяцы по порядку вслух, потом «Показать ряд»",
    "seasons": "Назовите времена года по порядку вслух, потом «Показать ряд»",
    "parts": "Назовите части суток по порядку вслух, потом «Показать ряд»",
}

# (kind, ряд, сколько элементов показать в начале) — варианты start для разнообразия
SERIES = [
    ("count", COUNT10, 3),
    ("count", COUNT10, 1),
    ("days", DAYS, 3),
    ("days", DAYS, 1),
    ("months", MONTHS, 3),
    ("months", MONTHS, 2),
    ("seasons", SEASONS, 1),
    ("parts", PARTS, 1),
]


def main():
    items = []
    for i, (kind, seq, start) in enumerate(SERIES, 1):
        items.append({
            "id": f"as_{i:03d}",
            "level": 0,
            "kind": kind,
            "prompt": PROMPT[kind],
            "start": start,
            "items": seq,
        })
    doc = {
        "type": "auto_series",
        "title": "Продолжите ряд",
        "section": "0. Узнавание",
        "draft": False,  # объективные последовательности — ревью не требуется
        "count": len(items),
        "items": items,
    }
    open(OUT, "w", encoding="utf-8").write(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    print(f"auto_series: {len(items)} заданий → {OUT}")


if __name__ == "__main__":
    main()
