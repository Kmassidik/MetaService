<script>
  import Card from './Card.svelte'
  import ApprovalDetails from './ApprovalDetails.svelte'

  // Approvals: Approve once or Deny right in the chat; "Details" opens the exact action in place.
  let { approval, busy = false, onApprove, onDeny } = $props()
  let detailsOpen = $state(false)
  const detailsId = $props.id()
  const where = $derived([approval.destination, approval.tool].filter(Boolean).join(' · '))
  const canApprove = $derived(Boolean(onApprove && approval.parametersJSON))
</script>

<Card title={`Approve: ${approval.action}`} reason={where}>
  {#if detailsOpen}<ApprovalDetails {approval} id={detailsId} />{/if}
  {#snippet actions()}
    {#if canApprove}<button type="button" class="primary-button" disabled={busy} onclick={() => onApprove(approval)}>Approve</button>{/if}
    {#if onDeny}<button type="button" class="card-quiet" disabled={busy} onclick={() => onDeny(approval)}>Deny</button>{/if}
    <button type="button" class="card-link" aria-expanded={detailsOpen} aria-controls={detailsId} onclick={() => detailsOpen = !detailsOpen}>
      {detailsOpen ? 'Hide details' : 'Details'}
    </button>
  {/snippet}
</Card>

<style>
  .card-link {
    margin-left: 4px; padding: 0; border: 0; background: none; color: var(--text-2);
    font: 400 14px/1.4 var(--font); text-decoration: underline; text-underline-offset: 3px; cursor: pointer;
  }
  .card-link:hover { color: var(--text); }
</style>
