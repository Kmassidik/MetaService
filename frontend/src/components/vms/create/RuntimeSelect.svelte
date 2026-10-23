<script lang="ts">
  // "Runtime environment": Container or VM in a select, with one plain line under it that follows the choice. The kind the machine cannot run is disabled with its reason.
  import { runtimeCaption, runtimeOptions } from '../../../lib/createSelects.ts'
  import type { RuntimeCard } from '../../../lib/createVm.ts'
  import FieldBlock from './FieldBlock.svelte'
  import SelectBox from './SelectBox.svelte'

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

<FieldBlock label="Runtime environment" forId={id}>
  <SelectBox {id} value={chosen} options={runtimeOptions(cards)} describedBy={captionId} {onpick} />
  <p class="caption" id={captionId}>{runtimeCaption(chosen, os)}</p>
</FieldBlock>

<style>
  .caption { margin: 0; font-size: 12px; line-height: 1.5; color: var(--m50); }
</style>
