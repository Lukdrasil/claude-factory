export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

const HELD = {
  blocked: (ask) => `Not delivered yet: the session shows a dialog. Answer it in herdr pane ${esc(ask.pane)}, then this goes through by itself.`,
  gone: (ask) => `Not delivered: the session has ended.${ask.task === 'none' ? '' : ` Run <code>/claude-factory:factory solve ${esc(ask.task)}</code> to continue.`}`,
  'prompt-failed': () => 'Not delivered yet: herdr refused the message. It stays queued.',
};

const STATES = { open: 'Needs your answer', sent: 'Sent, waiting for the session', answered: 'Answered' };
const TONE = { open: 'warn', sent: 'ok', answered: 'ok', gone: 'bad' };

const FORMS = {
  pick: (q, text) => `${q} ${text}`,
  own: (q, text) => `${q} ${text}`,
  discuss: (q, text) => `${q} ? ${text}`,
  more: (q) => `${q} more`,
  explore: (q) => `explore ${q}`,
  defer: (q) => `${q} defer`,
};

const SHOWN = {
  pick: (text) => text,
  own: (text) => text,
  discuss: (text) => `Question: ${text}`,
  more: () => 'Explain more',
  explore: () => 'Compare options',
  defer: () => 'Decide later',
};

/** The text of rendered HTML with its whitespace collapsed. */
function plain(html) {
  const t = document.createElement('template');
  t.innerHTML = html;
  return t.content.textContent.replace(/\s+/g, ' ').trim();
}

/**
 * The one state of an ask: answered once its session closed it, or once it ended after the relay typed the answer
 * without closing the ask; gone once its session ended before it took the answer, sent while an answer waits for the
 * session, else open. Only an open ask takes an answer.
 */
export function stateOf(ask) {
  if (ask.status !== 'open') return 'answered';
  if (ask.held === 'gone') return 'gone';
  if (ask.agent === 'gone') return ask.sent && !ask.held ? 'answered' : 'gone';
  return ask.sent ? 'sent' : 'open';
}

const PARSED = [[/^explore (Q\d+)$/, 'explore'], [/^(Q\d+) more$/, 'more'], [/^(Q\d+) defer$/, 'defer'], [/^(Q\d+) \? (.*)$/, 'discuss'], [/^(Q\d+) (.*)$/, 'own']];

/** The items of a sent answer, `compose` read back, an option's key a pick; null for a line of no question of the view. */
function itemsOf(view, text) {
  if (view.kind === 'notice') return { notice: { kind: 'own', text } };
  const items = {};
  for (const line of text.split('\n').filter((l) => l.trim())) {
    const [m, kind] = PARSED.map(([re, k]) => [line.match(re), k]).find(([hit]) => hit) ?? [];
    const q = m && view.questions.find((x) => x.q === m[1]);
    if (!q) return null;
    const t = m[2] ?? '';
    items[q.q] = kind === 'own' && q.options.some((o) => o.key === t) ? { kind: 'pick', text: t } : { kind, text: t };
  }
  return items;
}

/** The text the relay types for the staged items: one item per line in question order, or a notice's own answer, else `ok`. */
export function compose(view, items) {
  if (view.kind === 'notice') return items.notice?.text || 'ok';
  return view.questions
    .filter(({ q }) => items[q])
    .map(({ q }) => FORMS[items[q].kind](q, items[q].text.replace(/\s+/g, ' ').trim()))
    .join('\n');
}

/** The answer controls of one question: Write my answer, and the rarer `extra` actions behind More options, which
 * stay unfolded while one of them is staged or being written. */
