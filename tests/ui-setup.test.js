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
  await repos(page);
}

// --- the Repositories section of the Setup tab over fixture addRepos, onboarding reports and sessions --------------
const REPOS_YML = ['demo', 'busy', 'dead', 'plain', 'bad', 'slow']
  .map((k) => `${k}: {url: "https://example.test/g/${k}.git", default_branch: main, path: "/c/${k}"}`).join('\n') + '\n';
const ADD_REPOS = [
  { key: 'waits', url: 'https://example.test/g/waits.git', path: '/c/waits', state: 'pending', detail: '/c/waits', at: '2026-09-25T10:10:00Z' },
  { key: 'nope', url: 'https://example.test/g/nope.git', path: '/c/nope', state: 'pending', detail: '/c/nope', at: '2026-09-25T10:08:00Z' },
  { key: 'copy', url: 'https://example.test/g/copy.git', path: '/c/copy', state: 'cloning', detail: '/c/copy', at: '2026-09-25T10:05:00Z' },
  { key: 'demo', url: 'https://example.test/g/demo.git', path: '/c/demo', state: 'failed', detail: 'alias DEM is taken by <i>other</i>', at: '2026-09-25T10:00:00Z' },
];
const DEMO_REPORT = {
  repo: 'demo', status: 'done', at: '2026-09-25T09:00:00Z', stack: 'dotnet', summaryHtml: '<p>A <strong>dotnet</strong> service.</p>',
  checks: [
    { state: 'done', id: 'registration', detail: 'demo is in repos.yml', fix: '' },
    { state: 'done', id: 'alias', detail: 'alias DEM', fix: '' },
    { state: 'missing', id: 'analyzers', detail: 'no AnalysisLevel', fix: 'run setup-guardrails' },
    { state: 'failing', id: 'ci', detail: '<script>window.pwned = 1</script><img src=x onerror="window.pwned = 2"> never tests', fix: '<b>add</b> a test job' },
  ],
  proposals: [
    { id: 'P1', area: 'analyzers', text: 'set up the analyzers with "warnings as errors"' },
    { id: 'P2', area: 'ci', text: 'run the tests in CI' },
  ],
};
const ONBOARDING = [
  { repo: 'bad', status: 'failed', at: '2026-09-25T08:00:00Z', stack: 'unknown', summaryHtml: '<p>The clone cannot be read.</p>', checks: [], proposals: [] },
  { repo: 'dead', status: 'running', at: '2026-09-25T08:30:00Z', stack: '', summaryHtml: '', checks: [], proposals: [] },
  DEMO_REPORT,
];
const confirmAsk = (id, status, body = 'Clone it?') => ({
  ask: id, task: 'none', flow: 'add-repo', step: 'add-repo: confirm the clone', status, modified: '2026-09-25T10:10:00Z',
  body, sent: false, answer: status === 'open' ? null : 'Q1 B', held: null,
  view: { kind: 'notice', preamble: '<p>Clone it?</p>', questions: [] },
});
const fakeSession = (sid, fields, asks = []) => ({ sid, pane: 'w1:p7', flow: '', task: 'none', step: '', agent: 'idle', asks, visual: null, ...fields });
const SESSIONS = [
  fakeSession('s-ceo', { flow: 'ceo', task: 'ceo', pane: 'w1:p3' }, [confirmAsk('add-repo-waits', 'open'), confirmAsk('add-repo-nope', 'answered'),
    confirmAsk('add-repo-slow-wait', 'open', 'onboarding of slow waits for a free session: press Start onboarding again')]),
  fakeSession('s-busy', { flow: 'onboard', step: 'Onboarding busy', agent: 'working' }),
  fakeSession('s-dead', { flow: 'onboard', step: 'Onboarding dead', agent: 'gone' }),
];
const REPOS_SETUP = () => ({ steps: STEPS, doctorAt: '2026-09-24T21:40:00Z', reposYml: REPOS_YML, addRepos: ADD_REPOS, onboarding: ONBOARDING });

/** A page on the Setup tab with `setup` merged into /api/setup (its `tick` bumped by `poke`, a field given as undefined
 * dropped), the sessions and the CEO given, every post to /api/answers caught. */
