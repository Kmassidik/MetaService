<script lang="ts">
  // The last steps of adding another computer: "What will change" in plain words, the choices, then the install with its steps as they happen. Nothing is changed before Install.
  import { onDestroy, onMount, untrack } from 'svelte'
  import InstallSteps from './InstallSteps.svelte'
  import SecretField from './SecretField.svelte'
  import { ApiError, remoteInstall, remoteInstallProgress, remotePlan } from '../lib/api.ts'
  import { addBody, advancedProblem, defaultAddChoices, nameWrong, planBody } from '../lib/remote.ts'
  import type { ConnectForm, InstallJob, PlanPreview, VerifyResult } from '../lib/types.ts'

  const POLL_MS = 1000

  let { form, result, onBack, onClose, onInstalled }: { form: ConnectForm; result: VerifyResult; onBack: () => void; onClose: () => void; onInstalled: () => void } = $props()
  let choices = $state(untrack(() => defaultAddChoices(form.host)))
  let password = $state('')
  let preview: PlanPreview | null = $state(null)
  let job: InstallJob | null = $state(null)
  let busy = $state(false)
  let failure = $state('')
  let timer: ReturnType<typeof setInterval> | null = null
  const nameProblem = $derived(nameWrong(choices.name))
  const advancedWrong = $derived(advancedProblem(choices))
  const passwordMissing = $derived(!form.useKey && password === '')
  const ready = $derived(!busy && preview !== null && nameProblem === null && advancedWrong === null && !passwordMissing)

  async function loadPlan() {
    if (nameProblem || advancedWrong) return
    failure = ''
    try {
      preview = await remotePlan(planBody(form, result, choices))
    } catch (error) {
      preview = null
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    }
  }

  async function install(event: SubmitEvent) {
    event.preventDefault()
    if (!ready) return
    busy = true
    failure = ''
    try {
      const started = await remoteInstall(addBody({ ...form, password }, result.fingerprint, choices))
      job = await remoteInstallProgress(started.id)
      poll(started.id)
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
      busy = false
    } finally {
      password = ''
    }
  }

  function poll(id: string) {
    stop()
    timer = setInterval(async () => {
      try {
        job = await remoteInstallProgress(id)
        if (job.state === 'running') return
        stop()
        busy = false
        if (job.state === 'done') onInstalled()
      } catch {
        stop()
        busy = false
        failure = 'Lost contact with the control panel.'
      }
    }, POLL_MS)
  }

  function stop() {
    if (timer) clearInterval(timer)
    timer = null
  }

  onMount(loadPlan)
  onDestroy(stop)
</script>

{#if job}
  <InstallSteps {job} doneText="Done. {job.name} is added: it shows in Machines." />
  <div class="row">
    <button class="btn green" type="button" disabled={job.state === 'running'} onclick={onClose}>{job.state === 'failed' ? 'Close' : 'Done'}</button>
  </div>
{:else}
  <form onsubmit={install} novalidate>
    <h3>What will change on {result.facts.user}@{form.host}</h3>
    {#if preview}
      <ol class="plan" aria-label="What will change">
        {#each preview.steps as step (step.id)}
          <li><strong>{step.label}</strong><ul>{#each step.changes as change (change)}<li>{change}</li>{/each}</ul></li>
        {/each}
      </ol>
      {#each preview.notes as note (note)}<p class="note">{note}</p>{/each}
    {:else if !failure}
      <p class="muted">Working out what will change…</p>
    {/if}

    <label for="remote-name">Machine name</label>
    <input id="remote-name" bind:value={choices.name} onchange={loadPlan} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" aria-invalid={nameProblem ? 'true' : 'false'} />
    <p class="hint {nameProblem ? 'bad' : 'muted'}">{nameProblem ?? 'This is how the machine appears in the dashboard.'}</p>
    <label class="check"><input type="checkbox" bind:checked={choices.installKey} onchange={loadPlan} /> Allow the parent's tunnel (adds one restricted line to authorized_keys)</label>
    {#if !choices.installKey}<p class="hint muted">Without it the machine can report in, but the parent cannot send it commands yet.</p>{/if}
    <details class="advanced">
      <summary>Advanced: where it goes</summary>
      <label for="remote-box">Box folder (empty: metaservice-box in that user's home)</label>
      <input id="remote-box" bind:value={choices.box} onchange={loadPlan} autocomplete="off" spellcheck="false" placeholder="/home/build/metaservice-box" />
      <label for="remote-ssh">SSH folder for the tunnel key (empty: .ssh in that user's home)</label>
      <input id="remote-ssh" bind:value={choices.sshDir} onchange={loadPlan} autocomplete="off" spellcheck="false" placeholder="/home/build/.ssh" />
      <label for="remote-port">Port of the program on that computer (empty: 9101)</label>
      <input id="remote-port" bind:value={choices.agentPort} onchange={loadPlan} inputmode="numeric" autocomplete="off" placeholder="9101" />
      {#if advancedWrong}<p class="hint bad" role="alert">{advancedWrong}</p>{/if}
    </details>
    {#if !form.useKey}<SecretField label="Password (typed again, used once)" name="password" bind:value={password} />{/if}

    {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
    <div class="row">
      <button class="btn line" type="button" onclick={onBack}>Back</button>
      <button class="btn green" type="submit" disabled={!ready}>{busy ? 'Starting…' : 'Install'}</button>
    </div>
  </form>
{/if}

<style>
  h3 { margin: 0 0 8px; font-size: 14px; }
  .plan { margin: 0; padding-left: 20px; display: grid; gap: 10px; font-size: 13px; }
  .plan ul { margin: 4px 0 0; padding-left: 18px; display: grid; gap: 3px; color: var(--m50); }
  .note { font-size: 12px; margin: 8px 0 0; color: var(--m50); }
  label { display: block; margin-top: 14px; font-family: var(--mono); font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--m50); }
  input:not([type='checkbox']) { display: block; width: 100%; margin-top: 6px; padding: 9px 10px; border: 1px solid var(--gray); background: var(--white); font-family: var(--mono); font-size: 14px; }
  input:focus { outline: 2px solid var(--green); outline-offset: -1px; }
  .check { display: flex; gap: 8px; align-items: center; text-transform: none; letter-spacing: 0; font-family: var(--sans); font-size: 14px; color: var(--black); margin-top: 12px; }
  .check input { width: auto; margin: 0; }
  .advanced { margin-top: 14px; font-size: 13px; }
  .advanced summary { cursor: pointer; font-family: var(--mono); font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--m50); }
  .row { display: flex; justify-content: flex-end; gap: 10px; margin-top: 16px; }
  .hint { font-size: 12px; margin-top: 6px; }
  .bad { color: #d92d20; }
</style>