function answerBox(q, staged, extra) {
  const item = staged.items[q];
  const editing = staged.editing[q];
  const action = (act, label) => {
    const on = (item?.kind === act && !item.text) || editing === act;
    return `<button class="btn sm ${on ? 'on' : ''}" data-act="${act}" aria-pressed="${on}">${label}</button>`;
  };
  const busy = extra.some(([act]) => item?.kind === act || editing === act);
  const open = busy || staged.menu?.[q];
  const menu = extra.length && !busy
    ? `<button class="btn sm more" data-act="menu" aria-expanded="${Boolean(open)}">${open ? 'Hide options' : 'More options'}</button>` : '';
  let h = `<div class="actions">${action('own', 'Write my answer')}${menu}${open ? extra.map(([act, label]) => action(act, label)).join('') : ''}</div>`;
  if (editing) {
    h += `<div class="edit"><textarea rows="2" aria-label="${editing === 'own' ? 'Your answer' : 'Your question'} to ${q}">${esc(staged.drafts[q])}</textarea>`
      + '<button class="btn sm" data-act="stage">Add to answer</button></div>';
  }
  if (item) h += `<div class="staged">Your answer: <code>${esc(SHOWN[item.kind](item.text))}</code></div>`;
  return h;
}

/** How far one question is: its staged answer in a few words, or that it has none yet. */
function qState(q, item) {
  if (!item) return '<span class="qstate">Not answered yet</span>';
  return `<span class="qstate on">Answered: ${esc(item.kind === 'pick' ? item.text : SHOWN[item.kind](item.text))}</span>`;
}

/** One question as a box of its own: its header with how far it is, its text (a long one folded until Show all), the
 * options with the recommendation's Why right under the recommended one, and its answer controls. */
function question(q, kind, staged, live) {
  const item = staged.items[q.q];
  const why = q.rec && `${q.recKey ? `Why ${q.recKey}: ${q.rec.replace(/^<strong>[A-Z]<\/strong>:?\s*/, '')}` : q.rec}`;
  const long = plain(q.html).length > 420;
  const full = !long || staged.full?.[q.q];
  let h = `<section class="q" data-q="${q.q}"><h4><span class="qn">${q.q}</span> <span class="qtitle">${q.title}</span>${live ? qState(q, item) : ''}</h4>`;
  if (q.after) h += `<div class="muted">${esc(q.after)}</div>`;
  h += `<div class="md${full ? '' : ' clamp'}">${q.html}</div>`;
  if (long && live) h += `<button class="btn sm link" data-act="full" aria-expanded="${Boolean(full)}">${full ? 'Show less' : 'Show all'}</button>`;
  if (q.options.length) {
    h += `<div class="opts">${q.options.map((o) => {
      const on = item?.kind === 'pick' && item.text === o.key;
      const rec = o.key === q.recKey;
      const name = `${o.key} ${plain(o.html)}${rec ? ', recommended' : ''}`;
      return `<button class="opt ${on ? 'on' : ''}${rec ? ' rec' : ''}" data-act="pick" data-k="${o.key}" aria-label="${esc(name)}" aria-pressed="${on}" ${live ? '' : 'disabled'}>`
        + `<b>${o.key}</b> ${o.html}${rec ? ' <span class="chip accent">recommended</span>' : ''}`
        + `${on ? '<span class="tick" aria-hidden="true">✓</span>' : ''}</button>${rec && why ? `<p class="rec why">${why}</p>` : ''}`;
    }).join('')}</div>`;
  }
  if (why && !(q.recKey && q.options.some((o) => o.key === q.recKey))) h += `<p class="rec">${why}</p>`;
  if (live) {
    const extra = [['more', 'Explain more']];
    if (kind === 'round' && q.options.length > 1) extra.push(['explore', 'Compare options']);
    if (kind === 'round') extra.push(['discuss', 'Ask a question'], ['defer', 'Decide later']);
    h += answerBox(q.q, staged, extra);
  }
  return `${h}</section>`;
}

