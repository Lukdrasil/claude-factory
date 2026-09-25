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

  // --- T-029: one state per ask, live asks first and answerable, the rest read-only, one sticky footer ------------
  const card = (key) => drawer(page).locator(`[data-ask="${key}"]`);
  const opt = (key, q, k) => card(key).locator(`[data-q="${q}"] [data-act="pick"][data-k="${k}"]`);
  const STATES = [['open', /Needs your answer/], ['sent', /Sent, waiting for the session/], ['answered', /\bAnswered\b/],
    ['gone', /Not delivered: the session has ended/]];
  const sticky = () => page.evaluate(() => [...document.querySelectorAll('aside .ask-f')]
    .filter((f) => getComputedStyle(f).position === 'sticky').map((f) => f.closest('[data-ask]').dataset.ask).join(' '));
  const lines = (text) => text.split('\n').map((l) => l.trim()).filter(Boolean).join('|');
  await page.setViewportSize({ width: 1440, height: 900 });
  await openTask(page, 'T-029');

  await check('the drawer of T-029 lists the live c1 and r1 first, then x1, x2 and gn1, each group oldest first', async () => {
    await until('r1 in the drawer', () => card('s29/r1').isVisible());
    const order = await drawer(page).locator('[data-ask]').evaluateAll((els) => els.map((e) => e.dataset.ask).join(' '));
    ok(order === 's29/c1 s29/r1 s29/x1 s29/x2 s29g/gn1', `order: ${order}`);
  });

  for (const [key, state] of [['s29/c1', 'open'], ['s29/x2', 'sent'], ['s29/x1', 'gone'], ['s29g/gn1', 'gone']]) {
    await check(`the header of ${key} reads the one state ${state}`, async () => {
      const head = await card(key).locator('.ask-h').innerText();
      const hits = STATES.filter(([, re]) => re.test(head)).map(([s]) => s);
      ok(hits.join(' ') === state, `states ${JSON.stringify(hits)} in: ${head}`);
    });
  }

  for (const key of ['s29/x1', 's29/x2', 's29g/gn1']) {
    await check(`${key}, not open to an answer, is read-only: its options disabled, no Send, no answer box`, async () => {
      const c = card(key);
      const live = await c.locator('[data-act="pick"]').evaluateAll((bs) => bs.filter((b) => !b.disabled).length);
      ok(live === 0, `${live} enabled options`);
      ok((await c.locator('[data-act="pick"]').count()) === 2, 'no options');
      ok(!(await c.getByRole('button', { name: /send|write my answer|explain more/i }).count()), 'a Send or answer button');
      ok(!(await c.getByRole('textbox').count()), 'a text box');
    });
  }

  await check('the sent x2 shows its answer Q1 A in words, read-only, and the gone x1 does not', async () => {
    const got = (await card('s29/x2').locator('[data-sent] li').allInnerTexts()).map((t) => t.replace(/\s+/g, ' ').trim());
    ok(JSON.stringify(got) === '["Q1 A yes"]', `sent: ${JSON.stringify(got)}`);
    ok(await opt('s29/x2', 'Q1', 'A').getAttribute('aria-pressed') === 'true', 'A of the sent x2 is not pressed');
    ok(!(await card('s29/x1').locator('[data-sent]').count()), 'the gone x1 shows a sent answer');
  });

  await check('the open c1 keeps its enabled options and its Send', async () => {
    const live = await card('s29/c1').locator('[data-act="pick"]').evaluateAll((bs) => bs.filter((b) => !b.disabled).length);
    ok(live === 2, `${live} enabled options`);
    ok(await card('s29/c1').getByRole('button', { name: /^send answer$/i }).count(), 'no Send');
  });

  await check('picking B of Q1 of r1 marks it aria-pressed with a visible check, the others not pressed', async () => {
    await opt('s29/r1', 'Q1', 'B').click();
    const pressed = await card('s29/r1').locator('[data-q="Q1"] [data-act="pick"]')
      .evaluateAll((bs) => bs.map((b) => `${b.dataset.k}=${b.getAttribute('aria-pressed')}`).join(' '));
    ok(pressed === 'A=false B=true C=false', `aria-pressed: ${pressed}`);
    const tick = opt('s29/r1', 'Q1', 'B').getByText('✓');
    ok((await tick.count()) === 1 && (await tick.isVisible()), 'no visible check mark on B');
    ok(!(await opt('s29/r1', 'Q1', 'A').getByText('✓').count()), 'a check mark on A');
    ok(await card('s29/r1').locator('[data-q="Q1"]').getByRole('button', { name: /^B\b/ }).count(), 'the name of B no longer starts with B');
  });

  await check('the focus stays on B of Q1 of r1 after the click re-renders the drawer', async () => {
    const at = await page.evaluate(() => {
      const a = document.activeElement;
      return `${a.closest('[data-ask]')?.dataset.ask} ${a.closest('[data-q]')?.dataset.q} ${a.dataset.k}`;
    });
    ok(at === 's29/r1 Q1 B', `focus on ${at}`);
  });

  await check('Explain more on Q2 of r1 is aria-pressed once staged and keeps the focus', async () => {
    const more = card('s29/r1').locator('[data-q="Q2"] [data-act="more"]');
    ok(await more.getAttribute('aria-pressed') === 'false', `before: ${await more.getAttribute('aria-pressed')}`);
    await more.click();
    ok(await more.getAttribute('aria-pressed') === 'true', `after: ${await more.getAttribute('aria-pressed')}`);
    const act = await page.evaluate(() => `${document.activeElement.closest('[data-q]')?.dataset.q} ${document.activeElement.dataset.act}`);
    ok(act === 'Q2 more', `focus on ${act}`);
  });

  await check('the staged items of r1 read in a neutral colour and the preview reads them, the output keeps the exact text', async () => {
    const q3 = card('s29/r1').locator('[data-q="Q3"]');
    await q3.getByRole('button', { name: /write my answer/i }).click();
    await q3.getByRole('textbox').fill('the fixture part, kept');
    await q3.getByRole('button', { name: /add to answer/i }).click();
    const colours = await page.evaluate(() => {
      const probe = document.createElement('span');
      probe.className = 'chip warn';
      document.body.append(probe);
      const warn = getComputedStyle(probe).color;
      probe.remove();
      return [...document.querySelectorAll('aside [data-ask="s29/r1"] .staged')].map((s) => getComputedStyle(s).color).concat(warn);
    });
    const warn = colours.pop();
    ok(colours.length === 3, `${colours.length} staged lines`);
    ok(colours.every((c) => c !== warn), `a staged line in the warning colour ${warn}`);
    const f = card('s29/r1').locator('.ask-f');
    const out = await f.locator('output').innerText();
    ok(lines(out) === 'Q1 B|Q2 more|Q3 the fixture part, kept', `output: ${JSON.stringify(out)}`);
    const shown = (await f.innerText()).replace(out, '');
    holds(shown, ['Will be sent:', /Q1\W+B\b/, /Q2\W+Explain more/, /Q3\W+the fixture part, kept/]);
    ok(!/Q2 more/.test(shown), `raw text in the preview: ${shown}`);
  });

  await check('Esc closes the drawer of T-029 and puts the focus on its row', async () => {
    await page.keyboard.press('Escape');
    await until('no drawer', async () => !(await drawer(page).count()), 1000);
    const at = await page.evaluate(() => document.activeElement?.dataset.drawer);
    ok(at === 'T-029', `focus on ${at}`);
  });

  await openTask(page, 'T-029');

  await check('the answers staged on r1 are still there after a reload', async () => {
    await until('r1 in the drawer', () => card('s29/r1').isVisible());
    ok(await opt('s29/r1', 'Q1', 'B').getAttribute('aria-pressed') === 'true', 'B of Q1 is not pressed');
    const out = await card('s29/r1').locator('.ask-f output').innerText();
    ok(lines(out) === 'Q1 B|Q2 more|Q3 the fixture part, kept', `output: ${JSON.stringify(out)}`);
  });

  await check('only the first live card c1 has a sticky footer, so one Send sticks', async () => {
    const got = await sticky();
    ok(got === 's29/c1', `sticky footers: ${JSON.stringify(got)}`);
  });

  await check('with c1 scrolled out, the long r1 has the one sticky footer and its Send is in view', async () => {
    await page.evaluate(() => {
      const a = document.querySelector('aside');
      a.scrollTop += a.querySelector('[data-ask="s29/c1"]').getBoundingClientRect().bottom - a.querySelector('.drawer-h').getBoundingClientRect().bottom + 20;
    });
    await until('r1 sticky', async () => (await sticky()) === 's29/r1', 1000);
    const off = await exposed(page, 'aside [data-ask="s29/r1"] [data-act="send"]');
    ok(!off.length, off.join(' | '));
  });

  await check('?ask=s29/r1 opens T-029 with r1 marked current and highlighted, c1 not', async () => {
    await page.goto('about:blank');
    await page.goto(`${BASE}/?ask=s29/r1#token=${TOKEN}`);
    await until('r1 in the drawer', () => card('s29/r1').isVisible());
    await until('r1 aria-current', async () => (await card('s29/r1').getAttribute('aria-current')) === 'true', 1000);
    ok(!(await card('s29/c1').getAttribute('aria-current')), 'c1 is aria-current');
    const look = (key) => card(key).evaluate((e) => {
      const s = getComputedStyle(e);
      return `${s.outlineStyle} ${s.outlineColor} ${s.borderColor} ${s.boxShadow}`;
    });
    const [r1, c1] = [await look('s29/r1'), await look('s29/c1')];
    ok(r1 !== c1, `r1 looks like c1: ${r1}`);
  });

  // --- the token and the change stream: a plain message for a token the server refuses, a cue while the stream is down
  await check('a token the server refuses reads The UI token is not valid any more, no status code', async () => {
    await page.goto('about:blank');
    await page.goto(`${BASE}/#token=not-the-token`);
    const text = await until('the token message', async () => {
      const t = await page.locator('body').innerText();
      return /The UI token is not valid any more: open the URL ui-up\.sh printed\./.test(t) && t;
    });
    ok(!/\b401\b|answered/.test(text), `the raw error: ${text.slice(0, 300)}`);
  });

  await check('while the change stream is down the page shows it may be out of date, and the cue clears on reconnect', async () => {
    const cue = page.getByText(/may be out of date/i);
    await page.route('**/api/stream', (route) => route.abort());
    await fresh(page);
    await until('the stale cue', () => cue.isVisible(), 5000);
    ok(!(await page.locator('.error').count()), `an error: ${await page.locator('.error').first().innerText().catch(() => '')}`);
    await page.unroute('**/api/stream');
    await until('no stale cue', async () => !(await cue.count()), 5000);
  });

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
