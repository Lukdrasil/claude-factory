import { esc, renderAsk } from './ask-card.js';

const EMPTY = { items: {}, editing: {}, drafts: {} };
const RAIL = [['3', 'triage'], ['4', 'grill'], ['5', 'plan-check'], ['6', 'decompose'], ['8', 'cut check'], ['9', 'approve'],
  ['10', 'worktree'], ['11', 'blocks'], ['12', 'acceptance'], ['12b', 'duplication'], ['13', 'review'], ['14', 'MR'],
  ['15', 'self-report'], ['16', 'knowledge review'], ['', 'done']];

export const section = (text, head) => {
  const m = (text || '').match(new RegExp(`^## ${head}[^\\n]*\\n([\\s\\S]*?)(?=^## |(?![\\s\\S]))`, 'm'));
  return m ? m[1].trim() : '';
};

const stepOf = (s) => (s.step.match(/^Step (\w+) of 16/) || [])[1];
const gateOf = (a) => (a.flow === 'done' ? 'done' : a.flow === 'approve' || /^Step 9 of 16/.test(a.step) ? 'approve' : null);
const pre = (t) => (t ? `<pre>${esc(t)}</pre>` : '<p class="muted">Nothing yet.</p>');
const panel = (name, title, html) => `<section data-panel="${name}"><h3>${title}</h3>${html}</section>`;
const mrLink = (t) => (/^https?:\/\//.test(t.fields.mr_url || '') ? `<li><a href="${esc(t.fields.mr_url)}">${esc(t.task.id)}</a></li>` : '');

function rail(task) {
  const id = task.task.id;
  const now = Math.max(-1, ...task.sessions.filter((s) => s.task === id)
    .map((s) => RAIL.findIndex(([n]) => n && n === stepOf(s))));
  return `<nav aria-label="Solve steps of ${esc(id)}"><ol class="rail">${RAIL.map(([n, label], i) =>
    `<li${i === now ? ' aria-current="step"' : ''}>${n ? `${n} ` : ''}${label}</li>`).join('')}</ol></nav>`;
}

function blockList(blocks) {
  return blocks.length
    ? `<ul>${blocks.map((b) => `<li><span class="id">${esc(b.task.id)}</span> <span class="chip">${esc(b.task.status)}</span> ${esc(b.task.goal)}</li>`).join('')}</ul>`
    : '<p class="muted">No blocks.</p>';
}

/**
 * The step rail of a solve task, current at the step its session reports, and one `[data-panel]` per step from
 * triage to done. `task` is its `/api/tasks/{id}` detail with `blockDetails`, `sessions`, `asks` and `staged`; an
 * approve or done ask is a confirm inside its panel.
 */
export function renderTaskPanels(task) {
  const f = task.fields;
  const blocks = task.blockDetails;
  const grill = task.grill || task.plan;
  const mrs = [task, ...blocks].map(mrLink).join('');
  const el = document.createElement('div');
  el.className = 'panels';
  el.innerHTML = rail(task)
    + panel('triage', 'Triage', `<p><span class="chip">${esc(f.tier)}</span> <span class="chip">${esc(f.archetype)}</span> <span class="chip">${esc(f.complexity)}</span></p>${pre(section(task.body, 'Context'))}`)
    + panel('grill', 'Grill', pre(['Terms', 'Program design', 'Gap ledger'].map((h) => section(grill, h)).filter(Boolean).join('\n\n')))
    + panel('decompose', 'Decompose', blockList(blocks) + pre(section(task.progress, 'Wave plan')) + pre(section(task.verdicts, 'cut-check')))
    + panel('approve', 'Approve', pre(task.body) + blockList(blocks))
    + panel('blocks', 'Blocks', blockList(blocks))
    + panel('verdicts', 'Verify and review', blocks.map((b) => `<h4>${esc(b.task.id)}</h4>${pre(section(b.progress, 'Evidence'))}`).join('')
      + `<h4>Review</h4>${pre(section(task.progress, 'Review'))}`)
    + panel('mr', 'MRs', mrs ? `<ul>${mrs}</ul>` : '<p class="muted">No MR yet.</p>')
    + panel('done', 'Done', `<p><span class="chip">${esc(task.task.status)}</span></p>`);
  for (const name of ['approve', 'done']) {
    el.querySelector(`[data-panel="${name}"]`)
      .append(...task.asks.filter((a) => gateOf(a) === name).map((a) => renderAsk(a, task.staged[`${a.sid}/${a.ask}`] || EMPTY)));
  }
  return el;
}
