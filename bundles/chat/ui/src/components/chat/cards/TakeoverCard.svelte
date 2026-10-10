<script>
  import Card from './Card.svelte'

  // The bot needs you to sign in or act on its computer.
  let { card, busy = false, takingOver = false, onResolve } = $props()
</script>

<Card title={card.title || 'Sign in on my computer'} reason={card.reason}>
  {#snippet actions()}
    <button type="button" class="primary-button" disabled={busy} onclick={() => onResolve(takingOver ? 'continue' : 'takeover')}>{takingOver ? 'Give back, continue' : 'Take over'}</button>
    <button type="button" class="card-quiet" disabled={busy} onclick={() => onResolve('dismiss')}>Not now</button>
  {/snippet}
</Card>
