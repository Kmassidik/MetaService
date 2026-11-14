<script lang="ts">
  // A small square badge for a machine card: one line icon, and its word on hover (the browser's own tip, so the card's clipping never hides it) and for screen readers.
  // Used for the things a card says about a machine that come and go: where it sits, that it needs setup, that its helper can be updated.
  import Icon from './Icon.svelte'

  type Tone = 'plain' | 'run' | 'warn'
  let { path, label, tone = 'plain', ...rest }: { path: string; label: string; tone?: Tone; [key: string]: unknown } = $props()
</script>

<span class="ib {tone}" role="img" aria-label={label} title={label} {...rest}><Icon {path} /></span>

<style>
  .ib { display: inline-flex; align-items: center; justify-content: center; flex: none; width: 24px; height: 22px; border: 1px solid var(--line); color: var(--m60); cursor: default; }
  .ib.run { color: var(--ok); border-color: var(--ok-note-line); background: var(--ok-note-bg); }
  .ib.warn { color: var(--warn); border-color: var(--warn-line); background: var(--warn-bg); }
  .ib:hover { border-color: var(--line-strong); }
</style>
