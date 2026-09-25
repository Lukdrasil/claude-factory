// The browser half of tests/ui-setup.test.sh, run by node in the Playwright container against BASE with TOKEN, the UI
// home mounted at UI, once per PHASE: fixture, bare (only /ui, no factory root yet) and state (the state repo
// factory-init.sh made, mounted at STATE). Every check prints one PASS or FAIL line; the exit code is 1 when any failed.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const { PHASE, BASE, TOKEN, PRINTED, UI, STATE, ROOT } = process.env;
let failed = 0;

async function check(what, fn) {
  try {
    await fn();
    console.log(`PASS ${PHASE}: ${what}`);
  } catch (e) {
    failed = 1;
    console.log(`FAIL ${PHASE}: ${what}: ${String((e && e.message) || e).split('\n').slice(0, 4).join(' | ')}`);
  }
}

function ok(cond, why) {
  if (!cond) throw new Error(why);
}

async function until(what, fn, ms = 5000) {
  const end = Date.now() + ms;
  let last;
  for (;;) {
    try {
      last = await fn();
      if (last) return last;
    } catch (e) {
      last = e.message;
    }
    if (Date.now() > end) throw new Error(`${what} not within ${ms} ms (last: ${String(last).slice(0, 300)})`);
    await new Promise((r) => setTimeout(r, 50));
  }
}

function answer(sid, file) {
  const f = path.join(UI, 'sessions', sid, 'answers', file);
  return fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : null;
}

const card = (page, id) => page.locator(`[data-ask="${id}"]`);
const drawer = (page) => page.getByRole('complementary');
const stateCheck = (page) => page.locator('[data-check="state"]').first();
const repoRow = (page, key) => page.locator(`[data-repo="${key}"]`).first();

async function fresh(page, url = `${BASE}/#${TOKEN}`) {
  await page.goto('about:blank');
  await page.goto(url);
}

async function openSetup(page) {
  await page.locator('[data-drawer="setup"]').first().click();
  await until('the setup drawer', async () => /setup/i.test(await drawer(page).getAttribute('aria-label')));
}

async function repoKeys(page) {
  return page.locator('[data-repo]').evaluateAll((els) => els.map((e) => e.dataset.repo).sort());
}

async function render(page, setup) {
  return page.evaluate(async (setup) => {
    const { renderSetupStrip } = await import('/setup.js');
    const el = renderSetupStrip(setup);
    if (!(el instanceof Element)) return { error: `renderSetupStrip returned ${typeof el}, not an Element` };
    const state = el.querySelector('[data-check="state"]') || (el.matches('[data-check="state"]') ? el : null);
    return {
      state: state && state.dataset.ok,
      repos: [...el.querySelectorAll('[data-repo]')].map((r) => `${r.dataset.repo}=${r.dataset.toolset}`).sort(),
      text: el.textContent,
      bold: [...el.querySelectorAll('b')].map((b) => b.textContent),
    };
  }, setup);
}

