/**
 * Host text extraction (OCR) for an image or PDF. A request ID is reserved first, so Stop works
 * even before the slow extract call starts. Requests use keepalive so a cancel still reaches the
 * server when the viewer closes.
 */
import { arrayOf, isNumber, isRecord, isString, objectOf } from '../check.ts'

const NOT_FOUND = 404

/** One page the host read: the text, its number, and where the text came from (the picture or the PDF itself). */
export interface ExtractedPage {
  page: number
  text: string
  source: string
}

/** What the host read from a file, with the engine that read it and what it could not do. */
export interface Extraction {
  engine: string
  revision: number
  warnings: string[]
  pages: ExtractedPage[]
}

const isReservation = objectOf<{ requestId: string }>({ requestId: isString })
const isExtractedPage = objectOf<ExtractedPage>({ page: isNumber, text: isString, source: isString })
const isExtraction = objectOf<Extraction>({
  engine: isString, revision: isNumber, warnings: arrayOf(isString), pages: arrayOf(isExtractedPage),
})
const isExtractionAnswer = objectOf<{ extraction: Extraction }>({ extraction: isExtraction })

function headers(key: string, json = false): Record<string, string> {
  return { 'X-CSRF-Token': key, Accept: 'application/json', ...(json ? { 'Content-Type': 'application/json' } : {}) }
}

function filePath(fileId: string, rest: string): string {
  return `/api/files/${encodeURIComponent(fileId)}/extract${rest}`
}

async function errorFrom(response: Response, fallback: string): Promise<Error> {
  const data: unknown = await response.json().catch(() => null)
  const reason = isRecord(data) && typeof data.error === 'string' ? data.error : ''
  return new Error(reason || `${fallback} (${response.status}).`)
}

export async function reserveExtraction(fileId: string, key: string): Promise<string> {
  const response = await fetch(filePath(fileId, '/requests'), { method: 'POST', credentials: 'same-origin', headers: headers(key), keepalive: true })
  if (!response.ok) throw await errorFrom(response, 'Text extraction could not start')
  const reserved: unknown = await response.json().catch(() => null)
  if (!isReservation(reserved)) throw new Error('The server returned an invalid extraction request.')
  return reserved.requestId
}

/** Starts the slow extract call; once it answers, the worker is done whatever the answer says. */
export function startExtraction(fileId: string, key: string, requestId: string): Promise<Response> {
  return fetch(filePath(fileId, ''), { method: 'POST', credentials: 'same-origin', headers: headers(key, true), body: JSON.stringify({ requestId }) })
}

export async function readExtraction(response: Response): Promise<Extraction> {
  if (!response.ok) throw await errorFrom(response, 'Text extraction failed')
  const data: unknown = await response.json().catch(() => null)
  if (!isExtractionAnswer(data)) throw new Error('The server returned an unreadable extraction result.')
  return data.extraction
}

/** A finished or expired request (404) cannot affect a later extraction, so it counts as cancelled. */
export async function cancelExtraction(fileId: string, key: string, requestId: string): Promise<void> {
  const path = filePath(fileId, `/${encodeURIComponent(requestId)}/cancel`)
  const response = await fetch(path, { method: 'POST', credentials: 'same-origin', headers: headers(key), keepalive: true })
  if (!response.ok && response.status !== NOT_FOUND) throw await errorFrom(response, 'Could not request extraction cancellation')
}

export function extractedText(extraction: Extraction): string {
  return extraction.pages.map(page => page.text).join('\n\n')
}
