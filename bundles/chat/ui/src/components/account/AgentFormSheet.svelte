<script>
  /** Create or edit a group chat, or edit a bot (bots are created by conversation instead). */
  import Icon from '../Icon.svelte'
  import { chat, applyPreset, chooseLead, closeModal, saveAgent } from '../../lib/chatApp.svelte.js'
  import { MAX_GROUP_CHATS, MAX_GROUP_MEMBERS, MODALS, instructionPresets } from '../../lib/constants.js'
  import { bytes, number } from '../../lib/format.js'

  // Mirrors the API limits so the button disables before a doomed round trip.
  const MAX_NAME_BYTES = 120
  const MAX_DESCRIPTION_BYTES = 4000
  const MAX_NAME_CHARS = 80
  const MB_PER_GIB = 1024
  const BYTES_PER_GB = 1e9

  let { view } = $props()

  const isTeam = $derived(chat.formKind === 'team')
  const isCreate = $derived(chat.modal === MODALS.create)
  const noun = $derived(isTeam ? 'group chat' : 'bot')
  const title = $derived(`${isCreate ? 'Create' : 'Edit'} ${noun}`)
  const submitLabel = $derived(submitText(chat.saving, isCreate, title))
  const limits = $derived(view.planLimits)
  const memberChoices = $derived(view.readyBots.filter(bot => bot.id !== chat.formLeadId))
  const unavailableMembers = $derived(chat.formMemberIds.filter(id => !view.readyBots.some(bot => bot.id === id)))
  const submitDisabled = $derived(chat.saving || createBlocked() || Boolean(view.teamFormError) || !formValid())

  function submitText(saving, creating, heading) {
    if (!saving) return creating ? heading : 'Save changes'
    return creating ? 'Preparing workspace…' : 'Saving…'
  }

  function createBlocked() {
    if (!isCreate) return false
    return isTeam ? view.createTeamBlocked : view.createBlocked
  }

  function formValid() {
    const name = chat.formName.trim()
    return Boolean(name) && bytes(name) <= MAX_NAME_BYTES && bytes(chat.formDescription.trim()) <= MAX_DESCRIPTION_BYTES
  }

  function memberLocked(id) {
    return !chat.formMemberIds.includes(id) && chat.formMemberIds.length >= MAX_GROUP_MEMBERS
  }

  function memberName(id) {
    return view.bots.find(bot => bot.id === id)?.name || 'Selected member'
  }

  function removeMember(id) {
    chat.formMemberIds = chat.formMemberIds.filter(memberId => memberId !== id)
  }

  function askToDelete() {
    chat.modal = MODALS.delete
    chat.formError = ''
  }
</script>

