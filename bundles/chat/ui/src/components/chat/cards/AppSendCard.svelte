<script>
  import Card from './Card.svelte'
  import { approvalEditable, approvalLabel, approvalTitle, approvalWhere, MESSAGE_MAX_CHARS, messageToSend } from '../../../lib/appCards.js'

  // A bot wants to send one exact message, email, post or calendar change from the owner's own app:
  // Send, Edit (not for a calendar change) or Cancel. Nothing happens until the owner taps Send (the tool waits for this card).
  const EDIT_ROWS = 4
  let { card, busy = false, onResolve } = $props()
  let edited = $state(null)
  const editing = $derived(edited !== null)
  const outgoing = $derived(messageToSend(card.text, edited))
  const editorId = $props.id()

  function send() {
    if (busy || !outgoing.valid) return
    onResolve('send', editing ? { text: outgoing.text } : {})
  }
</script>

<Card label={approvalLabel(card)} title={approvalTitle(card)}>
  {#if editing}
    <label class="sr-only" for={editorId}>Message</label>
    <textarea id={editorId} class="card-row message-edit" rows={EDIT_ROWS} maxlength={MESSAGE_MAX_CHARS} bind:value={edited}></textarea>
  {:else}
    <p class="message">{card.text}</p>
  {/if}
  <p class="where">{approvalWhere(card)}</p>
  {#snippet actions()}
    <button type="button" class="primary-button" disabled={busy || !outgoing.valid} onclick={send}>Send</button>
    {#if !editing && approvalEditable(card)}
      <button type="button" class="card-quiet" disabled={busy} onclick={() => (edited = card.text)}>Edit</button>
    {/if}
    <button type="button" class="card-quiet" disabled={busy} onclick={() => onResolve('dismiss')}>Cancel</button>
  {/snippet}
</Card>

<style>
  .message {
    margin: 0; padding: 10px 12px; border-radius: 12px; background: var(--page);
    font: 400 var(--fs-message)/var(--lh-message) var(--font); white-space: pre-wrap; overflow-wrap: anywhere;
  }
  .message-edit { resize: vertical; font: 400 var(--fs-message)/var(--lh-message) var(--font); }
  .message-edit:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 0; }
  .where { margin: -4px 0 0; color: var(--text-2); font: 400 13px/1.45 var(--font); }
</style>
