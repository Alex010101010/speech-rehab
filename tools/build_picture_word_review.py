#!/usr/bin/env python3
"""Офлайн-страница ревью набора L0 «картинка→слово»: tools/picture_word_review.html
(самодостаточный HTML, картинки вшиты base64 — работает без интернета).

Соответствие картинка↔слово уже валидировано на ревью картинок
(picture-decisions.json). Здесь логопед проверяет ИМЕННО ДИСТРАКТОРЫ —
два неверных варианта: не оказался ли дистрактор тоже верным, не созвучен ли,
различимы ли три варианта по смыслу.

Карточка: картинка + правильное слово + 3 варианта как у пациента (верный
помечен) + id. Одобрить/отклонить (3 клика) + комментарий. Решения копятся в
localStorage; «Сохранить файл» → picture-word-decisions.json (id -> {approved,
comment}). «Загрузить» — продолжить.

Запуск:  python3 tools/build_picture_word_review.py
"""
import base64
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
PW = os.path.join(ROOT, "content", "json", "22_picture_word.json")
IMGDIR = os.path.join(ROOT, "content", "img")
OUT = os.path.join(HERE, "picture_word_review.html")


def load_data():
    items = json.load(open(PW, encoding="utf-8"))["items"]
    cards = []
    for it in items:
        img = it.get("image")
        fpath = os.path.join(IMGDIR, img) if img else ""
        if not img or not os.path.exists(fpath):
            continue
        b64 = base64.b64encode(open(fpath, "rb").read()).decode("ascii")
        cards.append({
            "id": it["id"],
            "answer": it.get("answer", ""),
            "options": it.get("options", []),
            "img": "data:image/png;base64," + b64,
        })
    return cards


TEMPLATE = r"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ревью L0: картинка→слово — speech-rehab</title>
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
         display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
         gap: 14px; }
  .card { background: #fff; border-radius: 12px; padding: 14px; border: 2px solid #e3e3e0;
          display: flex; flex-direction: column; }
  .card.ok { border-color: #2e7d32; background: #f3fbf3; }
  .card.bad { border-color: #c62828; background: #fdf3f3; }
  .card img { width: 100%; height: 170px; object-fit: contain; background: #fff; }
  .opts { margin-top: 10px; display: flex; flex-direction: column; gap: 6px; }
  .opt { font-size: 18px; padding: 8px 12px; border-radius: 9px; border: 2px solid #d6d6d2;
         background: #fafafa; }
  .opt.correct { border-color: #2e7d32; background: #eaf6ea; font-weight: 700; }
  .opt .tag { font-size: 13px; color: #2e7d32; font-weight: 700; margin-left: 6px; }
  .meta { font-size: 12px; color: #999; margin-top: 6px; }
  .appr { font-size: 16px; font-weight: 700; padding: 9px; border-radius: 9px;
          border: 2px solid #2e7d32; background: #fff; color: #2e7d32; cursor: pointer;
          margin-top: 10px; }
  .appr.on { background: #2e7d32; color: #fff; }
  textarea { font-size: 15px; padding: 7px 9px; border-radius: 8px; border: 1px solid #ccc;
             resize: vertical; min-height: 38px; font-family: inherit; margin-top: 8px; }
</style></head><body>
<header>
  <strong>Ревью L0: картинка→слово</strong>
  <span class="stats" id="stats"></span>
  <button id="onlyTodo">📋 Только неотсмотренные</button>
  <button id="exportBtn">💾 Сохранить файл</button>
  <label class="imp">📂 Загрузить<input id="importFile" type="file" accept="application/json" hidden></label>
</header>
<main id="list"></main>
<script>
const DATA = __DATA__;
const TOTAL = DATA.length;
const KEY = 'speech_pwreview_v1';
let dec = {};
try { dec = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch(e) { dec = {}; }
let todoOnly = false;

function save() { localStorage.setItem(KEY, JSON.stringify(dec)); stats(); }
function el(t, c) { const e = document.createElement(t); if (c) e.className = c; return e; }

function renderCard(d) {
  const card = el('div', 'card');
  const st = dec[d.id] || {};
  if (st.approved === true) card.classList.add('ok');
  if (st.approved === false) card.classList.add('bad');
  const im = el('img'); im.src = d.img; im.alt = d.answer;
  card.append(im);
  const opts = el('div', 'opts');
  d.options.forEach(o => {
    const isCorrect = o === d.answer;
    const row = el('div', 'opt' + (isCorrect ? ' correct' : ''));
    row.textContent = o;
    if (isCorrect) { const t = el('span', 'tag'); t.textContent = '✓ верно'; row.append(t); }
    opts.append(row);
  });
  card.append(opts);
  const m = el('div', 'meta'); m.textContent = d.id;
  card.append(m);
  const btn = el('button', 'appr');
  const setBtn = () => {
    const on = (dec[d.id] || {}).approved === true;
    btn.textContent = on ? '✓ Дистракторы ок' : 'Дистракторы ок?';
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
  ta.placeholder = 'Комментарий / чем заменить дистрактор';
  ta.value = st.comment || '';
  ta.oninput = () => { dec[d.id] = dec[d.id] || {}; dec[d.id].comment = ta.value; save(); };
  card.append(btn, ta);
  return card;
}

function render() {
  const list = document.getElementById('list');
  list.innerHTML = '';
  DATA.forEach(d => {
    const seen = (dec[d.id] || {}).approved !== undefined;
    if (!todoOnly || !seen) list.append(renderCard(d));
  });
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
    'ок ' + ok + ' · отклонено ' + bad + ' / ' + TOTAL + ' · коммент. ' + com;
}

document.getElementById('onlyTodo').onclick = () => { todoOnly = !todoOnly; render(); };
document.getElementById('exportBtn').onclick = () => {
  const blob = new Blob([JSON.stringify(dec, null, 2)], { type: 'application/json' });
  const a = el('a'); a.href = URL.createObjectURL(blob);
  a.download = 'picture-word-decisions.json'; a.click();
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
    print(f"Готово: {OUT}  ({size_mb:.1f} МБ, {len(cards)} заданий)")
    print("Открой tools/picture_word_review.html двойным кликом в браузере.")


if __name__ == "__main__":
    main()
