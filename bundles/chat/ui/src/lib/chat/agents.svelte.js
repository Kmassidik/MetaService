import { tick, untrack } from 'svelte'
import { MAX_GROUP_CHATS, MAX_GROUP_MEMBERS, instructionPresets } from '../constants.js'
import { fail, bytes } from '../format.js'
import { api } from './client.svelte.js'
import { updateEnvironment } from './environment.svelte.js'
import { cancelUpload } from './files.svelte.js'
import { loadHistory, scrollToLatest } from './messages.svelte.js'
import { keepDraftBots } from './draftBots.js'
import { guardUnsaved } from './unsavedGuard.svelte.js'
import { openSettings } from '../settingsSections.js'
import { loadUsage, loadStorage, loadStorageGate } from './usage.svelte.js'
import {
  chat,
  fileSession,
  historyVersions,
  selectedAgent,
  readyBots,
  agentLimitReached,
  storageBlocked,
  createTeamBlocked,
  teamLimitReached,
  planLimits,
} from './state.svelte.js'

export function resetAgentForm() {
  chat.editId = ''; chat.formName = ''; chat.formDescription = ''; chat.formKind = 'bot'
  chat.formLeadId = ''; chat.formMemberIds = []; chat.formError = ''; chat.presetId = ''; chat.presetNotice = ''
}

export function validateTeam() {
  const bots = readyBots()
  if (!bots.some(bot => bot.id === chat.formLeadId)) return 'Choose a ready bot to lead the group.'
  if (!chat.formMemberIds.length || chat.formMemberIds.length > MAX_GROUP_MEMBERS) return `Choose 1–${MAX_GROUP_MEMBERS} member bots (${MAX_GROUP_MEMBERS + 1} bots max with the lead).`
  if (new Set(chat.formMemberIds).size !== chat.formMemberIds.length || chat.formMemberIds.includes(chat.formLeadId)) return 'The lead and every member must be different bots.'
  if (chat.formMemberIds.some(id => !bots.some(bot => bot.id === id))) return 'Every member must be a ready bot. Update your selection.'
  return ''
}

export function chooseLead(event) {
  chat.formLeadId = event.currentTarget.value
  chat.formMemberIds = chat.formMemberIds.filter(id => id !== chat.formLeadId)
}

export function applyPreset() {
  const selectedPreset = instructionPresets.find(preset => preset.id === chat.presetId)
  if (!selectedPreset || chat.saving) return
  const next = [chat.formDescription.trim(), selectedPreset.text].filter(Boolean).join('\n\n')
  if (bytes(next) > 4000) { chat.presetNotice = 'This would exceed 4000 bytes. Shorten the existing instructions first.'; return }
  chat.formDescription = next
  chat.presetNotice = 'Added to instructions below. Review and edit before chat.saving.'
  chat.presetId = ''
}

// A bot still being set up, or a message waiting to run once it is ready, keeps the roster polling.
const isWaitingForComputer = agent => agent.status === 'provisioning' || agent.queuedMessage

export async function loadAgents() {
  const version = ++chat.agentsVersion
  const currentEnvironmentVersion = chat.environmentVersion
  let retry = false
  chat.agentsError = ''
  clearTimeout(chat.provisioningPoll)
  try {
    const data = await api('/api/agents')
    if (!chat.alive || !chat.session || version !== chat.agentsVersion) return
    if (!chat.environmentAction && currentEnvironmentVersion === chat.environmentVersion) updateEnvironment(data.environment)
    chat.agents = keepDraftBots(chat.agents, data.agents)
    if (data.limits) chat.session = { ...chat.session, limits: data.limits }
    if (!chat.selectedId || !chat.agents.some(agent => agent.id === chat.selectedId)) chat.selectedId = chat.agents[0]?.id || ''
    if (chat.selectedId && chat.environment?.state !== 'deleting') {
      const selected = chat.agents.find(agent => agent.id === chat.selectedId)
      if (selected?.status === 'idle' || selected?.status === 'running') await loadHistory(chat.selectedId)
    }
  } catch (error) {
    if (chat.alive && chat.session && version === chat.agentsVersion) { chat.agentsError = fail(error); retry = true }
  } finally {
    if (chat.alive && chat.session && version === chat.agentsVersion && !chat.environmentAction) {
      const waiting = chat.agents.some(isWaitingForComputer) || ['provisioning', 'deleting'].includes(chat.environment?.state)
      if (waiting || retry) chat.provisioningPoll = setTimeout(loadAgents, retry ? 5000 : 2000)
    }
  }
}

