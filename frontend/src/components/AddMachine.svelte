<script>
  // Add machine: install MetaService on a computer so it can create VMs. Today that is this computer; another computer by IP comes next.
  import Dialog from './Dialog.svelte'
  import { ApiError, installDefaults, installProgress, startInstall } from '../lib/api.js'
  import { nameProblem } from '../lib/format.js'

  let { open, onClose, onInstalled } = $props()
  let defaults = $state(null)
  let name = $state('')
  let chat = $state(true)
  let ramReserveMb = $state(0)
  let diskReserveGb = $state(0)
  let busy = $state(false)
  let failure = $state('')
  let job = $state(null)
  let timer = null
  const problem = $derived(name ? nameProblem(name) : null)
  const canInstall = $derived(defaults?.agent_ready === true && !problem && Boolean(name) && !busy)
  const STATE_MARK = { pending: '·', running: '…', done: '✓', failed: '✗' }

  $effect(() => {
    if (open) load()
    else stopPolling()
  })

  async function load() {
    job = null
    failure = ''
    busy = false
    try {
      defaults = await installDefaults()
      name = defaults.name
      chat = defaults.chat_available
      ramReserveMb = defaults.ram_reserve_mb
      diskReserveGb = defaults.disk_reserve_gb
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    }
  }

  async function submit(event) {
    event.preventDefault()
    if (!canInstall) return
    busy = true
    failure = ''
    try {
      const started = await startInstall({ target: 'this', name, chat, ram_reserve_mb: Number(ramReserveMb), disk_reserve_gb: Number(diskReserveGb) })
      job = await installProgress(started.id)
      poll(started.id)
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
      busy = false
    }
  }

  function poll(id) {
    stopPolling()
    timer = setInterval(async () => {
      try {
        job = await installProgress(id)
        if (job.state === 'running') return
        stopPolling()
        busy = false
        if (job.state === 'done') onInstalled()
      } catch {
        stopPolling()
        busy = false
        failure = 'Lost contact with the control panel.'
      }
    }, 1000)
  }

  function stopPolling() {
    if (timer) clearInterval(timer)
    timer = null
  }
</script>

<Dialog {open} title="Add a machine" {onClose}>
  {#if job}
    <p>Installing <strong>{job.name}</strong>…</p>
    <ol class="steps" aria-label="Install steps">
      {#each job.steps as step (step.id)}
        <li class={step.state}><span class="mark" aria-hidden="true">{STATE_MARK[step.state]}</span><span>{step.label}{#if step.detail}<small>{step.detail}</small>{/if}</span></li>
      {/each}
    </ol>
    {#if job.state === 'failed'}<p class="bad" role="alert">{job.error}</p>{/if}
    {#if job.state === 'done' && !job.warning}<p class="good" role="status">Done. {job.name} is ready: you can create VMs on it.</p>{/if}
    {#if job.state === 'done' && job.warning}<p class="warn" role="status">Installed, but you can't create VMs on {job.name} yet. {job.warning}</p>{/if}
    <div class="row">
      <button class="btn green" type="button" disabled={job.state === 'running'} onclick={onClose}>{job.state === 'failed' ? 'Close' : 'Done'}</button>
    </div>
  {:else}
    <form onsubmit={submit} novalidate>
      <p class="muted">This installs MetaService on <strong>this computer</strong>, so it can create VMs. Adding another computer by its IP comes next.</p>
      <label for="machine-name">Name</label>
      <input id="machine-name" bind:value={name} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" aria-invalid={problem ? 'true' : 'false'} />
      <p class="hint {problem ? 'bad' : 'muted'}">{problem ?? 'Lowercase letters, numbers and dashes. This is how the machine appears here.'}</p>
      <label class="check"><input type="checkbox" bind:checked={chat} disabled={!defaults?.chat_available} /> Install the chat on this machine</label>
      <p class="hint muted">{defaults && !defaults.chat_available ? 'There is no chat bundle on the control panel yet, so the chat cannot be installed.' : 'Leave it off and no chat is installed.'}</p>
      <div class="grid">
        <label>Keep free for the system: memory (MB) <input type="number" min="0" step="256" bind:value={ramReserveMb} /></label>
        <label>Keep free for the system: disk (GB) <input type="number" min="0" step="1" bind:value={diskReserveGb} /></label>
      </div>
      <p class="hint muted">Recommended values are filled in. MetaService will not use this much of the computer for VMs.</p>
      {#if defaults && !defaults.agent_ready}<p class="bad" role="alert">The MetaService program for this computer is not built yet. Start the control panel with scripts/run-control-plane.sh, which builds it.</p>{/if}
      {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
      <div class="row">
        <button class="btn line" type="button" onclick={onClose}>Cancel</button>
        <button class="btn green" type="submit" disabled={!canInstall}>{busy ? 'Starting…' : 'Install'}</button>
      </div>
    </form>
  {/if}
</Dialog>

<style>
  label { display: block; margin-top: 14px; font-family: var(--mono); font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--m50); }
  input:not([type='checkbox']) { display: block; width: 100%; margin-top: 6px; padding: 9px 10px; border: 1px solid var(--gray); font-family: var(--mono); font-size: 14px; }
  input:focus { outline: 2px solid var(--green); outline-offset: -1px; }
  .warn { padding: 10px 12px; background: var(--warnbg); color: var(--warn); border: 1px solid var(--warn); font-size: 13px; }
  .steps { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  .steps li { display: flex; gap: 10px; align-items: baseline; font-size: 13px; }
  .steps li.pending { color: var(--m40); }
  .steps li.failed { color: var(--red, #c0392b); }
  .steps li.done .mark { color: var(--run); font-weight: 700; }
  .steps small { display: block; font-family: var(--mono); font-size: 11px; color: var(--m50); }
  .mark { width: 14px; font-family: var(--mono); }
  .good { color: var(--run); }
  .check { display: flex; gap: 8px; align-items: center; margin-top: 16px; text-transform: none; letter-spacing: 0; font-family: var(--sans); font-size: 14px; color: var(--black); }
  .check input { width: auto; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 8px; }
  .row { display: flex; justify-content: flex-end; gap: 10px; margin-top: 16px; }
  .bad { color: #d92d20; }
  .hint { font-size: 12px; margin-top: 4px; }
</style>
