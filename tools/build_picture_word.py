#!/usr/bin/env python3
"""Генератор набора picture_word (этаж L0 «картинка→слово»).

L0 — до-вербальный пол лестницы: показать картинку и 2 дистрактора, спросить
«как это называется?». Узнавание, не воспроизведение (THEORY ч.6, грубая форма).

Источник слов — пары «картинка→слово», уже валидированные логопедом
(одобренные картинки в fill_letter). Дистракторы берутся из того же пула,
без совпадения первой буквы и рифмы — чтобы опора была на смысл, не на форму.

ЧЕРНОВИК: набор требует валидации логопедом (см. content/README.md).

Как добавить картинки позже:
  1) положить файл в content/img/<file>.png;
  2) либо привязать его к слову в fill_letter (поле "image"),
     либо дописать пару в EXTRA_PAIRS ниже;
  3) перезапустить: python3 tools/build_picture_word.py
"""
import json
import os
import re

from translit import slugify

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILL_LETTER = os.path.join(ROOT, "content", "json", "17_fill_letter.json")
# Решения ревью дистракторов логопедом: id -> {approved, comment}.
# comment = два слова-замены дистрактора (через «/» или пробел); approved:false — убрать.
DECISIONS = os.path.join(ROOT, "content", "picture-word-decisions.json")
# Ревью картинок расширенного пула логопедом: слово -> {approved, comment}.
# Слово берём в задания, только если оно НЕ отклонено (одобрено / переименовано
# по комментарию / вообще не попало в ревью = старая валидация).
POOL_DECISIONS = os.path.join(ROOT, "content", "picture-pool-decisions.json")
IMG_DIR = os.path.join(ROOT, "content", "img")
POOL = os.path.join(ROOT, "content", "picture_pool.json")
OUT_SRC = os.path.join(ROOT, "content", "json", "22_picture_word.json")

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
    # расширенный пул простых предметов: берём слово только если картинка уже
    # скачана (fetch_arasaac.py) И не отклонена логопедом (picture-pool-decisions)
    pooldec = {}
    if os.path.exists(POOL_DECISIONS):
        pooldec = json.load(open(POOL_DECISIONS, encoding="utf-8"))
    skipped = rejected = 0
    if os.path.exists(POOL):
        for e in json.load(open(POOL, encoding="utf-8")).get("words", []):
            word = (e.get("ru") or "").strip()
            if not word or word in seen:
                continue
            dec = pooldec.get(word)
            if dec is not None and dec.get("approved") is not True:
                rejected += 1  # отклонено на ревью картинок
                continue
            img = slugify(word) + ".png"
            if not os.path.exists(os.path.join(IMG_DIR, img)):
                skipped += 1
                continue
            seen.add(word)
            pairs.append((word, img, e.get("emoji", "")))
    if skipped:
        print(f"  пул: пропущено {skipped} слов без скачанной картинки")
    if rejected:
        print(f"  пул: отклонено логопедом {rejected} слов")
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


def load_decisions():
    """Решения логопеда по дистракторам. comment → два слова-замены."""
    if not os.path.exists(DECISIONS):
        return {}
    return json.load(open(DECISIONS, encoding="utf-8"))


def main():
    pairs = collect_pairs()
    words = [w for w, _, _ in pairs]
    missing = [img for _, img, _ in pairs
               if not os.path.exists(os.path.join(IMG_DIR, img))]
    if missing:
        raise SystemExit(f"Нет файлов картинок: {missing}")

    decisions = load_decisions()
    items, dropped, overridden = [], [], 0
    for i, (word, img, emoji) in enumerate(pairs, 1):
        pid = f"pw_{i:03d}"
        dec = decisions.get(pid, {})
        if dec.get("approved") is False:  # отклонено логопедом — убираем
            dropped.append(pid)
            continue
        comment = (dec.get("comment") or "").strip()
        if comment:  # логопед предложил замену дистракторов: два слова
            repl = [w for w in re.split(r"[/\s]+", comment) if w]
            if len(repl) == OPTIONS_PER_ITEM - 1:
                distractors = repl
                overridden += 1
            else:
                raise SystemExit(
                    f"{pid}: в комментарии ожидалось {OPTIONS_PER_ITEM - 1} слова, "
                    f"получено {len(repl)}: {repl}")
        else:  # авто-дистракторы (одобрено как есть или без решения)
            distractors = pick_distractors(word, words, OPTIONS_PER_ITEM - 1)
        items.append({
            "id": pid,
            "level": 0,
            "answer": word,
            "image": img,
            "options": [word] + distractors,  # верный первым; виджет перемешает
            "emoji": emoji,
        })

    # черновик, пока есть задания без решения логопеда. Задание «решено», если:
    #  — отсмотрены дистракторы (picture-word-decisions: одобрено/замена), ИЛИ
    #  — одобрена картинка слова на ревью пула (picture-pool-decisions) — тогда
    #    доверяем авто-дистракторам (без совпадения первой буквы и рифмы).
    pooldec = {}
    if os.path.exists(POOL_DECISIONS):
        pooldec = json.load(open(POOL_DECISIONS, encoding="utf-8"))

    def decided(it):
        d = decisions.get(it["id"], {})
        if d.get("approved") is True or bool((d.get("comment") or "").strip()):
            return True
        return pooldec.get(it["answer"], {}).get("approved") is True
    is_draft = any(not decided(it) for it in items)

    doc = {
        "type": "picture_word",
        "title": "Покажите, как это называется",
        "section": "0. Узнавание",
        "draft": is_draft,  # True пока не все задания отсмотрены логопедом
        "count": len(items),
        "items": items,
    }
    payload = json.dumps(doc, ensure_ascii=False, indent=2)
    open(OUT_SRC, "w", encoding="utf-8").write(payload + "\n")
    print(f"picture_word: {len(items)} заданий "
          f"(замен дистракторов: {overridden}, убрано: {len(dropped)})")
    print(f"  → {OUT_SRC} (ассет соберёт tools/build_assets.py)")


if __name__ == "__main__":
    main()
