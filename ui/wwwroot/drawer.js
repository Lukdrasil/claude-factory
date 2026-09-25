import { esc, renderAsk, stateOf } from './ask-card.js';
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

/** The footer of one card sticks, so one Send shows: the first card with a Send not scrolled above the header. */
function pin(el) {
  const top = el.querySelector('.drawer-h').getBoundingClientRect().bottom;
  const live = [...el.querySelectorAll('.ask')].filter((a) => a.querySelector('.ask-f'));
  const at = live.find((a) => a.getBoundingClientRect().bottom > top);
  for (const a of live) a.classList.toggle('pinned', a === at);
}

/**
 * The drawer of one task or of setup. With an open ask it is in decision mode: the asks first, then the blocked
 * question, wave, panels, visuals and context in one collapsed "Task details". Without one, all of it in a column.
 * The open asks come first, the ask the page was sent to (`group.cursor`) is marked current.
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
  const open = (a) => (stateOf(a) === 'open' ? 0 : 1);
  asks.append(...[...group.asks].sort((a, b) => open(a) - open(b)).map((a) => {
    const card = renderAsk(a, group.staged[`${a.sid}/${a.ask}`] || EMPTY);
    if (card.dataset.ask === group.cursor) card.setAttribute('aria-current', 'true');
    return card;
  }));
  asks.querySelector('.ask-f')?.closest('.ask').classList.add('pinned');
  el.addEventListener('scroll', () => pin(el), { passive: true });
  if (!group.asks.length) asks.innerHTML = '<p class="muted">No open questions for this task.</p>';
  return el;
}
