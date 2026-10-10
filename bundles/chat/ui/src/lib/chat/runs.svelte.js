import { untrack } from 'svelte'
import { fail } from '../format.js'
import { notifyBrowser } from '../runs.js'
import { api } from './client.svelte.js'
import { loadFiles } from './files.svelte.js'
import { loadUsage } from './usage.svelte.js'
import { loadHistory, sendMessage } from './messages.svelte.js'
import { loadAgents, openModal } from './agents.svelte.js'
import { computerAction, openComputer } from './computer.svelte.js'
import { profileVisible } from './sidePanel.svelte.js'
import { updateRun } from './runsUpdate.svelte.js'
import { recheckAppsAfterRun } from './apps.svelte.js'
import { approvalAwaitsDecision } from './selectors.js'
import { watchesRuns } from './draftBots.js'
import { appResults, cardAwaitsOwner, resolvedCardIds } from '../appCards.js'
import {
  chat,
  fileSession,
  runCursors,
  refreshedRuns,
  terminalRunStates,
  selectedRun,
  runIsActive,
} from './state.svelte.js'

// How often the open chat asks for its task's status while it is on screen.
const RUN_POLL_MS = 2000

export { updateRun }

export function activeAsk() {
  const run = selectedRun()
  if (!run || !chat.selectedId) return null
  const events = (chat.runEvents[run.id] || []).filter(event => event.kind === 'ask' && event.payload?.askId)
  const answeredIds = new Set(
    (chat.runEvents[run.id] || [])
      .filter(event => event.kind === 'ask_answered' && event.payload?.askId)
      .map(event => event.payload.askId),
  )
  for (let index = events.length - 1; index >= 0; index -= 1) {
    const payload = events[index].payload
    if (chat.answeredAsks[payload.askId] || answeredIds.has(payload.askId)) continue
    if (!Array.isArray(payload.options) || payload.options.length < 2) continue
    return { ...payload, runId: run.id, sequence: events[index].sequence }
  }
  return null
}

export function activeCard() {
  const run = selectedRun()
  if (!run || !chat.selectedId) return null
  const all = chat.runEvents[run.id] || []
  const resolvedOnServer = resolvedCardIds(all)
  const events = all.filter(event => event.kind === 'card' && event.payload?.cardId)
  for (let index = events.length - 1; index >= 0; index -= 1) {
    const payload = events[index].payload
    if (!cardAwaitsOwner(payload, chat.resolvedCards, resolvedOnServer)) continue
    return { ...payload, runId: run.id }
  }
  return null
}

/** What app tools did in the selected run (result cards). */
export function appResultCards() {
  const run = selectedRun()
  return run && chat.selectedId ? appResults(chat.runEvents[run.id]) : []
}

export async function loadRuns(id, key, signal) {
  const data = await api(`/api/agents/${encodeURIComponent(id)}/runs`, { signal })
  if (!fileSession(key) || signal?.aborted) return null
  const runs = [...data.runs].sort((a, b) => b.createdAt.localeCompare(a.createdAt))
  chat.agentRuns = { ...chat.agentRuns, [id]: runs }
  const run = runs.find(item => !terminalRunStates.has(item.state)) || runs[0]
  if (run) updateRun(run)
  return run
}

