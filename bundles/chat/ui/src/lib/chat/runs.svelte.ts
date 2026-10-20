import { untrack } from 'svelte'
import { type ProfileChange, answeredAskIds, askOf, cardOf, parseApprovals, parseEventPage, parseRunAnswer, parseRuns, profileChangeOf } from '../answers/runs.ts'
import { withSignal } from '../api.ts'
import type { Dict } from '../check.ts'
import { errorStatus } from '../errors.ts'
import { fail } from '../format.ts'
import { notifyBrowser } from '../runs.ts'
import type { Ask, AppResult, Approval, Run, RunCard, RunEvent } from '../types.ts'
import { api } from './client.svelte.ts'
import { loadFiles } from './files.svelte.ts'
import { loadUsage } from './usage.svelte.ts'
import { loadHistory, sendMessage } from './messages.svelte.ts'
import { loadAgents, openModal } from './agents.svelte.ts'
import { computerAction, openComputer } from './computer.svelte.ts'
import { profileVisible } from './sidePanel.svelte.ts'
import { updateRun } from './runsUpdate.svelte.ts'
import { recheckAppsAfterRun } from './apps.svelte.ts'
import { approvalAwaitsDecision } from './selectors.ts'
import { watchesRuns } from './draftBots.ts'
import { appResults, cardAwaitsOwner, resolvedCardIds } from '../appCards.ts'
import {
  chat,
  fileSession,
  requireSession,
  runCursors,
  refreshedRuns,
  terminalRunStates,
  selectedRun,
  runIsActive,
} from './state.svelte.ts'

// How often the open chat asks for its task's status while it is on screen.
const RUN_POLL_MS = 2000
// The run's event list keeps this many of the newest events.
const MAX_KEPT_EVENTS = 300
// The server dropped the events we asked for after (their window moved on).
const EVENTS_GONE = 410
const HIGHLIGHT_MS = 1600

export { updateRun }

const lastMatch = <T>(items: readonly T[], test: (item: T) => boolean): T | undefined => [...items].reverse().find(test)

export function activeAsk(): Ask | null {
  const run = selectedRun()
  if (!run || !chat.selectedId) return null
  const events = chat.runEvents[run.id] || []
  const answeredIds = answeredAskIds(events)
  const asks = events.flatMap(event => askOf(event, run.id) ?? [])
  return lastMatch(asks, ask => !chat.answeredAsks[ask.askId] && !answeredIds.has(ask.askId)) ?? null
}

export function activeCard(): RunCard | null {
  const run = selectedRun()
  if (!run || !chat.selectedId) return null
  const all = chat.runEvents[run.id] || []
  const resolvedOnServer = resolvedCardIds(all)
  const cards = all.flatMap(event => cardOf(event, run.id) ?? [])
  return lastMatch(cards, card => cardAwaitsOwner(card, chat.resolvedCards, resolvedOnServer)) ?? null
}

/** What app tools did in the selected run (result cards). */
export function appResultCards(): AppResult[] {
  const run = selectedRun()
  return run && chat.selectedId ? appResults(chat.runEvents[run.id]) : []
}

export async function loadRuns(id: string, key: string | undefined, signal?: AbortSignal): Promise<Run | null> {
  const listed = parseRuns(await api(`/api/agents/${encodeURIComponent(id)}/runs`, withSignal({}, signal)))
  if (!fileSession(key) || signal?.aborted) return null
  const runs = [...listed].sort((a, b) => b.createdAt.localeCompare(a.createdAt))
  chat.agentRuns = { ...chat.agentRuns, [id]: runs }
  const run = runs.find(item => !terminalRunStates.has(item.state)) || runs[0]
  if (run) updateRun(run)
  return run ?? null
}

function eventsPath(runId: string, after: number): string {
  return `/api/runs/${encodeURIComponent(runId)}/events?after=${after}`
}

