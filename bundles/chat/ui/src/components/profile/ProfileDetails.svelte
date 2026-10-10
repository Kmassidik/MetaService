<script>
  /** The side panel's Details tab for one bot: its profile, avatar, notifications, routines, skills and memory. */
  import Icon from '../Icon.svelte'
  import BotAvatar from '../BotAvatar.svelte'
  import ProfileSection from './ProfileSection.svelte'
  import ProfileField from './ProfileField.svelte'
  import ProfileToggle from './ProfileToggle.svelte'
  import ProfileRoutines from './ProfileRoutines.svelte'
  import ProfileSaveBar from './ProfileSaveBar.svelte'
  import { avatarCatalog, isSameAvatar } from '../../lib/avatars.js'
  import { isProfileDirty, saveState } from '../../lib/profileForm.js'
  import { ICON_SIZE, MODALS, PROFILE_LIMITS } from '../../lib/constants.js'

  const PICKER_AVATAR_SIZE = 40
  const SUMMARY_ROWS = 2
  const INSTRUCTIONS_ROWS = 6

  let {
    active,
    pending = null,
    agentLimitReached = false,
    profileSaving = false,
    profileError = '',
    profileHighlight = {},
    profileSaved = {},
    unsavedPrompt = false,
    profileName = $bindable(''),
    profileSummary = $bindable(''),
    profileInstructions = $bindable(''),
    profileRoutines = [],
    profileSkills = [],
    profileMemory = [],
    webhookNotice = '',
    onSubmit,
    onSaveAndLeave,
    onDiscard,
    savedTick,
    patchSetting,
    duplicateActive,
    shareTemplate,
    routineAction,
    createWebhookRoutine,
    toggleSkill,
    clearMemory,
    openModal,
  } = $props()

  const editLocked = $derived(profileSaving || Boolean(pending))
  const form = $derived({ name: profileName, summary: profileSummary, instructions: profileInstructions })
  const dirty = $derived(isProfileDirty(form, active))
  const state = $derived(saveState({ saving: profileSaving, dirty, justSaved: profileSaved[savedTick.details] }))

  function isCurrentAvatar(option) {
    return isSameAvatar(active, option)
  }
</script>

