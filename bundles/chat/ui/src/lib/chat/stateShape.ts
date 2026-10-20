/** Every piece of chat state, in one record: `chat` in state.svelte.ts holds it. */
import type { Dict } from '../check.ts'
import type { SettingsState } from '../settingsSections.ts'
import type { PanelTab } from '../sidePanel.ts'
import type {
  AccountStorage, Agent, AppRecord, Approval, ChatFile, ChatMessage, ComputerInfo, ConnectingApp, Connector,
  Desktop, Environment, FollowUp, HostState, MemoryEntry, Onboarding, PendingSend, Routine, Run, RunEvent,
  Session, Skill, Upload, Usage,
} from '../types.ts'
import type { SpeechRecognitionLike } from './speech.ts'

export type FormKind = 'bot' | 'team'

export interface ChatState {
  session: Session | null
  booting: boolean
  bootError: string
  googleConfigured: boolean | null
  registrationCapacity: HostState | null
  storage: AccountStorage | null
  storageLoading: boolean
  storageError: string
  onboarding: Onboarding | null
  onboardingGoal: string
  onboardingGoalDetail: string
  onboardingSource: string
  onboardingSourceDetail: string
  onboardingError: string
  onboardingSaving: boolean
  inviteCode: string
  inviteError: string
  inviteSaving: boolean
  environment: Environment | null
  environmentLoading: boolean
  environmentAction: string
  environmentError: string
  environmentRefreshError: string
  environmentNotice: string
  confirmEnvironmentDeletion: boolean
  environmentConfirmation: string
  agents: Agent[]
  agentsError: string
  usage: Usage | null
  usageError: string
  selectedId: string
  search: string
  histories: Dict<ChatMessage[]>
  computers: Dict<ComputerInfo>
  desktops: Dict<Desktop>
  loading: Dict<boolean>
  errors: Dict<string>
  drafts: Dict<string>
  pending: PendingSend | null
  mentionOpen: boolean
  mentionQuery: string
  mentionBusy: boolean
  mentionError: string
  mentionRoutines: Routine[]
  mentionConnectors: Connector[]
  nangoEnabled: boolean
  nangoConnections: unknown[]
  computerApps: AppRecord[]
  appsError: string
  checkingAppId: string
  connectingApp: ConnectingApp | null
  connectProbeError: string
  nangoIntegrations: unknown[]
  webhookNotice: string
  dictationSupported: boolean
  dictating: boolean
  recognition: SpeechRecognitionLike | null
  mobileRail: boolean
  /** The big computer view (Open from the side panel, Connect apps, a takeover card). */
  showComputer: boolean
  sidePanelOpen: boolean
  sidePanelTab: PanelTab
  showSearch: boolean
  files: ChatFile[]
  filesLoading: boolean
  filesError: string
  deletingFile: string
  attachments: Dict<ChatFile[]>
  attachmentErrors: Dict<string>
  uploads: Upload[]
  fileChooser: HTMLInputElement | null
  agentRuns: Dict<Run[]>
  runEvents: Dict<RunEvent[]>
  runApprovals: Dict<Approval[]>
  /** Approval id → the parameters hash the owner reviewed. */
  reviewedApprovals: Dict<string>
  runErrors: Dict<string>
  runActionErrors: Dict<string>
  runBusy: Dict<string>
  runNotices: Dict<string>
  /** Agent id → follow-ups typed while its task ran. */
  followUps: Dict<FollowUp[]>
  reconnectRun: number
  computerUrl: string
  computerText: string
  computerErrors: Dict<string>
  computerBusy: Dict<boolean>
  computerUpdated: Dict<string>
  modal: string | null
  settings: SettingsState
  editId: string
  formName: string
  formDescription: string
  formKind: FormKind
  formLeadId: string
  formMemberIds: string[]
  presetId: string
  presetNotice: string
  formError: string
  createError: string
  /** The new bot whose welcome is still "typing" (see newBot.svelte.ts). */
  typingWelcomeId: string
  saving: boolean
  profileHighlight: Dict<boolean>
  profileNotice: string
  profileSaving: boolean
  profileError: string
  /** Controls showing a brief "Saved" tick (details, label, avatar, notifications, skills); see savedFlash.ts. */
  profileSaved: Dict<boolean>
  /** The inline "You have unsaved changes — Save / Discard" prompt (unsavedGuard.svelte.ts). */
  unsavedPrompt: boolean
  profileName: string
  profileTitle: string
  profileSummary: string
  profileInstructions: string
  profileRoutines: Routine[]
  /** The routine a bot just created in chat (routine card); cleared when the owner sends again. */
  createdRoutine: Routine | null
  profileSkills: Skill[]
  profileMemory: MemoryEntry[]
  teachOpen: boolean
  teachName: string
  teachDescription: string
  skillPickerOpen: boolean
  skillQuery: string
  answeredAsks: Dict<string[]>
  askMulti: Dict<string[]>
  askFocus: number
  loggingOut: boolean
  confirmAccountDeletion: boolean
  accountConfirmation: string
  accountDeletionError: string
  deletingAccount: boolean
  messageList: HTMLElement | null
  composer: HTMLElement | null
  messageSearch: string
  matchIndex: number
  atLatest: boolean
  unreadMessages: boolean
  resolvedCards: Dict<string>
  cardSecret: string
  cardBusy: string
  replyDrafts: Dict<string>
  replyParent: string
  showHidden: boolean
  environmentVersion: number
  agentsVersion: number
  fileVersion: number
  dialog: HTMLDialogElement | null
  formSessionKey: string | null | undefined
  alive: boolean
  provisioningPoll: ReturnType<typeof setTimeout> | undefined
}
