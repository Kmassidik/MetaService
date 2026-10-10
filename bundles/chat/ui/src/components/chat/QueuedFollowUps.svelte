<script>
  import { FOLLOW_UP_STATE } from '../../lib/sendMode.js'

  // What the owner typed while the bot worked: their bubble at once, with a small hint until the
  // bot's next turn takes it (then the chat shows it as a normal message).
  let { items = [], botName = '' } = $props()

  function hint(item) {
    if (item.state === FOLLOW_UP_STATE.sending) return 'Sending…'
    if (item.state === FOLLOW_UP_STATE.dropped) return 'Not sent — the task was stopped'
    return `Queued — ${botName} reads it when this task finishes`
  }
</script>

{#each items as item (item.id)}
  <div class="follow-up" class:dropped={item.state === FOLLOW_UP_STATE.dropped} aria-label="Message queued for the running task">
    <div class="bubble">{item.text}</div>
    <p class="hint" role="status">{hint(item)}</p>
  </div>
{/each}

<style>
  .follow-up { display: flex; flex-direction: column; align-items: flex-end; margin-top: 12px; }
  .bubble {
    max-width: min(560px, 100%); padding: 12px 16px; border-radius: var(--radius-bubble);
    background: var(--ink); color: var(--on-ink); opacity: .78;
    font: 400 var(--fs-message)/var(--lh-message) var(--font); white-space: pre-wrap; overflow-wrap: anywhere;
  }
  .hint { margin: 4px 4px 0; color: var(--text-2); font: 400 var(--fs-time)/1.4 var(--font); text-align: right; }
  .dropped .bubble { opacity: .5; }
  .dropped .hint { color: var(--danger); }
</style>
