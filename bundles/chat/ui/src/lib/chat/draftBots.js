/**
 * A draft bot is the optimistic sidebar row and chat that New bot shows while the server creates
 * the real one (well under a second). Pure helpers, so the rules are testable without Svelte.
 */
import { NEW_BOT_NAME } from '../constants.js'

const DRAFT_PREFIX = 'draft-'
const PROVISIONING = 'provisioning'

export const isDraftBot = id => typeof id === 'string' && id.startsWith(DRAFT_PREFIX)

/** Task status is only asked for a real, saved bot: a draft has no runs on the server yet. */
export const watchesRuns = (id, sessionKey) => Boolean(id) && Boolean(sessionKey) && !isDraftBot(id)

/** A local stand-in for the New bot being created, wearing the avatar that will be sent. */
export function draftBot(avatar, now = new Date()) {
  return {
    id: `${DRAFT_PREFIX}${now.getTime()}`, name: NEW_BOT_NAME, kind: 'bot', status: PROVISIONING,
    title: '', summary: '', description: '', lastMessagePreview: '', createdAt: now.toISOString(), ...avatar,
  }
}

/** A roster refresh from the server keeps any draft that is still waiting for its real bot. */
export function keepDraftBots(current = [], incoming = []) {
  return [...current.filter(agent => isDraftBot(agent.id)), ...incoming]
}

/** The roster once the server answered: the real bot first, the draft and any stale copy gone. */
export function replaceDraftBot(agents = [], draftId, created) {
  return [created, ...agents.filter(agent => agent.id !== draftId && agent.id !== created.id)]
}
