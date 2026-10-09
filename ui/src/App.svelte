<script>
  import { onMount } from 'svelte'
  import { ApiError, authStatus, brainStatus, bundleOverview, chatLink, installBundle, pinBundle, rollbackBundle, getSession, listCommands, listMachines, removeMachine, signOut, testBrain, workloadAction } from './lib/api.js'
  import { summarize } from './lib/format.js'
  import Login from './components/Login.svelte'
  import Sidebar from './components/Sidebar.svelte'
  import Summary from './components/Summary.svelte'
  import MachineList from './components/MachineList.svelte'
  import AddMachine from './components/AddMachine.svelte'
  import ConfirmRemove from './components/ConfirmRemove.svelte'
  import ScanView from './components/ScanView.svelte'
  import NewWorkload from './components/NewWorkload.svelte'
  import ConfirmDelete from './components/ConfirmDelete.svelte'
  import Activity from './components/Activity.svelte'
  import Brain from './components/Brain.svelte'
  import Bundles from './components/Bundles.svelte'
  import ChatLink from './components/ChatLink.svelte'

  const REFRESH_MS = 10_000
  const CLOCK_MS = 5_000

  let phase = $state('loading')
  let username = $state('')
  let configured = $state(true)
  let machines = $state([])
  let now = $state(Date.now())
  let route = $state(location.hash.replace(/^#/, '') || '/')
  const page = $derived(({ '/scan': 'scan', '/bundle': 'bundle', '/ai': 'ai', '/activity': 'activity' })[route] ?? 'machines')
  let banner = $state('')
  let adding = $state(false)
  let commands = $state([])
  let bundles = $state(null)
  let brain = $state(null)
  let openLink = $state(null)
  let creating = $state(false)
  let deleting = $state(null)
  let deleteBusy = $state(false)
  let deleteFailure = $state('')
  let removing = $state(null)
  let removeBusy = $state(false)
  let removeFailure = $state('')
  const counts = $derived(summarize(machines))

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
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) {
        await restart()
        return
      }
      banner = 'Cannot reach the Root. Showing the last data.'
    }
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
      {#if page === 'scan'}
        <div class="phead"><h1>Find machines</h1><span class="crumb"><a href="#/">Machines</a> › Scan</span></div>
        <div class="body"><ScanView /></div>
      {:else if page === 'bundle'}
        <div class="phead"><h1>Chat bundle</h1></div>
        <div class="body"><Bundles overview={bundles} onPin={pin} onRollback={rollback} /></div>
      {:else if page === 'ai'}
        <div class="phead"><h1>AI provider</h1></div>
        <div class="body"><Brain status={brain} onTest={testProvider} /></div>
      {:else if page === 'activity'}
        <div class="phead"><h1>Activity</h1></div>
        <div class="body"><Activity {commands} {now} /></div>
      {:else}
        <div class="phead">
          <h1>Machines</h1><span class="crumb">{counts.online} of {counts.machines} online</span>
          <div class="sp">
            <button class="btn line sm" type="button" onclick={() => (adding = true)}>Add a machine</button>
            <button class="btn green sm" type="button" onclick={() => (creating = true)}>＋ New workload</button>
          </div>
        </div>
        <Summary {counts} />
        {#if banner}<p class="banner" role="status">{banner}</p>{/if}
        <MachineList {machines} {now} pinned={bundles?.pinned} onInstall={install} onOpenChat={openChat} onRemove={(machine) => (removing = machine)} onAdd={() => (adding = true)} onAct={act} onDelete={(machine, workload) => (deleting = { machine, workload })} />
      {/if}
    </main>
  </div>
  <AddMachine open={adding} onClose={() => (adding = false)} onCreated={refresh} />
  <ChatLink link={openLink} onClose={() => (openLink = null)} />
  <NewWorkload open={creating} {machines} onClose={() => (creating = false)} onCreated={refresh} />
  <ConfirmDelete target={deleting} busy={deleteBusy} failure={deleteFailure} onCancel={() => { deleting = null; deleteFailure = '' }} onConfirm={confirmDelete} />
  <ConfirmRemove machine={removing} busy={removeBusy} failure={removeFailure} onCancel={() => { removing = null; removeFailure = '' }} onConfirm={confirmRemove} />
{/if}

<style>
  .center { min-height: 100svh; display: grid; place-content: center; justify-items: center; gap: 12px; text-align: center; }
</style>
