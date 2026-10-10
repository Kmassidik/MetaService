/** HTML and CSV previews: decoded strictly as UTF-8, HTML reduced to static markup, CSV to text cells. */
import DOMPurify from 'dompurify'
import Papa from 'papaparse'

export const CSV_MAX_ROWS = 200
export const CSV_MAX_COLUMNS = 50
const UNDETECTABLE_DELIMITER = 'UndetectableDelimiter'

const HTML_TAGS = ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'br', 'hr', 'div', 'span', 'strong', 'b', 'em', 'i', 'u', 's', 'small', 'sub', 'sup', 'blockquote', 'pre', 'code', 'ul', 'ol', 'li', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'caption', 'section', 'article', 'header', 'footer', 'main', 'figure', 'figcaption']
const HTML_ATTRIBUTES = ['colspan', 'rowspan', 'scope', 'start']
const FRAME_POLICY = "default-src 'none'; script-src 'none'; style-src 'none'; img-src 'none'; connect-src 'none'; font-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'"

export function decodeText(data) {
  return new TextDecoder('utf-8', { fatal: true }).decode(data)
}

/** A sandboxed srcdoc: no scripts, CSS, forms, links, URLs, embeds or network resources survive. */
export function sanitizedHtml(source) {
  const content = DOMPurify.sanitize(source, { ALLOWED_TAGS: HTML_TAGS, ALLOWED_ATTR: HTML_ATTRIBUTES, ALLOW_DATA_ATTR: false, ALLOW_ARIA_ATTR: false })
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${FRAME_POLICY}"><meta name="referrer" content="no-referrer"></head><body>${content}</body></html>`
}

/** What the HTML or CSV view shows for downloaded bytes: the source plus its safe rendering. */
export function prepareTextPreview(kind, data) {
  const source = decodeText(data)
  return kind === 'html' ? { source, html: sanitizedHtml(source) } : { source, ...parseCsvPreview(source) }
}

/** The first rows and columns as plain strings (formulas are never evaluated). */
export function parseCsvPreview(source) {
  const parsed = Papa.parse(source, { preview: CSV_MAX_ROWS + 1, skipEmptyLines: 'greedy', dynamicTyping: false })
  const errors = parsed.errors.filter(item => item.code !== UNDETECTABLE_DELIMITER)
  if (errors.length) throw new Error(`CSV could not be safely parsed: ${errors[0].message}`)
  const rows = parsed.data.slice(0, CSV_MAX_ROWS).map(row => row.slice(0, CSV_MAX_COLUMNS))
  const truncated = parsed.meta.truncated || parsed.data.length > CSV_MAX_ROWS || parsed.data.some(row => row.length > CSV_MAX_COLUMNS)
  return { rows, truncated }
}
