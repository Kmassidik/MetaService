import { fail, bytes } from '../format.js'
import { api } from './client.svelte.js'
import { PROFILE_LIMITS } from '../constants.js'
import { PANEL_TABS } from '../sidePanel.js'
import { chat, fileSession, selectedAgent } from './state.svelte.js'
import { patchRoster } from './agents.svelte.js'
import { openSidePanel } from './sidePanel.svelte.js'
import { continueLeave, dropLeave } from './unsavedGuard.svelte.js'
import { createSavedFlash } from '../savedFlash.js'

/** Keys of the controls that show a brief "Saved" tick (chat.profileSaved). */
export const SAVED_TICK = Object.freeze({
  details: 'details', label: 'label', avatar: 'avatar', notifications: 'notifications', skills: 'skills', more: 'more',
})

const savedFlash = createSavedFlash((key, shown) => {
  chat.profileSaved = { ...chat.profileSaved, [key]: shown }
})

export async function createWebhookRoutine() {
  const active = selectedAgent()
  if (!active || active.kind === 'team') return
  const title = window.prompt('Webhook routine title')
  if (!title?.trim()) return
  const taskText = window.prompt('Task for the bot when the webhook fires', 'Handle the inbound event.')
  if (!taskText?.trim()) return
  try {
    const data = await api(`/api/agents/${encodeURIComponent(active.id)}/routines`, {
      method: 'POST',
      body: JSON.stringify({
        title: title.trim(),
        taskText: taskText.trim(),
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
        triggerKind: 'webhook',
      }),
    })
    const token = data.routine?.webhookToken
    chat.profileRoutines = [data.routine, ...chat.profileRoutines.filter(routine => routine.id !== data.routine?.id)]
    chat.webhookNotice = token
      ? `Copy now — webhook URL path /api/hooks/routines/${token} (token shown once).`
      : 'Webhook routine created.'
    chat.profileNotice = chat.webhookNotice
  } catch (error) {
    chat.profileError = fail(error)
  }
}

/** Fills the side panel's Details for the selected bot: its fields, routines, skills and memory. */
export async function loadProfile() {
  const active = selectedAgent()
  if (!active || active.kind === 'team') return
  fillProfileForm(active)
  dropLeave()
  chat.profileError = ''
  chat.profileHighlight = {}
  try {
    const [routines, skills, memory] = await Promise.all([
      api(`/api/agents/${encodeURIComponent(active.id)}/routines`),
      api(`/api/skills?agent=${encodeURIComponent(active.id)}`),
      api(`/api/agents/${encodeURIComponent(active.id)}/memory`),
    ])
    chat.profileRoutines = routines.routines || []
    chat.profileSkills = skills.skills || []
    chat.profileMemory = memory.entries || []
  } catch {
    chat.profileRoutines = []; chat.profileSkills = []; chat.profileMemory = []
  }
}

export async function routineAction(id, action) {
  if (action === 'delete') await api(`/api/routines/${encodeURIComponent(id)}`, { method: 'DELETE' })
  else if (action === 'test') await api(`/api/routines/${encodeURIComponent(id)}/test`, { method: 'POST', body: '{}' })
  else await api(`/api/routines/${encodeURIComponent(id)}/${action}`, { method: 'POST', body: '{}' })
  const active = selectedAgent()
  if (active) {
    const data = await api(`/api/agents/${encodeURIComponent(active.id)}/routines`)
    chat.profileRoutines = data.routines || []
  }
}

export async function toggleSkill(skillId, enabled) {
  const active = selectedAgent()
  if (!active) return
  try {
    await api(`/api/agents/${encodeURIComponent(active.id)}/skills/${encodeURIComponent(skillId)}`, {
      method: 'POST', body: JSON.stringify({ enabled }),
    })
    const data = await api(`/api/skills?agent=${encodeURIComponent(active.id)}`)
    chat.profileSkills = data.skills || []
    savedFlash.show(SAVED_TICK.skills)
  } catch (error) {
    chat.profileError = fail(error)
  }
}

/** A Details control that saves on its own (avatar, notifications, pin…), with its "Saved" tick. */
export async function patchProfileSetting(tick, fields) {
  try {
    await patchRoster(fields)
    savedFlash.show(tick)
  } catch (error) {
    chat.profileError = fail(error)
  }
}