<form class="profile-body" onsubmit={onSubmit}>
  <ProfileSection title="Profile">
    <ProfileField id="profile-name" label="Name" bind:value={profileName} max={PROFILE_LIMITS.name} disabled={editLocked} flash={profileHighlight.name} />
    <ProfileField id="profile-summary" label="Description" bind:value={profileSummary} max={PROFILE_LIMITS.summary} rows={SUMMARY_ROWS} placeholder="One or two lines on what it does" disabled={editLocked} flash={profileHighlight.summary} />
    <ProfileField id="profile-instructions" label="Instructions" bind:value={profileInstructions} max={PROFILE_LIMITS.instructions} rows={INSTRUCTIONS_ROWS} disabled={editLocked} flash={profileHighlight.instructions} />
  </ProfileSection>

  <ProfileSection title="Avatar" saved={profileSaved[savedTick.avatar]}>
    <div class="profile-avatars">
      {#each avatarCatalog as option (option.color)}
        <button
          type="button"
          class="profile-avatar-pick"
          class:is-selected={isCurrentAvatar(option)}
          disabled={profileSaving}
          aria-label={`${option.name} snake`}
          aria-pressed={isCurrentAvatar(option)}
          onclick={() => patchSetting(savedTick.avatar, { avatarColor: option.color, avatarShape: option.shape })}
        ><BotAvatar agent={{ ...active, avatarColor: option.color, avatarShape: option.shape }} size={PICKER_AVATAR_SIZE} /></button>
      {/each}
    </div>
  </ProfileSection>

  <ProfileSection title="Notifications" saved={profileSaved[savedTick.notifications]}>
    <ProfileToggle checked={active.notifyNeedsInput !== false} onChange={value => patchSetting(savedTick.notifications, { notifyNeedsInput: value })}>When {active.name} needs input</ProfileToggle>
    <ProfileToggle checked={active.notifyFinished !== false} onChange={value => patchSetting(savedTick.notifications, { notifyFinished: value })}>When {active.name} finishes</ProfileToggle>
  </ProfileSection>

  <ProfileSection title="Routines" note={webhookNotice}>
    <ProfileRoutines routines={profileRoutines} onAction={routineAction} />
    <button type="button" class="profile-row-button" onclick={createWebhookRoutine}><Icon name="plus" size={ICON_SIZE.inline} />Add webhook routine</button>
  </ProfileSection>

  <ProfileSection title="Skills" saved={profileSaved[savedTick.skills]}>
    {#each profileSkills as skill (skill.id)}
      <ProfileToggle checked={Boolean(skill.enabled)} detail={skill.state} onChange={value => toggleSkill(skill.id, value)}>{skill.name}</ProfileToggle>
    {:else}
      <p class="profile-empty">No skills yet. Teach a task, then type / in the composer.</p>
    {/each}
  </ProfileSection>

  <ProfileSection title="Memory">
    {#each profileMemory as entry (entry.key)}
      <p class="profile-memory"><strong>{entry.key}</strong>{entry.value}</p>
    {:else}
      <p class="profile-empty">Empty. {active.name} saves preferences here as you chat.</p>
    {/each}
    {#if profileMemory.length}<button type="button" class="profile-row-button is-danger" onclick={clearMemory}>Clear memory</button>{/if}
  </ProfileSection>

  <ProfileSection title="More" saved={profileSaved[savedTick.more]}>
    <button type="button" class="profile-row-button" disabled={profileSaving} onclick={() => patchSetting(savedTick.more, { pinned: !active.pinned })}>{active.pinned ? 'Unpin' : 'Pin to top'}</button>
    <button type="button" class="profile-row-button" disabled={profileSaving} onclick={() => patchSetting(savedTick.more, { hidden: !active.hidden })}>{active.hidden ? 'Show in sidebar' : 'Hide from sidebar'}</button>
    <button type="button" class="profile-row-button" disabled={profileSaving || agentLimitReached} onclick={duplicateActive}>Duplicate</button>
    <button type="button" class="profile-row-button" disabled={profileSaving} onclick={shareTemplate}>Share as template</button>
    <button type="button" class="profile-row-button is-danger" disabled={Boolean(pending)} onclick={() => openModal(MODALS.delete)}>Delete bot…</button>
  </ProfileSection>

  {#if profileError}<div class="error-box" role="alert">{profileError}</div>{/if}
  <ProfileSaveBar {state} locked={editLocked} asking={unsavedPrompt && dirty} {onSaveAndLeave} {onDiscard} />
</form>

<style>
  .profile-body { display: grid; align-content: start; gap: 20px; padding: 4px 16px 0; }
  /* One row per colour (the catalog lists each colour's six shapes in turn), like the sidebar picker. */
  .profile-avatars { display: grid; grid-template-columns: repeat(6, 1fr); justify-items: center; gap: 6px; padding: 12px; }
  .profile-avatar-pick { padding: 3px; border: 0; border-radius: var(--radius-control); background: none; line-height: 0; cursor: pointer; }
  .profile-avatar-pick:hover:not(:disabled) { background: var(--row-hover); }
  .profile-avatar-pick.is-selected { box-shadow: inset 0 0 0 2px var(--ink); }
  .profile-row-button {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
    padding: 12px 14px;
    border: 0;
    border-radius: 0;
    background: none;
    color: var(--text);
    font: 400 var(--fs-menu)/1.3 var(--font);
    text-align: left;
    cursor: pointer;
  }
  .profile-row-button:hover:not(:disabled) { background: var(--row-hover); }
  .profile-row-button:disabled { color: var(--text-3); cursor: default; }
  .profile-row-button.is-danger { color: var(--danger); }
  .profile-empty, .profile-memory { padding: 11px 14px; color: var(--text-2); font: 400 var(--fs-time)/1.45 var(--font); overflow-wrap: anywhere; }
  .profile-memory { color: var(--text); font-size: var(--fs-preview); }
  .profile-memory strong { margin-right: 6px; font-weight: 600; }
</style>
