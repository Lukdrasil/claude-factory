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
const counter = (page) => page.locator('[data-act="next"]');
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

async function ticked(page, id) {
  return page.locator('table').first().evaluate((table, id) => {
    const row = [...table.querySelectorAll('tr')].find(
      (r) => (r.textContent.match(/T-\d{3}(?:-\d{2})?/) || [''])[0] === id);
    if (!row) return `no row for ${id}`;
    const head = [...table.querySelectorAll('tr')].find((r) => r.querySelector('th'));
    return [...row.children].map((c, i) => (c.matches('.done') && /✓/.test(c.textContent) ? head.children[i].textContent.trim().split(/\s+/)[0] : ''))
      .filter(Boolean).join(' ');
  }, id);
}

const rowCount = async (page, id) => (await page.locator('table tr', { hasText: id }).first().locator('.chip.warn').allInnerTexts()).join(' ');

async function inViewport(locator) {
  return locator.evaluate((el) => {
    const r = el.getBoundingClientRect();
    return r.height > 0 && r.top < innerHeight && r.bottom > 0;
  });
}

async function exposed(page, selector) {
  return page.evaluate((selector) => {
    const els = [...document.querySelectorAll(selector)];
    if (!els.length) return [`nothing matches ${selector}`];
    return els.map((el) => {
      const r = el.getBoundingClientRect();
      const name = el.textContent.replace(/\s+/g, ' ').trim().slice(0, 40);
      if (!r.height) return `${name}: not laid out`;
      if (r.top < 0 || r.bottom > innerHeight || r.left < 0 || r.right > innerWidth) {
        return `${name}: at ${Math.round(r.top)}..${Math.round(r.bottom)} of a ${innerHeight} px viewport`;
      }
      const hit = document.elementFromPoint(r.left + Math.min(r.width / 2, 20), r.top + r.height / 2);
      return hit && el.contains(hit) ? '' : `${name}: covered by ${hit ? hit.outerHTML.slice(0, 80) : 'nothing'}`;
    }).filter(Boolean);
  }, selector);
}

const details = (page) => drawer(page).locator('details', { has: page.locator('summary', { hasText: /^\s*Task details\s*$/ }) });

async function expand(page) {
  const d = details(page);
  if ((await d.count()) && !(await d.first().evaluate((el) => el.open))) await d.first().locator('summary').first().click();
}

async function fresh(page, url = `${BASE}/#${TOKEN}`) {
  await page.goto('about:blank');
  await page.goto(url);
}

async function openTask(page, id) {
  await page.locator('table tr', { hasText: id }).first().getByText(id, { exact: true }).first().click();
  await until(`the drawer of ${id}`, () => drawer(page).getByText(id).first().isVisible());
  await until(`the panels of ${id}`, async () => (await drawer(page).locator('[data-panel]').count()) > 0);
}