/**
 * A light roster refresh with no chat history: the Workspace polls it for every bot's status and
 * live activity. A newer full load wins over a refresh that was already on its way.
 */
export async function refreshRoster() {
  const version = chat.agentsVersion
  try {
    const data = await api('/api/agents')
    if (!chat.alive || !chat.session || version !== chat.agentsVersion) return
    chat.agents = keepDraftBots(chat.agents, data.agents)
    chat.agentsError = ''
  } catch (error) {
    if (chat.alive && chat.session && version === chat.agentsVersion) chat.agentsError = fail(error)
  }
}

/** Opens a bot's chat; unsaved Details edits for the current bot are asked about first. */
export function selectAgent(id) {
  if (id === chat.selectedId) return switchAgent(id)
  return guardUnsaved(() => switchAgent(id))
}

async function switchAgent(id) {
  chat.selectedId = id
  chat.atLatest = true
  chat.unreadMessages = false
  chat.messageSearch = ''
  chat.matchIndex = 0
  chat.mobileRail = false
  chat.mentionOpen = false
  chat.mentionError = ''
  chat.replyParent = ''
  if (chat.pending?.id !== id) await loadHistory(id)
  else await scrollToLatest()
  try {
    const data = await api(`/api/agents/${encodeURIComponent(id)}/read`, { method: 'POST', body: '{}' })
    if (data.agent) chat.agents = chat.agents.map(agent => agent.id === id ? { ...agent, ...data.agent } : agent)
  } catch {}
}

export async function patchRoster(fields, agentId = null) {
  const target = agentId
    ? chat.agents.find(agent => agent.id === agentId)
    : selectedAgent()
  if (!target) return
  const data = await api(`/api/agents/${encodeURIComponent(target.id)}`, {
    method: 'PATCH',
    body: JSON.stringify({
      name: target.name, description: target.description || '', model: target.model || 'auto',
      title: target.title || '', summary: target.summary || '', ...fields,
    }),
  })
  if (data.agent) chat.agents = chat.agents.map(agent => agent.id === target.id ? { ...agent, ...data.agent } : agent)
}

export async function duplicateAgent(agentId = null) {
  const target = agentId
    ? chat.agents.find(agent => agent.id === agentId)
    : selectedAgent()
  if (!target || target.kind === 'team') return
  const data = await api(`/api/agents/${encodeURIComponent(target.id)}/duplicate`, { method: 'POST', body: '{}' })
  await loadAgents()
  if (data.agent?.id) await selectAgent(data.agent.id)
}

export async function duplicateActive() {
  await duplicateAgent()
}

export async function shareTemplate() {
  const active = selectedAgent()
  if (!active || active.kind === 'team') return
  try {
    const data = await api(`/api/agents/${encodeURIComponent(active.id)}/share`, { method: 'POST', body: '{}' })
    const token = data.template?.token
    const warning = data.template?.secretWarning
      ? ' Warning: key-like text was detected — review before sharing.'
      : ''
    chat.webhookNotice = token
      ? `Template link path /api/templates/${token} (copy once). Import with POST …/import.${warning}`
      : 'Template created.'
    chat.profileNotice = chat.webhookNotice
  } catch (error) {
    chat.profileError = fail(error)
  }
}

export async function openMentionPicker() {
  chat.mentionOpen = !chat.mentionOpen
  chat.skillPickerOpen = false
  chat.mentionError = ''
  if (!chat.mentionOpen || !chat.session) return
  try {
    const [routines, connectors] = await Promise.all([
      api('/api/routines'),
      api('/api/connectors'),
    ])
    chat.mentionRoutines = routines.routines || []
    chat.mentionConnectors = connectors.connectors || []
  } catch {
    chat.mentionRoutines = []
    chat.mentionConnectors = []
  }
}

