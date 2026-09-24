import { esc } from './ask-card.js';
import { section } from './task-panels.js';

/**
 * The `## Question` of a blocked task and of each blocked block, routed to a session of the task in herdr, or,
 * with none, the solve command that starts one. Null when nothing is blocked.
 */
export function renderBlockedQuestion(task, sessions) {
  const blocked = [task, ...task.blockDetails].filter((t) => t.task.status === 'blocked');
  if (!blocked.length) return null;
  const live = sessions.find((s) => s.pane);
  const el = document.createElement('section');
  el.dataset.panel = 'blocked';
  el.innerHTML = blocked.map((t) => `<h3>${esc(t.task.id)} is blocked</h3><pre>${esc(section(t.progress, 'Question'))}</pre>`).join('')
    + (live
      ? `<p>Answer it in session <span class="id">${esc(live.sid)}</span>, herdr pane ${esc(live.pane)}.</p>`
      : `<p>No session of ${esc(task.task.id)} runs in herdr. Start one and answer there:</p><p><code>/claude-factory:factory solve ${esc(task.task.id)}</code></p>`);
  return el;
}
