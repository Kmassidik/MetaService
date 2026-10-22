<script lang="ts">
  // The IMAGE row: one card for each image the parent's catalog lists for the machine. An image that cannot be picked is greyed out with its reason as the caption.
  import CardGroup from './CardGroup.svelte'
  import OptionCard from './OptionCard.svelte'
  import type { ImageCard } from '../../../lib/images.ts'

  interface Props {
    group: string
    cards: ImageCard[]
    chosen: string
    /** True when the parent's list of images could not be read, so only Blank is offered. */
    unreadable: boolean
    onpick: (id: string) => void
  }

  const UNREADABLE_NOTE = 'The list of images could not be read, so only Blank is offered.'

  let { group, cards, chosen, unreadable, onpick }: Props = $props()
</script>

<CardGroup label="Image" columns={3}>
  {#each cards as card (card.id)}
    <OptionCard {group} value={card.id} label={card.title} caption={card.caption} badge={card.title.charAt(0).toUpperCase()} selected={chosen === card.id} disabled={card.disabled} {onpick} />
  {/each}
</CardGroup>
{#if unreadable}<p class="muted note">{UNREADABLE_NOTE}</p>{/if}

<style>
  .note { margin: 0; font-size: 13px; }
</style>