async function stage(q, button, text) {
  await q.getByRole('button', { name: button }).first().click();
  await q.getByRole('textbox').last().fill(text);
  await q.getByRole('button', { name: /add to answer/i }).last().click();
}

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  page.setDefaultTimeout(3000);
  const requests = [];
  page.on('request', (r) => requests.push({ url: r.url(), token: r.headers()['x-factory-token'] }));

  await check('the page modules export renderPipeline, renderAsk, compose and renderDrawer, and no parseAsk', async () => {
    await fresh(page, `${BASE}/`);
    const kinds = await page.evaluate(async () => {
      const card = await import('/ask-card.js');
      return [
        typeof (await import('/pipeline.js')).renderPipeline,
        typeof card.renderAsk,
        typeof card.compose,
        typeof card.parseAsk,
        typeof (await import('/drawer.js')).renderDrawer,
      ].join(' ');
    });
    ok(kinds === 'function function function undefined function', `typeof: ${kinds}`);
  });

  await check('groupOf puts a legacy id, an alias id and a block or step of each under its parent', async () => {
    const got = await page.evaluate(async () => {
      const { groupOf } = await import('/pipeline.js');
      return ['T-264', 'T-264-03', 'T-1000', 'T-1000-01', 'T-ECS-12', 'T-ECS-12-03', 'T-ECS-12-chart', 'none', '']
        .map((id) => `${id}=${groupOf(id)}`).join(' ');
    });
    ok(got === 'T-264=T-264 T-264-03=T-264 T-1000=T-1000 T-1000-01=T-1000 T-ECS-12=T-ECS-12 T-ECS-12-03=T-ECS-12 '
      + 'T-ECS-12-chart=T-ECS-12 none=setup =setup', `groupOf: ${got}`);
  });

  await check('without the token in the fragment no task is shown', async () => {
    await fresh(page, `${BASE}/`);
    await page.waitForTimeout(1500);
    ok(!(await page.getByText('T-001', { exact: false }).count()), 'T-001 is on the page');
  });

  await check('without the token the page reads This page needs its access link. Run ui-up.sh and open the link it prints.', async () => {
    const text = (await page.locator('#app').innerText()).replace(/\s+/g, ' ').trim();
    ok(text === 'This page needs its access link. Run ui-up.sh and open the link it prints.', `page: ${JSON.stringify(text)}`);
  });

  await check('with no task in the state repo the grid reads No tasks yet. Start one with New request above.', async () => {
    const p = await context.newPage();
    await p.route('**/api/board', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: '[]' }));
    await p.goto(`${BASE}/#${TOKEN}`);
    const text = await until('the empty grid', async () => {
      const t = (await p.locator('table tbody').first().innerText()).replace(/\s+/g, ' ').trim();
      return t && t;
    });
    const above = await p.evaluate(() => document.querySelector('[data-intake]').getBoundingClientRect().bottom
      <= document.querySelector('.grid-wrap').getBoundingClientRect().top);
    await p.close();
    ok(text === 'No tasks yet. Start one with New request above.', `grid: ${JSON.stringify(text)}`);
    ok(above, 'the New request box is not above the empty grid');
  });

  await check('at 400x844 with tasks the grid starts within 180 px and the New request box sits below it', async () => {
    const p = await context.newPage();
    await p.setViewportSize({ width: 400, height: 844 });
    await p.goto(`${BASE}/#${TOKEN}`);
    await until('the rows', async () => (await taskRowIds(p)).length >= 4);
    const got = await p.evaluate(() => ({
      grid: Math.round(document.querySelector('.grid-wrap').getBoundingClientRect().top),
      below: document.querySelector('[data-intake]').getBoundingClientRect().top >= document.querySelector('.grid-wrap').getBoundingClientRect().bottom,
    }));
    await p.close();
    console.log(`NOTE at 400x844 the grid starts at ${got.grid} px`);
    ok(got.grid <= 180 && got.below, `positions: ${JSON.stringify(got)}`);
  });

  await check('with no state repo the setup chip reads No state repo: run factory init', async () => {
    const p = await context.newPage();
    await p.route('**/api/setup', async (r) => {
      const res = await r.fetch();
      await r.fulfill({ response: res, json: { ...(await res.json()), reposYml: null } });
    });
    await p.goto(`${BASE}/#${TOKEN}`);
    await until('the state chip', () => p.locator('[data-check="state"]').isVisible());
    const text = (await p.locator('[data-check="state"]').innerText()).trim();
    await p.close();
    ok(text === 'No state repo: run factory init', `chip: ${JSON.stringify(text)}`);
  });

  await fresh(page);
  await check('the grid lists T-001, its block T-001-01 under it, then T-002 and T-003', async () => {
    const ids = await until('four task rows', async () => {
      const ids = await taskRowIds(page);
      return ids.length >= 4 && ids;
    });
    ok(ids.join(' ') === 'T-001 T-001-01 T-002 T-003', `rows: ${ids.join(' ')}`);
  });

  await check('without a CEO session the New request box names the command that starts one, and its text, priority and Send are disabled', async () => {
    const box = page.locator('[data-intake]');
    await until('the New request box', () => box.isVisible());
    const text = (await box.innerText()).replace(/\s+/g, ' ');
    ok(text.includes("claude '/claude-factory:factory ceo'"), `box: ${text}`);
    const controls = await box.locator('textarea, select, button').evaluateAll((els) => els.map((e) => `${e.tagName}${e.disabled ? '' : ' enabled'}`));
    ok(controls.join(' ') === 'TEXTAREA SELECT BUTTON', `controls: ${controls.join(' ')}`);
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

  await check('the row of T-003 reads 1 to answer: g1, whose session in herdr is gone, still counts', async () => {
    const text = await rowCount(page, 'T-003');
    ok(text === '1 to answer', `row: ${JSON.stringify(text)}`);
  });

  await check('the current cell of T-002 reads 3 to answer: r1, c1 and k1, the ask of s6 whose own task is T-002', async () => {
    const cell = page.locator('table tr', { hasText: 'T-002' }).first().locator('[aria-current="step"]');
    ok(await cell.getByText('3 to answer', { exact: true }).count(), `cell: ${JSON.stringify(await cell.innerText())}`);
  });

  await check('the row of T-001 reads 2 to answer: q3 and k2, which names no task and takes the T-001 of its session s6, not k1', async () => {
    const text = await rowCount(page, 'T-001');
    ok(text === '2 to answer', `row: ${JSON.stringify(text)}`);
  });

  await check('the row of T-002 ticks only what its state records, 3 triage and 9 approve, not the steps before the 11 its session reports', async () => {
    const got = await ticked(page, 'T-002');
    ok(got === '3 9', `ticked: ${JSON.stringify(got)}`);
  });

  await check('with the state repo found the setup chip reads State repo found', async () => {
    const text = (await page.locator('[data-check="state"]').innerText()).trim();
    ok(text === 'State repo found', `chip: ${JSON.stringify(text)}`);
  });

  await check('the setup strip chip reads 1 to answer, the doctor notice d1', async () => {
    const text = await until('the setup chip', async () => (await page.locator('.strip .chip.warn', { hasText: /^\d+ (waiting|to answer)$/ }).innerText()).trim());
    ok(text === '1 to answer', `chip: ${JSON.stringify(text)}`);
  });

  await check('the setup strip labels each live setup session by its flow, task and step, not its id, and leaves out the gone s7', async () => {
    const chips = await page.locator('.strip [data-session]').evaluateAll((cs) => cs.map((c) => `${c.dataset.session}=${c.textContent.trim()}`));
    ok(chips.join(' | ') === 's4=doctor | s8=init · Step 2 of 4: repos', `chips: ${chips.join(' | ')}`);
  });

  await check('every step header of the grid carries a short title, 8 cut the check of the cut and its wave plan', async () => {
    const titles = await page.locator('table thead th').evaluateAll((ths) => ths.slice(2).map((th) => `${th.textContent.trim().split(/\s+/)[0]}=${th.title}`));
    const bare = titles.filter((t) => /=$/.test(t));
    ok(titles.length && !bare.length, `without a title: ${bare.join(' ')}`);
    const cut = titles.find((t) => t.startsWith('8='));
    ok(/dag-check/.test(cut) && /wave plan/.test(cut), `8 cut: ${cut}`);
  });

  await check('the row of T-002 marks step 11 as current', async () => {
    const step = await currentStep(page, 'T-002');
    ok(step === '11', `current: ${step}`);
  });

  await check('the counter reads 7 to answer, 1 whose session ended: the gone g1 counted and named, not the sent q1, the answered q2 or outside herdr', async () => {
    await until('the counter', () => counter(page).isVisible());
    const text = (await counter(page).innerText()).replace(/\s+/g, ' ').trim();
    ok(text === '7 to answer, 1 whose session ended', `counter: ${JSON.stringify(text)}`);
  });

  for (const [n, id, group] of [[1, 's5/g1', /T-003/], [2, 's6/k2', /T-001/], [3, 's4/d1', /setup/i], [4, 's2/r1', /T-002/],
    [5, 's1/q3', /T-001/], [6, 's2/c1', /T-002/], [7, 's6/k1', /T-002/]]) {
    await check(`click ${n} on the counter opens ${id}, the next oldest waiting ask, in its drawer`, async () => {
      await counter(page).click();
      await until(`the drawer of ${group}`, async () => group.test(await drawer(page).innerText()));
      await until(`${id} in the drawer`, () => drawer(page).locator(`[data-ask="${id}"]`).isVisible());
      await until(`${id} scrolled into view`, () => inViewport(card(page, id)));
    });
  }

  await check('the drawer of T-001 holds k2, which names no task, and not k1, which names T-002', async () => {
    await fresh(page);
    await openTask(page, 'T-001');
    ok(await drawer(page).locator('[data-ask="s6/k2"]').isVisible(), 'no k2');
    ok(!(await drawer(page).locator('[data-ask="s6/k1"]').count()), 'k1 is in the drawer of T-001');
  });

  await check('the rail of T-002 lists the steps of the grid with the grid\'s labels in its order, then the done gate', async () => {
    await fresh(page);
    const heads = await until('the grid header', async () => {
      const h = await page.locator('table thead th').allInnerTexts();
      return h.length > 2 && h.slice(2).map((t) => t.replace(/\s+/g, ' ').trim());
    });
    await openTask(page, 'T-002');
    await expand(page);
    const rail = (await drawer(page).locator('nav[aria-label^="Solve steps"] li').allInnerTexts()).map((t) => t.replace(/\s+/g, ' ').trim());
    ok(JSON.stringify(rail) === JSON.stringify([...heads, 'done']), `rail: ${rail.join(' | ')}; grid: ${heads.join(' | ')}`);
  });

  await check('the rail of T-002 marks done the steps the grid ticks, 3 and 9, and 11, the step its session reports, as current', async () => {
    const got = await drawer(page).locator('nav[aria-label^="Solve steps"] ol').evaluate((ol) => [...ol.children].map((li) => {
      const n = li.textContent.trim().split(/\s+/)[0];
      return `${li.matches('.done') ? n : ''}${li.getAttribute('aria-current') === 'step' ? `>${n}` : ''}`;
    }).filter(Boolean).join(' '));
    ok(got === '3 9 >11', `rail: ${JSON.stringify(got)}`);
  });

  await check('the link ui-ask.sh printed for c1 opens the drawer of T-002 scrolled to the card of c1', async () => {
    await fresh(page, fs.readFileSync(path.join(UI, 'c1.url'), 'utf8').trim());
    await until('the drawer of T-002', async () => /T-002/.test(await drawer(page).innerText()));
    await until('c1 in the drawer', () => drawer(page).locator('[data-ask="s2/c1"]').isVisible());
    await until('c1 scrolled into view', () => inViewport(card(page, 's2/c1')));
  });

  await check('?ask= of a setup ask opens the setup drawer with that ask', async () => {
    await fresh(page, `${BASE}/?ask=s4/d1#token=${TOKEN}`);
    await until('the setup drawer', async () => /setup/i.test(await drawer(page).innerText()));
    await until('d1 in the drawer', () => drawer(page).locator('[data-ask="s4/d1"]').isVisible());
  });

  await check('the setup strip opens the setup drawer with the doctor notice and no task ask', async () => {
    await fresh(page);
    await page.getByRole('button', { name: /setup/i }).first().click();
    await until('d1 in the drawer', () => drawer(page).locator('[data-ask="s4/d1"]').isVisible());
    ok(!(await drawer(page).locator('[data-ask="s2/r1"]').count()), 'r1 is in the setup drawer');
  });

  await check('the setup drawer is headed Setup', async () => {
    const text = (await drawer(page).getByRole('heading', { level: 2 }).first().innerText()).trim();
    ok(text === 'Setup', `heading: ${JSON.stringify(text)}`);
  });

  await check('the notice renders its text and offers Write my answer, no options, Explain more, Compare options or Decide later', async () => {
    const c = card(page, 's4/d1');
    ok(/Docker is running\. herdr is running\./.test(await c.innerText()), await c.innerText());
    const extra = await c.getByRole('button', { name: /^[A-D]\b|explain more|compare options|decide later/i }).count();
    ok(extra === 0, `${extra} such buttons`);
    ok(await c.getByRole('button', { name: /write my answer/i }).count(), 'no Write my answer');
  });

  await check('the notice with Own answer text posts that text verbatim, commas included', async () => {
    const c = card(page, 's4/d1');
    const own = 'ok, but rerun doctor after the install, please';
    await c.getByRole('button', { name: /write my answer/i }).click();
    await c.getByRole('textbox').last().fill(own);
    await c.getByRole('button', { name: /add to answer/i }).click();
    await c.getByRole('button', { name: /^send answer$/i }).click();
    const files = await until('an answer file for d1', () => {
      const f = answers('s4').filter((n) => /^\d+-d1\.txt$/.test(n));
      return f.length && f;
    });
    const text = fs.readFileSync(path.join(UI, 'sessions/s4/answers', files[0]), 'utf8');
    ok(text === own, `file: ${JSON.stringify(text)}`);
  });

  await check('the held reason gone on the setup notice d1 names no solve command', async () => {
    const seq = answers('s4').find((n) => /^\d+-d1\.txt$/.test(n)).split('-')[0];
    writeAtomic(path.join(UI, 'sessions/s4/relay'), `${seq} gone\n`);
    const text = await until('gone on d1', async () => {
      const t = await card(page, 's4/d1').innerText();
      return /Not delivered: the session has ended\./.test(t) && t;
    }, 1500);
    ok(!/solve/.test(text), `card: ${text}`);
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

  await check('q1, named by an answer file, shows Sent, waiting for the session, and the held reason blocked with its pane', async () => {
    const text = await card(page, 's1/q1').innerText();
    ok(/Sent, waiting for the session/.test(text), `no sent: ${text}`);
    ok(/Not delivered yet: the session shows a dialog\. Answer it in herdr pane w1:p1, then this goes through by itself\./.test(text),
      `no dialog: ${text}`);
  });

  await check('the relay held reason gone reaches q1 without a reload', async () => {
    writeAtomic(path.join(UI, 'sessions/s1/relay'), '1 gone\n');
    await until('gone on q1', async () => /Not delivered: the session has ended\. Run \/claude-factory:factory solve T-001 to continue\./
      .test(await card(page, 's1/q1').innerText()), 1500);
  });

  await check('a session outside herdr shows its task state and its ask with no answer box', async () => {
    await fresh(page);
    await openTask(page, 'T-003');
    await expand(page);
    const d = drawer(page);
    ok(/in_progress/.test(await d.innerText()), 'no task status in the drawer');
    const c = d.locator('[data-ask="s3/o1"]');
    ok(/Which outside answer\?/.test(await c.innerText()), 'the question is not shown');
    ok(/This session runs outside herdr, so answer it in its terminal\./.test(await c.innerText()), await c.innerText());
    ok(!(await c.getByRole('button', { name: /send/i }).count()), 'a Send button');
    ok(!(await c.getByRole('textbox').count()), 'a text box');
    const live = await c.getByRole('button', { name: /^[A-D]\b/ }).evaluateAll((bs) => bs.filter((b) => !b.disabled).length);
    ok(live === 0, `${live} enabled option buttons`);
  });

  await check('the triage panel of T-003, whose tier, archetype and complexity are the draft\'s placeholders, reads Not triaged yet.', async () => {
    const text = await drawer(page).locator('[data-panel="triage"]').innerText();
    ok(/Not triaged yet\./.test(text), `triage: ${text.slice(0, 300)}`);
    ok(!/<|green\|yellow|feature\|bugfix|low\|medium/.test(text), `a placeholder in: ${text.slice(0, 300)}`);
  });

  for (const [width, height] of [[1440, 900], [390, 844]]) {
    await page.setViewportSize({ width, height });
    await fresh(page);
    await openTask(page, 'T-002');

    await check(`at ${width}x${height} opening T-002 shows the question text and options of Q1 of r1 in the first viewport`, async () => {
      const q = question(card(page, 's2/r1'), 'Q1');
      await until('Q1 of r1', () => q.isVisible());
      ok(/Which store\?/.test(await q.locator('h4').innerText()), `Q1 reads ${await q.locator('h4').innerText()}`);
      const off = await exposed(page, ['h4', '[data-act="pick"]'].map((e) => `aside [data-ask="s2/r1"] [data-q="Q1"] ${e}`).join(', '));
      ok(!off.length, off.join(' | '));
    });

    await check(`at ${width}x${height} Send of the long ask r1 is visible without scrolling`, async () => {
      const off = await exposed(page, 'aside [data-ask="s2/r1"] [data-act="send"]');
      ok(!off.length, off.join(' | '));
    });

    await check(`at ${width}x${height} the drawer of T-002 is ${width > 720 ? 'at least 60% of' : 'the full'} viewport width`, async () => {
      const box = await page.evaluate(() => {
        const r = document.querySelector('aside').getBoundingClientRect();
        return { left: r.left, right: r.right, width: r.width, viewport: innerWidth };
      });
      if (width > 720) ok(box.width >= 0.6 * box.viewport, `the drawer is ${box.width} px of ${box.viewport}`);
      else ok(Math.abs(box.left) <= 1 && Math.abs(box.right - box.viewport) <= 1, `the drawer spans ${box.left} to ${box.right} of ${box.viewport}`);
    });

    await check(`at ${width}x${height} T-002 keeps its panels, visual and sessions in one collapsed Task details after the asks`, async () => {
      const why = await page.evaluate(() => {
        const aside = document.querySelector('aside');
        const all = [...aside.querySelectorAll('details')].filter((d) => d.querySelector(':scope > summary')?.textContent.trim() === 'Task details');
        if (all.length !== 1) return `${all.length} Task details`;
        const det = all[0];
        if (det.open) return 'Task details is open';
        const out = [...aside.querySelectorAll('[data-panel], [data-visual], nav')].filter((e) => !det.contains(e));
        if (out.length) return `outside Task details: ${out.map((e) => e.dataset.panel || e.dataset.visual || e.tagName).join(' ')}`;
        if (!det.querySelector('[data-panel]')) return 'no panel in Task details';
        if (!det.querySelector('[data-visual]')) return 'no visual in Task details';
        const step = 'Step 11 of 16: wave 1 implement';
        if (!det.textContent.includes(step)) return 'the session s2 is not in Task details';
        const walk = document.createTreeWalker(aside, NodeFilter.SHOW_TEXT);
        for (let n = walk.nextNode(); n; n = walk.nextNode()) {
          if (n.textContent.includes(step) && !det.contains(n)) return 'the session s2 is outside Task details too';
        }
        const asks = [...aside.querySelectorAll('[data-ask]')];
        if (!asks.length) return 'no ask';
        if (asks.some((a) => det.contains(a))) return 'an ask is inside Task details';
        return asks[0].compareDocumentPosition(det) & Node.DOCUMENT_POSITION_FOLLOWING ? '' : 'Task details comes before the asks';
      });
      ok(!why, why);
    });
  }
  await page.setViewportSize({ width: 1440, height: 900 });

  await check('the visual of s2 in Task details is headed Drawing for Q2 · version 1', async () => {
    await expand(page);
    const v = drawer(page).locator('[data-visual="s2"]');
    await until('the visual of s2', () => v.isVisible());
    const text = (await v.getByRole('heading').first().innerText()).trim();
    ok(text === 'Drawing for Q2 · version 1', `heading: ${JSON.stringify(text)}`);
  });

  await check('once s2 marks its visual stale it reads Out of date: an answer changed. Redraw to update., Task details still open', async () => {
    writeAtomic(path.join(UI, 'sessions/s2/visual.md'), '---\nrow: 2\nversion: 1\nstatus: stale\n---\n');
    await until('the out-of-date text', async () =>
      (await drawer(page).locator('[data-visual="s2"]').innerText()).includes('Out of date: an answer changed. Redraw to update.'), 3000);
    ok(await details(page).first().evaluate((el) => el.open), 'Task details closed on the refresh');
  });

  const staged = ['Q1 B', 'Q2 more', 'explore Q3', 'Q4 cf-ui-fixture, on port 7171', 'Q5 ? why not both, SQLite and files', 'Q6 defer'];
  await check('the round card shows Will be sent: with one staged item per line, Own answer and Ask a question text with commas', async () => {
    await fresh(page);
    await openTask(page, 'T-002');
    const c = card(page, 's2/r1');
    await question(c, 'Q1').getByRole('button', { name: /^B\b/ }).click();
    await question(c, 'Q2').getByRole('button', { name: /explain more/i }).click();
    await question(c, 'Q3').getByRole('button', { name: /compare options/i }).click();
    await stage(question(c, 'Q4'), /write my answer/i, 'cf-ui-fixture, on port 7171');
    await stage(question(c, 'Q5'), /ask a question/i, 'why not both, SQLite and files');
    await question(c, 'Q6').getByRole('button', { name: /decide later/i }).click();
    ok(/Will be sent:/.test(await c.innerText()), 'no Will be sent:');
    const lines = (await c.locator('output').first().innerText()).replace('Will be sent:', '')
      .split('\n').map((l) => l.trim()).filter(Boolean);
    ok(JSON.stringify(lines) === JSON.stringify(staged), `preview lines: ${JSON.stringify(lines)}`);
  });

  await check('Send answers writes one answer file for r1 whose lines are exactly the staged items', async () => {
    await card(page, 's2/r1').getByRole('button', { name: /^send answers$/i }).click();
    const files = await until('an answer file for r1', () => {
      const f = answers('s2').filter((n) => /^\d+-r1\.txt$/.test(n));
      return f.length && f;
    });
    ok(files.length === 1, `files: ${files.join(' ')}`);
    const text = fs.readFileSync(path.join(UI, 'sessions/s2/answers', files[0]), 'utf8');
    ok(text === staged.join('\n'), `file: ${JSON.stringify(text)}`);
  });

  await check('r1 shows Sent, waiting for the session without a reload once its answer file exists', async () => {
    await until('sent on r1', async () => /Sent, waiting for the session/.test(await card(page, 's2/r1').innerText()), 1500);
  });

  await check('r1 shows answered and offers no Send once its session closed it', async () => {
    const file = path.join(UI, 'sessions/s2/asks/r1.md');
    writeAtomic(file, fs.readFileSync(file, 'utf8').replace(/^status: open$/m, 'status: answered'));
    await until('answered on r1', async () => /\bAnswered\b/.test(await card(page, 's2/r1').innerText()), 1500);
    const live = await card(page, 's2/r1').getByRole('button', { name: /send/i })
      .evaluateAll((bs) => bs.filter((b) => !b.disabled).length);
    ok(live === 0, `${live} enabled Send buttons`);
  });

  for (const [width, height] of [[1440, 900], [390, 844]]) {
    await check(`at ${width}x${height} the drawer header stays opaque over the answered r1 scrolled under it`, async () => {
      await page.setViewportSize({ width, height });
      const why = await page.evaluate(() => {
        const aside = document.querySelector('aside');
        const head = aside.querySelector('.drawer-h');
        const c = aside.querySelector('[data-ask="s2/r1"]');
        let box = c.parentElement;
        while (box && !(/auto|scroll/.test(getComputedStyle(box).overflowY) && box.scrollHeight > box.clientHeight)) box = box.parentElement;
        if (!box) return 'nothing scrolls the drawer';
        box.scrollTop += c.getBoundingClientRect().top - head.getBoundingClientRect().top + 8;
        const h = head.getBoundingClientRect();
        const r = c.getBoundingClientRect();
        if (!(r.top < h.top && r.bottom > h.bottom)) return `r1 at ${r.top}..${r.bottom} is not under the header at ${h.top}..${h.bottom}`;
        const bg = getComputedStyle(head).backgroundColor;
        const alpha = bg === 'transparent' ? 0 : Number((bg.match(/rgba?\([^)]*,\s*([\d.]+)\)/) || [0, 1])[1]);
        if (alpha < 1) return `the header background is ${bg}`;
        const over = [0.1, 0.5, 0.9].map((f) => document.elementFromPoint(h.left + h.width * f, h.top + h.height / 2))
          .filter((e) => !head.contains(e));
        return over.length ? `painted over by ${over.map((e) => e.outerHTML.slice(0, 60)).join(' | ')}` : '';
      });
      ok(!why, why);
    });
  }
  await page.setViewportSize({ width: 1440, height: 900 });

  await check('the confirm card offers yes and no, no Compare options or Decide later, and sends Q1 A for yes', async () => {
    const c = card(page, 's2/c1');
    ok(await c.getByRole('button', { name: /\byes\b/i }).count(), 'no yes');
    ok(await c.getByRole('button', { name: /\bno\b/i }).count(), 'no no');
    ok(!(await c.getByRole('button', { name: /compare options|decide later/i }).count()), 'Compare options or Decide later on a confirm');
    await c.getByRole('button', { name: /\byes\b/i }).first().click();
    await c.getByRole('button', { name: /^send answer$/i }).click();
    const files = await until('an answer file for c1', () => {
      const f = answers('s2').filter((n) => /^\d+-c1\.txt$/.test(n));
      return f.length && f;
    });
    const text = fs.readFileSync(path.join(UI, 'sessions/s2/answers', files[0]), 'utf8');
    ok(text === 'Q1 A', `file: ${JSON.stringify(text)}`);
    await until('sent on c1', async () => /Sent, waiting for the session/.test(await card(page, 's2/c1').innerText()), 1500);
  });

  await check('with q3, k1 and k2 answered the counter reads 1 to answer, 1 whose session ended: the gone g1', async () => {
    writeAtomic(path.join(UI, 'sessions/s1/answers/2-q3.txt'), 'Q1 A');
    writeAtomic(path.join(UI, 'sessions/s6/answers/1-k1.txt'), 'Q1 A');
    writeAtomic(path.join(UI, 'sessions/s6/answers/2-k2.txt'), 'ok');
    const want = '1 to answer, 1 whose session ended';
    const text = await until(want, async () => {
      const t = (await counter(page).innerText()).replace(/\s+/g, ' ').trim();
      return t === want && t;
    }, 3000).catch(async () => (await counter(page).innerText()).trim());
    ok(text === want, `counter: ${JSON.stringify(text)}`);
  });

  await check('the counter reads All answered once the gone g1, the last waiting ask, has an answer', async () => {
    writeAtomic(path.join(UI, 'sessions/s5/answers/1-g1.txt'), 'Q1 A');
    const text = await until('All answered', async () => {
      const t = (await counter(page).innerText()).trim();
      return t === 'All answered' && t;
    }, 3000).catch(async () => (await counter(page).innerText()).trim());
    ok(text === 'All answered', `counter: ${JSON.stringify(text)}`);
  });

  await check('a new ask raises the counter within 1 s of its write (QS-03)', async () => {
    const before = (await counter(page).innerText()).match(/\d+/) || ['0'];
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

  await check('at 390x844 the ask m1 shows its preamble, the paragraph under Q1, its table as a table, its ### section and Why B:', async () => {
    await fresh(page);
    await openTask(page, 'T-003');
    const c = card(page, 's3/m1');
    await until('m1 in the drawer', () => c.isVisible());
    const text = await c.innerText();
    for (const s of ['The preamble sentence of m1, before its first question.', 'The paragraph under Q1 of m1.',
      'The sentence under the section of m1.', 'Why B: one pair of commands.']) {
      ok(text.includes(s), `no ${JSON.stringify(s)} in: ${text.slice(0, 600)}`);
    }
    ok(await c.getByRole('heading', { name: 'The section of m1' }).count(), 'the ### section is not a heading');
    const rows = await c.locator('table tr').evaluateAll((trs) => trs.map((tr) => [...tr.cells].map((td) => td.textContent.trim()).join('|')));
    ok(rows.join('\n') === 'runner|start|stop\nscript|ui-up.sh|ui-down.sh\ncompose|docker compose up|docker compose down',
      `table rows: ${JSON.stringify(rows)}`);
  });

  await check('at 390x844 each option of m1 holds its label, inline code included, as one line box', async () => {
    const opts = await until('the options of m1 laid out', async () => {
      const all = await card(page, 's3/m1').locator('[data-act="pick"]').evaluateAll((bs) => bs.map((b) => {
        const walk = document.createTreeWalker(b, NodeFilter.SHOW_TEXT);
        const lines = [];
        for (let n = walk.nextNode(); n; n = walk.nextNode()) {
          if (!n.textContent.trim() || n.parentElement.closest('.chip')) continue;
          const range = document.createRange();
          range.selectNodeContents(n);
          for (const r of range.getClientRects()) {
            if (!r.width) continue;
            const line = lines.find((l) => r.top < l.bottom && r.bottom > l.top);
            if (line) Object.assign(line, { top: Math.min(line.top, r.top), bottom: Math.max(line.bottom, r.bottom) });
            else lines.push({ top: r.top, bottom: r.bottom });
          }
        }
        return { key: b.dataset.k, lines: lines.length, text: b.innerText };
      }));
      return all.length && all.every((o) => o.lines > 0) && all;
    });
    ok(opts.map((o) => o.key).join() === 'A,B', `options: ${JSON.stringify(opts)}`);
    for (const o of opts) ok(o.lines === 1, `option ${o.key} spans ${o.lines} line boxes: ${JSON.stringify(o.text)}`);
    const b = opts[1].text.split('\n').map((l) => l.replace(/\s+/g, ' ').trim());
    ok(b.some((l) => /\brun ui-up\.sh then ui-down\.sh\b/.test(l)), `option B reads ${JSON.stringify(opts[1].text)}`);
  });

  // --- the org: tabs, requests, priority, capacity, Map and Plan, against the shapes of the wave-2 API -------------
  await page.setViewportSize({ width: 1440, height: 900 });

  await check('the header offers the tabs Pipeline, Map, Plan, Org, Memory and Setup in that order, Pipeline selected', async () => {
    await fresh(page);
    await until('the tabs', async () => (await page.getByRole('tab').count()) === 6);
    const tabs = await page.getByRole('tab').evaluateAll((ts) => ts.map((t) => `${t.textContent.trim()}${t.getAttribute('aria-selected') === 'true' ? '*' : ''}`));
    ok(tabs.join(' ') === 'Pipeline* Map Plan Org Memory Setup', `tabs: ${tabs.join(' ')}`);
  });

  await check('the row of T-001 shows its repo claude-factory as a chip right after its id', async () => {
    const chip = await page.locator('table tr', { hasText: 'T-001' }).first().locator('.id').first()
      .evaluate((id) => id.nextElementSibling && id.nextElementSibling.matches('.chip') && id.nextElementSibling.textContent.trim());
    ok(chip === 'claude-factory', `next to the id: ${JSON.stringify(chip)}`);
  });

  await check('without /api/requests and /api/org the grid still shows, the Map tab reads No request yet and no error shows', async () => {
    await page.getByRole('tab', { name: 'Map' }).click();
    await until('No request yet', async () => /No request yet/.test(await page.locator('#app').innerText()));
    await page.getByRole('tab', { name: 'Pipeline' }).click();
    await until('the grid', async () => (await taskRowIds(page)).length >= 4);
    ok(!(await page.locator('.error').count()), `error: ${await page.locator('.error').allInnerTexts()}`);
  });

  const row = (id, status, repo, goal, request, priority) => ({ id, status, archetype: 'feature', tier: 'yellow', repo, owner: '', goal, request, priority });
  const BOARD = [
    row('T-ECS-14', 'draft', 'ecs', 'feat(rotation): rotation metrics', 'R-20260925-1', 'P3'),
    row('T-ECS-12', 'draft', 'ecs', 'feat(rotation): rotate a stored credential on request', 'R-20260925-1', 'P1'),
    row('T-ECS-12-01', 'draft', 'ecs', 'feat(rotation): versioned secret write', 'R-20260925-1', 'P1'),
    row('T-264', 'ready', 'claude-factory', 'fix(ui): a legacy task without a request', '', 'P2'),
    row('T-BFF-3', 'draft', 'bff', 'feat(proxy): expose credential rotation', 'R-20260925-1', 'P1'),
    row('T-ART-21', 'in_progress', 'arthurcore', 'feat(jobs): bounded retry with backoff', 'R-20260924-2', 'P0'),
  ];
  const REQUESTS = [
    { id: 'R-20260925-1', status: 'planned', destination: 'Rotate a stored credential on request through the bff.', priority: 'P1', parents: ['T-ECS-12', 'T-BFF-3', 'T-ECS-14'], archived: false },
    { id: 'R-20260924-2', status: 'running', destination: 'Retry policy for arthurcore jobs.', priority: 'P0', parents: ['T-ART-21'], archived: false },
    { id: 'R-20260901-1', status: 'done', destination: 'An archived request.', priority: 'P2', parents: ['T-OLD-1'], archived: true },
  ];
  const ticket = (nn, title, type, status, blockedBy, repo, claimedBy, answer) => ({ nn, title, type, status, blockedBy, repo, claimedBy, question: title, answer });
  const DETAIL = {
    id: 'R-20260925-1', status: 'planned', destination: 'Rotate a stored credential on request through the bff.',
    notes: 'Both repos release together.', terms: '- **Rotation**: a new secret version. Avoid: renewal', archived: false,
    decisions: [{ title: 'Rotation API of the vault', file: '01-rotation-api-of-the-vault.md', gist: 'Versioned secrets.' },
      { title: 'Who may rotate', file: '02-who-may-rotate.md', gist: 'The owning org admin.' }],
    outOfScope: [{ title: 'Scheduled rotation', file: '05-scheduled-rotation.md', gist: 'The destination is rotation on request.' }],
    fog: 'How the bff shows a <b>rotation</b> in progress.',
    tickets: [
      ticket('01', 'Rotation API of the vault', 'research', 'resolved', [], 'ecs', '', 'Versioned secrets.'),
      ticket('02', 'Who may rotate', 'grilling', 'resolved', [], 'all', '', 'The owning org admin.'),
      ticket('03', 'Rotation trigger', 'grilling', 'claimed', ['01'], 'ecs', 'chart_ecs-12', ''),
      ticket('04', 'Error contract toward the bff', 'grilling', 'open', ['03'], 'all', '', ''),
      ticket('05', 'Scheduled rotation', 'grilling', 'dropped', [], 'all', '', 'The destination is rotation on request.'),
      ticket('06', 'Audit log format', 'research', 'open', [], 'ecs', '', ''),
    ],
    frontier: ['06'],
    parents: [
      { id: 'T-ECS-12', repo: 'ecs', priority: 'P1', status: 'draft', goal: 'feat(rotation): rotate a stored credential on request',
        acceptance: 'dotnet test --filter Rotation', blocks: [
          { id: 'T-ECS-12-01', status: 'draft', goal: 'feat(rotation): versioned secret write', acceptance: 'dotnet test --filter Rotation.Write' },
          { id: 'T-ECS-12-02', status: 'done', goal: 'feat(rotation): grace period', acceptance: 'dotnet test --filter Rotation.Grace' }] },
      { id: 'T-BFF-3', repo: 'bff', priority: 'P1', status: 'draft', goal: 'feat(proxy): expose credential rotation', acceptance: 'npm test -- rotation', blocks: [] },
      { id: 'T-ECS-14', repo: 'ecs', priority: 'P3', status: 'draft', goal: 'feat(rotation): rotation metrics', acceptance: '', blocks: [] },
    ],
  };
  const DETAIL2 = { ...DETAIL, id: 'R-20260924-2', status: 'running', destination: 'Retry policy for arthurcore jobs.', notes: '', terms: '',
    decisions: [], outOfScope: [], fog: '', tickets: [], frontier: [],
    parents: [{ id: 'T-ART-21', repo: 'arthurcore', priority: 'P0', status: 'in_progress', goal: 'feat(jobs): bounded retry with backoff', acceptance: 'dotnet test --filter Retry', blocks: [] }] };
  const ORG = { capacity: { sessions: { used: 9, cap: 10 }, roles: [{ role: 'repo-lead', used: 2, cap: 3 }, { role: 'implementer', used: 4, cap: 4 },
    { role: 'researcher', used: 1, cap: null }] }, leases: [], leads: [], ceo: null };

  async function mocked(routes) { // {path: body, or null for a 404}: a new page with those /api answers
    const p = await context.newPage();
    for (const [route, body] of Object.entries(routes)) {
      await p.route(`**${route}`, (r) => (body === null ? r.fulfill({ status: 404, body: '' })
        : r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) })));
    }
    await p.goto(`${BASE}/#${TOKEN}`);
    return p;
  }
  const org = await mocked({ '/api/board': BOARD, '/api/requests': REQUESTS, '/api/requests/R-20260925-1': DETAIL,
    '/api/requests/R-20260924-2': DETAIL2, '/api/org': ORG });

  await check('the grid groups the rows under one header row per request, best priority first, then the rows without a request', async () => {
    const seq = await until('the grouped rows', async () => {
      const s = await org.locator('table').first().evaluate((table) => [...table.querySelectorAll('tbody tr')].map((r) => {
        if (r.querySelector('th[scope="rowgroup"]')) return `req:${(r.textContent.match(/R-\d+-\d+/) || ['none'])[0]}`;
        return (r.querySelector('.id') || { textContent: '?' }).textContent.trim();
      }));
      return s.length >= 9 && s;
    });
    ok(seq.join(' ') === 'req:R-20260924-2 T-ART-21 req:R-20260925-1 T-ECS-12 T-ECS-12-01 T-BFF-3 T-ECS-14 req:none T-264',
      `rows: ${seq.join(' ')}`);
  });

  await check('the header row of R-20260925-1 shows its id, priority P1, status planned and its destination', async () => {
    const text = await org.locator('tr', { has: org.locator('th[scope="rowgroup"]', { hasText: 'R-20260925-1' }) }).innerText();
    for (const s of ['R-20260925-1', 'P1', 'planned', 'Rotate a stored credential on request through the bff.']) ok(text.includes(s), `no ${s} in: ${text}`);
  });

  await check('every task row carries its priority in the Prio column and its repo as a chip right after its id', async () => {
    const got = await org.locator('table').first().evaluate((table) => {
      const heads = [...table.querySelectorAll('thead th')].map((th) => th.textContent.trim().split(/\s+/)[0]);
      const prio = heads.indexOf('Prio');
      return [...table.querySelectorAll('tbody tr')].filter((r) => !r.querySelector('th[scope="rowgroup"]') && !r.classList.contains('sub'))
        .map((r) => `${r.querySelector('.id').textContent.trim()}:${r.querySelector('.id').nextElementSibling?.textContent.trim()}:${r.children[prio]?.textContent.trim()}`);
    });
    ok(got.join(' ') === 'T-ART-21:arthurcore:P0 T-ECS-12:ecs:P1 T-BFF-3:bff:P1 T-ECS-14:ecs:P3 T-264:claude-factory:P2', `rows: ${got.join(' ')}`);
  });

  await check('the capacity strip of the Pipeline tab shows sessions and every role as used/cap, a role without a cap as used/-', async () => {
    const items = await until('the capacity strip', async () => {
      const t = await org.locator('[data-capacity] [data-role]').allInnerTexts();
      return t.length && t.map((s) => s.replace(/\s+/g, ' ').trim());
    });
    ok(items.join(', ') === 'sessions 9/10, repo-lead 2/3, implementer 4/4, researcher 1/-', `strip: ${items.join(', ')}`);
  });

  await check('with /api/org missing the capacity strip reads the capacity of /api/setup', async () => {
    const p = await context.newPage();
    await p.route('**/api/org', (r) => r.fulfill({ status: 404, body: '' }));
    await p.route('**/api/setup', async (r) => {
      const res = await r.fetch();
      await r.fulfill({ response: res, json: { ...(await res.json()), capacity: { sessions: { used: 3, cap: 10 }, roles: [] } } });
    });
    await p.goto(`${BASE}/#${TOKEN}`);
    const items = await until('the capacity strip', async () => {
      const t = await p.locator('[data-capacity] [data-role]').allInnerTexts();
      return t.length && t.map((s) => s.replace(/\s+/g, ' ').trim());
    }).finally(() => p.close());
    ok(items.join(', ') === 'sessions 3/10', `strip: ${items.join(', ')}`);
  });

  await check('the Map tab lists every request newest first, the archived one marked, R-20260925-1 selected', async () => {
    await org.getByRole('tab', { name: 'Map' }).click();
    const list = await until('the request list', async () => {
      const t = await org.locator('[data-request]').evaluateAll((bs) => bs.map((b) => `${b.dataset.request}${b.getAttribute('aria-pressed') === 'true' ? '*' : ''}${/archived/.test(b.textContent) ? ' archived' : ''}`));
      return t.length === 3 && t;
    });
    ok(list.join(', ') === 'R-20260925-1*, R-20260924-2, R-20260901-1 archived', `requests: ${list.join(', ')}`);
  });

  await check('the Map tab shows the destination with the id, priority and status of R-20260925-1', async () => {
    const text = await until('the destination', async () => {
      const t = await org.locator('[data-map] .dest').innerText();
      return /Rotate a stored credential/.test(t) && t;
    });
    for (const s of ['R-20260925-1', 'P1', 'planned']) ok(text.includes(s), `no ${s} in: ${text}`);
  });

  await check('the Map tab shows the open and claimed tickets with type, blockers, repo and claimer, only 06 marked frontier', async () => {
    const col = org.locator('[data-map] [data-col="open"]');
    const tickets = await col.locator('[data-ticket]').evaluateAll((ts) => ts.map((t) => `${t.dataset.ticket}${/frontier/.test(t.textContent) ? '*' : ''}`));
    ok(tickets.join(' ') === '03 04 06*', `open tickets: ${tickets.join(' ')}`);
    const t03 = await col.locator('[data-ticket="03"]').innerText();
    for (const s of ['Rotation trigger', 'grilling', 'claimed', 'chart_ecs-12', '01', 'ecs']) ok(t03.includes(s), `no ${s} in 03: ${t03}`);
  });

  await check('the Map tab shows the decisions so far with their gist, the fog as text and out of scope with its reason', async () => {
    const dec = await org.locator('[data-map] [data-col="decisions"]').innerText();
    for (const s of ['Rotation API of the vault', 'Versioned secrets.', 'Who may rotate', 'The owning org admin.']) ok(dec.includes(s), `no ${s} in: ${dec}`);
    const fog = await org.locator('[data-map] [data-col="fog"]').innerText();
    ok(fog.includes('How the bff shows a <b>rotation</b> in progress.'), `fog: ${fog}`);
    const out = await org.locator('[data-map] [data-col="out"]').innerText();
    ok(out.includes('Scheduled rotation') && out.includes('The destination is rotation on request.'), `out of scope: ${out}`);
  });

  await check('selecting R-20260924-2 loads its map', async () => {
    await org.locator('[data-request="R-20260924-2"]').click();
    await until('the destination of R-20260924-2', async () => /Retry policy for arthurcore jobs\./.test(await org.locator('[data-map] .dest').innerText()));
    await org.locator('[data-request="R-20260925-1"]').click();
    await until('the destination of R-20260925-1', async () => /Rotate a stored credential/.test(await org.locator('[data-map] .dest').innerText()));
  });

  await check('the Plan tab shows the destination, the decisions and out of scope of the selected request', async () => {
    await org.getByRole('tab', { name: 'Plan' }).click();
    const text = await until('the plan', async () => {
      const t = await org.locator('[data-plan]').innerText();
      return /Rotate a stored credential/.test(t) && t;
    });
    for (const s of ['R-20260925-1', 'Rotation API of the vault', 'Versioned secrets.', 'Scheduled rotation', 'The destination is rotation on request.']) {
      ok(text.includes(s), `no ${s} in: ${text.slice(0, 600)}`);
    }
  });

  await check('the Plan checklist lists the parents per repo, ecs then bff, each with its blocks, status and acceptance', async () => {
    const got = await org.locator('[data-checklist]').evaluate((ck) => ({
      repos: [...ck.querySelectorAll('[data-plan-repo]')].map((r) => r.dataset.planRepo),
      items: [...ck.querySelectorAll('[data-item]')].map((li) => li.dataset.item),
      ecs12: ck.querySelector('[data-item="T-ECS-12"]')?.textContent || '',
      grace: ck.querySelector('[data-item="T-ECS-12-02"]')?.textContent || '',
    }));
    ok(got.repos.join(' ') === 'ecs bff', `repos: ${got.repos.join(' ')}`);
    ok(got.items.join(' ') === 'T-ECS-12 T-ECS-12-01 T-ECS-12-02 T-ECS-14 T-BFF-3', `items: ${got.items.join(' ')}`);
    for (const s of ['rotate a stored credential on request', 'dotnet test --filter Rotation', 'P1', 'draft']) ok(got.ecs12.includes(s), `no ${s} in: ${got.ecs12}`);
    for (const s of ['grace period', 'dotnet test --filter Rotation.Grace', 'done']) ok(got.grace.includes(s), `no ${s} in: ${got.grace}`);
  });

  await check('the Plan checklist is read-only: no input, button or editable element, and the approval is the CEO\'s confirm ask', async () => {
    const n = await org.locator('[data-checklist]').locator('input, textarea, select, button, [contenteditable]').count();
    ok(n === 0, `${n} controls in the checklist`);
    ok(!(await org.locator('[data-plan]').getByRole('button', { name: /approve/i }).count()), 'an approve button');
    ok(/confirm ask/i.test(await org.locator('[data-plan]').innerText()), 'no word of the CEO\'s confirm ask');
  });

  await check('at 390x844 no tab scrolls the page sideways', async () => {
    await org.setViewportSize({ width: 390, height: 844 });
    const wide = [];
    for (const name of ['Pipeline', 'Map', 'Plan', 'Org', 'Memory', 'Setup']) {
      await org.getByRole('tab', { name }).click();
      await org.waitForTimeout(300);
      const over = await org.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      if (over > 0) wide.push(`${name} by ${over} px`);
    }
    ok(!wide.length, wide.join(', '));
  });
  await org.close();

  // --- the intake: a New request box on the Pipeline tab that sends the request to the CEO as a free message --------
  const posted = [];
  const intake = await context.newPage();
  await intake.route('**/api/org', (r) => r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ ...ORG, ceo: { sid: 's-ceo', pane: 'w1:p9' } }) }));
  await intake.route('**/api/answers/s-ceo', (r) => {
    posted.push(r.request().postDataJSON());
    return r.fulfill({ status: 201, contentType: 'application/json', body: '{}' });
  });
  await intake.goto(`${BASE}/#${TOKEN}`);
  const box = intake.locator('[data-intake]');
  const request = 'Export the invoices to the ledger, every night';

  await check('with a CEO the New request box offers P0 to P3 with P2 selected, enabled, and no command to start the CEO', async () => {
    await until('the enabled box', () => box.locator('textarea').isEnabled());
    const options = await box.locator('select option').evaluateAll((os) => os.map((o) => `${o.textContent.trim()}${o.selected ? '*' : ''}`));
    ok(options.join(' ') === 'P0 P1 P2* P3', `options: ${options.join(' ')}`);
    ok(!(await box.innerText()).includes('factory ceo'), `box: ${await box.innerText()}`);
  });

  await check('the text typed in New request stays, focused, across a refresh of the page\'s data', async () => {
    await box.locator('textarea').fill(request);
    await box.evaluate((el) => { el.dataset.old = '1'; });
    writeAtomic(path.join(UI, 'sessions/s1/relay'), '1 blocked\n');
    await until('a re-render', async () => (await intake.locator('[data-intake]').getAttribute('data-old')) === null, 3000);
    const got = await intake.evaluate(() => ({
      value: document.querySelector('[data-intake] textarea').value,
      focused: document.activeElement === document.querySelector('[data-intake] textarea'),
    }));
    ok(got.value === request && got.focused, `after the refresh: ${JSON.stringify(got)}`);
  });

  await check('Send of New request posts request: <text>, priority P1 to the CEO as a free message and says it was sent', async () => {
    await box.locator('select').selectOption('P1');
    await box.getByRole('button', { name: /^send$/i }).click();
    await until('the post to the CEO', () => posted.length);
    const want = { ask: '', text: `request: ${request}, priority P1` };
    ok(JSON.stringify(posted) === JSON.stringify([want]), `posted: ${JSON.stringify(posted)}`);
    await until('the sent note', async () => (await box.innerText()).includes(`Sent to the CEO: ${want.text}`));
    ok((await box.locator('textarea').inputValue()) === '', 'the text stays after the send');
  });
  await intake.close();

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
