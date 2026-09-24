import { groupOf, renderPipeline, waiting } from './pipeline.js';
import { renderDrawer } from './drawer.js';
import { compose, parseAsk } from './ask-card.js';

const token = location.hash.slice(1);
const app = document.getElementById('app');
const S = { board: [], sessions: [], raw: '', drawer: null, shown: new Set(), staged: {}, cursor: null };

const keyOf = (a) => `${a.sid}/${a.ask}`;
const allAsks = () => S.sessions.flatMap((s) => s.asks.map((a) => ({ ...a, sid: s.sid, pane: s.pane })));
const stagedFor = (key) => (S.staged[key] ||= { items: {}, editing: {}, drafts: {} });

async function api(path, init = {}) {
  const r = await fetch(path, { ...init, headers: { 'X-Factory-Token': token, ...init.headers } });
  if (!r.ok) throw new Error(`${init.method || 'GET'} ${path} answered ${r.status}`);
  return r;
}

async function load() {
  const [board, sessions] = await Promise.all(['/api/board', '/api/sessions'].map((p) => api(p).then((r) => r.text())));
  if (board + sessions === S.raw) return;
  S.raw = board + sessions;
  S.board = JSON.parse(board);
  S.sessions = JSON.parse(sessions);
  render();
}

let loading = null;
let again = false;
function refresh() {
  if (loading) {
    again = true;
    return;
  }
  loading = load().catch(showError).finally(() => {
    loading = null;
    if (again) {
      again = false;
      refresh();
    }
  });
}

function showError(err) {
  const p = document.createElement('p');
  p.className = 'error';
  p.textContent = `${err.message}. Open the URL ui-up.sh printed.`;
  app.querySelector('.error')?.remove();
  app.prepend(p);
}

function group(id) {
  return {
    id,
    task: S.board.find((t) => t.id === id),
    blocks: S.board.filter((t) => t.id !== id && groupOf(t.id) === id),
    sessions: S.sessions.filter((s) => groupOf(s.task) === id),
    asks: allAsks()
      .filter((a) => groupOf(a.task) === id && (a.status === 'open' || S.shown.has(keyOf(a))))
      .sort((a, b) => Date.parse(a.modified) - Date.parse(b.modified)),
    staged: S.staged,
  };
}

function render() {
  const typing = document.activeElement?.tagName === 'TEXTAREA' ? document.activeElement : null;
  const at = typing && [typing.closest('[data-ask]').dataset.ask, typing.closest('[data-q]').dataset.q, typing.selectionStart];
  const left = app.querySelector('.grid-wrap')?.scrollLeft ?? 0;
  const top = app.querySelector('aside')?.scrollTop ?? 0;
  app.replaceChildren(renderPipeline(S.board, S.sessions));
  app.querySelector('.grid-wrap').scrollLeft = left;
  if (S.drawer) {
    app.append(renderDrawer(group(S.drawer)));
    app.querySelector('aside').scrollTop = top;
  }
  const box = at && app.querySelector(`[data-ask="${at[0]}"] [data-q="${at[1]}"] textarea`);
  box?.focus();
  box?.setSelectionRange(at[2], at[2]);
}

function open(id) {
  S.drawer = id;
  S.shown = new Set(allAsks().filter((a) => groupOf(a.task) === id && a.status === 'open').map(keyOf));
  app.querySelector('aside')?.remove();
  render();
}

function next() {
  const list = waiting(S.sessions);
  if (!list.length) return;
  const a = list[(list.findIndex((w) => keyOf(w) === S.cursor) + 1) % list.length];
  S.cursor = keyOf(a);
  open(groupOf(a.task));
  app.querySelector(`aside [data-ask="${S.cursor}"]`)?.scrollIntoView({ block: 'start' });
}

async function send(key, staged) {
  const [sid, ask] = key.split('/');
  const text = compose(parseAsk(allAsks().find((a) => keyOf(a) === key).body), staged.items);
  try {
    await api(`/api/answers/${sid}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask, text }),
    });
    delete S.staged[key];
  } catch (err) {
    staged.error = `Not sent: ${err.message}`;
  }
  render();
}

function toggle(staged, act, q, text) {
  const item = staged.items[q];
  if (item && item.kind === act && item.text === text) delete staged.items[q];
  else staged.items[q] = { kind: act, text };
}

app.addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b || b.disabled) return;
  if (b.dataset.drawer) return open(b.dataset.drawer);
  const act = b.dataset.act;
  if (act === 'next') return next();
  if (act === 'close') {
    S.drawer = null;
    return render();
  }
  const key = b.closest('[data-ask]')?.dataset.ask;
  if (!key) return;
  const staged = stagedFor(key);
  const q = b.closest('[data-q]')?.dataset.q;
  if (act === 'send') return send(key, staged);
  if (act === 'own' || act === 'discuss') {
    staged.editing[q] = staged.editing[q] === act ? undefined : act;
  } else if (act === 'stage') {
    const text = b.closest('[data-q]').querySelector('textarea').value.trim();
    if (text) staged.items[q] = { kind: staged.editing[q], text };
    delete staged.editing[q];
    delete staged.drafts[q];
  } else {
    toggle(staged, act, q, b.dataset.k || '');
  }
  render();
});

app.addEventListener('input', (e) => {
  const box = e.target.closest('textarea');
  if (box) stagedFor(box.closest('[data-ask]').dataset.ask).drafts[box.closest('[data-q]').dataset.q] = box.value;
});

async function stream() {
  for (;;) {
    try {
      const reader = (await api('/api/stream')).body.getReader();
      while (!(await reader.read()).done) refresh();
    } catch (err) {
      showError(err);
    }
    await new Promise((r) => setTimeout(r, 1000));
    refresh();
  }
}

if (token) {
  refresh();
  stream();
}
