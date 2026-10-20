/** Checks for the answers about a bot's profile: routines, skills, memory, and the connected apps. */
import {
  arrayOf, isBoolean, isString, objectOf, objectWithOptional, parseAnswer,
} from '../check.ts'
import type { AppRecord, Connector, MemoryEntry, Routine, Skill } from '../types.ts'

export const isRoutine = objectWithOptional<Routine>(
  { id: isString, title: isString },
  {
    agentId: isString, state: isString, createdAt: isString, triggerKind: isString, scheduleKind: isString,
    schedule: isString, hasWebhook: isBoolean, taskText: isString, webhookToken: isString,
  },
)

const isSkill = objectWithOptional<Skill>(
  { id: isString, name: isString, enabled: isBoolean, state: isString },
  { body: isString },
)

const isMemoryEntry = objectOf<MemoryEntry>({ key: isString, value: isString })
const isConnector = objectWithOptional<Connector>({ id: isString, name: isString }, { revoked: isBoolean })
const isAppRecord = objectWithOptional<AppRecord>(
  { appId: isString },
  { loginState: isString, connectedAt: isString, checkedAt: isString },
)

interface RoutineList {
  routines?: Routine[]
}

interface RoutineAnswer {
  routine?: Routine
}

interface SkillList {
  skills?: Skill[]
}

interface MemoryList {
  entries?: MemoryEntry[]
}

interface ConnectorList {
  connectors?: Connector[]
}

interface AppList {
  apps?: AppRecord[]
}

interface TeachAnswer {
  skill?: { name: string }
}

const isRoutineList = objectWithOptional<RoutineList>({}, { routines: arrayOf(isRoutine) })
const isRoutineAnswer = objectWithOptional<RoutineAnswer>({}, { routine: isRoutine })
const isSkillList = objectWithOptional<SkillList>({}, { skills: arrayOf(isSkill) })
const isMemoryList = objectWithOptional<MemoryList>({}, { entries: arrayOf(isMemoryEntry) })
const isConnectorList = objectWithOptional<ConnectorList>({}, { connectors: arrayOf(isConnector) })
const isAppList = objectWithOptional<AppList>({}, { apps: arrayOf(isAppRecord) })
const isAppAnswer = objectOf<{ app: AppRecord }>({ app: isAppRecord })
const isTeachAnswer = objectWithOptional<TeachAnswer>({}, { skill: objectOf<{ name: string }>({ name: isString }) })

export const parseRoutines = (answer: unknown): Routine[] => parseAnswer(isRoutineList, answer, 'routine list').routines ?? []
export const parseRoutine = (answer: unknown): RoutineAnswer => parseAnswer(isRoutineAnswer, answer, 'routine')
export const parseSkills = (answer: unknown): Skill[] => parseAnswer(isSkillList, answer, 'skill list').skills ?? []
export const parseMemory = (answer: unknown): MemoryEntry[] => parseAnswer(isMemoryList, answer, 'memory').entries ?? []
export const parseConnectors = (answer: unknown): Connector[] => parseAnswer(isConnectorList, answer, 'connector list').connectors ?? []
export const parseApps = (answer: unknown): AppRecord[] => parseAnswer(isAppList, answer, 'app list').apps ?? []
export const parseAppRecord = (answer: unknown): AppRecord => parseAnswer(isAppAnswer, answer, 'app').app
export const parseTeach = (answer: unknown): TeachAnswer => parseAnswer(isTeachAnswer, answer, 'skill')
