#!/usr/bin/env python3
"""Офлайн-страница ревью ТОЛЬКО НОВЫХ картинок: tools/picture_pool_review.html.

По той же схеме, что build_picture_review.py (картинка + слово, 2 кнопки
«Подходит?», комментарий, экспорт picture-pool-decisions.json), но источник —
картинки из расширенного пула (content/picture_pool.json) и fill_letter,
скачанные fetch_arasaac.py. Чтобы не пересматривать уже валидированное,
показываем только НОВЫЕ файлы content/img/*.png (untracked в git) — ранее
закоммиченные 63 картинки считаются прошедшими валидацию и пропускаются.

Решения копятся в localStorage + «Сохранить файл» выгружает
picture-pool-decisions.json (слово -> {approved, comment}). «Не одобрено = отклонено».

Запуск:  python3 tools/build_picture_pool_review.py
"""
import base64
import json
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
IMGDIR = os.path.join(ROOT, "content", "img")
POOL = os.path.join(ROOT, "content", "picture_pool.json")
OUT = os.path.join(HERE, "picture_pool_review.html")


def new_images():
    """Имена новых (untracked в git) png в content/img/."""
    out = subprocess.run(
        ["git", "status", "--porcelain", "content/img/"],
        cwd=ROOT, capture_output=True, text=True).stdout
    names = set()
    for line in out.splitlines():
        if line.startswith("??") and line.strip().endswith(".png"):
            names.add(os.path.basename(line[2:].strip()))
    return names


def load_data():
    manifest = {}
    mpath = os.path.join(IMGDIR, "MANIFEST.json")
    if os.path.exists(mpath):
        manifest = json.load(open(mpath, encoding="utf-8"))
    slug2meta = {m["slug"]: dict(m, word=w) for w, m in manifest.items()}
    pool = {e["ru"]: e for e in
            json.load(open(POOL, encoding="utf-8")).get("words", [])}

    fresh = new_images()
    cards = []
    for fname in sorted(fresh):
        fpath = os.path.join(IMGDIR, fname)
        if not os.path.exists(fpath):
            continue
        slug = fname[:-4]
        meta = slug2meta.get(slug, {})
        word = meta.get("word", slug)
        b64 = base64.b64encode(open(fpath, "rb").read()).decode("ascii")
        cards.append({
            "id": word,
            "word": word,
            "theme": pool.get(word, {}).get("theme", ""),
            "matches": meta.get("matches"),
            "query": meta.get("query", ""),
            "img": "data:image/png;base64," + b64,
        })
    return cards


