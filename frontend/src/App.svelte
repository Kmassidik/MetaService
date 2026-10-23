<script lang="ts">
  import { onMount } from 'svelte'
  import { ApiError, authStatus, brainStatus, bundleOverview, chatLink, installBundle, pinBundle, rollbackBundle, getSession, listCommands, listMachines, removeMachine, remoteMachines, remoteRemove, signOut, testBrain, uninstallBundle, workloadAction } from './lib/api.ts'
  import { LIST_POLL_MS } from './lib/stats.ts'
  import { newestVersion } from './lib/environment.ts'
  import { machineFromRoute, machineHref, machinesView, pageFor, vmFromRoute, vmsHref, createVmOpen } from './lib/routes.ts'
  import Owl from './components/Owl.svelte'
  import Login from './components/Login.svelte'
  import Sidebar from './components/Sidebar.svelte'
  import Overview from './pages/Overview.svelte'
  import Machines from './pages/Machines.svelte'
  import MachineDetail from './pages/MachineDetail.svelte'
  import VmDetail from './pages/VmDetail.svelte'
  import VmsList from './pages/VmsList.svelte'
    import TokenLedger from './pages/TokenLedger.svelte'
  import Health from './pages/Health.svelte'
  import Settings from './pages/Settings.svelte'
  import NotFound from './pages/NotFound.svelte'
  import ConnectMachine from './components/ConnectMachine.svelte'
  import RemoveMachineDialog from './components/RemoveMachineDialog.svelte'
  import RenameMachineDialog from './components/RenameMachineDialog.svelte'
  import CreateVmDialog from './components/vms/CreateVmDialog.svelte'
  import ConfirmDialog from './components/ConfirmDialog.svelte'
  import { deleteVmCopy } from './lib/confirmCopy.ts'
  import type { VmActionHandlers } from './lib/vmActions.ts'
  import ChatLink from './components/ChatLink.svelte'
  import Terminal from './components/Terminal.svelte'
  import { closeConsole, consoleTarget } from './lib/terminalStore.svelte.ts'
  import { stopNote } from './lib/stoppedReason.ts'
  import { dismissedOrders, sessionOrders } from './lib/pendingStore.svelte.ts'
  import { mergeOrders, pendingVms } from './lib/pendingVms.ts'
  import type { BrainStatus, BundleOverview, Command, Machine, RemoteMachineInfo, Workload } from './lib/types.ts'

  const CLOCK_MS = 5_000
  /** While a VM is being made the lists are read this often, so it shows up soon after the machine reports it. */
  const MAKING_POLL_MS = 3_000

  let phase = $state<'loading' | 'signedOut' | 'ready' | 'error'>('loading')
  let username = $state('')
  let configured = $state(true)
  let minPasswordLength = $state(8)
  let machines = $state<Machine[]>([])
  let now = $state(Date.now())
  let route = $state(location.hash.replace(/^#/, '') || '/')
  const page = $derived(pageFor(route))
  const detailId = $derived(machineFromRoute(route))
  const vmId = $derived(vmFromRoute(route))
  /** The machine a new VM is being created on, when the dialog was opened from that machine's own page. */
  let creatingOnId = $state<string | null>(null)
  const creatingOn = $derived(machines.find((machine) => machine.id === creatingOnId) ?? null)
  let banner = $state('')
  let connecting = $state(false)
  let connectHost = $state('')
  let commands = $state<Command[]>([])
  let bundles = $state<BundleOverview | null>(null)
  let brain = $state<BrainStatus | null>(null)
  /** False until the first answer from the Root, so an empty list is never shown while the data is still on its way. */
  let loaded = $state(false)
  let openLink = $state<string | null>(null)
  let creating = $state(false)
  /** The Create VM window is open from a button (creating) or from the old Create VM address. */
  const createOpen = $derived(loaded && (creating || createVmOpen(route)))
  let deleting = $state<{ machine: Machine; workload: Workload } | null>(null)
  let removing = $state<Machine | null>(null)
  let renaming = $state<Machine | null>(null)
  let remoteInfos = $state<RemoteMachineInfo[]>([])
  const removingRemote = $derived(remoteInfos.find((info) => info.machine === removing?.id) ?? null)
  const vmHandlers: VmActionHandlers = { onAct: act, onInstall: install, onOpenChat: openChat, onDelete: (machine, workload) => (deleting = { machine, workload }) }
  const deleteCopy = $derived(deleting ? deleteVmCopy(deleting.machine, deleting.workload) : deleteVmCopy({ name: '' }, { name: '' }))
  const pending = $derived(pendingVms(mergeOrders(commands, sessionOrders()), machines, now, dismissedOrders()))
  const openConsoleTarget = $derived(consoleTarget())
  const consoleMachine = $derived(machines.find((machine) => machine.id === openConsoleTarget?.machine))
  const consoleVm = $derived(consoleMachine?.workloads.find((workload) => workload.id === openConsoleTarget?.workload) ?? null)
  const consoleNote = $derived(consoleMachine && consoleVm ? stopNote(consoleMachine.id, consoleVm, commands) : null)
  const making = $derived(pending.some((entry) => entry.stage !== 'failed'))

  $effect(() => {
    if (!making) return
    const timer = setInterval(() => !document.hidden && refresh(), MAKING_POLL_MS)
    return () => clearInterval(timer)
  })

  async function start() {
    try {
      const who = await getSession()
      if (who) {
        username = who
        phase = 'ready'
        await refresh()
        return
      }
      const status = await authStatus()
      configured = status.configured
      minPasswordLength = status.min_password_length ?? 8
      phase = 'signedOut'
    } catch (error) {
      banner = error instanceof ApiError && error.status === 0 ? 'Cannot reach the Root.' : 'Something went wrong.'
      phase = 'error'
    }
  }

  async function refresh() {
    if (phase !== 'ready') return
    try {
      ;[machines, commands, bundles, brain, remoteInfos] = await Promise.all([listMachines(), listCommands(), bundleOverview(), brainStatus(), remoteMachines()])
      banner = ''
      loaded = true
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) {
        await restart()
        return
      }
      banner = 'Cannot reach the Root. Showing the last data.'
    }
  }

  /** Closes the window, whichever way it was opened. The old address is replaced by plain All VMs, so Back does not reopen it. */
  function closeCreate() {
    creating = false
    creatingOnId = null
    if (!createVmOpen(route)) return
    history.replaceState(null, '', vmsHref(null))
    route = '/vms'
  }

  function startCreate(machine?: Machine) {
    creatingOnId = machine?.id ?? null
    creating = true
  }

  /** The empty Machines list sends the person to Find machines, the one way to add a computer. */
  function goFind() {
    location.hash = '#/machines/find'
  }

  function startConnect(host = '') {
    connectHost = host
    connecting = true
  }

  async function leave() {
    try {
      await signOut()
    } finally {
      await restart()
    }
  }

  /** Back to the sign-in screen first, so no page reads data of a session that has ended. */
  async function restart() {
    phase = 'loading'
    loaded = false
    machines = []
    await start()
  }

  async function testProvider() {
    await testBrain()
    await refresh()
  }

  /** Start or stop a workload; the result shows up in the activity list. A refusal is thrown: the button that asked shows it next to itself. */
  async function act(machine: Machine, workload: Workload, action: 'start' | 'stop') {
    await workloadAction(machine.id, workload.id, action)
    await refresh()
  }

  /** The terminal window's "Start the VM": starts the VM that window is about. */
  async function startConsoleVm() {
    if (!consoleMachine || !consoleVm) return
    await act(consoleMachine, consoleVm, 'start')
  }

  // The chat bundle calls below throw a refusal (for example "no chat is built on the parent"): the control that asked shows it next to itself.
  async function pin(version: string) {
    await pinBundle(version)
    await refresh()
  }

  async function rollback() {
    await rollbackBundle()
    await refresh()
  }

  async function install(machine: Machine, workload: Workload | null) {
    await installBundle(machine.id, workload?.id)
    await refresh()
  }

  /** Ruvio on or off for a machine. */
  async function setRuvio(machine: Machine, on: boolean) {
    await (on ? installBundle(machine.id) : uninstallBundle(machine.id))
    await refresh()
  }

  const newestHelper = $derived(newestVersion(machines.map((machine) => machine.agent_version)))

  async function openChat(machine: Machine, workload: Workload | null) {
    try {
      openLink = await chatLink(machine.id, workload?.id)
    } catch (error) {
      banner = error instanceof ApiError ? error.message : 'Something went wrong.'
    }
  }

  /** Deletes the VM the dialog is about. A refusal is thrown: the dialog shows it and stays. */
  async function confirmDelete() {
    if (!deleting) return
    await workloadAction(deleting.machine.id, deleting.workload.id, 'delete')
    if (vmId) location.hash = machineHref(deleting.machine.id)
    await refresh()
  }

  /** Removes a machine; `body` is the SSH login choice for a machine installed over SSH. A refusal is thrown: the dialog shows it and stays. */
  async function confirmRemove(machine: Machine, body: Record<string, unknown> | null) {
    await (body ? remoteRemove(machine.id, body) : removeMachine(machine.id))
    await refresh()
  }

  onMount(() => {
    const onRoute = () => {
      route = location.hash.replace(/^#/, '') || '/'
      closeConsole()
    }
    addEventListener('hashchange', onRoute)
    start()
    const refreshTimer = setInterval(() => !document.hidden && refresh(), LIST_POLL_MS)
    const clockTimer = setInterval(() => (now = Date.now()), CLOCK_MS)
    const wake = () => !document.hidden && refresh()
    document.addEventListener('visibilitychange', wake)
    return () => {
      clearInterval(refreshTimer)
      clearInterval(clockTimer)
      document.removeEventListener('visibilitychange', wake)
      removeEventListener('hashchange', onRoute)
    }
  })
</script>

{#if phase === 'loading'}
  <p class="center muted" role="status"><Owl name="loading" eager />Loading…</p>
{:else if phase === 'error'}
  <main class="center">
    <Owl name="notFound" eager />
    <p role="alert">{banner}</p>
    <button class="btn line" type="button" onclick={start}>Try again</button>
  </main>
{:else if phase === 'signedOut'}
  <Login {configured} minLength={minPasswordLength} onDone={start} />
{:else}
  <div class="announce">MetaService · control panel</div>
  <div class="shell">
    <Sidebar active={page} {route} {username} onSignOut={leave} />
    <main class="main">
      {#if !loaded}
        <div class="phead"><h1>Loading…</h1></div>
      {:else}
      {#if page === 'machines' && detailId && vmId}
        <VmDetail machine={machines.find((machine) => machine.id === detailId)} workloadId={vmId} pinned={bundles?.pinned} {banner} {commands} onInstall={install} onOpenChat={openChat} onAct={act} onDelete={(machine, workload) => (deleting = { machine, workload })} />
      {:else if page === 'machines' && detailId}
        <MachineDetail {route} machine={machines.find((machine) => machine.id === detailId)} remote={remoteInfos.find((info) => info.machine === detailId) ?? null} {commands} {pending} {now} pinned={bundles?.pinned} {newestHelper} chatsBuilt={bundles?.bundles.length ?? 0} onRuvio={setRuvio} onChanged={refresh} onCreate={startCreate} onRemove={(machine) => (removing = machine)} onRename={(machine) => (renaming = machine)} onInstall={install} onOpenChat={openChat} onAct={act} onDelete={(machine, workload) => (deleting = { machine, workload })} />
      {:else if page === 'machines'}
        <Machines {machines} {now} pinned={bundles?.pinned} {banner} view={machinesView(route)} onRemove={(machine) => (removing = machine)} onRename={(machine) => (renaming = machine)} onAdd={goFind} onConnect={startConnect} />
      {:else if page === 'vms'}
        <VmsList {machines} {route} {banner} {pending} handlers={vmHandlers} />
      {:else if page === 'usage'}
        <TokenLedger {brain} />
      {:else if page === 'health'}
        <Health {machines} {commands} {now} />
      {:else if page === 'settings'}
        <Settings {brain} {bundles} onTest={testProvider} onPin={pin} onRollback={rollback} />
      {:else if page === 'notfound'}
        <NotFound {route} />
      {:else}
        <Overview {machines} {brain} {bundles} />
      {/if}
      {/if}
    </main>
  </div>
  <ConnectMachine open={connecting} host={connectHost} onClose={() => (connecting = false)} onInstalled={refresh} />
  <ChatLink link={openLink} onClose={() => (openLink = null)} />
  {#if openConsoleTarget}<Terminal machine={openConsoleTarget.machine} workload={openConsoleTarget.workload} name={openConsoleTarget.name} onclose={closeConsole} vm={consoleVm} note={consoleNote} onstart={startConsoleVm} onchanged={refresh} />{/if}
  <CreateVmDialog open={createOpen} {machines} {route} only={creatingOn} onClose={closeCreate} onCreated={refresh} />
  <ConfirmDialog open={deleting !== null} {...deleteCopy} onconfirm={confirmDelete} onClose={() => (deleting = null)} />
  <RenameMachineDialog machine={renaming} onSaved={refresh} onClose={() => (renaming = null)} />
  <RemoveMachineDialog machine={removing} info={removingRemote} onconfirm={confirmRemove} onClose={() => (removing = null)} />
{/if}

<style>
  .center { min-height: 100svh; display: grid; place-content: center; justify-items: center; gap: 12px; text-align: center; }
</style>
