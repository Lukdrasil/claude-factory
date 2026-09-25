import { groupOf, intake, intakeLine, renderPipeline, renderTop, view, waiting } from './pipeline.js';
import { renderDrawer } from './drawer.js';
import { compose } from './ask-card.js';
import { renderSetupStrip, renderSetupTab } from './setup.js';
import { renderOrg } from './org.js';
import { pickRequest, renderMap, renderPlan } from './requests.js';
import { renderMemory } from './memory.js';
import { addRepoLine, aliasProblem, keysOf, onboardLine, proposalLine, repoForm, urlProblem } from './repos.js';

const token = location.hash.slice(1).replace(/^token=/, '');
const app = document.getElementById('app');
const KEPT = 'factory-staged';
const S = {
  board: [], sessions: [], setup: null, raw: '', drawer: null, shown: new Set(), staged: kept(), cursor: null, detail: null,
  tab: 'Pipeline', org: null, requests: [], request: '', map: null, passNote: null, intakeNote: null, repoNote: null, capNote: null, stale: false,
  busy: new Map(), auto: null, mute: null,
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
  const own = ['act', 'k', 'key', 'id', 'tab', 'drawer', 'request', 'kind', 'scope'].filter((k) => el.dataset[k] !== undefined)
    .map((k) => `[data-${k}="${CSS.escape(el.dataset[k])}"]`).join('');
  if (!own && el.tagName !== 'TEXTAREA') return null;
  const ask = el.closest('[data-ask]')?.dataset.ask;
  const q = el.closest('[data-q]')?.dataset.q;
  const visual = el.closest('[data-visual]')?.dataset.visual;
  const scope = `${el.closest('[data-intake]') ? '[data-intake] ' : ''}${visual ? `[data-visual="${CSS.escape(visual)}"] ` : ''}`
    + `${ask ? `[data-ask="${CSS.escape(ask)}"] ` : ''}${q ? `[data-q="${CSS.escape(q)}"] ` : ''}`;
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
  const [board, sessions, setup, org, requests, detail, auto, mute] = await Promise.all([
    ...['/api/board', '/api/sessions', '/api/setup'].map((p) => api(p).then((r) => r.text())),
    soft('/api/org'),
    soft('/api/requests'),
    loadDetail(id).then((d) => d && JSON.stringify(d)),
    soft('/api/auto-answer'),
    soft('/api/mute-sound'),
  ]);
  const list = [JSON.parse(requests)].flat().filter(Boolean);
  const rid = (S.tab === 'Map' || S.tab === 'Plan') && pickRequest(list, S.request);
  const map = rid ? await soft(`/api/requests/${encodeURIComponent(rid)}`) : 'null';
  const raw = [board, sessions, setup, org, requests, detail, map, auto, mute].join('\n');
  if (raw === S.raw) return;
  S.raw = raw;
  S.board = JSON.parse(board);
  S.sessions = JSON.parse(sessions);
  S.setup = JSON.parse(setup);
  S.org = JSON.parse(org);
  S.requests = list;
  S.map = JSON.parse(map);
  S.detail = detail && JSON.parse(detail);
  S.auto = JSON.parse(auto)?.on ?? null;
  S.mute = JSON.parse(mute)?.on ?? null;
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
    ceo: S.org?.ceo,
    token,
  };
}

function renderTab() {
  const rid = pickRequest(S.requests, S.request);
  const map = S.map?.id === rid ? S.map : null;
  const el = {
    Map: () => renderMap(S.requests, rid, map),
    Plan: () => renderPlan(S.requests, rid, map),
    Org: () => renderOrg(S.org, S.capNote),
    Memory: () => renderMemory(S.setup.passes || [], S.org?.ceo, S.passNote),
    Setup: () => renderSetupTab(S.setup, S.sessions, S.org?.ceo, S.repoNote),
  }[S.tab]?.() || renderPipeline(S.board, S.sessions, S.requests, S.org?.capacity || S.setup.capacity, S.org?.ceo, S.intakeNote, keysOf(S.setup?.reposYml));
  el.setAttribute('role', 'tabpanel');
  el.setAttribute('aria-label', S.tab);
  return el;
}

