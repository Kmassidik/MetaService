/** Checks for the answers about the account: session, plan, storage, usage, the private computer. */
import {
  type Check, isBoolean, isNumber, isString, nullable, objectOf, objectWithOptional, parseAnswer,
} from '../check.ts'
import type {
  AccountStorage, ComputerInfo, Environment, FullStorage, HostState, Onboarding, PlanLimits, Session, SessionUser, StorageComputer,
  StorageMeter, Usage, UsageTotals,
} from '../types.ts'

const isPlanLimits = objectOf<PlanLimits>({
  cpu: isNumber, maxAgents: isNumber, maxTeams: isNumber, memoryMB: isNumber, workspaceBytes: isNumber,
})

export const isOnboarding = objectOf<Onboarding>({
  completedAt: isString, goal: isString, goalDetail: isString, source: isString, sourceDetail: isString,
})

const isSessionUser = objectOf<SessionUser>({ id: isString, email: isString, name: isString, access: isString })

export const isEnvironment = objectWithOptional<Environment>({ state: isString }, { stage: isString, lastError: isString })

const isSession = objectWithOptional<Session>(
  { csrf: isString, limits: isPlanLimits, user: isSessionUser },
  { onboarding: nullable(isOnboarding), environment: nullable(isEnvironment) },
)

const isHostState = objectOf<HostState>({ reason: nullable(isString), registrationsOpen: isBoolean, writesAllowed: isBoolean })

const isStorageMeter = objectWithOptional<StorageMeter>(
  { usedBytes: isNumber, limitBytes: isNumber },
  { availableBytes: isNumber, state: isString },
)

const isStorageComputer = objectOf<StorageComputer>({
  state: isString, system: nullable(isStorageMeter), workspace: nullable(isStorageMeter),
})

const isStorageGate = objectWithOptional<AccountStorage>(
  { canCreateAgent: isBoolean, host: isHostState, limits: isPlanLimits },
  { creationBlockedReason: isString, computer: isStorageComputer, results: isStorageMeter },
)

const isStorageFull = objectWithOptional<FullStorage>(
  { canCreateAgent: isBoolean, host: isHostState, limits: isPlanLimits, computer: isStorageComputer, results: isStorageMeter },
  { creationBlockedReason: isString },
)

const isUsageTotals = objectOf<UsageTotals>({ tokens: isNumber, turns: isNumber })

const isUsage = objectOf<Usage>({
  blocked: isBoolean, lifetime: isUsageTotals, monthly: isUsageTotals, remaining: isNumber, tokens: isNumber, turns: isNumber,
})

export const isComputerInfo: Check<ComputerInfo> = objectWithOptional<ComputerInfo>(
  { state: isString },
  { message: isString, image: isString, url: isString, mode: isString, environment: nullable(isEnvironment) },
)

interface Config {
  googleConfigured: boolean
  capacity: HostState
}

interface EnvironmentAnswer {
  environment?: Environment | null
  ok?: boolean
}

interface MaybeEnvironment {
  environment?: Environment | null
}

const isConfig = objectOf<Config>({ googleConfigured: isBoolean, capacity: isHostState })
const isEnvironmentAnswer = objectWithOptional<EnvironmentAnswer>({}, { environment: nullable(isEnvironment), ok: isBoolean })
const isMaybeEnvironment = objectWithOptional<MaybeEnvironment>({}, { environment: nullable(isEnvironment) })
const isOnboardingAnswer = objectOf<{ onboarding: Onboarding }>({ onboarding: isOnboarding })

export const parseSession = (answer: unknown): Session => parseAnswer(isSession, answer, 'session')
export const parseConfig = (answer: unknown): Config => parseAnswer(isConfig, answer, 'config')
export const parseOnboarding = (answer: unknown): Onboarding => parseAnswer(isOnboardingAnswer, answer, 'onboarding').onboarding
export const parseUsage = (answer: unknown): Usage => parseAnswer(isUsage, answer, 'usage')
export const parseStorageGate = (answer: unknown): AccountStorage => parseAnswer(isStorageGate, answer, 'storage gate')
export const parseStorage = (answer: unknown): FullStorage => parseAnswer(isStorageFull, answer, 'storage')
export const parseComputer = (answer: unknown): ComputerInfo => parseAnswer(isComputerInfo, answer, 'computer')
export const parseEnvironmentAnswer = (answer: unknown): EnvironmentAnswer => parseAnswer(isEnvironmentAnswer, answer, 'environment')

/** Answers that may carry the account's computer next to their own data (`environment`). */
export const parseMaybeEnvironment = (answer: unknown): MaybeEnvironment => parseAnswer(isMaybeEnvironment, answer, 'environment')

export type { Config, EnvironmentAnswer, MaybeEnvironment }
