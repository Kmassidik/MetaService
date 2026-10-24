<script lang="ts">
  // What each team's finished sandboxes used: how many ran, how long, and the vCPU and memory seconds they held. No charts:
  // a plain table, next to the token ledger.
  import { onMount } from 'svelte'
  import { ApiError, sandboxUsage } from '../lib/api.ts'
  import { countText, durationText, USAGE_WINDOWS, usageTotals, windowLabel } from '../lib/sandboxPanel.ts'
  import type { SandboxUsageReply } from '../lib/types.ts'

  let days = $state(USAGE_WINDOWS[0] ?? 7)
  let reply = $state<SandboxUsageReply | null>(null)
  let loading = $state(true)
  let banner = $state('')

  async function load() {
    loading = true
    try {
      reply = await sandboxUsage(days)
      banner = ''
    } catch (error) {
      banner = error instanceof ApiError ? error.message : 'The usage could not be read.'
    } finally {
      loading = false
    }
  }

  function pick(next: number) {
    if (next === days) return
    days = next
    void load()
  }

  const rows = $derived(reply?.teams ?? [])
  const totals = $derived(usageTotals(rows))

  onMount(load)
</script>

<div class="phead"><h1>Sandbox usage</h1><span class="crumb">Sandboxes › {windowLabel(days)}</span></div>
<p class="op-note">Every finished sandbox run adds its running time here, per team: whole seconds, and those seconds times the vCPU and memory it held. A paused sandbox uses no CPU or memory, so it counts nothing until it runs again.</p>

{#if banner}<p class="banner" role="status">{banner}</p>{/if}

<div class="op-filters" role="group" aria-label="Window">
  {#each USAGE_WINDOWS as choice (choice)}
    <button class="btn line sm" type="button" aria-pressed={days === choice} class:on={days === choice} onclick={() => pick(choice)}>{windowLabel(choice)}</button>
  {/each}
</div>

<section class="op-stats" aria-label="Totals">
  <div class="op-stat"><span>Sandboxes run</span><b class="nums">{countText(totals.sandboxes)}</b></div>
  <div class="op-stat"><span>Running time</span><b class="nums">{durationText(totals.seconds)}</b></div>
  <div class="op-stat"><span>vCPU time</span><b class="nums">{durationText(totals.vcpu_seconds)}</b></div>
  <div class="op-stat"><span>Memory time</span><b class="nums">{countText(totals.ram_mb_seconds)} MB·s</b></div>
</section>

<div class="tablewrap" role="region" aria-label="Usage per team, scroll to view columns">
  <table class="restable stack">
    <thead><tr><th>Team</th><th>Sandboxes run</th><th>Running time</th><th>vCPU time</th><th>Memory (MB·s)</th></tr></thead>
    <tbody>
      {#each rows as row (row.team)}
        <tr>
          <td data-label="Team"><b>{row.team_name}</b></td>
          <td data-label="Sandboxes run" class="nums">{countText(row.sandboxes)}</td>
          <td data-label="Running time" class="nums">{durationText(row.seconds)}</td>
          <td data-label="vCPU time" class="nums">{durationText(row.vcpu_seconds)}</td>
          <td data-label="Memory (MB·s)" class="nums">{countText(row.ram_mb_seconds)}</td>
        </tr>
      {:else}
        <tr><td colspan="5">{loading ? 'Reading the usage…' : `No sandbox has finished in the ${windowLabel(days).toLowerCase()}.`}</td></tr>
      {/each}
    </tbody>
  </table>
</div>

<style>
  .btn[aria-pressed='true'] { border-color: var(--accent-mark); color: var(--text); font-weight: 700; }
</style>
