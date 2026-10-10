<script>
  import Card from './Card.svelte'

  // The New bot welcome's answer card: tap an idea, or type something else. Either is sent as
  // the owner's first message, and the bot sets itself up from it.
  const MAX_ANSWER = 16000
  let { choices, locked = false, onPick } = $props()

  let somethingElse = $state('')

  function sendOwn(event) {
    event.preventDefault()
    const text = somethingElse.trim()
    if (!text || locked) return
    onPick(text)
    somethingElse = ''
  }
</script>

<Card label="Starter ideas" reason="Pick one to start, or say it in your own words.">
  <div class="options">
    {#each choices.options as option (option.id)}
      <button type="button" class="card-row option" disabled={locked} onclick={() => onPick(option.message)}>
        <span class="copy"><span>{option.label}</span>{#if option.subtitle}<small>{option.subtitle}</small>{/if}</span>
      </button>
    {/each}
  </div>
  <form onsubmit={sendOwn}>
    <input class="card-row" type="text" maxlength={MAX_ANSWER} placeholder="Something else…" aria-label="Something else" autocomplete="off" disabled={locked} bind:value={somethingElse} />
  </form>
</Card>

<style>
  .options { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px; }
  .option { align-items: flex-start; cursor: pointer; }
  .option:hover:not(:disabled) { border-color: var(--hairline); }
  .option:focus-visible, input:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 0; }
  .option:disabled { color: var(--text-2); cursor: default; }
  .copy { display: grid; gap: 2px; min-width: 0; overflow-wrap: anywhere; }
  small { color: var(--text-2); font: 400 13px/1.35 var(--font); }
  input::placeholder { color: var(--text-2); }
  @media (max-width: 520px) { .options { grid-template-columns: 1fr; } }
</style>