function render() {
  const focus = focusPath(document.activeElement);
  const left = app.querySelector('.grid-wrap')?.scrollLeft ?? 0;
  const down = app.querySelector('.grid-wrap')?.scrollTop ?? 0;
  const top = app.querySelector('aside')?.scrollTop ?? 0;
  const details = app.querySelector('aside .details')?.open;
  const page = renderTop(S.sessions, S.tab, S.auto, S.mute);
  page.querySelector('.strip').append(renderSetupStrip(S.setup));
  page.append(renderTab());
  app.replaceChildren(page);
  staleCue();
  const grid = app.querySelector('.grid-wrap');
  if (grid) Object.assign(grid, { scrollLeft: left, scrollTop: down });
  if (S.drawer) {
    app.append(renderDrawer(group(S.drawer)));
    if (details) app.querySelector('aside .details')?.setAttribute('open', '');
    app.querySelector('aside').scrollTop = top;
    app.querySelector('aside').dispatchEvent(new Event('scroll'));
  }
  for (const [at, state] of S.busy) {
    for (const b of app.querySelectorAll(at)) {
      b.disabled = true;
      b.classList.add(state);
      b.setAttribute('aria-busy', String(state === 'sending'));
    }
  }
  keep();
  if (!focus) return;
  // why: every render replaces the page; the focus goes back to the same control, else to the first one of its question
  const to = app.querySelector(focus.at) || (focus.question && app.querySelector(`${focus.question} button:not(:disabled)`));
  to?.focus({ preventScroll: true });
  if (to?.tagName === 'TEXTAREA' || (to?.tagName === 'INPUT' && ['text', 'search'].includes(to.type))) to.setSelectionRange(focus.caret, focus.caret);
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
    return render();
  }
  render();
  // the next waiting ask opens by itself: one of this drawer first, so the context stays, else the oldest elsewhere
  const rest = waiting(S.sessions).filter((w) => keyOf(w) !== key);
  const next = rest.find((w) => groupOf(w.task) === S.drawer) || rest[0];
  if (next) show(next);
}

async function redraw(visual) {
  try {
    await api(`/api/answers/${visual.dataset.visual}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask: visual.dataset.redraw, text: `Q${visual.dataset.row} redraw` }),
    });
    return true;
  } catch (err) {
    showError(err);
    return false;
  }
}

/** A button whose click posts to a session: disabled and marked sending while the post runs, then, with `hold`, sent
 * for 20 s, so a second click cannot repeat it; a failed post frees it at once. `post` resolves true once sent. A form
 * that empties once sent holds nothing, so its next message goes out at once. */
async function track(b, post, hold = true) {
  const at = focusPath(b)?.at;
  if (!at || S.busy.has(at)) return;
  S.busy.set(at, 'sending');
  render();
  if ((await post()) && hold) {
    S.busy.set(at, 'sent');
    setTimeout(() => {
      S.busy.delete(at);
      render();
    }, 20000);
  } else {
    S.busy.delete(at);
  }
  render();
}

/** A new request from the Pipeline tab's box: a free message to the CEO, as the Memory tab's start buttons send. */
async function sendRequest() {
  const text = intakeLine();
  if (!text) return false;
  try {
    await api(`/api/answers/${S.org.ceo.sid}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask: '', text }),
    });
    intake.text = '';
    S.intakeNote = { text: `Sent to the CEO: ${text}` };
    return true;
  } catch (err) {
    S.intakeNote = { text: `Couldn't send "${text}": ${err.message}. Your request is kept, try Send again.`, error: true };
    return false;
  }
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
    return true;
  } catch (err) {
    S.passNote = { text: `Couldn't send "${text}": ${err.message}.`, error: true };
    return false;
  }
}

/** A line of the Setup tab's Repositories section, or of another tab whose note is `note`, a free message to the CEO
 * like the New request box sends; true once sent. */
