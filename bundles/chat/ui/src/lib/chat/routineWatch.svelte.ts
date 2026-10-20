import { parseRoutines } from '../answers/profile.ts'
import type { ChatMessage, Routine } from '../types.ts'
import { api } from './client.svelte.ts'
import { chat } from './state.svelte.ts'
import { routineAction } from './profile.svelte.ts'
import { routineCreatedSince } from './selectors.ts'

// Routine card stopgap: the server sends no "routine created" run event yet, so after a reply
// lands we look for a routine this bot created since the owner's message (server clock only).

function sentMessageTime(messages: readonly ChatMessage[] = [], previousIds: ReadonlySet<string>): string {
  const sent = [...messages].reverse().find(message => message.role === 'user' && !previousIds.has(message.id))
  return sent?.createdAt || ''
}

// Only the confirmation card is lost on failure; the routine itself is listed in the profile panel.
function warnRoutineCheckFailed(error: unknown): Routine[] {
  console.warn('Could not check for a routine created in this reply.', error)
  return []
}

async function agentRoutines(agentId: string): Promise<Routine[]> {
  return parseRoutines(await api(`/api/agents/${encodeURIComponent(agentId)}/routines`))
}

/** Shows the routine card when the bot created a routine while answering this message. */
export async function noticeCreatedRoutine(agentId: string, messages: readonly ChatMessage[], previousIds: ReadonlySet<string>): Promise<void> {
  const since = sentMessageTime(messages, previousIds)
  if (!since) return
  const routines = await agentRoutines(agentId).catch(warnRoutineCheckFailed)
  chat.createdRoutine = routineCreatedSince(routines, agentId, since)
}

/** Pause or resume from the card, then show the routine's new state on it. */
export async function createdRoutineAction(id: string, action: string): Promise<void> {
  await routineAction(id, action)
  const updated = chat.profileRoutines.find(routine => routine.id === id)
  if (updated) chat.createdRoutine = updated
}
