import { esc, renderAsk } from './ask-card.js';
import { renderTaskPanels } from './task-panels.js';
import { renderBlockedQuestion } from './blocked.js';

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
    : '<p class="muted">No session.</p>'}`;
  return h;
}

/** The drawer of one task or of setup: its open asks first, then a task's blocked question and solve panels, then its context. */
export function renderDrawer(group) {
  const setup = group.id === 'setup';
  const el = document.createElement('aside');
  el.setAttribute('aria-label', setup ? 'Machine setup' : group.id);
  el.innerHTML = `<header class="drawer-h"><h2>${setup ? 'Machine setup' : `${esc(group.id)}${group.task ? ` · ${esc(group.task.goal)}` : ''}`}</h2>`
    + '<button class="btn sm" data-act="close">Close</button></header><div class="asks"></div>'
    + `<div class="context">${context(group)}</div>`;
  const asks = el.querySelector('.asks');
  const inPanels = new Set();
  if (group.detail) {
    const task = { ...group.detail, sessions: group.sessions, asks: group.asks, staged: group.staged };
    const panels = renderTaskPanels(task);
    panels.querySelectorAll('[data-ask]').forEach((a) => inPanels.add(a.dataset.ask));
    asks.after(...[renderBlockedQuestion(task, group.sessions), panels].filter(Boolean));
  }
  const top = group.asks.filter((a) => !inPanels.has(`${a.sid}/${a.ask}`));
  asks.append(...top.map((a) => renderAsk(a, group.staged[`${a.sid}/${a.ask}`] || EMPTY)));
  if (!top.length) asks.innerHTML = '<p class="muted">Nothing waits on you here.</p>';
  return el;
}
