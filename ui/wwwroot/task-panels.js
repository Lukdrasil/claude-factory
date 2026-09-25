import { esc } from './ask-card.js';
import { STEPS, currentStep } from './pipeline.js';

// why: an inline SVG and not a character, so the rail's text stays the grid's labels while a step shows its tick
const TICK = '<svg role="img" aria-label="done" viewBox="0 0 12 12" width="10" height="10"><path d="M2 6.5l2.5 2.5L10 3" fill="none" stroke="currentColor" stroke-width="2"/></svg>';

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

/** A frontmatter value the draft still holds as its template placeholder, `<green|yellow|red>`, or none at all. */
const placeholder = (v) => !v || v === 'null' || v.startsWith('<');
const md = (nodes) => {
  const d = document.createElement('div');
  d.className = 'md';
  d.append(...nodes);
  return d.textContent.trim() ? d.outerHTML : '<p class="muted">Nothing recorded for this step yet.</p>';
};
const panel = (name, title, html) => `<section data-panel="${name}"><h3>${title}</h3>${html}</section>`;
const mrLink = (t) => (/^https?:\/\//.test(t.fields.mr_url || '') ? `<li><a href="${esc(t.fields.mr_url)}">${esc(t.task.id)}</a></li>` : '');

/** The grid's steps with its labels, each ticked only when the state records it done, the step the task's sessions
 * report current apart from that, then the done gate. */
function rail(task) {
  const id = task.task.id;
  const now = currentStep(task.sessions, id);
  const done = new Set(task.task.steps || []);
  const li = (text, title, tick, current) => `<li title="${title}"${tick ? ' class="done"' : ''}${current ? ' aria-current="step"' : ''}>${text}${tick ? TICK : ''}</li>`;
  return `<nav aria-label="Solve steps of ${esc(id)}"><ol class="rail">${STEPS.map(([n, label, title], i) => li(`${n} ${label}`, title, done.has(n), i === now)).join('')}`
    + `${li('done', 'The human merged the task MR', task.task.status === 'done', false)}</ol></nav>`;
}

/** Triage's result: the tier, archetype and complexity it set, or Not triaged yet while the draft's placeholders stand. */
function triaged(f) {
  if (placeholder(f.tier) || placeholder(f.archetype)) return '<p class="muted">Not triaged yet.</p>';
  return `<p>${[f.tier, f.archetype, f.complexity].filter((v) => !placeholder(v)).map((v) => `<span class="chip">${esc(v)}</span>`).join(' ')}</p>`;
}

function blockList(blocks) {
  return blocks.length
    ? `<ul>${blocks.map((b) => `<li><span class="id">${esc(b.task.id)}</span> <span class="chip">${esc(b.task.status)}</span> ${esc(b.task.goal)}</li>`).join('')}</ul>`
    : '<p class="muted">No blocks.</p>';
}

/**
 * The step rail of a solve task, ticked from its recorded steps and current at the step its session reports, and one `[data-panel]` per step from
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
    + panel('triage', 'Triage', `${triaged(f)}${md(section(h.body, 'Context'))}`)
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
