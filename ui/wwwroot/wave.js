import { esc } from './ask-card.js';

const AGENT = { idle: 'Idle', working: 'Working', done: 'Finished its turn', gone: 'Session ended' };
const sidOf = (owner) => (owner.match(/:([A-Za-z0-9-]+)$/) || [])[1];

function worker(block, sessions) {
  if (!sidOf(block.task.owner)) return '<span class="muted">Not started</span>';
  const s = sessions.find((x) => x.sid === sidOf(block.task.owner));
  if (!s) return '<span class="muted">no worker session</span>';
  const agent = s.agent || 'unknown';
  return `<span class="id">${esc(s.sid)}</span> ${agent === 'blocked'
    ? `<span class="chip warn">Waiting at a dialog</span> answer it in herdr pane <span class="id">${esc(s.pane)}</span>`
    : `<span class="chip${agent === 'gone' ? ' bad' : ''}">${esc(AGENT[agent] || agent)}</span>`}`;
}

function row(block, sessions) {
  const { phase, mr_url: mr } = block.fields;
  return `<li data-block="${esc(block.task.id)}"><span class="id">${esc(block.task.id)}</span> <span class="chip">${esc(block.task.status)}</span> `
    + worker(block, sessions)
    + (phase ? ` <span class="chip">phase ${esc(phase)}</span>` : '')
    + (/^https?:\/\//.test(mr || '') ? ` <a href="${esc(mr)}">MR</a>` : '')
    + '</li>';
}

/**
 * The blocks of a herd, one `[data-block]` row each, with the worker session its `owner:` names: that session's
 * liveness as the relay last saw its pane, the block's phase and MR, and the pane of a worker at a dialog to answer
 * in. `task` is a `/api/tasks/{id}` detail with `blockDetails`, `sessions` every session. Null without blocks.
 */
export function renderWave(task, sessions) {
  if (!task.blockDetails.length) return null;
  const el = document.createElement('section');
  el.dataset.panel = 'wave';
  el.innerHTML = `<h3>Wave</h3><ul>${task.blockDetails.map((b) => row(b, sessions)).join('')}</ul>`;
  return el;
}
