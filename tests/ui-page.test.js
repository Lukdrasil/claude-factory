// The browser half of tests/ui-page.test.sh, run by node in the Playwright container against BASE with TOKEN,
// the UI home mounted at UI. Every check prints one PASS or FAIL line; the exit code is 1 when any failed.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const { BASE, TOKEN, UI } = process.env;
const origin = new URL(BASE).origin;
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

function writeAtomic(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = path.join(path.dirname(file), `.${path.basename(file)}.tmp`);
  fs.writeFileSync(temp, text);
  fs.renameSync(temp, file);
}

function answers(sid) {
  const dir = path.join(UI, 'sessions', sid, 'answers');
  return fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => !f.startsWith('.')).sort() : [];
}

const card = (page, id) => page.locator(`[data-ask="${id}"]`);
const drawer = (page) => page.getByRole('complementary');
const counter = (page) => page.getByRole('button', { name: /waiting on you/i });
const question = (c, q) => c.locator(`[data-q="${q}"]`);

async function taskRowIds(page) {
  return page.locator('table tr').evaluateAll((rows) =>
    rows.map((r) => (r.textContent.match(/T-\d{3}(?:-\d{2})?/) || [''])[0]).filter(Boolean));
}

async function currentStep(page, id) {
  return page.locator('table').first().evaluate((table, id) => {
    const row = [...table.querySelectorAll('tr')].find(
      (r) => (r.textContent.match(/T-\d{3}(?:-\d{2})?/) || [''])[0] === id);
    if (!row) return `no row for ${id}`;
    const cell = row.querySelector('[aria-current="step"]');
    if (!cell) return `no aria-current="step" cell in the row of ${id}`;
    const head = [...table.querySelectorAll('tr')].find((r) => r.querySelector('th'));
    const index = [...row.children].indexOf(cell);
    return head ? head.children[index].textContent.trim().split(/\s+/)[0] : 'no header row';
  }, id);
}

async function inViewport(locator) {
  return locator.evaluate((el) => {
    const r = el.getBoundingClientRect();
    return r.height > 0 && r.top < innerHeight && r.bottom > 0;
  });
}

async function fresh(page, url = `${BASE}/#${TOKEN}`) {
  await page.goto('about:blank');
  await page.goto(url);
}

async function openTask(page, id) {
  await page.locator('table tr', { hasText: id }).first().getByText(id, { exact: true }).first().click();
  await until(`the drawer of ${id}`, () => drawer(page).getByText(id).first().isVisible());
}

