#!/usr/bin/env python3
"""Генератор набора picture_word (этаж L0 «картинка→слово»).

L0 — до-вербальный пол лестницы: показать картинку и 2 дистрактора, спросить
«как это называется?». Узнавание, не воспроизведение (THEORY ч.6, грубая форма).

Источник слов — пары «картинка→слово», уже валидированные логопедом
(одобренные картинки в fill_letter). Дистракторы берутся из того же пула,
без совпадения первой буквы и рифмы — чтобы опора была на смысл, не на форму.

ЧЕРНОВИК: набор требует валидации логопедом (см. content/README.md).

Как добавить картинки позже:
  1) положить файл в app/assets/content/img/<file>.png;
  2) либо привязать его к слову в fill_letter (поле "image"),
     либо дописать пару в EXTRA_PAIRS ниже;
  3) перезапустить: python3 tools/build_picture_word.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILL_LETTER = os.path.join(ROOT, "content", "json", "17_fill_letter.json")
IMG_DIR = os.path.join(ROOT, "app", "assets", "content", "img")
OUT_SRC = os.path.join(ROOT, "content", "json", "22_picture_word.json")
OUT_ASSET = os.path.join(ROOT, "app", "assets", "content", "22_picture_word.json")

# Ручные добавления сверх пар из fill_letter: (image_file, word, emoji).
# emoji — запасная подсказка, если картинка не загрузится.
EXTRA_PAIRS: list[tuple[str, str, str]] = []

OPTIONS_PER_ITEM = 3  # правильный + 2 дистрактора (меньше выбор — легче узнавание)


def collect_pairs():
    """Уникальные пары (word, image, emoji) из fill_letter + EXTRA_PAIRS."""
    data = json.load(open(FILL_LETTER, encoding="utf-8"))
    pairs, seen = [], set()
    for it in data["items"]:
        img, word = it.get("image"), it.get("answer")
        if not img or not word or word in seen:
            continue
        seen.add(word)
        pairs.append((word, img, it.get("emoji", "")))
    for img, word, emoji in EXTRA_PAIRS:
        if word not in seen:
            seen.add(word)
            pairs.append((word, img, emoji))
    return pairs


def pick_distractors(word, pool, n):
    """n дистракторов: другие слова без совпадения первой буквы и рифмы.
    Детерминированно (порядок пула + хэш слова), без рандома."""
    def ok(other):
        return (other != word
                and other[0].lower() != word[0].lower()      # не та же первая буква
                and other[-2:].lower() != word[-2:].lower())  # не рифма
    cands = [w for w in pool if ok(w)]
    if len(cands) < n:  # запас, если фильтр слишком строгий
        cands = [w for w in pool if w != word]
    start = sum(map(ord, word)) % max(1, len(cands))
    rotated = cands[start:] + cands[:start]
    return rotated[:n]


def main():
    pairs = collect_pairs()
    words = [w for w, _, _ in pairs]
    missing = [img for _, img, _ in pairs
               if not os.path.exists(os.path.join(IMG_DIR, img))]
    if missing:
        raise SystemExit(f"Нет файлов картинок: {missing}")

    items = []
    for i, (word, img, emoji) in enumerate(pairs, 1):
        distractors = pick_distractors(word, words, OPTIONS_PER_ITEM - 1)
        items.append({
            "id": f"pw_{i:03d}",
            "level": 0,
            "answer": word,
            "image": img,
            "options": [word] + distractors,  # верный первым; виджет перемешает
            "emoji": emoji,
        })

    doc = {
        "type": "picture_word",
        "title": "Покажите, как это называется",
        "section": "0. Узнавание",
        "draft": True,  # на валидацию логопедом
        "count": len(items),
        "items": items,
    }
    payload = json.dumps(doc, ensure_ascii=False, indent=2)
    open(OUT_SRC, "w", encoding="utf-8").write(payload + "\n")
    open(OUT_ASSET, "w", encoding="utf-8").write(payload + "\n")
    print(f"picture_word: {len(items)} заданий → {OUT_SRC} и {OUT_ASSET}")


if __name__ == "__main__":
    main()
