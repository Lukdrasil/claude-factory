// The browser half of tests/ui-multisession.test.sh, run by node in the Playwright container against BASE with TOKEN,
// the UI home mounted at UI. Every check prints one PASS or FAIL line; the exit code is 1 when any failed.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const { BASE, TOKEN, UI } = process.env;
let failed = 0;

async function check(what, fn) {
  try {
    await fn();
    console.log(`PASS ${what}`);
  } catch (e) {
    failed = 1;
    console.log(`FAIL ${what}: ${String((e && e.message) || e).split('\n').slice(0, 4).join(' | ')}`);
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

function answers(sid) {
  const dir = path.join(UI, 'sessions', sid, 'answers');
  return fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => !f.startsWith('.')).sort() : [];
}

function holds(text, items) {
  for (const item of items) {
    const hit = item instanceof RegExp ? item.test(text) : text.includes(item);
    ok(hit, `no ${item} in: ${text.slice(0, 500)}`);
  }
}

function lacks(text, items) {
  for (const item of items) {
    const hit = item instanceof RegExp ? item.test(text) : text.includes(item);
    ok(!hit, `${item} in: ${text.slice(0, 500)}`);
  }
}

const drawer = (page) => page.getByRole('complementary');
const wave = (page) => drawer(page).locator('[data-panel="wave"]');
const row = (page, id) => wave(page).locator(`[data-block="${id}"]`);

async function rowText(page, id) {
  return until(`the wave row of ${id}`, async () => (await row(page, id).count()) === 1 && row(page, id).innerText());
}

(async () => {
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1400, height: 900 } })).newPage();
  page.setDefaultTimeout(3000);

  await check('the page module /wave.js exports renderWave', async () => {
    await page.goto(`${BASE}/`);
    const kind = await page.evaluate(async () => typeof (await import('/wave.js').catch(() => ({}))).renderWave);
    ok(kind === 'function', `typeof: ${kind}`);
  });

  await page.goto('about:blank');
  await page.goto(`${BASE}/#${TOKEN}`);
  await until('the row of T-030', () => page.locator('table tr', { hasText: 'T-030' }).first().isVisible());
  await page.locator('table tr', { hasText: 'T-030' }).first().getByText('T-030', { exact: true }).first().click();
  await until('the drawer of T-030', () => drawer(page).getByText('T-030').first().isVisible());

  await check('the drawer of T-030 has a wave panel with one row per block', async () => {
    await until('the wave panel', async () => (await wave(page).count()) === 1);
    for (const id of ['T-030-01', 'T-030-02', 'T-030-03', 'T-030-04']) await rowText(page, id);
  });

  await check('T-030-01 shows its worker sw1 working, phase implement, and a link to its MR', async () => {
    holds(await rowText(page, 'T-030-01'), ['sw1', /\bworking\b/i, /\bimplement\b/i]);
    const href = await row(page, 'T-030-01').locator('a[href="https://example.invalid/mr/301"]').count();
    ok(href === 1, `MR links: ${href}`);
  });

  await check('T-030-02 shows its worker sw2 idle, phase tests, and no MR link', async () => {
    holds(await rowText(page, 'T-030-02'), ['sw2', /\bidle\b/i, /\btests\b/i]);
    ok((await row(page, 'T-030-02').locator('a[href^="https://example.invalid/mr/"]').count()) === 0, 'an MR link');
  });

  await check('T-030-03 shows its worker sw3 at a dialog with its pane w3:p3 to answer in', async () => {
    holds(await rowText(page, 'T-030-03'), ['sw3', /at a dialog/i, 'w3:p3']);
  });

  await check('the row of the worker at a dialog offers no path to answer the dialog', async () => {
    await rowText(page, 'T-030-03');
    ok((await row(page, 'T-030-03').locator('textarea').count()) === 0, 'a textarea');
    ok((await row(page, 'T-030-03').getByRole('button', { name: /send/i }).count()) === 0, 'a Send button');
  });

  await check('only the worker at a dialog reads at a dialog', async () => {
    for (const id of ['T-030-01', 'T-030-02', 'T-030-04']) lacks(await rowText(page, id), [/at a dialog/i]);
  });

  await check('T-030-04 shows its worker sw4 gone, since its pane is not in herdr', async () => {
    holds(await rowText(page, 'T-030-04'), ['sw4', /\bgone\b/i]);
  });

  await check('each worker is in the row of its own block only, and the monitor sm in none', async () => {
    const texts = {};
    for (const id of ['T-030-01', 'T-030-02', 'T-030-03', 'T-030-04']) texts[id] = await rowText(page, id);
    for (const [id, text] of Object.entries(texts)) {
      const others = ['sw1', 'sw2', 'sw3', 'sw4'].filter((s) => s !== `sw${id.slice(-1)}`);
      lacks(text, [...others.map((s) => new RegExp(`\\b${s}\\b`)), /\bsm\b/]);
    }
  });

  await check('the open ask of worker sw2 is in the drawer of T-030 and its Send answers sw2 alone', async () => {
    const c = drawer(page).locator('[data-ask="sw2/wq1"]');
    await until('sw2/wq1 in the drawer', () => c.isVisible());
    await c.getByRole('button', { name: /^A\b/ }).first().click();
    await c.getByRole('button', { name: /send/i }).click();
    const files = await until('an answer file for wq1', () => {
      const f = answers('sw2').filter((n) => /^\d+-wq1\.txt$/.test(n));
      return f.length && f;
    });
    const text = fs.readFileSync(path.join(UI, 'sessions', 'sw2', 'answers', files[0]), 'utf8');
    ok(text === 'Q1 A', `file: ${JSON.stringify(text)}`);
    for (const sid of ['sw1', 'sw3', 'sw4', 'sm']) ok(answers(sid).length === 0, `answers of ${sid}: ${answers(sid)}`);
  });

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
