<script lang="ts">
  // The last step of adding another computer: what will change, the choices, then the install with its steps as they happen. Nothing is changed before Install.
  import { onDestroy, onMount, untrack } from 'svelte'
  import AddPlan from './connect/AddPlan.svelte'
  import InstallProgress from './connect/InstallProgress.svelte'
  import { ApiError, remoteInstall, remoteInstallProgress, remotePlan } from '../lib/api.ts'
  import { addBody, advancedProblem, defaultAddChoices, nameWrong, planBody } from '../lib/remote.ts'
  import type { ConnectForm, InstallJob, PlanPreview, VerifyResult } from '../lib/types.ts'

  const POLL_MS = 1000

  let { form, result, onBack, onClose, onInstalled }: { form: ConnectForm; result: VerifyResult; onBack: () => void; onClose: () => void; onInstalled: () => void } = $props()
  let choices = $state(untrack(() => defaultAddChoices(result.facts.computer_name || form.host)))
  let password = $state('')
  let preview: PlanPreview | null = $state(null)
  let job: InstallJob | null = $state(null)
  let busy = $state(false)
  let failure = $state('')
  let startedAt = $state(0)
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
      startedAt = Date.now()
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

  /** After a failed install: back to the plan, so the same choices can be tried again. */
  function retry() {
    job = null
    busy = false
    failure = ''
    loadPlan()
  }

  function stop() {
    if (timer) clearInterval(timer)
    timer = null
  }

  onMount(loadPlan)
  onDestroy(stop)
</script>

{#if job}
  <InstallProgress {job} where="{result.facts.user}@{form.host}" {startedAt} {onClose} onRetry={retry} />
{:else}
  <AddPlan {form} {result} bind:choices bind:password {preview} {failure} {busy} {ready} {nameProblem} {advancedWrong} onChange={loadPlan} onSubmit={install} {onBack} />
{/if}
