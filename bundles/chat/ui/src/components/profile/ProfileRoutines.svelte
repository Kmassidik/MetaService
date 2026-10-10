<script>
  let { routines = [], onAction } = $props()

  function summary(routine) {
    const trigger = routine.triggerKind || routine.scheduleKind
    const webhook = routine.hasWebhook ? ' · webhook' : ''
    return `${routine.state} · ${trigger}${webhook}`
  }
</script>

{#each routines as routine (routine.id)}
  <div class="profile-routine">
    <div class="profile-routine-text"><strong>{routine.title}</strong><span>{summary(routine)}</span></div>
    <div class="profile-routine-actions">
      {#if routine.state === 'active'}
        <button type="button" onclick={() => onAction(routine.id, 'pause')}>Pause</button>
      {:else}
        <button type="button" onclick={() => onAction(routine.id, 'resume')}>Resume</button>
      {/if}
      <button type="button" onclick={() => onAction(routine.id, 'test')}>Test</button>
      <button type="button" class="is-danger" onclick={() => onAction(routine.id, 'delete')}>Delete</button>
    </div>
  </div>
{:else}
  <p class="profile-routine-empty">No routines yet. Ask the bot to create one, or add a webhook.</p>
{/each}

<style>
  .profile-routine { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 10px 14px; }
  .profile-routine + .profile-routine { border-top: 1px solid var(--hairline); }
  .profile-routine-text { min-width: 0; display: grid; }
  strong { color: var(--text); font: 500 var(--fs-menu)/1.35 var(--font); overflow-wrap: anywhere; }
  span, .profile-routine-empty { color: var(--text-2); font: 400 var(--fs-time)/1.4 var(--font); }
  .profile-routine-empty { padding: 11px 14px; }
  .profile-routine-actions { display: flex; gap: 2px; flex-shrink: 0; }
  button { padding: 5px 8px; border: 0; border-radius: var(--radius-item); background: none; color: var(--text); font: 500 var(--fs-time)/1 var(--font); cursor: pointer; }
  button:hover { background: var(--row-hover); }
  button.is-danger { color: var(--danger); }
</style>
