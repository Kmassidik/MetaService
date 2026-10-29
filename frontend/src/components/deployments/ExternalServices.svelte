<script lang="ts">
  // Existing services discovered on the machine. They are never adopted, deleted, or added to the managed VM model.
  import ActionButton from '../ActionButton.svelte'
  import { ApiError, externalServiceAction, getCommand, listExternalServices } from '../../lib/api.ts'
  import type { Command, ExternalService, ExternalServiceAction, ExternalServicesReply } from '../../lib/types.ts'

  const COMMAND_POLL_MS = 250
  const COMMAND_TIMEOUT_MS = 120_000

  const ACTIONS: readonly { id: ExternalServiceAction; label: string; busy: string; done: string }[] = [
    { id: 'start', label: 'Start', busy: 'Starting…', done: 'Started' },
    { id: 'stop', label: 'Stop', busy: 'Stopping…', done: 'Stopped' },
    { id: 'restart', label: 'Restart', busy: 'Restarting…', done: 'Restarted' },
  ]

  let { machineId }: { machineId: string } = $props()
  let reply = $state<ExternalServicesReply | null>(null)
  let loading = $state(true)
  let legacy = $state(false)
  let failure = $state('')
  let asked = 0
  const running = $derived(reply?.services.filter((service) => service.state === 'running').length ?? 0)

  /** Only the newest read may update this machine's block. A 404 means an old helper and hides just this block. */
  async function load(id: string, initial = false): Promise<void> {
    const turn = ++asked
    if (initial) loading = true
    try {
      const next = await listExternalServices(id)
      if (turn !== asked) return
      reply = next
      legacy = false
      failure = ''
    } catch (error) {
      if (turn !== asked) return
      if (error instanceof ApiError && error.status === 404) {
        reply = null
        legacy = true
        failure = ''
        return
      }
      failure = error instanceof Error ? error.message : 'Something went wrong.'
      if (!initial) throw error
    } finally {
      if (turn === asked) loading = false
    }
  }

  $effect(() => {
    const id = machineId
    reply = null
    legacy = false
    failure = ''
    void load(id, true)
    return () => { asked += 1 }
  })

  async function waitForCommand(accepted: Command): Promise<void> {
    let current = accepted
    const deadline = Date.now() + COMMAND_TIMEOUT_MS
    while (current.state !== 'succeeded' && current.state !== 'failed') {
      if (Date.now() >= deadline) throw new ApiError(0, 'timeout', 'The machine is still working. Check the service again shortly.')
      await new Promise<void>((resolve) => setTimeout(resolve, COMMAND_POLL_MS))
      current = await getCommand(accepted.id)
    }
    if (current.state === 'failed') throw new ApiError(0, 'command_failed', current.result?.error ?? 'The machine could not change the service.')
  }

  /** One POST, then the existing command's completion, then fresh read-only discovery. */
  async function run(service: ExternalService, action: ExternalServiceAction): Promise<void> {
    const id = machineId
    const accepted = await externalServiceAction(id, service.id, action)
    await waitForCommand(accepted.command)
    if (id !== machineId) return
    await load(id)
  }
</script>

{#if !legacy}
  <section class="workload-block" aria-labelledby="external-services-title">
    <div class="block-head">
      <h2 id="external-services-title">External services</h2>
      <span class="muted">{reply ? `${reply.services.length} external · ${running} running` : 'Existing Docker, Incus and Apple services'}</span>
    </div>
    {#if loading && !reply}<p class="note muted" role="status">Discovering external services…</p>{/if}
    {#if failure}<p class="err" role="alert">{failure}</p>{/if}
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
              <small class="node-meta mono">{service.runtime} · {service.kind}</small>
              <small class="node-image mono muted" title={service.image ?? ''}>{service.image ?? '—'}</small>
              <div class="acts">
                {#each ACTIONS as action (action.id)}
                  <ActionButton label={action.label} busyLabel={action.busy} doneLabel={action.done} small variant="line" onrun={() => run(service, action.id)} />
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
  .external-node.run { box-shadow: inset 4px 0 var(--accent); }
  .node-top { display: flex; align-items: flex-start; gap: 8px; }
  .node-window { display: grid; grid-template-columns: repeat(2, 1fr); flex: 0 0 24px; height: 24px; border: 1px solid var(--line-strong); }
  .node-window i { border: 1px solid var(--pane-line); background: var(--accent); }
  .node-name { min-width: 0; flex: 1; }
  .node-name b { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 13px; }
  .service-id { display: block; margin-top: 2px; font-size: 9px; font-weight: 400; color: var(--m50); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .node-meta, .node-image { display: block; margin-top: 8px; font-size: 10px; }
  .node-image { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .acts { display: flex; align-items: flex-start; gap: 6px; flex-wrap: wrap; margin-top: 10px; }
  @media (max-width: 520px) { .external-nodes { grid-template-columns: 1fr; } }
</style>
