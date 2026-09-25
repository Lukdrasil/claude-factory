// The browser half of tests/ui-org.test.sh, run by node in the Playwright container against BASE with TOKEN, the UI
// home mounted at UI. Without UI/org-phase the /api/org answers are the browser's own routes in the shape of the
// wave-2 contract; with `real` in it the page runs over the server of the fixture's org_state, unmocked. Every check
// prints one PASS or FAIL line; the exit code is 1 when any failed.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const { BASE, TOKEN, UI } = process.env;
const REAL = fs.existsSync(path.join(UI, 'org-phase')) && fs.readFileSync(path.join(UI, 'org-phase'), 'utf8').trim() === 'real';
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

const FIVE_MIN_AGO = String(Math.floor(Date.now() / 1000) - 300); // capacity.sh writes `at=<epoch>`
const ORG = {
  capacity: {
    sessions: { used: 9, cap: 10 },
    roles: [{ role: 'repo-lead', used: 2, cap: 3 }, { role: 'scout', used: 0, cap: 8 }, { role: 'implementer', used: 4, cap: 4 },
      { role: 'code-reviewer', used: 1, cap: null }],
  },
  leases: [
    { role: 'repo-lead', key: 'T-NEX-7', session: '', unit: 'T-NEX-7-lead', at: FIVE_MIN_AGO },
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
const capacity = (p) => p.locator('[data-capacity] [data-role]').allInnerTexts().then((t) => t.map((s) => s.replace(/\s+/g, ' ').trim()).join(', '));

const cells = (p, what, col) => p.locator(`[data-org] [data-${what}] tbody tr`).evaluateAll((trs, i) => trs.map((tr) => tr.cells[i].textContent.replace(/\s+/g, ' ').trim()), col);

async function tab(p, name) {
  await p.getByRole('tab', { name }).click();
  await until(`the ${name} tab`, async () => (await p.getByRole('tabpanel').getAttribute('aria-label')) === name);
}

async function real(context) {
  const p = await context.newPage();
  await p.goto(`${BASE}/#${TOKEN}`);

  await check('real: the grid holds the tasks of R-20260925-1 under its header row, T-ECS-1 and its blocks before T-CF-1', async () => {
    const seq = await until('the rows', async () => {
      const s = await p.locator('table').first().evaluate((table) => [...table.querySelectorAll('tbody tr')].map((r) => (r.querySelector('th[scope="rowgroup"]')
        ? `req:${(r.textContent.match(/R-\d+-\d+/) || ['none'])[0]}` : (r.querySelector('.id') || { textContent: '?' }).textContent.trim())));
      return s.length >= 5 && s;
    });
    ok(seq.join(' ') === 'req:R-20260925-1 T-ECS-1 T-ECS-1-01 T-ECS-1-02 T-CF-1', `rows: ${seq.join(' ')}`);
    const head = await p.locator('th[scope="rowgroup"]').first().innerText();
    ok(head.includes('P1') && /grilling/.test(head) && head.includes('Invoices reach the ledger every night.'), `header: ${head}`);
  });

  await check('real: each parent row carries the priority and repo of /api/board, T-CF-1 without one at P2', async () => {
    const got = await p.locator('table').first().evaluate((table) => {
      const prio = [...table.querySelectorAll('thead th')].findIndex((th) => th.textContent.trim() === 'Prio');
      return [...table.querySelectorAll('tbody tr')].filter((r) => !r.querySelector('th') && !r.classList.contains('sub'))
        .map((r) => `${r.querySelector('.id').textContent.trim()}:${r.querySelector('.id').nextElementSibling?.textContent.trim()}:${r.children[prio]?.textContent.trim()}`);
    });
    ok(got.join(' ') === 'T-ECS-1:ecs:P1 T-CF-1:claude-factory:P2', `rows: ${got.join(' ')}`);
  });

  await check('real: the capacity strip counts the leases capacity.sh took, the uncapped architecture-auditor as 1/-', async () => {
    const want = 'sessions 1/10, repo-lead 1/3, scout 1/8, implementer 1/4, architecture-auditor 1/-';
    let got = '';
    await until('the capacity strip', async () => (got = await capacity(p)) === want).catch(() => {});
    ok(got === want, `strip: ${got}`);
  });

  await check('real: the Org tab shows the lead of T-ECS-1, every lease and the CEO session s-ceo in pane w1:p9', async () => {
    await tab(p, 'Org');
    const leads = await rows(p, 'leads');
    ok(leads.length === 1 && ['T-ECS-1', 'ecs', 'R-20260925-1', 'P1', 'in_progress', 'T-ECS-1-lead'].every((s) => leads[0].includes(s)), `leads: ${leads.join(' | ')}`);
    ok((await rows(p, 'leases')).length === 5, `leases: ${(await rows(p, 'leases')).join(' | ')}`);
    const ceo = await p.locator('[data-org] [data-ceo]').innerText();
    ok(/\bs-ceo\b/.test(ceo) && /w1:p9/.test(ceo), `ceo: ${ceo}`);
  });

  await check('real: every lease shows its Since as a local time with its age, never the epoch of capacity.sh, and a unit lease its unit as the session', async () => {
    const since = await cells(p, 'leases', 4);
    ok(since.length && since.every((c) => /^\d{4}-\d\d-\d\d \d\d:\d\d \(\d+ min ago\)$/.test(c)), `since: ${since.join(' | ')}`);
    const r = await rows(p, 'leases');
    const session = await cells(p, 'leases', 3);
    const lead = r.findIndex((x) => x.startsWith('repo-lead'));
    ok(session[lead] === 'T-ECS-1-lead', `session of the repo-lead lease: ${session[lead]}`);
    ok(session.every(Boolean), `sessions: ${session.join(' | ')}`);
  });

  await check('real: a lease capacity.sh takes, which never reaches the event stream, shows in the Org tab within 10 s', async () => {
    fs.writeFileSync(path.join(UI, 'lease-now'), 'go\n');
    let got = '';
    await until('scout 2/8', async () => (got = await capacity(p)).includes('scout 2/8'), 10000).catch(() => {});
    ok(got.includes('scout 2/8'), `capacity: ${got}`);
  });

  await check('real: the Map tab shows the destination of R-20260925-1 and its open tickets 02, 04 and 05, 02 on the frontier', async () => {
    await tab(p, 'Map');
    const t = await until('the open tickets', async () => {
      const x = await p.locator('[data-map] [data-col="open"] [data-ticket]').evaluateAll((ts) => ts.map((e) => `${e.dataset.ticket}${/frontier/.test(e.textContent) ? '*' : ''}`));
      return x.length && x;
    });
    ok(t.join(' ') === '02* 04 05', `open: ${t.join(' ')}`);
    ok((await p.locator('[data-map] .dest').innerText()).includes('Invoices reach the ledger every night.'), 'no destination');
  });

  await check('real: the Map tab renders the markdown of the map, the term Ledger in bold, no ** or backtick left', async () => {
    const text = await p.locator('[data-map]').innerText();
    ok(!/\*\*|`/.test(text), `raw markdown in: ${text.slice(0, 600)}`);
    ok((await p.locator('[data-map] strong').allInnerTexts()).includes('Ledger'), 'no bold Ledger');
    ok(text.includes('Both repos post through the REST API.') && text.includes('How the two exports are ordered once both run.'), `notes and fog: ${text.slice(0, 600)}`);
  });

  await check('real: the Plan checklist lists T-CF-1 under claude-factory, then T-ECS-1 and its blocks with their acceptance under ecs', async () => {
    await tab(p, 'Plan');
    const got = await until('the checklist', async () => p.locator('[data-checklist]').evaluate((ck) => ({
      repos: [...ck.querySelectorAll('[data-plan-repo]')].map((r) => r.dataset.planRepo).join(' '),
      items: [...ck.querySelectorAll('[data-item]')].map((li) => li.dataset.item).join(' '),
      block: ck.querySelector('[data-item="T-ECS-1-01"]')?.textContent || '',
    })));
    ok(got.repos === 'claude-factory ecs', `repos: ${got.repos}`);
    ok(got.items === 'T-CF-1 T-ECS-1 T-ECS-1-01 T-ECS-1-02', `items: ${got.items}`);
    ok(got.block.includes('The cursor test passes.'), `block: ${got.block}`);
  });

  await check('real: the red block T-ECS-1-02 shows the line under its ## Spec critic, the green T-ECS-1-01 no spec-critic', async () => {
    const got = await p.locator('[data-checklist]').evaluate((ck) => ['T-ECS-1-01', 'T-ECS-1-02']
      .map((id) => ck.querySelector(`[data-item="${id}"] [data-spec-critic]`)?.textContent || ''));
    ok(got[0] === '', `green: ${got[0]}`);
    ok(got[1].includes('OK - 0 blocking, 0 suggestions (2026-09-25)'), `red: ${got[1]}`);
  });

  await check('real: Start daily of global posts an empty ask the server writes as the message 1-msg.txt of s-ceo', async () => {
    await tab(p, 'Memory');
    const row = p.locator('[data-passes] tbody tr', { has: p.locator('td:first-child', { hasText: /^\s*global\s*$/ }) });
    await until('the row of global', () => row.isVisible());
    await row.getByRole('button', { name: /start daily/i }).click();
    const file = path.join(UI, 'sessions', 's-ceo', 'answers', '1-msg.txt');
    const text = await until('the message file', () => fs.existsSync(file) && fs.readFileSync(file, 'utf8'));
    ok(text === 'start the daily pass for global', `message: ${JSON.stringify(text)}`);
    await until('the sent note', async () => /Sent to the CEO: start the daily pass for global/.test(await p.locator('[data-memory-tab]').innerText()));
  });
  await p.close();
}

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  context.setDefaultTimeout(3000);
  if (REAL) {
    await real(context);
    await browser.close();
    process.exit(failed);
  }

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

  await check('the Since of a lease at an epoch 5 min ago reads as a local time and (5 min ago), never the epoch', async () => {
    const since = await cells(p, 'leases', 4);
    ok(/^\d{4}-\d\d-\d\d \d\d:\d\d \(5 min ago\)$/.test(since[0]), `since: ${since[0]}`);
    ok(!since.join(' ').includes(FIVE_MIN_AGO), `the raw epoch: ${since.join(' | ')}`);
  });

  await check('the Session column of a unit lease without a session shows its unit', async () => {
    const session = await cells(p, 'leases', 3);
    ok(session[0] === 'T-NEX-7-lead' && session[2] === 's1', `sessions: ${session.join(' | ')}`);
  });

  await check('the Org tab explains its jargon: the pane, the lease, unit, key and session columns carry a title, the Leases a caption', async () => {
    const pane = await p.locator('[data-org] [data-ceo] [title]').evaluateAll((els) => els.map((e) => e.title).join(' '));
    ok(/pane/i.test(pane), `pane title: ${pane}`);
    for (const t of ['leases', 'leads']) {
      const titles = await p.locator(`[data-org] [data-${t}] th`).evaluateAll((ths) => Object.fromEntries(ths.map((th) => [th.textContent.trim(), th.title])));
      for (const h of t === 'leases' ? ['Role', 'Key', 'Unit', 'Session'] : ['Unit']) ok(titles[h], `no title on ${t} ${h}: ${JSON.stringify(titles)}`);
    }
    const caption = await p.locator('[data-org] h3', { hasText: 'Leases' }).evaluate((h) => h.nextElementSibling.matches('p') && h.nextElementSibling.textContent);
    ok(/lease/i.test(caption || '') && /slot/i.test(caption || ''), `caption: ${caption}`);
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

  await check('a lease with neither a session nor a unit shows - as its session', async () => {
    const q = await orgTab(context, { ...ORG, leases: [{ role: 'scout', key: 'k1', session: '', unit: '', at: '' }] });
    const session = await cells(q, 'leases', 3);
    await q.close();
    ok(session[0] === '-', `session: ${session[0]}`);
  });

  await check('at 400x844 every tab is inside the header, the grid starts within 180 px and every other tab within 150 px', async () => {
    const q = await orgTab(context, ORG);
    await q.setViewportSize({ width: 400, height: 844 });
    await q.waitForTimeout(300);
    const bad = [];
    for (const name of ['Pipeline', 'Map', 'Plan', 'Org', 'Memory', 'Setup']) {
      const { tabs, t, x } = await q.evaluate((name) => {
        const box = document.querySelector('.tabs').getBoundingClientRect();
        const el = [...document.querySelectorAll('[role="tab"]')].find((b) => b.textContent === name).getBoundingClientRect();
        return { tabs: [box.left, box.right], t: [el.left, el.right], x: document.documentElement.clientWidth };
      }, name);
      if (t[0] < Math.max(0, tabs[0]) - 0.5 || t[1] > Math.min(x, tabs[1]) + 0.5) bad.push(`tab ${name} at ${t.map(Math.round)} outside ${tabs.map(Math.round)}`);
      await q.getByRole('tab', { name }).click();
      await q.waitForTimeout(200);
      const top = await q.evaluate((name) => Math.round((document.querySelector(name === 'Pipeline' ? '.grid-wrap' : '[role="tabpanel"]')).getBoundingClientRect().top), name);
      if (top > (name === 'Pipeline' ? 180 : 150)) bad.push(`${name} starts at ${top} px`);
    }
    await q.close();
    ok(!bad.length, bad.join(', '));
  });

  await check('at 390x844 the Org tab does not scroll the page sideways', async () => {
    const q = await orgTab(context, ORG);
    await q.setViewportSize({ width: 390, height: 844 });
    await q.waitForTimeout(300);
    const over = await q.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    await q.close();
    ok(over <= 0, `the page scrolls sideways by ${over} px`);
  });

  const REQ = { id: 'R-20260925-1', status: 'planned', destination: 'Invoices reach the ledger.', priority: 'P1', parents: ['T-NEX-7'], archived: false };
  const DETAIL = { ...REQ, notes: '', terms: '', fog: 'How the exports are ordered.',
    decisions: [], outOfScope: [{ title: 'Get access', file: '03-get-access.md', gist: 'Theirs.' }, { title: 'Anything about refunds.', file: '', gist: '' }],
    tickets: [{ nn: '02', title: 'Pick the store', type: 'grilling', status: 'open', blockedBy: [], repo: 'nexusapi', claimedBy: '', question: '', answer: '' }],
    frontier: ['02'],
    parents: [{ id: 'T-NEX-7', repo: 'nexusapi', priority: 'P2', status: 'in_progress', goal: 'feat: export', acceptance: '', blocks: [
      { id: 'T-NEX-7-01', status: 'done', tier: 'green', goal: 'feat: cursor', acceptance: '', specCritic: '' },
      { id: 'T-NEX-7-02', status: 'ready', tier: 'red', goal: 'feat: job', acceptance: '', specCritic: 'needs additions before approve - 1 blocking, 0 suggestions (2026-09-25)' },
      { id: 'T-NEX-7-03', status: 'draft', tier: 'red', goal: 'feat: purge', acceptance: '', specCritic: '' }] }] };
  const m = await context.newPage();
  await m.route('**/api/requests', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([REQ]) }));
  await m.route('**/api/requests/R-20260925-1', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(DETAIL) }));
  await m.goto(`${BASE}/#${TOKEN}`);
  await until('the Map tab', () => m.getByRole('tab', { name: 'Map' }).isVisible());
  await tab(m, 'Map');
  await until('the map', () => m.locator('[data-map] [data-col="out"]').isVisible());

  await check('an out-of-scope line without a gist ends with its own text, no stray colon, and one with a gist reads title: gist', async () => {
    const items = await m.locator('[data-map] [data-col="out"] li').evaluateAll((lis) => lis.map((li) => li.textContent.trim()));
    ok(items.join(' | ') === 'Get access: Theirs. | Anything about refunds.', `out of scope: ${items.join(' | ')}`);
  });

  await check('the Map tab explains the frontier chip with a title and the fog with a caption', async () => {
    const title = await m.locator('[data-map] [data-ticket="02"] .chip', { hasText: 'frontier' }).getAttribute('title');
    ok(/blocked|unblocked/i.test(title || ''), `frontier title: ${title}`);
    const fog = await m.locator('[data-map] [data-col="fog"]').innerText();
    ok(/fog/i.test(fog), `fog column: ${fog}`);
  });

  await check('the Plan checklist marks each item with a status, not a box that reads as a checkbox', async () => {
    await tab(m, 'Plan');
    await until('the checklist', () => m.locator('[data-checklist] [data-item]').first().isVisible());
    const marks = await m.locator('[data-checklist] [data-item]').evaluateAll((lis) => lis.map((li) => {
      const s = getComputedStyle(li.firstElementChild);
      return { id: li.dataset.item, border: s.borderTopStyle, text: li.firstElementChild.textContent.trim(), title: li.firstElementChild.title };
    }));
    ok(marks.every((x) => x.border === 'none'), `bordered marks: ${JSON.stringify(marks)}`);
    ok(marks.find((x) => x.id === 'T-NEX-7-01').text === '✓', `done: ${JSON.stringify(marks)}`);
    ok(marks.every((x) => x.title), `a mark without its status as title: ${JSON.stringify(marks)}`);
  });

  await check('the Plan checklist shows spec-critic\'s line on a red block, "spec-critic missing" on a red block without one, nothing on a green one', async () => {
    const got = await m.locator('[data-checklist]').evaluate((ck) => ['T-NEX-7-01', 'T-NEX-7-02', 'T-NEX-7-03', 'T-NEX-7']
      .map((id) => ck.querySelector(`[data-item="${id}"] [data-spec-critic]`)?.textContent || ''));
    ok(got[0] === '', `green: ${got[0]}`);
    ok(got[1].includes('needs additions before approve - 1 blocking, 0 suggestions (2026-09-25)'), `red with the line: ${got[1]}`);
    ok(/spec-critic missing/.test(got[2]), `red without the line: ${got[2]}`);
    ok(got[3] === '', `parent: ${got[3]}`);
  });
  await m.close();

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
