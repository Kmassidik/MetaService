<script lang="ts">
  // The Terminal button of one VM. Always shown; works only when the VM is running on a machine whose helper has a console, and otherwise says why. It opens the one terminal window the panel has.
  import { openConsole } from '../../lib/terminalStore.svelte.ts'
  import { consoleTitle, terminalAccess } from '../../lib/terminalAccess.ts'
  import type { Machine, Workload } from '../../lib/types.ts'

  let { machine, workload }: { machine: Pick<Machine, 'id' | 'os' | 'state' | 'capabilities'>; workload: Pick<Workload, 'id' | 'name' | 'state' | 'kind'> } = $props()
  const access = $derived(terminalAccess(machine, workload))
  const open = () => openConsole({ machine: machine.id, workload: workload.id, name: consoleTitle(workload) })
</script>

<span class="tbtn" title={access.allowed ? 'Open a terminal on this VM' : access.title}>
  <button class="btn line sm" type="button" disabled={!access.allowed} aria-label="Terminal for {consoleTitle(workload)}{access.allowed ? '' : `: ${access.text}`}" onclick={open}>
    ▸ Terminal{#if !access.allowed}<small>{access.text}</small>{/if}
  </button>
</span>

<style>
  /* Above the stretched row link of the All VMs table, so a click lands on the button and not on the row. */
  .tbtn { position: relative; z-index: 2; display: inline-block; }
  button { display: inline-flex; flex-direction: column; align-items: flex-start; gap: 2px; text-align: left; }
  small { font-size: 9.5px; font-weight: 400; letter-spacing: 0; }
</style>
