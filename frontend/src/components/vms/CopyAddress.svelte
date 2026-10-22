<script lang="ts">
  // A small copy icon for an address or a command. Its label says "Copied" (or that it could not copy) for a moment.
  import IconButton from '../IconButton.svelte'
  import { copyText } from '../../lib/clipboard.ts'
  import { VM_ICONS } from './vmIcons.ts'

  const RESET_MS = 2000
  type Outcome = 'idle' | 'copied' | 'failed'
  const DEFAULT_LABEL = 'Copy address'
  const OUTCOME_LABELS: Record<Exclude<Outcome, 'idle'>, string> = { copied: 'Copied', failed: 'Could not copy' }

  /** `address` is the text copied; `label` names the idle button; `subject` is what the button is about (the VM), added to the screen-reader name. */
  let { address, label = DEFAULT_LABEL, subject }: { address: string; label?: string; subject?: string } = $props()
  let outcome = $state<Outcome>('idle')
  const shownLabel = $derived(outcome === 'idle' ? label : OUTCOME_LABELS[outcome])

  async function copy() {
    outcome = (await copyText(address)) ? 'copied' : 'failed'
    setTimeout(() => (outcome = 'idle'), RESET_MS)
  }
</script>

<IconButton label={shownLabel} {subject} icon={VM_ICONS.copy} text="Copy" onclick={copy} />
