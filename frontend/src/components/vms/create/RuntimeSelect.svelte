<script lang="ts">
  // "Runtime environment": Container or VM in the rich dropdown, each row with what it is, and one plain line under it that follows the choice. The kind the machine cannot run is greyed out with its reason.
  import { runtimeCaption, runtimeRows } from '../../../lib/createSelects.ts'
  import type { RuntimeCard } from '../../../lib/createVm.ts'
  import RichDropdown from './RichDropdown.svelte'

  interface Props {
    id: string
    cards: RuntimeCard[]
    chosen: string
    /** The machine's operating system, for the line about Macs. */
    os: string | undefined
    onpick: (kind: string) => void
  }

  let { id, cards, chosen, os, onpick }: Props = $props()
  const captionId = $derived(`${id}-caption`)
</script>

<RichDropdown {id} label="Runtime environment" cards={runtimeRows(cards)} {chosen} describedBy={captionId} {onpick}>
  <p class="caption" id={captionId}>{runtimeCaption(chosen, os)}</p>
</RichDropdown>

<style>
  .caption { margin: 0; font-size: 12px; line-height: 1.5; color: var(--m50); }
</style>
