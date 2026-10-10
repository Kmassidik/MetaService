import { api } from './client.svelte.js'
import { chat } from './state.svelte.js'
import { routineAction } from './profile.svelte.js'
import { routineCreatedSince } from './selectors.js'

// Routine card stopgap: the server sends no "routine created" run event yet, so after a reply
// lands we look for a routine this bot created since the owner's message (server clock only).

function sentMessageTime(messages = [], previousIds) {
  const sent = messages.findLast(message => message.role === 'user' && !previousIds.has(message.id))
  return sent?.createdAt || ''
}

// Only the confirmation card is lost on failure; the routine itself is listed in the profile panel.
function warnRoutineCheckFailed(error) {
  console.warn('Could not check for a routine created in this reply.', error)
  return []
}

async function agentRoutines(agentId) {
  const data = await api(`/api/agents/${encodeURIComponent(agentId)}/routines`)
  return data.routines || []
}

/** Shows the routine card when the bot created a routine while answering this message. */
export async function noticeCreatedRoutine(agentId, messages, previousIds) {
  const since = sentMessageTime(messages, previousIds)
  if (!since) return
  const routines = await agentRoutines(agentId).catch(warnRoutineCheckFailed)
  chat.createdRoutine = routineCreatedSince(routines, agentId, since)
}

/** Pause or resume from the card, then show the routine's new state on it. */
export async function createdRoutineAction(id, action) {
  await routineAction(id, action)
  const updated = chat.profileRoutines.find(routine => routine.id === id)
  if (updated) chat.createdRoutine = updated
}
