/**
 * The approval card's "Details": the exact action in plain words. The task's proposed
 * parameters arrive as JSON; they show as readable "Label: value" rows, never as raw JSON.
 */

export const MISSING_PARAMETERS = 'The exact details aren’t available, so don’t approve this.'

const PATH_SEPARATOR = ' › '
const VALUE_LABEL = 'Value'
const RAW_LABEL = 'Details'
const NOTHING = 'None'
const YES = 'Yes'
const NO = 'No'

const isRecord = value => value !== null && typeof value === 'object' && !Array.isArray(value)
const isPrimitive = value => value === null || typeof value !== 'object'

/** "max_results" or "maxResults" → "Max results". */
export function humanizeKey(key) {
  const words = String(key)
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .trim()
    .toLowerCase()
  return words ? words.charAt(0).toUpperCase() + words.slice(1) : String(key)
}

function readable(value) {
  if (value === null || value === undefined || value === '') return NOTHING
  if (value === true) return YES
  if (value === false) return NO
  return String(value)
}

const childPath = (path, label) => (path ? `${path}${PATH_SEPARATOR}${label}` : label)

function arrayRows(items, path) {
  if (!items.length) return [{ label: path || VALUE_LABEL, value: NOTHING }]
  if (items.every(isPrimitive)) return [{ label: path || VALUE_LABEL, value: items.map(readable).join(', ') }]
  return items.flatMap((item, index) => rowsOf(item, childPath(path, String(index + 1))))
}

function recordRows(record, path) {
  const entries = Object.entries(record)
  if (!entries.length) return [{ label: path || VALUE_LABEL, value: NOTHING }]
  return entries.flatMap(([key, value]) => rowsOf(value, childPath(path, humanizeKey(key))))
}

function rowsOf(value, path) {
  if (Array.isArray(value)) return arrayRows(value, path)
  if (isRecord(value)) return recordRows(value, path)
  return [{ label: path || VALUE_LABEL, value: readable(value) }]
}

function parsed(json) {
  try {
    return { ok: true, value: JSON.parse(json) }
  } catch {
    return { ok: false }
  }
}

/** The parameters as rows; text that isn't JSON shows as one row, unchanged. */
export function parameterRows(parametersJSON) {
  if (!parametersJSON) return []
  const result = parsed(parametersJSON)
  if (!result.ok) return [{ label: RAW_LABEL, value: parametersJSON }]
  return rowsOf(result.value, '')
}

/** What the bot wants to do, where and with which tool. Empty fields are left out. */
export function actionRows(approval) {
  return [
    { label: 'Action', value: approval.action },
    { label: 'Website', value: approval.destination },
    { label: 'Tool', value: approval.tool },
  ].filter(row => row.value)
}
