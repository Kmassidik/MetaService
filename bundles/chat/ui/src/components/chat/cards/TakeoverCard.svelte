<script lang="ts">
  import type { Dict } from '../../../lib/check.ts'
  import type { RunCard } from '../../../lib/types.ts'
  import Card from './Card.svelte'

  // The bot needs you to sign in or act on its computer.
  interface Props {
    card: RunCard
    busy?: boolean
    takingOver?: boolean
    onResolve: (decision: string, extra?: Dict<unknown>) => unknown
  }

  let { card, busy = false, takingOver = false, onResolve }: Props = $props()
</script>

<Card title={card.title || 'Sign in on my computer'} reason={card.reason}>
  {#snippet actions()}
    <button type="button" class="primary-button" disabled={busy} onclick={() => onResolve(takingOver ? 'continue' : 'takeover')}>{takingOver ? 'Give back, continue' : 'Take over'}</button>
    <button type="button" class="card-quiet" disabled={busy} onclick={() => onResolve('dismiss')}>Not now</button>
  {/snippet}
</Card>
