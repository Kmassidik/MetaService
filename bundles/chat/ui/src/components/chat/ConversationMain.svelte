<script>
  import { tick } from 'svelte'
  import ConversationHeader from './ConversationHeader.svelte'
  import ConversationSearch from './ConversationSearch.svelte'
  import EmptyState from './EmptyState.svelte'
  import BotStatus from './BotStatus.svelte'
  import ThreadIntro from './ThreadIntro.svelte'
  import MessageList from './MessageList.svelte'
  import MessageFiles from './MessageFiles.svelte'
  import MentionPicker from './MentionPicker.svelte'
  import SkillPicker from './SkillPicker.svelte'
  import Composer from './Composer.svelte'
  import ComposerNotices from './ComposerNotices.svelte'
  import RunCards from './cards/RunCards.svelte'
  import StatusLine from './cards/StatusLine.svelte'
  import ProfileNoticeCard from './cards/ProfileNoticeCard.svelte'
  import RoutineCreatedCard from './cards/RoutineCreatedCard.svelte'
  import WelcomeChoices from './cards/WelcomeChoices.svelte'
  import TypingBubble from './TypingBubble.svelte'
  import QueuedFollowUps from './QueuedFollowUps.svelte'
  import SetupStatus from './cards/SetupStatus.svelte'
  import { approveFromChat } from './cards/approveFromChat.js'
  import { statusLabel } from './cards/statusLabel.js'
  import { MODALS } from '../../lib/constants.js'
  import { isDraftBot } from '../../lib/chat/draftBots.js'
  import { SEND_MODE, sendMode } from '../../lib/sendMode.js'

  // A bot still being set up opens its chat at once; only a failed one gets a whole-pane state.
  const FAILED = 'failed'
  const BOT_WORKING = 'running'
  const TOOLLESS_BOT_STATES = ['provisioning', FAILED]
  const NO_STEPS = { live: [], byReply: {} }

  let {
    active = null, greeting = 'there', selectedId = '',
    mobileRail = $bindable(false), showSearch = $bindable(false), computerOpen = false, panelOpen = false, panelId = '',
    messageList = $bindable(null), composer = $bindable(null), fileChooser = $bindable(null),
    messageSearch = $bindable(''), matchIndex = $bindable(0), matchingMessages = [], matchedMessageId = undefined,
    atLatest = true, unreadMessages = false, loading = {}, histories = {}, errors = {},
    messages = [], threadReplies = [], pending = null, drafts = $bindable({}), draft = '', canSend = false,
    welcomeChoices = null, typingWelcome = false, awaitingComputer = false, saving = false, createError = $bindable(''),
    storageBlocked = false, storageError = '', storage = null, storageLoading = false,
    profileNotice = $bindable(''), profileVisible = false,
    activeAsk = null, answeredAsks = {}, askMulti = {}, askFocus = -1,
    activeCard = null, appResults = [], cardSecret = $bindable(''), cardBusy = '', takingOver = false, agentLimitReached = false,
    currentRun = null, runActive = false, runNotices = {}, pendingApprovals = [], runSteps = NO_STEPS, followUps = [], runErrors = {},
    runActionErrors = $bindable({}), runBusy = {}, usage = null,
    attachmentErrors = $bindable({}), mentionError = $bindable(''),
    mentionOpen = false, mentionQuery = $bindable(''), mentionCandidates = [], mentionRoutineCandidates = [],
    mentionConnectorCandidates = [], mentionBusy = false,
    skillPickerOpen = $bindable(false), skillQuery = $bindable(''), skillCandidates = [],
    selectedAttachments = [], selectedUploads = [], attachments = $bindable({}),
    dictationSupported = false, dictating = false, reconnectRun = $bindable(0),
    replyParent = $bindable(''), replyDrafts = $bindable({}),
    // Optional, for the status thumbnail and group pill faces.
    computerLive = false, computerImage = '', members = [], decideRunApproval = null,
    // Optional, for the routine card: the routine just created and its Pause/Resume handler.
    createdRoutine = null, routineAction = null,
    trackScroll, findMessage, scrollToLatest, loadStorage, loadHistory, openModal, startNewBot,
    openProfile, openFiles, openComputer, openTeachSheet, toggleSidePanel, sendMessage, composerKey, pasteImages, dropFiles, uploadFiles,
    cancelUpload, openMentionPicker, mentionBot, pickSkill, toggleDictation, toggleReaction, sendThreadReply,
    toggleAskOption, submitAsk, skipAsk, askKeydown, resolveCard, cancelRun, loadSkills,
  } = $props()

  let skillError = $state('')

  const history = $derived(histories[selectedId])
  const paneView = $derived(botPaneView())
  const sendingHere = $derived(pending?.id === selectedId)
  const askLocked = $derived(Boolean(activeAsk && (answeredAsks[activeAsk.askId] || pending || usage?.blocked || runBusy[activeAsk.runId])))
  const toolsDisabled = $derived(Boolean(pending || mentionBusy || usage?.blocked || TOOLLESS_BOT_STATES.includes(active?.status)))
  const blockReason = $derived(storageBlocked || storageError ? (storage?.creationBlockedReason || storageError) : '')
  const status = $derived(active && statusLabel({
    name: active.name, run: currentRun, runActive, sending: sendingHere,
    waitingForAnswer: Boolean(activeAsk) && !askLocked, waitingForInput: Boolean(activeCard) && !cardBusy,
    approvalPending: pendingApprovals.length > 0,
    computerLive, notice: runNotices[currentRun?.id],
  }))
  const showRoutineCard = $derived(Boolean(createdRoutine && routineAction && createdRoutine.agentId === selectedId && !profileVisible))
  // A draft is the instant before the server's welcome lands; it stays blank rather than flash an intro.
  const showIntro = $derived(!messages.length && !typingWelcome && !activeAsk && !activeCard && !isDraftBot(selectedId))
  const welcomeLocked = $derived(Boolean(pending || usage?.blocked))
  const followUpMode = $derived(sendMode({ runActive, runState: currentRun?.state, botBusy: active?.status === BOT_WORKING }) === SEND_MODE.followUp)

  function botPaneView() {
    if (!active) return 'empty'
    if (active.status === FAILED) return FAILED
    if (loading[selectedId] && !history) return 'loading'
    if (!history && errors[selectedId]) return 'error'
    return 'chat'
  }

  function openSkillPicker() {
    closeMentions()
    skillPickerOpen = true
    skillError = ''
    return loadSkills().then(message => { skillError = message })
  }

  // openMentionPicker toggles, so it is only called when the state actually needs to flip.
  function openMentions() {
    if (!mentionOpen) openMentionPicker()
  }

  function closeMentions() {
    mentionQuery = ''
    if (mentionOpen) openMentionPicker()
  }

  function closeSkills() {
    skillPickerOpen = false
    skillQuery = ''
  }

  async function closeSearch() {
    showSearch = false
    messageSearch = ''
    await tick()
    composer?.focus()
  }

  function openProfileFromNotice() {
    profileNotice = ''
    openProfile()
  }

  const menuActions = {
    onFiles: () => openFiles(),
    onSkills: openSkillPicker,
    onMention: openMentions,
    onTeach: () => openTeachSheet(),
    onFind: () => { showSearch = true },
    onConnect: () => openModal(MODALS.marketplace),
    onHelp: () => openModal(MODALS.help),
  }
