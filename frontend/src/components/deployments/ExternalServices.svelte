<script lang="ts">
  // The list view of the services that were on the machine before MetaService (table and cards views; the Building draws them as blocks).
  // They are never adopted, deleted, or added to the managed VM model.
  import ActionButton from '../ActionButton.svelte'
  import type { ExternalServicesStore } from '../../lib/externalServicesStore.svelte.ts'
  import type { ExternalServiceAction } from '../../lib/types.ts'

  const ACTIONS: readonly { id: ExternalServiceAction; label: string; busy: string; done: string }[] = [
    { id: 'start', label: 'Start', busy: 'Starting…', done: 'Started' },
    { id: 'stop', label: 'Stop', busy: 'Stopping…', done: 'Stopped' },
    { id: 'restart', label: 'Restart', busy: 'Restarting…', done: 'Restarted' },
  ]

  let { store, managedCount }: { store: ExternalServicesStore; managedCount: number } = $props()
  const reply = $derived(store.reply)
</script>

{#if !store.legacy}
  <section class="workload-block" aria-labelledby="external-services-title">
    <div class="block-head">
      <h2 id="external-services-title">Compute workloads</h2>
      <span class="muted">{reply ? `${managedCount} managed · ${reply.services.length} external · ${store.running} external running` : 'Managed VMs and existing Docker, Incus and Apple services'}</span>
    </div>
    {#if store.loading && !reply}<p class="note muted" role="status">Discovering external services…</p>{/if}
    {#if store.failure}<p class="err" role="alert">{store.failure}</p>{/if}
    {#if reply}
      {#if reply.warnings.length > 0}
        <ul class="warnings" aria-label="External service warnings">
          {#each reply.warnings as warning}<li><b>{warning.runtime}</b>: {warning.message}</li>{/each}
        </ul>
      {/if}
      {#if reply.services.length === 0}
        <p class="note muted">No external services found.</p>
      {:else}
        <div class="external-nodes" aria-label="External service nodes">
          {#each reply.services as service (service.id)}
            <article class="external-node" class:run={service.state === 'running'} data-service-id={service.id}>
              <div class="node-top">
                <span class="node-window" aria-hidden="true"><i></i><i></i><i></i><i></i></span>
                <div class="node-name"><b>{service.name}</b><small class="service-id mono">{service.id}</small></div>
                <span class="tag" class:run={service.state === 'running'}>{service.state}</span>
              </div>
              <small class="node-meta mono">External · {service.runtime} · {service.kind}</small>
              <small class="node-image mono muted" title={service.image ?? ''}>{service.image ?? '—'}</small>
              <div class="acts">
                {#each ACTIONS as action (action.id)}
                  <ActionButton label={action.label} busyLabel={action.busy} doneLabel={action.done} small variant="line" onrun={() => store.run(service, action.id)} />
                {/each}
              </div>
            </article>
          {/each}
        </div>
      {/if}
    {/if}
  </section>
{/if}

<style>
  .workload-block { min-width: 0; }
  .block-head { display: flex; align-items: baseline; gap: 12px; flex-wrap: wrap; }
  .block-head h2 { margin: 0; font-family: var(--mono); font-size: 12px; letter-spacing: 0.12em; text-transform: uppercase; }
  .block-head span { font-size: 12px; }
  .note { margin: 12px 0 0; font-size: 13px; }
  .err { margin-top: 12px; margin-bottom: 0; }
  .warnings { margin: 12px 0 0; padding: 10px 14px 10px 32px; border: 1px solid var(--warn-line); background: var(--warn-bg); color: var(--warn); font-size: 12px; }
  .external-nodes { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 8px; margin-top: 12px; }
  .external-node { min-width: 0; padding: 10px; border: 1px solid var(--line-strong); background: var(--surface); }
  .external-node.run { box-shadow: inset 4px 0 var(--chart-orange); }
  .node-top { display: flex; align-items: flex-start; gap: 8px; }
  .node-window { display: grid; grid-template-columns: repeat(2, 1fr); flex: 0 0 24px; height: 24px; border: 1px solid var(--line-strong); }
  .node-window i { border: 1px solid var(--pane-line); background: var(--chart-orange); }
  .node-name { min-width: 0; flex: 1; }
  .node-name b { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 13px; }
  .service-id { display: block; margin-top: 2px; font-size: 9px; font-weight: 400; color: var(--m50); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .node-meta, .node-image { display: block; margin-top: 8px; font-size: 10px; }
  .node-image { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .acts { display: flex; align-items: flex-start; gap: 6px; flex-wrap: wrap; margin-top: 10px; }
  @media (max-width: 520px) { .external-nodes { grid-template-columns: 1fr; } }
</style>