export async function refreshMarketplaceConnections() {
  if (!chat.session) return
  try {
    const connectors = await api('/api/connectors').catch(() => ({ connectors: [] }))
    chat.mentionConnectors = connectors.connectors || []
    chat.nangoEnabled = false
    chat.nangoIntegrations = []
    chat.nangoConnections = []
  } catch {
    /* keep last known */
  }
}

export async function mentionBot(botId) {
  const active = selectedAgent()
  if (!active || chat.mentionBusy || chat.pending || chat.usage?.blocked) return
  const key = chat.session?.csrf
  chat.mentionBusy = true
  chat.mentionError = ''
  try {
    const data = await api(`/api/agents/${encodeURIComponent(active.id)}/mention`, {
      method: 'POST',
      body: JSON.stringify({ botId }),
    })
    if (!fileSession(key)) return
    chat.mentionOpen = false
    chat.mentionQuery = ''
    if (data.createdGroup && data.agent) {
      if ('environment' in data) updateEnvironment(data.environment)
      chat.agents = [...chat.agents.filter(agent => agent.id !== data.agent.id), data.agent]
      chat.selectedId = data.agent.id
      if (data.agent.status === 'idle') await loadHistory(data.agent.id)
      else {
        clearTimeout(chat.provisioningPoll)
        chat.provisioningPoll = setTimeout(() => { if (chat.alive && chat.session) loadAgents() }, 1500)
      }
    } else {
      if (data.messages) chat.histories = { ...chat.histories, [active.id]: data.messages }
      if (data.computer) chat.computers = { ...chat.computers, [active.id]: data.computer }
      await loadAgents()
      await scrollToLatest()
    }
  } catch (error) {
    if (fileSession(key)) chat.mentionError = fail(error)
  } finally {
    if (fileSession(key)) chat.mentionBusy = false
  }
}

export function openModal(kind, agentId = null, section = null) {
  const active = agentId
    ? chat.agents.find(agent => agent.id === agentId)
    : selectedAgent()
  if (kind === 'create-team' && createTeamBlocked()) return
  chat.formError = ''
  chat.editId = active?.id || ''
  chat.formName = kind === 'edit' ? (active?.name || '') : ''
  chat.formDescription = kind === 'edit' ? (active?.description || '') : ''
  chat.formKind = kind === 'create-team' || (['edit', 'team', 'delete'].includes(kind) && active?.kind === 'team') ? 'team' : 'bot'
  chat.formLeadId = kind === 'edit' && chat.formKind === 'team' ? active?.leadAgentId || '' : ''
  chat.formMemberIds = kind === 'edit' && chat.formKind === 'team' ? [...(active?.memberAgentIds || [])] : []
  chat.presetId = ''
  chat.presetNotice = ''
  chat.settings = openSettings(section)
  chat.modal = kind === 'create-team' ? 'create' : kind
  chat.mobileRail = false
  chat.dialog.showModal()
  tick().then(() => { if (chat.dialog?.open && ['create', 'edit'].includes(chat.modal)) document.getElementById('bot-name')?.focus() })
  if (kind === 'account') {
    chat.confirmEnvironmentDeletion = false
    chat.environmentConfirmation = ''
    chat.confirmAccountDeletion = false
    chat.accountConfirmation = ''
    chat.accountDeletionError = ''
    loadUsage()
    loadStorage()
  }
  if (kind === 'marketplace') {
    refreshMarketplaceConnections()
  }
}

export function closeModal() {
  if (chat.saving || chat.loggingOut || chat.environmentAction || chat.deletingAccount) return
  chat.dialog?.close()
  chat.modal = null
  resetAgentForm()
}

