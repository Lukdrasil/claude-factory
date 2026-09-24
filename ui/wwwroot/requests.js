import { esc } from './ask-card.js';
import { prio } from './org.js';

/** The request the Map and Plan tabs show: the one picked, else the newest live one, else the newest; '' for none. */
export const pickRequest = (list, picked) => (list.find((r) => r.id === picked) || list.find((r) => !r.archived) || list[0])?.id || '';

const picker = (list, id) => `<nav class="requests" aria-label="Requests">${list.map((r) => `<button class="btn sm" data-request="${esc(r.id)}" aria-pressed="${r.id === id}">`
  + `<span class="id">${esc(r.id)}</span> ${prio(r.priority)}<span class="chip">${esc(r.status)}</span>${r.archived ? '<span class="chip">archived</span>' : ''}</button>`).join('')}</nav>`;

const dest = (d, entry) => `<div class="dest"><p class="colh"><span class="id">${esc(d.id)}</span> ${prio(entry?.priority)}<span class="chip">${esc(d.status)}</span></p>`
  + `<p>${esc(d.destination)}</p>${d.notes ? `<p class="muted">${esc(d.notes)}</p>` : ''}</div>`;

const lines = (items, none) => (items?.length
  ? `<ul>${items.map((i) => `<li><b>${esc(i.title)}</b>: ${esc(i.gist)}</li>`).join('')}</ul>`
  : `<p class="muted">${none}</p>`);

function ticket(t, frontier) {
  const facts = [t.status === 'claimed' && t.claimedBy ? `claimed by ${esc(t.claimedBy)}` : esc(t.status),
    t.blockedBy?.length ? `blocked by ${t.blockedBy.map(esc).join(', ')}` : '', t.repo ? `repo ${esc(t.repo)}` : ''];
  return `<div class="tk" data-ticket="${esc(t.nn)}"><span class="chip">${esc(t.type)}</span>`
    + `<div><span class="nm"><span class="id">${esc(t.nn)}</span> ${esc(t.title)}</span><span class="ans">${facts.filter(Boolean).join(' · ')}</span></div>`
    + `${frontier.includes(t.nn) ? '<span class="chip accent">frontier</span>' : ''}</div>`;
}

/** The tab of one request: the request list, then `body(detail)` once `/api/requests/{id}` of the one shown is in. */
function tab(name, list, id, detail, body) {
  const el = document.createElement('section');
  el.className = 'tab-body';
  el.dataset[name] = '';
  if (!list.length) {
    el.innerHTML = '<p class="muted">No request yet. Hand one to the CEO.</p>';
    return el;
  }
  el.innerHTML = picker(list, id) + (detail ? body(detail) : `<p class="muted">Nothing of ${esc(id)} from the server yet.</p>`);
  return el;
}

/**
 * The Map tab: the wayfinder map of the request shown, its destination with priority and status, the open and
 * claimed tickets with the frontier marked, the decisions so far, the fog and out of scope.
 */
export function renderMap(list, id, detail) {
  return tab('map', list, id, detail, (d) => dest(d, list.find((r) => r.id === id))
    + '<div class="cols">'
    + `<div data-col="open"><h3>Frontier and open</h3>${(d.tickets || []).filter((t) => t.status === 'open' || t.status === 'claimed')
      .map((t) => ticket(t, d.frontier || [])).join('') || '<p class="muted">No open ticket.</p>'}</div>`
    + `<div data-col="decisions"><h3>Decisions so far</h3>${lines(d.decisions, 'None yet.')}</div>`
    + `<div><div data-col="fog"><h3>Not yet specified</h3>${d.fog ? `<p class="fog">${esc(d.fog)}</p>` : '<p class="muted">Nothing: the map is clear of fog.</p>'}</div>`
    + `<div data-col="out"><h3>Out of scope</h3>${lines(d.outOfScope, 'Nothing.')}</div></div>`
    + `</div>${d.terms ? `<h3>Terms</h3><p class="fog">${esc(d.terms)}</p>` : ''}`);
}

const item = (t, parent) => `<li class="${parent ? 'par' : 'blk'}" data-item="${esc(t.id)}"><span class="box${t.status === 'done' ? ' on' : ''}" aria-hidden="true">${t.status === 'done' ? '✓' : ''}</span>`
  + `<span><span class="id">${esc(t.id)}</span> ${esc(t.goal)}${t.acceptance ? `<span class="acc">${esc(t.acceptance)}</span>` : ''}</span>`
  + `<span>${parent ? prio(t.priority) : ''}<span class="chip">${esc(t.status)}</span></span></li>`;

/**
 * The Plan tab: the final plan of the request shown, its destination, decisions and out of scope, and a read-only
 * checklist of its parents per repo with their blocks, status and acceptance. The approval is the CEO's confirm ask.
 */
export function renderPlan(list, id, detail) {
  return tab('plan', list, id, detail, (d) => {
    const repos = new Map();
    for (const p of d.parents || []) repos.set(p.repo, [...(repos.get(p.repo) || []), p]);
    return dest(d, list.find((r) => r.id === id))
      + '<p class="muted">Read-only: the boxes follow the state repo. You approve this plan in the CEO\'s confirm ask, not here.</p>'
      + `<div class="cols"><div><h3>Decisions</h3>${lines(d.decisions, 'None yet.')}</div><div><h3>Out of scope</h3>${lines(d.outOfScope, 'Nothing.')}</div></div>`
      + `<div data-checklist>${[...repos].map(([repo, ps]) => `<h3 data-plan-repo="${esc(repo)}">${esc(repo)}</h3><ul class="ck">`
        + `${ps.map((p) => item(p, true) + (p.blocks || []).map((b) => item(b, false)).join('')).join('')}</ul>`).join('') || '<p class="muted">No parent yet.</p>'}</div>`;
  });
}
