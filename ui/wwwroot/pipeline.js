import { esc } from './ask-card.js';
import { capacityStrip, prio } from './org.js';

/** The solve steps of bin/solve-next.sh: the grid's columns and the task drawer's rail, number, label and title. */
export const STEPS = [
  ['3', 'triage', 'Tier, archetype and related issues of the task'],
  ['3b', 'chart', 'The request map charted until map.sh clear passes'],
  ['4', 'grill', 'The grill with the human until the plan is ready'],
  ['5', 'plan-check', 'The architect checks the plan against docs/architecture'],
  ['6', 'decompose', 'The plan cut into blocks'],
  ['8', 'cut', 'The cut checked by dag-check.sh, its wave plan in the progress file'],
  ['9', 'approve', 'The human approves the plan and the task is claimed'],
  ['10', 'worktree', 'The session worktree and branch of the task'],
  ['11', 'blocks', 'Every block implemented, verified and merged, wave by wave'],
  ['12', 'acceptance', 'The acceptance, quality gates and duplication check (12b) over the whole diff'],
  ['13', 'review', 'The code-reviewer over the whole diff'],
  ['14', 'MR', 'The task MR, for the human to review and merge'],
  ['15', 'report', 'The self-report: the task set to review'],
  ['16', 'knowledge', 'The knowledge review: lessons and decisions proposed'],
];
const TABS = ['Pipeline', 'Map', 'Plan', 'Org', 'Memory', 'Setup'];
const rank = (p) => ({ P0: 0, P1: 1, P2: 2, P3: 3 })[p] ?? 2;

/** The New request box's draft, kept across the page's re-renders; app.js empties `text` once the CEO has it. */
export const intake = { text: '', priority: 'P2' };

/** The drawer a task id or an ask's task belongs to: the parent task (`T-<n>` or `T-<ALIAS>-<n>`) of a block or
 * step, or setup for none. */
export const groupOf = (task) => (!task || task === 'none' ? 'setup' : (task.match(/^T-(?:[A-Z]{2,4}-)?\d+/) || [task])[0]);

/** The open, unsent asks of sessions in herdr, oldest first: what the counter counts and walks. A gone session's asks
 * count too, marked `gone`, since the relay queues their answers. An ask counts under its own task, which the server
 * fills from its session's when the ask names none, the key its drawer groups it by. */
export function waiting(sessions) {
  return sessions.filter((s) => s.pane)
    .flatMap((s) => s.asks.filter((a) => a.status === 'open' && !a.sent).map((a) => ({ ...a, sid: s.sid, pane: s.pane, gone: s.agent === 'gone' })))
    .sort((a, b) => Date.parse(a.modified) - Date.parse(b.modified));
}

/** The column of the step a session reports: its own, else the one of its number, so 12b sits under 12. */
function stepAt(session) {
  const k = (session.step.match(/^Step (\w+) of 16/) || [])[1];
  if (!k) return -1;
  const i = STEPS.findIndex(([n]) => n === k);
  return i >= 0 ? i : STEPS.findIndex(([n]) => n === k.replace(/\D+$/, ''));
}

/** The index in STEPS of the furthest step the sessions of task `id` or of its blocks report, -1 for none. */
export const currentStep = (sessions, id) => Math.max(-1, ...sessions.filter((s) => groupOf(s.task) === id).map(stepAt));

const sessionChip = (s) => `<span class="chip ${s.pane ? 'accent' : ''}" title="${s.pane ? `pane ${esc(s.pane)}` : 'outside herdr'}">${esc(s.sid)}</span>`;

/** One task's row: a step ticked only when the state records it done (`steps` of /api/board), the step its sessions
 * report marked current apart from that, and its open asks counted where they are. */
function taskRow(t, sessions) {
  const mine = sessions.filter((s) => groupOf(s.task) === t.id);
  const at = currentStep(sessions, t.id);
  const done = new Set(t.steps || []);
  const open = waiting(sessions).filter((a) => groupOf(a.task) === t.id).length;
  const count = open ? `<span class="chip warn">${open} to answer</span>` : '';
  const cells = STEPS.map(([n], i) => {
    const tick = done.has(n) ? '✓' : '';
    if (i === at) return `<td class="cur${tick ? ' done' : ''}" aria-current="step">${tick}${count}${mine.map(sessionChip).join('')}</td>`;
    return tick ? `<td class="done">${tick}</td>` : '<td></td>';
  });
  return `<tr><td class="task"><button data-drawer="${esc(t.id)}"><span class="id">${esc(t.id)}</span> ${t.repo ? `<span class="chip repo">${esc(t.repo)}</span>` : ''}`
    + `<span class="chip">${esc(t.status)}</span><span class="goal">${esc(t.goal)}</span>${at < 0 ? count : ''}</button></td><td>${prio(t.priority)}</td>${cells.join('')}</tr>`;
}

function blockRow(b, parent, sessions) {
  return `<tr class="sub"><td class="task"><button data-drawer="${esc(parent)}"><span class="id">${esc(b.id)}</span> <span class="chip">${esc(b.status)}</span></button></td>`
    + `<td colspan="${STEPS.length + 1}">${sessions.filter((s) => s.task === b.id).map(sessionChip).join('')} ${esc(b.goal)}</td></tr>`;
}

function requestRow(id, r) {
  const head = id
    ? `<button class="id" data-request="${esc(id)}" data-goto="Map" title="The map of ${esc(id)}">${esc(id)}</button>`
      + `${r ? ` ${prio(r.priority)}<span class="chip">${esc(r.status)}</span> ${esc(r.destination)}` : ''}`
    : 'Without a request';
  return `<tr class="req"><th scope="rowgroup" colspan="${STEPS.length + 2}">${head}</th></tr>`;
}