</script>

<main class="main-workspace">
  <ConversationHeader
    {active}
    bind:mobileRail
    {members}
    {panelOpen}
    {panelId}
    onOpenDetails={openProfile}
    onTogglePanel={toggleSidePanel}
  />
  {#if active && showSearch}
    <ConversationSearch bind:query={messageSearch} bind:matchIndex matchCount={matchingMessages.length} {findMessage} onClose={closeSearch} />
  {/if}
  <div class="conversation-body" bind:this={messageList} onscroll={trackScroll} aria-busy={Boolean(loading[selectedId])}>
    {#if paneView === 'empty'}
      <EmptyState {greeting} {saving} {createError} {blockReason} {storageLoading} {loadStorage} {startNewBot} />
    {:else if paneView !== 'chat'}
      <BotStatus view={paneView} {active} error={errors[selectedId]} onManage={() => openModal(MODALS.edit)} onReload={() => loadHistory(selectedId)} />
    {:else}
      <div class="thread">
        <MessageList {messages} {threadReplies} {active} {matchedMessageId} replySteps={runSteps.byReply} bind:replyParent bind:replyDrafts {toggleReaction} {sendThreadReply} onViewResults={openFiles} />
        {#if sendingHere}
          <div class="pending" aria-label="Sending message"><div class="pending-bubble">{pending.text}</div><MessageFiles items={pending.attachments || []} onViewResults={openFiles} /></div>
        {/if}
        <QueuedFollowUps items={followUps} botName={active.name} />
        <RunCards
          {activeAsk} {answeredAsks} {askMulti} {askFocus} {askLocked}
          {activeCard} {appResults} bind:cardSecret {cardBusy} {takingOver} {agentLimitReached}
          {pendingApprovals} approvalBusy={Boolean(runBusy[currentRun?.id])}
          {toggleAskOption} {submitAsk} {skipAsk} {askKeydown} {resolveCard}
          onApproveApproval={decideRunApproval ? approval => approveFromChat(approval, decideRunApproval) : null}
          onDenyApproval={decideRunApproval ? approval => decideRunApproval(approval, 'deny') : null}
        />
        {#if typingWelcome}<TypingBubble />{/if}
        {#if welcomeChoices && !sendingHere}
          <WelcomeChoices choices={welcomeChoices} locked={welcomeLocked} onPick={text => sendMessage(null, text)} />
        {/if}
        {#if showIntro}<ThreadIntro {active} />{/if}
        {#if showRoutineCard}
          <RoutineCreatedCard routine={createdRoutine} onAction={routineAction} onOpen={openProfile} />
        {:else if profileNotice && !profileVisible}
          <ProfileNoticeCard notice={profileNotice} onOpen={openProfileFromNotice} onDismiss={() => profileNotice = ''} />
        {/if}
        {#if awaitingComputer}
          <SetupStatus />
        {:else if status}
          <StatusLine
            {status}
            steps={runSteps.live}
            thumbnail={computerLive ? computerImage : ''}
            canStop={runActive}
            stopDisabled={Boolean(runBusy[currentRun?.id]) || currentRun?.state === 'cancelling'}
            onStop={cancelRun}
            onOpenComputer={openComputer}
          />
        {/if}
      </div>
    {/if}
  </div>
  {#if active}
    <div class="composer-dock">
      {#if !atLatest || unreadMessages}
        <button type="button" class="jump" onclick={scrollToLatest}>{unreadMessages ? 'New messages' : 'Jump to latest'}</button>
      {/if}
      <ComposerNotices
        {selectedId} {runErrors} bind:runActionErrors bind:attachmentErrors bind:mentionError
        historyError={history ? errors[selectedId] : ''}
        bind:createError
        historyReloadDisabled={Boolean(pending) || loading[selectedId]}
        usageBlocked={usage?.blocked}
        otherBotBusy={Boolean(pending) && !sendingHere}
        {takingOver}
        {computerOpen}
        onReconnect={() => reconnectRun += 1}
        onReloadHistory={() => loadHistory(selectedId)}
        onOpenComputer={openComputer}
      />
      <MentionPicker
        open={mentionOpen} bind:query={mentionQuery}
        bots={mentionCandidates} routines={mentionRoutineCandidates} connectors={mentionConnectorCandidates}
        busy={mentionBusy} pending={Boolean(pending)} everyone={active.kind === 'team'}
        onSelect={mentionBot} onClose={closeMentions}
      />
      <SkillPicker
        open={skillPickerOpen} bind:query={skillQuery} error={skillError}
        skills={skillCandidates}
        onPick={pickSkill} onClose={closeSkills}
      />
      <Composer
        botName={active.name} {selectedId} {draft} bind:drafts bind:composer bind:fileChooser bind:attachments
        {selectedAttachments} {selectedUploads} {canSend} sending={sendingHere} locked={Boolean(pending)} {toolsDisabled} followUp={followUpMode}
        {dictationSupported} {dictating}
        {sendMessage} {composerKey} {pasteImages} {dropFiles} {uploadFiles} {cancelUpload} {toggleDictation}
        onSkillTrigger={openSkillPicker} onMentionTrigger={openMentions} {menuActions}
      />
    </div>
  {/if}
</main>

<style>
  /* The reference's column: messages and composer share one 960 pt column (bubbles stay 560). */
  main { --chat-column: 960px; --chat-gutter: 28px; }
  .thread { display: flex; flex-direction: column; width: 100%; max-width: calc(var(--chat-column) + 2 * var(--chat-gutter)); margin: 0 auto; padding: 8px var(--chat-gutter) 32px; }
  .pending { display: flex; flex-direction: column; align-items: flex-end; margin-top: 12px; opacity: .72; }
  .pending-bubble {
    max-width: min(560px, 100%); padding: 12px 16px; border-radius: var(--radius-bubble);
    background: var(--ink); color: var(--on-ink);
    font: 400 var(--fs-message)/var(--lh-message) var(--font); white-space: pre-wrap; overflow-wrap: anywhere;
  }
  .composer-dock { position: relative; width: 100%; max-width: calc(var(--chat-column) + 2 * var(--chat-gutter)); margin: 0 auto; padding: 8px var(--chat-gutter) 20px; flex-shrink: 0; }
  .jump {
    position: absolute; bottom: calc(100% + 4px); left: 50%; transform: translateX(-50%);
    padding: 7px 14px; border: 1px solid var(--hairline); border-radius: var(--radius-pill);
    background: var(--surface); box-shadow: var(--shadow-float); color: var(--text); font: 500 var(--fs-preview)/1.3 var(--font); cursor: pointer;
  }
  @media (max-width: 820px) {
    .thread { padding: 8px 16px 24px; }
    .composer-dock { padding: 6px 12px calc(12px + env(safe-area-inset-bottom)); }
  }
</style>
