<script>
  import Card from './Card.svelte'

  // The value goes straight to the bot; the transcript never shows it.
  const MAX_SECRET_LENGTH = 4096
  let { card, busy = false, secret = $bindable(''), onResolve } = $props()
  const inputId = $props.id()

  function submit(event) {
    event.preventDefault()
    if (busy || !secret.trim()) return
    onResolve('submit')
  }
</script>

<Card title={card.title || 'Secret needed'} reason={card.reason}>
  <form class="secret" onsubmit={submit}>
    <label class="sr-only" for={inputId}>Enter secret</label>
    <input id={inputId} class="card-row" type="password" autocomplete="off" maxlength={MAX_SECRET_LENGTH} placeholder="Paste or type the secret" bind:value={secret} />
    <div class="secret-actions">
      <button type="submit" class="primary-button" disabled={busy || !secret.trim()}>Send securely</button>
      <button type="button" class="card-quiet" disabled={busy} onclick={() => onResolve('dismiss')}>Not now</button>
    </div>
  </form>
</Card>

<style>
  .secret { display: grid; gap: 10px; }
  .secret-actions { display: flex; flex-wrap: wrap; gap: 8px; }
  .secret-actions .primary-button { min-height: 36px; padding: 7px 16px; }
  input:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 0; }
</style>
