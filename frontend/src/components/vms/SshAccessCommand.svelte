<script lang="ts">
  // The command to log in with, on the VM page's Access tab. It reads the SSH keys once when the VM is running (and again if the VM starts or changes its address)
  // and shows the same block as the SSH keys dialog, but only when SSH is ready or when it says why there is no command. Setup progress and failures are left to the dialog.
  import { untrack } from 'svelte'
  import SshSetupBlock from './SshSetupBlock.svelte'
  import { listSshKeys } from '../../lib/api.ts'
  import { environmentHref } from '../../lib/routes.ts'
  import { setupBlock } from '../../lib/sshSetup.ts'
  import { RUNNING_STATE } from '../../lib/vm.ts'
  import type { Machine, SshKeyList, Workload } from '../../lib/types.ts'

  let { machine, workload }: { machine: Machine; workload: Workload } = $props()
  let list = $state<SshKeyList | null>(null)
  let unreadable = $state(false)
  const block = $derived(setupBlock(list, workload.state))
  const shown = $derived(block.kind === 'ready' || block.kind === 'no-command')

  /** The address of a running VM, or null. A derived value only changes when the address does, so the machine list refreshing every few seconds does not read the keys again. */
  const reachable = $derived(workload.state === RUNNING_STATE ? (workload.address ?? null) : null)

  // Only a running VM with an address has a command worth showing; the answer of an earlier VM state never lands on a later one.
  $effect(() => {
    if (reachable === null) return
    let current = true
    untrack(() => listSshKeys(machine.id, workload.id)).then(
      (next) => { if (current) { list = next; unreadable = false } },
      () => { if (current) unreadable = true },
    )
    return () => { current = false }
  })
</script>

{#if unreadable}
  <p class="hint">The login command could not be read. Open Manage SSH keys to see it.</p>
{:else if shown}
  <div class="command"><SshSetupBlock {block} address={workload.address} subject={workload.name} environmentHref={environmentHref(machine.id)} /></div>
{/if}

<style>
  .command { margin-top: 12px; }
  .hint { font-size: 13px; color: var(--m60); line-height: 1.6; margin: 8px 0 0; }
</style>
