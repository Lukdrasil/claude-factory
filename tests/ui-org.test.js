// The browser half of tests/ui-org.test.sh, run by node in the Playwright container against BASE with TOKEN. The
// /api/org answers are the browser's own routes in the shape of the wave-2 contract. Every check prints one PASS or
// FAIL line; the exit code is 1 when any failed.
const { chromium } = require('playwright-core');

const { BASE, TOKEN } = process.env;
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

const ORG = {
  capacity: {
    sessions: { used: 9, cap: 10 },
    roles: [{ role: 'repo-lead', used: 2, cap: 3 }, { role: 'scout', used: 0, cap: 8 }, { role: 'implementer', used: 4, cap: 4 },
      { role: 'code-reviewer', used: 1, cap: null }],
  },
  leases: [
    { role: 'repo-lead', key: 'T-NEX-7', session: '', unit: 'T-NEX-7-lead', at: '2026-09-25T08:00:00Z' },
    { role: 'repo-lead', key: 'T-NEX-9', session: '', unit: 'T-NEX-9-lead', at: '2026-09-25T08:10:00Z' },
    { role: 'implementer', key: 's1.toolu_01', session: 's1', unit: 'T-NEX-7-01', at: '2026-09-25T08:20:00Z' },
    { role: 'code-reviewer', key: 's2.toolu_02', session: 's2', unit: '', at: '2026-09-25T08:30:00Z' },
  ],
  leads: [
    { task: 'T-NEX-7', repo: 'nexusapi', request: 'R-20260924-3', priority: 'P2', status: 'in_progress', unit: 'T-NEX-7-lead' },
    { task: 'T-NEX-9', repo: 'nexusapi', request: '', priority: 'P1', status: 'in_progress', unit: 'T-NEX-9-lead' },
  ],
  ceo: { sid: 's-ceo', pane: 'w1:p3' },
};

async function orgTab(context, body) { // a new page whose /api/org answers body (null: 404), on the Org tab
  const p = await context.newPage();
  await p.route('**/api/org', (r) => (body === null ? r.fulfill({ status: 404, body: '' })
    : r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) })));
  await p.goto(`${BASE}/#${TOKEN}`);
  await until('the Org tab', () => p.getByRole('tab', { name: 'Org' }).isVisible());
  await p.getByRole('tab', { name: 'Org' }).click();
  await until('the org view', () => p.locator('[data-org]').isVisible());
  return p;
}

const rows = (p, what) => p.locator(`[data-org] [data-${what}] tbody tr`).evaluateAll((trs) => trs.map((tr) => tr.textContent.replace(/\s+/g, ' ').trim()));

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  context.setDefaultTimeout(3000);

  await check('the page module org.js exports renderOrg', async () => {
    const p = await context.newPage();
    await p.goto(`${BASE}/`);
    const kind = await p.evaluate(async () => typeof (await import('/org.js').catch(() => ({}))).renderOrg);
    await p.close();
    ok(kind === 'function', `typeof: ${kind}`);
  });

  const p = await orgTab(context, ORG);

  await check('the Org tab shows the capacity of sessions and of every role in file order as used/cap, a role without a cap as used/-', async () => {
    const items = (await p.locator('[data-org] [data-capacity] [data-role]').allInnerTexts()).map((s) => s.replace(/\s+/g, ' ').trim());
    ok(items.join(', ') === 'sessions 9/10, repo-lead 2/3, scout 0/8, implementer 4/4, code-reviewer 1/-', `capacity: ${items.join(', ')}`);
  });

  await check('each capped entry has a meter of used against cap, the one without a cap none', async () => {
    const meters = await p.locator('[data-org] [data-capacity] [data-role]').evaluateAll((els) => els.map((el) => {
      const m = el.querySelector('meter');
      return `${el.dataset.role}=${m ? `${m.value}/${m.max}` : 'none'}`;
    }));
    ok(meters.join(' ') === 'sessions=9/10 repo-lead=2/3 scout=0/8 implementer=4/4 code-reviewer=none', `meters: ${meters.join(' ')}`);
  });

  await check('only the role at its cap, implementer, is marked full', async () => {
    const full = await p.locator('[data-org] [data-capacity] [data-role][data-full="true"]').evaluateAll((els) => els.map((e) => e.dataset.role));
    ok(full.join(' ') === 'implementer', `full: ${full.join(' ')}`);
  });

  await check('the Org tab lists every lease with its role, key, unit and session', async () => {
    const r = await rows(p, 'leases');
    ok(r.length === 4, `${r.length} lease rows: ${r.join(' | ')}`);
    for (const s of ['implementer', 's1.toolu_01', 'T-NEX-7-01', 's1']) ok(r[2].includes(s), `no ${s} in: ${r[2]}`);
    for (const s of ['repo-lead', 'T-NEX-7', 'T-NEX-7-lead']) ok(r[0].includes(s), `no ${s} in: ${r[0]}`);
  });

  await check('the Org tab lists one lead per repo-lead lease with its task, the repo as a chip after it, request, priority and status', async () => {
    const r = await rows(p, 'leads');
    ok(r.length === 2, `${r.length} lead rows: ${r.join(' | ')}`);
    for (const s of ['T-NEX-7', 'nexusapi', 'R-20260924-3', 'P2', 'in_progress', 'T-NEX-7-lead']) ok(r[0].includes(s), `no ${s} in: ${r[0]}`);
    for (const s of ['T-NEX-9', 'P1']) ok(r[1].includes(s), `no ${s} in: ${r[1]}`);
    const chip = await p.locator('[data-org] [data-leads] tbody tr').first().locator('.id').first()
      .evaluate((id) => id.nextElementSibling && id.nextElementSibling.matches('.chip') && id.nextElementSibling.textContent.trim());
    ok(chip === 'nexusapi', `next to the id: ${JSON.stringify(chip)}`);
  });

  await check('the Org tab names the CEO session s-ceo and its pane w1:p3', async () => {
    const text = await p.locator('[data-org] [data-ceo]').innerText();
    ok(/\bs-ceo\b/.test(text) && /w1:p3/.test(text), `ceo: ${text}`);
  });
  await p.close();

  await check('with no CEO, no lease and no lead the Org tab reads The CEO is not running, No lease. and No lead is running.', async () => {
    const q = await orgTab(context, { ...ORG, leases: [], leads: [], ceo: null });
    const text = await q.locator('[data-org]').innerText();
    await q.close();
    for (const s of ['The CEO is not running', 'No lease.', 'No lead is running.']) ok(text.includes(s), `no ${s} in: ${text.slice(0, 500)}`);
  });

  await check('with /api/org missing the Org tab reads No org data from the server yet. and the page shows no error', async () => {
    const q = await orgTab(context, null);
    const text = await q.locator('[data-org]').innerText();
    const errors = await q.locator('.error').allInnerTexts();
    await q.close();
    ok(text.includes('No org data from the server yet.'), `org: ${text.slice(0, 300)}`);
    ok(!errors.length, `errors: ${errors.join(' | ')}`);
  });

  await check('at 390x844 the Org tab does not scroll the page sideways', async () => {
    const q = await orgTab(context, ORG);
    await q.setViewportSize({ width: 390, height: 844 });
    await q.waitForTimeout(300);
    const over = await q.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    await q.close();
    ok(over <= 0, `the page scrolls sideways by ${over} px`);
  });

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
