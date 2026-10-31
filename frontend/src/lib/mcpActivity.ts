// Read the recent calls of the AI clients (GET /api/mcp/activity). See mcp/SPEC.md sections 7 and 10.
import { fields, listUnder, maybeText, text, time } from './mcpParse.ts'
import { UnreadableAnswer } from './unreadable.ts'

export interface ActivityRow {
  at: number
  /** The person who made the call. Typed by the operator: only ever shown as text. */
  person: string
  /** The tool, for example `create_vm`. */
  tool: string
  target: string | null
  status: string
}

const ACTOR_PREFIX = 'mcp:'
const ACTION_PREFIX = 'mcp.'

function activityRow(value: unknown): ActivityRow {
  const row = fields(value, 'a call')
  const actor = text(row, 'actor')
  const action = text(row, 'action')
  if (!actor.startsWith(ACTOR_PREFIX)) throw new UnreadableAnswer('a call is not from an AI client')
  return {
    at: time(row, row.at === undefined ? 'created_at' : 'at'),
    person: actor.slice(ACTOR_PREFIX.length),
    tool: action.startsWith(ACTION_PREFIX) ? action.slice(ACTION_PREFIX.length) : action,
    target: maybeText(row, 'target'),
    status: text(row, 'status'),
  }
}

/** The recent calls, newest first as the parent sends them. */
export const parseActivity = (raw: unknown): ActivityRow[] => listUnder(raw, 'activity', 'the activity answer').map(activityRow)
