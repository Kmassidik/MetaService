<script>
  /**
   * The right-hand panel (P6), Grok-style: the bot's face, name and label, then Details / Files /
   * Computer. About 420 px beside the chat on desktop, full screen on phone.
   */
  import Icon from '../Icon.svelte'
  import PanelIdentity from './PanelIdentity.svelte'
  import PanelTabs from './PanelTabs.svelte'
  import GroupDetails from './GroupDetails.svelte'
  import ComputerPreview from './ComputerPreview.svelte'
  import ProfileDetails from '../profile/ProfileDetails.svelte'
  import FilePanel from '../workspace/FilePanel.svelte'
  import { ICON_SIZE, MODALS } from '../../lib/constants.js'
  import { PANEL_TABS } from '../../lib/sidePanel.js'
  import {
    chat, SIDE_PANEL_ID, closeSidePanel, selectPanelTab, saveTitle, saveProfile, saveAndLeave, discardAndLeave,
    patchProfileSetting, SAVED_TICK, duplicateActive, shareTemplate, routineAction, createWebhookRoutine, toggleSkill, clearMemory, openModal, openComputer,
    manageEnvironment, loadFiles, attachFile, deleteFile,
  } from '../../lib/chatApp.svelte.js'

  const BODY_ID = 'side-panel-body'
  const WAKE_ACTION = 'wake'
  const FILES_TITLE = 'Files'

  let { view } = $props()

  const active = $derived(view.active)
  const isGroup = $derived(active?.kind === 'team')

  function closeOnEscape(event) {
    if (event.key !== 'Escape' || event.defaultPrevented) return
    event.preventDefault()
    closeSidePanel()
  }
</script>

{#if view.panelShown}
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <aside id={SIDE_PANEL_ID} class="side-panel" tabindex="-1" aria-label={active ? `${active.name} details` : FILES_TITLE} onkeydown={closeOnEscape}>
    <div class="side-bar">
      <button type="button" class="icon-button" aria-label="Close panel" onclick={closeSidePanel}><Icon name="close" size={ICON_SIZE.header} /></button>
    </div>
    <div class="side-scroll">
      {#if active}
        <PanelIdentity agent={active} members={view.members} labelSaved={chat.profileSaved[SAVED_TICK.label]} onSaveLabel={saveTitle} />
        <PanelTabs tabs={view.panelTabs} current={view.panelTab} panelId={BODY_ID} onSelect={selectPanelTab} />
      {:else}
        <h2 class="files-title">{FILES_TITLE}</h2>
      {/if}
      <div id={BODY_ID} role="tabpanel">
        {#if view.panelTab === PANEL_TABS.files}
          <FilePanel
            files={chat.files} agents={chat.agents} loading={chat.filesLoading} error={chat.filesError}
            refresh={loadFiles} attach={attachFile} remove={deleteFile}
            selectedIds={view.selectedAttachments.map(file => file.id)} canAttach={!view.uploadLocked}
            deleting={chat.deletingFile || (chat.pending ? 'message-pending' : '')} sessionKey={chat.session.csrf}
          />
        {:else if view.panelTab === PANEL_TABS.computer}
          <ComputerPreview
            image={view.previewImage} stream={view.previewStream} line={view.previewLine} waking={chat.environmentAction === WAKE_ACTION}
            onOpen={openComputer} onWake={() => manageEnvironment(WAKE_ACTION)}
          />
        {:else if isGroup}
          <GroupDetails team={active} members={view.members} editLocked={Boolean(chat.pending)} onEdit={() => openModal(MODALS.edit)} />
        {:else}
          <ProfileDetails
            {active} pending={chat.pending} agentLimitReached={view.agentLimitReached}
            profileSaving={chat.profileSaving} profileError={chat.profileError} profileHighlight={chat.profileHighlight}
            profileSaved={chat.profileSaved} unsavedPrompt={chat.unsavedPrompt} savedTick={SAVED_TICK}
            bind:profileName={chat.profileName} bind:profileSummary={chat.profileSummary} bind:profileInstructions={chat.profileInstructions}
            profileRoutines={chat.profileRoutines} profileSkills={chat.profileSkills} profileMemory={chat.profileMemory}
            webhookNotice={chat.webhookNotice} onSubmit={saveProfile} onSaveAndLeave={saveAndLeave} onDiscard={discardAndLeave}
            patchSetting={patchProfileSetting} {duplicateActive} {shareTemplate} {routineAction} {createWebhookRoutine} {toggleSkill} {clearMemory} {openModal}
          />
        {/if}
      </div>
    </div>
  </aside>
{/if}

<style>
  /* The workspace grid's third track (style.css sizes it); a sheet over the chat on narrow screens. */
  .side-panel {
    grid-column: 3;
    grid-row: 1;
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
    border-left: 1px solid var(--sidebar-line);
    background: var(--sidebar);
    outline: none;
  }
  .side-bar { display: flex; justify-content: flex-end; flex-shrink: 0; padding: 12px 12px 0; }
  .files-title { padding: 0 20px 8px; color: var(--text); font: 600 20px/1.25 var(--font); }
  .side-scroll { flex: 1; min-height: 0; overflow-y: auto; overscroll-behavior: contain; }
  @media (max-width: 1200px) {
    .side-panel {
      position: absolute;
      inset: 0 0 0 auto;
      z-index: 15;
      width: min(var(--side-panel-width), 100%);
      box-shadow: var(--shadow-sheet);
    }
  }
  @media (max-width: 820px) {
    .side-panel { position: fixed; inset: 0; z-index: 32; width: 100%; border-left: 0; box-shadow: none; }
    .side-bar { padding-top: max(12px, env(safe-area-inset-top)); }
  }
</style>
