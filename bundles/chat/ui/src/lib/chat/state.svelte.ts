import { MAX_GROUP_CHATS, terminalRunStates as terminalRunStateList } from '../constants.ts'
import { openSettings } from '../settingsSections.ts'
import { PANEL_TABS } from '../sidePanel.ts'
import type { Agent, Run, Session } from '../types.ts'
import type { ChatState } from './stateShape.ts'

export const chat: ChatState = $state({
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
  provisioningPoll: undefined,
})

export const uploadControllers = new Map<string, AbortController>()
export const runCursors = new Map<string, number>()
export const refreshedRuns = new Set<string>()
export const terminalRunStates: ReadonlySet<string> = new Set(terminalRunStateList)
export const computerVersions = new Map<string, number>()
export const requests = new Set<AbortController>()
export const historyVersions = new Map<string, number>()

export function selectedAgent(): Agent | undefined {
  return chat.agents.find(agent => agent.id === chat.selectedId)
}

export function selectedRun(): Run | undefined {
  return (chat.agentRuns[chat.selectedId] || [])[0]
}

export function runIsActive(run: Run | undefined = selectedRun()): boolean {
  return Boolean(run && !terminalRunStates.has(run.state))
}

export function readyBots(): Agent[] {
  return chat.agents.filter(agent => agent.kind !== 'team' && ['idle', 'running'].includes(agent.status))
}

export function planLimits(): Session['limits'] | undefined {
  return chat.session?.limits
}

export function agentLimitReached(): boolean {
  const limits = planLimits()
  const bots = chat.agents.filter(agent => agent.kind !== 'team')
  return limits !== undefined && Number.isInteger(limits.maxAgents) && bots.length >= limits.maxAgents
}

export function storageBlocked(): boolean {
  return chat.storage?.canCreateAgent === false
}

export function createBlocked(): boolean {
  return agentLimitReached() || storageBlocked() || !chat.storage
}

export function teamLimitReached(): boolean {
  return chat.agents.filter(agent => agent.kind === 'team').length >= MAX_GROUP_CHATS
}

export function createTeamBlocked(): boolean {
  return teamLimitReached() || readyBots().length < 2 || storageBlocked() || !chat.storage
}

export function waitlisted(): boolean {
  return chat.session?.user?.access === 'waitlisted'
}

export function fileSession(key: string | null | undefined): boolean {
  return chat.alive && chat.session !== null && chat.session.csrf === key
}

/** The signed-in session; a screen that needs one is only shown once it exists. */
export function requireSession(): Session {
  if (!chat.session) throw new Error('You are signed out. Sign in again.')
  return chat.session
}
