#!/usr/bin/env python3
"""Скачивает пиктограммы ARASAAC (CC BY-NC-SA) для слов-ответов из
17_fill_letter.json в app/assets/content/img/<slug>.png.

База ARASAAC по сути англоязычная: русское покрытие неполное. Поэтому
ищем по АНГЛИЙСКОМУ переводу (endpoint /en/) из словаря WORDS_EN —
заодно точный термин снимает омонимы (коса→scythe, ручка→pen). Имя файла
— транслит русского слова (стабильный slug). Берётся первый результат —
после загрузки проверь картинки глазами.

    python3 tools/fetch_arasaac.py

Пишет манифест img/MANIFEST.json и ATTRIBUTION.md. Перезапуск безопасен.
Нужен только стандартный Python 3."""
import json
import os
import time
import urllib.parse
import urllib.request

TIMEOUT = 40
RETRIES = 3
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(ROOT, "app", "assets", "content", "img")
FILL = os.path.join(ROOT, "content", "json", "17_fill_letter.json")

# русское слово -> английский запрос для поиска в ARASAAC (точный смысл)
WORDS_EN = {
    "дуб": "oak", "трава": "grass", "дорога": "road", "тетерев": "grouse",
    "дятел": "woodpecker", "телефон": "telephone", "диван": "sofa",
    "тарелка": "plate", "деньги": "money", "труба": "pipe",
    "деталь": "spare part", "электрод": "electrode", "удочка": "fishing rod",
    "дно": "seabed", "листья": "leaves", "почта": "mail", "булка": "bun",
    "пальто": "coat", "полотенце": "towel", "паспорт": "passport",
    "бутылка": "bottle", "помидор": "tomato", "берёза": "birch tree",
    "паук": "spider", "поплавок": "float", "рыбалка": "fishing",
    "берег": "shore", "баллон": "gas cylinder", "перчатки": "gloves",
    "бутерброд": "sandwich", "грибы": "mushrooms", "клён": "maple tree",
    "горох": "peas", "корова": "cow", "колбаса": "sausage",
    "картофель": "potato", "капуста": "cabbage", "газета": "newspaper",
    "кастрюля": "saucepan", "куртка": "jacket", "кабель": "cable",
    "искра": "spark", "крючок": "fishing hook", "коряга": "log",
    "камыш": "reed", "лес": "forest", "небо": "sky", "луна": "moon",
    "нора": "den", "листва": "leaf", "лампа": "lamp", "нож": "knife",
    "ложка": "spoon", "нитки": "thread", "лодка": "boat", "наживка": "bait",
    "лещ": "bream", "металл": "metal", "осень": "autumn", "солнце": "sun",
    "суп": "soup", "зеркало": "mirror", "соль": "salt", "зонт": "umbrella",
    "стол": "table", "заяц": "hare", "сосна": "pine tree",
    "звери": "wild animals", "роса": "dew", "сеть": "fishing net",
    "озеро": "lake", "сварка": "welding", "мороз": "frost", "глаз": "eye",
    "жук": "beetle", "шишка": "pine cone", "жёлудь": "acorn",
    "шкаф": "wardrobe", "ножницы": "scissors", "шапка": "hat",
    "щука": "pike", "шарф": "scarf", "часы": "clock", "чайник": "kettle",
    "чемодан": "suitcase", "цемент": "cement", "улица": "street",
    "ручка": "pen", "цапля": "heron", "овца": "sheep", "черепаха": "turtle",
    "чайка": "seagull", "огурец": "cucumber", "рецепт": "prescription",
    # без точного перевода/омонимичны — пробуем по-русски (часто без картинки):
    # заготовка, ёрш, железо
}

_TR = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya', ' ': '_',
}


def slugify(word):
    return ''.join(_TR.get(ch, '') for ch in word.lower()).strip('_')


def _open(url, retries=RETRIES):
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "speech-rehab"})
            return urllib.request.urlopen(req, timeout=TIMEOUT)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise  # нет такого ресурса — ретрай не поможет
            last = e
            if i + 1 < retries:
                time.sleep(2 * (i + 1))
        except Exception as e:  # noqa
            last = e
            if i + 1 < retries:
                time.sleep(2 * (i + 1))
    raise last


def search(word):
    """Ищем по англ. переводу (база англоязычная), иначе по русскому слову.
    Возвращает (результаты, язык_запроса, текст_запроса)."""
    en = WORDS_EN.get(word)
    lang, q = ("en", en) if en else ("ru", word)
    url = (f"https://api.arasaac.org/api/pictograms/{lang}/search/"
           + urllib.parse.quote(q))
    try:
        with _open(url) as r:
            return json.load(r), lang, q
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return [], lang, q
        raise


def download(url, dst):
    with _open(url) as r, open(dst, "wb") as f:
        f.write(r.read())


def main():
    os.makedirs(OUT, exist_ok=True)
    d = json.load(open(FILL, encoding="utf-8"))
    words = []
    for it in d["items"]:
        ans = (it.get("answer") or "").strip()
        if ans and ans not in words:
            words.append(ans)
    print(f"слов-ответов: {len(words)}\n")

    # идемпотентность: подхватываем прошлый манифест, пропускаем уже скачанное
    mpath = os.path.join(OUT, "MANIFEST.json")
    manifest = {}
    if os.path.exists(mpath):
        try:
            manifest = json.load(open(mpath, encoding="utf-8"))
        except Exception:  # noqa
            manifest = {}
    manifest = {w: m for w, m in manifest.items()
                if os.path.exists(os.path.join(OUT, m["slug"] + ".png"))}

    miss = []
    for word in words:
        slug = slugify(word)
        if word in manifest:
            continue  # уже есть картинка
        try:
            res, lang, q = search(word)
            if not res:
                miss.append(word)
                print(f"нет пиктограммы: {word} ({lang}:{q})")
                continue
            pid = res[0]["_id"]
            url = f"https://static.arasaac.org/pictograms/{pid}/{pid}_300.png"
            download(url, os.path.join(OUT, slug + ".png"))
            manifest[word] = {"slug": slug, "id": pid, "matches": len(res),
                              "query": f"{lang}:{q}"}
            flag = "  ⚠многозначно" if len(res) > 6 else ""
            print(f"ok: {word} ({lang}:{q}) -> {slug}.png (id {pid}, "
                  f"{len(res)} совпад.){flag}")
        except Exception as e:  # noqa
            miss.append(word)
            print("ошибка:", word, e)

    json.dump(manifest, open(os.path.join(OUT, "MANIFEST.json"), "w",
              encoding="utf-8"), ensure_ascii=False, indent=2)
    with open(os.path.join(OUT, "ATTRIBUTION.md"), "w", encoding="utf-8") as f:
        f.write("# Источник картинок\n\n")
        f.write("Пиктограммы ARASAAC (https://arasaac.org), автор Sergio Palao, "
                "лицензия CC BY-NC-SA. Используются в некоммерческом проекте.\n\n")
        f.write("| Слово | Файл | ARASAAC id |\n|---|---|---|\n")
        for w, m in sorted(manifest.items()):
            f.write(f"| {w} | {m['slug']}.png | {m['id']} |\n")
    print(f"\nГотово: {len(manifest)} скачано, {len(miss)} пропущено.")
    if miss:
        print("Пропущены:", ", ".join(miss))


if __name__ == "__main__":
    main()
