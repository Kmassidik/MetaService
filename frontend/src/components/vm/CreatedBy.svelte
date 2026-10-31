<script lang="ts">
  // Who made a VM, in one short piece of text: "Ayu (MCP) · 7f3a9c21", "panel (kurnia) · 5b02d1ee" or "unknown origin". Names are text only.
  import { readCreatedBy, UNKNOWN_ORIGIN, createdByText } from '../../lib/vmOrigin.ts'

  let { workload }: { workload: { created_by?: unknown } } = $props()
  const by = $derived(readCreatedBy(workload.created_by))
</script>

<span class="by mono" class:unknown={by === null} data-testid="created-by" title={by ? 'Made by ' + by.label + '. The number is the fingerprint of the record the parent kept.' : UNKNOWN_ORIGIN}>{createdByText(by)}</span>

<style>
  .by { font-size: 11.5px; color: var(--m70); overflow-wrap: anywhere; }
  .unknown { color: var(--m50); }
</style>
