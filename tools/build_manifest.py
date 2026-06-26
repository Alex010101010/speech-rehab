#!/usr/bin/env python3
"""Генерит manifest.json для OTA-доставки контента (Фаза 0).

Манифест — контракт между ботом (издателем) и приложением (потребителем).
Приложение сравнит content_version с локальной, проверит гейт min_app_version
и по списку files с sha256 скачает только изменённое (атомарно, Фаза 2).

    python3 tools/build_manifest.py <dir>

<dir> — плоский каталог OTA-нагрузки (index.json + NN_*.json + img/*.png).
По умолчанию app/assets/content. manifest.json пишется в этот же каталог.

content_version и min_app_version берутся из index.json. Пути в files —
относительно <dir> (приложение качает <base_url>/<path>). Нужен Python 3."""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
DEFAULT_DIR = os.path.join(ROOT, "app", "assets", "content")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def collect(root):
    """Файлы, которые приложение реально тянет: index.json, NN_*.json, img/*.png."""
    files = []
    for name in sorted(os.listdir(root)):
        if name.endswith(".json") and name != "manifest.json":
            files.append(name)
    img = os.path.join(root, "img")
    if os.path.isdir(img):
        for name in sorted(os.listdir(img)):
            if name.lower().endswith(".png"):
                files.append(f"img/{name}")
    return files


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DIR
    index = json.load(open(os.path.join(target, "index.json"), encoding="utf-8"))
    if "content_version" not in index or "min_app_version" not in index:
        raise KeyError("в index.json нужны поля content_version и min_app_version")

    entries = []
    for rel in collect(target):
        full = os.path.join(target, rel)
        entries.append({
            "path": rel,
            "sha256": sha256(full),
            "size": os.path.getsize(full),
        })

    manifest = {
        "pack": index.get("pack"),
        "content_version": index["content_version"],
        "min_app_version": index["min_app_version"],
        "files": entries,
    }
    out = os.path.join(target, "manifest.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"build_manifest: v{manifest['content_version']} "
          f"(min_app {manifest['min_app_version']}), {len(entries)} файлов -> {out}")


if __name__ == "__main__":
    main()
