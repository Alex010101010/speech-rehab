#!/usr/bin/env python3
"""Генерирует офлайн-страницу ревью всех заданий: tools/review.html
(самодостаточный HTML, весь контент внутри, работает без интернета).

На странице: каждое задание показано, кнопка «Одобрить», поле комментария.
Решения копятся в localStorage браузера + «Сохранить файл» выгружает
review-decisions.json (id -> {approved, comment}) — его потом применит бот.
«Загрузить» позволяет продолжить с ранее сохранённого файла.

Запуск:  python3 tools/build_review.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "content", "json")
INDEX = os.path.join(ROOT, "content", "index.json")
OUT = os.path.join(HERE, "review.html")


def load_data():
    idx = json.load(open(INDEX, encoding="utf-8"))
    groups = []
    total = 0
    for e in idx["types"]:
        fname = os.path.basename(e.get("file", ""))
        fpath = os.path.join(SRC, fname)
        if not os.path.exists(fpath):
            continue
        items = json.load(open(fpath, encoding="utf-8")).get("items", [])
        total += len(items)
        groups.append({
            "type": e["type"],
            "title": e.get("title", e["type"]),
            "section": e.get("section", ""),
            "advanced": bool(e.get("advanced")),
            "items": items,
        })
    return groups, total


TEMPLATE = r"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ревью заданий — speech-rehab</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, system-ui, sans-serif; margin: 0;
         background: #f4f5f4; color: #1a1a1a; font-size: 18px; }
  header { position: sticky; top: 0; z-index: 10; background: #1565c0; color: #fff;
           padding: 12px 18px; display: flex; gap: 14px; align-items: center;
           flex-wrap: wrap; box-shadow: 0 2px 8px rgba(0,0,0,.2); }
  header strong { font-size: 20px; }
  header .stats { font-size: 16px; opacity: .95; }
  header select, header button, header label.imp {
    font-size: 16px; padding: 8px 12px; border-radius: 8px; border: none;
    cursor: pointer; background: #fff; color: #1565c0; font-weight: 600; }
  main { max-width: 920px; margin: 0 auto; padding: 18px; }
  h2.sec { margin: 28px 0 10px; font-size: 22px; }
  h2.sec .adv { font-size: 14px; color: #b26a00; background: #fff3e0;
    padding: 2px 8px; border-radius: 6px; margin-left: 8px; }
  .card { background: #fff; border-radius: 12px; padding: 16px 18px; margin: 12px 0;
          border: 2px solid #e3e3e0; }
  .card.ok { border-color: #2e7d32; background: #f3fbf3; }
  .hd { display: flex; gap: 8px; align-items: center; flex-wrap: wrap;
        margin-bottom: 10px; }
  .badge { font-size: 13px; padding: 2px 9px; border-radius: 20px;
           background: #eef1f5; color: #444; }
  .badge.id { margin-left: auto; color: #999; background: none; }
  .fld { margin: 6px 0; line-height: 1.4; }
  .fld .lbl { font-size: 13px; color: #888; text-transform: uppercase;
              letter-spacing: .03em; }
  .fld .val { font-size: 19px; }
  .ctl { display: flex; gap: 12px; align-items: flex-start; margin-top: 14px;
         border-top: 1px dashed #ddd; padding-top: 12px; }
  .appr { font-size: 17px; font-weight: 700; padding: 10px 18px; border-radius: 10px;
          border: 2px solid #2e7d32; background: #fff; color: #2e7d32; cursor: pointer;
          white-space: nowrap; }
  .appr.on { background: #2e7d32; color: #fff; }
  .ctl textarea { flex: 1; font-size: 16px; padding: 8px 10px; border-radius: 8px;
                  border: 1px solid #ccc; resize: vertical; min-height: 44px;
                  font-family: inherit; }
</style></head><body>
<header>
  <strong>Ревью заданий</strong>
  <span class="stats" id="stats"></span>
  <select id="filter"></select>
  <button id="exportBtn">💾 Сохранить файл</button>
  <label class="imp">📂 Загрузить<input id="importFile" type="file" accept="application/json" hidden></label>
</header>
<main id="list"></main>
<script>
const DATA = __DATA__;
const TOTAL = __TOTAL__;
const KEY = 'speech_review_v1';
let dec = {};
try { dec = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch(e) { dec = {}; }

function save() { localStorage.setItem(KEY, JSON.stringify(dec)); stats(); }
function el(t, c) { const e = document.createElement(t); if (c) e.className = c; return e; }
function fld(lbl, val) {
  const d = el('div', 'fld');
  const l = el('div', 'lbl'); l.textContent = lbl;
  const v = el('div', 'val'); v.textContent = val;
  d.append(l, v); return d;
}
function badge(text, cls) { const b = el('span', 'badge' + (cls ? ' ' + cls : '')); b.textContent = text; return b; }

function renderItem(it, type) {
  const card = el('div', 'card');
  card.dataset.id = it.id;
  if (dec[it.id] && dec[it.id].approved) card.classList.add('ok');
  const hd = el('div', 'hd');
  hd.append(badge(type), badge('L' + (it.level || 1)));
  if (it.theme) hd.append(badge(it.theme));
  hd.append(badge(it.id, 'id'));
  card.append(hd);
  if (it.prompt) card.append(fld('Задание', it.prompt));
  if (it.task) card.append(fld('Тип', it.task));
  if (Array.isArray(it.options)) card.append(fld('Варианты', it.options.join('   |   ')));
  if (it.answer) card.append(fld('Ответ', it.answer));
  if (Array.isArray(it.syllables)) card.append(fld('Слоги', it.syllables.join(' · ')));
  if (it.word) card.append(fld('Слово', it.word + (it.match === true ? '  →  Да (совпадает)' : it.match === false ? '  →  Нет (не совпадает)' : '')));
  if (it.image) {
    const wrap = el('div', 'fld');
    const l = el('div', 'lbl'); l.textContent = 'Картинка';
    const img = el('img'); img.src = '../content/img/' + it.image; img.alt = it.image;
    img.style.maxHeight = '160px'; img.style.maxWidth = '100%'; img.style.borderRadius = '8px';
    // если файла нет — показать имя текстом вместо битой картинки
    img.onerror = () => { const v = el('div', 'val'); v.textContent = it.image + ' (нет файла)'; img.replaceWith(v); };
    wrap.append(l, img); card.append(wrap);
  }
  if (Array.isArray(it.accept) && it.accept.length) card.append(fld('Также принимается', it.accept.join(', ')));
  if (Array.isArray(it.display)) card.append(fld('Ряд', it.display.join('   ·   ')));
  else if (Array.isArray(it.row)) card.append(fld('Ряд', it.row.join('   ·   ')));
  if (it.title) card.append(fld('Заголовок', it.title));
  if (it.text) card.append(fld('Текст', it.text));
  if (Array.isArray(it.questions)) it.questions.forEach((q, i) =>
    card.append(fld('Вопрос ' + (i + 1), (q.q || '') + '  →  ' + (q.a || ''))));
  const ctl = el('div', 'ctl');
  const btn = el('button', 'appr');
  const setBtn = () => {
    const on = dec[it.id] && dec[it.id].approved;
    btn.textContent = on ? '✓ Одобрено' : 'Одобрить';
    btn.classList.toggle('on', !!on);
    card.classList.toggle('ok', !!on);
  };
  btn.onclick = () => {
    dec[it.id] = dec[it.id] || {};
    dec[it.id].approved = !dec[it.id].approved;
    setBtn(); save();
  };
  setBtn();
  const ta = el('textarea');
  ta.placeholder = 'Комментарий (необязательно)';
  ta.value = (dec[it.id] && dec[it.id].comment) || '';
  ta.oninput = () => { dec[it.id] = dec[it.id] || {}; dec[it.id].comment = ta.value; save(); };
  ctl.append(btn, ta);
  card.append(ctl);
  return card;
}

function render(filterType) {
  const list = document.getElementById('list');
  list.innerHTML = '';
  DATA.forEach(g => {
    if (filterType && filterType !== g.type) return;
    const h = el('h2', 'sec');
    h.textContent = g.title;
    if (g.advanced) { const a = el('span', 'adv'); a.textContent = 'advanced'; h.append(a); }
    list.append(h);
    g.items.forEach(it => list.append(renderItem(it, g.type)));
  });
  window.scrollTo(0, 0);
}

function stats() {
  let appr = 0, com = 0;
  Object.values(dec).forEach(d => { if (d.approved) appr++; if (d.comment && d.comment.trim()) com++; });
  document.getElementById('stats').textContent =
    'одобрено ' + appr + ' / ' + TOTAL + ' · с комментарием ' + com;
}

// фильтр по типу
const sel = document.getElementById('filter');
const optAll = el('option'); optAll.value = ''; optAll.textContent = 'Все типы (' + TOTAL + ')';
sel.append(optAll);
DATA.forEach(g => { const o = el('option'); o.value = g.type; o.textContent = g.title + ' (' + g.items.length + ')'; sel.append(o); });
sel.onchange = () => render(sel.value);

// экспорт / импорт
document.getElementById('exportBtn').onclick = () => {
  const blob = new Blob([JSON.stringify(dec, null, 2)], { type: 'application/json' });
  const a = el('a'); a.href = URL.createObjectURL(blob);
  a.download = 'review-decisions.json'; a.click();
};
document.getElementById('importFile').onchange = (ev) => {
  const f = ev.target.files[0]; if (!f) return;
  const r = new FileReader();
  r.onload = () => {
    try {
      const loaded = JSON.parse(r.result);
      Object.keys(loaded).forEach(k => { dec[k] = Object.assign(dec[k] || {}, loaded[k]); });
      save(); render(sel.value);
      alert('Загружено решений: ' + Object.keys(loaded).length);
    } catch (e) { alert('Не удалось прочитать файл: ' + e); }
  };
  r.readAsText(f);
};

render('');
stats();
</script></body></html>
"""


def main():
    groups, total = load_data()
    html = (TEMPLATE
            .replace("__DATA__", json.dumps(groups, ensure_ascii=False))
            .replace("__TOTAL__", str(total)))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Готово: {OUT}")
    print(f"Заданий: {total} в {len(groups)} типах")
    print("Открой tools/review.html двойным кликом в браузере.")


if __name__ == "__main__":
    main()
