import { esc } from './ask-card.js';

const STEPS = [[3, 'triage'], [4, 'grill'], [5, 'plan-check'], [6, 'decompose'], [8, 'cut'], [9, 'approve'],
  [10, 'worktree'], [11, 'blocks'], [12, 'acceptance'], [13, 'review'], [14, 'MR'], [15, 'report'], [16, 'knowledge']];

/** The drawer a task id or an ask's task belongs to: the parent task (`T-<n>` or `T-<ALIAS>-<n>`) of a block or
 * step, or setup for none. */
export const groupOf = (task) => (!task || task === 'none' ? 'setup' : (task.match(/^T-(?:[A-Z]{2,4}-)?\d+/) || [task])[0]);

/** The open, unsent asks of live sessions in herdr, oldest first: what the counter counts and walks. */
export function waiting(sessions) {
  return sessions.filter((s) => s.pane && s.agent !== 'gone')
    .flatMap((s) => s.asks.filter((a) => a.status === 'open' && !a.sent).map((a) => ({ ...a, sid: s.sid, pane: s.pane })))
    .sort((a, b) => Date.parse(a.modified) - Date.parse(b.modified));
}

const stepOf = (session) => Number((session.step.match(/^Step (\d+) of 16/) || [])[1]) || 0;
const sessionChip = (s) => `<span class="chip ${s.pane ? 'accent' : ''}" title="${s.pane ? `pane ${esc(s.pane)}` : 'outside herdr'}">${esc(s.sid)}</span>`;

function taskRow(t, sessions) {
  const mine = sessions.filter((s) => groupOf(s.task) === t.id);
  const step = Math.max(0, ...mine.map(stepOf));
  const open = waiting(mine).length;
  const cells = STEPS.map(([n]) => {
    if (n === step) {
      return `<td class="cur" aria-current="step">${open ? `<span class="chip warn">${open} to answer</span>` : ''}${mine.map(sessionChip).join('')}</td>`;
    }
    return t.status === 'done' || n < step ? '<td class="done">✓</td>' : '<td></td>';
  });
  return `<tr><td class="task"><button data-drawer="${esc(t.id)}"><span class="id">${esc(t.id)}</span> <span class="chip">${esc(t.status)}</span>`
    + `<span class="goal">${esc(t.goal)}</span></button></td>${cells.join('')}</tr>`;
}

function blockRow(b, parent, sessions) {
  return `<tr class="sub"><td class="task"><button data-drawer="${esc(parent)}"><span class="id">${esc(b.id)}</span> <span class="chip">${esc(b.status)}</span></button></td>`
    + `<td colspan="${STEPS.length}">${sessions.filter((s) => s.task === b.id).map(sessionChip).join('')} ${esc(b.goal)}</td></tr>`;
}

/**
 * The pipeline page: the to-answer counter, the setup strip, and the grid of tasks across the solve steps with
 * each task's blocks in sub-rows under it and the step its session reports marked current.
 */
export function renderPipeline(board, sessions) {
  const ids = new Set(board.map((t) => t.id));
  const roots = board.filter((t) => groupOf(t.id) === t.id || !ids.has(groupOf(t.id)));
  const setup = sessions.filter((s) => groupOf(s.task) === 'setup');
  const all = waiting(sessions).length;
  const setupWaiting = waiting(setup).length;
  const rows = roots.map((t) => taskRow(t, sessions)
    + board.filter((b) => b !== t && groupOf(b.id) === t.id && t.id === groupOf(t.id)).map((b) => blockRow(b, t.id, sessions)).join(''));
  const el = document.createElement('div');
  el.className = 'page';
  el.innerHTML = `<header class="top"><h1>Factory</h1><button class="btn counter ${all ? 'primary' : ''}" data-act="next" ${all ? '' : 'disabled'}>${all ? `${all} to answer` : 'All answered'}</button></header>`
    + `<button class="strip" data-drawer="setup"><b>Setup</b>${setup.map((s) => `<span class="chip">${esc(s.flow || s.sid)}</span>`).join('')}`
    + `${setupWaiting ? `<span class="chip warn">${setupWaiting} to answer</span>` : ''}</button>`
    + `<div class="grid-wrap"><table><thead><tr><th class="task">Task</th>${STEPS.map(([n, label]) => `<th>${n} <small>${label}</small></th>`).join('')}</tr></thead>`
    + `<tbody>${rows.join('') || `<tr><td colspan="${STEPS.length + 1}" class="muted">No tasks yet. Start one with <code>/claude-factory:factory new</code>.</td></tr>`}</tbody></table></div>`;
  return el;
}
