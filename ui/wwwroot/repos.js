import { esc } from './ask-card.js';
import { when } from './org.js';

/** The add form's draft, the priority picked per report and the reports opened, kept across the page's re-renders. */
export const repoForm = { open: false, url: '', alias: '', prio: {}, reports: new Set() };

const USERINFO = 'Remove the user or token: the factory clones with your own git login, and the URL is stored in the state repo.';
const REPORT_HEAD = 'An onboarding session reports and proposes; it changes nothing. Send a proposal as a request to have a lead do it.';
const CHIP = { done: 'ok', missing: 'warn', failing: 'bad' };

/** The repository key of a URL: its last path segment without `.git`, as factory-add-repo.sh derives it. */
export const keyOf = (url) => url.trim().replace(/\/+$/, '').split(/[/:]/).pop().replace(/\.git$/, '');

/** Why the page will not send this URL, or '' when it will: the charset and forms of factory-add-repo.sh, no leading
 * `-`, no user or token in an http(s) URL, and a key the scripts accept. The script checks again; this is for the human. */
export function urlProblem(url) {
  if (!url) return '';
  if (url.startsWith('-')) return 'The URL must not start with -.';
  if (!/^[A-Za-z0-9._~:/@+-]+$/.test(url)) return 'The URL may hold only letters, digits and . _ ~ : / @ + -, no spaces or quotes.';
  if (!/^(?:(?:https?|ssh):\/\/[^/]+\/.+|[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:.+)$/.test(url)) return 'Use an https://, http://, ssh:// or user@host:path URL.';
  if (/^https?:\/\/[^/]*@/.test(url)) return USERINFO;
  if (!/^[A-Za-z0-9_-]+$/.test(keyOf(url))) return 'The URL must end in the repository name: letters, digits, _ and -.';
  return '';
}

export const aliasProblem = (alias) =>
  !alias || /^[A-Z]{2,4}$/.test(alias) ? '' : 'The alias is 2 to 4 capital letters, like DEM, or empty for the one the CEO proposes.';

/** C1: the line Send posts to the CEO. */
export const addRepoLine = (form) => `add repo ${form.url.trim()}${form.alias ? ` alias ${form.alias}` : ''}`;

export const onboardLine = (key) => `onboard repo ${key}`;

/** C1: a proposal of the report of `key` as the intake line of the New request box. */
export const proposalLine = (key, p, priority) => `request: ${key}: ${p.text} (onboarding ${p.id}), priority ${priority}`;

const keysOf = (reposYml) => (reposYml || '').match(/^[A-Za-z0-9_-]+(?=:)/gm) || [];
const openAsk = (sessions, id) => sessions.some((s) => (s.asks || []).some((a) => a.ask === id && a.status === 'open'));
const onboarding = (sessions, key) => sessions.some((s) => s.agent !== 'gone' && (s.step.match(/^Onboarding ([A-Za-z0-9_-]+)$/) || [])[1] === key);

/**
 * The one state of a repository's row, from `/api/setup` and the asks and sessions the page has: `confirm` while the
 * CEO's ask `add-repo-<key>` is open, `unconfirmed` for a pending add-repo file without it, `cloning`, `running` while a
 * live session reports `Onboarding <key>`, `waits` while the notice `add-repo-<key>-wait` is open, `ended` for a report
 * still running with no such session, `report` for a done or failed one, else `none`, or `unregistered` for a key
 * repos.yml lacks. A failed add-repo file is no state: it is `failed`, the banner above the row.
 */
export function repoRowState(key, setup, sessions) {
  const json = (setup.addRepos || []).find((a) => a.key === key);
  const report = (setup.onboarding || []).find((o) => o.repo === key);
  const registered = keysOf(setup.reposYml).includes(key) || json?.state === 'registered';
  const failed = json?.state === 'failed' ? json : null;
  const state = openAsk(sessions, `add-repo-${key}`) ? 'confirm'
    : json?.state === 'pending' ? 'unconfirmed'
      : json?.state === 'cloning' ? 'cloning'
        : !registered ? 'unregistered'
          : onboarding(sessions, key) ? 'running'
            : openAsk(sessions, `add-repo-${key}-wait`) ? 'waits'
              : report?.status === 'running' ? 'ended'
                : report?.status === 'done' || report?.status === 'failed' ? 'report'
                  : 'none';
  return { state, json, report, failed };
}

function reportBody(key, report, off) {
  const prio = repoForm.prio[key] || 'P3';
  const summary = report.summaryHtml ? `<div class="md">${report.summaryHtml}</div>` : '';
  // why: a failed report's summary is the reason it failed, so it shows without opening the report
  return (report.status === 'failed' ? summary : '')
    + `<details data-report="${esc(key)}"${repoForm.reports.has(key) ? ' open' : ''}><summary>Report</summary>`
    + `<p class="muted">${REPORT_HEAD}</p>`
    + (report.status === 'failed' ? '' : summary)
    + (report.checks.length ? `<ol class="steps" data-checks>${report.checks.map((c, i) => `<li class="${esc(c.state)}" data-check-id="${esc(c.id)}" data-state="${esc(c.state)}"><span class="sn">${i + 1}</span>`
      + `<div><strong>${esc(c.id)}</strong><span class="dt">${esc(c.detail)}</span>${c.fix ? `<span class="fix">fix: <code>${esc(c.fix)}</code></span>` : ''}</div>`
      + `<span class="chip ${CHIP[c.state] || ''}">${esc(c.state)}</span></li>`).join('')}</ol>` : '')
    + (report.proposals.length ? '<div class="proposals"><h4>Proposals</h4>'
      + `<label class="muted">Priority of a request <select data-k="prio" data-key="${esc(key)}"${off}>${['P0', 'P1', 'P2', 'P3'].map((p) => `<option${p === prio ? ' selected' : ''}>${p}</option>`).join('')}</select></label>`
      + `<ul>${report.proposals.map((p) => `<li data-proposal="${esc(p.id)}"><span class="chip">${esc(p.id)}</span><code>${esc(p.area)}</code> ${esc(p.text)} `
        + `<button class="btn sm" data-act="propose" data-key="${esc(key)}" data-id="${esc(p.id)}"${off}>Make it a request</button></li>`).join('')}</ul></div>` : '')
    + '</details>';
}

function repoRow(key, setup, sessions, off) {
  const { state, json, report, failed } = repoRowState(key, setup, sessions);
  const start = (name) => `<button class="btn sm" data-act="onboard" data-key="${esc(key)}"${off}>${name}</button>`;
  const count = (s) => report.checks.filter((c) => c.state === s).length;
  const line = {
    confirm: () => `<span class="chip warn">Waiting for your confirm</span><button class="btn sm" data-drawer="setup"${off}>Open the confirm</button>`,
    unconfirmed: () => '<span class="chip warn">Not confirmed. Send again.</span>',
    cloning: () => `<span class="chip accent">Cloning since ${when(json.at)}</span>`,
    unregistered: () => '<span class="chip">Not registered</span>',
    running: () => '<span class="chip accent">Onboarding runs</span>',
    waits: () => `<span class="chip warn">Onboarding waits for a free session</span>${start('Start onboarding')}`,
    ended: () => `<span class="chip bad">Onboarding ended without a report</span>${start('Start again')}`,
    report: () => `<span class="chip ${report.status === 'done' ? 'ok' : 'bad'}">${report.status === 'done' ? 'Onboarded' : 'Onboarding failed'}</span>`
      + `<span class="muted">${when(report.at)}</span><span class="chip ok">${count('done')} done</span><span class="chip warn">${count('missing')} missing</span>`
      + `<span class="chip bad">${count('failing')} failing</span>${start('Run again')}`,
    none: () => `<span class="chip">Not onboarded</span>${start('Start onboarding')}`,
  }[state]();
  return `<li class="repo-row" data-repo-row="${esc(key)}" data-state="${state}">`
    + (failed ? `<p class="bad" data-failed>Adding ${esc(key)} failed: ${esc(failed.detail)}. Fix it and send again.</p>` : '')
    + `<div class="repo-line"><strong>${esc(key)}</strong>${line}</div>`
    + (state === 'report' ? reportBody(key, report, off) : '')
    + '</li>';
}

/** The problem shown under the form and whether Send is off, from the draft. */
function formCheck() {
  const problem = urlProblem(repoForm.url.trim()) || aliasProblem(repoForm.alias);
  const key = repoForm.url.trim() && !problem ? keyOf(repoForm.url) : '';
  return { problem, key, off: !repoForm.url.trim() || !!problem };
}

function form(off) {
  const { problem, key, off: noSend } = formCheck();
  return '<div class="repo-form" data-repo-form>'
    + `<label>Repository URL <input type="text" data-k="url" value="${esc(repoForm.url)}" placeholder="https://host/group/name.git" spellcheck="false" autocomplete="off"${off}></label>`
    + `<label>Alias (optional) <input type="text" data-k="alias" value="${esc(repoForm.alias)}" placeholder="DEM" spellcheck="false" autocomplete="off"${off}></label>`
    + `<button class="btn primary" data-act="add-repo"${off || (noSend ? ' disabled' : '')}>Send</button>`
    + `<p class="bad" data-problem aria-live="polite">${esc(problem)}</p>`
    + `<p class="muted" data-key-line>${key ? `key: ${esc(key)}, clones into the clones directory (the confirm shows the path)` : ''}</p>`
    + '</div>';
}

/**
 * The Setup tab's Repositories section: Add repository and its form, whose Send (`data-act="add-repo"`) posts the C1
 * `add repo` line to the CEO, then one row per repos.yml key and per key only an add-repo file names, each in its
 * `repoRowState`, with Start onboarding, Start again and Run again (`data-act="onboard"`) and a report's Make it a
 * request (`data-act="propose"`). Without a CEO session every button is off. Check lines are text; only the summary is
 * the server's rendered markdown. `note` is the outcome of the last send.
 */
export function renderRepos(setup, sessions, ceo, note) {
  const off = ceo ? '' : ' disabled';
  const keys = [...new Set([...keysOf(setup.reposYml), ...(setup.addRepos || []).map((a) => a.key).filter(Boolean)])];
  const el = document.createElement('section');
  el.className = 'repos';
  el.dataset.repos = '';
  el.innerHTML = `<header class="repos-head"><h3>Repositories</h3><button class="btn sm" data-act="add-repo-form" aria-expanded="${repoForm.open && !!ceo}"${off}>Add repository</button></header>`
    + (ceo ? '' : '<p class="muted">No CEO session runs, so nothing goes out from here. Start one in the state directory: '
      + '<code>claude \'/claude-factory:factory ceo\'</code></p>')
    + (repoForm.open && ceo ? form(off) : '')
    + (note ? `<p class="${note.error ? 'bad' : 'muted'}">${esc(note.text)}</p>` : '')
    + (keys.length ? `<ul class="repo-rows">${keys.map((k) => repoRow(k, setup, sessions, off)).join('')}</ul>` : '<p class="muted">No repository registered yet.</p>');
  el.addEventListener('input', (e) => {
    const k = e.target.dataset.k;
    if (k === 'prio') repoForm.prio[e.target.dataset.key] = e.target.value;
    if (k !== 'url' && k !== 'alias') return;
    repoForm[k] = e.target.value;
    // why: typing re-renders nothing, so the problem, the key line and Send follow the draft in place
    const { problem, key, off: noSend } = formCheck();
    el.querySelector('[data-problem]').textContent = problem;
    el.querySelector('[data-key-line]').textContent = key ? `key: ${key}, clones into the clones directory (the confirm shows the path)` : '';
    el.querySelector('[data-act="add-repo"]').disabled = noSend;
  });
  el.addEventListener('toggle', (e) => {
    const key = e.target.dataset?.report;
    if (key === undefined) return;
    if (e.target.open) repoForm.reports.add(key);
    else repoForm.reports.delete(key);
  }, true);
  return el;
}
