<script lang="ts">
  // One row for every machine the panel knows. A machine that has not reported is "Not watched" with the plain line "no security data yet": its counts are dashes,
  // never zeros. A watched machine shows its six baseline checks as chips (ok, needs a look, unknown) and its failed logins and blocked addresses in the range.
  import StatePill from '../StatePill.svelte'
  import { relativeTime } from '../../lib/format.ts'
  import { machineHref } from '../../lib/routes.ts'
  import { numberText } from '../../lib/securityRules.ts'
  import { NOT_WATCHED_LABEL, NOT_WATCHED_LINE, type MachineSecurityRow } from '../../lib/securityView.ts'
  import type { CheckState } from '../../lib/securityRules.ts'

  let { rows, now }: { rows: MachineSecurityRow[]; now: number } = $props()
  const TONES: Record<CheckState, string> = { ok: 'run', warning: 'warn', unknown: '' }
</script>

<div class="scroll">
  <table class="restable stack" data-testid="security-machines">
    <thead><tr><th>Machine</th><th>Status</th><th>Last reported</th><th>Baseline</th><th class="num">Failed logins</th><th class="num">Blocked</th></tr></thead>
    <tbody>
      {#each rows as row (row.id)}
        <tr data-machine={row.id} data-watched={row.watched}>
          <td data-label="Machine" class="c-name"><a href={machineHref(row.id)}>{row.name}</a></td>
          <td data-label="Status"><StatePill state={row.state} /></td>
          <td data-label="Reported" class="muted" title={row.lastReported ?? ''}>{row.watched ? relativeTime(row.lastReported, now) : 'never'}</td>
          <td data-label="Baseline" class="chips">
            {#if row.watched}
              {#each row.checks as check (check.id)}
                <span class="tag {TONES[check.state]}" data-check={check.id} data-state={check.state} title={check.line}>{check.label}: {check.short}</span>
              {/each}
            {:else}
              <span class="tag warn" data-testid="not-watched">{NOT_WATCHED_LABEL}</span><span class="muted">{NOT_WATCHED_LINE}</span>
            {/if}
          </td>
          <td data-label="Failed" class="nums num">{numberText(row.failed)}</td>
          <td data-label="Blocked" class="nums num">{numberText(row.blocked)}</td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<style>
  .scroll { overflow-x: auto; }
  .chips { display: flex; flex-wrap: wrap; gap: 4px 6px; align-items: center; }
  .chips .tag { white-space: normal; }
  .num { text-align: right; }
  a { color: inherit; }
  :global(.restable.stack td) { padding: 10px 14px; }
  @media (max-width: 820px) {
    .num { text-align: left; }
    :global(.restable.stack tbody td) { padding: 3px 0; }
    .chips { display: flex; flex: 1; }
  }
</style>
