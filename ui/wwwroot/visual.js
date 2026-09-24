import { esc } from './ask-card.js';

/** The drawn visual of a prototype ledger row in a sandboxed frame, with its version and out-of-date mark. */
export function renderVisual(visual) {
  const el = document.createElement('section');
  el.className = 'visual';
  el.dataset.visual = visual.sid;
  el.dataset.row = visual.row;
  if (visual.ask) el.dataset.redraw = visual.ask;
  el.innerHTML = `<h3>Visual · row ${esc(visual.row)} · v${esc(visual.version)}`
    + `${visual.status === 'stale' ? ' <span class="chip warn">out of date</span>' : ''}</h3>`
    + `<button class="btn sm" data-act="redraw"${visual.ask ? '' : ' disabled'}>Redraw</button>`
    + `<iframe sandbox="allow-scripts" title="Visual of row ${esc(visual.row)}"></iframe>`;
  el.querySelector('iframe').src = `/visual?${new URLSearchParams({ sid: visual.sid, token: visual.token })}`;
  return el;
}
