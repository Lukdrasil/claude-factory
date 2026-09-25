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
export const intake = { text: '', priority: 'P2', kind: 'request', repos: [], branch: '' };

/** The line Send posts to the CEO: `request: <text>, priority <P>`, or for a question or research
 * `<kind>[ <keys joined by ,>][ branch <branch>]: <text>`, the branch only with one repository; '' with no text. */
export function intakeLine() {
  const text = intake.text.trim();
  if (!text) return '';
  if (intake.kind === 'request') return `request: ${text}, priority ${intake.priority}`;
  const branch = intake.repos.length === 1 && intake.branch.trim();
  return `${intake.kind}${intake.repos.length ? ` ${intake.repos.join(',')}` : ''}${branch ? ` branch ${branch}` : ''}: ${text}`;
}

/** The grid's filter, kept across the page's re-renders: the done and closed tasks shown or not, the search text, the
 * repository picked, '' for all, and the tasks whose blocks are unfolded. */
export const view = { finished: false, q: '', repo: '', open: new Set() };

/** The phases the grid folds the solve steps into, each with the numbers of its steps in STEPS. */
const PHASES = [
  ['Plan', ['3', '3b', '4', '5', '6', '8']],
  ['Approve', ['9']],
  ['Build', ['10', '11']],
  ['Verify', ['12', '13']],
  ['Ship', ['14', '15', '16']],
];
const FINISHED = new Set(['done', 'closed']);
const TONE = { failed: 'bad', blocked: 'bad', triaged: 'warn', review: 'warn', ready: 'accent', claimed: 'accent', in_progress: 'accent', tests_ready: 'accent', done: 'ok' };
const statusChip = (s) => `<span class="chip status ${TONE[s] || ''}">${esc(s)}</span>`;

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

/** The sessions the grid draws: every one but those whose agent is gone. */
const live = (sessions) => sessions.filter((s) => s.agent !== 'gone');

/** A count of sessions as one chip, their ids in its title; nothing for none. */
const sessionsChip = (list) => (list.length
  ? `<span class="chip accent sessions" title="sessions ${esc(list.map((s) => s.sid).join(', '))}">${list.length}</span>` : '');

/** One phase of a task's row: a segment per step, done when the state records it (`steps` of /api/board), the step its
 * sessions report marked current apart from that; under it the current step and the count done, or `MR waits for
 * you` under Ship for a task in review, and the task's open asks when its current step is in this phase. */
function phaseCell(t, steps, at, count) {
  const done = new Set(t.steps || []);
  const cur = at >= 0 ? STEPS[at][0] : '';
  const here = steps.includes(cur);
  const k = steps.filter((n) => done.has(n)).length;
  const segs = steps.map((n) => {
    const [, label, title] = STEPS.find(([m]) => m === n);
    return `<span class="st${done.has(n) ? ' d' : ''}${n === cur ? ' c' : ''}" data-step="${n}" aria-label="${n} ${label}" title="${n} ${label}: ${esc(title)}"`
      + `${n === cur ? ' aria-current="step"' : ''}></span>`;
  }).join('');
  let label = k === steps.length ? (k === 1 ? 'done' : `${k}/${k}`) : k ? `${k}/${steps.length}` : '';
  if (here) label = `${STEPS[at][1]}${steps.length > 1 ? ` · ${k}/${steps.length}` : ''}`;
  if (steps.includes('14') && t.status === 'review') label = 'MR waits for you';
  return `<td class="phase${here ? ' cur' : ''}"><div class="seg">${segs}</div><small>${label}</small>${here ? count : ''}</td>`;
}

/** One task's row: its id, repo, status, live sessions and goal, the fold of its blocks, its priority and a cell per
 * phase; its open asks are counted in the phase of its current step, or in the task cell without one. */
function taskRow(t, sessions, blocks, shown) {
  const at = currentStep(live(sessions), t.id);
  const open = waiting(sessions).filter((a) => groupOf(a.task) === t.id).length;
  const count = open ? `<span class="chip warn">${open} to answer</span>` : '';
  const tally = Object.entries(blocks.reduce((m, b) => ({ ...m, [b.status]: (m[b.status] || 0) + 1 }), {}))
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([s, n]) => `${n} ${esc(s)}`);
  const fold = blocks.length ? `<button class="fold" data-act="blocks" data-key="${esc(t.id)}" aria-expanded="${shown}">`
    + `${blocks.length} block${blocks.length > 1 ? 's' : ''} · ${tally.join(' · ')}</button>` : '';
  return `<tr><td class="task"><button data-drawer="${esc(t.id)}"><span class="id">${esc(t.id)}</span> ${t.repo ? `<span class="chip repo">${esc(t.repo)}</span>` : ''}`
    + `${statusChip(t.status)}${sessionsChip(live(sessions).filter((s) => groupOf(s.task) === t.id))}<span class="goal" title="${esc(t.goal)}">${esc(t.goal)}</span>`
    + `${at < 0 ? count : ''}</button>${fold}</td><td>${prio(t.priority)}</td>${PHASES.map(([, steps]) => phaseCell(t, steps, at, count)).join('')}</tr>`;
}

