import { esc } from './ask-card.js';

/** The drawn visual of a prototype ledger row in a sandboxed frame, with its version and out-of-date mark. */
export function renderVisual(visual) {
  const el = document.createElement('section');
  el.className = 'visual';
  el.dataset.visual = visual.sid;
  el.dataset.row = visual.row;
  if (visual.ask) el.dataset.redraw = visual.ask;
  el.innerHTML = `<h3>Drawing for Q${esc(visual.row)} · version ${esc(visual.version)}</h3>`
    + `${visual.status === 'stale' ? '<p class="chip warn">Out of date: an answer changed. Redraw to update.</p>' : ''}`
    + `<button class="btn sm" data-act="redraw"${visual.ask ? '' : ' disabled'}>Redraw</button>`
    + `<iframe sandbox="allow-scripts" title="Drawing for Q${esc(visual.row)}"></iframe>`;
  el.querySelector('iframe').src = `/visual?${new URLSearchParams({ sid: visual.sid, token: visual.token })}`;
  return el;
}
