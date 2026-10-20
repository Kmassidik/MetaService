// Answers as the Swift chat service really builds them (control-plane/Sources/Chat), each a shape the first
// TypeScript checks refused or let through wrongly. A bot's computer, files, tasks and routines must all load.
import { describe, expect, it } from 'bun:test'
import { parseStorage } from './account.ts'
import { parseConversation, parseMessageAnswer } from './agents.ts'
import { parseFile } from './files.ts'
import { parseRoutine, parseRoutines } from './profile.ts'
import { parseApprovals, parseEventPage } from './runs.ts'

const AT = '2026-10-01T00:00:00Z'

// ChatStore+SkillsMemoryRoutines.swift routinePublic: `schedule` is the decoded schedule_json object.
const dailyRoutine = {
  id: 'rt1', userId: 'u1', agentId: 'a1', title: 'Morning brief', taskText: 'Summarise the news', scheduleKind: 'daily',
  schedule: { time: '08:00' }, timezone: 'Asia/Jakarta', state: 'active', triggerKind: 'schedule', hasWebhook: false,
  createdAt: AT, updatedAt: AT, nextRunAt: 1_790_000_000.5,
}
const webhookRoutine = { ...dailyRoutine, id: 'rt2', scheduleKind: 'webhook', schedule: {}, triggerKind: 'webhook', hasWebhook: true }

describe('routines', () => {
  it('keeps the schedule as an object', () => {
    const [daily, weekly, hourly] = parseRoutines({
      routines: [dailyRoutine, { ...dailyRoutine, scheduleKind: 'weekly', schedule: { time: '09:30', weekday: 2 } }, { ...dailyRoutine, scheduleKind: 'every_hours', schedule: { hours: 4 } }],
    })
    expect(daily?.schedule).toEqual({ time: '08:00' })
    expect(weekly?.schedule).toEqual({ time: '09:30', weekday: 2 })
    expect(hourly?.schedule).toEqual({ hours: 4 })
  })

  it('reads a webhook routine with an empty schedule and the one-time token', () => {
    const created = parseRoutine({ routine: { ...webhookRoutine, webhookToken: 'tok' } })
    expect(created.routine?.schedule).toEqual({})
    expect(created.routine?.webhookToken).toBe('tok')
  })

  it('refuses a schedule that is a string, a list, or has a field of the wrong type', () => {
    expect(() => parseRoutines({ routines: [{ ...dailyRoutine, schedule: '08:00' }] })).toThrow('routine list')
    expect(() => parseRoutines({ routines: [{ ...dailyRoutine, schedule: ['08:00'] }] })).toThrow('routine list')
    expect(() => parseRoutines({ routines: [{ ...dailyRoutine, schedule: { hours: '4' } }] })).toThrow('routine list')
  })

  it('refuses a routine without a schedule or a kind, which the service always sends', () => {
    const { schedule: _schedule, ...noSchedule } = dailyRoutine
    const { triggerKind: _kind, ...noKind } = dailyRoutine
    expect(() => parseRoutines({ routines: [noSchedule] })).toThrow('routine list')
    expect(() => parseRoutines({ routines: [noKind] })).toThrow('routine list')
  })
})

// Files.swift Record.publicValue: the digest is `sha256`.
const savedFile = {
  id: 'f1', agentId: 'a1', name: 'notes.txt', size: 10, received: 10, state: 'ready', mediaType: 'text/plain', createdAt: AT, sha256: 'ab12',
}

describe('files', () => {
  it('reads the digest as sha256', () => {
    expect(parseFile({ file: savedFile }).sha256).toBe('ab12')
  })

  it('refuses a digest that is not text', () => {
    expect(() => parseFile({ file: { ...savedFile, sha256: 12 } })).toThrow('file')
  })

  it('accepts a file that has no digest yet', () => {
    const { sha256: _digest, ...pending } = savedFile
    expect(parseFile({ file: { ...pending, state: 'receiving', received: 3 } }).state).toBe('receiving')
  })
})

// Routes.swift history(): a file the owner deleted is only {id, state, name} in the messages that held it.
const history = (attachments: unknown[]) => ({
  messages: [{ id: 'm1', role: 'user', text: 'see this', createdAt: AT, attachmentIds: ['f1', 'f2'], attachments }],
  computer: { state: 'busy', message: 'A run is active.' },
  pending: false,
})
const deletedStub = { id: 'f2', state: 'deleted', name: 'File no longer available' }

