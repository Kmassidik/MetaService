<script>
  import Switch from '../Switch.svelte'
  let { checked = false, disabled = false, detail = '', onChange, children } = $props()
</script>

<label class="profile-toggle">
  <span class="profile-toggle-text">{@render children()}{#if detail}<small>{detail}</small>{/if}</span>
  <Switch {checked} {disabled} {onChange} />
</label>

<style>
  .profile-toggle { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 11px 14px; color: var(--text); font: 400 var(--fs-menu)/1.35 var(--font); cursor: pointer; }
  .profile-toggle-text { min-width: 0; display: grid; }
  small { color: var(--text-2); font: 400 var(--fs-time)/1.35 var(--font); }
</style>
