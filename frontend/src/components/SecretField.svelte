<script>
  let { label, value = $bindable(''), name, autocomplete = 'off', hint = '' } = $props()
  let shown = $state(false)
</script>

<label class="field secret">
  <span>{label}</span>
  <div class="inp">
    <input {name} type={shown ? 'text' : 'password'} {autocomplete} required bind:value />
    <button type="button" class="eye" aria-label={shown ? `Hide ${label.toLowerCase()}` : `Show ${label.toLowerCase()}`} aria-pressed={shown} onclick={() => (shown = !shown)}>
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" aria-hidden="true">
        <path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z" /><circle cx="12" cy="12" r="3" />
        {#if !shown}<path d="M3 3l18 18" />{/if}
      </svg>
    </button>
  </div>
  {#if hint}<small class="hint">{hint}</small>{/if}
</label>

<style>
  .inp { position: relative; }
  .inp input { padding-right: 44px; }
  .eye { position: absolute; right: 0; top: 0; bottom: 0; width: 42px; background: none; border: 0; color: var(--m50); display: grid; place-items: center; }
  .eye:hover, .eye[aria-pressed='true'] { color: var(--black); }
  .hint { display: block; margin-top: 6px; font-family: var(--mono); font-size: 10px; color: var(--m50); }
</style>
