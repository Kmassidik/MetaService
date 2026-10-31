<script lang="ts">
  // One tab per app, each with where the snippet goes and the snippet to copy. The picked tab lives only in this view; nothing is stored.
  import McpCodeBox from './McpCodeBox.svelte'
  import { appTabs, tabIndexForKey, type AppTabId } from '../../lib/mcpSnippets.ts'

  let { endpoint }: { endpoint: string } = $props()
  const tabs = $derived(appTabs(endpoint))
  let picked: AppTabId = $state('claude-code')
  const index = $derived(Math.max(0, tabs.findIndex((tab) => tab.id === picked)))
  const current = $derived(tabs[index]!)

  const tabId = (id: AppTabId) => `mcp-app-tab-${id}`
  const panelId = 'mcp-app-panel'

  function onKey(event: KeyboardEvent) {
    const next = tabIndexForKey(index, tabs.length, event.key)
    const target = next === null ? undefined : tabs[next]
    if (!target) return
    event.preventDefault()
    picked = target.id
    document.getElementById(tabId(target.id))?.focus()
  }
</script>

<div class="apps" data-testid="mcp-apps">
  <div class="tabs" role="tablist" aria-label="Connect an app">
    {#each tabs as { id, label } (id)}
      <button type="button" role="tab" id={tabId(id)} class:on={picked === id} aria-selected={picked === id} aria-controls={panelId} tabindex={picked === id ? 0 : -1} onclick={() => (picked = id)} onkeydown={onKey}>{label}</button>
    {/each}
  </div>
  <div class="panel" role="tabpanel" id={panelId} aria-labelledby={tabId(current.id)} data-testid="mcp-app-panel">
    <p class="muted" data-testid="mcp-app-where">{current.where}</p>
    <McpCodeBox text={current.snippet} describe="{current.label} snippet" />
    {#if current.extra}
      <p class="muted" data-testid="mcp-app-extra">{current.extra.intro}</p>
      <McpCodeBox text={current.extra.text} describe="{current.label} bridge line" />
    {/if}
    {#if current.footer}<p class="muted" data-testid="mcp-app-footer">{current.footer}</p>{/if}
    {#if current.caution}<p class="muted small" data-testid="mcp-app-caution">{current.caution}</p>{/if}
  </div>
</div>

<style>
  .apps { display: grid; gap: 0; }
  .tabs { display: flex; overflow-x: auto; border-bottom: 1px solid var(--line); }
  .tabs button { background: none; border: 0; border-bottom: 2px solid transparent; padding: 10px 14px; font-family: var(--mono); font-size: 12px; color: var(--m50); margin-bottom: -1px; white-space: nowrap; cursor: pointer; }
  .tabs button:hover { color: var(--text); }
  .tabs button.on { color: var(--text); border-bottom-color: var(--accent-mark); font-weight: 700; }
  .tabs button:focus-visible { outline: 3px solid var(--focus); outline-offset: -3px; }
  .panel { display: grid; gap: 10px; padding-top: 14px; }
  p { margin: 0; }
  .muted { color: var(--m60); font-size: 13px; line-height: 1.6; }
  .small { font-size: 12px; }
</style>
