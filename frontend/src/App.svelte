<script>
  import { onMount } from 'svelte'
  import { ApiError, authStatus, brainStatus, bundleOverview, chatLink, installBundle, pinBundle, rollbackBundle, getSession, listCommands, listMachines, removeMachine, signOut, testBrain, workloadAction } from './lib/api.js'
  import { machineFromRoute, pageFor } from './lib/routes.js'
  import Login from './components/Login.svelte'
  import Sidebar from './components/Sidebar.svelte'
  import Overview from './pages/Overview.svelte'
  import Machines from './pages/Machines.svelte'
  import MachineDetail from './pages/MachineDetail.svelte'
  import TokenLedger from './pages/TokenLedger.svelte'
  import Health from './pages/Health.svelte'
  import Settings from './pages/Settings.svelte'
  import AddMachine from './components/AddMachine.svelte'
  import ConfirmRemove from './components/ConfirmRemove.svelte'
  import NewWorkload from './components/NewWorkload.svelte'
  import ConfirmDelete from './components/ConfirmDelete.svelte'
  import ChatLink from './components/ChatLink.svelte'

  const REFRESH_MS = 10_000
  const CLOCK_MS = 5_000

  let phase = $state('loading')
  let username = $state('')
  let configured = $state(true)
  let machines = $state([])
  let now = $state(Date.now())
  let route = $state(location.hash.replace(/^#/, '') || '/')
  const page = $derived(pageFor(route))
  const detailId = $derived(machineFromRoute(route))
  /** The machine a new VM is being created on, when the dialog was opened from that machine's own page. */
  let creatingOnId = $state(null)
  const creatingOn = $derived(machines.find((machine) => machine.id === creatingOnId) ?? null)
  let banner = $state('')
  let adding = $state(false)
  let commands = $state([])
  let bundles = $state(null)
  let brain = $state(null)
  /** False until the first answer from the Root, so an empty list is never shown while the data is still on its way. */
  let loaded = $state(false)
  let openLink = $state(null)
  let creating = $state(false)
  let deleting = $state(null)
  let deleteBusy = $state(false)
  let deleteFailure = $state('')
  let removing = $state(null)
  let removeBusy = $state(false)
  let removeFailure = $state('')

  async function start() {
    try {
      const who = await getSession()
      if (who) {
        username = who
        phase = 'ready'
        await refresh()
        return
      }
      configured = (await authStatus()).configured
      phase = 'signedOut'
    } catch (error) {
      banner = error instanceof ApiError && error.status === 0 ? 'Cannot reach the Root.' : 'Something went wrong.'
      phase = 'error'
    }
  }

  async function refresh() {
    if (phase !== 'ready') return
    try {
      ;[machines, commands, bundles, brain] = await Promise.all([listMachines(), listCommands(), bundleOverview(), brainStatus()])
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

  function startCreate(machine) {
    creatingOnId = machine?.id ?? null
    creating = true
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

  /** Start or stop a workload; the result shows up in the activity list. */
  async function act(machine, workload, action) {
    try {
      await workloadAction(machine.id, workload.id, action)
      await refresh()
    } catch (error) {
      banner = error instanceof ApiError ? error.message : 'Something went wrong.'
    }
  }

  async function tryAction(work) {
    try {
      await work()
      await refresh()
    } catch (error) {
      banner = error instanceof ApiError ? error.message : 'Something went wrong.'
    }
  }

  const pin = (version) => tryAction(() => pinBundle(version))
  const rollback = () => tryAction(() => rollbackBundle())
  const install = (machine, workload) => tryAction(() => installBundle(machine.id, workload?.id))

  async function openChat(machine, workload) {
    try {
      openLink = await chatLink(machine.id, workload?.id)
    } catch (error) {
      banner = error instanceof ApiError ? error.message : 'Something went wrong.'
    }
  }

  async function confirmDelete() {
    deleteBusy = true
    deleteFailure = ''
    try {
      await workloadAction(deleting.machine.id, deleting.workload.id, 'delete')
      deleting = null
      await refresh()
    } catch (error) {
      deleteFailure = error instanceof ApiError ? error.message : 'Something went wrong.'
    } finally {
      deleteBusy = false
    }
  }

  async function confirmRemove() {
    removeBusy = true
    removeFailure = ''
    try {
      await removeMachine(removing.id)
      removing = null
      await refresh()
    } catch (error) {
      removeFailure = error instanceof ApiError ? error.message : 'Something went wrong.'
    } finally {
      removeBusy = false
    }
  }

  onMount(() => {
    const onRoute = () => (route = location.hash.replace(/^#/, '') || '/')
    addEventListener('hashchange', onRoute)
    start()
    const refreshTimer = setInterval(() => !document.hidden && refresh(), REFRESH_MS)
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
  <p class="center muted" role="status">Loading…</p>
{:else if phase === 'error'}
  <main class="center">
    <p role="alert">{banner}</p>
    <button class="btn line" type="button" onclick={start}>Try again</button>
  </main>
{:else if phase === 'signedOut'}
  <Login {configured} onDone={start} />
{:else}
  <div class="announce">MetaService · control panel</div>
  <div class="shell">
    <Sidebar active={page} {username} onSignOut={leave} />
    <main class="main">
      {#if !loaded}
        <div class="phead"><h1>Loading…</h1></div>
      {:else}
      {#if page === 'machines' && detailId}
        <MachineDetail machine={machines.find((machine) => machine.id === detailId)} {commands} {now} pinned={bundles?.pinned} onCreate={startCreate} onRemove={(machine) => (removing = machine)} onInstall={install} onOpenChat={openChat} onAct={act} onDelete={(machine, workload) => (deleting = { machine, workload })} />
      {:else if page === 'machines'}
        <Machines {machines} {now} pinned={bundles?.pinned} {banner} showScan={route === '/machines/find'} onRemove={(machine) => (removing = machine)} onAdd={() => (adding = true)} />
      {:else if page === 'usage'}
        <TokenLedger {brain} />
      {:else if page === 'health'}
        <Health {machines} {commands} {now} />
      {:else if page === 'settings'}
        <Settings {brain} {bundles} onTest={testProvider} onPin={pin} onRollback={rollback} />
      {:else}
        <Overview {machines} {brain} {bundles} />
      {/if}
      {/if}
    </main>
  </div>
  <AddMachine open={adding} onClose={() => (adding = false)} onInstalled={refresh} />
  <ChatLink link={openLink} onClose={() => (openLink = null)} />
  <NewWorkload open={creating} {machines} only={creatingOn} onClose={() => (creating = false)} onCreated={refresh} />
  <ConfirmDelete target={deleting} busy={deleteBusy} failure={deleteFailure} onCancel={() => { deleting = null; deleteFailure = '' }} onConfirm={confirmDelete} />
  <ConfirmRemove machine={removing} busy={removeBusy} failure={removeFailure} onCancel={() => { removing = null; removeFailure = '' }} onConfirm={confirmRemove} />
{/if}

<style>
  .center { min-height: 100svh; display: grid; place-content: center; justify-items: center; gap: 12px; text-align: center; }
</style>
