<script>
  import BootScreen from './components/BootScreen.svelte'
  import LoginScreen from './components/auth/LoginScreen.svelte'
  import OnboardingScreen from './components/auth/OnboardingScreen.svelte'
  import WaitlistScreen from './components/auth/WaitlistScreen.svelte'
  import Rail from './components/chrome/Rail.svelte'
  import ConversationMain from './components/chat/ConversationMain.svelte'
  import SidePanel from './components/sidepanel/SidePanel.svelte'
  import LiveComputer from './components/workspace/LiveComputer.svelte'
  import WorkspaceModals from './components/account/WorkspaceModals.svelte'

  import { onMount } from 'svelte'
  import {
    chat,
    askKeydown,
    cancelRun,
    cancelUpload,
    clickComputer,
    cancelAppConnect,
    finishAppConnect,
    closeComputer,
    createdRoutineAction,
    composerKey,
    computerAction,
    decideRunApproval,
    dropFiles,
    duplicateAgent,
    findMessage,
    initialize,
    installChatEffects,
    mountChatLifecycle,
    loadAgents,
    loadHistory,
    loadStorageGate,
    logout,
    mentionBot,
    openMentionPicker,
    openModal,
    openProfile,
    openFiles,
    openComputer,
    openTeachSheet,
    pasteImages,
    patchRoster,
    pickSkill,
    redeemInvite,
    resolveCard,
    saveOnboarding,
    scrollToLatest,
    selectAgent,
    sendMessage,
    sendThreadReply,
    skipAsk,
    startNewBot,
    submitAsk,
    teachTask,
    loadSkills,
    toggleSidePanel,
    SIDE_PANEL_ID,
    toggleAskOption,
    toggleDictation,
    toggleReaction,
    trackScroll,
    uploadFiles,
    openFindOnShortcut,
    WorkspaceView,
  } from './lib/chatApp.svelte.js'

  // $effect must register during component init — not at module import time.
  installChatEffects()
  onMount(mountChatLifecycle)

  // Every derived value the panels read lives in one place so App stays a thin layout shell.
  const view = new WorkspaceView()
  const focusComposer = () => chat.composer?.focus()
  const openFilesFromComputer = () => closeComputer().then(openFiles)
</script>

<svelte:window onkeydown={openFindOnShortcut} />


