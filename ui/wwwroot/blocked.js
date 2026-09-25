import { esc } from './ask-card.js';
import { section } from './task-panels.js';

/**
 * The `## Question` of a blocked task and of each blocked block, each with Unblock (`data-act="unblock"`), which sends
 * `unblock <T-id>` to the CEO, disabled while no CEO session runs; then routed to a session of the task in herdr, or,
 * with none, the solve command that starts one. Null when nothing is blocked.
 */
export function renderBlockedQuestion(task, sessions, ceo) {
  const blocked = [task, ...task.blockDetails].filter((t) => t.task.status === 'blocked');
  if (!blocked.length) return null;
  const live = sessions.find((s) => s.pane);
  const el = document.createElement('section');
  el.dataset.panel = 'blocked';
  el.innerHTML = blocked.map((t) => `<h3>${esc(t.task.id)} is blocked and needs a decision</h3><div class="md"></div>`
    + `<p><button class="btn sm primary" data-act="unblock" data-id="${esc(t.task.id)}"${ceo ? '' : ' disabled'}>Unblock ${esc(t.task.id)}</button> `
    + `<span class="muted">${ceo ? 'The CEO sets it ready and its lead goes on.' : 'No CEO session runs, so nothing goes out.'}</span></p>`).join('')
    + (live
      ? `<p>Answer it in session <span class="id">${esc(live.sid)}</span>, herdr pane ${esc(live.pane)}.</p>`
      : `<p>No session of ${esc(task.task.id)} runs in herdr. Start one and answer there:</p><p><code>/claude-factory:factory solve ${esc(task.task.id)}</code></p>`);
  el.querySelectorAll('.md').forEach((d, i) => d.append(...section(blocked[i].html.progress, 'Question')));
  return el;
}
