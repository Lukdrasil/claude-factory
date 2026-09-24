// The browser half of tests/ui-task.test.sh, run by node in the Playwright container against BASE with TOKEN,
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

const drawer = (page) => page.getByRole('complementary');
const panel = (page, name) => drawer(page).locator(`[data-panel="${name}"]`);
const rail = (page) => drawer(page).getByRole('navigation');
const details = (page) => drawer(page).locator('details', { has: page.locator('summary', { hasText: /^\s*Task details\s*$/ }) });

async function expand(page) {
  const d = details(page);
  if ((await d.count()) && !(await d.first().evaluate((el) => el.open))) await d.first().locator('summary').first().click();
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

async function noPre(page) {
  await expand(page);
  const n = await drawer(page).locator('[data-panel] pre').count();
  ok(n === 0, `${n} pre elements in the panels`);
}

async function fresh(page) {
  await page.goto('about:blank');
  await page.goto(`${BASE}/#${TOKEN}`);
}

async function openTask(page, id) {
  await fresh(page);
  await until(`the row of ${id}`, () => page.locator('table tr', { hasText: id }).first().isVisible());
  await page.locator('table tr', { hasText: id }).first().getByText(id, { exact: true }).first().click();
  await until(`the drawer of ${id}`, () => drawer(page).getByText(id).first().isVisible());
  await until(`the panels of ${id}`, async () => (await drawer(page).locator('[data-panel]').count()) > 0);
}

async function panelText(page, name) {
  await expand(page);
  return until(`the ${name} panel`, async () => {
    const p = panel(page, name);
    return (await p.count()) && (await p.first().innerText());
  });
}

function holds(text, items) {
  for (const item of items) {
    const hit = item instanceof RegExp ? item.test(text) : text.includes(item);
    ok(hit, `no ${item} in: ${text.slice(0, 500)}`);
  }
}

async function current(page) {
  await expand(page);
  return until('the current step of the rail', async () => {
    const c = rail(page).locator('[aria-current="step"]');
    return (await c.count()) === 1 && (await c.innerText());
  });
}

async function confirmYes(page, name, key) {
  const [sid, ask] = key.split('/');
  const c = drawer(page).locator(`[data-ask="${key}"]`);
  await until(`${key} in the drawer`, () => c.isVisible());
  ok((await drawer(page).locator(`[data-ask="${key}"]`).count()) === 1, `${key} is in the drawer more than once`);
  ok(await c.getByRole('button', { name: /\byes\b/i }).count(), 'no yes');
  ok(await c.getByRole('button', { name: /\bno\b/i }).count(), 'no no');
  await c.getByRole('button', { name: /\byes\b/i }).first().click();
  await c.getByRole('button', { name: /send/i }).click();
  const files = await until(`an answer file for ${ask}`, () => {
    const f = answers(sid).filter((n) => new RegExp(`^\\d+-${ask}\\.txt$`).test(n));
    return f.length && f;
  });
  const text = fs.readFileSync(path.join(UI, 'sessions', sid, 'answers', files[0]), 'utf8');
  ok(text === 'Q1 A', `file: ${JSON.stringify(text)}`);
}

(async () => {
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 } })).newPage();
  page.setDefaultTimeout(3000);

  await check('the page modules export renderTaskPanels and renderBlockedQuestion', async () => {
    await page.goto(`${BASE}/`);
    const kinds = await page.evaluate(async () => {
      const load = (m) => import(m).catch(() => ({}));
      return [
        typeof (await load('/task-panels.js')).renderTaskPanels,
        typeof (await load('/blocked.js')).renderBlockedQuestion,
      ].join(' ');
    });
    ok(kinds === 'function function', `typeof: ${kinds}`);
  });

  await check('section takes rendered HTML and returns the nodes under the <h2> it names, up to the next <h2>', async () => {
    const got = await page.evaluate(async () => {
      const { section } = await import('/task-panels.js');
      const html = '<h1>Title</h1><h2 id="context">Context</h2><p>first</p><ul><li>one</li></ul><h3>Deeper</h3><p>still</p>'
        + '<h2 id="next">Next</h2><p>after</p>';
      const text = (r) => (r instanceof Node ? [r] : [...(r || [])]).map((n) => (n instanceof Node ? n.textContent : `not a node: ${n}`)).join('');
      return { hit: text(section(html, 'Context')), miss: text(section(html, 'Missing')) };
    });
    ok(got.hit === 'firstoneDeeperstill', `Context: ${JSON.stringify(got.hit)}`);
    ok(got.miss === '', `Missing: ${JSON.stringify(got.miss)}`);
  });

  for (const [width, height] of [[1440, 900], [390, 844]]) {
    await page.setViewportSize({ width, height });
    await openTask(page, 'T-021');

    await check(`at ${width}x${height} opening T-021 shows the question and options of its approve confirm in the first viewport`, async () => {
      const q = drawer(page).locator('[data-ask="s21/ap1"] [data-q="Q1"]');
      await until('Q1 of ap1', async () => (await q.count()) === 1);
      ok(/Approve T-021\?/.test(await q.locator('h4').innerText()), `Q1 reads ${await q.locator('h4').innerText()}`);
      const off = await exposed(page, ['h4', '[data-act="pick"]'].map((e) => `aside [data-ask="s21/ap1"] [data-q="Q1"] ${e}`).join(', '));
      ok(!off.length, off.join(' | '));
    });

    await check(`at ${width}x${height} T-021 opens with Task details collapsed and the approve confirm outside it`, async () => {
      ok((await details(page).count()) === 1, `${await details(page).count()} Task details`);
      ok(!(await details(page).evaluate((el) => el.open)), 'Task details is open');
      ok(!(await details(page).locator('[data-ask="s21/ap1"]').count()), 'the confirm is inside Task details');
    });
  }
  await page.setViewportSize({ width: 1440, height: 900 });

  // --- T-021 at step 9: the rail, decompose with its cut check, approve as a confirm with the whole body ---------
  await openTask(page, 'T-021');

  await check('the rail of T-021 runs from triage to the done gate', async () => {
    await expand(page);
    const text = await until('the rail', async () => (await rail(page).count()) && rail(page).innerText());
    holds(text, [/triage/i, /grill/i, /approve/i, /\bMR\b/, /\bdone\b/i]);
  });

  await check('the rail of T-021 has step 3b chart between 3 triage and 4 grill', async () => {
    const steps = await rail(page).locator('li').allInnerTexts();
    const at = steps.map((s) => s.trim()).join(' | ');
    ok(/(^| \| )3 triage \| 3b chart \| 4 grill( \| |$)/.test(at), `rail: ${at}`);
  });

  await check('the rail of T-021 marks step 9, approve, the step its session reports, as current', async () => {
    holds(await current(page), [/(^|\D)9(\D|$)/, /approve/i]);
  });

  await check('the decompose panel of T-021 lists its draft blocks and the cut check: the wave plan and the cut-check verdict', async () => {
    holds(await panelText(page, 'decompose'), ['T-021-01', 'T-021-02', 'block two of T-021', /draft/,
      /wave 2\W+T-021-02/, 'The cut-check sentence of cf-ap.']);
  });

  await check('the approve panel of T-021 shows the whole body, its Out of scope included, and the block list', async () => {
    holds(await panelText(page, 'approve'), ['the fixture task waiting for approval',
      'The context sentence the approver must read in full.', 'sh tests/fx-021.test.sh',
      'The last sentence of the body of T-021.', 'T-021-01', 'T-021-02']);
  });

  await check('the panels of T-021 hold no pre: the body is rendered', async () => {
    await noPre(page);
  });

  await check('the approve confirm of T-021 is in the drawer once and its yes sends Q1 A to its session', async () => {
    await confirmYes(page, 'approve', 's21/ap1');
  });

  await check('T-021, not blocked, has no blocked panel', async () => {
    ok(!(await panel(page, 'blocked').count()), 'a blocked panel');
  });

  // --- T-022 at step 4: the grill panel from the grill file whose task: is T-022, found before any plan names it ---
  await openTask(page, 'T-022');

  await check('the rail of T-022 marks step 4, grill, as current', async () => {
    holds(await current(page), [/(^|\D)4(\D|$)/, /grill/i]);
  });

  await check('the triage panel of T-022 shows its context, tier and archetype', async () => {
    holds(await panelText(page, 'triage'), ['The triage context sentence of T-022.', /yellow/, /feature/]);
  });

  await check('the grill panel of T-022 shows the ledger with open and closed rows, the terms and the design round of its grill file', async () => {
    holds(await panelText(page, 'grill'), ['Which gauge store?', 'the flat file', 'Which gauge port?', /\bopen\b/,
      /\bclosed\b/, 'fixture gauge', 'the term the grill settled', 'src/gauge.js', 'readGauge']);
  });

  await check('the triage panel of T-022 renders the list of its context as a list', async () => {
    await panelText(page, 'triage');
    const items = await panel(page, 'triage').locator('li').allInnerTexts();
    ok(items.includes('the first context item of T-022') && items.includes('the second context item of T-022'),
      `list items: ${JSON.stringify(items)}`);
  });

  await check('the panels of T-022 hold no pre', async () => {
    await noPre(page);
  });

  await check('the decompose panel of T-022, with nothing yet, reads Nothing recorded for this step yet.', async () => {
    const text = await panelText(page, 'decompose');
    holds(text, ['Nothing recorded for this step yet.']);
    ok(!text.includes('Nothing yet.'), `the old text: ${text.slice(0, 300)}`);
  });

  await check('the drawer of T-022, with no ask, reads No open questions for this task.', async () => {
    holds(await drawer(page).innerText(), ['No open questions for this task.']);
  });

  await check('the grill panel of T-022 holds nothing of the grill file of another task', async () => {
    const text = await panelText(page, 'grill');
    ok(!text.includes('Which decoy store?'), `the decoy row of T-099 is there: ${text.slice(0, 300)}`);
  });

  // --- T-020 at step 16: the finished grill, blocks, verify and review verdicts, the MR list and the done gate -----
  await openTask(page, 'T-020');

  await check('the rail of T-020 marks step 16 as current', async () => {
    holds(await current(page), [/(^|\D)16(\D|$)/]);
  });

  await check('the triage panel of T-020 shows the context the triage wrote', async () => {
    holds(await panelText(page, 'triage'), ['The triage found the fixture context sentence of T-020.']);
  });

  await check('the grill panel of T-020 shows the ledger, terms and design of its finished plan', async () => {
    holds(await panelText(page, 'grill'), ['Which finished store?', 'fixture widget', 'fxFinished']);
  });

  await check('the blocks panel of T-020 lists each block with its status and goal', async () => {
    holds(await panelText(page, 'blocks'), [/T-020-01[^\n]*\bdone\b/, /T-020-02[^\n]*\breview\b/,
      'block one of T-020', 'block two of T-020']);
  });

  await check('the verdicts panel of T-020 shows each block\'s verify evidence and the review verdict', async () => {
    holds(await panelText(page, 'verdicts'), ['tests: 3 run, 3 passed, 0 failed', 'tests: 5 run, 5 passed, 0 failed',
      'changes needed']);
  });

  await check('the MR panel of T-020 links the parent MR and every block MR', async () => {
    await panelText(page, 'mr');
    for (const n of ['20', '201', '202']) {
      ok(await panel(page, 'mr').locator(`a[href="https://example.invalid/mr/${n}"]`).count(), `no link to mr/${n}`);
    }
  });

  await check('the wave of T-020 reads Not started for each block with no owner', async () => {
    await panelText(page, 'wave');
    for (const id of ['T-020-01', 'T-020-02']) {
      holds(await panel(page, 'wave').locator(`[data-block="${id}"]`).innerText(), [/\bNot started\b/]);
    }
  });

  await check('the panels of T-020 hold no pre: evidence and review are rendered', async () => {
    await noPre(page);
  });

  await check('the done confirm of T-020 is in the drawer once and its yes sends Q1 A to its session', async () => {
    await confirmYes(page, 'done', 's20/dn1');
  });

  await check('T-020, not blocked, has no blocked panel', async () => {
    ok(!(await panel(page, 'blocked').count()), 'a blocked panel');
  });

  // --- blocked: routed to a live session in herdr, else the solve command to copy -------------------------------
  await openTask(page, 'T-023');

  await check('blocked T-023 shows its ## Question from the state, its options and recommendation', async () => {
    holds(await panelText(page, 'blocked'), ['Which fixture queue should T-023 drain first?', 'the old queue',
      'the new queue', 'the old one is empty']);
  });

  await check('the blocked panel of T-023 reads T-023 is blocked and needs a decision, its options a rendered list', async () => {
    holds(await panelText(page, 'blocked'), ['T-023 is blocked and needs a decision']);
    const items = await panel(page, 'blocked').locator('li').allInnerTexts();
    ok(items.includes('the old queue') && items.includes('the new queue'), `list items: ${JSON.stringify(items)}`);
    ok(!(await panel(page, 'blocked').locator('pre').count()), 'a pre in the blocked panel');
  });

  await check('blocked T-023 goes to its live session s23 in herdr, with no solve command', async () => {
    const text = await panelText(page, 'blocked');
    holds(text, [/\bs23\b/]);
    ok(!/factory solve T-023/.test(text), `a solve command: ${text.slice(0, 300)}`);
  });

  await openTask(page, 'T-024');

  await check('blocked T-024, whose only session is outside herdr, shows its question and the solve command to copy', async () => {
    holds(await panelText(page, 'blocked'), ['Which fixture lane should T-024 take?']);
    ok(await panel(page, 'blocked').locator('code', { hasText: /factory solve T-024\b/ }).count(), 'no solve command in a code element');
  });

  await openTask(page, 'T-025');

  await check('the drawer of T-025 shows the question of its blocked block T-025-01 and the solve command of the parent', async () => {
    holds(await panelText(page, 'blocked'), ['Which fixture cache should T-025-01 keep?']);
    ok(await panel(page, 'blocked').locator('code', { hasText: /factory solve T-025\b/ }).count(), 'no solve command in a code element');
  });

  await check('the drawer of T-025 reads T-025-01 is blocked and needs a decision and No session is working on this task.', async () => {
    holds(await panelText(page, 'blocked'), ['T-025-01 is blocked and needs a decision']);
    holds(await drawer(page).innerText(), ['No session is working on this task.']);
  });

  await openTask(page, 'T-027');

  for (const [n, text] of [[1, 'Idle'], [2, 'Working'], [3, 'Finished its turn'], [4, 'Session ended'], [5, 'Waiting at a dialog']]) {
    await check(`the wave of T-027 reads ${text} for the worker of T-027-0${n}`, async () => {
      await panelText(page, 'wave');
      holds(await panel(page, 'wave').locator(`[data-block="T-027-0${n}"]`).innerText(), [`s27w${n}`, new RegExp(`\\b${text}\\b`)]);
    });
  }

  // --- T-026: registered through solve-next.sh --ui only, so its task and step come from what production writes ---
  await check('the grid row of T-026 marks step 3, the step solve-next.sh recorded, with its session s26', async () => {
    await fresh(page);
    const row = page.locator('table tr', { hasText: 'T-026' }).first();
    await until('the row of T-026', () => row.isVisible());
    const at = await until('the current cell of T-026', async () => {
      const i = await row.locator('td').evaluateAll((tds) => tds.findIndex((td) => td.getAttribute('aria-current') === 'step'));
      return i > 0 && i;
    });
    const head = await page.locator('table thead th').nth(at).innerText();
    ok(/^3\b/.test(head.trim()), `current under the column ${JSON.stringify(head)}`);
    ok(/\bs26\b/.test(await row.locator('td[aria-current="step"]').innerText()), 'no s26 chip in the current cell');
  });

  await openTask(page, 'T-026');

  await check('the rail of T-026 marks step 3, triage, as current', async () => {
    holds(await current(page), [/(^|\D)3(\D|$)/, /triage/i]);
  });

  // --- T-028 at step 3b: charting its request map, a column and a rail step of its own ----------------------------
  await check('the grid row of T-028 marks the column 3b chart, the step its session reports, with its session s28', async () => {
    await fresh(page);
    const row = page.locator('table tr', { hasText: 'T-028' }).first();
    await until('the row of T-028', () => row.isVisible());
    const at = await until('the current cell of T-028', async () => {
      const i = await row.locator('td').evaluateAll((tds) => tds.findIndex((td) => td.getAttribute('aria-current') === 'step'));
      return i > 0 && i;
    });
    const head = (await page.locator('table thead th').nth(at).innerText()).replace(/\s+/g, ' ').trim();
    ok(head === '3b chart', `current under the column ${JSON.stringify(head)}`);
    ok(/\bs28\b/.test(await row.locator('td[aria-current="step"]').innerText()), 'no s28 chip in the current cell');
  });

  await openTask(page, 'T-028');

  await check('the rail of T-028 marks step 3b, chart, as current', async () => {
    holds(await current(page), [/^\s*3b chart\s*$/]);
  });

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
