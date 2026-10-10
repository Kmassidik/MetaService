<script>
  import Card from './Card.svelte'

  // The bot needs an app connected before it can continue.
  let { card, busy = false, onResolve } = $props()
  const service = $derived(card.service || 'app')
</script>

<Card title={card.title || `Connect ${service}`} reason={card.reason}>
  {#snippet actions()}
    <button type="button" class="primary-button" disabled={busy} onclick={() => onResolve('open_connect')}>Connect {service}</button>
    <button type="button" class="card-quiet" disabled={busy} onclick={() => onResolve('continue')}>I’m done, continue</button>
    <button type="button" class="card-quiet" disabled={busy} onclick={() => onResolve('dismiss')}>Not now</button>
  {/snippet}
</Card>
