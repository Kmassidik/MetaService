<script>
  /** Settings › General › Appearance: System / Light / Dark, applied at once and saved on this device. */
  import { THEME_OPTIONS, chooseTheme, readTheme } from '../../lib/theme.js'

  let choice = $state(readTheme())
  let saveFailed = $state(false)

  function pick(id) {
    choice = id
    saveFailed = !chooseTheme(id)
  }
</script>

<div class="appearance" role="radiogroup" aria-label="Appearance">
  {#each THEME_OPTIONS as option (option.id)}
    <button type="button" role="radio" aria-checked={choice === option.id} onclick={() => pick(option.id)}>{option.label}</button>
  {/each}
</div>
{#if saveFailed}<p class="save-note" role="status">This browser won’t save it, so it lasts for this visit only.</p>{/if}

<style>
  .appearance { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2px; margin: 8px; padding: 3px; border-radius: var(--radius-control); background: var(--tint-hover); }
  button { min-height: 34px; padding: 6px 10px; border-radius: var(--radius-item); background: transparent; color: var(--text-2); font: 500 var(--fs-preview)/1.2 var(--font); }
  button[aria-checked="true"] { background: var(--page); color: var(--text); box-shadow: var(--shadow-float); }
  .save-note { padding: 0 14px 10px; color: var(--text-2); font: 400 var(--fs-time)/1.4 var(--font); }
</style>
