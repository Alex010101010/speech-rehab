#!/usr/bin/env python3
"""Скачивает пиктограммы ARASAAC (CC BY-NC-SA) для слов из WORDS в
app/assets/content/img/<slug>.png. Запускать в ОБЫЧНОМ терминале с интернетом:

    python3 tools/fetch_arasaac.py

Нужен только стандартный Python 3 (urllib). Перезапуск безопасен (перекачает).
Берётся первый результат поиска ARASAAC по русскому слову — после загрузки
проверь картинки глазами (бывает неточное совпадение)."""
import json
import os
import time
import urllib.parse
import urllib.request

TIMEOUT = 40
RETRIES = 3

# русское слово -> латинский slug (имя файла)
WORDS = {
    "тарелка": "tarelka",
    "телефон": "telefon",
    "диван": "divan",
    "труба": "truba",
    "помидор": "pomidor",
    "паук": "pauk",
    "пальто": "palto",
    "полотенце": "polotentse",
    "бутылка": "butylka",
    "трава": "trava",
    "дуб": "dub",
    "берёза": "bereza",
}

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "app", "assets", "content", "img")


def _open(url, retries=RETRIES):
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "speech-rehab"})
            return urllib.request.urlopen(req, timeout=TIMEOUT)
        except Exception as e:  # noqa
            last = e
            if i + 1 < retries:
                time.sleep(2 * (i + 1))
    raise last


def search_id(word):
    url = ("https://api.arasaac.org/api/pictograms/ru/search/"
           + urllib.parse.quote(word))
    with _open(url) as r:
        data = json.load(r)
    return data[0]["_id"] if data else None


def download(url, dst):
    with _open(url) as r, open(dst, "wb") as f:
        f.write(r.read())


def main():
    os.makedirs(OUT, exist_ok=True)
    # проба связи (без повторов): сразу видно, блокирует ли сеть
    try:
        with _open("https://api.arasaac.org/api/pictograms/ru/search/дом", 1):
            print("связь с ARASAAC: ок\n")
    except Exception as e:  # noqa
        print("НЕТ связи с ARASAAC:", e)
        print("Похоже, сеть блокирует сайт — сообщи, перейдём на эмодзи.")
        return
    ok, miss = {}, []
    for word, slug in WORDS.items():
        try:
            pid = search_id(word)
            if not pid:
                miss.append(word)
                print("нет пиктограммы:", word)
                continue
            img = f"https://static.arasaac.org/pictograms/{pid}/{pid}_500.png"
            dst = os.path.join(OUT, slug + ".png")
            download(img, dst)
            ok[slug] = pid
            print(f"ok: {word} -> {slug}.png (ARASAAC id {pid})")
        except Exception as e:  # noqa
            miss.append(word)
            print("ошибка:", word, e)
    # атрибуция (CC BY-NC-SA требует указания источника)
    attr = os.path.join(OUT, "ATTRIBUTION.md")
    with open(attr, "w", encoding="utf-8") as f:
        f.write("# Источник картинок\n\n")
        f.write("Пиктограммы ARASAAC (https://arasaac.org), автор Sergio Palao, "
                "лицензия CC BY-NC-SA. Используются в некоммерческом проекте.\n\n")
        f.write("| Файл | ARASAAC id |\n|---|---|\n")
        for slug, pid in sorted(ok.items()):
            f.write(f"| {slug}.png | {pid} |\n")
    print(f"\nГотово: {len(ok)} скачано, {len(miss)} пропущено.")
    if miss:
        print("Пропущены (нет/ошибка):", ", ".join(miss))


if __name__ == "__main__":
    main()
