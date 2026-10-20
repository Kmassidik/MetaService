<script lang="ts">
  // What is installed on the machine: the helper, the engine that makes VMs, and the tunnel the parent keeps to it. A value nobody reported says so.
  import Section from './Section.svelte'
  import { NOT_REPORTED, type SoftwareRow } from '../../lib/environment.ts'

  let { rows, newest }: { rows: SoftwareRow[]; newest: string | null } = $props()
</script>

<Section title="Software">
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
  </dl>
</Section>

<style>
  .kv { display: grid; gap: 0; margin: 0; }
  .kv > div { display: grid; grid-template-columns: 160px 1fr; align-items: center; gap: 16px; border-bottom: 1px solid var(--gray2); padding: 10px 0; }
  .kv dt { font: 11px var(--mono); text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  .kv dd { margin: 0; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; overflow-wrap: anywhere; font-size: 13px; }
  .kv dd.missing { color: var(--m50); }
  @media (max-width: 820px) { .kv > div { grid-template-columns: 1fr; gap: 4px; } }
</style>
