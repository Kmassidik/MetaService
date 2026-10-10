<script>
  import Icon from '../Icon.svelte'
  import PickerShell from './PickerShell.svelte'

  const PREVIEW_LENGTH = 80
  let {
    open = false,
    query = $bindable(''),
    skills = [],
    error = '',
    onPick,
    onClose,
  } = $props()
</script>

{#if open}
  <PickerShell label="Pick a skill" placeholder="Search skills…" bind:query {onClose}>
    {#if error}<p class="picker-empty" role="alert">{error}</p>{/if}
    {#each skills as skill (skill.id)}
      <button type="button" class="picker-option" role="option" aria-selected="false" onclick={() => onPick(skill)}>
        <span class="picker-glyph"><Icon name="spark" size={16} /></span>
        <span><strong>{skill.name}</strong><small>{(skill.body || '').slice(0, PREVIEW_LENGTH)}</small></span>
      </button>
    {:else}
      <p class="picker-empty">No enabled skills. Open the profile to enable one.</p>
    {/each}
  </PickerShell>
{/if}
