/**
 * The shapes the chat screen shares: what the server sends (checked in answers.ts before anything
 * here is trusted) and the small records the screen builds itself. Server states stay `string`
 * because the server owns the list; the words the screen compares against live in constants.
 */

// ---- Session -----------------------------------------------------------------------------

export interface PlanLimits {
  cpu: number
  maxAgents: number
  maxTeams: number
  memoryMB: number
  workspaceBytes: number
}

export interface Onboarding {
  completedAt: string
  goal: string
  goalDetail: string
  source: string
  sourceDetail: string
}

export interface SessionUser {
  id: string
  email: string
  name: string
  access: string
}

/** The private computer of an account (`stage` and `lastError` only while it is changing or failed). */
export interface Environment {
  state: string
  stage?: string
  lastError?: string
}

export interface Session {
  csrf: string
  limits: PlanLimits
  onboarding?: Onboarding | null
  user: SessionUser
  environment?: Environment | null
}

/** Whether the host takes new accounts and new work. */
export interface HostState {
  reason: string | null
  registrationsOpen: boolean
  writesAllowed: boolean
}

/** A quota meter: the saved files, or the workspace disk inside the computer. */
export interface StorageMeter {
  usedBytes: number
  limitBytes: number
  availableBytes?: number
  state?: string
}

/** The computer's system disk: it reports its size, not a quota. */
export interface SystemDisk {
  totalBytes: number
  availableBytes: number
  state: string
}

/**
 * The computer's disks. The meters are null while it has none (not created) or are missing when
 * its storage could not be read (`reason` says why).
 */
export interface StorageComputer {
  state: string
  reason?: string
  system?: SystemDisk | null
  workspace?: StorageMeter | null
}

/** The create gate; the full answer also holds the meters (Settings › Computer). */
export interface AccountStorage {
  canCreateAgent: boolean
  host: HostState
  limits: PlanLimits
  creationBlockedReason?: string
  computer?: StorageComputer
  results?: StorageMeter
}

/** The full answer of Settings › Computer: the meters are there. */
export interface FullStorage extends AccountStorage {
  computer: StorageComputer
  results: StorageMeter
}

export interface UsageTotals {
  tokens: number
  turns: number
}

export interface Usage {
  blocked: boolean
  lifetime: UsageTotals
  monthly: UsageTotals
  remaining: number
  tokens: number
  turns: number
}

// ---- Bots and groups ---------------------------------------------------------------------

export interface AgentActivity {
  state: string
  tool: string | null
  model?: string
  startedAt?: string
  title?: string
}

/** A bot (`kind` "bot") or a group chat (`kind` "team"). */
export interface Agent {
  id: string
  name: string
  kind: string
  status: string
  title: string
  summary: string
  description: string
  model: string
  avatarColor: string
  avatarShape: string
  createdAt: string
  lastMessagePreview: string
  lastReadSequence: number
  unreadCount: number
  hidden: boolean
  pinned: boolean
  queuedMessage: boolean
  notifyFinished: boolean
  notifyNeedsInput: boolean
  leadAgentId: string | null
  memberAgentIds: string[]
  activity?: AgentActivity
  lastError?: string
}

/** The colour and shape a new bot wears. */
export interface AvatarChoice {
  avatarShape: string
  avatarColor: string
}

// ---- Files and messages ------------------------------------------------------------------

export interface ChatFile {
  id: string
  name: string
  size: number
  mediaType: string
  state: string
  createdAt: string
  version?: number
  artifactId?: string
  sourceFileId?: string
  previewFileId?: string
  sha256?: string
  agentId?: string
  received?: number
}

/** The part of a file the preview rules look at. */
export type FileFacts = Pick<ChatFile, 'name' | 'size' | 'mediaType' | 'state'>

export interface Reaction {
  emoji: string
  count: number
}

/** A starter idea as a welcome message offers it. */
export interface WelcomeIdea {
  id: string
  label: string
  subtitle: string
  message: string
}

