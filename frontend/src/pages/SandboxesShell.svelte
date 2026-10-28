<script lang="ts">
  import Sandboxes from './Sandboxes.svelte'
  import SandboxKeys from './SandboxKeys.svelte'
  import SandboxUsage from './SandboxUsage.svelte'
  import { SANDBOX_TABS, sandboxTabFromRoute } from '../lib/sandboxTabs.ts'

  let { route }: { route: string } = $props()
  const tab = $derived(sandboxTabFromRoute(route))
</script>

<div class="tabs" role="tablist" aria-label="Sandboxes">
  {#each SANDBOX_TABS as { id, label, href } (id)}
    <a role="tab" id={`sandbox-tab-${id}`} href={href} class:on={tab === id} aria-selected={tab === id} aria-controls={`sandbox-panel-${id}`} aria-current={tab === id ? 'page' : undefined}>{label}</a>
  {/each}
</div>

<div class="tabbody" role="tabpanel" id="sandbox-panel-live" aria-labelledby="sandbox-tab-live" hidden={tab !== 'live'}>
  <Sandboxes />
</div>
<div class="tabbody" role="tabpanel" id="sandbox-panel-keys" aria-labelledby="sandbox-tab-keys" hidden={tab !== 'keys'}>
  <SandboxKeys />
</div>
<div class="tabbody" role="tabpanel" id="sandbox-panel-usage" aria-labelledby="sandbox-tab-usage" hidden={tab !== 'usage'}>
  <SandboxUsage />
</div>

<style>
  .tabs { display: flex; overflow-x: auto; border-bottom: 1px solid var(--line); padding: 0 28px; }
  .tabs a { display: block; border-bottom: 2px solid transparent; padding: 12px 16px; font-family: var(--mono); font-size: 12px; color: var(--m50); margin-bottom: -1px; white-space: nowrap; text-decoration: none; }
  .tabs a.on { color: var(--text); border-bottom-color: var(--accent-mark); font-weight: 700; }
  .tabbody { padding: 24px 28px; }
  @media (max-width: 820px) { .tabs, .tabbody { padding-left: 16px; padding-right: 16px; } }
</style>
