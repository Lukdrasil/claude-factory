import { esc } from './ask-card.js';
import { capacityStrip, prio } from './org.js';

const STEPS = [['3', 'triage'], ['3b', 'chart'], ['4', 'grill'], ['5', 'plan-check'], ['6', 'decompose'], ['8', 'cut'], ['9', 'approve'],
  ['10', 'worktree'], ['11', 'blocks'], ['12', 'acceptance'], ['13', 'review'], ['14', 'MR'], ['15', 'report'], ['16', 'knowledge']];
const TABS = ['Pipeline', 'Map', 'Plan', 'Org', 'Memory', 'Setup'];
const rank = (p) => ({ P0: 0, P1: 1, P2: 2, P3: 3 })[p] ?? 2;

/** The drawer a task id or an ask's task belongs to: the parent task (`T-<n>` or `T-<ALIAS>-<n>`) of a block or
 * step, or setup for none. */
export const groupOf = (task) => (!task || task === 'none' ? 'setup' : (task.match(/^T-(?:[A-Z]{2,4}-)?\d+/) || [task])[0]);

/** The open, unsent asks of live sessions in herdr, oldest first: what the counter counts and walks. */
export function waiting(sessions) {
  return sessions.filter((s) => s.pane && s.agent !== 'gone')
    .flatMap((s) => s.asks.filter((a) => a.status === 'open' && !a.sent).map((a) => ({ ...a, sid: s.sid, pane: s.pane })))
    .sort((a, b) => Date.parse(a.modified) - Date.parse(b.modified));
}

/** The column of the step a session reports: its own, else the one of its number, so 12b sits under 12. */
function stepAt(session) {
  const k = (session.step.match(/^Step (\w+) of 16/) || [])[1];
  if (!k) return -1;
  const i = STEPS.findIndex(([n]) => n === k);
  return i >= 0 ? i : STEPS.findIndex(([n]) => n === k.replace(/\D+$/, ''));
}

const sessionChip = (s) => `<span class="chip ${s.pane ? 'accent' : ''}" title="${s.pane ? `pane ${esc(s.pane)}` : 'outside herdr'}">${esc(s.sid)}</span>`;

function taskRow(t, sessions) {
  const mine = sessions.filter((s) => groupOf(s.task) === t.id);
  const at = Math.max(-1, ...mine.map(stepAt));
  const open = waiting(mine).length;
  const cells = STEPS.map((_, i) => {
    if (i === at) {
      return `<td class="cur" aria-current="step">${open ? `<span class="chip warn">${open} to answer</span>` : ''}${mine.map(sessionChip).join('')}</td>`;
    }
    return t.status === 'done' || i < at ? '<td class="done">✓</td>' : '<td></td>';
  });
  return `<tr><td class="task"><button data-drawer="${esc(t.id)}"><span class="id">${esc(t.id)}</span> ${t.repo ? `<span class="chip repo">${esc(t.repo)}</span>` : ''}`
    + `<span class="chip">${esc(t.status)}</span><span class="goal">${esc(t.goal)}</span></button></td><td>${prio(t.priority)}</td>${cells.join('')}</tr>`;
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

/** The top of every tab: the tabs, the to-answer counter and the setup strip that opens the setup drawer. */
export function renderTop(sessions, tab) {
  const setup = sessions.filter((s) => groupOf(s.task) === 'setup');
  const all = waiting(sessions).length;
  const setupWaiting = waiting(setup).length;
  const el = document.createElement('div');
  el.className = 'page';
  el.innerHTML = '<header class="top"><h1>Factory</h1><div class="tabs" role="tablist" aria-label="Views">'
    + `${TABS.map((t) => `<button role="tab" data-tab="${t}" aria-selected="${t === tab}">${t}</button>`).join('')}</div>`
    + `<button class="btn counter ${all ? 'primary' : ''}" data-act="next" ${all ? '' : 'disabled'}>${all ? `${all} to answer` : 'All answered'}</button></header>`
    + `<button class="strip" data-drawer="setup"><b>Setup</b>${setup.map((s) => `<span class="chip">${esc(s.flow || s.sid)}</span>`).join('')}`
    + `${setupWaiting ? `<span class="chip warn">${setupWaiting} to answer</span>` : ''}</button>`;
  return el;
}

/**
 * The Pipeline tab: the capacity strip and the grid of tasks across the solve steps, the tasks of each request of
 * `/api/requests` under one header row with its priority, status and destination, each task with its repo chip and
 * priority, its blocks in sub-rows under it and the step its session reports marked `aria-current="step"`.
 */
export function renderPipeline(board, sessions, requests = [], capacity = null) {
  const ids = new Set(board.map((t) => t.id));
  const roots = board.filter((t) => groupOf(t.id) === t.id || !ids.has(groupOf(t.id)));
  const groups = byRequest(roots, requests);
  const heads = groups.some(([k]) => k);
  const bodies = groups.map(([k, ts]) => `<tbody>${heads ? requestRow(k, requests.find((r) => r.id === k)) : ''}${ts.map((t) => taskRow(t, sessions)
    + board.filter((b) => b !== t && groupOf(b.id) === t.id && t.id === groupOf(t.id)).map((b) => blockRow(b, t.id, sessions)).join('')).join('')}</tbody>`);
  const el = document.createElement('div');
  el.className = 'pipeline';
  el.innerHTML = (capacity ? capacityStrip(capacity) : '')
    + `<div class="grid-wrap"><table><thead><tr><th class="task">Task</th><th>Prio</th>${STEPS.map(([n, label]) => `<th>${n} <small>${label}</small></th>`).join('')}</tr></thead>`
    + `${bodies.join('') || `<tbody><tr><td colspan="${STEPS.length + 2}" class="muted">No tasks yet. Start one with <code>/claude-factory:factory new</code>.</td></tr></tbody>`}</table></div>`;
  return el;
}