export async function refreshRun(run, key, signal) {
  if (!fileSession(key) || signal?.aborted) return
  let after = runCursors.get(run.id) || 0
  let data
  try {
    data = await api(`/api/runs/${encodeURIComponent(run.id)}/events?after=${after}`, { signal })
  } catch (error) {
    if (error.status !== 410 || !fileSession(key) || signal?.aborted) throw error
    const snapshot = await api(`/api/agents/${encodeURIComponent(run.agentId)}/runs`, { signal })
    if (!fileSession(key) || signal?.aborted) return
    const current = snapshot.runs.find(item => item.id === run.id && item.agentId === run.agentId)
    if (!current || !Number.isSafeInteger(current.firstEventSequence) || current.firstEventSequence < 1 || !Number.isSafeInteger(current.lastEventSequence) || current.lastEventSequence < current.firstEventSequence - 1) throw new Error('The retained event window could not be recovered. Refresh task status.')
    after = current.firstEventSequence - 1
    runCursors.set(run.id, after)
    // Retry the retained event window once. Never restart execution or recursively retry a moving window.
    data = await api(`/api/runs/${encodeURIComponent(run.id)}/events?after=${after}`, { signal })
  }
  if (!fileSession(key) || signal?.aborted) return
  const approvals = await api(`/api/runs/${encodeURIComponent(run.id)}/approvals`, { signal })
  if (!fileSession(key) || signal?.aborted) return
  const incoming = data.events.filter(event => Number.isSafeInteger(event.sequence) && event.sequence > after)
  const seen = new Set((chat.runEvents[run.id] || []).map(event => event.sequence))
  chat.runEvents = { ...chat.runEvents, [run.id]: [...(chat.runEvents[run.id] || []), ...incoming.filter(event => !seen.has(event.sequence))].sort((a, b) => a.sequence - b.sequence).slice(-300) }
  // Advance only through received events. A server cursor cannot silently skip a paginated replay.
  if (incoming.length) runCursors.set(run.id, Math.max(after, ...incoming.map(event => event.sequence)))
  chat.runApprovals = { ...chat.runApprovals, [run.id]: approvals.approvals }
  updateRun(data.run)
  chat.runErrors = { ...chat.runErrors, [run.agentId]: '' }
  for (const event of incoming) {
    if (event.kind === 'profile' && event.payload?.agentId) {
      const payload = event.payload
      chat.agents = chat.agents.map(agent => agent.id === payload.agentId
        ? { ...agent, name: payload.name ?? agent.name, title: payload.title ?? agent.title, summary: payload.summary ?? agent.summary }
        : agent)
      if (payload.agentId === chat.selectedId) {
        if (profileVisible()) {
          chat.profileName = payload.name ?? chat.profileName
          chat.profileTitle = payload.title ?? chat.profileTitle
          chat.profileSummary = payload.summary ?? chat.profileSummary
          const flash = {}
          for (const field of payload.changed || []) flash[field === 'instructions' ? 'instructions' : field] = true
          chat.profileHighlight = flash
          setTimeout(() => { chat.profileHighlight = {} }, 1600)
        } else {
          chat.profileNotice = payload.notice || 'Profile updated'
        }
      }
    }
    if (event.kind === 'ask' || event.kind === 'card' || event.kind?.startsWith('approval.')) {
      const agent = chat.agents.find(item => item.id === run.agentId)
      if (agent?.notifyNeedsInput !== false && run.agentId !== chat.selectedId) {
        notifyBrowser(agent?.name || 'Ruvio', event.kind === 'card' ? (event.payload?.title || 'Needs your input') : 'Needs your input')
      }
    }
  }
  if (terminalRunStates.has(data.run.state) && !refreshedRuns.has(run.id)) {
    chat.runNotices = { ...chat.runNotices, [run.id]: '' }
    const agent = chat.agents.find(item => item.id === run.agentId)
    if (data.run.state === 'succeeded' && agent?.notifyFinished !== false && run.agentId !== chat.selectedId) {
      notifyBrowser(agent?.name || 'Ruvio', 'Finished a task')
    }
    recheckAppsAfterRun(chat.runEvents[run.id])
    await Promise.all([loadHistory(run.agentId), loadFiles(), loadUsage()])
    if (fileSession(key) && !signal?.aborted) refreshedRuns.add(run.id)
  }
}

export async function cancelRun() {
  const run = selectedRun()
  if (!run || !runIsActive(run) || chat.runBusy[run.id]) return
  const key = chat.session.csrf
  chat.runBusy = { ...chat.runBusy, [run.id]: 'cancel' }
  chat.runActionErrors = { ...chat.runActionErrors, [run.agentId]: '' }
  try {
    const data = await api(`/api/runs/${encodeURIComponent(run.id)}/cancel`, { method: 'POST' })
    if (!fileSession(key)) return
    if (data.run) updateRun(data.run)
    chat.runNotices = { ...chat.runNotices, [run.id]: 'Cancellation requested. Waiting for the server to confirm the final state.' }
    chat.reconnectRun += 1
  } catch (error) {
    if (fileSession(key)) chat.runActionErrors = { ...chat.runActionErrors, [run.agentId]: `${fail(error)} Refresh status before retrying cancellation.` }
  } finally { if (fileSession(key)) chat.runBusy = { ...chat.runBusy, [run.id]: '' } }
}

export async function decideRunApproval(approval, decision) {
  const run = selectedRun()
  if (!approvalAwaitsDecision(approval, run) || !runIsActive(run) || run.state === 'cancelling' || chat.runBusy[run.id]) return
  if (decision === 'approve' && chat.reviewedApprovals[approval.id] !== approval.parametersSHA256) return
  const key = chat.session.csrf
  chat.runBusy = { ...chat.runBusy, [run.id]: 'approval' }
  chat.runActionErrors = { ...chat.runActionErrors, [run.agentId]: '' }
  try {
    await api(`/api/runs/${encodeURIComponent(run.id)}/approvals/${encodeURIComponent(approval.id)}/decision`, { method: 'POST', body: JSON.stringify({ decision }) })
    if (fileSession(key)) chat.runNotices = { ...chat.runNotices, [run.id]: decision === 'approve' ? 'Approved for this exact task action once. The task will execute it automatically; an uncertain action is never retried.' : 'Action denied. It will not execute.' }
  } catch (error) {
    if (fileSession(key)) chat.runActionErrors = { ...chat.runActionErrors, [run.agentId]: `${fail(error)} Refresh approvals before trying again; your decision may already be recorded.` }
  } finally { if (fileSession(key)) { chat.runBusy = { ...chat.runBusy, [run.id]: '' }; chat.reconnectRun += 1 } }
}

