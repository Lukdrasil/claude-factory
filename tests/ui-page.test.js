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

  await check('without the token in the fragment no task is shown', async () => {
    await fresh(page, `${BASE}/`);
    await page.waitForTimeout(1500);
    ok(!(await page.getByText('T-001', { exact: false }).count()), 'T-001 is on the page');
  });

  await check('without the token the page reads This page needs its access link. Run ui-up.sh and open the link it prints.', async () => {
    const text = (await page.locator('#app').innerText()).replace(/\s+/g, ' ').trim();
    ok(text === 'This page needs its access link. Run ui-up.sh and open the link it prints.', `page: ${JSON.stringify(text)}`);
  });

  await check('with no task in the state repo the grid reads No tasks yet. Start one with /claude-factory:factory new.', async () => {
    const p = await context.newPage();
    await p.route('**/api/board', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: '[]' }));
    await p.goto(`${BASE}/#${TOKEN}`);
    const text = await until('the empty grid', async () => {
      const t = (await p.locator('table tbody').first().innerText()).replace(/\s+/g, ' ').trim();
      return t && t;
    });
    await p.close();
    ok(text === 'No tasks yet. Start one with /claude-factory:factory new.', `grid: ${JSON.stringify(text)}`);
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

  await check('the row of T-003 counts no waiting ask: its one session in herdr is gone', async () => {
    const text = await page.locator('table tr', { hasText: 'T-003' }).first().innerText();
    ok(!/waiting|to answer/.test(text), `row: ${text}`);
  });

  await check('the current cell of T-002 reads 2 to answer, r1 and c1', async () => {
    const cell = page.locator('table tr', { hasText: 'T-002' }).first().locator('[aria-current="step"]');
    ok(await cell.getByText('2 to answer', { exact: true }).count(), `cell: ${JSON.stringify(await cell.innerText())}`);
  });

  await check('with the state repo found the setup chip reads State repo found', async () => {
    const text = (await page.locator('[data-check="state"]').innerText()).trim();
    ok(text === 'State repo found', `chip: ${JSON.stringify(text)}`);
  });

  await check('the setup strip chip reads 1 to answer, the doctor notice d1', async () => {
    const text = await until('the setup chip', async () => (await page.locator('.strip .chip.warn', { hasText: /^\d+ (waiting|to answer)$/ }).innerText()).trim());
    ok(text === '1 to answer', `chip: ${JSON.stringify(text)}`);
  });

  await check('the row of T-002 marks step 11 as current', async () => {
    const step = await currentStep(page, 'T-002');
    ok(step === '11', `current: ${step}`);
  });

  await check('the counter reads 4 to answer: not the sent q1, not the answered q2, not outside herdr, not the gone g1', async () => {
    await until('the counter', () => counter(page).isVisible());
    const text = (await counter(page).innerText()).trim();
    ok(text === '4 to answer', `counter: ${JSON.stringify(text)}`);
  });

  for (const [n, id, group] of [[1, 's4/d1', /setup/i], [2, 's2/r1', /T-002/], [3, 's1/q3', /T-001/], [4, 's2/c1', /T-002/]]) {
    await check(`click ${n} on the counter opens ${id}, the next oldest waiting ask, in its drawer`, async () => {
      await counter(page).click();
      await until(`the drawer of ${group}`, async () => group.test(await drawer(page).innerText()));
      await until(`${id} in the drawer`, () => drawer(page).locator(`[data-ask="${id}"]`).isVisible());
      await until(`${id} scrolled into view`, () => inViewport(card(page, id)));
    });
  }

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

  await check('the counter reads All answered once the last waiting ask q3 has an answer', async () => {
    writeAtomic(path.join(UI, 'sessions/s1/answers/2-q3.txt'), 'Q1 A');
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

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
