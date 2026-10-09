<script>
  // A password-style input with an eye on the right to show what was typed.
  let { label, value = $bindable(''), name, autocomplete = 'off', placeholder = '' } = $props()
  let shown = $state(false)
</script>

<label class="field secret">
  <span>{label}</span>
  <div class="inp">
    <input {name} type={shown ? 'text' : 'password'} {autocomplete} {placeholder} required bind:value />
    <button type="button" class="eye" aria-label={shown ? `Hide ${label.toLowerCase()}` : `Show ${label.toLowerCase()}`} aria-pressed={shown} onclick={() => (shown = !shown)}>
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z" /><circle cx="12" cy="12" r="3" />
        {#if shown}<path d="M3 3l18 18" />{/if}
      </svg>
    </button>
  </div>
</label>

<style>
  .inp { position: relative; }
  .inp input { padding-right: 44px; }
  .eye { position: absolute; right: 0; top: 0; bottom: 0; width: 42px; background: none; border: 0; color: var(--m40); display: grid; place-items: center; }
  .eye:hover, .eye[aria-pressed='true'] { color: var(--black); }
</style>
