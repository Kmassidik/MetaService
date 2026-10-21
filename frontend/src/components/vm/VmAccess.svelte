<script lang="ts">
  // The Access tab. MAAS teaches SSH through a Cloudflare name and a web terminal; MetaService has no Cloudflare name, so only what it knows is shown: the VM's address and its chat. The web terminal is the button in the page header.
  import type { Workload } from '../../lib/types.ts'

  interface Props {
    workload: Workload
    onCopy: (text: string) => void
    onOpenChat: () => void
  }

  let { workload, onCopy, onOpenChat }: Props = $props()
</script>

<div class="access">
  <p class="lbl">Connect</p>
  {#if workload.address}
    <p class="hint">The address the machine reports for this VM.</p>
    <div class="copybox"><code>{workload.address}</code><button class="btn line sm" type="button" onclick={() => onCopy(workload.address ?? '')}>Copy</button></div>
  {:else}
    <p class="hint">No address yet.</p>
  {/if}
  {#if workload.bundle_version}
    <p class="lbl">Ruvio</p>
    <p class="hint">The chat runs inside this VM.</p>
    <button class="btn sm" type="button" onclick={onOpenChat}>Open chat</button>
  {/if}
</div>

<style>
  .lbl { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.14em; color: var(--m50); margin: 22px 0 8px; }
  .lbl:first-child { margin-top: 0; }
  .hint { font-size: 13px; color: var(--m60); line-height: 1.6; margin: 0 0 8px; }
  code { font-family: var(--mono); background: var(--surface-2); padding: 1px 4px; font-size: 12px; }
  .copybox { display: flex; align-items: stretch; border: 1px solid var(--line); margin-bottom: 6px; }
  .copybox code { flex: 1; padding: 11px 13px; background: none; overflow-x: auto; white-space: nowrap; }
  .copybox .btn { border: 0; border-left: 1px solid var(--line); }
</style>
