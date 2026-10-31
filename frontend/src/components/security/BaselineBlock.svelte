<script lang="ts">
  // The baseline: one row per check, each with a clear state (ok, needs a look, unknown), one plain line, and when it needs a look, what to do. Read only.
  import MetricCard from '../monitor/MetricCard.svelte'
  import { baselineRows, type CheckState } from '../../lib/securityRules.ts'
  import type { MachineSecurity } from '../../lib/types.ts'

  const WORDS: Record<CheckState, string> = { ok: 'OK', warning: 'Fix', unknown: 'Unknown' }
  const TAG_CLASS: Record<CheckState, string> = { ok: 'run', warning: 'warn', unknown: '' }

  let { report }: { report: MachineSecurity } = $props()
  const rows = $derived(baselineRows(report))
</script>

<MetricCard label="Baseline" hint="The basic settings that keep strangers out. A row marked Look needs someone to change a setting on the machine. Unknown means the helper did not say.">
  <ul>
    {#each rows as row (row.id)}
      <li data-check={row.id} data-state={row.state}>
        <span class="tag {TAG_CLASS[row.state]}">{WORDS[row.state]}</span>
        <div class="text">
          <b>{row.label}</b>
          <span class="line">{row.line}</span>
          {#if row.todo}<span class="todo">{row.todo}</span>{/if}
        </div>
      </li>
    {/each}
  </ul>
</MetricCard>

<style>
  ul { list-style: none; margin: 0; padding: 0; display: grid; }
  li { display: grid; grid-template-columns: 76px minmax(0, 1fr); gap: 12px; align-items: start; padding: 10px 0; border-top: 1px solid var(--line); }
  li:first-child { border-top: 0; }
  li[data-state='warning'] { background: var(--warn-note-bg); margin: 0 -16px; padding: 10px 16px; }
  .tag { justify-self: start; text-align: center; min-width: 62px; }
  .text { display: grid; gap: 2px; min-width: 0; font-size: 13px; overflow-wrap: anywhere; }
  .line { color: var(--m60); }
  .todo { color: var(--warn-note-title); font-weight: 700; }
</style>