function retainedWindowRecoverable(current: Run | undefined): current is Run {
  return current !== undefined
    && Number.isSafeInteger(current.firstEventSequence) && current.firstEventSequence >= 1
    && Number.isSafeInteger(current.lastEventSequence) && current.lastEventSequence >= current.firstEventSequence - 1
}

/**
 * The run's events after the cursor. When the server no longer has them (410) the retained window
 * is read once from the run list; the execution is never restarted or retried in a loop.
 */
async function fetchEvents(run: Run, key: string | undefined, signal: AbortSignal | undefined) {
  const after = runCursors.get(run.id) || 0
  try {
    return { page: parseEventPage(await api(eventsPath(run.id, after), withSignal({}, signal))), after }
  } catch (error) {
    if (errorStatus(error) !== EVENTS_GONE || !fileSession(key) || signal?.aborted) throw error
  }
  const snapshot = parseRuns(await api(`/api/agents/${encodeURIComponent(run.agentId)}/runs`, withSignal({}, signal)))
  if (!fileSession(key) || signal?.aborted) return null
  const current = snapshot.find(item => item.id === run.id && item.agentId === run.agentId)
  if (!retainedWindowRecoverable(current)) throw new Error('The retained event window could not be recovered. Refresh task status.')
  const retainedAfter = current.firstEventSequence - 1
  runCursors.set(run.id, retainedAfter)
  // Retry the retained event window once. Never restart execution or recursively retry a moving window.
  return { page: parseEventPage(await api(eventsPath(run.id, retainedAfter), withSignal({}, signal))), after: retainedAfter }
}

function mergeEvents(runId: string, incoming: readonly RunEvent[]): void {
  const known = chat.runEvents[runId] || []
  const seen = new Set(known.map(event => event.sequence))
  const merged = [...known, ...incoming.filter(event => !seen.has(event.sequence))]
  chat.runEvents = { ...chat.runEvents, [runId]: merged.sort((a, b) => a.sequence - b.sequence).slice(-MAX_KEPT_EVENTS) }
}

/** A bot changed its own profile: show it on the open Details form, or as a notice. */
function showProfileChange(change: ProfileChange): void {
  chat.agents = chat.agents.map(agent => agent.id === change.agentId
    ? { ...agent, name: change.name ?? agent.name, title: change.title ?? agent.title, summary: change.summary ?? agent.summary }
    : agent)
  if (change.agentId !== chat.selectedId) return
  if (!profileVisible()) {
    chat.profileNotice = change.notice || 'Profile updated'
    return
  }
  chat.profileName = change.name ?? chat.profileName
  chat.profileTitle = change.title ?? chat.profileTitle
  chat.profileSummary = change.summary ?? chat.profileSummary
  const flash: Dict<boolean> = {}
  for (const field of change.changed ?? []) flash[field] = true
  chat.profileHighlight = flash
  setTimeout(() => { chat.profileHighlight = {} }, HIGHLIGHT_MS)
}

const asksForOwner = (event: RunEvent): boolean => event.kind === 'ask' || event.kind === 'card' || event.kind.startsWith('approval.')

function notifyNeedsInput(run: Run, event: RunEvent): void {
  const agent = chat.agents.find(item => item.id === run.agentId)
  if (agent?.notifyNeedsInput === false || run.agentId === chat.selectedId) return
  const cardTitle = typeof event.payload?.title === 'string' ? event.payload.title : ''
  notifyBrowser(agent?.name || 'Ruvio', event.kind === 'card' ? (cardTitle || 'Needs your input') : 'Needs your input')
}

function reactToEvent(run: Run, event: RunEvent): void {
  const change = profileChangeOf(event)
  if (change) showProfileChange(change)
  if (asksForOwner(event)) notifyNeedsInput(run, event)
}

