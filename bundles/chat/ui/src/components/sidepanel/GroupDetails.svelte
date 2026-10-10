<script>
  /** The side panel's Details for a group chat: its purpose, lead and members, and the way into editing it. */
  import Icon from '../Icon.svelte'
  import BotAvatar from '../BotAvatar.svelte'
  import ProfileSection from '../profile/ProfileSection.svelte'
  import { ICON_SIZE } from '../../lib/constants.js'

  const FACE_SIZE = 32

  let { team, members = [], editLocked = false, onEdit } = $props()
</script>

<div class="group-body">
  {#if team.description}
    <ProfileSection title="Purpose"><p class="group-text">{team.description}</p></ProfileSection>
  {/if}
  <ProfileSection title="Members" note="The lead hands work to members and brings their results together in this chat.">
    {#each members as member (member.id)}
      <div class="member">
        <BotAvatar agent={member} size={FACE_SIZE} />
        <span class="member-name">{member.name}</span>
        {#if member.id === team.leadAgentId}<span class="member-role">Lead</span>{/if}
      </div>
    {/each}
  </ProfileSection>
  <button type="button" class="secondary-button" disabled={editLocked} onclick={onEdit}><Icon name="edit" size={ICON_SIZE.inline} />Edit group</button>
</div>

<style>
  .group-body { display: grid; align-content: start; gap: 20px; padding: 4px 16px 24px; }
  .group-text { padding: 11px 14px; color: var(--text); font: 400 var(--fs-preview)/1.45 var(--font); white-space: pre-wrap; overflow-wrap: anywhere; }
  .member { display: flex; align-items: center; gap: 10px; padding: 9px 14px; }
  .member-name { flex: 1; min-width: 0; overflow: hidden; color: var(--text); font: 400 var(--fs-menu)/1.3 var(--font); text-overflow: ellipsis; white-space: nowrap; }
  .member-role { color: var(--text-2); font: 500 var(--fs-time)/1 var(--font); }
</style>
