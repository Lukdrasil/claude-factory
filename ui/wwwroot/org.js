import { esc } from './ask-card.js';

/** A priority as its chip, `P0` to `P3`; nothing without one. */
export const prio = (p) => (p ? `<span class="prio ${esc(p.toLowerCase())}">${esc(p)}</span>` : '');

/** A UTC stamp of the state repo as `YYYY-MM-DD HH:MM UTC`; `never` and anything else as it is. */
export const when = (s) => esc(String(s || '').replace(/^(\d+-\d+-\d+)T(\d+:\d+).*Z$/, '$1 $2 UTC'));

/** A lease's `at`, the epoch seconds of capacity.sh or an ISO stamp, as local `YYYY-MM-DD HH:MM (<age> ago)`; `-` for none. */
function since(at) {
  const ms = /^\d+$/.test(at || '') ? Number(at) * 1000 : Date.parse(at);
  if (Number.isNaN(ms)) return esc(at || '-');
  const d = new Date(ms);
  const two = (n) => String(n).padStart(2, '0');
  const min = Math.max(0, Math.round((Date.now() - ms) / 60000));
  const age = min < 120 ? `${min} min` : min < 2880 ? `${Math.floor(min / 60)} h` : `${Math.floor(min / 1440)} d`;
  return `<time datetime="${d.toISOString()}">${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())} ${two(d.getHours())}:${two(d.getMinutes())}</time> (${age} ago)`;
}

const HELP = {
  Role: 'The role whose capacity the lease counts against',
  Key: 'The lease name: the task or unit it runs for, or the id of a subagent',
  Unit: 'The herdr unit: the agent of a lead, a step or a block, in a pane of its own',
  Session: 'The Claude session of a subagent; a unit\'s own lease has none, so its unit shows',
  Since: 'When the lease was taken, in local time',
};

/** A table whose headers `heads` carry the title of HELP where it has one. */
const table = (name, heads, rows) => `<div class="scroll-x"><table data-${name}><thead><tr>${heads.map((h) => `<th${HELP[h] ? ` title="${esc(HELP[h])}"` : ''}>${h}</th>`).join('')}</tr></thead>`
  + `<tbody>${rows.map((cells) => `<tr>${cells.map((c) => `<td>${c}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;

/**
 * The capacity in use, one `[data-role]` entry per cap of /api/org or /api/setup `capacity`: `sessions`, then every
 * role in factory.yml order, each `used/cap` with a meter, `used/-` for a role without a cap, `data-full` at its cap.
 */
export function capacityStrip(capacity) {
  const items = [['sessions', capacity.sessions], ...(capacity.roles || []).map((r) => [r.role, r])].filter(([, c]) => c);
  return `<div class="capacity" data-capacity aria-label="Capacity in use">${items.map(([name, c]) => {
    const capped = c.cap != null;
    return `<span class="cap" data-role="${esc(name)}" data-full="${capped && c.used >= c.cap}">${esc(name)} `
      + `${capped ? `<meter min="0" max="${Number(c.cap)}" value="${Number(c.used)}"></meter> ` : ''}${Number(c.used)}/${capped ? Number(c.cap) : '-'}</span>`;
  }).join('')}</div>`;
}

/**
 * The Org tab from `GET /api/org`: the CEO session, the capacity of every role, one row per lead with its task, repo,
 * request, priority and status, and every lease. Null, a server without the route, reads as no data.
 */
export function renderOrg(org) {
  const el = document.createElement('section');
  el.className = 'tab-body';
  el.dataset.org = '';
  if (!org) {
    el.innerHTML = '<p class="muted">No org data from the server yet.</p>';
    return el;
  }
  const leads = org.leads || [];
  const leases = org.leases || [];
  el.innerHTML = `<p data-ceo>${org.ceo
    ? `CEO session <span class="id">${esc(org.ceo.sid)}</span>${org.ceo.pane ? ` in herdr pane <span class="id" title="The herdr pane id, window:pane, of the terminal the CEO runs in">${esc(org.ceo.pane)}</span>` : ''}`
    : 'The CEO is not running. The Setup tab has the command that starts it.'}</p>`
    + `<h3>Capacity</h3>${org.capacity ? capacityStrip(org.capacity) : '<p class="muted">No capacity.</p>'}`
    + `<h3>Leads</h3>${leads.length
      ? table('leads', ['Task', 'Request', 'Prio', 'Status', 'Unit'], leads.map((l) => [
        `<span class="id">${esc(l.task)}</span> ${l.repo ? `<span class="chip repo">${esc(l.repo)}</span>` : ''}`,
        `<span class="id">${esc(l.request)}</span>`, prio(l.priority), esc(l.status), `<span class="id">${esc(l.unit)}</span>`]))
      : '<p class="muted">No lead is running.</p>'}`
    + '<h3>Leases</h3><p class="muted hint">A lease holds one slot of a role\'s capacity while a unit or a subagent runs, and frees it when that ends.</p>'
    + `${leases.length
      ? table('leases', ['Role', 'Key', 'Unit', 'Session', 'Since'], leases.map((l) => [esc(l.role), `<span class="id">${esc(l.key)}</span>`,
        `<span class="id">${esc(l.unit)}</span>`, `<span class="id">${esc(l.session || l.unit || '-')}</span>`, since(l.at)]))
      : '<p class="muted">No lease.</p>'}`;
  return el;
}
