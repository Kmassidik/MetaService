// Who made a VM: the short `created_by` every VM in a machine's answer may carry, and the full record of one VM (GET .../origin). See mcp/SPEC.md section 10.3.
import { fields, maybeText, maybeTime, oneOf, text, flag } from './mcpParse.ts'
import { isFields } from './unreadable.ts'

export const ORIGIN_KINDS = ['panel', 'mcp'] as const
export type OriginKind = (typeof ORIGIN_KINDS)[number]

export const UNKNOWN_ORIGIN = 'unknown origin'
export const ALTERED_TEXT = 'record altered'

/** The short form on every VM of a list: the label ("Ayu (MCP)") and the first 8 characters of the record's seal. */
export interface CreatedBy {
  kind: OriginKind
  /** Made from names typed by people: only ever shown as text. */
  label: string
  fingerprint: string
}

/** The short creator of a VM. A VM the parent did not make has none; so does a value in another shape, so one odd VM never breaks a whole list. */
export function readCreatedBy(raw: unknown): CreatedBy | null {
  if (!isFields(raw)) return null
  const { kind, label, fingerprint } = raw
  if (typeof label !== 'string' || typeof fingerprint !== 'string' || !label || !fingerprint) return null
  return ORIGIN_KINDS.find((known) => known === kind) === undefined ? null : { kind: kind as OriginKind, label, fingerprint }
}

/** "Ayu (MCP) · 7f3a9c21", "panel (kurnia) · 5b02d1ee", or "unknown origin". */
export const createdByText = (by: CreatedBy | null): string => (by ? `${by.label} · ${by.fingerprint}` : UNKNOWN_ORIGIN)

/** The one line for a workload of a machine's answer. */
export const workloadCreatedByText = (workload: { created_by?: unknown }): string => createdByText(readCreatedBy(workload.created_by))

/** The full record of one VM, with the answer of the parent's check of its seal. */
export interface VmOrigin {
  kind: OriginKind
  actor: string
  personName: string | null
  tokenPrefix: string | null
  /** The AI client's name and version, for an MCP VM. */
  client: string | null
  sourceIp: string | null
  /** Null for a VM made before creators were tracked. */
  createdAt: number | null
  /** True for a VM made before creators were tracked: the record was written afterwards. */
  backfilled: boolean
  deletedAt: number | null
  deletedBy: string | null
  fingerprint: string
  /** False when the stored record no longer matches its seal. */
  intact: boolean
}

/** `{origin: {...}|null}`. Null means there is no record for this VM. */
export function parseOrigin(raw: unknown): VmOrigin | null {
  const origin = fields(raw, 'the origin answer').origin
  if (origin === null || origin === undefined) return null
  const row = fields(origin, 'the origin')
  return {
    kind: oneOf(row.kind, ORIGIN_KINDS, 'kind'),
    actor: text(row, 'actor'),
    personName: maybeText(row, 'person_name'),
    tokenPrefix: maybeText(row, 'token_prefix'),
    client: maybeText(row, 'client'),
    sourceIp: maybeText(row, 'source_ip'),
    createdAt: maybeTime(row, 'created_at'),
    backfilled: row.backfilled === true,
    deletedAt: maybeTime(row, 'deleted_at'),
    deletedBy: maybeText(row, 'deleted_by'),
    fingerprint: text(row, 'fingerprint'),
    intact: flag(row, 'intact'),
  }
}

export const BACKFILLED_NOTE = 'Recorded afterwards: this VM was made before creators were tracked.'
export const BEFORE_TRACKING = 'before tracking started'

/** "Ayu (MCP)", "panel (kurnia)" or "admin (recorded afterwards)". */
export function originLabel(origin: Pick<VmOrigin, 'kind' | 'actor' | 'personName' | 'backfilled'>): string {
  if (origin.backfilled) return `${origin.actor} (recorded afterwards)`
  return origin.kind === 'mcp' ? `${origin.personName ?? origin.actor} (MCP)` : `panel (${origin.actor})`
}

const MINUTE_END = 16

/** A moment as "2026-10-31 12:00 UTC", the same wherever the panel is opened. */
export const originTime = (ms: number): string => `${new Date(ms).toISOString().slice(0, MINUTE_END).replace('T', ' ')} UTC`

export interface OriginRow {
  label: string
  value: string
}

/** The rows of the VM page: only the ones the record has. */
export function originRows(origin: VmOrigin): OriginRow[] {
  const rows: (OriginRow | null)[] = [
    { label: 'Created by', value: `${originLabel(origin)} · ${origin.fingerprint}` },
    origin.client ? { label: 'Client', value: origin.client } : null,
    origin.tokenPrefix ? { label: 'Token', value: `msk_${origin.tokenPrefix}…` } : null,
    origin.sourceIp ? { label: 'From', value: origin.sourceIp } : null,
    { label: 'Created', value: origin.createdAt === null ? BEFORE_TRACKING : originTime(origin.createdAt) },
    origin.deletedAt === null ? null : { label: 'Deleted', value: `${originTime(origin.deletedAt)}${origin.deletedBy ? ` by ${origin.deletedBy}` : ''}` },
  ]
  return rows.filter((row): row is OriginRow => row !== null)
}
