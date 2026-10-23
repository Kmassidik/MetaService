<script lang="ts">
  // The one Create VM window, used from every place that makes a VM (a machine's page, All VMs, the empty states, the old #/vms/create address).
  // It is only a shell: the form inside is built fresh each time the window opens, follows another address or is reset (the ↺ in the title bar). On a machine's own page `only` fixes the machine.
  import Dialog from '../Dialog.svelte'
  import Owl from '../Owl.svelte'
  import CreateVmForm from './create/CreateVmForm.svelte'
  import type { Machine } from '../../lib/types.ts'

  interface Props {
    open: boolean
    machines: Machine[]
    /** The address the window was opened from (for the machine it names), without the #. */
    route: string
    /** Set when opened from one machine's own page: the VM goes there and nowhere else. */
    only?: Machine | null
    onClose: () => void
    /** The VM was ordered: read the lists again so the "Creating…" card shows. */
    onCreated: () => void
  }

  let { open, machines, route, only = null, onClose, onCreated }: Props = $props()
  /** True while the order is on its way: the X and Escape do nothing until it ends. */
  let busy = $state(false)
  /** Counts the resets: each one builds the form again from its starting values. */
  let resets = $state(0)

  const closeByPerson = () => {
    if (!busy) onClose()
  }
</script>

<Dialog {open} title="Create VM" onClose={closeByPerson} closeButton locked={busy} roomy onReset={machines.length > 0 ? () => resets++ : undefined}>
  {#if open && machines.length === 0}
    <div class="empty" role="status"><Owl name="emptyMachines" />No machines yet. Add one first, then make a VM on it.<a class="btn green sm" href="#/machines/find">Find machines</a></div>
  {:else if open}
    {#key `${route} ${resets}`}
      <CreateVmForm {machines} {route} {only} bind:busy {onClose} {onCreated} />
    {/key}
  {/if}
</Dialog>