describe('a message that holds a deleted file', () => {
  it('loads, with the deleted file filled in like the one the screen makes itself', () => {
    const { messages } = parseConversation(history([savedFile, deletedStub]))
    expect(messages[0]?.attachments).toEqual([
      savedFile,
      { id: 'f2', state: 'deleted', name: 'File no longer available', size: 0, mediaType: '', createdAt: '' },
    ])
  })

  it('loads as a single message answer too', () => {
    const [message] = parseConversation(history([deletedStub])).messages
    expect(parseMessageAnswer({ message }).message?.attachments?.[0]?.state).toBe('deleted')
  })

  it('still refuses a file that is neither whole nor a deleted stub', () => {
    expect(() => parseConversation(history([{ id: 'f2', state: 'ready', name: 'x' }]))).toThrow('conversation')
    expect(() => parseConversation(history([{ id: 'f2', name: 'x' }]))).toThrow('conversation')
  })
})

// ChatRunEvent.publicValue: the payload is whatever JSON the run wrote.
const eventPage = (events: unknown[]) => ({
  cursor: 3,
  events,
  run: { id: 'r1', agentId: 'a1', attachmentIds: [], model: 'auto', state: 'running', createdAt: AT, updatedAt: AT, firstEventSequence: 1, lastEventSequence: 3 },
})
const event = (sequence: number, payload: unknown) => ({ runId: 'r1', sequence, kind: 'runtime', payload, createdAt: AT })

describe('run events', () => {
  it('load when a payload is null, text, a number or a list, and drop that payload', () => {
    const { events } = parseEventPage(eventPage([event(1, null), event(2, 'plain'), event(3, [1]), event(4, 7), event(5, { type: 'tool' })]))
    expect(events.map(item => item.payload)).toEqual([undefined, undefined, undefined, undefined, { type: 'tool' }])
    expect(events.map(item => 'payload' in item)).toEqual([false, false, false, false, true])
  })
})

// ChatRunApproval.publicValue (Models/ChatModels.swift) and the route in Routes.swift.
const runApproval = {
  id: 'ap1', runId: 'r1', action: 'send', destination: 'a@b.c', tool: 'mail', parametersSHA256: 'h', state: 'pending', expiresAt: AT, createdAt: AT,
}

describe('task approvals', () => {
  it('read the service shape, with or without the full parameters and the resolved time', () => {
    const list = parseApprovals({ approvals: [runApproval, { ...runApproval, parametersJSON: '{"kind":"research"}', resolvedAt: AT, state: 'approved' }] })
    expect(list.map(item => item.parametersJSON)).toEqual([undefined, '{"kind":"research"}'])
  })

  it('refuse one without the tool, destination or expiry the service always sends', () => {
    for (const field of ['tool', 'action', 'destination', 'expiresAt']) {
      const rest = Object.fromEntries(Object.entries(runApproval).filter(([key]) => key !== field))
      expect(() => parseApprovals({ approvals: [rest] })).toThrow('approval list')
    }
  })
})

// Routes.swift GET /api/storage: when the computer's disks cannot be read the answer is only {state, reason};
// when they can, the system disk reports totalBytes (no quota) and the workspace a quota with `created`.
const storage = (computer: unknown) => ({
  canCreateAgent: true,
  computer,
  host: { reason: null, registrationsOpen: true, writesAllowed: true },
  limits: { cpu: 2, maxAgents: 8, maxTeams: 3, memoryMB: 3072, workspaceBytes: 10_000_000_000 },
  results: { usedBytes: 1, limitBytes: 2, availableBytes: 1, state: 'ok' },
})

describe('storage', () => {
  it('loads when the computer could not be read', () => {
    expect(parseStorage(storage({ state: 'unavailable', reason: 'Storage usage could not be checked.' })).computer.reason).toContain('could not')
  })

  it('loads the live meters with the system disk reporting its size', () => {
    const live = {
      state: 'ok',
      system: { totalBytes: 100, availableBytes: 40, state: 'ok' },
      workspace: { usedBytes: 5, limitBytes: 10, availableBytes: 5, state: 'ok', created: true },
    }
    expect(parseStorage(storage(live)).computer.system).toEqual(live.system)
  })

  it('still refuses a system disk without its size', () => {
    expect(() => parseStorage(storage({ state: 'ok', system: { state: 'ok' } }))).toThrow('storage')
  })
})