async function stage(q, button, text) {
  await q.getByRole('button', { name: button }).first().click();
  await q.getByRole('textbox').last().fill(text);
  await q.getByRole('button', { name: /stage/i }).last().click();
}

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const page = await context.newPage();
  page.setDefaultTimeout(3000);
  const requests = [];
  page.on('request', (r) => requests.push({ url: r.url(), token: r.headers()['x-factory-token'] }));

  await check('the page modules export renderPipeline, renderAsk and renderDrawer', async () => {
    await fresh(page, `${BASE}/`);
    const kinds = await page.evaluate(async () => [
      typeof (await import('/pipeline.js')).renderPipeline,
      typeof (await import('/ask-card.js')).renderAsk,
      typeof (await import('/drawer.js')).renderDrawer,
    ].join(' '));
    ok(kinds === 'function function function', `typeof: ${kinds}`);
  });

  await check('without the token in the fragment no task is shown', async () => {
    await fresh(page, `${BASE}/`);
    await page.waitForTimeout(1500);
    ok(!(await page.getByText('T-001', { exact: false }).count()), 'T-001 is on the page');
  });

  await fresh(page);
  await check('the grid lists T-001, its block T-001-01 under it, then T-002 and T-003', async () => {
    const ids = await until('four task rows', async () => {
      const ids = await taskRowIds(page);
      return ids.length >= 4 && ids;
    });
    ok(ids.join(' ') === 'T-001 T-001-01 T-002 T-003', `rows: ${ids.join(' ')}`);
  });

  await check('every /api request carries the token from the fragment as X-Factory-Token', async () => {
    const api = requests.filter((r) => new URL(r.url).pathname.startsWith('/api/'));
    ok(api.length > 0, 'no /api request');
    const off = api.filter((r) => r.token !== TOKEN);
    ok(!off.length, `without the token: ${off.map((r) => r.url).join(', ')}`);
  });

  await check('the page loads nothing from any other origin', async () => {
    const foreign = requests.filter((r) => !r.url.startsWith('data:') && new URL(r.url).origin !== origin);
    ok(!foreign.length, foreign.map((r) => r.url).join(', '));
  });

  await check('the row of T-001 marks step 4, the step its session reports, as current', async () => {
    const step = await currentStep(page, 'T-001');
    ok(step === '4', `current: ${step}`);
  });

  await check('the row of T-002 marks step 11 as current', async () => {
    const step = await currentStep(page, 'T-002');
    ok(step === '11', `current: ${step}`);
  });

  await check('the counter shows 4 waiting on you: not the sent q1, not the answered q2, not outside herdr', async () => {
    await until('the counter', () => counter(page).isVisible());
    const text = await counter(page).innerText();
    ok(/(^|\D)4(\D|$)/.test(text), `counter: ${text}`);
  });

  for (const [n, id, group] of [[1, 's4/d1', /setup/i], [2, 's2/r1', /T-002/], [3, 's1/q3', /T-001/], [4, 's2/c1', /T-002/]]) {
    await check(`click ${n} on the counter opens ${id}, the next oldest waiting ask, in its drawer`, async () => {
      await counter(page).click();
      await until(`the drawer of ${group}`, async () => group.test(await drawer(page).innerText()));
      await until(`${id} in the drawer`, () => drawer(page).locator(`[data-ask="${id}"]`).isVisible());
      await until(`${id} scrolled into view`, () => inViewport(card(page, id)));
    });
  }

  await check('the setup strip opens the setup drawer with the doctor notice and no task ask', async () => {
    await fresh(page);
    await page.getByRole('button', { name: /setup/i }).first().click();
    await until('d1 in the drawer', () => drawer(page).locator('[data-ask="s4/d1"]').isVisible());
    ok(!(await drawer(page).locator('[data-ask="s2/r1"]').count()), 'r1 is in the setup drawer');
  });

  await check('the notice renders its text and offers no options, More detail, Explore or Defer', async () => {
    const c = card(page, 's4/d1');
    ok(/Docker is running\. herdr is running\./.test(await c.innerText()), await c.innerText());
    const extra = await c.getByRole('button', { name: /^[A-D]\b|more detail|explore|defer/i }).count();
    ok(extra === 0, `${extra} such buttons`);
  });

  await check('the drawer of T-001 holds its goal and its open asks q1 and q3, not the answered q2', async () => {
    await fresh(page);
    await openTask(page, 'T-001');
    const d = drawer(page);
    ok(await d.getByText('The fixture sentence of state one.').first().isVisible(), 'no goal');
    ok(await d.locator('[data-ask="s1/q1"]').isVisible(), 'no q1');
    ok(await d.locator('[data-ask="s1/q3"]').isVisible(), 'no q3');
    ok(!(await d.locator('[data-ask="s1/q2"]').count()), 'q2 is there');
    ok(!(await d.locator('[data-ask="s4/d1"]').count()), 'the setup notice is there');
  });

  await check('q1, named by an answer file, shows sent, and the relay held reason blocked as a dialog', async () => {
    const text = await card(page, 's1/q1').innerText();
    ok(/\bsent\b/i.test(text), `no sent: ${text}`);
    ok(/dialog/i.test(text), `no dialog: ${text}`);
  });

  await check('the relay held reason gone reaches q1 without a reload', async () => {
    writeAtomic(path.join(UI, 'sessions/s1/relay'), '1 gone\n');
    await until('gone on q1', async () => /\bgone\b/i.test(await card(page, 's1/q1').innerText()), 1500);
  });

  await check('a session outside herdr shows its task state and its ask with no answer box', async () => {
    await fresh(page);
    await openTask(page, 'T-003');
    const d = drawer(page);
    ok(/in_progress/.test(await d.innerText()), 'no task status in the drawer');
    const c = d.locator('[data-ask="s3/o1"]');
    ok(/Which outside answer\?/.test(await c.innerText()), 'the question is not shown');
    ok(!(await c.getByRole('button', { name: /send/i }).count()), 'a Send button');
    ok(!(await c.getByRole('textbox').count()), 'a text box');
    const live = await c.getByRole('button', { name: /^[A-D]\b/ }).evaluateAll((bs) => bs.filter((b) => !b.disabled).length);
    ok(live === 0, `${live} enabled option buttons`);
  });

  let composed = '';
  await check('the round card composes every staged item into the shorthand the relay will type', async () => {
    await fresh(page);
    await openTask(page, 'T-002');
    const c = card(page, 's2/r1');
    await question(c, 'Q1').getByRole('button', { name: /^B\b/ }).click();
    await question(c, 'Q2').getByRole('button', { name: /more detail/i }).click();
    await question(c, 'Q3').getByRole('button', { name: /explore/i }).click();
    await stage(question(c, 'Q4'), /own answer/i, 'cf-ui-fixture');
    await stage(question(c, 'Q5'), /discuss/i, 'why not both');
    await question(c, 'Q6').getByRole('button', { name: /defer/i }).click();
    composed = await c.locator('output').first().innerText();
    for (const item of [/\bQ1 B\b/, /\bQ2 more\b/, /\bexplore Q3\b/, /\bQ4 cf-ui-fixture\b/, /\bQ5\b[^\n,]*why not both/, /\bQ6 defer\b/]) {
      ok(item.test(composed), `no ${item} in: ${composed}`);
    }
  });

  await check('Send writes one answer file for r1 whose text is the composed shorthand byte for byte', async () => {
    ok(composed, 'nothing composed');
    await card(page, 's2/r1').getByRole('button', { name: /send/i }).click();
    const files = await until('an answer file for r1', () => {
      const f = answers('s2').filter((n) => /^\d+-r1\.txt$/.test(n));
      return f.length && f;
    });
    ok(files.length === 1, `files: ${files.join(' ')}`);
    const text = fs.readFileSync(path.join(UI, 'sessions/s2/answers', files[0]), 'utf8');
    ok(text === composed, `file: ${JSON.stringify(text)} composed: ${JSON.stringify(composed)}`);
  });

  await check('r1 shows sent without a reload once its answer file exists', async () => {
    await until('sent on r1', async () => /\bsent\b/i.test(await card(page, 's2/r1').innerText()), 1500);
  });

  await check('r1 shows answered and offers no Send once its session closed it', async () => {
    const file = path.join(UI, 'sessions/s2/asks/r1.md');
    writeAtomic(file, fs.readFileSync(file, 'utf8').replace(/^status: open$/m, 'status: answered'));
    await until('answered on r1', async () => /answered/i.test(await card(page, 's2/r1').innerText()), 1500);
    const live = await card(page, 's2/r1').getByRole('button', { name: /send/i })
      .evaluateAll((bs) => bs.filter((b) => !b.disabled).length);
    ok(live === 0, `${live} enabled Send buttons`);
  });

  await check('the confirm card offers yes and no, no Explore or Defer, and sends Q1 A for yes', async () => {
    const c = card(page, 's2/c1');
    ok(await c.getByRole('button', { name: /\byes\b/i }).count(), 'no yes');
    ok(await c.getByRole('button', { name: /\bno\b/i }).count(), 'no no');
    ok(!(await c.getByRole('button', { name: /explore|defer/i }).count()), 'Explore or Defer on a confirm');
    await c.getByRole('button', { name: /\byes\b/i }).first().click();
    await c.getByRole('button', { name: /send/i }).click();
    const files = await until('an answer file for c1', () => {
      const f = answers('s2').filter((n) => /^\d+-c1\.txt$/.test(n));
      return f.length && f;
    });
    const text = fs.readFileSync(path.join(UI, 'sessions/s2/answers', files[0]), 'utf8');
    ok(text === 'Q1 A', `file: ${JSON.stringify(text)}`);
    await until('sent on c1', async () => /\bsent\b/i.test(await card(page, 's2/c1').innerText()), 1500);
  });

  await check('a new ask raises the counter within 1 s of its write (QS-03)', async () => {
    const before = (await counter(page).innerText()).match(/\d+/);
    ok(before, `no number in the counter: ${await counter(page).innerText()}`);
    const t0 = Date.now();
    writeAtomic(path.join(UI, 'sessions/s2/asks/r2.md'),
      '---\nask: r2\ntask: T-002\nflow: solve\nstep: fixture\nstatus: open\n---\n\n' +
      '❓ **Q1** - **A new question?**: written while the page is open.\n  **A** yes\n  **B** no\n\n➡️ **A**: it is new.\n');
    await until('the counter to rise', async () =>
      (await counter(page).innerText()).includes(String(Number(before[0]) + 1)), 1000);
    console.log(`NOTE the counter rose ${Date.now() - t0} ms after the write`);
  });

  await check('on a narrow screen the grid scrolls sideways in its container and the page does not', async () => {
    await page.setViewportSize({ width: 390, height: 844 });
    await fresh(page);
    await until('the grid', async () => (await taskRowIds(page)).length >= 4);
    const widths = await page.locator('table').first().evaluate((table) => {
      let el = table.parentElement;
      while (el && el !== document.body && !/auto|scroll/.test(getComputedStyle(el).overflowX)) el = el.parentElement;
      const doc = document.documentElement;
      return {
        page: doc.scrollWidth - doc.clientWidth,
        box: el && el !== document.body ? el.scrollWidth - el.clientWidth : -1,
      };
    });
    ok(widths.page <= 0, `the page scrolls sideways by ${widths.page} px`);
    ok(widths.box > 0, `no container scrolls the grid sideways (${widths.box})`);
  });

  await check('on a narrow screen the drawer takes the full width', async () => {
    await openTask(page, 'T-001');
    const box = await drawer(page).evaluate((el) => {
      const r = el.getBoundingClientRect();
      return { left: r.left, right: r.right, width: innerWidth };
    });
    ok(Math.abs(box.left) <= 1 && Math.abs(box.right - box.width) <= 1,
      `the drawer spans ${box.left} to ${box.right} of a ${box.width} px viewport`);
  });

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