async function withRepos(context, setup, ceo, sessions = SESSIONS) {
  const p = await context.newPage();
  const posted = [];
  const live = { ...setup, tick: 0 };
  await p.route('**/api/setup', async (r) => {
    const res = await r.fetch();
    const json = { ...(await res.json()), ...live };
    for (const [k, v] of Object.entries(live)) if (v === undefined) delete json[k];
    await r.fulfill({ response: res, json });
  });
  await p.route('**/api/sessions', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(sessions) }));
  await p.route('**/api/org', (r) => r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ capacity: { sessions: { used: 0, cap: 10 }, roles: [] }, leases: [], leads: [], ceo }) }));
  await p.route('**/api/answers/**', (r) => {
    const q = r.request();
    posted.push({ path: new URL(q.url()).pathname, body: q.postDataJSON() });
    return r.fulfill({ status: 201, contentType: 'application/json', body: '{"file":"1-msg.txt"}' });
  });
  await fresh(p);
  await until('the Setup tab', () => p.getByRole('tab', { name: 'Setup' }).isVisible());
  await p.getByRole('tab', { name: 'Setup' }).click();
  await until('the Repositories section', () => p.locator('[data-repos]').isVisible());
  const poke = () => { // why: a changed /api/setup and a file under /ui make the page fetch and render again
    live.tick += 1;
    fs.writeFileSync(path.join(UI, 'poke'), String(live.tick));
  };
  return { p, posted, poke };
}

const repoSection = (p) => p.locator('[data-repos]');
const row = (p, key) => p.locator(`[data-repo-row="${key}"]`);
const lastPost = async (posted, n = 1) => (await until('the post', () => posted.length >= n && posted))[n - 1];

async function openForm(p) {
  await repoSection(p).getByRole('button', { name: 'Add repository' }).click();
  await until('the form', () => p.locator('[data-repos] input[data-k="url"]').isVisible());
}

