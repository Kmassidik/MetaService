<script>
  import { onMount } from 'svelte'
  import { ApiError, authStatus, getSession, listMachines, removeMachine, signOut } from './lib/api.js'
  import { summarize } from './lib/format.js'
  import SignIn from './components/SignIn.svelte'
  import TopBar from './components/TopBar.svelte'
  import Summary from './components/Summary.svelte'
  import MachineList from './components/MachineList.svelte'
  import AddMachine from './components/AddMachine.svelte'
  import ConfirmRemove from './components/ConfirmRemove.svelte'
  import ScanView from './components/ScanView.svelte'

  const REFRESH_MS = 10_000
  const CLOCK_MS = 5_000

  let phase = $state('loading')
  let googleReady = $state(false)
  let operator = $state(null)
  let machines = $state([])
  let now = $state(Date.now())
  let view = $state('machines')
  let banner = $state('')
  let adding = $state(false)
  let removing = $state(null)
  let removeBusy = $state(false)
  let removeFailure = $state('')
  const counts = $derived(summarize(machines))

  async function start() {
    try {
      operator = await getSession()
      if (operator) {
        phase = 'ready'
        await refresh()
        return
      }
      googleReady = (await authStatus()).google === true
      phase = 'signedOut'
    } catch (error) {
      banner = error instanceof ApiError && error.status === 0 ? 'Cannot reach the Root.' : 'Something went wrong.'
      phase = 'error'
    }
  }

  async function refresh() {
    if (phase !== 'ready') return
    try {
      machines = await listMachines()
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

  /** Leave the signed-in view first, then forget the operator, so no screen reads a missing operator. */
  async function restart() {
    phase = 'loading'
    operator = null
    machines = []
    await start()
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
    start()
    const refreshTimer = setInterval(() => !document.hidden && refresh(), REFRESH_MS)
    const clockTimer = setInterval(() => (now = Date.now()), CLOCK_MS)
    const wake = () => !document.hidden && refresh()
    document.addEventListener('visibilitychange', wake)
    return () => {
      clearInterval(refreshTimer)
      clearInterval(clockTimer)
      document.removeEventListener('visibilitychange', wake)
    }
  })
</script>

{#if phase === 'loading'}
  <p class="center muted" role="status">Loading…</p>
{:else if phase === 'error'}
  <main class="center">
    <p role="alert">{banner}</p>
    <button class="btn" type="button" onclick={start}>Try again</button>
  </main>
{:else if phase === 'signedOut'}
  <SignIn {googleReady} />
{:else}
  <div class="page">
    <TopBar email={operator.email} onSignOut={leave} {view} onView={(next) => (view = next)} />
    <main>
      {#if view === 'scan'}
        <ScanView />
      {:else}
        <div class="intro">
          <Summary {counts} />
          <button class="btn primary" type="button" onclick={() => (adding = true)}>Add a machine</button>
        </div>
        {#if banner}<p class="banner" role="status">{banner}</p>{/if}
        <MachineList {machines} {now} onRemove={(machine) => (removing = machine)} onAdd={() => (adding = true)} />
      {/if}
    </main>
  </div>
  <AddMachine open={adding} onClose={() => (adding = false)} onCreated={refresh} />
  <ConfirmRemove machine={removing} busy={removeBusy} failure={removeFailure} onCancel={() => { removing = null; removeFailure = '' }} onConfirm={confirmRemove} />
{/if}

<style>
  .page { max-width: 1240px; margin-inline: auto; padding-bottom: max(32px, env(safe-area-inset-bottom)); }
  main { display: grid; gap: 18px; }
  .intro { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
  .banner { padding: 10px 14px; border-radius: 8px; background: var(--warn-bg); color: var(--warn); }
  .center { min-height: 100svh; display: grid; place-content: center; justify-items: center; gap: 12px; text-align: center; }
</style>
