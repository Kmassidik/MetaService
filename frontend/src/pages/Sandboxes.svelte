<script lang="ts">
  // Sandboxes, live: every machine's microVMs across all teams, with the time each has left, and an operator's kill or pause.
  // The list is asked for again every few seconds, but only while the browser tab is visible.
  import { onMount } from 'svelte'
  import ActionButton from '../components/ActionButton.svelte'
  import ConfirmDialog from '../components/ConfirmDialog.svelte'
  import { listSandboxes, sandboxAction } from '../lib/api.ts'
  import { relativeTime } from '../lib/format.ts'
  import { endsText, killCopy, sandboxStateLabel, sandboxStateTone, shapeText } from '../lib/sandboxPanel.ts'
  import { browserEnvironment, startPolling } from '../lib/statsPoll.ts'
  import type { SandboxLive } from '../lib/types.ts'

  const POLL_MS = 5_000
  const CLOCK_MS = 5_000

  let sandboxes = $state<SandboxLive[]>([])
  let loading = $state(true)
  let failed = $state(false)
  let now = $state(Date.now())
  let killing = $state<SandboxLive | null>(null)
  const killText = $derived(killing ? killCopy(killing) : killCopy({ id: '', template: '', team_name: '' }))

  async function load() {
    try {
      sandboxes = await listSandboxes()
      failed = false
    } catch {
      failed = true
    } finally {
      loading = false
    }
  }

  async function kill() {
    if (!killing) return
    await sandboxAction(killing.id, 'kill')
    await load()
  }

  async function pause(sandbox: SandboxLive) {
    await sandboxAction(sandbox.id, 'pause')
    await load()
  }

  $effect(() => {
    let running = true
    const stop = startPolling(browserEnvironment(), POLL_MS, async () => {
      if (running) await load()
    })
    return () => {
      running = false
      stop()
    }
  })

  onMount(() => {
    const timer = setInterval(() => (now = Date.now()), CLOCK_MS)
    return () => clearInterval(timer)
  })

  const count = $derived(sandboxes.length)
</script>

<div class="phead"><h1>Sandboxes</h1><span class="crumb">Sandboxes › {count} running</span></div>
<p class="op-note">A sandbox is a small Linux machine a program asks for with its key. It ends by itself at its end time; here you can pause one, or kill it at once. Paused sandboxes keep their files and memory, and use no CPU.</p>

{#if failed}<p class="banner" role="status">The list could not be read just now. Showing the last one.</p>{/if}

<div class="tablewrap" role="region" aria-label="Live sandboxes, scroll to view columns">
  <table class="restable stack">
    <thead><tr><th>Sandbox</th><th>Team</th><th>Machine</th><th>State</th><th>Shape</th><th>Ends</th><th>Created</th><th><span class="sr">Actions</span></th></tr></thead>
    <tbody>
      {#each sandboxes as sandbox (sandbox.id)}
        <tr>
          <td data-label="Sandbox"><b class="mono">{sandbox.id}</b><br /><span class="muted">{sandbox.template}</span></td>
          <td data-label="Team">{sandbox.team_name}</td>
          <td data-label="Machine">{sandbox.machine}</td>
          <td data-label="State"><span class="tag" class:run={sandboxStateTone(sandbox.state) === 'run'} class:warn={sandboxStateTone(sandbox.state) === 'warn'} class:act={sandboxStateTone(sandbox.state) === 'act'}>{sandboxStateLabel(sandbox.state)}</span></td>
          <td data-label="Shape" class="mono">{shapeText(sandbox.vcpu, sandbox.ram_mb, sandbox.disk_mb)}</td>
          <td data-label="Ends" class="mono">{endsText(sandbox.end_at, now)}</td>
          <td data-label="Created" class="muted">{relativeTime(sandbox.created_at, now)}</td>
          <td data-label="Actions">
            <div class="acts">
              {#if sandbox.state === 'paused'}
                <span class="muted">Paused</span>
              {:else}
                <ActionButton small label="Pause" busyLabel="Pausing…" doneLabel="Paused" onrun={() => pause(sandbox)} />
              {/if}
              <button class="btn danger sm" type="button" onclick={() => (killing = sandbox)} aria-label="Kill sandbox {sandbox.id}">Kill</button>
            </div>
          </td>
        </tr>
      {:else}
        <tr><td colspan="8">{loading ? 'Reading the list…' : 'No sandboxes are running. A program makes one with its team’s key.'}</td></tr>
      {/each}
    </tbody>
  </table>
</div>

<ConfirmDialog open={killing !== null} {...killText} onconfirm={kill} onClose={() => (killing = null)} />

<style>
  .mono { font-family: var(--mono); font-size: 12px; }
  .acts { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
</style>
