<script lang="ts">
  // A small Copy button for a command or the host key. It says "Copied" for a moment, or that it could not copy.
  const RESET_MS = 2000

  let { text, label = 'Copy', describe }: { text: string; label?: string; describe: string } = $props()
  type Outcome = 'idle' | 'copied' | 'failed'
  const SAID: Record<Exclude<Outcome, 'idle'>, string> = { copied: 'Copied', failed: 'Could not copy' }

  let outcome = $state<Outcome>('idle')
  const shown = $derived(outcome === 'idle' ? label : SAID[outcome])

  async function copy() {
    try {
      await navigator.clipboard.writeText(text)
      outcome = 'copied'
    } catch {
      outcome = 'failed'
    }
    setTimeout(() => (outcome = 'idle'), RESET_MS)
  }
</script>

<button class="copy" type="button" aria-label={`Copy ${describe}`} onclick={copy}>{shown}</button>

<style>
  .copy { flex: none; padding: 2px 8px; background: transparent; color: var(--black); border: 1px solid var(--m50); font-family: var(--sans); font-size: 12px; cursor: pointer; }
  .copy:hover { border-color: var(--black); }
  .copy:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }
</style>
