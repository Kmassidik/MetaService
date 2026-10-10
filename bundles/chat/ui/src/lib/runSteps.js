/**
 * "Show steps": what a bot did during one run, in plain words. Built only from the public run
 * events the server already redacts (tool names and phases, never arguments or reasoning), and
 * only the steps a person cares about: lifecycle, routing and other plumbing are left out.
 */
import { terminalRunStates } from './constants.js'

const RUNTIME = 'runtime'
const TOOL = 'tool'
const HELPER = 'child'
const PROBLEM = 'error'
const TOOL_STARTED = 'start'
const UNKNOWN_TOOL = 'Used a tool'
const HELPER_NAME = 'A helper'

const TOOL_STEPS = Object.freeze({
  browser: 'Browsed the web',
  ruvio_desktop: 'Used the computer screen',
  ruvio_message_person: 'Messaged someone for you',
  ruvio_search_email: 'Searched your email',
  ruvio_send_email: 'Emailed someone for you',
  ruvio_reply_email: 'Replied to an email for you',
  ruvio_find_free_time: 'Checked your calendar',
  ruvio_schedule_event: 'Scheduled an event for you',
  ruvio_move_event: 'Moved an event for you',
  ruvio_cancel_event: 'Cancelled an event for you',
  ruvio_post: 'Posted on X for you',
  read: 'Read a file',
  write: 'Wrote a file',
  edit: 'Edited a file',
  apply_patch: 'Edited a file',
  exec: 'Ran a command',
  process: 'Ran a command',
  maas_research: 'Looked something up online',
  maas_connectors: 'Used a connected app',
  maas_documents: 'Worked on a document',
  maas_specialists: 'Shared out parts of the task',
  ruvio_ask: 'Asked you to choose',
  ruvio_profile: 'Updated its profile',
  ruvio_takeover: 'Asked you to take over the computer',
  ruvio_connect: 'Asked you to connect an app',
  ruvio_secret: 'Asked you for a key',
  ruvio_suggest: 'Suggested another bot',
  ruvio_handoff: 'Handed the task to another bot',
  ruvio_routines: 'Set up a routine',
  ruvio_skills: 'Used a skill',
  ruvio_memory: 'Checked its memory',
})

const HELPER_STEPS = Object.freeze({
  running: 'started on part of the task',
  completed: 'finished its part',
  failed: 'couldn’t finish its part',
  cancelled: 'stopped its part',
})

const APPROVAL_STEPS = Object.freeze({
  'approval.requested': 'Asked for your approval',
  'approval.consumed': 'Did the approved action',
  'approval.expired': 'The approval request expired',
})

const lowerFirst = text => text.charAt(0).toLowerCase() + text.slice(1)

function helperName(payload) {
  return payload.memberName || HELPER_NAME
}

// A helper's own tool use reads as "Atlas browsed the web".
function attributed(payload, label) {
  if (!payload.childId) return label
  return `${helperName(payload)} ${lowerFirst(label)}`
}

function toolStep(payload) {
  if (payload.phase !== TOOL_STARTED) return ''
  return attributed(payload, TOOL_STEPS[payload.name] || UNKNOWN_TOOL)
}

function helperStep(payload) {
  const phase = HELPER_STEPS[payload.phase]
  return phase ? `${helperName(payload)} ${phase}` : ''
}

function runtimeStep(payload) {
  if (payload.type === TOOL) return toolStep(payload)
  if (payload.type === HELPER) return helperStep(payload)
  if (payload.type === PROBLEM) return attributed(payload, 'Ran into a problem')
  return ''
}

/** The plain-words step for one run event, or '' when it is not worth showing. */
export function stepLabel(event) {
  if (event?.kind === RUNTIME) return runtimeStep(event.payload || {})
  return APPROVAL_STEPS[event?.kind] || ''
}

/** The run's steps in order; repeats in a row fold into one ("Browsed the web · 3 times"). */
export function runSteps(events = []) {
  const steps = []
  for (const event of events) {
    const text = stepLabel(event)
    if (!text) continue
    const last = steps.at(-1)
    if (last?.text === text) last.count += 1
    else steps.push({ id: event.sequence, text, count: 1 })
  }
  return steps
}

export function stepText(step) {
  return step.count > 1 ? `${step.text} · ${step.count} times` : step.text
}

const timeOf = value => Date.parse(value) || 0

// A run's reply is the first bot message after the run started and before the next run did.
function replyTo(run, messages, nextStart) {
  const start = timeOf(run.createdAt)
  return messages.find(message => message.role === 'assistant'
    && timeOf(message.createdAt) >= start
    && timeOf(message.createdAt) < nextStart)
}

/**
 * Message id → steps, for every finished run whose events are loaded and whose reply is in
 * `messages`. Runs with no meaningful steps are left out, so their reply shows nothing.
 */
export function stepsByReply(messages = [], runs = [], eventsByRun = {}) {
  const ordered = [...runs].sort((a, b) => timeOf(a.createdAt) - timeOf(b.createdAt))
  const byReply = {}
  ordered.forEach((run, index) => {
    const steps = terminalRunStates.includes(run.state) ? runSteps(eventsByRun[run.id]) : []
    if (!steps.length) return
    const nextStart = index + 1 < ordered.length ? timeOf(ordered[index + 1].createdAt) : Infinity
    const reply = replyTo(run, messages, nextStart)
    if (reply) byReply[reply.id] = steps
  })
  return byReply
}
