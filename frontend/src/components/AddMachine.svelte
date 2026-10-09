<script>
  // Add machine: install MetaService on a computer so it can create VMs. Today that is this computer; another computer by IP comes next.
  import Dialog from './Dialog.svelte'
  import { ApiError, installDefaults, installProgress, latestScan, startInstall } from '../lib/api.js'
  import { PROFILES, formatGb, formatMb, installBody, installPreview, nameProblem, profileLabel } from '../lib/format.js'

  let { open, onClose, onInstalled } = $props()
  let defaults = $state(null)
  let form = $state(emptyForm())
  let busy = $state(false)
  let failure = $state('')
  let job = $state(null)
  let found = $state([])
  let chosen = $state('this')
  let timer = null
  const problem = $derived(form.name ? nameProblem(form.name) : null)
  const canInstall = $derived(defaults?.agent_ready === true && !problem && Boolean(form.name) && !busy)
  const preview = $derived(installPreview(form))
  const STATE_MARK = { pending: '·', running: '…', done: '✓', failed: '✗' }

  function emptyForm() {
    return { name: '', profile: 'custom', labels: '', notes: '', chat: false, ramReserveMb: '', diskReserveGb: '', ramAllowanceMb: '', diskAllowanceGb: '', allowGpu: true,
      vmCpu: '', vmRamMb: '', vmDiskGb: '', vmImage: '', vmMaxRunning: '', subdomain: '', publicChat: false, aiModel: '' }
  }

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
      found = ((await latestScan().catch(() => null))?.results ?? []).filter((device) => !device.machine).slice(0, 8)
      form = { ...emptyForm(), name: defaults.name, profile: defaults.profile, chat: defaults.chat_available, ramReserveMb: defaults.ram_reserve_mb, diskReserveGb: defaults.disk_reserve_gb,
        vmCpu: defaults.vm_cpu, vmRamMb: defaults.vm_ram_mb, vmDiskGb: defaults.vm_disk_gb }
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
      const started = await startInstall(installBody(form))
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

