<script>
  import { onMount } from 'svelte'
  import Icon from '../Icon.svelte'

  // Find in the loaded conversation; opened from the sidebar search.
  let { query = $bindable(''), matchIndex = $bindable(0), matchCount = 0, findMessage, onClose } = $props()
  let field = $state(null)
  const summary = $derived(matchCount ? `${Math.min(matchIndex + 1, matchCount)} of ${matchCount}` : 'No matches')

  onMount(() => field?.focus())

  function search(event) {
    query = event.currentTarget.value
    matchIndex = 0
    findMessage()
  }

  function next(event) {
    event.preventDefault()
    findMessage(1)
  }

  function closeOnEscape(event) {
    if (event.key === 'Escape') onClose()
  }
</script>

<form class="find" role="search" onsubmit={next}>
  <Icon name="search" size={17} />
  <input bind:this={field} type="search" aria-label="Find in conversation" placeholder="Find in conversation" value={query} oninput={search} onkeydown={closeOnEscape} />
  {#if query.trim()}<span class="count" role="status">{summary}</span>{/if}
  <button type="button" class="step" aria-label="Previous match" disabled={!matchCount} onclick={() => findMessage(-1)}><Icon name="up" size={16} /></button>
  <button type="submit" class="step" aria-label="Next match" disabled={!matchCount}><Icon name="down" size={16} /></button>
  <button type="button" class="step" aria-label="Close search" onclick={onClose}><Icon name="close" size={16} /></button>
</form>

<style>
  .find {
    display: flex; align-items: center; gap: 6px; width: min(560px, calc(100% - 32px)); margin: 0 auto 8px; padding: 4px 6px 4px 14px;
    border: 1px solid var(--hairline); border-radius: var(--radius-pill); background: var(--surface); box-shadow: var(--shadow-float); color: var(--text-2);
  }
  input { flex: 1; min-width: 0; height: 30px; border: 0; outline: none; background: transparent; color: var(--text); font: 400 15px/1.3 var(--font); }
  .count { font: 400 var(--fs-time)/1 var(--font); white-space: nowrap; }
  .step { display: grid; place-items: center; width: 30px; height: 30px; padding: 0; border: 0; border-radius: var(--radius-pill); background: transparent; color: var(--text-2); cursor: pointer; }
  .step:hover:not(:disabled) { background: var(--row-hover); color: var(--text); }
  .step:disabled { color: var(--text-3); cursor: default; }
  @media (max-width: 820px) { input { font-size: 16px; } }
</style>