async function repos(page) {
  const context = page.context();

  await check('the Repositories section sits above the doctor steps, with Add repository in its header', async () => {
    const { p } = await withRepos(context, REPOS_SETUP(), CEO);
    const order = await p.evaluate(() => {
      const r = document.querySelector('[data-repos]');
      const s = document.querySelector('[data-steps]');
      return !!(r && s && r.compareDocumentPosition(s) & Node.DOCUMENT_POSITION_FOLLOWING);
    });
    const head = await repoSection(p).locator('header').getByRole('button', { name: 'Add repository' }).count();
    const title = await repoSection(p).locator('header').innerText();
    await p.close();
    ok(order, 'the doctor steps come before the Repositories section');
    ok(head === 1, `${head} Add repository buttons in the header`);
    ok(/Repositories/.test(title), `header: ${title}`);
  });

  await check('the section has one row per repos.yml key, then the keys only an add-repo file names', async () => {
    const { p } = await withRepos(context, REPOS_SETUP(), CEO);
    const keys = await p.locator('[data-repo-row]').evaluateAll((els) => els.map((e) => e.dataset.repoRow)).finally(() => p.close());
    ok(keys.join(' ') === 'demo busy dead plain bad slow waits nope copy', `rows: ${keys.join(' ')}`);
  });

  await check('without a CEO session every button of the section is disabled and it names the command that starts the CEO', async () => {
    const { p, posted } = await withRepos(context, REPOS_SETUP(), null);
    await row(p, 'demo').locator('summary').click();
    const buttons = await repoSection(p).locator('button').evaluateAll((bs) => bs.map((b) => `${b.textContent.trim()}=${b.disabled}`));
    const selects = await repoSection(p).locator('select').evaluateAll((ss) => ss.map((s) => s.disabled));
    const text = await repoSection(p).innerText();
    await p.close();
    for (const name of ['Add repository', 'Start onboarding', 'Start again', 'Run again', 'Make it a request']) {
      ok(buttons.some((b) => b.startsWith(`${name}=`)), `no ${name} in: ${buttons.join(' | ')}`);
    }
    ok(buttons.every((b) => b.endsWith('=true')), `enabled: ${buttons.filter((b) => b.endsWith('=false')).join(' | ')}`);
    ok(selects.length && selects.every(Boolean), `selects: ${selects.join(' ')}`);
    ok(text.includes("claude '/claude-factory:factory ceo'"), `section: ${text.slice(0, 300)}`);
    ok(!posted.length, 'something was posted');
  });

  await check('with a CEO session Add repository opens the form with Send disabled until a URL is there', async () => {
    const { p } = await withRepos(context, REPOS_SETUP(), CEO);
    await openForm(p);
    const send = repoSection(p).getByRole('button', { name: 'Send' });
    const before = await send.isDisabled();
    await p.locator('[data-repos] input[data-k="url"]').fill('https://example.test/g/demo.git');
    const after = await send.isDisabled();
    const line = await repoSection(p).innerText();
    await p.close();
    ok(before, 'Send is enabled with no URL');
    ok(!after, 'Send is disabled with a good URL');
    ok(/key: demo\b/.test(line), `no key line in: ${line.slice(0, 400)}`);
  });

  const problems = [
    ['https://me:glpat-x@example.test/g/demo.git', '', /Remove the user or token: the factory clones with your own git login, and the URL is stored in the state repo\./],
    ['https://example.test/g/de mo.git', '', /only letters, digits and \. _ ~ : \/ @ \+ -/],
    ["https://example.test/g/demo.git'; rm -rf ~; '", '', /only letters, digits and \. _ ~ : \/ @ \+ -/],
    ['-uhttps://example.test/g/demo.git', '', /must not start with -/],
    ['ftp://example.test/g/demo.git', '', /Use an https:\/\/, http:\/\/, ssh:\/\/ or user@host:path URL/],
    ['https://example.test/g/my.repo.git', '', /must end in the repository name/],
    ['https://example.test/g/demo.git', 'dem', /The alias is 2 to 4 capital letters/],
    ['https://example.test/g/demo.git', 'DEMOS', /The alias is 2 to 4 capital letters/],
  ];
  for (const [url, alias, want] of problems) {
    await check(`the form refuses ${JSON.stringify(url)}${alias ? ` with alias ${alias}` : ''}: ${want.source.slice(0, 60)}`, async () => {
      const { p, posted } = await withRepos(context, REPOS_SETUP(), CEO);
      await openForm(p);
      await p.locator('[data-repos] input[data-k="url"]').fill(url);
      await p.locator('[data-repos] input[data-k="alias"]').fill(alias);
      const problem = await repoSection(p).locator('[data-problem]').innerText();
      const send = repoSection(p).getByRole('button', { name: 'Send' });
      const off = await send.isDisabled();
      await send.click({ force: true }).catch(() => {});
      await p.waitForTimeout(100);
      await p.close();
      ok(want.test(problem), `problem: ${problem}`);
      ok(off, 'Send is enabled');
      ok(!posted.length, `posted: ${JSON.stringify(posted)}`);
    });
  }

  await check('the form takes ssh://, http:// and user@host:path URLs and names their key', async () => {
    const { p } = await withRepos(context, REPOS_SETUP(), CEO);
    await openForm(p);
    const got = [];
    for (const url of ['ssh://git@example.test/g/one.git', 'http://example.test/g/two', 'git@example.test:g/three.git']) {
      await p.locator('[data-repos] input[data-k="url"]').fill(url);
      got.push(`${await repoSection(p).locator('[data-problem]').innerText()}|${await repoSection(p).getByRole('button', { name: 'Send' }).isDisabled()}`);
    }
    const text = await repoSection(p).innerText();
    await p.close();
    ok(got.join(' ') === '|false |false |false', `problems: ${got.join(' ')}`);
    ok(/key: three\b/.test(text), `no key line: ${text.slice(0, 300)}`);
  });

  await check('Send posts add repo https://example.test/g/demo.git alias DEM as a free message to the CEO sid', async () => {
    const { p, posted } = await withRepos(context, REPOS_SETUP(), CEO);
    await openForm(p);
    await p.locator('[data-repos] input[data-k="url"]').fill('https://example.test/g/demo.git');
    await p.locator('[data-repos] input[data-k="alias"]').fill('DEM');
    await repoSection(p).getByRole('button', { name: 'Send' }).click();
    const got = await lastPost(posted);
    const note = await until('the sent note', async () => {
      const t = await repoSection(p).innerText();
      return /Sent to the CEO/.test(t) && t;
    }).finally(() => p.close());
    ok(got.path === '/api/answers/s-ceo', `path: ${got.path}`);
    ok(JSON.stringify(got.body) === JSON.stringify({ ask: '', text: 'add repo https://example.test/g/demo.git alias DEM' }), `body: ${JSON.stringify(got.body)}`);
    ok(note.includes('It picks it up when it is idle'), `note: ${note.slice(0, 300)}`);
  });

  await check('Send without an alias posts add repo <url> alone', async () => {
    const { p, posted } = await withRepos(context, REPOS_SETUP(), CEO);
    await openForm(p);
    await p.locator('[data-repos] input[data-k="url"]').fill('git@example.test:g/three.git');
    await repoSection(p).getByRole('button', { name: 'Send' }).click();
    const got = await lastPost(posted).finally(() => p.close());
    ok(got.body.text === 'add repo git@example.test:g/three.git', `text: ${got.body.text}`);
  });

  await check('the URL box keeps the focus, its text and its caret across a re-render', async () => {
    const { p, poke } = await withRepos(context, REPOS_SETUP(), CEO);
    await openForm(p);
    const input = p.locator('[data-repos] input[data-k="url"]');
    await input.click();
    await input.pressSequentially('https://example.test/g/de');
    await input.press('ArrowLeft');
    await input.press('ArrowLeft');
    await input.evaluate((el) => { el.dataset.old = ''; });
    poke();
    await until('a re-render', () => p.evaluate(() => !document.querySelector('[data-repos] input[data-old]')));
    const got = await p.evaluate(() => {
      const a = document.activeElement;
      return { k: a.dataset.k, v: a.value, c: a.selectionStart };
    }).finally(() => p.close());
    ok(got.k === 'url' && got.v === 'https://example.test/g/de' && got.c === 23, `focus: ${JSON.stringify(got)}`);
  });

  await check('every row reads its state: confirm, not confirmed, cloning, onboarding runs, waits for a session, ended without a report, report, not onboarded', async () => {
    const { p } = await withRepos(context, REPOS_SETUP(), CEO);
    const got = await p.locator('[data-repo-row]').evaluateAll((els) => els.map((e) => `${e.dataset.repoRow}=${e.dataset.state}`));
    const text = {};
    for (const k of ['waits', 'nope', 'copy', 'busy', 'dead', 'plain', 'bad', 'slow']) text[k] = await row(p, k).innerText();
    await p.close();
    ok(got.join(' ') === 'demo=report busy=running dead=ended plain=none bad=report slow=waits waits=confirm nope=unconfirmed copy=cloning', `states: ${got.join(' ')}`);
    ok(/Waiting for your confirm/.test(text.waits), `waits: ${text.waits}`);
    ok(/Not confirmed\. Send again\./.test(text.nope), `nope: ${text.nope}`);
    ok(/Cloning since 2026-09-25 10:05 UTC/.test(text.copy), `copy: ${text.copy}`);
    ok(/Onboarding runs/.test(text.busy) && !/Start/.test(text.busy), `busy: ${text.busy}`);
    ok(/Onboarding ended without a report/.test(text.dead) && /Start again/.test(text.dead), `dead: ${text.dead}`);
    ok(/Not onboarded/.test(text.plain) && /Start onboarding/.test(text.plain), `plain: ${text.plain}`);
    ok(/failed/i.test(text.bad) && /The clone cannot be read\./.test(text.bad), `bad: ${text.bad}`);
    ok(/Onboarding waits for a free session/.test(text.slow) && /Start onboarding/.test(text.slow), `slow: ${text.slow}`);
  });

  await check('a pending add-repo file with no ask at all reads Not confirmed. Send again.', async () => {
    const { p } = await withRepos(context, REPOS_SETUP(), CEO, [SESSIONS[1]]);
    const got = await row(p, 'waits').getAttribute('data-state');
    const text = await row(p, 'waits').innerText().finally(() => p.close());
    ok(got === 'unconfirmed' && /Not confirmed\. Send again\./.test(text), `waits: ${got} ${text}`);
  });

  await check('Waiting for your confirm opens the setup drawer on the confirm ask', async () => {
    const { p } = await withRepos(context, REPOS_SETUP(), CEO);
    await row(p, 'waits').getByRole('button', { name: /confirm/i }).click();
    await until('the setup drawer', async () => /setup/i.test(await drawer(p).getAttribute('aria-label')));
    const shown = await card(p, 's-ceo/add-repo-waits').isVisible().finally(() => p.close());
    ok(shown, 'the confirm ask is not in the drawer');
  });

  await check('a failed add-repo file is a banner above the report of its row, its detail as text', async () => {
    const { p } = await withRepos(context, REPOS_SETUP(), CEO);
    const r = row(p, 'demo');
    const banner = await r.locator('[data-failed]').innerText();
    const first = await r.evaluate((el) => el.firstElementChild && el.firstElementChild.hasAttribute('data-failed'));
    const italic = await r.locator('[data-failed] i').count();
    const state = await r.getAttribute('data-state');
    const report = await r.locator('[data-report]').count();
    await p.close();
    ok(banner.includes('alias DEM is taken by <i>other</i>'), `banner: ${banner}`);
    ok(first, 'the banner is not the first thing in the row');
    ok(!italic, 'the detail was rendered as markup');
    ok(state === 'report' && report === 1, `state ${state}, ${report} reports`);
  });

  await check('the report shows its counts, summary, checks and proposals, a check line with <script> as text', async () => {
    const { p } = await withRepos(context, REPOS_SETUP(), CEO);
    const r = row(p, 'demo');
    const head = await r.innerText();
    await r.locator('summary').click();
    const checks = await r.locator('[data-check-id]').evaluateAll((li) => li.map((l) => `${l.dataset.checkId}=${l.dataset.state}`));
    const ci = await r.locator('[data-check-id="ci"]').innerText();
    const summary = await r.locator('strong').allInnerTexts();
    const proposals = await r.locator('[data-proposal]').allInnerTexts();
    const report = await r.locator('[data-report]').innerText();
    const injected = await p.evaluate(() => ({ pwned: window.pwned, scripts: document.querySelectorAll('[data-repos] script, [data-repos] img, [data-repos] b').length }));
    await p.close();
    for (const s of ['2 done', '1 missing', '1 failing']) ok(head.includes(s), `no ${s} in: ${head}`);
    ok(checks.join(' ') === 'registration=done alias=done analyzers=missing ci=failing', `checks: ${checks.join(' ')}`);
    ok(ci.includes('<script>window.pwned = 1</script><img src=x onerror="window.pwned = 2"> never tests') && ci.includes('<b>add</b> a test job'), `ci: ${ci}`);
    ok(injected.pwned === undefined && injected.scripts === 0, `injected: ${JSON.stringify(injected)}`);
    ok(summary.includes('dotnet'), `summary: ${summary.join(' | ')}`);
    ok(proposals.length === 2 && proposals[0].includes('set up the analyzers with "warnings as errors"'), `proposals: ${proposals.join(' | ')}`);
    ok(report.includes('An onboarding session reports and proposes; it changes nothing.'), `report: ${report.slice(0, 300)}`);
  });

  await check('Make it a request posts the intake line at P3, then at the priority picked, and the report stays open', async () => {
    const { p, posted } = await withRepos(context, REPOS_SETUP(), CEO);
    const r = row(p, 'demo');
    await r.locator('summary').click();
    await r.locator('[data-proposal="P1"]').getByRole('button', { name: 'Make it a request' }).click();
    const first = await lastPost(posted);
    await r.locator('select').selectOption('P1');
    await r.locator('[data-proposal="P2"]').getByRole('button', { name: 'Make it a request' }).click();
    const second = await lastPost(posted, 2).finally(() => p.close());
    ok(first.path === '/api/answers/s-ceo' && first.body.ask === '', `post: ${JSON.stringify(first)}`);
    ok(first.body.text === 'request: demo: set up the analyzers with "warnings as errors" (onboarding P1), priority P3', `text: ${first.body.text}`);
    ok(second.body.text === 'request: demo: run the tests in CI (onboarding P2), priority P1', `text: ${second.body.text}`);
  });

  for (const [key, name] of [['plain', 'Start onboarding'], ['slow', 'Start onboarding'], ['dead', 'Start again'], ['demo', 'Run again']]) {
    await check(`${name} of ${key} posts onboard repo ${key}`, async () => {
      const { p, posted } = await withRepos(context, REPOS_SETUP(), CEO);
      await row(p, key).getByRole('button', { name }).click();
      const got = await lastPost(posted).finally(() => p.close());
      ok(JSON.stringify(got.body) === JSON.stringify({ ask: '', text: `onboard repo ${key}` }), `body: ${JSON.stringify(got.body)}`);
    });
  }

  await check('with /api/setup of a server before addRepos and onboarding every repos.yml key reads Not onboarded', async () => {
    const { steps, doctorAt, reposYml } = REPOS_SETUP();
    const { p } = await withRepos(context, { steps, doctorAt, reposYml, addRepos: undefined, onboarding: undefined }, CEO);
    const got = await p.locator('[data-repo-row]').evaluateAll((els) => els.map((e) => `${e.dataset.repoRow}=${e.dataset.state}`));
    const errors = await p.locator('.error').allInnerTexts().finally(() => p.close());
    ok(got.join(' ') === 'demo=none busy=running dead=none plain=none bad=none slow=waits', `states: ${got.join(' ')}`);
    ok(!errors.length, `errors: ${errors.join(' | ')}`);
  });
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

  // the Repositories section over the real server: repos/demo/onboarding.md and setup/add-repo/fresh.json as the
  // shell wrote them, and every button writing the CEO's next msg file
  const msgs = () => {
    const dir = path.join(UI, 'sessions', 's-ceo', 'answers');
    return fs.existsSync(dir)
      ? fs.readdirSync(dir).filter((f) => /^\d+-msg\.txt$/.test(f)).sort((a, b) => parseInt(a, 10) - parseInt(b, 10)).map((f) => fs.readFileSync(path.join(dir, f), 'utf8'))
      : [];
  };
  const sent = async (n) => (await until(`msg file ${n}`, () => msgs().length >= n && msgs()))[n - 1];
  await fresh(page);
  await until('the Setup tab', () => page.getByRole('tab', { name: 'Setup' }).isVisible());
  await page.getByRole('tab', { name: 'Setup' }).click();

  await check('over the real server the demo row shows the report of repos/demo/onboarding.md, its check lines as text', async () => {
    const r = row(page, 'demo');
    await until('the demo report', async () => (await r.getAttribute('data-state')) === 'report');
    await r.locator('summary').click();
    const ci = await r.locator('[data-check-id="ci"]').innerText();
    const injected = await page.evaluate(() => ({ pwned: window.pwned, scripts: document.querySelectorAll('[data-repos] script').length }));
    ok(ci.includes('<script>window.pwned = 1</script> never runs dotnet test') && ci.includes('add a test job'), `ci: ${ci}`);
    ok(injected.pwned === undefined && injected.scripts === 0, `injected: ${JSON.stringify(injected)}`);
    ok(/1 done/.test(await r.innerText()), `demo: ${await r.innerText()}`);
  });

  await check('over the real server a pending add-repo file with no confirm ask reads Not confirmed. Send again.', async () => {
    const r = row(page, 'fresh');
    await until('the fresh row', () => r.isVisible());
    ok((await r.getAttribute('data-state')) === 'unconfirmed' && /Not confirmed\. Send again\./.test(await r.innerText()), `fresh: ${await r.innerText()}`);
  });

  await check('Make it a request writes the intake line as the CEO\'s next msg file', async () => {
    const n = msgs().length;
    await row(page, 'demo').locator('[data-proposal="P1"]').getByRole('button', { name: 'Make it a request' }).click();
    const got = await sent(n + 1);
    ok(got === 'request: demo: add a CI job that runs "dotnet test" (onboarding P1), priority P3', `msg: ${got}`);
  });

  await check('Run again writes onboard repo demo as the CEO\'s next msg file', async () => {
    const n = msgs().length;
    await row(page, 'demo').getByRole('button', { name: 'Run again' }).click();
    const got = await sent(n + 1);
    ok(got === 'onboard repo demo', `msg: ${got}`);
  });

  await check('Send of the form writes add repo https://example.test/g/demo.git alias DEM as the CEO\'s next msg file', async () => {
    const n = msgs().length;
    await openForm(page);
    await page.locator('[data-repos] input[data-k="url"]').fill('https://example.test/g/demo.git');
    await page.locator('[data-repos] input[data-k="alias"]').fill('DEM');
    await repoSection(page).getByRole('button', { name: 'Send' }).click();
    const got = await sent(n + 1);
    ok(got === 'add repo https://example.test/g/demo.git alias DEM', `msg: ${got}`);
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
