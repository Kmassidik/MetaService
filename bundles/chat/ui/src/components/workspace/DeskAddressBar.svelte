<script>
  let { url = $bindable(''), disabled = false, onOpen } = $props()

  function submit(event) {
    event.preventDefault()
    onOpen?.()
  }
</script>

<form class="desk-address" onsubmit={submit}>
  <label for="computer-url" class="sr-only">Web address</label>
  <input id="computer-url" type="url" bind:value={url} placeholder="https://example.com" required {disabled} />
  <button type="submit" {disabled}>Open</button>
</form>

<style>
  .desk-address { display: flex; gap: 6px; margin: 8px 12px 0; }
  .desk-address input {
    flex: 1;
    min-width: 0;
    height: 36px;
    padding: 0 14px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-pill);
    background: var(--page);
    color: var(--text);
    font: 400 var(--fs-preview)/1 var(--font);
  }
  .desk-address button {
    height: 36px;
    padding: 0 16px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-pill);
    background: var(--page);
    color: var(--text);
    font: 500 var(--fs-preview)/1 var(--font);
    cursor: pointer;
  }
  .desk-address button:hover:not(:disabled) { background: var(--row-hover); }
  @media (max-width: 820px) { .desk-address input { font-size: 16px; } }
</style>
