<script>
  import { MISSING_PARAMETERS, actionRows, parameterRows } from '../../../lib/approvalDetails.js'

  // Exactly what Approve will let the bot do: the action, where, with which tool and what it sends.
  let { approval, id = '' } = $props()
  const action = $derived(actionRows(approval))
  const parameters = $derived(parameterRows(approval.parametersJSON))
</script>

{#snippet rows(list)}
  {#each list as row, index (index)}
    <div class="row"><dt>{row.label}</dt><dd>{row.value}</dd></div>
  {/each}
{/snippet}

<div class="approval-details" {id}>
  <dl>{@render rows(action)}</dl>
  {#if parameters.length}
    <p class="heading">What it will send</p>
    <dl>{@render rows(parameters)}</dl>
  {:else}
    <p class="missing" role="alert">{MISSING_PARAMETERS}</p>
  {/if}
</div>

<style>
  .approval-details { display: grid; gap: 6px; padding: 10px 12px; border-radius: var(--radius-control); background: var(--page); }
  /* One grid per list, so every value lines up in the same column. */
  dl { display: grid; grid-template-columns: max-content 1fr; gap: 4px 14px; margin: 0; }
  .row { display: contents; }
  dt { color: var(--text-2); font: 400 var(--fs-preview)/1.45 var(--font); }
  dd { min-width: 0; margin: 0; color: var(--text); font: 400 var(--fs-preview)/1.45 var(--font); white-space: pre-wrap; overflow-wrap: anywhere; }
  .heading { margin: 6px 0 0; padding-top: 8px; border-top: 1px solid var(--hairline); color: var(--text-2); font: 500 var(--fs-time)/1.4 var(--font); }
  .missing { margin: 4px 0 0; color: var(--danger); font: 400 var(--fs-preview)/1.45 var(--font); }
  @media (max-width: 520px) {
    dl { grid-template-columns: 1fr; gap: 0; }
    .row:not(:last-child) dd { margin-bottom: 6px; }
  }
</style>
