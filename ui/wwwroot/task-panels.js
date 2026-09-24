import { esc } from './ask-card.js';

const RAIL = [['3', 'triage'], ['4', 'grill'], ['5', 'plan-check'], ['6', 'decompose'], ['8', 'cut check'], ['9', 'approve'],
  ['10', 'worktree'], ['11', 'blocks'], ['12', 'acceptance'], ['12b', 'duplication'], ['13', 'review'], ['14', 'MR'],
  ['15', 'self-report'], ['16', 'knowledge review'], ['', 'done']];

const parse = (html) => {
  const t = document.createElement('template');
  t.innerHTML = html || '';
  return [...t.content.childNodes];
};

/** The nodes under the first `<h2>` of rendered `html` whose text starts with `head`, up to the next `<h2>`. */
export const section = (html, head) => {
  const nodes = parse(html);
  const i = nodes.findIndex((n) => n.nodeName === 'H2' && n.textContent.trim().startsWith(head));
  if (i < 0) return [];
  const end = nodes.findIndex((n, j) => j > i && n.nodeName === 'H2');
  return nodes.slice(i + 1, end < 0 ? undefined : end);
};

const stepOf = (s) => (s.step.match(/^Step (\w+) of 16/) || [])[1];
const md = (nodes) => {
  const d = document.createElement('div');
  d.className = 'md';
  d.append(...nodes);
  return d.textContent.trim() ? d.outerHTML : '<p class="muted">Nothing recorded for this step yet.</p>';
};
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
 * triage to done, each markdown section rendered from `task.html`. `task` is its `/api/tasks/{id}` detail with
 * `blockDetails` and `sessions`.
 */
export function renderTaskPanels(task) {
  const f = task.fields;
  const h = task.html;
  const blocks = task.blockDetails;
  const grill = h.grill || h.plan;
  const mrs = [task, ...blocks].map(mrLink).join('');
  const el = document.createElement('div');
  el.className = 'panels';
  el.innerHTML = rail(task)
    + panel('triage', 'Triage', `<p><span class="chip">${esc(f.tier)}</span> <span class="chip">${esc(f.archetype)}</span> <span class="chip">${esc(f.complexity)}</span></p>${md(section(h.body, 'Context'))}`)
    + panel('grill', 'Grill', md(['Terms', 'Program design', 'Gap ledger'].flatMap((head) => section(grill, head))))
    + panel('decompose', 'Decompose', blockList(blocks) + md(section(h.progress, 'Wave plan')) + md(section(h.verdicts, 'cut-check')))
    + panel('approve', 'Approve', md(parse(h.body)) + blockList(blocks))
    + panel('blocks', 'Blocks', blockList(blocks))
    + panel('verdicts', 'Verify and review', blocks.map((b) => `<h4>${esc(b.task.id)}</h4>${md(section(b.html.progress, 'Evidence'))}`).join('')
      + `<h4>Review</h4>${md(section(h.progress, 'Review'))}`)
    + panel('mr', 'MRs', mrs ? `<ul>${mrs}</ul>` : '<p class="muted">No MR yet.</p>')
    + panel('done', 'Done', `<p><span class="chip">${esc(task.task.status)}</span></p>`);
  return el;
}
