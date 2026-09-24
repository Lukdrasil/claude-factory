export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

export const inline = (s) => esc(s)
  .replace(/\*\*(.+?)\*\*/g, '<b>$1</b>')
  .replace(/`([^`]+)`/g, '<code>$1</code>');

const HELD = {
  blocked: 'held: the session sits at a dialog, answer it in its pane',
  gone: 'held: the session is gone',
  'prompt-failed': 'held: herdr refused the prompt',
};

const FORMS = {
  pick: (q, text) => `${q} ${text}`,
  own: (q, text) => `${q} ${text}`,
  discuss: (q, text) => `${q} ? ${text}`,
  more: (q) => `${q} more`,
  explore: (q) => `explore ${q}`,
  defer: (q) => `${q} defer`,
};

/** Splits an ask's markdown into its questions: a notice has none, a confirm is one question with the options yes and no. */
export function parseAsk(body) {
  const questions = body.split(/^❓ /m).slice(1).map((part) => {
    const [, q, title, after, text] = part.match(/^\*\*(Q\d+)\*\* - \*\*(.+?)\*\*(?: \((after [^)]*)\))?:?[ \t]*(.*)/) || [];
    const options = [...part.matchAll(/^[ \t]+\*\*([A-Z])\*\* (.+)$/gm)].map(([, key, label]) => ({ key, label }));
    const rec = (part.match(/^➡️ (.*)$/m) || [])[1] || '';
    return { q, title, after, text, options, rec, recKey: (rec.match(/^\*\*([A-Z])\*\*/) || [])[1] };
  }).filter((q) => q.q);
  if (!questions.length) return { kind: 'notice', text: body.trim(), questions };
  const yesNo = questions.length === 1 && questions[0].options.map((o) => o.label.trim().toLowerCase()).join() === 'yes,no';
  return { kind: yesNo ? 'confirm' : 'round', questions };
}

/** The shorthand the relay types for the staged items, in question order: `Q1 B, Q2 more, explore Q3`. */
export function compose(parsed, items) {
  if (parsed.kind === 'notice') return 'ok';
  return parsed.questions
    .filter(({ q }) => items[q])
    .map(({ q }) => FORMS[items[q].kind](q, items[q].text.replace(/\s+/g, ' ').trim()))
    .join(', ');
}

function notice(text) {
  return `<div class="md">${text.split(/\n+/).map((line) => (/^#+ /.test(line)
    ? `<h4>${inline(line.replace(/^#+ /, ''))}</h4>`
    : `<p>${inline(line)}</p>`)).join('')}</div>`;
}

function question(q, kind, staged, live) {
  const item = staged.items[q.q];
  const editing = staged.editing[q.q];
  const on = (act, text = '') => item && item.kind === act && item.text === text;
  const action = (act, label) => `<button class="btn sm ${on(act) || editing === act ? 'on' : ''}" data-act="${act}">${label}</button>`;
  let h = `<section class="q" data-q="${q.q}"><h4><span class="qn">${q.q}</span> ${inline(q.title)}</h4>`;
  if (q.after) h += `<div class="muted">${esc(q.after)}</div>`;
  if (q.text) h += `<p>${inline(q.text)}</p>`;
  if (q.options.length) {
    h += `<div class="opts">${q.options.map((o) => `<button class="opt ${on('pick', o.key) ? 'on' : ''}" data-act="pick" data-k="${o.key}" ${live ? '' : 'disabled'}>`
      + `<b>${o.key}</b> ${inline(o.label)}${o.key === q.recKey ? ' <span class="chip accent">recommended</span>' : ''}</button>`).join('')}</div>`;
  }
  if (q.rec) h += `<p class="rec">➡️ ${inline(q.rec)}</p>`;
  if (live) {
    h += `<div class="actions">${action('more', 'More detail')}`;
    if (kind === 'round') {
      if (q.options.length > 1) h += action('explore', 'Explore');
      h += action('own', 'Own answer') + action('discuss', 'Discuss') + action('defer', 'Defer');
    }
    h += '</div>';
    if (editing) {
      h += `<div class="edit"><textarea rows="2" aria-label="${editing === 'own' ? 'Your answer' : 'Your question'} to ${q.q}">${esc(staged.drafts[q.q])}</textarea>`
        + '<button class="btn sm" data-act="stage">Stage</button></div>';
    }
  }
  if (item) h += `<div class="staged">staged: <code>${esc(FORMS[item.kind](q.q, item.text))}</code></div>`;
  return `${h}</section>`;
}

/**
 * One ask as a card: a round, a confirm or a notice, open, sent or answered, with the relay's held reason. Only an
 * open ask of a session in herdr can be answered: staged items compose into the `<output>` that Send posts.
 */
export function renderAsk(ask, staged) {
  const parsed = parseAsk(ask.body);
  const state = ask.status !== 'open' ? 'answered' : ask.sent ? 'sent' : 'open';
  const live = state !== 'answered' && !!ask.pane;
  const el = document.createElement('article');
  el.className = `ask ${state}`;
  el.dataset.ask = `${ask.sid}/${ask.ask}`;
  let h = `<header class="ask-h"><span class="chip">${parsed.kind}</span><span class="muted">${esc(ask.task)} · ${esc(ask.flow)} · session ${esc(ask.sid)}</span>`
    + `<span class="chip ${state === 'open' ? 'warn' : 'ok'}">${state}</span>`
    + (ask.held && state === 'sent' ? `<span class="chip bad">${esc(HELD[ask.held] || `held: ${ask.held}`)}</span>` : '')
    + '</header>';
  if (!ask.pane) h += `<p class="note">Session ${esc(ask.sid)} runs outside herdr: answer it in its terminal.</p>`;
  h += parsed.kind === 'notice' ? notice(parsed.text) : parsed.questions.map((q) => question(q, parsed.kind, staged, live)).join('');
  if (live) {
    const text = compose(parsed, staged.items);
    h += `<footer class="ask-f">${staged.error ? `<span class="bad">${esc(staged.error)}</span>` : ''}`
      + `<output>${esc(text)}</output><button class="btn primary" data-act="send" ${text && !staged.sending ? '' : 'disabled'}>Send</button></footer>`;
  }
  el.innerHTML = h;
  return el;
}
