// The address of the Security page and what it keeps in it: #/security?range=30d&machine=<id>&type=blocked&preview=1. A choice in the address survives a reload
// and can be shared. A value the page does not know is ignored, so the page always opens on something sensible.
import { DEFAULT_RANGE, EVENT_TYPES, RANGES, type SecurityEventType, type SecurityRange } from './securityTypes.ts'

export interface SecurityView {
  range: SecurityRange
  /** A machine id, or empty for all machines. */
  machine: string
  /** An event type, or empty for all types. */
  type: SecurityEventType | ''
  /** True only when the address asks for the sample data. */
  preview: boolean
}

const SECURITY_PATH = '/security'
const PREVIEW_ON = '1'
const MACHINE_ID = /^[a-z0-9][a-z0-9-]{0,62}$/
const DEFAULT_VIEW: SecurityView = { range: DEFAULT_RANGE, machine: '', type: '', preview: false }

const queryOf = (route: string): URLSearchParams => new URLSearchParams(route.split('?')[1] ?? '')
const rangeOf = (text: string | null): SecurityRange => RANGES.find((range) => range === text) ?? DEFAULT_RANGE
const typeOf = (text: string | null): SecurityEventType | '' => EVENT_TYPES.find((type) => type === text) ?? ''
const machineOf = (text: string | null): string => (text !== null && MACHINE_ID.test(text) ? text : '')

/** What the address says the page should show. */
export function parseSecurityView(route: string): SecurityView {
  const query = queryOf(route)
  return { range: rangeOf(query.get('range')), machine: machineOf(query.get('machine')), type: typeOf(query.get('type')), preview: query.get('preview') === PREVIEW_ON }
}

/** The address of the Security page, with the given choices; whatever is the default is left out. */
export function securityHref(choice: Partial<SecurityView> = {}): string {
  const view = { ...DEFAULT_VIEW, ...choice }
  const query = new URLSearchParams()
  if (view.range !== DEFAULT_RANGE) query.set('range', view.range)
  if (view.machine !== '') query.set('machine', view.machine)
  if (view.type !== '') query.set('type', view.type)
  if (view.preview) query.set('preview', PREVIEW_ON)
  const text = query.toString()
  return text === '' ? `#${SECURITY_PATH}` : `#${SECURITY_PATH}?${text}`
}