/** A task that just ended: say so, re-check the apps, and reload what it changed. */
async function finishRun(run: Run, finished: Run, key: string | undefined, signal: AbortSignal | undefined): Promise<void> {
  chat.runNotices = { ...chat.runNotices, [run.id]: '' }
  const agent = chat.agents.find(item => item.id === run.agentId)
  if (finished.state === 'succeeded' && agent?.notifyFinished !== false && run.agentId !== chat.selectedId) {
    notifyBrowser(agent?.name || 'Ruvio', 'Finished a task')
  }
  recheckAppsAfterRun(chat.runEvents[run.id])
  await Promise.all([loadHistory(run.agentId), loadFiles(), loadUsage()])
  if (fileSession(key) && !signal?.aborted) refreshedRuns.add(run.id)
}

export async function refreshRun(run: Run, key: string | undefined, signal?: AbortSignal): Promise<void> {
  if (!fileSession(key) || signal?.aborted) return
  const fetched = await fetchEvents(run, key, signal)
  if (!fetched || !fileSession(key) || signal?.aborted) return
  const { page, after } = fetched
  const approvals: Approval[] = parseApprovals(await api(`/api/runs/${encodeURIComponent(run.id)}/approvals`, withSignal({}, signal)))
  if (!fileSession(key) || signal?.aborted) return
  const incoming = page.events.filter(event => Number.isSafeInteger(event.sequence) && event.sequence > after)
  mergeEvents(run.id, incoming)
  // Advance only through received events. A server cursor cannot silently skip a paginated replay.
  if (incoming.length) runCursors.set(run.id, Math.max(after, ...incoming.map(event => event.sequence)))
  chat.runApprovals = { ...chat.runApprovals, [run.id]: approvals }
  updateRun(page.run)
  chat.runErrors = { ...chat.runErrors, [run.agentId]: '' }
  for (const event of incoming) reactToEvent(run, event)
  if (terminalRunStates.has(page.run.state) && !refreshedRuns.has(run.id)) await finishRun(run, page.run, key, signal)
}

export async function cancelRun(): Promise<void> {
  const run = selectedRun()
  if (!run || !runIsActive(run) || chat.runBusy[run.id]) return
  const key = requireSession().csrf
  chat.runBusy = { ...chat.runBusy, [run.id]: 'cancel' }
  chat.runActionErrors = { ...chat.runActionErrors, [run.agentId]: '' }
  try {
    const data = parseRunAnswer(await api(`/api/runs/${encodeURIComponent(run.id)}/cancel`, { method: 'POST' }))
    if (!fileSession(key)) return
    if (data.run) updateRun(data.run)
    chat.runNotices = { ...chat.runNotices, [run.id]: 'Cancellation requested. Waiting for the server to confirm the final state.' }
    chat.reconnectRun += 1
  } catch (error) {
    if (fileSession(key)) chat.runActionErrors = { ...chat.runActionErrors, [run.agentId]: `${fail(error)} Refresh status before retrying cancellation.` }
  } finally { if (fileSession(key)) chat.runBusy = { ...chat.runBusy, [run.id]: '' } }
}

export async function decideRunApproval(approval: Approval, decision: string): Promise<void> {
  const run = selectedRun()
  if (!run || !approvalAwaitsDecision(approval, run) || !runIsActive(run) || run.state === 'cancelling' || chat.runBusy[run.id]) return
  if (decision === 'approve' && chat.reviewedApprovals[approval.id] !== approval.parametersSHA256) return
  const key = requireSession().csrf
  chat.runBusy = { ...chat.runBusy, [run.id]: 'approval' }
  chat.runActionErrors = { ...chat.runActionErrors, [run.agentId]: '' }
  try {
    await api(`/api/runs/${encodeURIComponent(run.id)}/approvals/${encodeURIComponent(approval.id)}/decision`, { method: 'POST', body: JSON.stringify({ decision }) })
    if (fileSession(key)) chat.runNotices = { ...chat.runNotices, [run.id]: decision === 'approve' ? 'Approved for this exact task action once. The task will execute it automatically; an uncertain action is never retried.' : 'Action denied. It will not execute.' }
  } catch (error) {
    if (fileSession(key)) chat.runActionErrors = { ...chat.runActionErrors, [run.agentId]: `${fail(error)} Refresh approvals before trying again; your decision may already be recorded.` }
  } finally { if (fileSession(key)) { chat.runBusy = { ...chat.runBusy, [run.id]: '' }; chat.reconnectRun += 1 } }
}

