<script lang="ts">
  // One service that was on the machine before MetaService: what it is, and Start / Stop / Restart. It is never adopted, deleted, or added to the managed VM model.
  import ActionButton from '../ActionButton.svelte'
  import Dialog from '../Dialog.svelte'
  import RuntimeLogo from './RuntimeLogo.svelte'
  import { externalBlocks } from '../../lib/externalBlocks.ts'
  import type { ExternalService, ExternalServiceAction } from '../../lib/types.ts'

  const ACTIONS: readonly { id: ExternalServiceAction; label: string; busy: string; done: string }[] = [
    { id: 'start', label: 'Start', busy: 'Starting…', done: 'Started' },
    { id: 'stop', label: 'Stop', busy: 'Stopping…', done: 'Stopped' },
    { id: 'restart', label: 'Restart', busy: 'Restarting…', done: 'Restarted' },
  ]

  interface Props {
    service: ExternalService | null
    onClose: () => void
    onRun: (service: ExternalService, action: ExternalServiceAction) => Promise<void>
  }

  let { service, onClose, onRun }: Props = $props()
  const logo = $derived(service ? (externalBlocks([service])[0]?.logo ?? null) : null)
</script>

<Dialog open={service !== null} title={service?.name ?? ''} {onClose} closeButton backdropClose>
  {#if service}
    <div class="ext" data-service-id={service.id}>
      <p class="state"><RuntimeLogo {logo} size={22} /><span class="tag" class:run={service.state === 'running'}>{service.state}</span><span class="muted">External · {service.runtime} · {service.kind}</span></p>
      <dl>
        <div><dt>Image</dt><dd class="mono">{service.image ?? '—'}</dd></div>
        <div><dt>ID</dt><dd class="mono">{service.id}</dd></div>
      </dl>
      <p class="muted note">It was here before MetaService. MetaService can start, stop and restart it, and never deletes it or counts it in a VM's space.</p>
      <div class="acts">
        {#each ACTIONS as action (action.id)}
          <ActionButton label={action.label} busyLabel={action.busy} doneLabel={action.done} small variant="line" onrun={() => onRun(service, action.id)} />
        {/each}
      </div>
    </div>
  {/if}
</Dialog>

<style>
  .ext { display: grid; gap: 12px; min-width: 0; }
  .state { display: flex; align-items: center; gap: 10px; margin: 0; font-size: 12px; }
  dl { display: grid; gap: 8px; margin: 0; }
  dl div { display: grid; gap: 2px; }
  dt { font-size: 11px; color: var(--m60); letter-spacing: .08em; text-transform: uppercase; }
  dd { margin: 0; font-size: 12px; overflow-wrap: anywhere; }
  .note { margin: 0; font-size: 12px; }
  .acts { display: flex; align-items: flex-start; gap: 6px; flex-wrap: wrap; }
</style>
