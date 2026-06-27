#!/usr/bin/env python3
"""Генератор набора word_order (собрать предложение из слов касанием).

Дано перемешанное предложение — собрать в правильном порядке, нажимая слова
по очереди (виджет OrderExercise, sep=' '). Восстановление синтаксиса/линейной
схемы фразы — усложнение (L2-L3), не для облегчающего тира.

ЧЕРНОВИК: предложения составлены ботом — нужна валидация логопедом
(естественность, уместность). Перезапуск: python3 tools/build_word_order.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "content", "json", "27_word_order.json")
# Решения логопеда: id -> {approved, comment}. approved:false — убрать;
# comment = исправленное предложение (целиком, через пробел).
DECISIONS = os.path.join(ROOT, "content", "word_order-decisions.json")

PROMPT = "Соберите предложение: нажимайте слова по порядку"

# короткие предложения (3-5 слов), темы рыбалка/быт/сварка/природа
SENTENCES = [
    # 3 слова → L2
    "Рыбак поймал щуку",
    "Кот пьёт молоко",
    "Дед читает газету",
    "Мама печёт пирог",
    "Мальчик кормит рыбок",
    "Папа чинит лодку",
    "Бабушка вяжет носки",
    "Собака грызёт кость",
    # 4 слова → L3
    "Рыбак сидит на берегу",
    "Кошка спит на диване",
    "Дети играют во дворе",
    "Дед поймал большую рыбу",
    "Бабушка варит вкусный суп",
    "Машина едет по дороге",
    "Сварщик надел защитную маску",
    "Мальчик рисует красивый дом",
    # 5 слов → L3
    "Рыбак закинул удочку в воду",
    "Кот забрался на высокое дерево",
    "Мама купила свежий белый хлеб",
    "Дед починил старую деревянную лодку",
]


def load_decisions():
    if not os.path.exists(DECISIONS):
        return {}
    return json.load(open(DECISIONS, encoding="utf-8"))


def main():
    decisions = load_decisions()
    items, dropped, overridden = [], [], 0
    # нумеруем по исходному списку (id стабильны при отклонении отдельных)
    for i, s in enumerate(SENTENCES, 1):
        pid = f"wo_{i:03d}"
        dec = decisions.get(pid, {})
        if dec.get("approved") is False:  # отклонено логопедом
            dropped.append(pid)
            continue
        comment = (dec.get("comment") or "").strip()
        if comment:  # логопед прислал исправленное предложение
            s = comment
            overridden += 1
        words = s.split()
        items.append({
            "id": pid,
            "level": 2 if len(words) <= 3 else 3,
            "prompt": PROMPT,
            "tokens": words,
            "answer": s,
        })

    # черновик, пока есть предложение без явного одобрения логопеда
    def decided(pid):
        d = decisions.get(pid, {})
        return d.get("approved") is True or bool((d.get("comment") or "").strip())
    is_draft = any(not decided(it["id"]) for it in items)

    doc = {
        "type": "word_order",
        "title": "Соберите предложение",
        "section": "I. Понимание",
        "draft": is_draft,
        "count": len(items),
        "items": items,
    }
    open(OUT, "w", encoding="utf-8").write(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    print(f"word_order: {len(items)} заданий "
          f"(draft={is_draft}, убрано {len(dropped)}, правок {overridden})")


if __name__ == "__main__":
    main()
