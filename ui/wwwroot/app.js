import { groupOf, intake, renderPipeline, renderTop, waiting } from './pipeline.js';
import { renderDrawer } from './drawer.js';
import { compose } from './ask-card.js';
import { renderSetupStrip, renderSetupTab } from './setup.js';
import { renderOrg } from './org.js';
import { pickRequest, renderMap, renderPlan } from './requests.js';
import { renderMemory } from './memory.js';

const token = location.hash.slice(1).replace(/^token=/, '');
const app = document.getElementById('app');
const KEPT = 'factory-staged';
const S = {
  board: [], sessions: [], setup: null, raw: '', drawer: null, shown: new Set(), staged: kept(), cursor: null, detail: null,
  tab: 'Pipeline', org: null, requests: [], request: '', map: null, passNote: null, intakeNote: null, stale: false,
};
let linked = new URLSearchParams(location.search).get('ask');

const keyOf = (a) => `${a.sid}/${a.ask}`;
const allAsks = () => S.sessions.flatMap((s) => s.asks.map((a) => ({ ...a, sid: s.sid, pane: s.pane, agent: s.agent })));
const stagedFor = (key) => (S.staged[key] ||= { items: {}, editing: {}, drafts: {} });

/** The answers staged in this tab before a reload, without a send in flight or its error. */
function kept() {
  try {
    const staged = JSON.parse(sessionStorage.getItem(KEPT)) || {};
    for (const st of Object.values(staged)) {
      delete st.sending;
      delete st.error;
    }
    return staged;
  } catch {
    return {};
  }
}

function keep() {
  try {
    sessionStorage.setItem(KEPT, JSON.stringify(S.staged));
  } catch {
    // why: storage may be off or full; the staged answers then last until a reload, as before
  }
}

/** A selector for the focused control that finds its twin after a render: its card, question and data attributes. */
function focusPath(el) {
  if (!el || el === document.body || !app.contains(el)) return null;
  const own = ['act', 'k', 'tab', 'drawer', 'request', 'kind', 'scope'].filter((k) => el.dataset[k] !== undefined)
    .map((k) => `[data-${k}="${CSS.escape(el.dataset[k])}"]`).join('');
  if (!own && el.tagName !== 'TEXTAREA') return null;
  const ask = el.closest('[data-ask]')?.dataset.ask;
  const q = el.closest('[data-q]')?.dataset.q;
  const scope = `${el.closest('[data-intake]') ? '[data-intake] ' : ''}${ask ? `[data-ask="${CSS.escape(ask)}"] ` : ''}${q ? `[data-q="${CSS.escape(q)}"] ` : ''}`;
  return { at: `${scope}${el.tagName.toLowerCase()}${own}`, question: q && scope.trim(), caret: el.selectionStart };
}

async function api(path, init = {}) {
  const r = await fetch(path, { ...init, headers: { 'X-Factory-Token': token, ...init.headers } });
  if (!r.ok) throw Object.assign(new Error(`${init.method || 'GET'} ${path} answered ${r.status}`), { status: r.status });
  return r;
}

async function loadDetail(id) {
  if (!id || id === 'setup') return null;
  const r = await fetch(`/api/tasks/${id}`, { headers: { 'X-Factory-Token': token } });
  if (r.status === 404) return null;
  if (!r.ok) throw Object.assign(new Error(`GET /api/tasks/${id} answered ${r.status}`), { status: r.status });
  const detail = await r.json();
  detail.blockDetails = (await Promise.all(detail.blocks.map((b) => loadDetail(b.id)))).filter(Boolean);
  return detail;
}

/** A route a server of an older build may lack: its body, or `null` for any answer but 200, so the page degrades. */
async function soft(path) {
  const r = await fetch(path, { headers: { 'X-Factory-Token': token } }).catch(() => null);
  const text = r && r.ok ? await r.text() : 'null';
  try {
    JSON.parse(text);
    return text;
  } catch {
    return 'null';
  }
}

