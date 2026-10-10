import { tick } from 'svelte'
import { fail, bytes } from '../format.js'
import { api } from './client.svelte.js'
import { loadFiles } from './files.svelte.js'
import { loadUsage } from './usage.svelte.js'
import { updateRun } from './runsUpdate.svelte.js'
import { isAwaitingComputer, visibleMessages } from './selectors.js'
import { isDraftBot } from './draftBots.js'
import { noticeCreatedRoutine } from './routineWatch.svelte.js'
import { currentSendMode, sendFollowUp } from './followUps.svelte.js'
import { SEND_MODE, hasSendableInput } from '../sendMode.js'
import {
  chat,
  fileSession,
  historyVersions,
  computerVersions,
  selectedAgent,
} from './state.svelte.js'

export function trackScroll() {
  if (!chat.messageList) return
  chat.atLatest = chat.messageList.scrollHeight - chat.messageList.scrollTop - chat.messageList.clientHeight < 64
  if (chat.atLatest) chat.unreadMessages = false
}

export function matchingMessages() {
  const query = chat.messageSearch.trim().toLowerCase()
  if (!query) return []
  return visibleMessages(chat.histories[chat.selectedId] || [])
    .filter(message => (message.text || '').toLowerCase().includes(query))
}

// The header search button is gone, so Cmd/Ctrl+F is how a chat is searched.
const FIND_KEY = 'f'

/** Window keydown handler: Cmd/Ctrl+F opens find-in-chat while a conversation is open. */
export function openFindOnShortcut(event) {
  if (event.key.toLowerCase() !== FIND_KEY || !(event.metaKey || event.ctrlKey)) return
  if (!chat.selectedId) return
  event.preventDefault()
  chat.showSearch = true
}

export async function findMessage(direction = 0) {
  const matches = matchingMessages()
  if (!matches.length) { chat.matchIndex = 0; return }
  chat.matchIndex = (chat.matchIndex + direction + matches.length) % matches.length
  await tick()
  const matchedMessageId = matches[chat.matchIndex]?.id
  const target = document.getElementById(`message-${matchedMessageId}`)
  if (target && chat.messageList) chat.messageList.scrollTop += target.getBoundingClientRect().top - chat.messageList.getBoundingClientRect().top - 16
  trackScroll()
}

export async function scrollToLatest() {
  const id = chat.selectedId
  await tick()
  if (chat.selectedId !== id) return
  if (chat.messageList) chat.messageList.scrollTop = chat.messageList.scrollHeight
  chat.atLatest = true
  chat.unreadMessages = false
}

/** Keep rail last-message preview in sync when history loads without waiting for GET /api/agents. */
function syncAgentPreview(id, messages) {
  let preview = ''
  for (let i = (messages || []).length - 1; i >= 0; i -= 1) {
    const message = messages[i]
    const text = String(message.text || '').replace(/\s+/g, ' ').trim()
    if (text) { preview = text.length > 140 ? text.slice(0, 140) : text; break }
    if ((message.attachmentIds || []).length) { preview = 'Attachment'; break }
  }
  chat.agents = chat.agents.map(agent => agent.id === id ? { ...agent, lastMessagePreview: preview } : agent)
}

export async function loadHistory(id) {
  const key = chat.session?.csrf
  const version = (historyVersions.get(id) || 0) + 1
  const computerVersion = computerVersions.get(id)
  historyVersions.set(id, version)
  chat.loading = { ...chat.loading, [id]: true }
  chat.errors = { ...chat.errors, [id]: '' }
  try {
    const data = await api(`/api/agents/${encodeURIComponent(id)}/messages`)
    if (!fileSession(key) || historyVersions.get(id) !== version) return
    const wasAtLatest = chat.atLatest && !chat.messageSearch.trim()
    const previousLastId = chat.histories[id]?.at(-1)?.id
    chat.histories = { ...chat.histories, [id]: data.messages }
    syncAgentPreview(id, data.messages)
    if (computerVersions.get(id) === computerVersion && !chat.computerBusy[id]) chat.computers = { ...chat.computers, [id]: data.computer }
    if (data.pending) {
      chat.agents = chat.agents.map(agent => agent.id === id ? { ...agent, status: 'running' } : agent)
    } else if (chat.agents.some(agent => agent.id === id && agent.status === 'running')) {
      loadFiles()
      chat.agents = chat.agents.map(agent => agent.id === id ? { ...agent, status: 'idle' } : agent)
    }
    chat.errors = { ...chat.errors, [id]: data.lastError || '' }
    if (chat.selectedId === id) {
      if (wasAtLatest) await scrollToLatest()
      else if (data.messages.at(-1)?.id !== previousLastId) chat.unreadMessages = true
    }
  } catch (error) {
    if (fileSession(key) && historyVersions.get(id) === version) {
      chat.errors = { ...chat.errors, [id]: fail(error) }
    }
  } finally {
    if (fileSession(key) && historyVersions.get(id) === version) chat.loading = { ...chat.loading, [id]: false }
  }
}

