<script lang="ts">
  // Apps already installed in managed VMs. This is another view of workload.app, never another workload or a separate discovery request.
  import AppChip from '../vm/AppChip.svelte'
  import { appChip, appTitle } from '../../lib/appInstall.ts'
  import { appWorkloads } from '../../lib/deployments.ts'
  import { vmHref } from '../../lib/routes.ts'
  import type { Machine } from '../../lib/types.ts'

  let { machine }: { machine: Machine } = $props()
  const rows = $derived(appWorkloads(machine))
</script>

<section class="workload-block" aria-labelledby="apps-title">
  <div class="block-head">
    <h2 id="apps-title">Apps</h2>
    <span class="muted">{rows.length} in managed VMs</span>
  </div>
  {#if rows.length === 0}
    <p class="note muted">No apps installed in managed VMs.</p>
  {:else}
    <div class="tablewrap">
      <table class="restable stack" aria-label="Apps">
        <thead><tr><th>App</th><th>Managed VM</th><th>State</th><th>Detail</th></tr></thead>
        <tbody>
          {#each rows as workload (workload.id)}
            {@const app = workload.app}
            {#if app}
              {@const chip = appChip(app)}
              <tr data-app-workload={workload.id}>
                <td class="c-name" data-label="App">{appTitle(app.name)}</td>
                <td data-label="Managed VM"><a href={vmHref(machine.id, workload.id)}>{workload.name}</a><small class="vm-id mono">{workload.id}</small></td>
                <td data-label="State">{#if chip}<AppChip {chip} />{/if}</td>
                <td class="muted" data-label="Detail">{app.message ?? '—'}</td>
              </tr>
            {/if}
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</section>

<style>
  .workload-block { margin-top: 24px; padding-top: 20px; border-top: 1px solid var(--line); }
  .block-head { display: flex; align-items: baseline; gap: 12px; }
  .block-head h2 { margin: 0; font-family: var(--mono); font-size: 12px; letter-spacing: 0.12em; text-transform: uppercase; }
  .block-head span { font-size: 12px; }
  .note { margin: 12px 0 0; font-size: 13px; }
  .tablewrap { padding-bottom: 0; }
  .vm-id { display: block; margin-top: 2px; font-size: 11px; font-weight: 400; color: var(--m50); }
  td:last-child { overflow-wrap: anywhere; }
</style>