export interface ChatMessage {
  id: string
  role: string
  text: string
  createdAt: string
  parentId?: string
  attachmentIds?: string[]
  attachments?: ChatFile[]
  reactions?: Reaction[]
  choices?: WelcomeIdea[]
}

/** A file being sent to the server in chunks. */
export interface Upload {
  token: string
  agentId: string
  name: string
  size: number
  received: number
  fileId: string
  status: string
  error: string
  sessionKey: string
}

/** The message that is on its way to a bot. */
export interface PendingSend {
  id: string
  text: string
  attachments: ChatFile[]
}

/** A message typed while the bot works, queued on its task. */
export interface FollowUp {
  id: string
  runId: string
  text: string
  confirmed: boolean
}

// ---- Computer ----------------------------------------------------------------------------

export interface ComputerInfo {
  state: string
  message?: string
  image?: string
  url?: string
  mode?: string
  environment?: Environment | null
}

export type DesktopMode = 'stream' | 'browser'

export interface Desktop {
  state: string
  mode: DesktopMode
  wsPath: string
  message: string
}

/** The app whose sign-in page the account computer is showing. */
export interface ConnectingApp {
  id: string
  name: string
  loginUrl: string
}

/** One app's last login check on the account computer. */
export interface AppRecord {
  appId: string
  loginState?: string
  connectedAt?: string
  checkedAt?: string
}

// ---- Tasks (runs) ------------------------------------------------------------------------

export interface Run {
  id: string
  agentId: string
  state: string
  createdAt: string
  updatedAt: string
  firstEventSequence: number
  lastEventSequence: number
  model?: string
  error?: string
  attachmentIds?: string[]
}

export type EventPayload = Record<string, unknown>

/** One public event of a run (the server has already redacted it). */
export interface RunEvent {
  sequence: number
  kind: string
  createdAt: string
  runId?: string
  /** Only when the server sent an object; any other payload (null, text, a list) is dropped. */
  payload?: EventPayload
}

export interface Approval {
  id: string
  runId: string
  state: string
  parametersSHA256: string
  tool: string
  action: string
  destination: string
  expiresAt: string
  /** Only for research and connector proposals, which the owner reviews in full. */
  parametersJSON?: string
}

export interface AskOption {
  id: string
  label: string
}

/** A question the bot asked the owner (a `ruvio_ask` event), with the run it belongs to. */
export interface Ask {
  askId: string
  options: AskOption[]
  runId: string
  sequence: number
  mode?: string
  skippable?: boolean
  prompt?: string
  hint?: string
  helper?: string
}

/** A card a run published: app approvals, takeover and connect prompts, secrets. */
export interface RunCard {
  cardId: string
  kind: string
  runId: string
  subject?: string
  appName?: string
  target?: string
  change?: string
  url?: string
  title?: string
  reason?: string
  name?: string
  text?: string
  service?: string
}

/** What an app tool did, as a result card. */
export interface AppResult {
  kind: string
  ok?: boolean
  app?: string
  appName?: string
  subject?: string
  target?: string
  change?: string
  delivery?: string
  reason?: string
}

// ---- Profile -----------------------------------------------------------------------------

/** When a schedule routine runs; which fields exist depends on its `scheduleKind`. A webhook routine has none. */
export interface ScheduleFields {
  time?: string
  weekday?: number
  hours?: number
}

export interface Routine {
  id: string
  title: string
  agentId: string
  state: string
  createdAt: string
  triggerKind: string
  scheduleKind: string
  schedule: ScheduleFields
  hasWebhook: boolean
  taskText: string
  /** Only in the answer that creates a webhook routine, once. */
  webhookToken?: string
}

export interface Skill {
  id: string
  name: string
  enabled: boolean
  state: string
  body?: string
}

export interface MemoryEntry {
  key: string
  value: string
}

export interface Connector {
  id: string
  name: string
  revoked?: boolean
}
