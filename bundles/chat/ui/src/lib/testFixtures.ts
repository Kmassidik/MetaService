/** Builders for the tests: a complete record with every field filled, then the test's own fields on top. */
import type { DeviceStorage } from './deviceStore.ts'
import type { Agent, AppRecord, Approval, ChatFile, ChatMessage, Routine, Run, RunEvent, Session, Skill } from './types.ts'

export function agent(over: Partial<Agent> = {}): Agent {
  return {
    id: 'a1', name: 'Atlas', kind: 'bot', status: 'idle', title: '', summary: '', description: '', model: 'auto',
    avatarColor: '#00f56d', avatarShape: 'pebble', createdAt: '2026-10-01T00:00:00.000Z', lastMessagePreview: '',
    lastReadSequence: 0, unreadCount: 0, hidden: false, pinned: false, queuedMessage: false, notifyFinished: true,
    notifyNeedsInput: true, leadAgentId: null, memberAgentIds: [], ...over,
  }
}

export function session(over: Partial<Session> = {}): Session {
  return {
    csrf: 'csrf',
    limits: { cpu: 2, maxAgents: 8, maxTeams: 3, memoryMB: 3072, workspaceBytes: 10_000_000_000 },
    user: { id: 'u1', email: 'ada@example.com', name: 'Ada Lovelace', access: 'active' },
    ...over,
  }
}

export function message(over: Partial<ChatMessage> = {}): ChatMessage {
  return { id: 'm1', role: 'user', text: '', createdAt: '2026-10-01T00:00:00.000Z', ...over }
}

export function run(over: Partial<Run> = {}): Run {
  return {
    id: 'r1', agentId: 'a1', state: 'running', createdAt: '2026-10-01T00:00:00.000Z', updatedAt: '2026-10-01T00:00:00.000Z',
    firstEventSequence: 1, lastEventSequence: 1, ...over,
  }
}

export function runEvent(over: Partial<RunEvent> = {}): RunEvent {
  return { sequence: 1, kind: 'runtime', createdAt: '2026-10-01T00:00:00.000Z', ...over }
}

export function file(over: Partial<ChatFile> = {}): ChatFile {
  return {
    id: 'f1', name: 'notes.txt', size: 10, mediaType: 'text/plain', state: 'ready', createdAt: '2026-10-01T00:00:00.000Z', ...over,
  }
}

export function approval(over: Partial<Approval> = {}): Approval {
  return {
    id: 'ap1', runId: 'r1', state: 'pending', parametersSHA256: 'abc', tool: 'send', action: 'send', destination: 'x',
    expiresAt: '2030-01-01T00:00:00.000Z', ...over,
  }
}

export function skill(over: Partial<Skill> = {}): Skill {
  return { id: 's1', name: 'Summarise', enabled: true, state: 'active', ...over }
}

export function routine(over: Partial<Routine> = {}): Routine {
  return {
    id: 'rt1', title: 'Morning brief', agentId: 'a1', state: 'active', createdAt: '2026-10-01T00:00:00.000Z',
    triggerKind: 'schedule', scheduleKind: 'daily', schedule: { time: '09:00' }, hasWebhook: false, taskText: 'Summarise the news',
    ...over,
  }
}

export function appRecord(over: Partial<AppRecord> = {}): AppRecord {
  return { appId: 'google', ...over }
}

/** A device storage that keeps its values in memory and shows them for the test to read. */
export function memoryStorage(initial: Record<string, string> = {}): DeviceStorage & { values: Map<string, string> } {
  const values = new Map(Object.entries(initial))
  return {
    values,
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => { values.set(key, String(value)) },
  }
}

/** A device storage whose every call throws, like a private window with site data blocked. */
export const blockedStorage: DeviceStorage = {
  getItem() { throw new Error('blocked') },
  setItem() { throw new Error('blocked') },
}