export async function resolveCard(decision, extra = {}) {
  const card = activeCard()
  if (!card || chat.cardBusy) return
  const cardId = card.cardId
  chat.cardBusy = cardId
  const computer = chat.computers[chat.selectedId] || {}
  const takingOver = computer.state === 'takeover'
  try {
    if (decision === 'continue' && card.kind === 'takeover' && takingOver) {
      await computerAction('release')
    }
    if (decision === 'takeover' && card.kind === 'takeover') {
      if (card.url) chat.computerUrl = card.url
      await openComputer()
      await computerAction('takeover')
      chat.cardBusy = ''
      return
    }
    if (decision === 'open_connect') {
      openModal('marketplace')
      chat.cardBusy = ''
      return
    }
    const body = { decision, ...extra }
    if (decision === 'submit') body.secret = chat.cardSecret
    await api(`/api/runs/${encodeURIComponent(card.runId)}/cards/${encodeURIComponent(cardId)}`, {
      method: 'POST', body: JSON.stringify(body),
    })
    chat.resolvedCards = { ...chat.resolvedCards, [cardId]: decision }
    chat.cardSecret = ''
    if (decision === 'create') await loadAgents()
  } catch (error) {
    chat.runActionErrors = { ...chat.runActionErrors, [chat.selectedId]: fail(error) }
  } finally {
    chat.cardBusy = ''
  }
}

export function toggleAskOption(optionId) {
  const ask = activeAsk()
  if (!ask || ask.mode !== 'multiple') return
  const selected = new Set(chat.askMulti[ask.askId] || [])
  if (selected.has(optionId)) selected.delete(optionId)
  else selected.add(optionId)
  chat.askMulti = { ...chat.askMulti, [ask.askId]: [...selected] }
}

export async function submitAsk(labels) {
  const ask = activeAsk()
  if (!ask || !labels.length || chat.answeredAsks[ask.askId]) return
  const text = labels.join(', ')
  chat.answeredAsks = { ...chat.answeredAsks, [ask.askId]: labels }
  chat.askFocus = -1
  const run = selectedRun()
  const key = chat.session.csrf
  // Prefer unblocking the waiting `ruvio_ask` tool so the same turn continues with the answer.
  if (runIsActive(run) && run?.id === ask.runId) {
    chat.runBusy = { ...chat.runBusy, [ask.runId]: 'ask' }
    try {
      await api(`/api/runs/${encodeURIComponent(ask.runId)}/asks/${encodeURIComponent(ask.askId)}`, {
        method: 'POST', body: JSON.stringify({ labels }),
      })
      if (!fileSession(key)) return
      await loadHistory(chat.selectedId)
      if (fileSession(key)) chat.reconnectRun += 1
    } catch (error) {
      if (fileSession(key)) {
        const next = { ...chat.answeredAsks }
        delete next[ask.askId]
        chat.answeredAsks = next
        chat.runActionErrors = { ...chat.runActionErrors, [chat.selectedId]: fail(error) }
      }
    } finally {
      if (fileSession(key)) chat.runBusy = { ...chat.runBusy, [ask.runId]: '' }
    }
    return
  }
  await sendMessage(null, text)
}

/** Dismiss a skippable ask card without sending a message (composer stays available). */
export function skipAsk() {
  const ask = activeAsk()
  if (!ask || !ask.skippable || chat.answeredAsks[ask.askId]) return
  chat.answeredAsks = { ...chat.answeredAsks, [ask.askId]: [] }
  chat.askFocus = -1
}

export function askKeydown(event) {
  const ask = activeAsk()
  if (!ask || chat.answeredAsks[ask.askId]) return
  const options = ask.options
  if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
    event.preventDefault()
    chat.askFocus = (chat.askFocus + 1 + options.length) % options.length
  } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
    event.preventDefault()
    chat.askFocus = (chat.askFocus - 1 + options.length) % options.length
  } else if (event.key === 'Enter' && chat.askFocus >= 0) {
    event.preventDefault()
    const option = options[chat.askFocus]
    if (ask.mode === 'multiple') toggleAskOption(option.id)
    else submitAsk([option.label])
  }
}

/** Must run during App component init (not at module import). */
export function installRunEffects() {
  $effect(() => {
    const id = chat.selectedId
    const key = chat.session?.csrf
    const _reconnect = chat.reconnectRun
    if (!watchesRuns(id, key)) return
    const controller = new AbortController()
    let timer
    let lastRunId = ''
    async function poll() {
      try {
        const run = await loadRuns(id, key, controller.signal)
        if (run && run.id !== lastRunId) {
          lastRunId = run.id
          await loadHistory(id)
        }
        if (run) await refreshRun(run, key, controller.signal)
        if (fileSession(key) && !controller.signal.aborted) chat.runErrors = { ...chat.runErrors, [id]: '' }
      } catch (error) {
        if (fileSession(key) && !controller.signal.aborted) chat.runErrors = { ...chat.runErrors, [id]: `Run status disconnected: ${fail(error)} Reconnecting automatically; no task is restarted.` }
      } finally {
        if (fileSession(key) && !controller.signal.aborted) timer = setTimeout(poll, RUN_POLL_MS)
      }
    }
    untrack(poll)
    return () => { controller.abort(); clearTimeout(timer) }
  })
}
