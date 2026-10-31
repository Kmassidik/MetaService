<script lang="ts">
  // Connect: the address of the AI endpoint, a tab for each app with the snippet that connects it (with a placeholder, never a real token), and the tools.
  import McpAppTabs from './McpAppTabs.svelte'
  import type { McpInfo } from '../../lib/mcp.ts'
  import { SCOPE_TEXT, TOOL_TEXT } from '../../lib/mcpText.ts'

  let { info }: { info: McpInfo } = $props()
  const tools = $derived(info.tools.length > 0 ? info.tools : Object.keys(TOOL_TEXT))
</script>

<div class="connect" data-testid="mcp-connect">
  <p class="line">Endpoint <code data-testid="mcp-endpoint">{info.endpoint}</code></p>
  <p class="muted">Make a token below, then pick your app. Replace the placeholder with your token.</p>
  <McpAppTabs endpoint={info.endpoint} />
  <h4>Tools the AI can call</h4>
  <div class="tablewrap">
    <table class="restable stack" data-testid="mcp-tools">
      <thead><tr><th>Tool</th><th>Needs</th><th>What it does</th></tr></thead>
      <tbody>
        {#each tools as tool (tool)}
          {@const known = TOOL_TEXT[tool]}
          <tr>
            <td class="c-name mono" data-label="Tool">{tool}</td>
            <td data-label="Needs">{known ? SCOPE_TEXT[known.scope].name : 'unknown'}</td>
            <td class="muted" data-label="Does">{known?.explain ?? 'A tool this panel has no words for yet.'}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>

<style>
  .connect { display: grid; gap: 10px; }
  p { margin: 0; }
  .muted { color: var(--m60); font-size: 13px; line-height: 1.6; }
  .line { font-size: 13px; overflow-wrap: anywhere; }
  code { font-family: var(--mono); font-size: 12.5px; background: var(--surface-2); padding: 2px 6px; }
  h4 { margin: 8px 0 0; font-family: var(--mono); font-size: 11px; letter-spacing: .1em; text-transform: uppercase; color: var(--m50); }
  .tablewrap { padding: 0; }
</style>
