<script lang="ts">
  // "Size": Small, Medium, Large and Custom in a select, across the window. A preset the machine cannot hold is disabled with the reason in brackets.
  // A preset fills Cores, Memory and Disk below (on one socket); Custom keeps what is there. Typing in those boxes moves this select by itself.
  import { sizeOptions } from '../../../lib/createSelects.ts'
  import { SIZE_PRESETS, type SizeCard, type SizeKey } from '../../../lib/vmSize.ts'
  import type { WorkloadForm } from '../../../lib/types.ts'
  import FieldBlock from './FieldBlock.svelte'
  import SelectBox from './SelectBox.svelte'

  interface Props {
    id: string
    cards: SizeCard[]
    chosen: SizeKey
    /** The form whose CPU, RAM and disk the presets fill in. */
    form: WorkloadForm
    onpick: (key: SizeKey) => void
  }

  let { id, cards, chosen, form = $bindable(), onpick }: Props = $props()

  /** A preset puts its numbers in the form (so Custom, picked next, starts from them); Custom keeps what is there. */
  function pick(value: string) {
    const preset = SIZE_PRESETS.find((entry) => entry.key === value)
    if (preset) Object.assign(form, { cpu: preset.cpu, ramGb: preset.ramGb, diskGb: preset.diskGb, cpuSockets: undefined })
    onpick(preset ? preset.key : 'custom')
  }
</script>

<FieldBlock label="Size" forId={id} wide>
  <SelectBox {id} value={chosen} options={sizeOptions(cards)} strong onpick={pick} />
</FieldBlock>
