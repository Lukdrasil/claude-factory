import { esc, renderAsk } from './ask-card.js';
import { renderTaskPanels } from './task-panels.js';
import { renderBlockedQuestion } from './blocked.js';
import { renderVisual } from './visual.js';
import { renderWave } from './wave.js';

const EMPTY = { items: {}, editing: {}, drafts: {} };

function context(group) {
  const t = group.task;
  let h = t
    ? `<p><span class="chip">${esc(t.status)}</span> <span class="chip">${esc(t.archetype)}</span> <span class="chip">${esc(t.tier)}</span> <span class="muted">owner ${esc(t.owner)}</span></p><p>${esc(t.goal)}</p>`
    : '';
  if (group.blocks.length) {
    h += `<h3>Blocks</h3><ul>${group.blocks.map((b) => `<li><span class="id">${esc(b.id)}</span> <span class="chip">${esc(b.status)}</span> ${esc(b.goal)}</li>`).join('')}</ul>`;
  }
  h += `<h3>Sessions</h3>${group.sessions.length
    ? `<ul>${group.sessions.map((s) => `<li><span class="id">${esc(s.sid)}</span> ${esc(s.flow)} · ${esc(s.step)} · ${s.pane ? `pane ${esc(s.pane)}` : 'outside herdr'}</li>`).join('')}</ul>`
    : '<p class="muted">No session is working on this task.</p>'}`;
  return h;
}

/**
 * The drawer of one task or of setup. With an open ask it is in decision mode: the asks first, then the blocked
 * question, wave, panels, visuals and context in one collapsed "Task details". Without one, all of it in a column.
 */
export function renderDrawer(group) {
  const setup = group.id === 'setup';
  const decide = group.asks.some((a) => a.status === 'open');
  const el = document.createElement('aside');
  el.setAttribute('aria-label', setup ? 'Setup' : group.id);
  if (decide) el.className = 'decide';
  el.innerHTML = `<header class="drawer-h"><h2>${setup ? 'Setup' : `${esc(group.id)}${group.task ? ` · ${esc(group.task.goal)}` : ''}`}</h2>`
    + '<button class="btn sm" data-act="close">Close</button></header><div class="asks"></div>'
    + `${decide ? '<details class="details"><summary>Task details</summary>' : ''}<div class="context">${context(group)}</div>${decide ? '</details>' : ''}`;
  const asks = el.querySelector('.asks');
  const ctx = el.querySelector('.context');
  if (group.detail) {
    const task = { ...group.detail, sessions: group.sessions };
    ctx.before(...[renderBlockedQuestion(task, group.sessions), renderWave(task, group.allSessions), renderTaskPanels(task)].filter(Boolean));
  }
  ctx.before(...group.sessions.filter((s) => s.visual).map((s) => renderVisual({
    ...s.visual,
    sid: s.sid,
    token: group.token,
    ask: s.asks.filter((a) => a.status === 'open').sort((a, b) => Date.parse(b.modified) - Date.parse(a.modified))[0]?.ask,
  })));
  asks.append(...group.asks.map((a) => renderAsk(a, group.staged[`${a.sid}/${a.ask}`] || EMPTY)));
  if (!group.asks.length) asks.innerHTML = '<p class="muted">No open questions for this task.</p>';
  return el;
}
