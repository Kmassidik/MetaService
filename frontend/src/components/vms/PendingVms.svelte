<script lang="ts">
  // The VMs that are being made, or could not be made. One card each: the name, the machine, three steps with the current one marked, and for a failed one the reason and a way to dismiss it.
  import { dismissOrder } from '../../lib/pendingStore.svelte.ts'
  import { stageSteps, stageText, type PendingVm } from '../../lib/pendingVms.ts'
  import { machineHref } from '../../lib/routes.ts'

  const STEP_NAMES = ['Waiting for the machine', 'Creating', 'Starting']

  /** `compact` is one slim row per VM (no step list): the machine page keeps it above its tabs without pushing them down. */
  let { pending, showMachine = true, compact = false }: { pending: PendingVm[]; showMachine?: boolean; compact?: boolean } = $props()
</script>

{#if pending.length > 0}
  <ul class="pending" class:compact aria-label="VMs being made">
    {#each pending as entry (entry.id)}
      <li class:failed={entry.stage === 'failed'} data-pending={entry.name}>
        <div class="head">
          <b class="name">{entry.name}</b>
          {#if showMachine}<span class="on">on <a href={machineHref(entry.machine)}>{entry.machineName}</a></span>{/if}
          <span class="tag {entry.stage === 'failed' ? 'bad' : 'prog'}">{entry.stage === 'failed' ? stageText('failed') : `${stageText(entry.stage)}…`}</span>
        </div>
        {#if entry.stage === 'failed'}
          <p class="reason" role="alert">{entry.reason}</p>
          <button class="btn line sm" type="button" onclick={() => dismissOrder(entry.id)}>Dismiss</button>
        {:else if !compact}
          <ol class="steps" aria-label="Progress">
            {#each stageSteps(entry.stage) as step, index (index)}
              <li class={step} aria-current={step === 'now' ? 'step' : undefined}><i aria-hidden="true"></i>{STEP_NAMES[index]}</li>
            {/each}
          </ol>
        {/if}
        {#if entry.note && entry.stage !== 'failed'}<p class="note muted" role="status">{entry.note}</p>{/if}
      </li>
    {/each}
  </ul>
{/if}

<style>
  .pending { list-style: none; margin: 0; padding: 16px 28px 0; display: grid; gap: 10px; }
  .pending > li { border: 1px solid var(--warn); border-left-width: 4px; background: var(--warnbg); padding: 12px 14px; display: grid; gap: 8px; }
  .pending > li.failed { border-color: #e0b4b4; border-left-color: #c0392b; background: #fff5f4; }
  .pending.compact { padding-top: 8px; gap: 6px; }
  .compact > li { padding: 6px 12px; gap: 4px; }
  .head { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .name { overflow-wrap: anywhere; }
  .on { color: var(--m60); font-size: 13px; }
  .on a { text-decoration: underline; }
  .tag.bad { color: #c0392b; border-color: #c0392b; }
  .reason { margin: 0; color: #98281f; overflow-wrap: anywhere; }
  .note { margin: 0; font-size: 13px; }
  .steps { list-style: none; margin: 0; padding: 0; display: flex; gap: 6px; flex-wrap: wrap; }
  .steps li { display: flex; align-items: center; gap: 6px; flex: 1 1 140px; font-family: var(--mono); font-size: 11px; color: var(--m50); padding-top: 6px; border-top: 3px solid var(--gray); }
  .steps li.done { color: var(--run); border-top-color: var(--green); }
  .steps li.now { color: var(--black); font-weight: 700; border-top-color: var(--green); }
  .steps i { width: 10px; height: 10px; border: 2px solid currentColor; border-radius: 50%; flex: none; }
  .steps .now i { border-color: var(--gray); border-top-color: var(--black); animation: spin 0.9s linear infinite; }
  .steps .done i { background: var(--green); border-color: var(--green); }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (prefers-reduced-motion: reduce) { .steps .now i { animation: none; border-top-color: var(--black); } }
  @media (max-width: 820px) { .pending { padding-left: 16px; padding-right: 16px; } }
</style>