async function load() {
  const id = S.drawer;
  const [board, sessions, setup, org, requests, detail] = await Promise.all([
    ...['/api/board', '/api/sessions', '/api/setup'].map((p) => api(p).then((r) => r.text())),
    soft('/api/org'),
    soft('/api/requests'),
    loadDetail(id).then((d) => d && JSON.stringify(d)),
  ]);
  const list = [JSON.parse(requests)].flat().filter(Boolean);
  const rid = (S.tab === 'Map' || S.tab === 'Plan') && pickRequest(list, S.request);
  const map = rid ? await soft(`/api/requests/${encodeURIComponent(rid)}`) : 'null';
  const raw = [board, sessions, setup, org, requests, detail, map].join('\n');
  if (raw === S.raw) return;
  S.raw = raw;
  S.board = JSON.parse(board);
  S.sessions = JSON.parse(sessions);
  S.setup = JSON.parse(setup);
  S.org = JSON.parse(org);
  S.requests = list;
  S.map = JSON.parse(map);
  S.detail = detail && JSON.parse(detail);
  render();
  const a = linked && allAsks().find((w) => keyOf(w) === linked);
  linked = null;
  if (a) show(a);
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
  p.textContent = err.status === 401
    ? 'The UI token is not valid any more: open the URL ui-up.sh printed.'
    : `${err.message}. Open the URL ui-up.sh printed.`;
  app.querySelector('.error')?.remove();
  app.prepend(p);
}

/** The cue that the page may show old data, while the change stream is down; every render puts it back. */
function staleCue() {
  app.querySelector('.stale')?.remove();
  if (!S.stale) return;
  const p = document.createElement('p');
  p.className = 'stale';
  p.setAttribute('role', 'status');
  p.textContent = 'Live updates stopped, reconnecting. What you see may be out of date.';
  app.prepend(p);
}

function stale(on) {
  if (S.stale === on) return;
  S.stale = on;
  staleCue();
}

function group(id) {
  return {
    id,
    task: S.board.find((t) => t.id === id),
    blocks: S.board.filter((t) => t.id !== id && groupOf(t.id) === id),
    sessions: S.sessions.filter((s) => groupOf(s.task) === id),
    allSessions: S.sessions,
    asks: allAsks()
      .filter((a) => groupOf(a.task) === id && (a.status === 'open' || S.shown.has(keyOf(a))))
      .sort((a, b) => Date.parse(a.modified) - Date.parse(b.modified)),
    staged: S.staged,
    cursor: S.cursor,
    detail: S.detail?.task.id === id ? S.detail : null,
    token,
  };
}

function renderTab() {
  const rid = pickRequest(S.requests, S.request);
  const map = S.map?.id === rid ? S.map : null;
  const el = {
    Map: () => renderMap(S.requests, rid, map),
    Plan: () => renderPlan(S.requests, rid, map),
    Org: () => renderOrg(S.org),
    Memory: () => renderMemory(S.setup.passes || [], S.org?.ceo, S.passNote),
    Setup: () => renderSetupTab(S.setup),
  }[S.tab]?.() || renderPipeline(S.board, S.sessions, S.requests, S.org?.capacity || S.setup.capacity, S.org?.ceo, S.intakeNote);
  el.setAttribute('role', 'tabpanel');
  el.setAttribute('aria-label', S.tab);
  return el;
}

function render() {
  const focus = focusPath(document.activeElement);
  const left = app.querySelector('.grid-wrap')?.scrollLeft ?? 0;
  const top = app.querySelector('aside')?.scrollTop ?? 0;
  const details = app.querySelector('aside .details')?.open;
  const page = renderTop(S.sessions, S.tab);
  page.querySelector('.strip').append(renderSetupStrip(S.setup));
  page.append(renderTab());
  app.replaceChildren(page);
  staleCue();
  const grid = app.querySelector('.grid-wrap');
  if (grid) grid.scrollLeft = left;
  if (S.drawer) {
    app.append(renderDrawer(group(S.drawer)));
    if (details) app.querySelector('aside .details')?.setAttribute('open', '');
    app.querySelector('aside').scrollTop = top;
    app.querySelector('aside').dispatchEvent(new Event('scroll'));
  }
  keep();
  if (!focus) return;
  // why: every render replaces the page; the focus goes back to the same control, else to the first one of its question
  const to = app.querySelector(focus.at) || (focus.question && app.querySelector(`${focus.question} button:not(:disabled)`));
  to?.focus({ preventScroll: true });
  if (to?.tagName === 'TEXTAREA') to.setSelectionRange(focus.caret, focus.caret);
}