async function fixture(page) {
  await check('setup.js exports renderSetupStrip', async () => {
    await fresh(page, `${BASE}/`);
    const kind = await page.evaluate(async () => typeof (await import('/setup.js')).renderSetupStrip);
    ok(kind === 'function', `typeof: ${kind}`);
  });

  await check('with no repos.yml the strip marks the state repo missing, lists no repo and shows the root as text', async () => {
    const r = await render(page, { root: '/home/me/<b>x</b>', reposYml: null, toolsets: [], doctorNotice: null });
    ok(!r.error, r.error);
    ok(r.state === 'false', `data-check="state" data-ok: ${r.state}`);
    ok(r.repos.length === 0, `repos: ${r.repos.join(' ')}`);
    ok(r.text.includes('/home/me/<b>x</b>'), `no root in: ${r.text}`);
    ok(!r.bold.includes('x'), 'the root was rendered as markup');
  });

  await check('with a repos.yml the strip lists every key line with its toolset, never a commented example', async () => {
    const r = await render(page, {
      root: '/home/me/factory',
      reposYml: '# registry of product repos\n# my-repo: {url: "https://github.com/acme/my-repo.git"}\n\n'
        + 'demo: {url: "https://example.invalid/acme/demo.git", default_branch: main, path: "/d"}\nother:\n  path: /o\n',
      toolsets: [{ repo: 'demo', text: '---\nstack: dotnet\n---\n' }],
      doctorNotice: null,
    });
    ok(!r.error, r.error);
    ok(r.state === 'true', `data-check="state" data-ok: ${r.state}`);
    ok(r.repos.join(' ') === 'demo=true other=false', `repos: ${r.repos.join(' ')}`);
  });

  await check('the URL ui-up.sh printed opens the pipeline without an error', async () => {
    await fresh(page, PRINTED);
    await until('the row of T-001 or an error', async () =>
      (await page.locator('.error').count()) || page.locator('table tr', { hasText: 'T-001' }).first().isVisible());
    const errors = await page.locator('.error').allInnerTexts();
    ok(!errors.length, `${PRINTED}: ${errors.join(' | ')}`);
  });

  await fresh(page);
  await check('the strip on the pipeline page shows the state repo and claude-factory without a toolset', async () => {
    await until('the state check', () => stateCheck(page).isVisible());
    ok((await stateCheck(page).getAttribute('data-ok')) === 'true', 'the state repo is marked missing');
    await until('the row of claude-factory', () => repoRow(page, 'claude-factory').isVisible());
    ok((await repoRow(page, 'claude-factory').getAttribute('data-toolset')) === 'false', 'claude-factory has a toolset');
  });

  await check('the init confirm in the setup drawer heads with its step and 1 question, stays a confirm and shows the printed diff in a pre block', async () => {
    await openSetup(page);
    const c = card(page, 's-init/apply');
    await until('s-init/apply in the drawer', () => c.isVisible());
    const head = await c.locator('header').first().innerText();
    ok(head.includes('init: confirm the diff') && /\b1 question\b/.test(head), `header: ${head}`);
    ok(!(await c.getByRole('button', { name: /compare options|decide later/i }).count()), 'not a confirm');
    const pre = await c.locator('pre').allInnerTexts().catch(() => []);
    const text = pre.join('\n');
    ok(text.split('\n').includes(`+ git init -b main ${ROOT}/state`), `no git init line in the pre blocks: ${text.slice(0, 300)}`);
    ok(text.split('\n').includes('+ui: docker'), `no +ui: docker line in the pre blocks: ${text.slice(0, 300)}`);
  });

  await check('yes on the init confirm writes the answer Q1 A', async () => {
    const c = card(page, 's-init/apply');
    await c.locator('[data-act="pick"][data-k="A"]').click();
    await c.getByRole('button', { name: /^send answer$/i }).click();
    const got = await until('the answer file', () => answer('s-init', '1-apply.txt'));
    ok(got === 'Q1 A', `answer: ${got}`);
  });

  await check('the doctor round heads with its step and 2 questions and sends Q1 A and Q2 B one per line', async () => {
    const c = card(page, 's-doctor/tools');
    await until('s-doctor/tools in the drawer', () => c.isVisible());
    const head = await c.locator('header').first().innerText();
    ok(head.includes('doctor: offer the fixes') && /\b2 questions\b/.test(head), `header: ${head}`);
    await c.locator('[data-q="Q1"] [data-act="pick"][data-k="A"]').click();
    await c.locator('[data-q="Q2"] [data-act="pick"][data-k="B"]').click();
    await c.getByRole('button', { name: /^send answers$/i }).click();
    const got = await until('the answer file', () => answer('s-doctor', '1-tools.txt'));
    ok(got === 'Q1 A\nQ2 B', `answer: ${JSON.stringify(got)}`);
  });

  await tabs(page);
}

// --- the Setup and Memory tabs against the wave-2 shapes of /api/setup and /api/org, answered by the browser ------
const STEPS = [
  { id: 'git', state: 'done', detail: 'git 2.47.0', fix: '' },
  { id: 'herdr', state: 'failing', detail: 'herdr 0.8.1 is older than 0.8.2', fix: 'update herdr to 0.8.2 or later' },
  { id: 'prompt-suggestion', state: 'missing', detail: 'promptSuggestionEnabled is not false', fix: 'set promptSuggestionEnabled: false in the Claude settings' },
  { id: 'repo:ecs:alias', state: 'done', detail: 'alias ECS', fix: '' },
  { id: 'doctor', state: 'failing', detail: '1 failing and 2 missing', fix: 'fix the failing steps first, then rerun doctor' },
  { id: 'ceo', state: 'missing', detail: 'the CEO is not running', fix: "open a herdr tab in /home/me/factory/state and run: claude '/claude-factory:factory ceo'" },
];
const PASSES = [
  { scope: 'global', daily: '2026-09-24T06:00:00Z', weekly: 'never', due: 'none' },
  { scope: 'repo-agent:ecs/implementer', daily: 'never', weekly: '2026-09-19T07:30:00Z', due: 'both' },
];
const CEO = { sid: 's-ceo', pane: 'w1:p3' };

