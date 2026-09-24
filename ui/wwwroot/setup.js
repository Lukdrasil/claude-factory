import { esc } from './ask-card.js';

/** The machine checklist and the registered repos, read from GET /api/setup: one row per key line of repos.yml. */
export function renderSetupStrip(setup) {
  const ok = setup.reposYml != null;
  const keys = (setup.reposYml || '').match(/^[A-Za-z0-9_-]+(?=:)/gm) || [];
  const toolsets = new Set(setup.toolsets.map((t) => t.repo));
  const el = document.createElement('span');
  el.className = 'setup';
  el.innerHTML = `<span class="chip ${ok ? 'ok' : 'warn'}" data-check="state" data-ok="${ok}">${ok ? 'state repo' : 'no state repo'}</span>`
    + `<span class="muted">${esc(setup.root)}</span>`
    + keys.map((k) => `<span class="chip ${toolsets.has(k) ? 'ok' : 'warn'}" data-repo="${esc(k)}" data-toolset="${toolsets.has(k)}">`
      + `${esc(k)}${toolsets.has(k) ? '' : ' · no toolset'}</span>`).join('');
  return el;
}
