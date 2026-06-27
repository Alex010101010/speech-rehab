#!/usr/bin/env python3
"""Генератор набора match_pairs (соединение пар касанием, без клавиатуры).

Один тип, три механики (поле kind), один виджет MatchPairsExercise:
  - action  — предмет ↔ действие (мыло→моют)
  - synonym — близкие по значению (скамья→лавка)
  - letter  — слово-с-пропуском ↔ буква (_уб→д), переиспользуем валидированные
              слова из 17_fill_letter.json

Каждое задание = один экран = до PAIRS_PER пар. В пределах экрана правые
значения РАЗНЫЕ (иначе соответствие неоднозначно). У каждого задания понятная
инструкция в prompt (озвучивается виджетом) — для 70+ это критично.

ЧЕРНОВИК: action/synonym составлены ботом — нужна валидация логопедом
(letter наследует валидацию fill_letter). Перезапуск: python3 tools/build_match_pairs.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILL = os.path.join(ROOT, "content", "json", "17_fill_letter.json")
OUT = os.path.join(ROOT, "content", "json", "25_match_pairs.json")
# Решения логопеда по заданиям action/synonym: id -> {approved, comment}.
# approved:false — убрать задание; comment = заметка (правку пар вносим в
# списки ACTION/SYNONYM вручную). letter наследует валидацию fill_letter.
DECISIONS = os.path.join(ROOT, "content", "match_pairs-decisions.json")

PAIRS_PER = 4

PROMPTS = {
    "action": "Соедините предмет и действие: нажмите слово слева, потом подходящее справа",
    "synonym": "Соедините слова, близкие по значению: нажмите слово слева, потом пару справа",
    "letter": "Вставьте букву: нажмите слово слева, потом нужную букву справа",
}

# предмет -> что им делают (инструментальное действие)
ACTION = [
    ("мыло", "моют"), ("нож", "режут"), ("ручка", "пишут"), ("ложка", "едят"),
    ("топор", "рубят"), ("удочка", "ловят"), ("пила", "пилят"),
    ("молоток", "забивают"), ("игла", "шьют"), ("карандаш", "рисуют"),
    ("лопата", "копают"), ("чашка", "пьют"), ("кисть", "красят"),
    ("утюг", "гладят"), ("ножницы", "стригут"), ("веник", "метут"),
    ("расчёска", "причёсывают"), ("фонарик", "светят"), ("лейка", "поливают"),
    ("ключ", "открывают"),
]

# слово -> близкое по значению
SYNONYM = [
    ("доктор", "врач"), ("дорога", "путь"), ("скамья", "лавка"),
    ("мастер", "специалист"), ("труд", "работа"), ("друг", "товарищ"),
    ("еда", "пища"), ("машина", "автомобиль"), ("холод", "мороз"),
    ("дом", "жилище"), ("буря", "шторм"), ("печаль", "грусть"),
    ("смелый", "храбрый"), ("большой", "крупный"), ("граница", "рубеж"),
    ("болезнь", "недуг"),
]


def chunk_distinct(pairs, n):
    """Разбить на группы по n так, чтобы правые значения в группе не повторялись.
    Каждый проход берёт до n элементов с уникальными right; остальное — дальше."""
    groups = []
    rest = list(pairs)
    while rest:
        cur, used, leftover = [], set(), []
        for l, r in rest:
            if len(cur) < n and r not in used:
                cur.append((l, r))
                used.add(r)
            else:
                leftover.append((l, r))
        groups.append(cur)
        rest = leftover
    return [g for g in groups if len(g) >= 2]  # экран минимум из 2 пар


def letter_pairs():
    """Из fill_letter: (слово-с-пропуском, пропущенная буква)."""
    data = json.load(open(FILL, encoding="utf-8"))
    out = []
    for it in data["items"]:
        prompt = (it.get("prompt") or "")
        answer = (it.get("answer") or "")
        if "_" not in prompt or not answer:
            continue
        idx = prompt.index("_")
        if idx >= len(answer):
            continue
        out.append((prompt, answer[idx]))
    return out


def build_kind(kind, pairs, start):
    items = []
    for g in chunk_distinct(pairs, PAIRS_PER):
        start += 1
        items.append({
            "id": f"mp_{start:03d}",
            "level": 0,
            "kind": kind,
            "prompt": PROMPTS[kind],
            "pairs": [{"left": l, "right": r} for l, r in g],
        })
    return items, start


def load_decisions():
    if not os.path.exists(DECISIONS):
        return {}
    return json.load(open(DECISIONS, encoding="utf-8"))


def main():
    decisions = load_decisions()
    # 1. нумеруем ВСЕ задания (id стабильны при отклонении отдельных)
    built, n = [], 0
    for kind, src in (("action", ACTION), ("synonym", SYNONYM),
                      ("letter", letter_pairs())):
        part, n = build_kind(kind, src, n)
        built += part
        print(f"  {kind}: {len(part)} заданий")

    # 2. применяем решения логопеда (только action/synonym; letter — авто)
    items, dropped = [], []
    for it in built:
        dec = decisions.get(it["id"], {})
        if it["kind"] != "letter" and dec.get("approved") is False:
            dropped.append(it["id"])
            continue
        items.append(it)

    # черновик, пока есть action/synonym без явного одобрения логопеда
    def decided(it):
        if it["kind"] == "letter":
            return True
        d = decisions.get(it["id"], {})
        return d.get("approved") is True or bool((d.get("comment") or "").strip())
    is_draft = any(not decided(it) for it in items)

    doc = {
        "type": "match_pairs",
        "title": "Соедините пары",
        "section": "0. Узнавание",
        "draft": is_draft,
        "count": len(items),
        "items": items,
    }
    open(OUT, "w", encoding="utf-8").write(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    print(f"match_pairs: {len(items)} заданий "
          f"(draft={is_draft}, убрано {len(dropped)})")


if __name__ == "__main__":
    main()
