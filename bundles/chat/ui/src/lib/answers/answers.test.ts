// The checking functions against the shapes the real Ruvio Chat server sent, plus answers that must be refused.
import { describe, expect, it } from 'bun:test'
import fixtureFile from '../../../../tests/fixtures/maas-shapes.json'
import { isRecord } from '../check.ts'
import {
  parseComputer, parseConfig, parseEnvironmentAnswer, parseSession, parseStorage, parseStorageGate, parseUsage,
} from './account.ts'
import { parseAgentAnswer, parseAgentList, parseConversation, parseNewBot } from './agents.ts'
import { parseFiles } from './files.ts'
import { parseApps, parseConnectors, parseMemory, parseRoutines } from './profile.ts'
import { answeredAskIds, askOf, cardOf, parseApprovals, parseEventPage, parseRuns, profileChangeOf } from './runs.ts'

const SAMPLE_STRING = 'sample'
const SAMPLE_NUMBER = 3

/** A fixture marks each value by its kind ("str", "number", "bool", "null", []); this makes a real value of that kind. */
function sampleOf(shape: unknown): unknown {
  if (Array.isArray(shape)) return shape.map(sampleOf)
  if (isRecord(shape)) return Object.fromEntries(Object.entries(shape).map(([key, value]) => [key, sampleOf(value)]))
  if (shape === 'str') return SAMPLE_STRING
  if (shape === 'number') return SAMPLE_NUMBER
  if (shape === 'bool') return true
  if (shape === 'null') return null
  throw new Error(`Unknown fixture marker: ${String(shape)}`)
}

function fixture(name: string): Record<string, unknown> {
  const shape: unknown = Reflect.get(fixtureFile, name)
  const sample = sampleOf(shape)
  if (!isRecord(sample)) throw new Error(`Fixture ${name} is not an object`)
  return sample
}

const PARSERS: Record<string, (answer: unknown) => unknown> = {
  agents: parseAgentList,
  agents_after_failure: parseAgentList,
  approvals: parseApprovals,
  apps: parseApps,
  config: parseConfig,
  connectors: parseConnectors,
  environment: parseEnvironmentAnswer,
  events: parseEventPage,
  files: parseFiles,
  me: parseSession,
  memory: parseMemory,
  messages: parseConversation,
  messages_empty: parseConversation,
  send: parseConversation,
  new_bot: parseNewBot,
  read: parseAgentAnswer,
  routines: parseRoutines,
  runs: parseRuns,
  runs_empty: parseRuns,
  storage: parseStorage,
  storage_gate: parseStorageGate,
  usage: parseUsage,
}

describe('answers the real server sent', () => {
  for (const [name, parse] of Object.entries(PARSERS)) {
    it(`${name} is accepted`, () => {
      expect(() => parse(fixture(name))).not.toThrow()
    })
  }

  it('every fixture has a parser', () => {
    const named = Object.keys(fixtureFile).filter(key => !key.startsWith('_'))
    expect(named.sort()).toEqual(Object.keys(PARSERS).sort())
  })
})

describe('answers that must be refused', () => {
  it('a session without csrf', () => {
    const { csrf: _csrf, ...rest } = fixture('me')
    expect(() => parseSession(rest)).toThrow('unexpected session answer')
  })

  it('a string where a number is expected', () => {
    expect(() => parseUsage({ ...fixture('usage'), remaining: '3' })).toThrow('unexpected usage answer')
  })

  it('a non-object', () => {
    expect(() => parseSession('nope')).toThrow('unexpected session answer')
    expect(() => parseSession(null)).toThrow('unexpected session answer')
    expect(() => parseRuns([])).toThrow('unexpected task list answer')
  })

  it('a bot list with a bad bot', () => {
    expect(() => parseAgentList({ agents: [{ id: 'a1' }] })).toThrow('unexpected bot list answer')
  })

  it('an optional field set to undefined', () => {
    expect(() => parseComputer({ state: 'ready', message: undefined })).toThrow('unexpected computer answer')
  })

  it('an optional field that is missing is fine', () => {
    expect(parseComputer({ state: 'ready' })).toEqual({ state: 'ready' })
  })
})

const ASK_PAYLOAD = { askId: 'q1', prompt: 'Which?', options: [{ id: 'a', label: 'A' }, { id: 'b', label: 'B' }] }
const askEvent = (payload: Record<string, unknown>, sequence = 4) => ({ kind: 'ask', sequence, payload })

describe('askOf', () => {
  it('reads a well-formed question, with the run and sequence', () => {
    expect(askOf(askEvent(ASK_PAYLOAD), 'r1')).toEqual({ ...ASK_PAYLOAD, runId: 'r1', sequence: 4 })
  })

  it('drops null fields the server sends for "none"', () => {
    expect(askOf(askEvent({ ...ASK_PAYLOAD, hint: null }), 'r1')?.hint).toBeUndefined()
  })

  it('refuses fewer than 2 options', () => {
    expect(askOf(askEvent({ ...ASK_PAYLOAD, options: [{ id: 'a', label: 'A' }] }), 'r1')).toBeNull()
  })

  it('refuses options that are not {id,label}', () => {
    expect(askOf(askEvent({ ...ASK_PAYLOAD, options: ['A', 'B'] }), 'r1')).toBeNull()
    expect(askOf(askEvent({ ...ASK_PAYLOAD, options: [{ id: 'a' }, { id: 'b' }] }), 'r1')).toBeNull()
  })

  it('refuses an empty id, another kind, and a missing payload', () => {
    expect(askOf(askEvent({ ...ASK_PAYLOAD, askId: '' }), 'r1')).toBeNull()
    expect(askOf({ kind: 'runtime', sequence: 1, payload: ASK_PAYLOAD }, 'r1')).toBeNull()
    expect(askOf({ kind: 'ask', sequence: 1 }, 'r1')).toBeNull()
  })
})

describe('cardOf', () => {
  const payload = { cardId: 'c1', kind: 'login', title: 'Sign in' }

  it('reads a card with the run', () => {
    expect(cardOf({ kind: 'card', payload }, 'r1')).toEqual({ ...payload, runId: 'r1' })
  })

  it('refuses a card without an id, another kind, and a missing payload', () => {
    expect(cardOf({ kind: 'card', payload: { kind: 'login' } }, 'r1')).toBeNull()
    expect(cardOf({ kind: 'runtime', payload }, 'r1')).toBeNull()
    expect(cardOf({ kind: 'card' }, 'r1')).toBeNull()
  })
})

describe('answeredAskIds and profileChangeOf', () => {
  it('collects the ids of answered asks only', () => {
    const events = [
      { kind: 'ask_answered', payload: { askId: 'q1' } },
      { kind: 'ask_answered', payload: { askId: 7 } },
      { kind: 'ask_answered', payload: { askId: '' } },
      { kind: 'ask_answered' },
      { kind: 'ask', payload: { askId: 'q2' } },
    ]
    expect([...answeredAskIds(events)]).toEqual(['q1'])
  })

  it('reads a profile change and refuses one without an agent id', () => {
    expect(profileChangeOf({ kind: 'profile', payload: { agentId: 'a1', name: 'Ada', notice: null } })).toEqual({ agentId: 'a1', name: 'Ada' })
    expect(profileChangeOf({ kind: 'profile', payload: { name: 'Ada' } })).toBeNull()
  })
})
