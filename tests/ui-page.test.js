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
  await q.getByRole('button', { name: /add to answer/i }).last().click();
}

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });
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