/** A takeover card: hand the screen to the owner (or take it back when they continue). Resolves true when the card is handled. */
async function handleTakeoverCard(card: RunCard, decision: string): Promise<boolean> {
  if (card.kind !== 'takeover') return false
  if (decision === 'continue' && chat.computers[chat.selectedId]?.state === 'takeover') await computerAction('release')
  if (decision !== 'takeover') return false
  if (card.url) chat.computerUrl = card.url
  await openComputer()
  await computerAction('takeover')
  return true
}

export async function resolveCard(decision: string, extra: Dict<unknown> = {}): Promise<void> {
  const card = activeCard()
  if (!card || chat.cardBusy) return
  const cardId = card.cardId
  chat.cardBusy = cardId
  try {
    if (await handleTakeoverCard(card, decision)) return
    if (decision === 'open_connect') {
      openModal('marketplace')
      return
    }
    const body: Dict<unknown> = { decision, ...extra }
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

export function toggleAskOption(optionId: string): void {
  const ask = activeAsk()
  if (!ask || ask.mode !== 'multiple') return
  const selected = new Set(chat.askMulti[ask.askId] || [])
  if (selected.has(optionId)) selected.delete(optionId)
  else selected.add(optionId)
  chat.askMulti = { ...chat.askMulti, [ask.askId]: [...selected] }
}

/** Answers the waiting `ruvio_ask` tool so the same turn continues with the answer. */
async function answerWaitingAsk(ask: Ask, labels: string[], key: string): Promise<void> {
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
}

export async function submitAsk(labels: string[]): Promise<void> {
  const ask = activeAsk()
  if (!ask || !labels.length || chat.answeredAsks[ask.askId]) return
  chat.answeredAsks = { ...chat.answeredAsks, [ask.askId]: labels }
  chat.askFocus = -1
  const run = selectedRun()
  const key = requireSession().csrf
  // Prefer unblocking the waiting `ruvio_ask` tool so the same turn continues with the answer.
  if (runIsActive(run) && run?.id === ask.runId) {
    await answerWaitingAsk(ask, labels, key)
    return
  }
  await sendMessage(null, labels.join(', '))
}

/** Dismiss a skippable ask card without sending a message (composer stays available). */
export function skipAsk(): void {
  const ask = activeAsk()
  if (!ask || !ask.skippable || chat.answeredAsks[ask.askId]) return
  chat.answeredAsks = { ...chat.answeredAsks, [ask.askId]: [] }
  chat.askFocus = -1
}

const NEXT_KEYS = ['ArrowRight', 'ArrowDown']
const PREVIOUS_KEYS = ['ArrowLeft', 'ArrowUp']

export function askKeydown(event: KeyboardEvent): void {
  const ask = activeAsk()
  if (!ask || chat.answeredAsks[ask.askId]) return
  const options = ask.options
  if (NEXT_KEYS.includes(event.key)) {
    event.preventDefault()
    chat.askFocus = (chat.askFocus + 1 + options.length) % options.length
    return
  }
  if (PREVIOUS_KEYS.includes(event.key)) {
    event.preventDefault()
    chat.askFocus = (chat.askFocus - 1 + options.length) % options.length
    return
  }
  const option = event.key === 'Enter' && chat.askFocus >= 0 ? options[chat.askFocus] : undefined
  if (!option) return
  event.preventDefault()
  if (ask.mode === 'multiple') toggleAskOption(option.id)
  else submitAsk([option.label])
}

/** Must run during App component init (not at module import). */
export function installRunEffects(): void {
  $effect(() => {
    const id = chat.selectedId
    const key = chat.session?.csrf
    void chat.reconnectRun
    if (!watchesRuns(id, key)) return
    const controller = new AbortController()
    let timer: ReturnType<typeof setTimeout> | undefined
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
