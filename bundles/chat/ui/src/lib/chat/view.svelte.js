/**
 * Derived, read-only state for App.svelte's panels. App builds one WorkspaceView during component
 * init, so every `$derived` below is owned by the App component and torn down with it.
 */
import { instructionPresets } from '../constants.js'
import { isConnectable, pluginById } from '../marketplace.js'
import { offeredApps } from '../apps.js'
import { runSteps, stepsByReply } from '../runSteps.js'
import { waitingFollowUps } from '../sendMode.js'
import { chat } from './state.svelte.js'
import * as gates from './state.svelte.js'
import * as runs from './runs.svelte.js'
import * as transcript from './messages.svelte.js'
import * as desk from './computer.svelte.js'
import { validateTeam } from './agents.svelte.js'
import * as select from './selectors.js'
import { previewStreamSource } from '../../components/workspace/deskStatus.js'
import * as panel from '../sidePanel.js'

const NO_COMPUTER = { state: 'unavailable', message: 'Live computer preview is not connected.' }
const TEAM_FORM = 'team'
const DELETING_STATE = 'deleting'

const pluginName = id => pluginById(id)?.name || id

export class WorkspaceView {
  // Session and plan
  waitlisted = $derived(gates.waitlisted())
  planLimits = $derived(gates.planLimits())
  greeting = $derived(select.firstName(chat.session))

  // Roster and creation gates
  bots = $derived(select.botsOf(chat.agents))
  teams = $derived(select.teamsOf(chat.agents))
  readyBots = $derived(gates.readyBots())
  active = $derived(chat.agents.find(agent => agent.id === chat.selectedId))
  members = $derived(select.groupMembers(this.active, this.bots))
  activityAt = $derived(select.activityByAgent(chat.histories))
  connectedApps = $derived(select.connectedApps(offeredApps(chat.computerApps, isConnectable), chat.mentionConnectors || [], pluginName))
  agentLimitReached = $derived(gates.agentLimitReached())
  storageBlocked = $derived(gates.storageBlocked())
  createBlocked = $derived(gates.createBlocked())
  teamLimitReached = $derived(gates.teamLimitReached())
  createTeamBlocked = $derived(gates.createTeamBlocked())

  // Conversation
  history = $derived(chat.histories[chat.selectedId] || [])
  messages = $derived(select.visibleMessages(this.history))
  threadReplies = $derived(select.threadRepliesOf(this.history))
  welcomeChoices = $derived(select.openWelcomeChoices(this.messages))
  typingWelcome = $derived(Boolean(chat.selectedId) && chat.typingWelcomeId === chat.selectedId)
  awaitingComputer = $derived(select.isAwaitingComputer(this.active, chat.pending?.id))
  draft = $derived(chat.drafts[chat.selectedId] || '')
  canSend = $derived(transcript.canSendMessage())
  matchingMessages = $derived(transcript.matchingMessages())
  matchedMessageId = $derived(this.matchingMessages[chat.matchIndex]?.id)
  selectedAttachments = $derived(chat.attachments[chat.selectedId] || [])
  selectedUploads = $derived(chat.uploads.filter(upload => upload.agentId === chat.selectedId))
  uploadLocked = $derived(Boolean(!this.active || chat.pending || chat.loggingOut || chat.environmentAction || chat.environment?.state === DELETING_STATE))

  // Pickers
  mentionCandidates = $derived(select.mentionBots(this.active, this.readyBots, chat.mentionQuery))
  mentionRoutineCandidates = $derived(select.mentionRoutines(chat.mentionRoutines, chat.mentionQuery))
  mentionConnectorCandidates = $derived(select.mentionConnectors(chat.mentionConnectors, chat.mentionQuery))
  skillCandidates = $derived(select.skillMatches(chat.profileSkills, chat.skillQuery))

  // Runs and cards
  currentRun = $derived(gates.selectedRun())
  runActive = $derived(gates.runIsActive(this.currentRun))
  pendingApprovals = $derived(select.pendingApprovals(chat.runApprovals[this.currentRun?.id]))
  // "Show steps": the live run's steps for the status line, and each finished run's under its reply.
  runSteps = $derived({
    live: this.runActive ? runSteps(chat.runEvents[this.currentRun?.id]) : [],
    byReply: stepsByReply(this.messages, chat.agentRuns[chat.selectedId], chat.runEvents),
  })
  // Messages typed while the bot worked, until its next turn shows them in the chat.
  followUps = $derived(waitingFollowUps(chat.followUps[chat.selectedId], this.history, chat.agentRuns[chat.selectedId]))
  activeAsk = $derived(runs.activeAsk())
  activeCard = $derived(runs.activeCard())
  appResults = $derived(runs.appResultCards())

  // Computer and environment
  deskKey = $derived(chat.connectingApp ? desk.ACCOUNT_COMPUTER : chat.selectedId)
  computer = $derived(chat.computers[this.deskKey] || NO_COMPUTER)
  computerImage = $derived(select.safeComputerImage(this.computer))
  computerLive = $derived(select.isComputerOn(this.computer))
  takingOver = $derived(select.isTakenOver(this.computer))
  hasTakeover = $derived(Object.values(chat.computers).some(select.isTakenOver))
  environmentBusy = $derived(desk.environmentBusy())
  environmentTransitioning = $derived(desk.environmentTransitioning())
  environmentState = $derived(select.environmentLabel(chat.environment))

  // Side panel (P6): its tabs and the Computer tab's preview of the selected bot's screen
  panelTabs = $derived(panel.panelTabs(this.active))
  panelTab = $derived(panel.resolveTab(chat.sidePanelTab, this.active))
  panelShown = $derived(panel.isPanelShown({ open: chat.sidePanelOpen, active: this.active, tab: chat.sidePanelTab }))
  profileVisible = $derived(chat.sidePanelOpen && this.panelTab === panel.PANEL_TABS.details)
  previewComputer = $derived(chat.computers[chat.selectedId] || NO_COMPUTER)
  previewImage = $derived(select.safeComputerImage(this.previewComputer))
  previewStream = $derived(previewStreamSource(this.previewComputer))
  previewLine = $derived(panel.previewStatus({
    botName: this.active?.name || '',
    environmentState: chat.environment?.state,
    takingOver: select.isTakenOver(this.previewComputer),
    runActive: this.runActive,
  }))

  // Create and edit forms
  teamFormError = $derived(chat.formKind === TEAM_FORM ? validateTeam() : '')
  selectedPreset = $derived(instructionPresets.find(preset => preset.id === chat.presetId))
}
