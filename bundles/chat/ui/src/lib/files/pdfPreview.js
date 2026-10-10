/** PDF previews: pdf.js loaded on demand, no eval, no embedded fonts, bounded pages and pixels. */

export const PDF_MAX_PAGES = 200
export const PDF_MAX_PIXELS = 12_000_000
const PDF_MAX_SIDE_PX = 4096
const PDF_MAX_SCALE = 1.5
const CANVAS_MAX_AREA_BYTES = 48_000_000

/** The render scale: sharp, but never past 12 megapixels or 4096 px a side. */
export function pdfScale({ width, height }) {
  if (!Number.isFinite(width * height) || width <= 0 || height <= 0) throw new Error('PDF page dimensions are invalid.')
  return Math.min(PDF_MAX_SCALE, Math.sqrt(PDF_MAX_PIXELS / (width * height)), PDF_MAX_SIDE_PX / width, PDF_MAX_SIDE_PX / height)
}

/** A pdf.js loading task for `data`; the caller awaits `.promise` and destroys the task. */
export async function openPdf(data) {
  const [{ getDocument, GlobalWorkerOptions }, { default: workerUrl }] = await Promise.all([
    import('pdfjs-dist'),
    import('pdfjs-dist/build/pdf.worker.min.mjs?url'),
  ])
  GlobalWorkerOptions.workerSrc = workerUrl
  return getDocument({
    data, isEvalSupported: false, disableFontFace: true, useSystemFonts: true, useWasm: false,
    maxImageSize: PDF_MAX_PIXELS, canvasMaxAreaInBytes: CANVAS_MAX_AREA_BYTES, stopAtErrors: true,
  })
}
