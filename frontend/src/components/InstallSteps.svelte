<script lang="ts">
  // The steps of an install, shown as they happen (this computer in Add machine, another computer in Connect), with how it ended.
  import type { InstallJob, StepState } from '../lib/types.ts'

  let { job, doneText }: { job: InstallJob; doneText: string } = $props()
  const STATE_MARK: Record<StepState, string> = { pending: '·', running: '…', done: '✓', failed: '✗' }
</script>

<p>Installing <strong>{job.name}</strong>…</p>
<ol class="steps" aria-label="Install steps">
  {#each job.steps as step (step.id)}
    <li class={step.state}><span class="mark" aria-hidden="true">{STATE_MARK[step.state]}</span><span>{step.label}{#if step.detail}<small>{step.detail}</small>{/if}</span></li>
  {/each}
</ol>
{#if job.state === 'failed'}<p class="bad" role="alert">{job.error}</p>{/if}
{#if job.state === 'done' && !job.warning}<p class="good" role="status">{doneText}</p>{/if}
{#if job.state === 'done' && job.warning}<p class="warn" role="status">Installed, but you can't create VMs on {job.name} yet. {job.warning}</p>{/if}

<style>
  .steps { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  .steps li { display: flex; gap: 10px; align-items: baseline; font-size: 13px; }
  .steps li.pending { color: var(--m40); }
  .steps li.failed { color: #c0392b; }
  .steps li.done .mark { color: var(--run); font-weight: 700; }
  .steps small { display: block; font-family: var(--mono); font-size: 11px; color: var(--m50); }
  .mark { width: 14px; font-family: var(--mono); }
  .good { color: var(--run); }
  .warn { padding: 10px 12px; background: var(--warnbg); color: var(--warn); border: 1px solid var(--warn); font-size: 13px; }
  .bad { color: #d92d20; }
</style>
