// The browser half of tests/ui-visual.test.sh, run by node in the Playwright container against BASE with TOKEN,
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

const session = (sid) => path.join(UI, 'sessions', sid);

function put(sid, file, text) {
  const temp = path.join(session(sid), `.${file}.tmp`);
  fs.writeFileSync(temp, text);
  fs.renameSync(temp, path.join(session(sid), file));
}

const meta = (row, version, status) => `---\nrow: ${row}\nversion: ${version}\nstatus: ${status}\n---\n`;

function answers(sid) {
  const dir = path.join(session(sid), 'answers');
  return fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => !f.startsWith('.')).sort() : [];
}

const drawer = (page) => page.getByRole('complementary');
const visual = (page, sid) => drawer(page).locator(`[data-visual="${sid}"]`);
const frameText = (page, sid) => visual(page, sid).frameLocator('iframe').locator('#out').innerText();
const staleMark = /out of date/i;

async function openTask(page, id) {
  await page.goto('about:blank');
  await page.goto(`${BASE}/#${TOKEN}`);
  await until(`the row of ${id}`, () => page.locator('table tr', { hasText: id }).first().isVisible());
  await page.locator('table tr', { hasText: id }).first().getByText(id, { exact: true }).first().click();
  await until(`the drawer of ${id}`, () => drawer(page).getByText(id).first().isVisible());
}

async function visualText(page, sid) {
  return until(`the visual of ${sid}`, async () => {
    const v = visual(page, sid);
    return (await v.count()) === 1 && (await v.innerText());
  });
}

(async () => {
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1400, height: 900 } })).newPage();
  page.setDefaultTimeout(3000);

  await check('the page module /visual.js exports renderVisual', async () => {
    await page.goto(`${BASE}/`);
    const kind = await page.evaluate(async () => typeof (await import('/visual.js').catch(() => ({}))).renderVisual);
    ok(kind === 'function', `typeof: ${kind}`);
  });

  // --- v1, current: the row, the version, the frame ------------------------------------------------------------
  await openTask(page, 'T-030');

  await check('the drawer of T-030 shows the visual of session s30 with its row and version 1', async () => {
    const text = await visualText(page, 's30');
    ok(/\brow 3\b/i.test(text), `no row 3 in: ${text.slice(0, 300)}`);
    ok(/\bv(ersion)?\s*1\b/i.test(text), `no version 1 in: ${text.slice(0, 300)}`);
  });

  await check('a current visual carries no out-of-date mark', async () => {
    const text = await visualText(page, 's30');
    ok(!staleMark.test(text), `an out-of-date mark on a current visual: ${text.slice(0, 300)}`);
  });

  await check('the visual is one iframe sandboxed to allow-scripts alone, on /visual with the sid and the token as query parameters', async () => {
    const frames = visual(page, 's30').locator('iframe');
    ok((await frames.count()) === 1, `iframes: ${await frames.count()}`);
    const sandbox = await frames.getAttribute('sandbox');
    ok(sandbox !== null && sandbox.trim() === 'allow-scripts', `sandbox: ${JSON.stringify(sandbox)}`);
    const src = new URL(await frames.getAttribute('src'), BASE);
    ok(src.pathname === '/visual', `path: ${src.pathname}`);
    ok(src.searchParams.get('sid') === 's30', `sid: ${src.searchParams.get('sid')}`);
    ok(src.searchParams.get('token') === TOKEN, 'the token is not the query parameter token');
  });

  await check('the visual\'s own script runs in the frame and cannot reach the page', async () => {
    const text = await until('the drawn frame', async () => {
      const t = await frameText(page, 's30');
      return /^drawn /.test(t) && t;
    });
    ok(text === 'drawn v1 of s30 by script, isolated from the page', `frame: ${text}`);
  });

  await check('the drawer of T-031, whose session has no visual, shows no visual frame', async () => {
    await openTask(page, 'T-031');
    await until('the drawer of T-031 settled', () => drawer(page).getByText('s31').first().isVisible());
    ok(!(await drawer(page).locator('[data-visual], iframe').count()), 'a visual in the drawer of T-031');
  });

  // --- a changed answer: the session marks the visual stale --------------------------------------------------------
  await openTask(page, 'T-030');
  await visualText(page, 's30').catch(() => null);
  put('s30', 'visual.md', meta(3, 1, 'stale'));

  await check('the visual is marked out of date once the session marks it stale, still version 1', async () => {
    const text = await until('the out-of-date mark', async () => {
      const t = await visualText(page, 's30');
      return staleMark.test(t) && t;
    });
    ok(/\bv(ersion)?\s*1\b/i.test(text), `no version 1 in: ${text.slice(0, 300)}`);
  });

  await check('Redraw on the visual sends Q3 redraw to the open ask of its session', async () => {
    await visual(page, 's30').getByRole('button', { name: /redraw/i }).click();
    const files = await until('an answer file for g1', () => {
      const f = answers('s30').filter((n) => /^\d+-g1\.txt$/.test(n));
      return f.length && f;
    });
    ok(files.length === 1, `answer files: ${files.join(' ')}`);
    const text = fs.readFileSync(path.join(session('s30'), 'answers', files[0]), 'utf8');
    ok(text === 'Q3 redraw', `file: ${JSON.stringify(text)}`);
  });

  // --- the redraw: a new file and version 2, current ---------------------------------------------------------------
  put('s30', 'visual.html', fs.readFileSync(path.join(session('s30'), 'visual.html'), 'utf8').replace('drawn v1', 'drawn v2'));
  put('s30', 'visual.md', meta(3, 2, 'current'));

  await check('the redrawn visual shows version 2 and no out-of-date mark', async () => {
    const text = await until('version 2', async () => {
      const t = await visualText(page, 's30');
      return /\bv(ersion)?\s*2\b/i.test(t) && t;
    });
    ok(!staleMark.test(text), `an out-of-date mark on the redrawn visual: ${text.slice(0, 300)}`);
  });

  await check('the frame shows the redrawn file', async () => {
    const text = await until('the redrawn frame', async () => {
      const t = await frameText(page, 's30');
      return /^drawn v2 /.test(t) && t;
    });
    ok(text === 'drawn v2 of s30 by script, isolated from the page', `frame: ${text}`);
  });

  await browser.close();
  process.exit(failed);
})().catch((e) => {
  console.log(`FAIL the browser run: ${e.message}`);
  process.exit(1);
});
