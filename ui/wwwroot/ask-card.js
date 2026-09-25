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

/**
 * The one state of an ask: answered once its session closed it, gone once its session ended before it took the
 * answer, sent while an answer waits for the session, else open. Only an open ask takes an answer.
 */
export function stateOf(ask) {
  if (ask.status !== 'open') return 'answered';
  if (ask.held === 'gone' || ask.agent === 'gone') return 'gone';
  return ask.sent ? 'sent' : 'open';
}

/** The text the relay types for the staged items: one item per line in question order, or a notice's own answer, else `ok`. */
export function compose(view, items) {
  if (view.kind === 'notice') return items.notice?.text || 'ok';
  return view.questions
    .filter(({ q }) => items[q])
    .map(({ q }) => FORMS[items[q].kind](q, items[q].text.replace(/\s+/g, ' ').trim()))
    .join('\n');
}

function answerBox(q, staged, actions) {
  const item = staged.items[q];
  const editing = staged.editing[q];
  const action = (act, label) => {
    const on = (item?.kind === act && !item.text) || editing === act;
    return `<button class="btn sm ${on ? 'on' : ''}" data-act="${act}" aria-pressed="${on}">${label}</button>`;
  };
  let h = `<div class="actions">${actions.map(([act, label]) => action(act, label)).join('')}</div>`;
  if (editing) {
    h += `<div class="edit"><textarea rows="2" aria-label="${editing === 'own' ? 'Your answer' : 'Your question'} to ${q}">${esc(staged.drafts[q])}</textarea>`
      + '<button class="btn sm" data-act="stage">Add to answer</button></div>';
  }
  if (item) h += `<div class="staged">Your answer: <code>${esc(SHOWN[item.kind](item.text))}</code></div>`;
  return h;
}

function question(q, kind, staged, live) {
  const item = staged.items[q.q];
  let h = `<section class="q" data-q="${q.q}"><h4><span class="qn">${q.q}</span> ${q.title}</h4>`;
  if (q.after) h += `<div class="muted">${esc(q.after)}</div>`;
  h += `<div class="md">${q.html}</div>`;
  if (q.options.length) {
    h += `<div class="opts">${q.options.map((o) => {
      const on = item?.kind === 'pick' && item.text === o.key;
      return `<button class="opt ${on ? 'on' : ''}" data-act="pick" data-k="${o.key}" aria-pressed="${on}" ${live ? '' : 'disabled'}>`
        + `<b>${o.key}</b> ${o.html}${o.key === q.recKey ? ' <span class="chip accent">recommended</span>' : ''}`
        + `${on ? '<span class="tick" aria-hidden="true">✓</span>' : ''}</button>`;
    }).join('')}</div>`;
  }
  if (q.rec) h += `<p class="rec">${q.recKey ? `Why ${q.recKey}: ${q.rec.replace(/^<strong>[A-Z]<\/strong>:?\s*/, '')}` : q.rec}</p>`;
  if (live) {
    const actions = [['more', 'Explain more']];
    if (kind === 'round' && q.options.length > 1) actions.push(['explore', 'Compare options']);
    actions.push(['own', 'Write my answer']);
    if (kind === 'round') actions.push(['discuss', 'Ask a question'], ['defer', 'Decide later']);
    h += answerBox(q.q, staged, actions);
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
 * staged items show in words and compose into the `<output>` that Send posts.
 */
export function renderAsk(ask, given) {
  const { view } = ask;
  const state = stateOf(ask);
  const live = state === 'open' && !!ask.pane;
  const staged = live ? given : { items: {}, editing: {}, drafts: {} };
  const n = view.questions.length;
  const el = document.createElement('article');
  el.className = `ask ${state}`;
  el.dataset.ask = `${ask.sid}/${ask.ask}`;
  el.dataset.state = state;
  const held = ask.held && state !== 'gone' && state !== 'answered';
  let h = `<header class="ask-h"><b>${esc(ask.step)}</b>${n ? `<span class="muted">${n} question${n > 1 ? 's' : ''}</span>` : ''}`
    + `<span class="chip state ${TONE[state]}">${state === 'gone' ? HELD.gone(ask) : STATES[state]}</span>`
    + '</header>';
  if (held) h += `<p class="note held">${HELD[ask.held]?.(ask) ?? `held: ${esc(ask.held)}`}</p>`;
  if (!ask.pane) h += '<p class="note">This session runs outside herdr, so answer it in its terminal.</p>';
  if (view.preamble) h += `<div class="md">${view.preamble}</div>`;
  h += view.questions.map((q) => question(q, view.kind, staged, live)).join('');
  if (live && view.kind === 'notice') h += `<section class="q" data-q="notice">${answerBox('notice', staged, [['own', 'Write my answer']])}</section>`;
  if (live) {
    const text = compose(view, staged.items);
    const answered = view.questions.filter(({ q }) => staged.items[q]).length;
    h += `<footer class="ask-f">${staged.error ? `<span class="bad">${esc(staged.error)}</span>` : ''}`
      + `<div class="will">${text ? `<b>Will be sent:</b><ul class="preview">${preview(view, staged.items)}</ul>` : ''}`
      + `<output aria-label="Exact text">${esc(text)}</output></div>`
      + `<button class="btn primary" data-act="send" ${text && !staged.sending ? '' : 'disabled'}>Send answer${answered > 1 ? 's' : ''}</button></footer>`;
  }
  h += `<p class="sid muted">${esc(ask.task)} · ${esc(ask.flow)} · session ${esc(ask.sid)}</p>`;
  el.innerHTML = h;
  return el;
}