/**
 * A bot still being set up takes one message, which runs once its computer is ready; a failed
 * bot and the draft shown before the server answers take none.
 */
function acceptsMessages(active) {
  return Boolean(active) && active.status !== 'failed' && !isDraftBot(active.id) && !isAwaitingComputer(active)
}

const MAX_MESSAGE_BYTES = 16000

// Nothing account-wide blocks sending: no computer change, sign-out or exhausted allowance.
function workspaceIdle() {
  return chat.environment?.state !== 'deleting' && !chat.environmentAction && !chat.loggingOut && !chat.usage?.blocked
}

// This chat is loaded and free: no upload, send or computer action in flight, no takeover.
function conversationIdle(id) {
  const computer = chat.computers[id] || {}
  const uploading = chat.uploads.some(upload => upload.agentId === id)
  return Boolean(chat.histories[id]) && !uploading && !chat.pending && !chat.loading[id]
    && computer.state !== 'takeover' && !chat.computerBusy[id]
}

// Everything that must be true before anything can be sent, turn or follow-up.
function composerOpen(active) {
  return acceptsMessages(active) && workspaceIdle() && conversationIdle(chat.selectedId)
}

export function canSendMessage() {
  const text = (chat.drafts[chat.selectedId] || '').trim()
  if (!composerOpen(selectedAgent()) || bytes(text) > MAX_MESSAGE_BYTES) return false
  const attachmentCount = (chat.attachments[chat.selectedId] || []).length
  return hasSendableInput(currentSendMode(), { text, attachmentCount })
}

/** Send starts a turn, or while the bot works queues a text-only follow-up on its task. */
export async function sendMessage(event, overrideText) {
  event?.preventDefault?.()
  if (currentSendMode() !== SEND_MODE.followUp) return sendTurn(overrideText)
  if (overrideText === undefined && !canSendMessage()) return
  await sendFollowUp((overrideText ?? chat.drafts[chat.selectedId] ?? '').trim())
  await scrollToLatest()
}

async function sendTurn(overrideText) {
  const id = chat.selectedId
  const key = chat.session.csrf
  const active = selectedAgent()
  const sentAttachments = [...(chat.attachments[id] || [])]
  const text = (overrideText ?? (chat.drafts[id] || '')).trim()
  if (!text && !sentAttachments.length) return
  if (chat.pending?.id === id || active?.status === 'running' || !acceptsMessages(active)) return
  if (!canSendMessage() && overrideText === undefined) return
  const previousMessages = new Set((chat.histories[id] || []).map(message => message.id))
  chat.pending = { id, text, attachments: sentAttachments }
  chat.createdRoutine = null
  chat.drafts = { ...chat.drafts, [id]: '' }
  chat.errors = { ...chat.errors, [id]: '' }
  historyVersions.set(id, (historyVersions.get(id) || 0) + 1)
  await scrollToLatest()
  try {
    const data = await api(`/api/agents/${encodeURIComponent(id)}/messages`, { method: 'POST', body: JSON.stringify({ text, attachments: sentAttachments.map(file => file.id) }) })
    if (!fileSession(key)) return
    chat.attachments = { ...chat.attachments, [id]: (chat.attachments[id] || []).filter(file => !sentAttachments.some(sent => sent.id === file.id)) }
    loadFiles()
    chat.histories = { ...chat.histories, [id]: data.messages }
    syncAgentPreview(id, data.messages)
    if (!data.pending) noticeCreatedRoutine(id, data.messages, previousMessages)
    chat.computers = { ...chat.computers, [id]: data.computer }
    chat.errors = { ...chat.errors, [id]: data.lastError || '' }
    if (data.run) {
      updateRun(data.run)
      chat.reconnectRun += 1
    } else if (data.pending) {
      chat.agents = chat.agents.map(agent => agent.id === id ? { ...agent, status: 'running' } : agent)
      chat.reconnectRun += 1
    } else {
      // No run yet: the bot's computer is still being set up, and the message runs once it's ready.
      chat.agents = chat.agents.map(agent => agent.id === id ? { ...agent, queuedMessage: true } : agent)
    }
  } catch (error) {
    if (!fileSession(key)) return
    const reason = fail(error)
    await loadHistory(id)
    if (!fileSession(key)) return
    const retained = chat.histories[id]?.some(message => !previousMessages.has(message.id) && message.role === 'user' && message.text === text)
    if (!retained) chat.drafts = { ...chat.drafts, [id]: chat.drafts[id] || text }
    chat.errors = { ...chat.errors, [id]: `${reason} The request may have reached your bot; review the conversation before sending again.` }
  } finally {
    if (fileSession(key)) {
      chat.pending = null
      if (chat.selectedId === id && chat.atLatest && !chat.messageSearch.trim()) await scrollToLatest()
      else if (chat.selectedId === id) chat.unreadMessages = true
      if (chat.session) await loadUsage()
    }
  }
}

