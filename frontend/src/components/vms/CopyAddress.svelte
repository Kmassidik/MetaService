<script lang="ts">
  // A small copy icon for an address. Its label says "Copied" (or that it could not copy) for a moment.
  import IconButton from '../IconButton.svelte'
  import { copyText } from '../../lib/clipboard.ts'
  import { VM_ICONS } from './vmIcons.ts'

  const RESET_MS = 2000
  type Outcome = 'idle' | 'copied' | 'failed'
  const LABELS: Record<Outcome, string> = { idle: 'Copy address', copied: 'Copied', failed: 'Could not copy' }

  let { address }: { address: string } = $props()
  let outcome = $state<Outcome>('idle')

  async function copy() {
    outcome = (await copyText(address)) ? 'copied' : 'failed'
    setTimeout(() => (outcome = 'idle'), RESET_MS)
  }
</script>

<IconButton label={LABELS[outcome]} icon={VM_ICONS.copy} text="Copy" onclick={copy} />
