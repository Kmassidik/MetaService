<script lang="ts">
  // The RUNTIME row: Container and VM. The one the machine cannot run is greyed out with its reason.
  import CardGroup from './CardGroup.svelte'
  import OptionCard from './OptionCard.svelte'
  import type { RuntimeCard } from '../../../lib/createVm.ts'

  interface Props {
    group: string
    cards: RuntimeCard[]
    chosen: string
    onpick: (kind: string) => void
  }

  let { group, cards, chosen, onpick }: Props = $props()
</script>

<CardGroup label="Runtime" columns={2}>
  {#each cards as card (card.kind)}
    <OptionCard {group} value={card.kind} label={card.label} caption={card.caption} reason={card.reason} selected={chosen === card.kind} disabled={card.disabled} {onpick} />
  {/each}
</CardGroup>
