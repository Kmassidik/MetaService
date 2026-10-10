<script>
  // Reply threads: a quiet "N replies" link that expands the thread under its parent.
  const MAX_REPLY_LENGTH = 4000
  const OWNER_ROLE = 'user'
  let { replies = [], open = false, draft = '', onToggle, onDraft, onSend } = $props()
  const countLabel = $derived(replies.length === 1 ? '1 reply' : `${replies.length} replies`)
</script>

{#if replies.length && !open}
  <button type="button" class="thread-link" onclick={onToggle}>{countLabel}</button>
{/if}
{#if open}
  <div class="thread">
    {#each replies as reply (reply.id)}<p class="reply" class:mine={reply.role === OWNER_ROLE}>{reply.text}</p>{/each}
    <div class="compose">
      <textarea rows="2" maxlength={MAX_REPLY_LENGTH} placeholder="Reply in thread…" aria-label="Reply in thread" value={draft} oninput={event => onDraft(event.currentTarget.value)}></textarea>
      <div class="compose-actions">
        <button type="button" class="thread-link" onclick={onToggle}>Close</button>
        <button type="button" class="primary-button" disabled={!draft.trim()} onclick={onSend}>Reply</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .thread-link { align-self: flex-start; padding: 2px 0; border: 0; background: none; color: var(--text-2); font: 500 13px/1.4 var(--font); cursor: pointer; }
  .thread-link:hover { color: var(--text); text-decoration: underline; text-underline-offset: 3px; }
  .thread { display: grid; gap: 4px; width: min(560px, 100%); margin-top: 4px; padding-left: 12px; border-left: 2px solid var(--hairline); }
  /* Same bubbles as the chat: the bot's are gray on the left, yours black on the right. */
  .reply { justify-self: start; max-width: 100%; margin: 0; padding: 8px 12px; border-radius: var(--radius-bubble); background: var(--bubble); color: var(--text); font: 400 14.5px/1.4 var(--font); white-space: pre-wrap; overflow-wrap: anywhere; }
  .reply.mine { justify-self: end; background: var(--ink); color: var(--on-ink); }
  .compose { display: grid; gap: 6px; }
  textarea { width: 100%; min-height: 56px; padding: 8px 12px; border: 1px solid var(--hairline); border-radius: 12px; font: 400 14.5px/1.4 var(--font); resize: vertical; }
  .compose-actions { display: flex; justify-content: flex-end; align-items: center; gap: 10px; }
  .compose-actions .thread-link { align-self: center; }
  .compose-actions .primary-button { min-height: 32px; padding: 5px 14px; }
</style>
