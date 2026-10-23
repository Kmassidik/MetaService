<script lang="ts">
  // The "Software" block of a VM's Overview: the app installed inside it after it started (OpenClaw or Hermes) with its logo, how the install is going, the version when known,
  // and, when it failed, the last lines of the install log as plain text and a Try again button. While it installs, the block asks again every few seconds, one request at a time.
  import ActionButton from '../ActionButton.svelte'
  import RichBadge from '../vms/create/RichBadge.svelte'
  import { getWorkloadApp, retryWorkloadApp } from '../../lib/api.ts'
  import { appLogoName, appTitle, shouldPollApp, shownLog, stateLine, type AppView } from '../../lib/appInstall.ts'
  import { LOGOS } from '../../lib/logos.ts'
  import { APP_POLL_MS } from '../../lib/timeouts.ts'

  interface Props {
    machineId: string
    workloadId: string
  }

  const READ_FAILED = 'The software state could not be read. Trying again…'

  let { machineId, workloadId }: Props = $props()
  let view = $state<AppView | null>(null)
  let readFailed = $state(false)
  /** Every answer that replaces the view counts; a check sent before one of them must not undo it. */
  let version = 0
  const title = $derived(appTitle(view?.app ?? null))
  const logoName = $derived(appLogoName(view?.app ?? null))
  const polling = $derived(shouldPollApp(view))
  const log = $derived(view ? shownLog(view) : [])

  const take = (next: AppView) => {
    version += 1
    view = next
  }

  async function check() {
    const sentAt = version
    try {
      const next = await getWorkloadApp(machineId, workloadId)
      if (sentAt === version) take(next)
      readFailed = false
    } catch {
      readFailed = true
    }
  }

  $effect(() => {
    view = null
    void check()
  })

  $effect(() => {
    if (!polling) return
    let stopped = false
    let timer: ReturnType<typeof setTimeout> | undefined
    const tick = async () => {
      await check()
      if (!stopped) timer = setTimeout(tick, APP_POLL_MS)
    }
    timer = setTimeout(tick, APP_POLL_MS)
    return () => {
      stopped = true
      clearTimeout(timer)
    }
  })

  async function retry() {
    take(await retryWorkloadApp(machineId, workloadId))
  }
</script>

<section class="software" aria-label="Software">
  <p class="lbl">Software</p>
  {#if view === null}
    <p class="hint">{readFailed ? READ_FAILED : 'Reading the software…'}</p>
  {:else}
    <div class="head">
      <RichBadge {title} logo={logoName === null ? undefined : LOGOS[logoName]} />
      <strong class="name">{title}</strong>
      {#if view.version}<span class="mono ver">version {view.version}</span>{/if}
    </div>
    <p class="state" class:bad={view.state === 'failed'} class:ok={view.state === 'ready'} role="status">
      {#if view.state === 'installing'}<span class="btn-spin" aria-hidden="true"></span>{/if}{stateLine(view)}
    </p>
    {#if readFailed}<p class="hint">{READ_FAILED}</p>{/if}
    {#if view.state === 'failed'}
      {#if log.length > 0}<pre class="log" aria-label="The last lines of the install log">{log.join('\n')}</pre>{/if}
      <ActionButton label="Try again" busyLabel="Trying…" doneLabel="Started" variant="line" small onrun={retry} />
    {/if}
  {/if}
</section>

<style>
  .software { display: grid; gap: 10px; margin-top: 24px; padding-top: 20px; border-top: 1px solid var(--surface-2); justify-items: start; }
  .lbl { margin: 0; font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.14em; color: var(--m50); }
  .head { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .name { font-size: 15px; }
  .ver { font-size: 12px; color: var(--m60); }
  .state { margin: 0; font-size: 13px; color: var(--m70); overflow-wrap: anywhere; }
  .state.ok { color: var(--ok); font-weight: 700; }
  .state.bad { color: var(--danger-note-text); }
  .hint { margin: 0; font-size: 12px; color: var(--m60); }
  .log { box-sizing: border-box; width: 100%; max-height: 260px; margin: 0; padding: 8px 10px; overflow: auto; border: 1px solid var(--line); background: var(--surface); font: 12px/1.5 var(--mono); white-space: pre-wrap; overflow-wrap: anywhere; }
</style>