<form onsubmit={saveAgent}>
  <h2>{title}</h2>
  {#if isTeam}
    <p class="modal-description">One lead coordinates your selected bots in a separate group conversation. The group uses their saved personalities, not their personal chats or files.</p>
    <p class="form-help">Up to {MAX_GROUP_CHATS} group chats, separate from your bot limit. Up to {MAX_GROUP_MEMBERS + 1} bots per group (1 lead + {MAX_GROUP_MEMBERS} members). Lead and member work shares the task’s token budget.</p>
  {:else}
    <p class="modal-description">Update your bot’s settings. Existing conversations stay in place. To change the role by chatting, just ask the bot.</p>
    {#if isCreate && limits}<p class="form-help">Free beta: up to {limits.maxAgents} bots sharing one {limits.cpu} vCPU / {number(limits.memoryMB / MB_PER_GIB)} GiB RAM computer and {number(limits.workspaceBytes / BYTES_PER_GB)} GB workspace.</p>{/if}
  {/if}
  <label class="form-label" for="bot-name">Name</label>
  <input id="bot-name" class="form-input" bind:value={chat.formName} placeholder={isTeam ? 'e.g. Launch crew' : 'e.g. Research partner'} maxlength={MAX_NAME_CHARS} required disabled={chat.saving} />
  {#if isTeam}
    <label class="form-label" for="team-lead">Lead bot</label>
    <select id="team-lead" class="form-input" value={chat.formLeadId} onchange={chooseLead} required disabled={chat.saving}>
      <option value="">Choose a lead</option>
      {#each view.readyBots as bot (bot.id)}<option value={bot.id}>{bot.name}</option>{/each}
    </select>
    <fieldset class="team-members" disabled={chat.saving} aria-describedby="team-members-help">
      <legend>Member bots <span>{chat.formMemberIds.length}/{MAX_GROUP_MEMBERS}</span></legend>
      {#each memberChoices as bot (bot.id)}
        <label><input type="checkbox" value={bot.id} bind:group={chat.formMemberIds} disabled={memberLocked(bot.id)} /><span>{bot.name}</span></label>
      {:else}
        <p class="form-help">No other ready bots available.</p>
      {/each}
    </fieldset>
    <p id="team-members-help" class="form-help">Choose 1–{MAX_GROUP_MEMBERS} members. The lead delegates to these named personalities; source bots stay unchanged.</p>
    {#each unavailableMembers as id (id)}
      <p class="form-help">{memberName(id)} is no longer ready. <button type="button" class="text-button" disabled={chat.saving} onclick={() => removeMember(id)}>Remove unavailable member</button></p>
    {/each}
    {#if view.teamFormError}<p class="form-help" role="status">{view.teamFormError}</p>{/if}
    <label class="form-label" for="bot-description">Purpose <span>optional · {bytes(chat.formDescription)}/{MAX_DESCRIPTION_BYTES} bytes</span></label>
    <textarea id="bot-description" class="form-input form-description" bind:value={chat.formDescription} placeholder="What should this team accomplish together?" maxlength={MAX_DESCRIPTION_BYTES} rows="3" disabled={chat.saving}></textarea>
  {:else}
    <label class="form-label" for="instruction-preset">Optional personality preset</label>
    <select id="instruction-preset" class="form-input" bind:value={chat.presetId} onchange={() => chat.presetNotice = ''} disabled={chat.saving}>
      <option value="">Write your own instructions</option>
      {#each instructionPresets as preset (preset.id)}<option value={preset.id}>{preset.name}</option>{/each}
    </select>
    {#if view.selectedPreset}
      <div class="preset-preview">
        <p>{view.selectedPreset.text}</p>
        <button type="button" class="secondary-button" onclick={applyPreset} disabled={chat.saving}>Add to instructions</button>
        <small>Appends to your text; never replaces existing instructions. Does not change permissions.</small>
      </div>
    {/if}
    {#if chat.presetNotice}<p class="form-help" role="status">{chat.presetNotice}</p>{/if}
    <label class="form-label" for="bot-description">Instructions <span>optional · {bytes(chat.formDescription)}/{MAX_DESCRIPTION_BYTES} bytes</span></label>
    <textarea id="bot-description" class="form-input form-description" bind:value={chat.formDescription} placeholder="What should this bot help with? How should it respond?" maxlength={MAX_DESCRIPTION_BYTES} rows="4" disabled={chat.saving}></textarea>
  {/if}
  <p class="form-help">Auto selects a model for each task. Model access is included with Ruvio. No API key needed.</p>
  {#if chat.formError}<div class="error-box" role="alert">{chat.formError}</div>{/if}
  <div class="modal-actions">
    {#if isCreate}
      <button type="button" class="secondary-button" onclick={closeModal} disabled={chat.saving}>Cancel</button>
    {:else}
      <button class="danger-text" type="button" disabled={chat.saving || Boolean(chat.pending)} onclick={askToDelete}><Icon name="trash" size={16} />Delete {noun}</button>
    {/if}
    <button class="primary-button" type="submit" disabled={submitDisabled}>{submitLabel}<Icon name="chevron" size={16} /></button>
  </div>
</form>

<style>
  .team-members { min-width: 0; margin: 18px 0 0; padding: 6px 14px; border: 1px solid var(--hairline); border-radius: var(--radius-card); }
  .team-members legend { padding: 0 6px; color: var(--text-2); font: 13px/1.5 var(--font); }
  .team-members legend span { margin-left: 8px; }
  .team-members label { display: flex; align-items: center; gap: 10px; padding: 10px 0; cursor: pointer; font: var(--fs-menu)/1.4 var(--font); overflow-wrap: anywhere; }
  .team-members input { flex-shrink: 0; width: 16px; height: 16px; accent-color: var(--ink); }
  .team-members label:has(input:disabled) { opacity: .55; }
  .preset-preview { margin-top: 10px; padding: 14px; border-radius: var(--radius-card); background: var(--bubble); display: grid; gap: 10px; justify-items: start; }
  .preset-preview p { font: 14px/1.55 var(--font); }
  .preset-preview small { color: var(--text-2); font: var(--fs-time)/1.5 var(--font); }
</style>
