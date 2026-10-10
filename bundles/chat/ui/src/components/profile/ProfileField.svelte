<script>
  import { bytes } from '../../lib/format.js'

  let {
    id,
    label,
    value = $bindable(''),
    max,
    rows = 0,
    placeholder = '',
    disabled = false,
    flash = false,
  } = $props()
</script>

<div class="profile-field">
  <label for={id} class:is-flashing={flash}>{label}<span>{bytes(value)}/{max}</span></label>
  {#if rows}
    <textarea {id} bind:value maxlength={max} {rows} {placeholder} {disabled}></textarea>
  {:else}
    <input {id} bind:value maxlength={max} {placeholder} {disabled} />
  {/if}
</div>

<style>
  .profile-field { display: grid; gap: 2px; padding: 10px 14px; }
  label { display: flex; justify-content: space-between; gap: 8px; color: var(--text-2); font: 400 var(--fs-time)/1.4 var(--font); }
  label span { color: var(--text-3); }
  /* Flashes when the bot itself just edited this field. */
  label.is-flashing { color: var(--text); background: color-mix(in srgb, var(--brand-green) 30%, transparent); border-radius: var(--radius-item); }
  input, textarea {
    width: 100%;
    padding: 0;
    border: 0;
    background: none;
    color: var(--text);
    font: 400 var(--fs-name)/1.45 var(--font);
    resize: vertical;
  }
  input:focus, textarea:focus { outline: none; }
  .profile-field:focus-within { box-shadow: inset 3px 0 0 var(--brand-green-d); }
  @media (max-width: 820px) { input, textarea { font-size: 16px; } }
</style>
