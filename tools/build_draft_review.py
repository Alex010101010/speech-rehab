#!/usr/bin/env python3
"""Офлайн-страница ревью ТОЛЬКО непросмотренных draft-заданий: tools/draft_review.html.

Показывает лишь то, по чему ещё нет решения в соответствующем <тип>-decisions.json
(уже одобренные/отклонённые/прокомментированные не показываются). Покрывает три
draft-набора: syllables (деление на слоги), word_order (предложение), match_pairs
(action/synonym; letter пропускается — наследует валидацию fill_letter).

Решения копятся в localStorage + «Сохранить файл» выгружает draft-decisions.json
(id -> {approved, comment}). Бот раскладывает его по <тип>-decisions.json по
префиксу id (sy_/wo_/mp_) и перегенерит наборы — draft снимается.

Запуск:  python3 tools/build_draft_review.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "content", "json")
OUT = os.path.join(HERE, "draft_review.html")

# (заголовок, json-файл, decisions-файл, фильтр по kind или None)
GROUPS = [
    ("Слоги (деление на слоги)", "23_syllables.json",
     "syllables-decisions.json", None),
    ("Соедините пары (action / synonym)", "25_match_pairs.json",
     "match_pairs-decisions.json", ("action", "synonym")),
    ("Соберите предложение", "27_word_order.json",
     "word_order-decisions.json", None),
]


def load_decisions(fname):
    p = os.path.join(ROOT, "content", fname)
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}


def is_pending(dec):
    """Нет решения = не одобрено/не отклонено и без комментария."""
    return not (dec.get("approved") in (True, False)
                or (dec.get("comment") or "").strip())


def load_groups():
    groups, total = [], 0
    for title, jf, df, kinds in GROUPS:
        items = json.load(open(os.path.join(SRC, jf), encoding="utf-8"))["items"]
        decisions = load_decisions(df)
        pending = []
        for it in items:
            if kinds and it.get("kind") not in kinds:
                continue
            if is_pending(decisions.get(it["id"], {})):
                pending.append(it)
        if pending:
            groups.append({"title": title, "items": pending})
        total += len(pending)
    return groups, total


TEMPLATE = r"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ревью черновиков — speech-rehab</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, system-ui, sans-serif; margin: 0;
         background: #f4f5f4; color: #1a1a1a; font-size: 18px; }
  header { position: sticky; top: 0; z-index: 10; background: #b26a00; color: #fff;
           padding: 12px 18px; display: flex; gap: 14px; align-items: center;
           flex-wrap: wrap; box-shadow: 0 2px 8px rgba(0,0,0,.2); }
  header strong { font-size: 20px; }
  header .stats { font-size: 16px; opacity: .95; }
  header button, header label.imp {
    font-size: 16px; padding: 8px 12px; border-radius: 8px; border: none;
    cursor: pointer; background: #fff; color: #b26a00; font-weight: 600; }
  main { max-width: 920px; margin: 0 auto; padding: 18px; }
  .empty { text-align: center; color: #666; margin-top: 60px; font-size: 20px; }
  h2.sec { margin: 28px 0 10px; font-size: 22px; }
  .card { background: #fff; border-radius: 12px; padding: 16px 18px; margin: 12px 0;
          border: 2px solid #e3e3e0; }
  .card.ok { border-color: #2e7d32; background: #f3fbf3; }
  .card.no { border-color: #c62828; background: #fdf3f3; }
  .hd { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-bottom: 10px; }
  .badge { font-size: 13px; padding: 2px 9px; border-radius: 20px; background: #eef1f5; color: #444; }
  .badge.id { margin-left: auto; color: #999; background: none; }
  .fld { margin: 6px 0; line-height: 1.4; }
  .fld .lbl { font-size: 13px; color: #888; text-transform: uppercase; letter-spacing: .03em; }
  .fld .val { font-size: 21px; }
  .pairs { display: grid; grid-template-columns: max-content auto; gap: 4px 14px; font-size: 21px; }
  .pairs .r { color: #1565c0; }
  .ctl { display: flex; gap: 10px; align-items: flex-start; margin-top: 14px;
         border-top: 1px dashed #ddd; padding-top: 12px; flex-wrap: wrap; }
  .btn { font-size: 16px; font-weight: 700; padding: 10px 16px; border-radius: 10px;
         border: 2px solid #bbb; background: #fff; cursor: pointer; white-space: nowrap; }
  .btn.appr { border-color: #2e7d32; color: #2e7d32; }
  .btn.appr.on { background: #2e7d32; color: #fff; }
  .btn.rej { border-color: #c62828; color: #c62828; }
  .btn.rej.on { background: #c62828; color: #fff; }
  .ctl textarea { flex: 1; min-width: 220px; font-size: 16px; padding: 8px 10px;
                  border-radius: 8px; border: 1px solid #ccc; resize: vertical;
                  min-height: 44px; font-family: inherit; }
</style></head><body>
<header>
  <strong>Ревью черновиков</strong>
  <span class="stats" id="stats"></span>
  <button id="exportBtn">💾 Сохранить файл</button>
  <label class="imp">📂 Загрузить<input id="importFile" type="file" accept="application/json" hidden></label>
</header>
<main id="list"></main>
<script>
const DATA = __DATA__;
const TOTAL = __TOTAL__;
const KEY = 'speech_draft_review_v1';
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

function renderItem(it) {
  const card = el('div', 'card');
  card.dataset.id = it.id;
  const hd = el('div', 'hd');
  if (it.kind) hd.append(badge(it.kind));
  hd.append(badge('L' + (it.level || 0)), badge(it.id, 'id'));
  card.append(hd);
  if (it.prompt) card.append(fld('Задание', it.prompt));
  if (it.answer) card.append(fld('Ответ', it.answer));
  if (Array.isArray(it.syllables)) card.append(fld('Слоги', it.syllables.join(' · ')));
  if (Array.isArray(it.tokens)) card.append(fld('Слова по порядку', it.tokens.join('  ·  ')));
  if (Array.isArray(it.pairs)) {
    const w = el('div', 'fld');
    const l = el('div', 'lbl'); l.textContent = 'Пары';
    const g = el('div', 'pairs');
    it.pairs.forEach(p => {
      const a = el('div'); a.textContent = p.left;
      const b = el('div', 'r'); b.textContent = '→ ' + p.right;
      g.append(a, b);
    });
    w.append(l, g); card.append(w);
  }
  if (it.emoji) card.append(fld('Эмодзи', it.emoji));

  const ctl = el('div', 'ctl');
  const ok = el('button', 'btn appr');
  const no = el('button', 'btn rej');
  const setBtns = () => {
    const a = dec[it.id] && dec[it.id].approved;
    ok.textContent = a === true ? '✓ Одобрено' : 'Одобрить';
    ok.classList.toggle('on', a === true);
    no.textContent = a === false ? '✕ Убрать' : 'Убрать';
    no.classList.toggle('on', a === false);
    card.classList.toggle('ok', a === true);
    card.classList.toggle('no', a === false);
  };
  ok.onclick = () => { dec[it.id] = dec[it.id] || {}; dec[it.id].approved = dec[it.id].approved === true ? null : true; setBtns(); save(); };
  no.onclick = () => { dec[it.id] = dec[it.id] || {}; dec[it.id].approved = dec[it.id].approved === false ? null : false; setBtns(); save(); };
  setBtns();
  const ta = el('textarea');
  ta.placeholder = Array.isArray(it.syllables) ? 'Исправленное деление (через / или пробел)'
    : Array.isArray(it.tokens) ? 'Исправленное предложение целиком'
    : Array.isArray(it.pairs) ? 'Заметка / какую пару поправить'
    : 'Комментарий';
  ta.value = (dec[it.id] && dec[it.id].comment) || '';
  ta.oninput = () => { dec[it.id] = dec[it.id] || {}; dec[it.id].comment = ta.value; save(); };
  ctl.append(ok, no, ta);
  card.append(ctl);
  return card;
}

function render() {
  const list = document.getElementById('list');
  list.innerHTML = '';
  if (!DATA.length) { list.innerHTML = '<div class="empty">Нет непросмотренных черновиков 🎉</div>'; return; }
  DATA.forEach(g => {
    const h = el('h2', 'sec'); h.textContent = g.title + ' (' + g.items.length + ')';
    list.append(h);
    g.items.forEach(it => list.append(renderItem(it)));
  });
}

function stats() {
  let appr = 0, rej = 0;
  Object.values(dec).forEach(d => { if (d.approved === true) appr++; else if (d.approved === false) rej++; });
  document.getElementById('stats').textContent =
    'одобрено ' + appr + ' · убрать ' + rej + ' · всего к ревью ' + TOTAL;
}

document.getElementById('exportBtn').onclick = () => {
  // не выгружаем «пустые» решения (null без комментария)
  const out = {};
  Object.keys(dec).forEach(k => {
    const d = dec[k] || {};
    const hasC = (d.comment || '').trim();
    if (d.approved === true || d.approved === false || hasC) {
      out[k] = {}; if (d.approved === true || d.approved === false) out[k].approved = d.approved;
      if (hasC) out[k].comment = d.comment.trim();
    }
  });
  const blob = new Blob([JSON.stringify(out, null, 2)], { type: 'application/json' });
  const a = el('a'); a.href = URL.createObjectURL(blob);
  a.download = 'draft-decisions.json'; a.click();
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
    groups, total = load_groups()
    html = (TEMPLATE
            .replace("__DATA__", json.dumps(groups, ensure_ascii=False))
            .replace("__TOTAL__", str(total)))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Готово: {OUT}")
    print(f"Непросмотренных черновиков: {total} в {len(groups)} наборах")
    for g in groups:
        print(f"  {g['title']}: {len(g['items'])}")
    print("Открой tools/draft_review.html двойным кликом в браузере.")


if __name__ == "__main__":
    main()