{#if chat.booting}
  <BootScreen />
{:else if !chat.session}
  <LoginScreen
    googleConfigured={chat.googleConfigured}
    registrationCapacity={chat.registrationCapacity}
    bootError={chat.bootError}
    onRetry={initialize}
  />
{:else if !chat.onboarding}
  <OnboardingScreen
    bind:goal={chat.onboardingGoal}
    bind:goalDetail={chat.onboardingGoalDetail}
    bind:source={chat.onboardingSource}
    bind:sourceDetail={chat.onboardingSourceDetail}
    error={chat.onboardingError}
    saving={chat.onboardingSaving}
    onSubmit={saveOnboarding}
  />
{:else if view.waitlisted}
  <WaitlistScreen
    firstName={view.greeting}
    bind:inviteCode={chat.inviteCode}
    inviteError={chat.inviteError}
    inviteSaving={chat.inviteSaving}
    loggingOut={chat.loggingOut}
    onSubmit={redeemInvite}
    onLogout={logout}
  />
{:else}
  <div class="workspace" class:panel-open={view.panelShown}>
    {#if chat.mobileRail}<button class="rail-backdrop" aria-label="Close conversation navigation" onclick={() => chat.mobileRail = false}></button>{/if}
    <Rail
      mobileRail={chat.mobileRail}
      bind:search={chat.search}
      showHidden={chat.showHidden}
      selectedId={chat.selectedId}
      pending={chat.pending}
      bots={view.bots}
      teams={view.teams}
      readyBots={view.readyBots}
      createTeamBlocked={view.createTeamBlocked}
      teamLimitReached={view.teamLimitReached}
      agentLimitReached={view.agentLimitReached}
      storageBlocked={view.storageBlocked}
      storage={chat.storage}
      storageError={chat.storageError}
      agentsError={chat.agentsError}
      saving={chat.saving}
      session={chat.session}
      {selectAgent}
      loadStorage={loadStorageGate}
      {loadAgents}
      {openModal}
      {openProfile}
      {patchRoster}
      {duplicateAgent}
      onCloseMobile={() => chat.mobileRail = false}
      onToggleHidden={() => chat.showHidden = !chat.showHidden}
      onNewBot={startNewBot}
      activityAt={view.activityAt}
      usage={chat.usage}
      loggingOut={chat.loggingOut}
      onLogout={logout}
    />
    <ConversationMain
      active={view.active}
      greeting={view.greeting}
      selectedId={chat.selectedId}
      bind:mobileRail={chat.mobileRail}
      bind:showSearch={chat.showSearch}
      computerOpen={chat.showComputer}
      panelOpen={chat.sidePanelOpen}
      panelId={SIDE_PANEL_ID}
      bind:messageList={chat.messageList}
      bind:composer={chat.composer}
      bind:fileChooser={chat.fileChooser}
      bind:messageSearch={chat.messageSearch}
      bind:matchIndex={chat.matchIndex}
      matchingMessages={view.matchingMessages}
      matchedMessageId={view.matchedMessageId}
      atLatest={chat.atLatest}
      unreadMessages={chat.unreadMessages}
      loading={chat.loading}
      histories={chat.histories}
      errors={chat.errors}
      messages={view.messages}
      threadReplies={view.threadReplies}
      pending={chat.pending}
      bind:drafts={chat.drafts}
      draft={view.draft}
      canSend={view.canSend}
      welcomeChoices={view.welcomeChoices} typingWelcome={view.typingWelcome}
      awaitingComputer={view.awaitingComputer}
      saving={chat.saving}
      bind:createError={chat.createError}
      storageBlocked={view.storageBlocked}
      storageError={chat.storageError}
      storage={chat.storage}
      storageLoading={chat.storageLoading}
      bind:profileNotice={chat.profileNotice}
      profileVisible={view.profileVisible}
      activeAsk={view.activeAsk}
      answeredAsks={chat.answeredAsks}
      askMulti={chat.askMulti}
      askFocus={chat.askFocus}
      activeCard={view.activeCard} appResults={view.appResults}
      bind:cardSecret={chat.cardSecret}
      cardBusy={chat.cardBusy}
      takingOver={view.takingOver}
      agentLimitReached={view.agentLimitReached}
      currentRun={view.currentRun}
      runActive={view.runActive}
      runNotices={chat.runNotices}
      pendingApprovals={view.pendingApprovals} runSteps={view.runSteps} followUps={view.followUps}
      runErrors={chat.runErrors}
      bind:runActionErrors={chat.runActionErrors}
      runBusy={chat.runBusy}
      usage={chat.usage}
      bind:attachmentErrors={chat.attachmentErrors}
      bind:mentionError={chat.mentionError}
      mentionOpen={chat.mentionOpen}
      bind:mentionQuery={chat.mentionQuery}
      mentionCandidates={view.mentionCandidates}
      mentionRoutineCandidates={view.mentionRoutineCandidates}
      mentionConnectorCandidates={view.mentionConnectorCandidates}
      mentionBusy={chat.mentionBusy}
      bind:skillPickerOpen={chat.skillPickerOpen}
      bind:skillQuery={chat.skillQuery}
      skillCandidates={view.skillCandidates}
      selectedAttachments={view.selectedAttachments}
      selectedUploads={view.selectedUploads}
      bind:attachments={chat.attachments}
      dictationSupported={chat.dictationSupported}
      dictating={chat.dictating}
      bind:reconnectRun={chat.reconnectRun}
      bind:replyParent={chat.replyParent}
      bind:replyDrafts={chat.replyDrafts}
      {trackScroll}
      {findMessage}
      {scrollToLatest}
      loadStorage={loadStorageGate}
      {loadHistory}
      {openModal}
      {startNewBot}
      {openProfile}
      {openFiles}
      {openComputer}
      {openTeachSheet}
      {toggleSidePanel}
      {sendMessage}
      {composerKey}
      {pasteImages}
      {dropFiles}
      {uploadFiles}
      {cancelUpload}
      {openMentionPicker}
      {mentionBot}
      {pickSkill}
      {toggleDictation}
      {toggleReaction}
      {sendThreadReply}
      {toggleAskOption}
      {submitAsk}
      {skipAsk}
      {askKeydown}
      {resolveCard}
      {cancelRun}
      {decideRunApproval}
      createdRoutine={chat.createdRoutine}
      routineAction={createdRoutineAction}
      computerLive={view.computerLive}
      computerImage={view.computerImage}
      members={view.members}
      {loadSkills}
    />
    <SidePanel {view} />
    <LiveComputer
      open={chat.showComputer}
      active={view.active}
      pending={chat.pending}
      takingOver={view.takingOver}
      connectingApp={chat.connectingApp}
      connectProbeError={chat.connectProbeError}
      onFinishConnect={finishAppConnect}
      onCancelConnect={cancelAppConnect}
      bind:url={chat.computerUrl}
      bind:text={chat.computerText}
      bind:teachOpen={chat.teachOpen}
      bind:teachName={chat.teachName}
      bind:teachDescription={chat.teachDescription}
      busy={Boolean(chat.computerBusy[view.deskKey] || chat.checkingAppId)}
      error={chat.computerErrors[view.deskKey] || ''}
      updated={chat.computerUpdated[view.deskKey] || ''}
      image={view.computerImage}
      message={view.computer.message || ''}
      pageUrl={view.computer.url || ''}
      desktop={chat.desktops[view.deskKey] || null}
      settingUp={chat.environment?.state === 'provisioning'}
      onClose={closeComputer}
      onOpenFiles={openFilesFromComputer}
      onAction={computerAction}
      onClickScreenshot={clickComputer}
      onTeach={teachTask}
      onFocusChat={focusComposer}
    />
  </div>
{/if}

<WorkspaceModals {view} />
