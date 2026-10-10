<script>
  import Icon from '../Icon.svelte'
  import AuthShell from './AuthShell.svelte'
  import { goalOptions, sourceOptions } from '../../lib/constants.js'

  let {
    goal = $bindable(''),
    goalDetail = $bindable(''),
    source = $bindable(''),
    sourceDetail = $bindable(''),
    error = '',
    saving = false,
    onSubmit,
  } = $props()
</script>

<AuthShell labelledby="onboarding-title" wide>
  <h1 id="onboarding-title">What brings you here?</h1>
  <p>Two quick answers help us set up Ruvio for you. They stay with your account.</p>
  <form onsubmit={onSubmit}>
    <fieldset>
      <legend>What do you want your bots to help with?</legend>
      <div class="choice-grid">
        {#each goalOptions as [value, label] (value)}
          <label class:chosen={goal === value}>
            <input type="radio" name="goal" value={value} bind:group={goal} required />{label}
          </label>
        {/each}
      </div>
    </fieldset>
    {#if goal === 'other'}
      <label class="form-label" for="goal-detail">Tell us more</label>
      <textarea id="goal-detail" class="form-input" bind:value={goalDetail} maxlength="500" rows="3" required></textarea>
    {/if}
    <fieldset>
      <legend>Where did you hear about Ruvio?</legend>
      <div class="choice-grid">
        {#each sourceOptions as [value, label] (value)}
          <label class:chosen={source === value}>
            <input type="radio" name="source" value={value} bind:group={source} required />{label}
          </label>
        {/each}
      </div>
    </fieldset>
    {#if source === 'other'}
      <label class="form-label" for="source-detail">Where did you find us?</label>
      <input id="source-detail" class="form-input" bind:value={sourceDetail} maxlength="200" required />
    {/if}
    {#if error}<div class="error-box" role="alert">{error}</div>{/if}
    <button class="primary-button submit" type="submit" disabled={saving || !goal || !source}>
      {saving ? 'Saving…' : 'Open my workspace'}<Icon name="chevron" size={16} />
    </button>
  </form>
</AuthShell>

<style>
  fieldset { border: 0; padding: 0; margin: 0 0 28px; }
  legend { margin-bottom: 12px; padding: 0; color: var(--text); font: 600 15px/1.4 var(--font); }
  .choice-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
  .choice-grid label { display: flex; align-items: center; gap: 10px; min-height: 48px; padding: 12px 14px; border: 1px solid var(--hairline); border-radius: var(--radius-menu); background: var(--page); color: var(--text); cursor: pointer; font: 14.5px/1.35 var(--font); }
  .choice-grid label:hover { background: var(--row-hover); }
  .choice-grid label.chosen { border-color: var(--ink); background: var(--row-selected); }
  .choice-grid input { accent-color: var(--ink); }
  .submit { display: flex; min-height: 44px; margin: 8px 0 0 auto; padding-inline: 20px; }
  @media (max-width: 520px) {
    .choice-grid { grid-template-columns: 1fr; }
    .submit { width: 100%; }
  }
</style>
