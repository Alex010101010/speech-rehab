#!/usr/bin/env python3
"""Генератор набора yesno_picture (этаж L0 «да/нет: слово↔картинка»).

Самая нижняя ступень узнавания: показываем картинку и ОДНО слово, спрашиваем
«это <слово>?» — ответ Да/Нет. Бинарный выбор легче, чем выбор из трёх
(picture_word), и опирается на доказательную методику word-picture verification.

Источник — уже валидированный логопедом набор picture_word: на каждую картинку
делаем две карточки — верную (слово = ответ → Да) и неверную (слово = первый
дистрактор → Нет). Так набор наследует валидацию картинок и дистракторов.

ЧЕРНОВИК наследует draft исходного picture_word.

Перезапуск: python3 tools/build_yesno.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "content", "json", "22_picture_word.json")
OUT = os.path.join(ROOT, "content", "json", "24_yesno_picture.json")


def main():
    src = json.load(open(SRC, encoding="utf-8"))
    items = []
    n = 0
    for it in src["items"]:
        word = (it.get("answer") or "").strip()
        img = it.get("image")
        emoji = it.get("emoji", "")
        if not word or not img:
            continue
        # верная карточка: «это <ответ>?» → Да
        n += 1
        items.append({
            "id": f"yn_{n:03d}",
            "level": 0,
            "image": img,
            "word": word,
            "match": True,
            "emoji": emoji,
        })
        # неверная карточка: «это <дистрактор>?» → Нет (берём первый дистрактор)
        opts = [o for o in (it.get("options") or []) if o and o != word]
        if opts:
            n += 1
            items.append({
                "id": f"yn_{n:03d}",
                "level": 0,
                "image": img,
                "word": opts[0],
                "match": False,
                "emoji": emoji,
            })

    doc = {
        "type": "yesno_picture",
        "title": "Это правильное слово?",
        "section": "0. Узнавание",
        "draft": bool(src.get("draft", False)),
        "count": len(items),
        "items": items,
    }
    open(OUT, "w", encoding="utf-8").write(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    print(f"yesno_picture: {len(items)} заданий из {len(src['items'])} картинок")
    print(f"  → {OUT} (ассет соберёт tools/build_assets.py)")


if __name__ == "__main__":
    main()
