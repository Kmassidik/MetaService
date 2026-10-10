/**
 * Which saved files the Chat UI can show, and how. Pure: no DOM, no network.
 * Downloads are served as application/octet-stream on purpose; only the server-detected
 * `mediaType` of a ready file picks a decoder, and only for the types and sizes below.
 */
import { MiB } from '../constants.js'

const READY = 'ready'
const DELETED = 'deleted'
const PDF_TYPE = 'application/pdf'
const CSV_TYPE = 'text/csv'

export const IMAGE_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/gif'])

const IMAGE_PREVIEW_MIB = 25
const PDF_PREVIEW_MIB = 100
const TEXT_PREVIEW_MIB = 2
const EXTRACTION_MIB = 25

/** The most bytes each preview kind will download and decode. */
export const PREVIEW_LIMITS = Object.freeze({
  image: IMAGE_PREVIEW_MIB * MiB, pdf: PDF_PREVIEW_MIB * MiB, html: TEXT_PREVIEW_MIB * MiB, csv: TEXT_PREVIEW_MIB * MiB,
})

// Sentence case; only real acronyms stay in capitals.
export const PREVIEW_LABELS = Object.freeze({ image: 'image', pdf: 'PDF', html: 'HTML', csv: 'CSV' })

/** Text extraction (OCR) runs on the host for images and PDFs up to this size. */
export const EXTRACTION_LIMIT = EXTRACTION_MIB * MiB
const EXTRACTABLE_TYPES = new Set([...IMAGE_TYPES, PDF_TYPE])

// First match wins, as in the old Files panel: an oversized image is not shown as anything else.
const PREVIEW_RULES = [
  ['image', file => IMAGE_TYPES.has(file.mediaType)],
  ['pdf', file => file.mediaType === PDF_TYPE],
  ['html', file => /\.html?$/i.test(file.name)],
  ['csv', file => file.mediaType === CSV_TYPE || /\.csv$/i.test(file.name)],
]

/** 'image' | 'pdf' | 'html' | 'csv', or '' when the file has no safe visual preview. */
export function previewKind(file) {
  const rule = PREVIEW_RULES.find(([, matches]) => matches(file))
  if (!rule) return ''
  const [kind] = rule
  return file.size <= PREVIEW_LIMITS[kind] ? kind : ''
}

export function isReady(file) {
  return file?.state === READY
}

export function isDeleted(file) {
  return file?.state === DELETED
}

/** A ready image small enough to fetch and show as a picture (thumbnail and viewer). */
export function isViewableImage(file) {
  return isReady(file) && previewKind(file) === 'image'
}

/** A ready PDF, HTML or CSV file that opens in the document preview. */
export function isDocumentPreview(file) {
  return isReady(file) && ['pdf', 'html', 'csv'].includes(previewKind(file))
}

export function canExtractText(file) {
  return isReady(file) && file.size <= EXTRACTION_LIMIT && EXTRACTABLE_TYPES.has(file.mediaType)
}

/** Before the server has detected a type, an upload's name says whether it will be a picture. */
export function looksLikeImage(name = '') {
  return /\.(png|jpe?g|webp|gif)$/i.test(name)
}

export function downloadUrl(id) {
  return `/api/files/${encodeURIComponent(id)}/download`
}

const CATEGORY_RULES = [
  ['image', file => (file.mediaType || '').startsWith('image/')],
  ['pdf', file => file.mediaType === PDF_TYPE],
  ['spreadsheet', file => /spreadsheet|excel|csv/.test(file.mediaType || '') || /\.(csv|xlsx?|ods)$/i.test(file.name)],
  ['document', file => /word|presentation|text\//.test(file.mediaType || '') || /\.(docx?|pptx?|odt|odp)$/i.test(file.name)],
  ['media', file => /^(audio|video)\//.test(file.mediaType || '')],
]

/** The Files tab's type filter, in chip order. */
export const CATEGORIES = Object.freeze([
  { id: 'image', label: 'Images', icon: 'image' },
  { id: 'pdf', label: 'PDFs', icon: 'file' },
  { id: 'spreadsheet', label: 'Spreadsheets', icon: 'sheet' },
  { id: 'document', label: 'Documents', icon: 'file' },
  { id: 'media', label: 'Audio & video', icon: 'file' },
  { id: 'other', label: 'Other', icon: 'file' },
])

export function fileCategory(file) {
  return CATEGORY_RULES.find(([, matches]) => matches(file))?.[0] || 'other'
}

export function fileIcon(file) {
  const category = fileCategory(file)
  return CATEGORIES.find(item => item.id === category).icon
}
