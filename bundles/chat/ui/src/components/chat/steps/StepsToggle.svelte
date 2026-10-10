<script>
  import Icon from '../../Icon.svelte'

  // The quiet "Show steps" link; the list it opens is rendered by the caller.
  const CHEVRON_SIZE = 14

  let { open = $bindable(false), controls = '' } = $props()
</script>

<button type="button" class="steps-toggle" aria-expanded={open} aria-controls={controls} onclick={() => open = !open}>
  {open ? 'Hide steps' : 'Show steps'}<Icon name={open ? 'up' : 'down'} size={CHEVRON_SIZE} />
</button>

<style>
  .steps-toggle {
    display: inline-flex; align-items: center; gap: 3px; padding: 2px 6px;
    border: 0; border-radius: var(--radius-item); background: transparent;
    color: var(--text-2); font: 500 var(--fs-preview)/1.4 var(--font); cursor: pointer;
  }
  .steps-toggle:hover { background: var(--tint-hover); color: var(--text); }
  .steps-toggle:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 1px; }
</style>
