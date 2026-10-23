<script lang="ts">
  // The window shown after Create: the VM's name and machine, a status tag, and a vertical list of the steps with the real one marked.
  // It only draws what createProgress.ts works out. Closing it never stops the making; the VM keeps its row on the pages behind.
  import Dialog from '../Dialog.svelte'
  import RichBadge from './create/RichBadge.svelte'
  import type { ProgressStatus, ProgressView } from '../../lib/createProgress.ts'
  import { LOGOS } from '../../lib/logos.ts'
  import { machineHref, vmHref } from '../../lib/routes.ts'

  const STATUS_TAGS: Record<ProgressStatus, string> = { working: 'Creating…', ready: 'Ready', failed: 'Failed' }
  const STATUS_CLASSES: Record<ProgressStatus, string> = { working: 'prog', ready: 'run', failed: 'bad' }

  let { view, onClose }: { view: ProgressView | null; onClose: () => void } = $props()
  const header = $derived(view?.header ?? null)
  const progress = $derived(view?.progress ?? null)
  const openHref = $derived(header?.workloadId ? vmHref(header.machineId, header.workloadId) : null)
</script>

<Dialog open={view !== null} title="Create VM" {onClose} closeButton backdropClose>
  {#if header && progress}
    <div class="progress" data-create-progress={progress.status}>
      <div class="head">
        <RichBadge title={header.name} logo={header.logo ? LOGOS[header.logo] : undefined} glyph={header.kind} />
        <div class="who">
          <b class="name">{header.name}</b>
          <span class="on">on <a href={machineHref(header.machineId)} onclick={onClose}>{header.machineName}</a></span>
        </div>
        <span class="tag {STATUS_CLASSES[progress.status]}" data-progress-tag>{STATUS_TAGS[progress.status]}</span>
      </div>
      <ol class="steps" aria-label="Progress">
        {#each progress.steps as step (step.id)}
          <li class={step.state} data-step={step.id} aria-current={step.state === 'now' ? 'step' : undefined}>
            <i aria-hidden="true">{#if step.state === 'now'}<span class="btn-spin"></span>{:else if step.state === 'done'}✓{:else if step.state === 'failed'}!{/if}</i>
            <span>{step.label}</span>
          </li>
        {/each}
      </ol>
      {#if progress.reason}<p class="reason" role="alert">{progress.reason}</p>{/if}
      <div class="buttons">
        {#if progress.status === 'ready' && openHref}<a class="btn green" href={openHref} onclick={onClose}>Open VM</a>{/if}
        <button class="btn line" type="button" onclick={onClose}>Close</button>
      </div>
      {#if progress.status === 'working'}<p class="note">You can close this. The VM keeps being made, and shows in All VMs.</p>{/if}
    </div>
  {/if}
</Dialog>

<style>
  .progress { display: grid; gap: 18px; }
  .head { display: flex; align-items: center; gap: 12px; min-width: 0; }
  .who { display: grid; gap: 2px; min-width: 0; flex: 1 1 auto; }
  .name { overflow-wrap: anywhere; }
  .on { color: var(--m60); font-size: 13px; }
  .on a { text-decoration: underline; }
  .tag.bad { color: var(--danger); border-color: var(--danger); background: var(--danger-bg); }
  .steps { list-style: none; margin: 0; padding: 0; display: grid; gap: 0; position: relative; }
  .steps li { position: relative; display: flex; align-items: center; gap: 12px; min-height: 40px; font-size: 14px; color: var(--m50); }
  /* The thin line runs behind the dots, from the first to the last. */
  .steps li:not(:last-child)::before { content: ''; position: absolute; left: 10px; top: 30px; bottom: -10px; width: 1px; background: var(--line); }
  .steps li.done:not(:last-child)::before { background: var(--ok); }
  .steps i { position: relative; flex: none; width: 21px; height: 21px; display: grid; place-items: center; border: 1.5px solid var(--line-strong); border-radius: 50%; background: var(--surface); font: 700 11px var(--mono); font-style: normal; color: var(--m50); opacity: .55; }
  .steps li.done { color: var(--text); }
  .steps li.done i { background: var(--ok); border-color: var(--ok); color: var(--surface); opacity: 1; }
  .steps li.now { color: var(--text); font-weight: 700; }
  .steps li.now i { border-color: var(--line-strong); color: var(--text); opacity: 1; }
  .steps li.now i :global(.btn-spin) { margin: 0; width: 11px; height: 11px; vertical-align: 0; }
  .steps li.failed { color: var(--danger); font-weight: 700; }
  .steps li.failed i { background: var(--danger); border-color: var(--danger); color: var(--surface); opacity: 1; }
  /* A reason can hold the last lines a VM printed: keep its line breaks, wrap it, and let a very long one scroll inside the window. */
  .reason { margin: 0; padding: 10px 12px; border-left: 3px solid var(--danger-note-bar); background: var(--danger-note-bg); color: var(--danger-note-text); overflow-wrap: anywhere; white-space: pre-wrap; max-height: 14em; overflow-y: auto; font-size: 13px; }
  .buttons { display: flex; gap: 10px; flex-wrap: wrap; justify-content: flex-end; }
  .note { margin: 0; font-size: 12px; color: var(--m50); }
</style>
