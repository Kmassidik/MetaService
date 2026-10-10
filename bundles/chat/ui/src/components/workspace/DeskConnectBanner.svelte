<script>
  import Icon from '../Icon.svelte'
  import DeskNotice from './DeskNotice.svelte'

  let { appName = '', disabled = false, probeError = '', onFinish, onCancel } = $props()
</script>

<div class="desk-connect" role="status">
  <Icon name="shield" size={16} />
  <p>Sign in to <strong>{appName}</strong> below. Ruvio notices when you’re signed in. All your bots share this login. Never type passwords in chat.</p>
  <div class="desk-connect-actions">
    <button type="button" class="desk-connect-primary" {disabled} onclick={onFinish}>I’m signed in</button>
    <button type="button" class="desk-connect-quiet" {disabled} onclick={onCancel}>Cancel</button>
  </div>
</div>
{#if probeError}<DeskNotice tone="error">{probeError}</DeskNotice>{/if}

<style>
  .desk-connect {
    display: flex;
    align-items: center;
    gap: 10px;
    margin: 10px 12px 0;
    padding: 8px 8px 8px 14px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-card);
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow-float);
  }
  .desk-connect > :global(svg) { flex-shrink: 0; color: var(--ok-text); }
  .desk-connect p { flex: 1; min-width: 0; font: 400 var(--fs-preview)/1.4 var(--font); }
  .desk-connect strong { font-weight: 600; }
  .desk-connect-actions { display: flex; gap: 6px; flex-shrink: 0; }
  .desk-connect-actions button {
    height: 32px;
    padding: 0 14px;
    border-radius: var(--radius-pill);
    font: 500 var(--fs-preview)/1 var(--font);
    cursor: pointer;
  }
  .desk-connect-primary { border: 1px solid var(--ink); background: var(--ink); color: var(--on-ink); }
  .desk-connect-quiet { border: 1px solid transparent; background: none; color: var(--text-2); }
  .desk-connect-quiet:hover:not(:disabled) { background: var(--row-hover); color: var(--text); }
  .desk-connect-actions button:disabled { opacity: .5; cursor: default; }
  @media (max-width: 520px) {
    .desk-connect { flex-wrap: wrap; }
    .desk-connect-actions { width: 100%; justify-content: flex-end; }
  }
</style>
