<script>
  // tone: 'error' | 'info' | 'control' (you are driving the computer)
  let { tone = 'info', children } = $props()
</script>

<div class="desk-notice is-{tone}" role={tone === 'error' ? 'alert' : 'status'}>{@render children()}</div>

<style>
  .desk-notice {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin: 8px 12px 0;
    padding: 8px 12px;
    border-radius: var(--radius-control);
    background: var(--bubble);
    color: var(--text-2);
    font: 400 var(--fs-preview)/1.45 var(--font);
    overflow-wrap: anywhere;
  }
  .desk-notice.is-error { background: var(--danger-bg); color: var(--danger); }
  .desk-notice.is-control { background: var(--ok-bg); color: var(--ok-text); }
  .desk-notice :global(.text-button) { flex-shrink: 0; }
</style>
