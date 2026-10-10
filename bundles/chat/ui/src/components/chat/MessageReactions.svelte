<script>
  import Icon from '../Icon.svelte'
  import { REACTIONS, reactionCount } from './reactions.js'

  // Chips under the bubble: chosen ones always show; all three show while picking.
  let { reactions = [], picking = false, onToggle } = $props()
  const shown = $derived(REACTIONS.filter(item => picking || reactionCount(reactions, item.emoji)))
</script>

{#if shown.length}
  <div class="reactions" role="group" aria-label="Reactions">
    {#each shown as item (item.emoji)}
      {@const count = reactionCount(reactions, item.emoji)}
      <button type="button" class="chip" class:chosen={count > 0} aria-pressed={count > 0} aria-label={item.label} title={item.label} onclick={() => onToggle(item.emoji)}>
        <Icon name={item.icon} size={14} />{#if count}<span>{count}</span>{/if}
      </button>
    {/each}
  </div>
{/if}

<style>
  .reactions { display: flex; gap: 4px; margin-top: 4px; }
  .chip {
    display: inline-flex; align-items: center; gap: 4px; height: 26px; padding: 0 9px;
    border: 1px solid var(--hairline); border-radius: var(--radius-pill);
    background: var(--page); color: var(--text-2); font: 500 var(--fs-time)/1 var(--font); cursor: pointer;
  }
  .chip:hover { color: var(--text); border-color: var(--text-3); }
  .chip.chosen { background: var(--bubble); border-color: var(--bubble); color: var(--text); }
  .chip:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 1px; }
</style>