export async function toggleReaction(messageId, emoji) {
  const active = selectedAgent()
  if (!active) return
  const existing = (chat.histories[chat.selectedId] || []).find(message => message.id === messageId)
  const has = (existing?.reactions || []).some(reaction => reaction.emoji === emoji)
  const data = await api(`/api/agents/${encodeURIComponent(active.id)}/messages/${encodeURIComponent(messageId)}/reactions`, {
    method: 'POST', body: JSON.stringify({ emoji, on: !has }),
  })
  if (data.message) {
    chat.histories = {
      ...chat.histories,
      [chat.selectedId]: (chat.histories[chat.selectedId] || []).map(message => message.id === messageId ? { ...message, reactions: data.message.reactions || [] } : message),
    }
  }
}

export async function sendThreadReply(parentId) {
  const active = selectedAgent()
  if (!active) return
  const text = (chat.replyDrafts[parentId] || '').trim()
  if (!text) return
  const data = await api(`/api/agents/${encodeURIComponent(active.id)}/messages/${encodeURIComponent(parentId)}/replies`, {
    method: 'POST', body: JSON.stringify({ text }),
  })
  if (data.message) {
    const next = [...(chat.histories[chat.selectedId] || []), data.message]
    chat.histories = { ...chat.histories, [chat.selectedId]: next }
    syncAgentPreview(chat.selectedId, next)
    chat.replyDrafts = { ...chat.replyDrafts, [parentId]: '' }
    chat.replyParent = ''
  }
}

export function toggleDictation() {
  const active = selectedAgent()
  if (!chat.dictationSupported || !active) return
  const Speech = window.SpeechRecognition || window.webkitSpeechRecognition
  if (!Speech) return
  if (chat.dictating && chat.recognition) {
    try { chat.recognition.stop() } catch {}
    chat.dictating = false
    return
  }
  const next = new Speech()
  next.continuous = false
  next.interimResults = true
  next.lang = navigator.language || 'en-US'
  next.onresult = event => {
    let text = ''
    for (let i = 0; i < event.results.length; i += 1) text += event.results[i][0].transcript
    chat.drafts = { ...chat.drafts, [chat.selectedId]: `${(chat.drafts[chat.selectedId] || '').trim()} ${text.trim()}`.trim() }
  }
  next.onerror = () => { chat.dictating = false }
  next.onend = () => { chat.dictating = false; chat.recognition = null }
  chat.recognition = next
  chat.dictating = true
  try { next.start() } catch { chat.dictating = false }
}

export function composerKey(event) {
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing && window.matchMedia('(pointer: fine)').matches) {
    event.preventDefault()
    sendMessage()
  }
}

export function pickSkill(skill) {
  const prefix = `Use skill ${skill.name}:\n${skill.body}\n\n`
  chat.drafts = { ...chat.drafts, [chat.selectedId]: `${prefix}${(chat.drafts[chat.selectedId] || '').trim()}`.trim() }
  chat.skillPickerOpen = false
  chat.skillQuery = ''
}

/** Must run during App component init (not at module import). */
export function installMessageEffects() {
  $effect(() => {
    chat.selectedId
    chat.session?.csrf
    chat.messageSearch = ''; chat.matchIndex = 0; chat.atLatest = true; chat.unreadMessages = false
  })

  $effect(() => {
    chat.dictationSupported = Boolean(typeof window !== 'undefined' && (window.SpeechRecognition || window.webkitSpeechRecognition))
  })
}