async function tellCeo(text, note = 'repoNote') {
  try {
    await api(`/api/answers/${S.org.ceo.sid}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask: '', text }),
    });
    S[note] = { text: `Sent to the CEO: ${text}. It picks it up when it is idle.` };
    return true;
  } catch (err) {
    S[note] = { text: `Couldn't send "${text}": ${err.message}.`, error: true };
    return false;
  }
}

/** Send of the Add repository form: the C1 add repo line, the draft kept until the CEO has it. */
async function sendRepo() {
  if (!repoForm.url.trim() || urlProblem(repoForm.url.trim()) || aliasProblem(repoForm.alias)) return false;
  const sent = await tellCeo(addRepoLine(repoForm));
  if (sent) Object.assign(repoForm, { open: false, url: '', alias: '' });
  return sent;
}

/** Make it a request of one proposal of a report, at the priority picked for that report, P3 unless picked. */
async function propose(b) {
  const key = b.dataset.key;
  const p = (S.setup.onboarding || []).find((o) => o.repo === key)?.proposals.find((x) => x.id === b.dataset.id);
  if (!p) return false;
  return tellCeo(proposalLine(key, p, repoForm.prio[key] || 'P3'));
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
  if (act === 'blocks') {
    if (!view.open.delete(b.dataset.key)) view.open.add(b.dataset.key);
    return render();
  }
  if (act === 'next') return next();
  if (act === 'auto') {
    return track(b, async () => {
      try {
        S.auto = (await (await api('/api/auto-answer', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ on: !S.auto }),
        })).json()).on;
        return true;
      } catch (err) {
        showError(err);
        return false;
      }
    }, false);
  }
  if (act === 'mute') {
    return track(b, async () => {
      try {
        S.mute = (await (await api('/api/mute-sound', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ on: !S.mute }),
        })).json()).on;
        return true;
      } catch (err) {
        showError(err);
        return false;
      }
    }, false);
  }
  if (act === 'pass') return track(b, () => startPass(b));
  if (act === 'intake') return track(b, sendRequest, false);
  if (act === 'add-repo-form') {
    repoForm.open = !repoForm.open;
    return render();
  }
  if (act === 'add-repo') return track(b, sendRepo, false);
  if (act === 'set-default-branch') {
    const v = document.querySelector(`[data-base-for="${CSS.escape(b.dataset.key)}"]`)?.value.trim() ?? '';
    if (!/^[A-Za-z0-9._/-]+$/.test(v)) {
      S.repoNote = { text: `"${v}" is not a branch name.`, error: true };
      return render();
    }
    return track(b, () => tellCeo(`set default branch ${b.dataset.key} ${v}`), false);
  }
  if (act === 'set-base') {
    const field = document.querySelector(`[data-base-of="${CSS.escape(b.dataset.id)}"]`);
    const v = field.value.trim();
    field.setCustomValidity(!S.org?.ceo ? 'No CEO session runs, so nothing goes out.'
      : /^[A-Za-z0-9._/-]+$/.test(v) ? '' : `"${v}" is not a branch name.`);
    if (!field.reportValidity()) return;
    return track(b, async () => {
      try {
        await api(`/api/answers/${S.org.ceo.sid}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ask: '', text: `set base ${b.dataset.id} ${v}` }),
        });
        return true;
      } catch (err) {
        showError(err);
        return false;
      }
    });
  }
  if (act === 'set-cap') {
    const n = document.querySelector(`[data-cap-for="${CSS.escape(b.dataset.name)}"]`)?.value.trim() ?? '';
    if (!/^\d{1,2}$/.test(n)) {
      S.capNote = { text: `A cap is a number from 0 to 99, not "${n}".`, error: true };
      return render();
    }
    return track(b, () => tellCeo(`set capacity ${b.dataset.name} ${n}`, 'capNote'), false);
  }
  if (act === 'onboard') return track(b, () => tellCeo(onboardLine(b.dataset.key)));
  if (act === 'unblock') return track(b, () => tellCeo(`unblock ${b.dataset.id}`, 'unblockNote'));
  if (act === 'propose') return track(b, () => propose(b));
  if (act === 'redraw') return track(b, () => redraw(b.closest('[data-visual]')));
  if (act === 'close') return close();
  const key = b.closest('[data-ask]')?.dataset.ask;
  if (!key) return;
  const staged = stagedFor(key);
  const q = b.closest('[data-q]')?.dataset.q;
  if (act === 'send') return send(key, staged);
  if (act === 'own' || act === 'discuss') {
    staged.editing[q] = staged.editing[q] === act ? undefined : act;
  } else if (act === 'menu' || act === 'full') {
    const k = act === 'menu' ? 'menu' : 'full';
    staged[k] = { ...staged[k], [q]: !staged[k]?.[q] };
  } else if (act === 'accept') {
    // why: only a question with nothing staged takes its recommendation, so Accept never overwrites a pick
    for (const x of allAsks().find((a) => keyOf(a) === key).view.questions) {
      if (x.recKey && !staged.items[x.q]) staged.items[x.q] = { kind: 'pick', text: x.recKey };
    }
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
  const act = e.target.dataset.act;
  if (act === 'find' || act === 'finished' || act === 'repo') {
    if (act === 'find') view.q = e.target.value;
    else if (act === 'repo') view.repo = e.target.value;
    else view.finished = e.target.checked;
    return render();
  }
  if (act === 'intake-kind' || act === 'intake-repo') {
    if (act === 'intake-kind') intake.kind = e.target.value;
    else intake.repos = [...document.querySelectorAll('[data-act="intake-repo"]:checked')].map((c) => c.value);
    return render();
  }
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
