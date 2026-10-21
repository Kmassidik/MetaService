<script lang="ts">
  // Step 4 while and after the install: a ring, a plain checklist of the install steps, the time, and how it ended (stopped with the reason, or done with the machine online).
  import ProgressRing from './ProgressRing.svelte'
  import StatusMark from './StatusMark.svelte'
  import type { MarkKind } from './StatusMark.svelte'
  import { formatElapsed, installProgress, installTitle, stepWord } from '../../lib/installView.ts'
  import { machineHref } from '../../lib/routes.ts'
  import type { InstallJob, StepState } from '../../lib/types.ts'

  const TICK_MS = 1000
  const MARK_OF: Record<StepState, MarkKind> = { pending: 'waiting', running: 'running', done: 'ready', failed: 'blocking' }

  interface Props {
    job: InstallJob
    where: string
    startedAt: number
    onClose: () => void
    onRetry: () => void
  }

  let { job, where, startedAt, onClose, onRetry }: Props = $props()
  let now = $state(Date.now())
  const progress = $derived(installProgress(job))
  const elapsed = $derived(formatElapsed(now - startedAt))
  const tone = $derived(job.state === 'failed' ? 'blocking' : 'ready')
  const timeText = $derived({ running: `time so far ${elapsed}`, failed: `stopped after ${elapsed}`, done: `All ${progress.total} steps done in ${elapsed}.` }[job.state])

  $effect(() => {
    now = Date.now()
    if (job.state !== 'running') return
    const timer = setInterval(() => (now = Date.now()), TICK_MS)
    return () => clearInterval(timer)
  })
</script>

<div class="top">
  <ProgressRing done={progress.done} total={progress.total} alt="{progress.done} of {progress.total} install steps done" {tone} />
  <div>
    <h2>{installTitle(job)}</h2>
    <p class="time" class:calm={job.state === 'done'}>{timeText}</p>
  </div>
</div>

{#if job.state === 'failed'}
  <div class="problem" role="alert"><StatusMark kind="blocking" /><span>{job.error}</span></div>
{/if}
{#if job.state === 'done' && job.warning}
  <p class="warn" role="status">Installed, but you can't create VMs on {job.name} yet. {job.warning}</p>
{/if}

{#snippet steps()}
  <ol class="list" aria-label="Install steps">
    {#each job.steps as step, index (step.id)}
      <li data-state={step.state}>
        <StatusMark kind={MARK_OF[step.state]} word={stepWord(step.state)} />
        <div><span class="lbl">{index + 1}. {step.label}</span>{#if step.detail}<span class="det">{step.detail}</span>{/if}</div>
      </li>
    {/each}
  </ol>
{/snippet}

{#if job.state === 'done'}
  <section class="card">
    <h4>Where it is</h4>
    <div class="where"><StatusMark kind="ready" /><div><span class="lbl">{job.name}</span><span class="det">Online · {where}</span></div></div>
  </section>
  <details class="all"><summary>Show the {progress.total} steps</summary>{@render steps()}</details>
{:else}
  <div class="card list-card">{@render steps()}</div>
{/if}

<div class="foot">
  {#if job.state === 'failed'}
    <button class="btn line" type="button" onclick={onClose}>Close</button>
    <button class="btn green" type="button" onclick={onRetry}>Try again</button>
  {:else if job.state === 'done'}
    <a class="btn line open" href={machineHref(job.name)} onclick={onClose}>Open {job.name}</a>
    <button class="btn green" type="button" onclick={onClose}>Done</button>
  {:else}
    <button class="btn line" type="button" disabled>Close</button>
  {/if}
</div>

<style>
  .top { display: flex; gap: 16px; align-items: center; }
  h2 { margin: 0; font-size: 18px; line-height: 1.25; }
  .time { margin: 2px 0 0; font-family: var(--mono); font-size: 13px; color: var(--m70); }
  .time.calm { font-family: var(--sans); }
  .problem { display: flex; gap: 10px; padding: 10px 12px; border: 1px solid var(--gray); border-left: 4px solid var(--danger); background: var(--gray2); font-weight: 600; overflow-wrap: anywhere; }
  .warn { margin: 0; padding: 10px 12px; background: var(--warn-bg); color: var(--warn); border: 1px solid var(--warn); font-size: 13px; }
  .card { padding: 6px 14px; border: 1px solid var(--gray); background: var(--gray2); }
  h4 { margin: 4px 0; font-family: var(--mono); font-size: 12px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--m70); }
  .list { list-style: none; margin: 0; padding: 0; }
  .list li { display: flex; gap: 12px; align-items: center; padding: 6px 0; }
  .list li + li { border-top: 1px solid var(--gray); }
  .list li[data-state='pending'] { color: var(--m70); }
  .list li div { min-width: 0; overflow-wrap: anywhere; }
  .lbl { display: block; font-weight: 600; }
  .list li[data-state='pending'] .lbl { font-weight: 400; }
  .det { display: block; font-size: 12px; color: var(--m70); }
  .where { display: flex; gap: 12px; align-items: flex-start; padding: 6px 0 8px; }
  .all { font-size: 13px; }
  .all summary { padding: 4px 0; color: var(--m70); text-decoration: underline; cursor: pointer; }
  .all summary:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }
  .foot { display: flex; flex-wrap: wrap; gap: 10px; justify-content: flex-end; }
  .open { text-decoration: none; display: inline-flex; align-items: center; border-color: var(--black); }
  .btn.line { border-color: var(--black); }
  @media (max-width: 520px) { .foot .btn { flex: 1 1 100%; justify-content: center; } }
</style>
