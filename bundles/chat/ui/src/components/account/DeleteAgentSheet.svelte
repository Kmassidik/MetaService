<script>
  /** Confirm deleting a bot or group chat; warns when that stops work in progress. */
  import Icon from '../Icon.svelte'
  import { chat, closeModal, deleteAgent } from '../../lib/chatApp.svelte.js'

  const WORKING_STATES = ['running', 'provisioning']

  const isTeam = $derived(chat.formKind === 'team')
  const noun = $derived(isTeam ? 'group chat' : 'bot')
  const target = $derived(chat.agents.find(agent => agent.id === chat.editId))
  const name = $derived(target?.name || (isTeam ? 'this group' : 'this bot'))
  const working = $derived(Boolean(chat.pending) || WORKING_STATES.includes(target?.status))
</script>

<div class="delete-icon"><Icon name="trash" size={25} /></div>
<h2>Delete {name}?</h2>
<p class="modal-description">
  {#if isTeam}
    This permanently deletes the group chat and its conversation. Lead and member bots are kept.
  {:else}
    This permanently deletes the bot and its conversation history. Bots in a group must leave that group first.
  {/if}
  There’s no undo. Files already in Results stay until you delete them there.
</p>
<div class="error-box" role="note">
  {#if working}
    This bot is still working. Confirming will <strong>stop that work</strong> and delete it.
  {:else}
    If it starts working before you confirm, we’ll stop that work and delete it anyway.
  {/if}
</div>
{#if chat.formError}<div class="error-box" role="alert">{chat.formError}</div>{/if}
<div class="modal-actions">
  <button class="secondary-button" onclick={closeModal} disabled={chat.saving}>Keep {noun}</button>
  <button class="danger-button" onclick={deleteAgent} disabled={chat.saving}>{chat.saving ? 'Deleting…' : `Yes, delete ${isTeam ? 'group' : 'bot'}`}</button>
</div>

<style>
  .delete-icon { display: grid; place-items: center; width: 48px; height: 48px; margin-bottom: 16px; border-radius: var(--radius-avatar); background: var(--danger-bg); color: var(--danger); }
</style>
