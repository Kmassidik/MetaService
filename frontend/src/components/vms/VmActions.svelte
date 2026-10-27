<script lang="ts">
  // The action buttons of one VM as icons: Terminal, SSH keys, Start or Stop, Open chat, Install chat, then Delete alone at the end.
  // Start, Stop and Install chat each run one request at a time (ActionState): a second press while one runs sends nothing, and the result shows in a small line below.
  import ActionLine from '../ActionLine.svelte'
  import IconButton from '../IconButton.svelte'
  import SshKeysDialog from './SshKeysDialog.svelte'
  import { lineOf } from '../../lib/action.ts'
  import { ActionState } from '../../lib/action.svelte.ts'
  import { consoleTitle, terminalAccess } from '../../lib/terminalAccess.ts'
  import { deleteFailure } from '../../lib/deleteOrders.ts'
  import { openConsole } from '../../lib/terminalStore.svelte.ts'
  import { vmActionFacts, vmActions, type VmActionHandlers, type VmActionId } from '../../lib/vmActions.ts'
  import { VM_ICONS } from './vmIcons.ts'
  import type { Command, Machine, Workload } from '../../lib/types.ts'

  interface Props {
    machine: Machine
    workload: Workload
    commands: Command[]
    handlers: VmActionHandlers
  }

  type GuardedId = Extract<VmActionId, 'start' | 'stop' | 'install-chat'>

  interface Words {
    busy: string
    done: string
  }

  interface Button {
    label: string
    /** The short word beside the icon on a phone. */
    text: string
    icon: string
    onclick: () => void
    disabled?: boolean
    busy?: boolean
  }

  let { machine, workload, commands, handlers }: Props = $props()
  let keysOpen = $state(false)
  const runs: Record<GuardedId, ActionState> = { start: new ActionState(), stop: new ActionState(), 'install-chat': new ActionState() }
  /** The press that spoke last, and the words of its success line: the button may change meaning while it runs (Start becomes Stop), but the line must say what was asked. */
  let asked = $state<{ id: GuardedId | null; done: string }>({ id: null, done: '' })
  const current = $derived(asked.id ? runs[asked.id] : null)
  const line = $derived(current ? lineOf(current.view, asked.done) : '')
  const layout = $derived(vmActions(vmActionFacts(workload)))
  const access = $derived(terminalAccess(machine, workload))
  const installed = $derived(Boolean(workload.bundle_version))
  const deleting = $derived(workload.state === 'deleting')
  const deleteError = $derived(deleting ? null : deleteFailure(commands, machine.id, workload.id))

  /** A button that runs one request at a time. */
  function guarded(id: GuardedId, label: string, text: string, icon: string, words: Words, work: () => Promise<unknown>): Button {
    const run = runs[id]
    const press = () => {
      if (run.busy) return
      asked = { id, done: words.done }
      void run.run(work)
    }
    return { label: run.busy ? words.busy : label, text, icon, onclick: press, disabled: run.busy, busy: run.busy }
  }

  const buttons = $derived<Record<VmActionId, Button>>({
    terminal: {
      label: access.allowed ? 'Terminal' : `Terminal: ${access.text}`,
      text: access.allowed ? 'Terminal' : access.text,
      icon: VM_ICONS.terminal,
      disabled: !access.allowed,
      onclick: () => openConsole({ machine: machine.id, workload: workload.id, name: consoleTitle(workload) }),
    },
    'ssh-keys': { label: 'SSH keys', text: 'Keys', icon: VM_ICONS.key, onclick: () => (keysOpen = true) },
    start: guarded('start', 'Start', 'Start', VM_ICONS.start, { busy: 'Starting…', done: 'Started' }, () => handlers.onAct(machine, workload, 'start')),
    stop: guarded('stop', 'Stop', 'Stop', VM_ICONS.stop, { busy: 'Stopping…', done: 'Stopped' }, () => handlers.onAct(machine, workload, 'stop')),
    'open-chat': { label: 'Open chat', text: 'Chat', icon: VM_ICONS.chat, onclick: () => handlers.onOpenChat(machine, workload) },
    'install-chat': guarded('install-chat', installed ? 'Reinstall chat' : 'Install chat', installed ? 'Reinstall' : 'Install', VM_ICONS.install, { busy: 'Installing…', done: 'Installed' }, () => handlers.onInstall(machine, workload)),
    delete: { label: deleting ? 'Deleting…' : 'Delete', text: deleting ? 'Deleting…' : 'Delete', icon: VM_ICONS.trash, disabled: deleting, busy: deleting, onclick: () => handlers.onDelete(machine, workload) },
  })
</script>

{#snippet icon(id: VmActionId)}
  <IconButton {...buttons[id]} subject={workload.name} variant={id === 'delete' ? 'danger' : 'normal'} />
{/snippet}

<div class="vm-acts">
  <div class="buttons">
    <span class="group">{#each layout.main as id (id)}{@render icon(id)}{/each}</span>
    <span class="group apart">{#each layout.danger as id (id)}{@render icon(id)}{/each}</span>
  </div>
  <ActionLine {line} failed={current?.status === 'failed'} />
  <ActionLine line={deleteError ?? ''} failed={deleteError !== null} />
  {#if keysOpen}<SshKeysDialog {machine} {workload} open={keysOpen} onClose={() => (keysOpen = false)} />{/if}
</div>

<style>
  /* Above the stretched row link of the All VMs table, so a click lands on the button and not on the row. */
  .vm-acts { position: relative; z-index: 2; display: grid; justify-items: end; gap: 4px; }
  .buttons { display: flex; flex-wrap: wrap; justify-content: flex-end; align-items: center; gap: 6px 18px; }
  .group { display: inline-flex; flex-wrap: wrap; gap: 6px; justify-content: flex-end; }
  @media (max-width: 820px) {
    .vm-acts { justify-items: start; }
    .buttons, .group { justify-content: flex-start; }
  }
</style>
