<script lang="ts">
  // What is installed on the machine: the helper, the engine that makes VMs, and the tunnel the parent keeps to it. A value nobody reported says so.
  import Section from './Section.svelte'
  import HelperRow from './HelperRow.svelte'
  import { NOT_REPORTED, type SoftwareRow } from '../../lib/environment.ts'
  import type { HelperView, OutcomeView } from '../../lib/helperUpdate.ts'

  let { rows, newest = null, title = 'Software', helper = null, updating = false, outcome = null, onUpdate = () => {} }: {
    rows: SoftwareRow[]
    newest?: string | null
    title?: string
    /** The Helper row and its button; left out where a machine has no helper to update. */
    helper?: HelperView | null
    updating?: boolean
    outcome?: OutcomeView | null
    onUpdate?: () => void
  } = $props()
</script>

<Section {title}>
  <dl class="kv">
    {#each rows as row (row.label)}
      <div>
        <dt>{row.label}</dt>
        <dd class:missing={row.value === NOT_REPORTED}>
          {row.value}
          {#if row.old}<span class="tag warn" title="Behind the newest helper version seen ({newest})">old</span>{/if}
        </dd>
      </div>
    {/each}
    {#if helper}<HelperRow {helper} {updating} {outcome} {onUpdate} />{/if}
  </dl>
</Section>

<style>
  .kv { display: grid; gap: 0; margin: 0; }
  .kv > div { display: grid; grid-template-columns: 160px 1fr; align-items: center; gap: 16px; border-bottom: 1px solid var(--surface-2); padding: 10px 0; }
  .kv dt { font: 11px var(--mono); text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  .kv dd { margin: 0; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; overflow-wrap: anywhere; font-size: 13px; }
  .kv dd.missing { color: var(--m50); }
  @media (max-width: 820px) { .kv > div { grid-template-columns: 1fr; gap: 4px; } }
</style>
