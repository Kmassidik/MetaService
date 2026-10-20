/** Checks for the answers about bots, groups and their conversations. */
import {
  arrayOf, isBoolean, isNumber, isString, nullable, objectOf, objectWithOptional, parseAnswer,
} from '../check.ts'
import type {
  Agent, AgentActivity, ChatMessage, ComputerInfo, Environment, PlanLimits, Reaction, Run, WelcomeIdea,
} from '../types.ts'
import { isComputerInfo, isEnvironment } from './account.ts'
import { isChatFile } from './files.ts'
import { isRun } from './runs.ts'

const isActivity = objectWithOptional<AgentActivity>(
  { state: isString, tool: nullable(isString) },
  { model: isString, startedAt: isString, title: isString },
)

export const isAgent = objectWithOptional<Agent>(
  {
    id: isString, name: isString, kind: isString, status: isString, title: isString, summary: isString,
    description: isString, model: isString, avatarColor: isString, avatarShape: isString, createdAt: isString,
    lastMessagePreview: isString, lastReadSequence: isNumber, unreadCount: isNumber, hidden: isBoolean,
    pinned: isBoolean, queuedMessage: isBoolean, notifyFinished: isBoolean, notifyNeedsInput: isBoolean,
    leadAgentId: nullable(isString), memberAgentIds: arrayOf(isString),
  },
  { activity: isActivity, lastError: isString },
)

const isReaction = objectOf<Reaction>({ emoji: isString, count: isNumber })
const isWelcomeIdea = objectOf<WelcomeIdea>({ id: isString, label: isString, subtitle: isString, message: isString })

export const isChatMessage = objectWithOptional<ChatMessage>(
  { id: isString, role: isString, text: isString, createdAt: isString },
  {
    parentId: isString, attachmentIds: arrayOf(isString), attachments: arrayOf(isChatFile),
    reactions: arrayOf(isReaction), choices: arrayOf(isWelcomeIdea),
  },
)

interface AgentList {
  agents: Agent[]
  limits?: PlanLimits
  environment?: Environment | null
}

interface Conversation {
  messages: ChatMessage[]
  computer: ComputerInfo
  pending: boolean
  lastError?: string
  run?: Run
}

interface AgentAnswer {
  agent: Agent
  environment?: Environment | null
  messages?: ChatMessage[]
}

/** The answer of New bot: the bot, its computer, and its welcome. */
interface NewBotAnswer {
  agent: Agent
  environment?: Environment | null
  messages: ChatMessage[]
}

interface MaybeAgent {
  agent?: Agent
}

interface Mention {
  createdGroup?: boolean
  agent?: Agent
  environment?: Environment | null
  messages?: ChatMessage[]
  computer?: ComputerInfo
}

interface ShareAnswer {
  template?: { token?: string, secretWarning?: boolean }
}

interface QueuedAnswer {
  message: { id: string }
}

interface MessageAnswer {
  message?: ChatMessage
}

const isLimits = objectOf<PlanLimits>({
  cpu: isNumber, maxAgents: isNumber, maxTeams: isNumber, memoryMB: isNumber, workspaceBytes: isNumber,
})

const isAgentList = objectWithOptional<AgentList>(
  { agents: arrayOf(isAgent) },
  { limits: isLimits, environment: nullable(isEnvironment) },
)

const isConversation = objectWithOptional<Conversation>(
  { messages: arrayOf(isChatMessage), computer: isComputerInfo, pending: isBoolean },
  { lastError: isString, run: isRun },
)

const isAgentAnswer = objectWithOptional<AgentAnswer>(
  { agent: isAgent },
  { environment: nullable(isEnvironment), messages: arrayOf(isChatMessage) },
)

const isNewBot = objectWithOptional<NewBotAnswer>(
  { agent: isAgent, messages: arrayOf(isChatMessage) },
  { environment: nullable(isEnvironment) },
)

const isMaybeAgent = objectWithOptional<MaybeAgent>({}, { agent: isAgent })

const isMention = objectWithOptional<Mention>({}, {
  createdGroup: isBoolean, agent: isAgent, environment: nullable(isEnvironment),
  messages: arrayOf(isChatMessage), computer: isComputerInfo,
})

const isShare = objectWithOptional<ShareAnswer>({}, {
  template: objectWithOptional<{ token?: string, secretWarning?: boolean }>({}, { token: isString, secretWarning: isBoolean }),
})

const isQueuedAnswer = objectOf<QueuedAnswer>({ message: objectOf<{ id: string }>({ id: isString }) })
const isMessageAnswer = objectWithOptional<MessageAnswer>({}, { message: isChatMessage })

export const parseAgentList = (answer: unknown): AgentList => parseAnswer(isAgentList, answer, 'bot list')
export const parseConversation = (answer: unknown): Conversation => parseAnswer(isConversation, answer, 'conversation')
export const parseAgentAnswer = (answer: unknown): AgentAnswer => parseAnswer(isAgentAnswer, answer, 'bot')
export const parseNewBot = (answer: unknown): NewBotAnswer => parseAnswer(isNewBot, answer, 'new bot')
export const parseMaybeAgent = (answer: unknown): MaybeAgent => parseAnswer(isMaybeAgent, answer, 'bot')
export const parseMention = (answer: unknown): Mention => parseAnswer(isMention, answer, 'mention')
export const parseShare = (answer: unknown): ShareAnswer => parseAnswer(isShare, answer, 'share')
export const parseQueued = (answer: unknown): QueuedAnswer => parseAnswer(isQueuedAnswer, answer, 'queued message')
export const parseMessageAnswer = (answer: unknown): MessageAnswer => parseAnswer(isMessageAnswer, answer, 'message')

export type { AgentAnswer, AgentList, Conversation, MaybeAgent, MessageAnswer, Mention, NewBotAnswer, ShareAnswer }
