import { MAX_GROUP_CHATS, terminalRunStates as terminalRunStateList } from '../constants.js'
import { openSettings } from '../settingsSections.js'
import { PANEL_TABS } from '../sidePanel.js'

export const chat = $state({
  session: null,
  booting: true,
  bootError: '',
  googleConfigured: null,
  registrationCapacity: null,
  storage: null,
  storageLoading: false,
  storageError: '',
  onboarding: null,
  onboardingGoal: '',
  onboardingGoalDetail: '',
  onboardingSource: '',
  onboardingSourceDetail: '',
  onboardingError: '',
  onboardingSaving: false,
  inviteCode: '',
  inviteError: '',
  inviteSaving: false,
  environment: null,
  environmentLoading: false,
  environmentAction: '',
  environmentError: '',
  environmentRefreshError: '',
  environmentNotice: '',
  confirmEnvironmentDeletion: false,
  environmentConfirmation: '',
  agents: [],
  agentsError: '',
  usage: null,
  usageError: '',
  selectedId: '',
  search: '',
  histories: {},
  computers: {},
  desktops: {},
  loading: {},
  errors: {},
  drafts: {},
  pending: null,
  mentionOpen: false,
  mentionQuery: '',
  mentionBusy: false,
  mentionError: '',
  mentionRoutines: [],
  mentionConnectors: [],
  nangoEnabled: false,
  nangoConnections: [],
  computerApps: [],
  appsError: '',
  checkingAppId: '',
  connectingApp: null,
  connectProbeError: '',
  nangoIntegrations: [],
  webhookNotice: '',
  dictationSupported: false,
  dictating: false,
  recognition: null,
  mobileRail: false,
  // The big computer view (Open from the side panel, Connect apps, a takeover card).
  showComputer: false,
  // 3D Workspace page (/workspace). Separate from showComputer.
  sidePanelOpen: false,
  sidePanelTab: PANEL_TABS.details,
  showSearch: false,
  files: [],
  filesLoading: false,
  filesError: '',
  deletingFile: '',
  attachments: {},
  attachmentErrors: {},
  uploads: [],
  fileChooser: null,
  agentRuns: {},
  runEvents: {},
  runApprovals: {},
  reviewedApprovals: {},
  runErrors: {},
  runActionErrors: {},
  runBusy: {},
  runNotices: {},
  // Agent id → follow-ups typed while its task ran ({ id, runId, text, confirmed }).
  followUps: {},
  reconnectRun: 0,
  computerUrl: 'https://example.com',
  computerText: '',
  computerErrors: {},
  computerBusy: {},
  computerUpdated: {},
  modal: null,
  settings: openSettings(),
  editId: '',
  formName: '',
  formDescription: '',
  formKind: 'bot',
  formLeadId: '',
  formMemberIds: [],
  presetId: '',
  presetNotice: '',
  formError: '',
  createError: '',
  // The new bot whose welcome is still "typing" (see newBot.svelte.js).
  typingWelcomeId: '',
  saving: false,
  profileHighlight: {},
  profileNotice: '',
  profileSaving: false,
  profileError: '',
  // Controls showing a brief "Saved" tick (details, label, avatar, notifications, skills); see savedFlash.js.
  profileSaved: {},
  // The inline "You have unsaved changes — Save / Discard" prompt (unsavedGuard.svelte.js).
  unsavedPrompt: false,
  profileName: '',
  profileTitle: '',
  profileSummary: '',
  profileInstructions: '',
  profileRoutines: [],
  // The routine a bot just created in chat (routine card); cleared when the owner sends again.
  createdRoutine: null,
  profileSkills: [],
  profileMemory: [],
  // Lives here (not in LiveComputer) so the composer's + → Teach a task can open it directly.
  teachOpen: false,
  teachName: '',
  teachDescription: '',
  skillPickerOpen: false,
  skillQuery: '',
  answeredAsks: {},
  askMulti: {},
  askFocus: -1,
  loggingOut: false,
  confirmAccountDeletion: false,
  accountConfirmation: '',
  accountDeletionError: '',
  deletingAccount: false,
  messageList: null,
  composer: null,
  messageSearch: '',
  matchIndex: 0,
  atLatest: true,
  unreadMessages: false,
  resolvedCards: {},
  cardSecret: '',
  cardBusy: '',
  replyDrafts: {},
  replyParent: '',
  showHidden: false,
  environmentVersion: 0,
  agentsVersion: 0,
  fileVersion: 0,
  dialog: null,
  formSessionKey: null,
  alive: true,
  provisioningPoll: null,
})

export const uploadControllers = new Map()
export const runCursors = new Map()
export const refreshedRuns = new Set()
export const terminalRunStates = new Set(terminalRunStateList)
export const computerVersions = new Map()
export const requests = new Set()
export const historyVersions = new Map()

export function selectedAgent() {
  return chat.agents.find(agent => agent.id === chat.selectedId)
}

export function selectedRun() {
  return (chat.agentRuns[chat.selectedId] || [])[0]
}

export function runIsActive(run = selectedRun()) {
  return Boolean(run && !terminalRunStates.has(run.state))
}

export function readyBots() {
  return chat.agents.filter(agent => agent.kind !== 'team' && ['idle', 'running'].includes(agent.status))
}

export function planLimits() {
  return chat.session?.limits
}

export function agentLimitReached() {
  const limits = planLimits()
  const bots = chat.agents.filter(agent => agent.kind !== 'team')
  return Number.isInteger(limits?.maxAgents) && bots.length >= limits.maxAgents
}

export function storageBlocked() {
  return chat.storage?.canCreateAgent === false
}

export function createBlocked() {
  return agentLimitReached() || storageBlocked() || !chat.storage
}

export function teamLimitReached() {
  return chat.agents.filter(agent => agent.kind === 'team').length >= MAX_GROUP_CHATS
}

export function createTeamBlocked() {
  return teamLimitReached() || readyBots().length < 2 || storageBlocked() || !chat.storage
}

export function waitlisted() {
  return chat.session?.user?.access === 'waitlisted'
}

export function fileSession(key) {
  return chat.alive && Boolean(chat.session) && chat.session.csrf === key
}
