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

async function fresh(page) {
  await page.goto('about:blank');
  await page.goto(`${BASE}/#${TOKEN}`);
}

async function openTask(page, id) {
  await fresh(page);
  await until(`the row of ${id}`, () => page.locator('table tr', { hasText: id }).first().isVisible());
  await page.locator('table tr', { hasText: id }).first().getByText(id, { exact: true }).first().click();
  await until(`the drawer of ${id}`, () => drawer(page).getByText(id).first().isVisible());
}

async function panelText(page, name) {
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
  return until('the current step of the rail', async () => {
    const c = rail(page).locator('[aria-current="step"]');
    return (await c.count()) === 1 && (await c.innerText());
  });
}

async function confirmYes(page, name, key) {
  const [sid, ask] = key.split('/');
  const c = panel(page, name).locator(`[data-ask="${key}"]`);
  await until(`${key} in the ${name} panel`, () => c.isVisible());
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
  const page = await (await browser.newContext({ viewport: { width: 1400, height: 900 } })).newPage();
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

  // --- T-021 at step 9: the rail, decompose with its cut check, approve as a confirm with the whole body ---------
  await openTask(page, 'T-021');

  await check('the rail of T-021 runs from triage to the done gate', async () => {
    const text = await until('the rail', async () => (await rail(page).count()) && rail(page).innerText());
    holds(text, [/triage/i, /grill/i, /approve/i, /\bMR\b/, /\bdone\b/i]);
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

  await check('the approve panel of T-021 is a confirm whose yes sends Q1 A to its session', async () => {
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

  await check('the done panel of T-020 is a confirm whose yes sends Q1 A to its session', async () => {
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

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