export async function saveAgent(event) {
  event.preventDefault()
  if (chat.saving || !chat.formName.trim()) return
  const limits = planLimits()
  const teamFormError = chat.formKind === 'team' ? validateTeam() : ''
  if (chat.modal === 'create' && chat.formKind === 'bot' && agentLimitReached()) { chat.formError = `Your free beta allows up to ${limits.maxAgents} bots. Delete a bot before creating another.`; return }
  if (chat.modal === 'create' && chat.formKind === 'team' && teamLimitReached()) { chat.formError = `You can save up to ${MAX_GROUP_CHATS} group chats. Delete a group before creating another.`; return }
  if (teamFormError) { chat.formError = teamFormError; return }
  if (bytes(chat.formName.trim()) > 120) { chat.formError = 'Name must be 120 UTF-8 bytes or fewer.'; return }
  if (bytes(chat.formDescription.trim()) > 4000) { chat.formError = 'Instructions must be 4000 UTF-8 bytes or fewer.'; return }
  chat.saving = true
  chat.formError = ''
  const editing = chat.modal === 'edit'
  const key = chat.session?.csrf
  const targetId = chat.editId
  const fields = { name: chat.formName.trim(), description: chat.formDescription.trim(), model: 'auto', ...(chat.formKind === 'team' ? { kind: 'team', leadAgentId: chat.formLeadId, memberAgentIds: [...chat.formMemberIds] } : {}) }
  try {
    if (!editing) {
      await loadStorageGate()
      if (!fileSession(key)) return
      if (storageBlocked() || !chat.storage) { chat.formError = chat.storage?.creationBlockedReason || chat.storageError || 'Storage capacity is being checked. Try again shortly.'; return }
    }
    const data = await api(editing ? `/api/agents/${encodeURIComponent(targetId)}` : '/api/agents', {
      method: editing ? 'PATCH' : 'POST',
      body: JSON.stringify(fields),
    })
    if (!fileSession(key)) return
    if ('environment' in data) updateEnvironment(data.environment)
    chat.agents = editing ? chat.agents.map(agent => agent.id === data.agent.id ? data.agent : agent) : [...chat.agents, data.agent]
    chat.saving = false
    closeModal()
    chat.selectedId = data.agent.id
    if (data.agent.status === 'idle') await loadHistory(data.agent.id)
    else {
      clearTimeout(chat.provisioningPoll)
      chat.provisioningPoll = setTimeout(() => { if (chat.alive && chat.session) loadAgents() }, 1500)
    }
    await tick()
    if (data.agent.status === 'idle') chat.composer?.focus()
  } catch (error) { if (fileSession(key)) chat.formError = fail(error) }
  finally { if (fileSession(key)) chat.saving = false }
}

export async function deleteAgent() {
  if (chat.saving || chat.pending) return
  chat.saving = true
  chat.formError = ''
  const id = chat.editId
  const key = chat.session?.csrf
  await Promise.all(chat.uploads.filter(upload => upload.agentId === id).map(cancelUpload))
  if (!fileSession(key)) return
  if (chat.uploads.some(upload => upload.agentId === id && upload.status === 'Cleanup failed')) { chat.formError = `Remove unfinished chat.uploads before deleting this ${chat.formKind}.`; chat.saving = false; return }
  try {
    await api(`/api/agents/${encodeURIComponent(id)}`, { method: 'DELETE' })
    if (!fileSession(key)) return
    chat.agents = chat.agents.filter(agent => agent.id !== id)
    historyVersions.set(id, (historyVersions.get(id) || 0) + 1)
    const { [id]: _removedHistory, ...remainingHistory } = chat.histories
    const { [id]: _removedDraft, ...remainingDrafts } = chat.drafts
    chat.histories = remainingHistory
    chat.drafts = remainingDrafts
    chat.saving = false
    closeModal()
    if (chat.selectedId === id) {
      chat.selectedId = ''
      if (chat.agents.length) await selectAgent(chat.agents[0].id)
    }
  } catch (error) { if (fileSession(key)) chat.formError = fail(error) }
  finally { if (fileSession(key)) chat.saving = false }
}

/** Must run during App component init (not at module import). */
export function installAgentEffects() {
  $effect(() => {
    const key = chat.session?.csrf
    untrack(() => {
      if (chat.formSessionKey === key) return
      chat.formSessionKey = key
      chat.dialog?.close(); chat.modal = null; chat.saving = false; resetAgentForm()
    })
  })
}