/** The staged items in words, one per question: what Send will answer, before the exact text of `compose`. */
function preview(view, items) {
  if (view.kind === 'notice') return `<li>${esc(items.notice?.text || 'ok')}</li>`;
  return view.questions.filter(({ q }) => items[q]).map(({ q, options }) => {
    const { kind, text } = items[q];
    const o = kind === 'pick' && options.find((x) => x.key === text);
    return `<li><span class="qn">${q}</span> ${o ? `<b>${o.key}</b> ${o.html}` : esc(SHOWN[kind](text))}</li>`;
  }).join('');
}

/**
 * One ask as a card from its ask view: a round, a confirm or a notice in its one state of `stateOf`, with the relay's
 * held reason while it waits. Only an open ask of a session in herdr can be answered, every other card is read-only:
 * staged items show in words and compose into the `<output>` that Send posts. A sent or answered card shows the
 * `answer` it was sent in words, its picks pressed, or as text when it does not read back.
 */
export function renderAsk(ask, given) {
  const { view } = ask;
  const state = stateOf(ask);
  const live = state === 'open' && !!ask.pane;
  const answer = (state === 'sent' || state === 'answered') && ask.answer ? ask.answer : null;
  const sent = answer && itemsOf(view, answer);
  const staged = live ? given : { items: sent || {}, editing: {}, drafts: {} };
  const n = view.questions.length;
  const el = document.createElement('article');
  el.className = `ask ${state}`;
  el.dataset.ask = `${ask.sid}/${ask.ask}`;
  el.dataset.state = state;
  const held = ask.held && state !== 'gone' && state !== 'answered';
  const done = view.questions.filter(({ q }) => staged.items[q]).length;
  const recs = live && view.kind === 'round' ? view.questions.filter((q) => q.recKey && !staged.items[q.q]).length : 0;
  let h = `<header class="ask-h"><b>${esc(ask.step)}</b>${n ? `<span class="muted">${n} question${n > 1 ? 's' : ''}</span>` : ''}`
    + `<span class="chip state ${TONE[state]}">${state === 'gone' ? HELD.gone(ask) : STATES[state]}</span>`
    + `${live && n > 1 ? `<span class="prog">${done} of ${n} answered</span>` : ''}`
    + `${recs ? `<button class="btn sm primary accept" data-act="accept">Accept ${recs} recommended</button>` : ''}`
    + '</header>';
  if (held) h += `<p class="note held">${HELD[ask.held]?.(ask) ?? `held: ${esc(ask.held)}`}</p>`;
  if (!ask.pane) h += '<p class="note">This session runs outside herdr, so answer it in its terminal.</p>';
  if (view.preamble) h += `<div class="md">${view.preamble}</div>`;
  h += view.questions.map((q) => question(q, view.kind, staged, live)).join('');
  if (answer) h += `<div class="note" data-sent><b>Sent:</b><ul class="preview">${sent ? preview(view, sent) : `<li><code>${esc(answer)}</code></li>`}</ul></div>`;
  if (live && view.kind === 'notice') h += `<section class="q" data-q="notice">${answerBox('notice', staged, [])}</section>`;
  if (live) {
    const text = compose(view, staged.items);
    const answered = view.questions.filter(({ q }) => staged.items[q]).length;
    h += `<footer class="ask-f">${staged.error ? `<span class="bad">${esc(staged.error)}</span>` : ''}`
      + `<div class="will">${text ? `<b>Will be sent:</b><ul class="preview">${preview(view, staged.items)}</ul>`
        : view.kind === 'notice' ? '' : `<span class="muted">Answer ${view.questions.map(({ q }) => q).join(', ')} to send${recs ? `, or Accept ${recs} recommended` : ''}.</span>`}`
      + `<output aria-label="Exact text">${esc(text)}</output></div>`
      + `<button class="btn primary${staged.sending ? ' sending' : ''}" data-act="send" ${text && !staged.sending ? '' : 'disabled'}>Send answer${answered > 1 ? 's' : ''}</button></footer>`;
  }
  h += `<p class="sid muted">${esc(ask.task)} · ${esc(ask.flow)} · session ${esc(ask.sid)}</p>`;
  el.innerHTML = h;
  return el;
}
