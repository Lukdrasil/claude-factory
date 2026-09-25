import { esc } from './ask-card.js';
import { when } from './org.js';
import { renderRepos } from './repos.js';

/** The machine checklist and the registered repos, read from GET /api/setup: one row per key line of repos.yml. */
export function renderSetupStrip(setup) {
  const ok = setup.reposYml != null;
  const keys = (setup.reposYml || '').match(/^[A-Za-z0-9_-]+(?=:)/gm) || [];
  const toolsets = new Set(setup.toolsets.map((t) => t.repo));
  const el = document.createElement('span');
  el.className = 'setup';
  el.innerHTML = `<span class="chip ${ok ? 'ok' : 'warn'}" data-check="state" data-ok="${ok}">${ok ? 'State repo found' : 'No state repo: run factory init'}</span>`
    + `<span class="muted">${esc(setup.root)}</span>`
    + keys.map((k) => `<span class="chip ${toolsets.has(k) ? 'ok' : 'warn'}" data-repo="${esc(k)}" data-toolset="${toolsets.has(k)}">`
      + `${esc(k)}${toolsets.has(k) ? '' : ' · no toolset'}</span>`).join('');
  return el;
}

const STATE = { done: 'ok', missing: 'warn', failing: 'bad' };

/**
 * The Setup tab: the Repositories section of repos.js over `sessions`, the `ceoSession` it sends to and the `note` of its
 * last send, then the steps of `<ui home>/setup/doctor.json` in its order, each done, missing or failing with its
 * detail and, unless done, its fix, then Start the CEO with the fix of the `ceo` step. Nothing here writes: every fix
 * runs in a terminal or through the confirm ask of the session running init, add-repo or doctor.
 */
export function renderSetupTab(setup, sessions = [], ceoSession = null, note = null) {
  const steps = setup.steps || [];
  const el = document.createElement('section');
  el.className = 'tab-body';
  el.dataset.setupTab = '';
  if (!steps.length) {
    el.innerHTML = '<p class="muted">No doctor report yet. init, add-repo and doctor write it: run <code>/claude-factory:factory doctor</code> in a terminal.</p>';
    el.prepend(renderRepos(setup, sessions, ceoSession, note));
    return el;
  }
  const count = (s) => steps.filter((x) => x.id !== 'doctor' && x.state === s).length; // why: the doctor step sums the others
  const ceo = steps.find((s) => s.id === 'ceo');
  const before = steps.filter((s) => s.id !== 'ceo' && s.id !== 'doctor' && s.state !== 'done').length;
  el.innerHTML = `<p class="muted">doctor.json of ${when(setup.doctorAt) || 'an unknown time'}: `
    + `<span class="chip ok">${count('done')} done</span><span class="chip warn">${count('missing')} missing</span><span class="chip bad">${count('failing')} failing</span></p>`
    + `<ol class="steps" data-steps>${steps.map((s, i) => `<li class="${esc(s.state)}" data-step="${esc(s.id)}" data-state="${esc(s.state)}"><span class="sn">${i + 1}</span>`
      + `<div><b>${esc(s.id)}</b><span class="dt">${esc(s.detail)}</span>${s.state !== 'done' && s.fix ? `<span class="fix">fix: <code>${esc(s.fix)}</code></span>` : ''}</div>`
      + `<span class="chip ${STATE[s.state] || ''}">${esc(s.state)}</span></li>`).join('')}</ol>`
    + (ceo ? `<div class="startbox" data-start-ceo><h3>Start the CEO</h3>${ceo.state === 'done' ? '<p>The CEO runs.</p>'
      : `${before ? `<p class="muted">${before} step${before > 1 ? 's' : ''} above ${before > 1 ? 'are' : 'is'} not done yet.</p>` : ''}<p><code>${esc(ceo.fix)}</code></p>`}</div>` : '');
  el.prepend(renderRepos(setup, sessions, ceoSession, note));
  return el;
}
