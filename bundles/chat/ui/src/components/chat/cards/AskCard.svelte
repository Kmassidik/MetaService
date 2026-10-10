<script>
  import Card from './Card.svelte'
  import Icon from '../../Icon.svelte'

  // A question with choices that waits for the owner's answer.
  const MAX_CUSTOM_ANSWER = 16000
  let { ask, locked = false, picked = [], multiSelected = [], focusIndex = -1, onToggle, onSubmit, onSkip, onKeydown } = $props()

  let customAnswer = $state('')
  const multiple = $derived(ask.mode === 'multiple')
  const answered = $derived(locked && picked.length > 0)
  const helper = $derived(ask.helper || ask.hint || (multiple ? 'Select all that apply, then Send.' : ''))

  function isSelected(option) {
    return multiple ? multiSelected.includes(option.id) : picked.includes(option.label)
  }

  function choose(option) {
    if (multiple) onToggle(option.id)
    else onSubmit([option.label])
  }

  function sendSelected() {
    onSubmit(ask.options.filter(option => multiSelected.includes(option.id)).map(option => option.label))
  }

  function submitCustom(event) {
    event.preventDefault()
    const text = customAnswer.trim()
    if (!text || locked) return
    onSubmit([text])
    customAnswer = ''
  }
</script>

<Card label={ask.prompt || 'Answer choices'} title={ask.prompt} reason={answered ? '' : helper}>
  {#if ask.skippable && !locked}
    <button type="button" class="skip" aria-label="Skip question" title="Skip" onclick={onSkip}><Icon name="close" size={14} /></button>
  {/if}
  {#if answered}
    {#each picked as label (label)}
      <div class="card-row chosen"><span>{label}</span><Icon name="check" size={17} /></div>
    {/each}
  {:else}
    <div class="options">
      {#each ask.options as option, index (option.id)}
        {@const subtitle = option.subtitle || option.description || ''}
        <button type="button" class="card-row option" class:selected={isSelected(option)} class:focused={focusIndex === index} disabled={locked} onkeydown={onKeydown} onclick={() => choose(option)}>
          <span class="copy"><span>{option.title || option.label}</span>{#if subtitle}<small>{subtitle}</small>{/if}</span>
          {#if isSelected(option)}<Icon name="check" size={17} />{/if}
        </button>
      {/each}
    </div>
    {#if !locked}
      <form onsubmit={submitCustom}>
        <input class="card-row" type="text" maxlength={MAX_CUSTOM_ANSWER} placeholder="Type your own answer" aria-label="Type your own answer" autocomplete="off" bind:value={customAnswer} />
      </form>
    {/if}
  {/if}
  {#snippet actions()}
    {#if multiple && !locked}<button type="button" class="primary-button" disabled={!multiSelected.length} onclick={sendSelected}>Send</button>{/if}
  {/snippet}
</Card>

<style>
  .options { display: grid; gap: 6px; }
  .option { cursor: pointer; justify-content: space-between; }
  .option:hover:not(:disabled) { border-color: var(--hairline); }
  .option.selected { border-color: var(--text); }
  .option.focused, .option:focus-visible, input:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 0; }
  .option:disabled { color: var(--text-2); cursor: default; }
  .option :global(svg), .chosen :global(svg) { flex-shrink: 0; color: var(--text); }
  .copy { display: grid; gap: 2px; min-width: 0; overflow-wrap: anywhere; }
  small { color: var(--text-2); font: 400 13px/1.35 var(--font); }
  .chosen { justify-content: space-between; color: var(--text-2); }
  input::placeholder { color: var(--text-2); }
  .skip {
    position: absolute; top: 10px; right: 10px; display: grid; place-items: center; width: 28px; height: 28px; padding: 0;
    border: 0; border-radius: var(--radius-pill); background: transparent; color: var(--text-2); cursor: pointer;
  }
  .skip:hover { background: var(--tint-hover); color: var(--text); }
</style>
