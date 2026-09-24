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
