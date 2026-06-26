#!/usr/bin/env python3
"""Собирает вшитый офлайн-снимок контента app/assets/content/ из источника content/.

Единственный источник правды — content/ (index.json + json/*.json + img/*).
app/assets/content/ — ПРОИЗВОДНАЯ копия (офлайн-фолбэк в APK/web), в git не хранится,
генерируется здесь и в CI перед flutter build. Раскладка плоская: загрузчик
ContentRepository читает assets/content/index.json и assets/content/<basename>.

    python3 tools/build_assets.py

Идемпотентно: app/assets/content полностью пересобирается с нуля. Нужен Python 3."""
import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "content")
DEST = os.path.join(ROOT, "app", "assets", "content")


def main():
    index_path = os.path.join(SRC, "index.json")
    index = json.load(open(index_path, encoding="utf-8"))

    # Чистая пересборка снимка.
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)
    os.makedirs(DEST)

    # index.json (плоско в корень снимка).
    shutil.copy2(index_path, os.path.join(DEST, "index.json"))

    # Наборы заданий: json/NN_*.json -> плоско NN_*.json (загрузчик берёт basename).
    copied = 0
    for t in index["types"]:
        rel = t.get("file", "")
        if not rel:
            continue
        base = os.path.basename(rel)
        src_file = os.path.join(SRC, rel)
        if not os.path.exists(src_file):
            raise FileNotFoundError(f"в index.json есть {rel}, но файла нет: {src_file}")
        shutil.copy2(src_file, os.path.join(DEST, base))
        copied += 1

    # Картинки: content/img -> app/assets/content/img (целиком).
    src_img = os.path.join(SRC, "img")
    imgs = 0
    if os.path.isdir(src_img):
        dest_img = os.path.join(DEST, "img")
        shutil.copytree(src_img, dest_img)
        imgs = sum(1 for f in os.listdir(dest_img) if f.lower().endswith(".png"))

    print(f"build_assets: index + {copied} наборов + {imgs} картинок -> {DEST}")


if __name__ == "__main__":
    main()