TEMPLATE = r"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ревью новых картинок — speech-rehab</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, system-ui, sans-serif; margin: 0;
         background: #f4f5f4; color: #1a1a1a; font-size: 18px; }
  header { position: sticky; top: 0; z-index: 10; background: #1565c0; color: #fff;
           padding: 12px 18px; display: flex; gap: 14px; align-items: center;
           flex-wrap: wrap; box-shadow: 0 2px 8px rgba(0,0,0,.2); }
  header strong { font-size: 20px; }
  header .stats { font-size: 16px; opacity: .95; }
  header button, header label.imp {
    font-size: 16px; padding: 8px 12px; border-radius: 8px; border: none;
    cursor: pointer; background: #fff; color: #1565c0; font-weight: 600; }
  main { max-width: 1040px; margin: 0 auto; padding: 18px;
         display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
         gap: 14px; }
  .card { background: #fff; border-radius: 12px; padding: 14px; border: 2px solid #e3e3e0;
          display: flex; flex-direction: column; }
  .card.ok { border-color: #2e7d32; background: #f3fbf3; }
  .card.bad { border-color: #c62828; background: #fdf3f3; }
  .card img { width: 100%; height: 170px; object-fit: contain; background: #fff; }
  .word { font-size: 24px; font-weight: 700; margin-top: 8px; }
  .theme { font-size: 14px; color: #1565c0; }
  .meta { font-size: 12px; color: #999; margin-top: 4px; }
  .meta.warn { color: #b26a00; font-weight: 600; }
  .appr { font-size: 16px; font-weight: 700; padding: 9px; border-radius: 9px;
          border: 2px solid #2e7d32; background: #fff; color: #2e7d32; cursor: pointer;
          margin-top: 10px; }
  .appr.on { background: #2e7d32; color: #fff; }
  textarea { font-size: 15px; padding: 7px 9px; border-radius: 8px; border: 1px solid #ccc;
             resize: vertical; min-height: 38px; font-family: inherit; margin-top: 8px; }
</style></head><body>
<header>
  <strong>Ревью новых картинок</strong>
  <span class="stats" id="stats"></span>
  <button id="onlyWarn">⚠ Только многозначные</button>
  <button id="exportBtn">💾 Сохранить файл</button>
  <label class="imp">📂 Загрузить<input id="importFile" type="file" accept="application/json" hidden></label>
</header>
<main id="list"></main>
<script>
const DATA = __DATA__;
const TOTAL = DATA.length;
const KEY = 'speech_picpoolreview_v1';
let dec = {};
try { dec = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch(e) { dec = {}; }
let warnOnly = false;

function save() { localStorage.setItem(KEY, JSON.stringify(dec)); stats(); }
function el(t, c) { const e = document.createElement(t); if (c) e.className = c; return e; }

function renderCard(d) {
  const card = el('div', 'card');
  const st = dec[d.id] || {};
  if (st.approved === true) card.classList.add('ok');
  if (st.approved === false) card.classList.add('bad');
  const im = el('img'); im.src = d.img; im.alt = d.word;
  const w = el('div', 'word'); w.textContent = d.word;
  const th = el('div', 'theme'); th.textContent = d.theme || '';
  const m = el('div', 'meta' + (d.matches > 6 ? ' warn' : ''));
  m.textContent = (d.query || '') + (d.matches != null ? ' · ' + d.matches + ' совп.' : '');
  card.append(im, w, th, m);
  const btn = el('button', 'appr');
  const setBtn = () => {
    const on = (dec[d.id] || {}).approved === true;
    btn.textContent = on ? '✓ Подходит' : 'Подходит?';
    btn.classList.toggle('on', on);
    card.classList.toggle('ok', on);
    card.classList.toggle('bad', (dec[d.id] || {}).approved === false);
  };
  // три состояния по клику: нет → одобрено → отклонено → нет
  btn.onclick = () => {
    dec[d.id] = dec[d.id] || {};
    const cur = dec[d.id].approved;
    dec[d.id].approved = (cur === undefined) ? true : (cur === true ? false : undefined);
    if (dec[d.id].approved === undefined) delete dec[d.id].approved;
    setBtn(); save();
  };
  setBtn();
  const ta = el('textarea');
  ta.placeholder = 'Комментарий / чем заменить';
  ta.value = st.comment || '';
  ta.oninput = () => { dec[d.id] = dec[d.id] || {}; dec[d.id].comment = ta.value; save(); };
  card.append(btn, ta);
  return card;
}

function render() {
  const list = document.getElementById('list');
  list.innerHTML = '';
  DATA.forEach(d => { if (!warnOnly || d.matches > 6) list.append(renderCard(d)); });
  window.scrollTo(0, 0);
}

function stats() {
  let ok = 0, bad = 0, com = 0;
  Object.values(dec).forEach(v => {
    if (v.approved === true) ok++;
    if (v.approved === false) bad++;
    if (v.comment && v.comment.trim()) com++;
  });
  document.getElementById('stats').textContent =
    'подходит ' + ok + ' · отклонено ' + bad + ' / ' + TOTAL + ' · коммент. ' + com;
}

document.getElementById('onlyWarn').onclick = () => { warnOnly = !warnOnly; render(); };
document.getElementById('exportBtn').onclick = () => {
  const blob = new Blob([JSON.stringify(dec, null, 2)], { type: 'application/json' });
  const a = el('a'); a.href = URL.createObjectURL(blob);
  a.download = 'picture-pool-decisions.json'; a.click();
};
document.getElementById('importFile').onchange = (ev) => {
  const f = ev.target.files[0]; if (!f) return;
  const r = new FileReader();
  r.onload = () => {
    try {
      const loaded = JSON.parse(r.result);
      Object.keys(loaded).forEach(k => { dec[k] = Object.assign(dec[k] || {}, loaded[k]); });
      save(); render();
      alert('Загружено решений: ' + Object.keys(loaded).length);
    } catch (e) { alert('Не удалось прочитать файл: ' + e); }
  };
  r.readAsText(f);
};

render();
stats();
</script></body></html>
"""


def main():
    cards = load_data()
    html = TEMPLATE.replace("__DATA__", json.dumps(cards, ensure_ascii=False))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    size_mb = os.path.getsize(OUT) / 1e6
    print(f"Готово: {OUT}  ({size_mb:.1f} МБ, {len(cards)} новых картинок)")
    print("Открой tools/picture_pool_review.html двойным кликом в браузере.")


if __name__ == "__main__":
    main()
