<script>
  /** A native checkbox drawn as a small switch; keeps keyboard and screen-reader behaviour for free. */
  let { checked = false, disabled = false, label = undefined, onChange } = $props()
</script>

<input type="checkbox" role="switch" aria-label={label} {checked} {disabled} onchange={event => onChange(event.currentTarget.checked)} />

<style>
  input {
    appearance: none;
    flex-shrink: 0;
    position: relative;
    width: 38px;
    height: 22px;
    margin: 0;
    border-radius: var(--radius-pill);
    background: var(--switch-off);
    cursor: pointer;
    transition: background-color .15s ease;
  }
  input::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: var(--switch-knob);
    box-shadow: 0 1px 2px var(--tint-selected);
    transition: transform .15s ease;
  }
  input:checked { background: var(--brand-green-d); }
  input:checked::after { transform: translateX(16px); }
  input:disabled { cursor: default; opacity: .5; }
  input:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
</style>