async function withTab(context, name, setup, ceo) { // a new page with setup merged into /api/setup and ceo in /api/org
  const p = await context.newPage();
  const posted = [];
  await p.route('**/api/setup', async (r) => {
    const res = await r.fetch();
    await r.fulfill({ response: res, json: { ...(await res.json()), ...setup } });
  });
  await p.route('**/api/org', (r) => r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ capacity: { sessions: { used: 0, cap: 10 }, roles: [] }, leases: [], leads: [], ceo }) }));
  await p.route('**/api/answers/**', (r) => {
    const q = r.request();
    posted.push({ path: new URL(q.url()).pathname, body: q.postDataJSON(), token: q.headers()['x-factory-token'] });
    return r.fulfill({ status: 201, contentType: 'application/json', body: '{"file":"1-x.txt"}' });
  });
  await fresh(p);
  await until(`the ${name} tab`, () => p.getByRole('tab', { name }).isVisible());
  await p.getByRole('tab', { name }).click();
  return { p, posted };
}

async function tabs(page) {
  const context = page.context();
  const full = { steps: STEPS, doctorAt: '2026-09-24T21:40:00Z', passes: PASSES };

  await check('the Setup tab lists the doctor steps in doctor.json order, each with its state', async () => {
    const { p } = await withTab(context, 'Setup', full, CEO);
    const got = await until('the steps', async () => {
      const s = await p.locator('[data-steps] [data-step]').evaluateAll((li) => li.map((l) => `${l.dataset.step}=${l.dataset.state}`));
      return s.length && s;
    }).finally(() => p.close());
    ok(got.join(' ') === 'git=done herdr=failing prompt-suggestion=missing repo:ecs:alias=done doctor=failing ceo=missing', `steps: ${got.join(' ')}`);
  });

  await check('each missing or failing step shows its detail and its fix, a done step no fix, and the time of doctor.json shows', async () => {
    const { p } = await withTab(context, 'Setup', full, CEO);
    await until('the steps', () => p.locator('[data-steps] [data-step="herdr"]').isVisible());
    const herdr = await p.locator('[data-step="herdr"]').innerText();
    const git = await p.locator('[data-step="git"]').innerText();
    const text = await p.locator('[data-setup-tab]').innerText();
    await p.close();
    for (const s of ['herdr 0.8.1 is older than 0.8.2', 'update herdr to 0.8.2 or later', 'failing']) ok(herdr.includes(s), `no ${s} in: ${herdr}`);
    ok(git.includes('git 2.47.0') && !/fix/i.test(git), `git: ${git}`);
    ok(text.includes('2026-09-24'), `no doctor.json time in: ${text.slice(0, 300)}`);
  });

  await check('the Setup header counts the real steps as doctor does, not its doctor step: 2 done, 2 missing, 1 failing', async () => {
    const { p } = await withTab(context, 'Setup', full, CEO);
    const head = await until('the counts', async () => {
      const t = await p.locator('[data-setup-tab] > p').first().innerText();
      return /done/.test(t) && t;
    }).finally(() => p.close());
    for (const s of ['2 done', '2 missing', '1 failing']) ok(head.includes(s), `no ${s} in: ${head}`);
  });

  await check('the Setup tab offers Start the CEO with the command of the ceo step in a code element', async () => {
    const { p } = await withTab(context, 'Setup', full, null);
    const box = p.locator('[data-start-ceo]');
    await until('Start the CEO', () => box.isVisible());
    const text = await box.innerText();
    const code = await box.locator('code').allInnerTexts();
    await p.close();
    ok(/Start the CEO/.test(text), `box: ${text}`);
    ok(code.some((c) => c.includes("claude '/claude-factory:factory ceo'")), `code: ${code.join(' | ')}`);
  });

  await check('with no doctor.json the Setup tab says doctor writes it and lists no step', async () => {
    const { p } = await withTab(context, 'Setup', { steps: [], doctorAt: '', passes: [] }, null);
    const text = await until('the setup tab', async () => p.locator('[data-setup-tab]').innerText());
    const n = await p.locator('[data-step]').count();
    await p.close();
    ok(/No doctor report yet/.test(text), `setup: ${text.slice(0, 300)}`);
    ok(n === 0, `${n} steps`);
  });

  await check('the Memory tab lists every scope with its last daily and weekly pass, never included', async () => {
    const { p } = await withTab(context, 'Memory', full, CEO);
    const rows = await until('the pass rows', async () => {
      const r = await p.locator('[data-passes] tbody tr').evaluateAll((trs) => trs.map((tr) => [...tr.cells].map((td) => td.textContent.trim()).join(' | ')));
      return r.length && r;
    }).finally(() => p.close());
    ok(rows.length === 2, `rows: ${rows.join(' | ')}`);
    ok(/^global\b/.test(rows[0]) && rows[0].includes('2026-09-24') && rows[0].includes('never'), `global: ${rows[0]}`);
    ok(rows[1].includes('repo-agent:ecs/implementer') && rows[1].includes('never') && rows[1].includes('2026-09-19'), `row 2: ${rows[1]}`);
  });

  await check('the Memory tab shows next to the dates which pass is due: daily and weekly for implementer, none for global', async () => {
    const { p } = await withTab(context, 'Memory', full, CEO);
    const got = await until('the pass rows', async () => {
      const r = await p.locator('[data-passes]').evaluate((t) => [...t.rows].map((tr) => [...tr.cells].slice(0, 4).map((c) => c.textContent.trim()).join(' | ')));
      return r.length === 3 && r;
    }).finally(() => p.close());
    ok(got[0] === 'Scope | Last daily | Last weekly | Due', `head: ${got[0]}`);
    ok(got[1].endsWith('| -'), `global: ${got[1]}`);
    ok(got[2].endsWith('| daily and weekly'), `implementer: ${got[2]}`);
  });

  await check('a scope whose first daily pass is due, with no passes.yml yet, reads never twice, due daily, and starts from its row', async () => {
    const { p, posted } = await withTab(context, 'Memory', { ...full, passes: [...PASSES, { scope: 'repo-agent:ecs/scout', daily: 'never', weekly: 'never', due: 'daily' }] }, CEO);
    const row = p.locator('[data-passes] tbody tr', { hasText: 'repo-agent:ecs/scout' });
    await until('the row', () => row.isVisible());
    const cells = await row.locator('td').allInnerTexts();
    await row.getByRole('button', { name: /start daily/i }).click();
    const got = await until('the post', () => posted.length && posted).finally(() => p.close());
    ok(cells.slice(1, 4).map((c) => c.trim()).join(' | ') === 'never | never | daily', `cells: ${cells.join(' | ')}`);
    ok(got[0].body.text === 'start the daily pass for repo-agent:ecs/scout', `post: ${JSON.stringify(got[0])}`);
  });

  await check('Start daily of repo-agent:ecs/implementer posts an empty ask and start the daily pass for repo-agent:ecs/implementer to the CEO sid', async () => {
    const { p, posted } = await withTab(context, 'Memory', full, CEO);
    const row = p.locator('[data-passes] tbody tr', { hasText: 'repo-agent:ecs/implementer' });
    await until('the row', () => row.isVisible());
    await row.getByRole('button', { name: /start daily/i }).click();
    const got = await until('the post', () => posted.length && posted);
    const note = await until('the sent note', async () => {
      const t = await p.locator('[data-memory-tab]').innerText();
      return /Sent to the CEO/.test(t) && t;
    }).finally(() => p.close());
    ok(got.length === 1, `${got.length} posts`);
    ok(got[0].path === '/api/answers/s-ceo', `path: ${got[0].path}`);
    ok(JSON.stringify(got[0].body) === JSON.stringify({ ask: '', text: 'start the daily pass for repo-agent:ecs/implementer' }), `body: ${JSON.stringify(got[0].body)}`);
    ok(got[0].token === TOKEN, 'the post carries no token');
    ok(note.includes('start the daily pass for repo-agent:ecs/implementer'), `note: ${note.slice(0, 300)}`);
  });

  await check('Start weekly of global posts start the weekly pass for global', async () => {
    const { p, posted } = await withTab(context, 'Memory', full, CEO);
    const row = p.locator('[data-passes] tbody tr', { has: p.locator('td:first-child', { hasText: /^\s*global\s*$/ }) });
    await until('the row', () => row.isVisible());
    await row.getByRole('button', { name: /start weekly/i }).click();
    const got = await until('the post', () => posted.length && posted).finally(() => p.close());
    ok(got[0].path === '/api/answers/s-ceo' && got[0].body.text === 'start the weekly pass for global' && got[0].body.ask === '',
      `post: ${JSON.stringify(got[0])}`);
  });

  await check('without a CEO session the Memory tab offers no start button and says the CEO is not running', async () => {
    const { p, posted } = await withTab(context, 'Memory', full, null);
    await until('the pass rows', async () => (await p.locator('[data-passes] tbody tr').count()) === 2);
    const n = await p.locator('[data-memory-tab]').getByRole('button', { name: /start/i }).count();
    const text = await p.locator('[data-memory-tab]').innerText();
    await p.close();
    ok(n === 0, `${n} start buttons`);
    ok(/The CEO is not running/.test(text), `memory: ${text.slice(0, 300)}`);
    ok(!posted.length, 'something was posted');
  });

  await check('the Setup tab over the real server lists the steps of the doctor.json init wrote, in its order and states', async () => {
    const want = JSON.parse(fs.readFileSync(path.join(UI, 'setup', 'doctor.json'), 'utf8')).steps.map((s) => `${s.id}=${s.state}`);
    const p = await context.newPage();
    await fresh(p);
    await until('the Setup tab', () => p.getByRole('tab', { name: 'Setup' }).isVisible());
    await p.getByRole('tab', { name: 'Setup' }).click();
    const got = await until('the steps', async () => {
      const s = await p.locator('[data-steps] [data-step]').evaluateAll((li) => li.map((l) => `${l.dataset.step}=${l.dataset.state}`));
      return s.length && s;
    }).finally(() => p.close());
    ok(want.length > 0, 'doctor.json holds no step');
    ok(got.join(' ') === want.join(' '), `steps: ${got.join(' ')}, doctor.json: ${want.join(' ')}`);
  });

  await check('with /api/setup of a server before the wave-2 fields and no /api/org the Setup and Memory tabs render empty, with no error', async () => {
    const p = await context.newPage();
    await p.route('**/api/setup', async (r) => {
      const res = await r.fetch();
      const { steps, doctorAt, capacity, passes, ...old } = await res.json();
      await r.fulfill({ response: res, json: old });
    });
    await p.route('**/api/org', (r) => r.fulfill({ status: 404, body: '' }));
    await fresh(p);
    await until('the Setup tab', () => p.getByRole('tab', { name: 'Setup' }).isVisible());
    await p.getByRole('tab', { name: 'Setup' }).click();
    const setup = await until('the setup tab', async () => p.locator('[data-setup-tab]').innerText());
    await p.getByRole('tab', { name: 'Memory' }).click();
    const memory = await until('the memory tab', async () => p.locator('[data-memory-tab]').innerText());
    const errors = await p.locator('.error').allInnerTexts();
    await p.close();
    ok(/No doctor report yet/.test(setup), `setup: ${setup.slice(0, 200)}`);
    ok(/No pass dates yet/.test(memory), `memory: ${memory.slice(0, 200)}`);
    ok(!errors.length, `errors: ${errors.join(' | ')}`);
  });
}

