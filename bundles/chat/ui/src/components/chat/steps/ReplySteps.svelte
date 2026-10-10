<script>
  import StepsToggle from './StepsToggle.svelte'
  import StepList from './StepList.svelte'

  // "Show steps" under a bot's reply; nothing at all when the run had no meaningful steps.
  let { steps = [] } = $props()
  let open = $state(false)
  const listId = $props.id()
</script>

{#if steps.length}
  <div class="reply-steps">
    <StepsToggle bind:open controls={listId} />
    {#if open}<StepList {steps} id={listId} />{/if}
  </div>
{/if}

<style>
  .reply-steps { max-width: min(560px, 100%); margin: 2px 0 0 6px; }
</style>