<Dialog {open} title="Add a machine" {onClose} wide>
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
      <label for="machine-computer">Available computers</label>
      <select id="machine-computer" class="computer" bind:value={chosen}>
        {#if defaults?.computer}
          <option value="this">{defaults.computer.name} · this computer · {profileLabel(defaults.profile)} · {defaults.computer.cpu_cores} cores · {formatMb(defaults.computer.ram_mb)} memory · {formatGb(defaults.computer.disk_gb)} disk</option>
        {:else}<option value="this">Looking at this computer…</option>{/if}
        {#each found as device (device.id)}
          <option value={device.id} disabled>{device.hostname ?? device.ip} · {device.ip} · found on your network · SSH install coming next</option>
        {/each}
      </select>
      <p class="hint muted">Other computers on your network show here after you run "Find machines".</p>

      <div class="two">
        <div class="left">
          <fieldset>
            <legend>Who it is</legend>
            <label for="machine-name">Name</label>
            <input id="machine-name" bind:value={form.name} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" aria-invalid={problem ? 'true' : 'false'} />
            <p class="hint {problem ? 'bad' : 'muted'}">{problem ?? 'Lowercase letters, numbers and dashes. This is how the machine appears here.'}</p>
            <label for="machine-profile">Profile (detected from the computer)</label>
            <select id="machine-profile" bind:value={form.profile}>{#each PROFILES as profile (profile.id)}<option value={profile.id}>{profile.label}</option>{/each}</select>
            <label for="machine-labels">Labels (separated by commas)</label>
            <input id="machine-labels" bind:value={form.labels} autocomplete="off" placeholder="office, gpu" />
            <label for="machine-notes">Notes</label>
            <input id="machine-notes" bind:value={form.notes} autocomplete="off" maxlength="300" />
          </fieldset>

          <fieldset>
            <legend>What to install</legend>
            <label class="check"><input type="checkbox" bind:checked={form.chat} disabled={!defaults?.chat_available} /> Install Ruvio (the chat) on this machine</label>
            <p class="hint muted">{defaults && !defaults.chat_available ? 'There is no chat bundle on the control panel yet, so Ruvio cannot be installed.' : 'Leave it off and Ruvio is not installed.'}</p>
          </fieldset>

          <fieldset>
            <legend>Limits</legend>
            <div class="pair">
              <label>Keep free: memory (MB) <input type="number" min="0" step="256" bind:value={form.ramReserveMb} /></label>
              <label>Keep free: disk (GB) <input type="number" min="0" step="1" bind:value={form.diskReserveGb} /></label>
              <label>Most it may use: memory (MB) <input type="number" min="512" step="256" bind:value={form.ramAllowanceMb} placeholder="no limit" /></label>
              <label>Most it may use: disk (GB) <input type="number" min="1" step="1" bind:value={form.diskAllowanceGb} placeholder="no limit" /></label>
            </div>
            <label class="check"><input type="checkbox" bind:checked={form.allowGpu} /> Offer the GPU to VMs and containers (only matters if it has one)</label>
          </fieldset>
        </div>

        <div class="right">
          <fieldset>
            <legend>What a new VM gets</legend>
            <div class="pair">
              <label>CPU <input type="number" min="1" max="64" bind:value={form.vmCpu} /></label>
              <label>Memory (MB) <input type="number" min="512" step="256" bind:value={form.vmRamMb} /></label>
              <label>Disk (GB) <input type="number" min="1" bind:value={form.vmDiskGb} /></label>
              <label>Most VMs at once <input type="number" min="1" bind:value={form.vmMaxRunning} placeholder="no limit" /></label>
            </div>
            <label for="machine-image">Image</label>
            <input id="machine-image" bind:value={form.vmImage} autocomplete="off" placeholder="the machine's own default" />
          </fieldset>

          <fieldset>
            <legend>Name on the internet</legend>
            <label for="machine-subdomain">Subdomain</label>
            <input id="machine-subdomain" bind:value={form.subdomain} autocomplete="off" autocapitalize="off" placeholder="mac1" />
            <label class="check"><input type="checkbox" bind:checked={form.publicChat} /> Make its chat reachable from the internet</label>
            <p class="hint muted">The domain and the Cloudflare settings stay on the control panel. These take effect when the control panel's domain is connected.</p>
          </fieldset>

          <fieldset>
            <legend>AI for Ruvio</legend>
            <label for="machine-model">Model</label>
            <input id="machine-model" bind:value={form.aiModel} autocomplete="off" placeholder={defaults?.ai_model ?? 'the control panel\'s model'} />
            <p class="hint muted">Empty means the control panel's model. The AI key never leaves the control panel.</p>
          </fieldset>
        </div>
      </div>

      <div class="review" aria-label="What will change">
        <strong>What will change</strong>
        <ul>{#each preview as line}<li>{line}</li>{/each}</ul>
      </div>
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
  .two { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 28px; }
  .computer { font-size: 13px; }
  @media (max-width: 820px) { .two { grid-template-columns: 1fr; gap: 0; } }
  label { display: block; margin-top: 14px; font-family: var(--mono); font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--m50); }
  input:not([type='checkbox']):not([type='radio']), select { display: block; width: 100%; margin-top: 6px; padding: 9px 10px; border: 1px solid var(--gray); background: var(--white); font-family: var(--mono); font-size: 14px; }
  input:focus, select:focus { outline: 2px solid var(--green); outline-offset: -1px; }
  fieldset { border: 0; border-top: 1px solid var(--gray); margin: 18px 0 0; padding: 0; }
  legend { padding: 0 8px 0 0; margin-top: -9px; background: var(--white); font-family: var(--mono); font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--m40); }
  .check { display: flex; gap: 8px; align-items: center; text-transform: none; letter-spacing: 0; font-family: var(--sans); font-size: 14px; color: var(--black); margin-top: 12px; }
  .check input { width: auto; margin: 0; }
  .pair { display: grid; grid-template-columns: 1fr 1fr; gap: 0 12px; }
  .review { margin-top: 18px; padding: 12px 14px; background: var(--gray2); border: 1px solid var(--gray); font-size: 13px; }
  .review ul { margin: 6px 0 0; padding-left: 18px; display: grid; gap: 4px; }
  .steps { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  .steps li { display: flex; gap: 10px; align-items: baseline; font-size: 13px; }
  .steps li.pending { color: var(--m40); }
  .steps li.failed { color: #c0392b; }
  .steps li.done .mark { color: var(--run); font-weight: 700; }
  .steps small { display: block; font-family: var(--mono); font-size: 11px; color: var(--m50); }
  .mark { width: 14px; font-family: var(--mono); }
  .good { color: var(--run); }
  .warn { padding: 10px 12px; background: var(--warnbg); color: var(--warn); border: 1px solid var(--warn); font-size: 13px; }
  .row { display: flex; justify-content: flex-end; gap: 10px; margin-top: 16px; }
  .bad { color: #d92d20; }
  .hint { font-size: 12px; margin-top: 4px; }
</style>