export async function clearMemory() {
  const active = selectedAgent()
  if (!active) return
  await api(`/api/agents/${encodeURIComponent(active.id)}/memory`, { method: 'DELETE' })
  chat.profileMemory = []
}

/** Refreshes the / picker's skills; resolves to an error message for the picker, or ''. */
export async function loadSkills() {
  const active = selectedAgent()
  if (!active) return ''
  try {
    const data = await api(`/api/skills?agent=${encodeURIComponent(active.id)}`)
    chat.profileSkills = data.skills || []
    return ''
  } catch (error) {
    chat.profileSkills = []
    return error.message || 'Couldn’t load skills.'
  }
}

export async function teachTask() {
  const active = selectedAgent()
  if (!active || !chat.teachName.trim() || !chat.teachDescription.trim()) return
  const data = await api(`/api/agents/${encodeURIComponent(active.id)}/teach`, {
    method: 'POST', body: JSON.stringify({ name: chat.teachName.trim(), description: chat.teachDescription.trim() }),
  })
  chat.teachName = ''; chat.teachDescription = ''
  chat.teachOpen = false
  if (!data.skill) return
  await openSidePanel(PANEL_TABS.details)
  chat.profileNotice = `Draft skill “${data.skill.name}” created`
}

/** The "Add a label" line under the bot's name, saved on its own as the bot's title. */
export async function saveTitle(title) {
  const trimmed = title.trim()
  if (bytes(trimmed) > PROFILE_LIMITS.title) {
    chat.profileError = `The label must be ${PROFILE_LIMITS.title} bytes or fewer.`
    return
  }
  try {
    await patchRoster({ title: trimmed })
    chat.profileTitle = trimmed
    savedFlash.show(SAVED_TICK.label)
  } catch (error) {
    chat.profileError = fail(error)
  }
}

/** Puts the bot's saved profile into the Details form. */
function fillProfileForm(agent) {
  chat.profileName = agent.name || ''
  chat.profileTitle = agent.title || ''
  chat.profileSummary = agent.summary || ''
  chat.profileInstructions = agent.description || ''
}

// Why the form can't be saved as it is, or ''.
function profileProblem(name) {
  if (!name || bytes(name) > PROFILE_LIMITS.name) return `Name is required (≤${PROFILE_LIMITS.name} bytes).`
  const tooLong = bytes(chat.profileTitle) > PROFILE_LIMITS.title
    || bytes(chat.profileSummary) > PROFILE_LIMITS.summary
    || bytes(chat.profileInstructions) > PROFILE_LIMITS.instructions
  return tooLong ? 'One of the fields is too long.' : ''
}

function patchProfile(agent, name) {
  return api(`/api/agents/${encodeURIComponent(agent.id)}`, {
    method: 'PATCH',
    body: JSON.stringify({
      name, title: chat.profileTitle.trim(), summary: chat.profileSummary.trim(),
      description: chat.profileInstructions.trim(), model: 'auto',
    }),
  })
}

function applySavedProfile(agent) {
  chat.agents = chat.agents.map(item => item.id === agent.id ? { ...item, ...agent } : item)
  fillProfileForm(agent)
  savedFlash.show(SAVED_TICK.details)
}

/** Saves the Details form; resolves true once the bot has the new profile. */
export async function saveProfile(event) {
  event?.preventDefault?.()
  const active = selectedAgent()
  if (!active || chat.profileSaving || Boolean(chat.pending)) return false
  const name = chat.profileName.trim()
  chat.profileError = profileProblem(name)
  if (chat.profileError) return false
  const key = chat.session.csrf
  chat.profileSaving = true
  try {
    const data = await patchProfile(active, name)
    if (!fileSession(key)) return false
    applySavedProfile(data.agent)
    return true
  } catch (error) {
    if (fileSession(key)) chat.profileError = fail(error)
    return false
  } finally {
    if (fileSession(key)) chat.profileSaving = false
  }
}

/** Unsaved-changes prompt → Save: save, then go where the owner was heading. */
export async function saveAndLeave() {
  if (await saveProfile()) return continueLeave()
}

/** Unsaved-changes prompt → Discard: put the saved profile back, then go. */
export function discardAndLeave() {
  const active = selectedAgent()
  if (active) fillProfileForm(active)
  return continueLeave()
}