/** Closes the drawer and gives the focus back to the row that opens it. */
function close() {
  const id = S.drawer;
  S.drawer = null;
  render();
  app.querySelector(`[data-drawer="${CSS.escape(id)}"]`)?.focus({ preventScroll: true });
}

function open(id) {
  S.drawer = id;
  S.shown = new Set(allAsks().filter((a) => groupOf(a.task) === id && a.status === 'open').map(keyOf));
  app.querySelector('aside')?.remove();
  render();
  refresh();
}

function next() {
  const list = waiting(S.sessions);
  if (!list.length) return;
  show(list[(list.findIndex((w) => keyOf(w) === S.cursor) + 1) % list.length]);
}

function show(a) {
  S.cursor = keyOf(a);
  open(groupOf(a.task));
  app.querySelector(`aside [data-ask="${S.cursor}"]`)?.scrollIntoView({ block: 'start' });
}

async function send(key, staged) {
  const [sid, ask] = key.split('/');
  const text = compose(allAsks().find((a) => keyOf(a) === key).view, staged.items);
  staged.sending = true;
  render();
  try {
    await api(`/api/answers/${sid}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask, text }),
    });
    delete S.staged[key];
  } catch (err) {
    staged.error = `Couldn't send: ${err.message}. Your answer is kept, try Send again.`;
    staged.sending = false;
  }
  render();
}

async function redraw(visual) {
  try {
    await api(`/api/answers/${visual.dataset.visual}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask: visual.dataset.redraw, text: `Q${visual.dataset.row} redraw` }),
    });
  } catch (err) {
    showError(err);
  }
}

/** A new request from the Pipeline tab's box: a free message to the CEO, as the Memory tab's start buttons send. */
async function sendRequest() {
  if (!intake.text.trim()) return;
  const text = `request: ${intake.text.trim()}, priority ${intake.priority}`;
  try {
    await api(`/api/answers/${S.org.ceo.sid}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask: '', text }),
    });
    intake.text = '';
    S.intakeNote = { text: `Sent to the CEO: ${text}` };
  } catch (err) {
    S.intakeNote = { text: `Couldn't send "${text}": ${err.message}. Your request is kept, try Send again.`, error: true };
  }
  render();
}

/** A memory pass the human starts: a free message, no ask, typed into the CEO's pane by the relay. */
async function startPass(b) {
  const text = `start the ${b.dataset.kind} pass for ${b.dataset.scope}`;
  try {
    await api(`/api/answers/${S.org.ceo.sid}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask: '', text }),
    });
    S.passNote = { text: `Sent to the CEO: ${text}` };
  } catch (err) {
    S.passNote = { text: `Couldn't send "${text}": ${err.message}.`, error: true };
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
  if (b.dataset.tab || b.dataset.request) {
    S.tab = b.dataset.tab || b.dataset.goto || S.tab;
    S.request = b.dataset.request || S.request;
    render();
    return refresh();
  }
  if (b.dataset.drawer) return open(b.dataset.drawer);
  const act = b.dataset.act;
  if (act === 'next') return next();
  if (act === 'pass') return startPass(b);
  if (act === 'intake') return sendRequest();
  if (act === 'redraw') return redraw(b.closest('[data-visual]'));
  if (act === 'close') return close();
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
  const box = e.target.closest('[data-ask] textarea');
  if (!box) return;
  stagedFor(box.closest('[data-ask]').dataset.ask).drafts[box.closest('[data-q]').dataset.q] = box.value;
  keep();
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && S.drawer) close();
});

async function stream() {
  for (;;) {
    let refused = false;
    try {
      const reader = (await api('/api/stream')).body.getReader();
      stale(false);
      while (!(await reader.read()).done) refresh();
    } catch (err) {
      // why: a refused token needs the new URL; any other drop is retried below, so the page only marks its data stale
      refused = err.status === 401;
      if (refused) showError(err);
    }
    stale(!refused);
    await new Promise((r) => setTimeout(r, 1000));
    refresh();
  }
}

if (token) {
  refresh();
  stream();
  // why: the leases under .capacity never reach the change stream, so the capacity and the Org tab poll for them
  setInterval(refresh, 5000);
}