function blockRow(b, parent, sessions) {
  return `<tr class="sub"><td class="task"><button data-drawer="${esc(parent)}"><span class="id">${esc(b.id)}</span> ${statusChip(b.status)}</button></td>`
    + `<td colspan="${PHASES.length + 1}"><div class="bline">${sessionsChip(live(sessions).filter((s) => s.task === b.id))}`
    + `<span class="goal" title="${esc(b.goal)}">${esc(b.goal)}</span></div></td></tr>`;
}

function requestRow(id, r) {
  const head = id
    ? `<button class="id" data-request="${esc(id)}" data-goto="Map" title="The map of ${esc(id)}">${esc(id)}</button>`
      + `${r ? ` ${prio(r.priority)}<span class="chip">${esc(r.status)}</span> <span class="req-dest" title="${esc(r.destination)}">${esc(r.destination)}</span>` : ''}`
    : 'Without a request';
  return `<tr class="req"><th scope="rowgroup" colspan="${PHASES.length + 2}"><div class="req-line">${head}</div></th></tr>`;
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

const AUTO = 'On: the server answers a round with its recommended options as it arrives. Confirm asks, notices, the approve, '
  + 'done and add-repo flows, and a round with any question lacking a recommended option always wait for you.';

const MUTE = 'On: while the UI runs, a session waiting on an answer shows its herdr notification with no sound.';

/** The top of every tab: the tabs, the Auto answer and Mute sound switches (none when the server has no such route,
 * `auto` or `mute` null), the to-answer counter and the setup strip, with its live sessions, that opens the setup drawer. */
export function renderTop(sessions, tab, auto = null, mute = null) {
  const setup = sessions.filter((s) => groupOf(s.task) === 'setup' && s.agent !== 'gone');
  const list = waiting(sessions);
  const all = list.length;
  const gone = list.filter((a) => a.gone).length;
  const setupWaiting = list.filter((a) => groupOf(a.task) === 'setup').length;
  const el = document.createElement('div');
  el.className = 'page';
  el.innerHTML = '<header class="top"><h1>Factory</h1><div class="tabs" role="tablist" aria-label="Views">'
    + `${TABS.map((t) => `<button role="tab" data-tab="${t}" aria-selected="${t === tab}">${t}</button>`).join('')}</div>`
    + `${auto === null ? '' : `<button class="toggle" data-act="auto" aria-pressed="${auto}" title="${AUTO}">Auto answer</button>`}`
    + `${mute === null ? '' : `<button class="toggle" data-act="mute" aria-pressed="${mute}" title="${MUTE}">Mute sound</button>`}`
    + `<button class="btn counter ${all ? 'primary' : ''}" data-act="next" ${all ? '' : 'disabled'}>${all ? `${all} to answer` : 'All answered'}${gone ? `<small>, ${gone} whose session ended</small>` : ''}</button></header>`
    + `<button class="strip" data-drawer="setup"><b>Setup</b>${setup.map((s) => `<span class="chip" data-session="${esc(s.sid)}" title="session ${esc(s.sid)}">${esc(setupLabel(s))}</span>`).join('')}`
    + `${setupWaiting ? `<span class="chip warn">${setupWaiting} to answer</span>` : ''}</button>`;
  return el;
}

/** The New request box: a request with its priority, P2 unless picked, or a question or research over none or more of
 * the registered `keys` with a branch when one is picked, that Send (`data-act="intake"`) posts to the CEO as a free
 * message; without a CEO session it names the command that starts one and takes nothing. `note` is the outcome of
 * the last send. */
function intakeBox(ceo, note, keys) {
  const off = ceo ? '' : ' disabled';
  const kinds = [['request', 'Request'], ['question', 'Question'], ['research', 'Research']];
  const target = intake.kind === 'request'
    ? `<select data-intake-prio aria-label="Priority"${off}>${['P0', 'P1', 'P2', 'P3'].map((p) => `<option${p === intake.priority ? ' selected' : ''}>${p}</option>`).join('')}</select>`
    : `<fieldset class="intake-repos"><legend>Repositories, none for the org</legend>${keys.map((k) => `<label><input type="checkbox" data-act="intake-repo" value="${esc(k)}"${intake.repos.includes(k) ? ' checked' : ''}${off}> ${esc(k)}</label>`).join('')}`
      + `<input type="text" data-intake-branch aria-label="Branch" placeholder="Branch, with one repository" value="${esc(intake.branch)}"${intake.repos.length === 1 ? off : ' disabled'}></fieldset>`;
  return '<section class="tab-body" data-intake aria-label="New request"><h3>New request</h3>'
    + (ceo ? '' : '<p class="muted">No CEO session runs, so no request goes out from here. Start one in the state directory: '
      + '<code>claude \'/claude-factory:factory ceo\'</code></p>')
    + `<div class="edit"><select data-act="intake-kind" aria-label="Kind"${off}>${kinds.map(([v, l]) => `<option value="${v}"${v === intake.kind ? ' selected' : ''}>${l}</option>`).join('')}</select>`
    + `<textarea rows="2" aria-label="The request"${off}>${esc(intake.text)}</textarea>${target}`
    + `<button class="btn primary" data-act="intake"${off}>Send</button></div>`
    + (note ? `<p class="${note.error ? 'bad' : 'muted'}">${esc(note.text)}</p>` : '')
    + '</section>';
}

/**
 * The Pipeline tab: the filter bar with the sessions in use, the grid of tasks across the five phases of the solve
 * steps and the New request box under it, above it while there is no task. The tasks of each request of
 * `/api/requests` sit under one header row with its priority, status and destination on one line, each task with its
 * repo chip, priority and live sessions, its blocks folded into one line until unfolded or searched, and the step its
 * session reports marked `aria-current="step"`.
 */
export function renderPipeline(board, sessions, requests = [], capacity = null, ceo = null, note = null, keys = []) {
  const ids = new Set(board.map((t) => t.id));
  const all = board.filter((t) => groupOf(t.id) === t.id || !ids.has(groupOf(t.id)));
  const blocksOf = (t) => board.filter((b) => b !== t && groupOf(b.id) === t.id && t.id === groupOf(t.id));
  const q = view.q.trim().toLowerCase();
  const hit = (t) => [t.id, t.goal, t.repo, t.request].some((v) => v && v.toLowerCase().includes(q));
  const finished = all.filter((t) => FINISHED.has(t.status)).length;
  const repos = [...new Set(all.map((t) => t.repo).filter(Boolean))].sort();
  const roots = all.filter((t) => (view.finished || !FINISHED.has(t.status)) && (!view.repo || t.repo === view.repo)
    && (!q || hit(t) || blocksOf(t).some(hit)));
  const groups = byRequest(roots, requests);
  const heads = groups.some(([k]) => k);
  const bodies = groups.map(([k, ts]) => `<tbody>${heads ? requestRow(k, requests.find((r) => r.id === k)) : ''}${ts.map((t) => {
    const shown = Boolean(q) || view.open.has(t.id);
    return taskRow(t, sessions, blocksOf(t), shown) + (shown ? blocksOf(t).map((b) => blockRow(b, t.id, sessions)).join('') : '');
  }).join('')}</tbody>`);
  const filter = all.length ? '<div class="grid-bar">'
    + `<input type="search" data-act="find" aria-label="Search tasks" placeholder="Search tasks" value="${esc(view.q)}">`
    + (repos.length > 1 ? `<select data-act="repo" aria-label="Repository"><option value="">All repositories</option>`
      + `${repos.map((r) => `<option${r === view.repo ? ' selected' : ''}>${esc(r)}</option>`).join('')}</select>` : '')
    + `<label><input type="checkbox" data-act="finished"${view.finished ? ' checked' : ''}> Show done and closed (${finished})</label>`
    + `${capacity?.sessions ? capacityStrip({ sessions: capacity.sessions }) : ''}</div>` : '';
  const el = document.createElement('div');
  el.className = 'pipeline';
  // why: with tasks the grid comes first, so on a phone it starts right under the header; an empty grid points to the box
  const box = intakeBox(ceo, note, keys);
  el.innerHTML = (all.length ? '' : box) + filter
    + `<div class="grid-wrap"><table><thead><tr><th class="task">Task</th><th>Prio</th>${PHASES.map(([name, steps]) => `<th title="${steps
      .map((n) => `${n} ${STEPS.find(([m]) => m === n)[1]}`).join(', ')}">${name}</th>`).join('')}</tr></thead>`
    + `${bodies.join('') || `<tbody><tr><td colspan="${PHASES.length + 2}" class="muted">${all.length ? 'No task matches.' : 'No tasks yet. Start one with New request above.'}</td></tr></tbody>`}</table></div>${all.length ? box : ''}`;
  el.addEventListener('input', (e) => {
    if (e.target.matches('[data-intake] textarea')) intake.text = e.target.value;
    if (e.target.matches('[data-intake-prio]')) intake.priority = e.target.value;
    if (e.target.matches('[data-intake-branch]')) intake.branch = e.target.value;
  });
  return el;
}