async function bare(page) {
  await fresh(page);
  await check('before a factory root exists the strip marks the state repo missing and lists no repo', async () => {
    await until('the state check', () => stateCheck(page).isVisible());
    ok((await stateCheck(page).getAttribute('data-ok')) === 'false', 'the state repo is marked present');
    const keys = await repoKeys(page);
    ok(!keys.length, `repos: ${keys.join(' ')}`);
  });

  await check('the setup drawer still shows the init confirm, now Sent, waiting for the session', async () => {
    await openSetup(page);
    const c = card(page, 's-init/apply');
    await until('s-init/apply in the drawer', () => c.isVisible());
    ok(/Sent, waiting for the session/.test(await c.innerText()), 'not sent');
  });
}

async function state(page) {
  await fresh(page);
  await check('over the new state repo the strip lists demo with its toolset and not the commented my-repo', async () => {
    await until('the state check marked present', async () => (await stateCheck(page).getAttribute('data-ok')) === 'true');
    await until('the row of demo', () => repoRow(page, 'demo').isVisible());
    ok((await repoRow(page, 'demo').getAttribute('data-toolset')) === 'true', 'demo has no toolset');
    const keys = await repoKeys(page);
    ok(keys.join(' ') === 'demo', `repos: ${keys.join(' ')}`);
  });

  await check('a repo registered while the page is open reaches the strip without a reload', async () => {
    fs.appendFileSync(path.join(STATE, 'repos.yml'),
      'late: {url: "https://example.invalid/acme/late.git", default_branch: main, path: "/late"}\n');
    await until('the row of late', () => repoRow(page, 'late').isVisible(), 3000);
    ok((await repoRow(page, 'late').getAttribute('data-toolset')) === 'false', 'late has a toolset');
  });
}

(async () => {
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1400, height: 900 } })).newPage();
  page.setDefaultTimeout(3000);
  await ({ fixture, bare, state })[PHASE](page);
  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL ${PHASE}: the browser run: ${e.message}`);
  process.exit(1);
});
