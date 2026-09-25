import { esc } from './ask-card.js';
import { when } from './org.js';

const DUE = { daily: 'daily', weekly: 'weekly', both: 'daily and weekly' };

/**
 * The Memory tab: every scope of `/api/setup` `passes`, a scope with a `passes.yml` or with work for its first pass,
 * its last daily and weekly pass and the pass it is `due` for, and with a CEO session a start button per pass whose
 * `data-act="pass"` click posts `start the <kind> pass for <scope>` to the CEO; `note` is the outcome of the last one.
 * The page runs no pass itself.
 */
export function renderMemory(passes, ceo, note) {
  const el = document.createElement('section');
  el.className = 'tab-body';
  el.dataset.memoryTab = '';
  const start = (p, kind) => `<button class="btn sm" data-act="pass" data-kind="${kind}" data-scope="${esc(p.scope)}">Start ${kind}</button>`;
  el.innerHTML = (ceo ? '' : '<p class="muted">The CEO is not running, so no pass starts from here. The Setup tab has the command that starts it.</p>')
    + (note ? `<p class="${note.error ? 'bad' : 'muted'}">${esc(note.text)}</p>` : '')
    + (passes.length
      ? `<div class="scroll-x"><table data-passes><thead><tr><th>Scope</th><th>Last daily</th><th>Last weekly</th><th title="The pass that has work and whose last run is 24 h (daily) or 7 d (weekly) old or more">Due</th><th></th></tr></thead><tbody>${passes.map((p) => '<tr>'
        + `<td><code>${esc(p.scope)}</code></td><td>${when(p.daily)}</td><td>${when(p.weekly)}</td><td>${DUE[p.due] ?? '-'}</td><td>${ceo ? `${start(p, 'daily')} ${start(p, 'weekly')}` : ''}</td></tr>`).join('')}</tbody></table></div>`
      : '<p class="muted">No pass dates yet: a scope gets its passes.yml from its first pass.</p>');
  return el;
}
