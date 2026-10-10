<script>
  // Screenshot fallback only: the live stream takes keys directly, a snapshot needs them sent one by one.
  const TEXT_MAX = 2000
  const REMOTE_KEYS = ['Enter', 'Backspace', 'Tab', 'Shift+Tab', 'Escape', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight']

  let { text = $bindable(''), busy = false, locked = false, onAction } = $props()

  function typeText(event) {
    event.preventDefault()
    onAction('type', { text })
  }
</script>

<form class="desk-keyboard" onsubmit={typeText}>
  <label for="computer-text">Type into the focused field</label>
  <div class="desk-keyboard-row">
    <textarea id="computer-text" class="form-input" bind:value={text} rows="1" placeholder="Click a field in the screenshot, then type here…" maxlength={TEXT_MAX} disabled={busy}></textarea>
    <button type="submit" class="primary-button" disabled={busy || !text}>Type</button>
  </div>
  <div class="desk-keys" role="group" aria-label="Remote browser keyboard">
    {#each REMOTE_KEYS as key (key)}
      <button type="button" disabled={busy || locked} onclick={() => onAction('key', { key })}>{key}</button>
    {/each}
  </div>
</form>

<style>
  .desk-keyboard { display: grid; gap: 8px; padding: 12px; border-top: 1px solid var(--hairline); background: var(--page); }
  .desk-keyboard label { color: var(--text-2); font: 400 var(--fs-time)/1.4 var(--font); }
  .desk-keyboard-row { display: flex; gap: 8px; }
  .desk-keyboard-row textarea { flex: 1; resize: vertical; min-height: 38px; max-height: 140px; }
  .desk-keyboard-row .primary-button { min-height: 38px; }
  .desk-keys { display: flex; flex-wrap: wrap; gap: 6px; }
  .desk-keys button {
    height: 30px;
    padding: 0 11px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-pill);
    background: var(--page);
    color: var(--text);
    font: 400 var(--fs-time)/1 var(--font);
    cursor: pointer;
  }
  .desk-keys button:hover:not(:disabled) { background: var(--row-hover); }
</style>
