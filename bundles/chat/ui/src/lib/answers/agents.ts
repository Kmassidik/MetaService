/** Checks for the answers about bots, groups and their conversations. */
import {
  arrayOf, isBoolean, isNumber, isString, nullable, objectOf, objectWithOptional, parseAnswer,
} from '../check.ts'
import type {
  Agent, AgentActivity, ChatFile, ChatMessage, ComputerInfo, Environment, PlanLimits, Reaction, Run, WelcomeIdea,
} from '../types.ts'
import { isComputerInfo, isEnvironment } from './account.ts'
import { type RemovedFile, isMessageFile, messageFile } from './files.ts'
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

/** A message as the server sends it: a deleted file is only a stub (see `messageFile`). */
type WireMessage = Omit<ChatMessage, 'attachments'> & { attachments?: (ChatFile | RemovedFile)[] }

const isWireMessage = objectWithOptional<WireMessage>(
  { id: isString, role: isString, text: isString, createdAt: isString },
  {
    parentId: isString, attachmentIds: arrayOf(isString), attachments: arrayOf(isMessageFile),
    reactions: arrayOf(isReaction), choices: arrayOf(isWelcomeIdea),
  },
)

function messageOf({ attachments, ...message }: WireMessage): ChatMessage {
  return attachments ? { ...message, attachments: attachments.map(messageFile) } : message
}

/** The `messages` field of an answer that may leave it out. */
function messagesOf(messages: WireMessage[] | undefined): { messages?: ChatMessage[] } {
  return messages ? { messages: messages.map(messageOf) } : {}
}

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

interface WireConversation extends Omit<Conversation, 'messages'> {
  messages: WireMessage[]
}

interface WireAgentAnswer extends Omit<AgentAnswer, 'messages'> {
  messages?: WireMessage[]
}

interface WireNewBot extends Omit<NewBotAnswer, 'messages'> {
  messages: WireMessage[]
}

interface WireMention extends Omit<Mention, 'messages'> {
  messages?: WireMessage[]
}

interface WireMessageAnswer {
  message?: WireMessage
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

const isConversation = objectWithOptional<WireConversation>(
  { messages: arrayOf(isWireMessage), computer: isComputerInfo, pending: isBoolean },
  { lastError: isString, run: isRun },
)

const isAgentAnswer = objectWithOptional<WireAgentAnswer>(
  { agent: isAgent },
  { environment: nullable(isEnvironment), messages: arrayOf(isWireMessage) },
)

const isNewBot = objectWithOptional<WireNewBot>(
  { agent: isAgent, messages: arrayOf(isWireMessage) },
  { environment: nullable(isEnvironment) },
)

const isMaybeAgent = objectWithOptional<MaybeAgent>({}, { agent: isAgent })

const isMention = objectWithOptional<WireMention>({}, {
  createdGroup: isBoolean, agent: isAgent, environment: nullable(isEnvironment),
  messages: arrayOf(isWireMessage), computer: isComputerInfo,
})

const isShare = objectWithOptional<ShareAnswer>({}, {
  template: objectWithOptional<{ token?: string, secretWarning?: boolean }>({}, { token: isString, secretWarning: isBoolean }),
})

const isQueuedAnswer = objectOf<QueuedAnswer>({ message: objectOf<{ id: string }>({ id: isString }) })
const isMessageAnswer = objectWithOptional<WireMessageAnswer>({}, { message: isWireMessage })

export const parseAgentList = (answer: unknown): AgentList => parseAnswer(isAgentList, answer, 'bot list')
export function parseConversation(answer: unknown): Conversation {
  const { messages, ...conversation } = parseAnswer(isConversation, answer, 'conversation')
  return { ...conversation, messages: messages.map(messageOf) }
}

export function parseAgentAnswer(answer: unknown): AgentAnswer {
  const { messages, ...rest } = parseAnswer(isAgentAnswer, answer, 'bot')
  return { ...rest, ...messagesOf(messages) }
}

export function parseNewBot(answer: unknown): NewBotAnswer {
  const { messages, ...rest } = parseAnswer(isNewBot, answer, 'new bot')
  return { ...rest, messages: messages.map(messageOf) }
}

export const parseMaybeAgent = (answer: unknown): MaybeAgent => parseAnswer(isMaybeAgent, answer, 'bot')
export function parseMention(answer: unknown): Mention {
  const { messages, ...rest } = parseAnswer(isMention, answer, 'mention')
  return { ...rest, ...messagesOf(messages) }
}

export const parseShare = (answer: unknown): ShareAnswer => parseAnswer(isShare, answer, 'share')
export const parseQueued = (answer: unknown): QueuedAnswer => parseAnswer(isQueuedAnswer, answer, 'queued message')
export function parseMessageAnswer(answer: unknown): MessageAnswer {
  const { message } = parseAnswer(isMessageAnswer, answer, 'message')
  return message ? { message: messageOf(message) } : {}
}

export type { AgentAnswer, AgentList, Conversation, MaybeAgent, MessageAnswer, Mention, NewBotAnswer, ShareAnswer }
