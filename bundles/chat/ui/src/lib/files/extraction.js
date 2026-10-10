/**
 * Host text extraction (OCR) for an image or PDF. A request ID is reserved first, so Stop works
 * even before the slow extract call starts. Requests use keepalive so a cancel still reaches the
 * server when the viewer closes.
 */
const NOT_FOUND = 404

function headers(key, json = false) {
  return { 'X-CSRF-Token': key, Accept: 'application/json', ...(json ? { 'Content-Type': 'application/json' } : {}) }
}

function filePath(fileId, rest) {
  return `/api/files/${encodeURIComponent(fileId)}/extract${rest}`
}

async function errorFrom(response, fallback) {
  const data = await response.json().catch(() => null)
  return new Error(data?.error || `${fallback} (${response.status}).`)
}

export async function reserveExtraction(fileId, key) {
  const response = await fetch(filePath(fileId, '/requests'), { method: 'POST', credentials: 'same-origin', headers: headers(key), keepalive: true })
  if (!response.ok) throw await errorFrom(response, 'Text extraction could not start')
  const reserved = await response.json().catch(() => null)
  if (typeof reserved?.requestId !== 'string') throw new Error('The server returned an invalid extraction request.')
  return reserved.requestId
}

/** Starts the slow extract call; once it answers, the worker is done whatever the answer says. */
export function startExtraction(fileId, key, requestId) {
  return fetch(filePath(fileId, ''), { method: 'POST', credentials: 'same-origin', headers: headers(key, true), body: JSON.stringify({ requestId }) })
}

export async function readExtraction(response) {
  if (!response.ok) throw await errorFrom(response, 'Text extraction failed')
  const data = await response.json().catch(() => null)
  if (!data?.extraction?.pages) throw new Error('The server returned an unreadable extraction result.')
  return data.extraction
}

/** A finished or expired request (404) cannot affect a later extraction, so it counts as cancelled. */
export async function cancelExtraction(fileId, key, requestId) {
  const path = filePath(fileId, `/${encodeURIComponent(requestId)}/cancel`)
  const response = await fetch(path, { method: 'POST', credentials: 'same-origin', headers: headers(key), keepalive: true })
  if (!response.ok && response.status !== NOT_FOUND) throw await errorFrom(response, 'Could not request extraction cancellation')
}

export function extractedText(extraction) {
  return extraction.pages.map(page => page.text).join('\n\n')
}