/** The root rows by their `request:`, the best priority first, then the newest request, the rows without one last;
 * inside a request its parents by priority. */
function byRequest(roots, requests) {
  const groups = new Map();
  for (const t of roots) groups.set(t.request || '', [...(groups.get(t.request || '') || []), t]);
  const best = (k) => (requests.find((r) => r.id === k) ? rank(requests.find((r) => r.id === k).priority) : Math.min(...groups.get(k).map((t) => rank(t.priority))));
  return [...groups.keys()]
    .sort((a, b) => (!a) - (!b) || best(a) - best(b) || b.localeCompare(a, 'en', { numeric: true }))
    .map((k) => [k, groups.get(k).sort((a, b) => rank(a.priority) - rank(b.priority))]);
}

/** A setup session's label: its flow, task and step, each once. */
const setupLabel = (s) => [...new Set([s.flow, s.task, s.step].filter((v) => v && v !== 'none'))].join(' · ') || s.sid;

/** The top of every tab: the tabs, the to-answer counter and the setup strip, with its live sessions, that opens the
 * setup drawer. */
export function renderTop(sessions, tab) {
  const setup = sessions.filter((s) => groupOf(s.task) === 'setup' && s.agent !== 'gone');
  const list = waiting(sessions);
  const all = list.length;
  const gone = list.filter((a) => a.gone).length;
  const setupWaiting = list.filter((a) => groupOf(a.task) === 'setup').length;
  const el = document.createElement('div');
  el.className = 'page';
  el.innerHTML = '<header class="top"><h1>Factory</h1><div class="tabs" role="tablist" aria-label="Views">'
    + `${TABS.map((t) => `<button role="tab" data-tab="${t}" aria-selected="${t === tab}">${t}</button>`).join('')}</div>`
    + `<button class="btn counter ${all ? 'primary' : ''}" data-act="next" ${all ? '' : 'disabled'}>${all ? `${all} to answer` : 'All answered'}${gone ? `<small>, ${gone} whose session ended</small>` : ''}</button></header>`
    + `<button class="strip" data-drawer="setup"><b>Setup</b>${setup.map((s) => `<span class="chip" data-session="${esc(s.sid)}" title="session ${esc(s.sid)}">${esc(setupLabel(s))}</span>`).join('')}`
    + `${setupWaiting ? `<span class="chip warn">${setupWaiting} to answer</span>` : ''}</button>`;
  return el;
}

/** The New request box: the request and its priority, P2 unless picked, that Send (`data-act="intake"`) posts to the CEO
 * as a free message; without a CEO session it names the command that starts one and takes nothing. `note` is the
 * outcome of the last send. */
function intakeBox(ceo, note) {
  const off = ceo ? '' : ' disabled';
  return '<section class="tab-body" data-intake aria-label="New request"><h3>New request</h3>'
    + (ceo ? '' : '<p class="muted">No CEO session runs, so no request goes out from here. Start one in the state directory: '
      + '<code>claude \'/claude-factory:factory ceo\'</code></p>')
    + `<div class="edit"><textarea rows="2" aria-label="The request"${off}>${esc(intake.text)}</textarea>`
    + `<select aria-label="Priority"${off}>${['P0', 'P1', 'P2', 'P3'].map((p) => `<option${p === intake.priority ? ' selected' : ''}>${p}</option>`).join('')}</select>`
    + `<button class="btn primary" data-act="intake"${off}>Send</button></div>`
    + (note ? `<p class="${note.error ? 'bad' : 'muted'}">${esc(note.text)}</p>` : '')
    + '</section>';
}

/**
 * The Pipeline tab: the capacity strip, the grid of tasks across the solve steps and the New request box under it,
 * above it while there is no task. The tasks of each request of `/api/requests` sit under one header row with its
 * priority, status and destination, each task with its repo chip and priority, its blocks in sub-rows under it and
 * the step its session reports marked `aria-current="step"`.
 */
export function renderPipeline(board, sessions, requests = [], capacity = null, ceo = null, note = null) {
  const ids = new Set(board.map((t) => t.id));
  const roots = board.filter((t) => groupOf(t.id) === t.id || !ids.has(groupOf(t.id)));
  const groups = byRequest(roots, requests);
  const heads = groups.some(([k]) => k);
  const bodies = groups.map(([k, ts]) => `<tbody>${heads ? requestRow(k, requests.find((r) => r.id === k)) : ''}${ts.map((t) => taskRow(t, sessions)
    + board.filter((b) => b !== t && groupOf(b.id) === t.id && t.id === groupOf(t.id)).map((b) => blockRow(b, t.id, sessions)).join('')).join('')}</tbody>`);
  const el = document.createElement('div');
  el.className = 'pipeline';
  // why: with tasks the grid comes first, so on a phone it starts right under the header; an empty grid points to the box
  const box = intakeBox(ceo, note);
  el.innerHTML = (capacity ? capacityStrip(capacity) : '') + (bodies.length ? '' : box)
    + `<div class="grid-wrap"><table><thead><tr><th class="task">Task</th><th>Prio</th>${STEPS.map(([n, label, title]) => `<th title="${title}">${n} <small>${label}</small></th>`).join('')}</tr></thead>`
    + `${bodies.join('') || `<tbody><tr><td colspan="${STEPS.length + 2}" class="muted">No tasks yet. Start one with New request above.</td></tr></tbody>`}</table></div>${bodies.length ? box : ''}`;
  el.addEventListener('input', (e) => {
    if (e.target.matches('[data-intake] textarea')) intake.text = e.target.value;
    if (e.target.matches('[data-intake] select')) intake.priority = e.target.value;
  });
  return el;
}
