<script>
  /** The brief "Saved" tick beside a control that saves on its own; announced politely. */
  import Icon from '../Icon.svelte'
  import { ICON_SIZE } from '../../lib/constants.js'

  let { shown = false } = $props()
</script>

<span class="saved-tick" role="status">
  {#if shown}<Icon name="check" size={ICON_SIZE.inline} />Saved{/if}
</span>

<style>
  .saved-tick { display: inline-flex; align-items: center; gap: 3px; min-height: 1em; color: var(--ok-text); font: 500 var(--fs-time)/1.3 var(--font); }
</style>
