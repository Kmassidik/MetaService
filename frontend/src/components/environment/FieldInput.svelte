<script lang="ts">
  // One labelled text box with its reason when the value cannot be saved. The id is env-<name>, so a test or a label can find it.
  let { name, label, value = $bindable(), error = undefined, hint = '', numeric = false, placeholder = 'not set' }: {
    name: string
    label: string
    value: string
    error?: string | undefined
    hint?: string
    numeric?: boolean
    placeholder?: string
  } = $props()
</script>

<div class="entry">
  <label for="env-{name}">{label}</label>
  <input id="env-{name}" {name} type="text" inputmode={numeric ? 'numeric' : 'text'} autocomplete="off" spellcheck="false" {placeholder} aria-invalid={error ? 'true' : 'false'} aria-describedby={error ? `env-${name}-error` : undefined} bind:value />
  {#if error}<p class="error" id="env-{name}-error" role="alert">{error}</p>{:else if hint}<p class="hint">{hint}</p>{/if}
</div>

<style>
  .entry { display: grid; gap: 6px; align-content: start; min-width: 0; }
  label { font: 10px var(--mono); text-transform: uppercase; letter-spacing: 0.12em; color: var(--m50); }
  input { width: 100%; border: 1px solid var(--line); background: var(--surface); color: var(--text); padding: 10px 12px; font: 14px var(--sans); }
  input::placeholder { color: var(--m40); }
  input:focus { outline: 2px solid var(--accent-mark); outline-offset: -1px; }
  input[aria-invalid='true'] { border-color: var(--danger); }
  .error, .hint { margin: 0; font-size: 12px; line-height: 1.5; overflow-wrap: anywhere; }
  .error { color: var(--danger); }
  .hint { color: var(--m50); }
</style>
