<script>
  import Card from './Card.svelte'
  import Icon from '../../Icon.svelte'

  // The bot changed its profile (a routine, skill or name); a compact confirmation.
  let { notice, onOpen, onDismiss } = $props()
</script>

<Card label="Profile update">
  <p class="notice"><Icon name="check" size={16} />{notice}</p>
  {#snippet actions()}
    <button type="button" class="primary-button" onclick={onOpen}>Open</button>
    <button type="button" class="card-quiet" onclick={onDismiss}>Dismiss</button>
  {/snippet}
</Card>

<style>
  .notice { display: flex; align-items: center; gap: 8px; margin: 0; font: 400 var(--fs-message)/1.4 var(--font); }
  .notice :global(svg) { flex-shrink: 0; color: var(--ok); }
</style>
