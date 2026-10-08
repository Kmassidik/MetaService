<script>
  import { STATE_LABELS } from '../lib/format.js'

  let { state, label = null } = $props()
</script>

<span class="pill {state}"><span class="dot"></span>{label ?? STATE_LABELS[state] ?? 'Unknown'}</span>

<style>
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 2px 10px 2px 8px;
    border-radius: 999px;
    font-size: 13px;
    font-weight: 600;
    background: var(--off-bg);
    color: var(--off);
  }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: currentColor; }
  .online { background: var(--ok-bg); color: var(--ok); }
  .busy { background: var(--warn-bg); color: var(--warn); }
</style>
