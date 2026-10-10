/** How a message lays out its attachments: pictures in a grid, everything else as file chips. */
import { isViewableImage } from './preview.js'

// Two and four pictures read best as pairs; three, five and more as rows of three.
const MAX_PAIRED_COUNT = 4
const PAIR_COLUMNS = 2
const ROW_COLUMNS = 3

/** Columns for `count` pictures; one picture keeps its own shape at up to ~320 px. */
export function gridColumns(count) {
  if (count <= 1) return 1
  const paired = count <= MAX_PAIRED_COUNT && count % PAIR_COLUMNS === 0
  return paired ? PAIR_COLUMNS : ROW_COLUMNS
}

/** Splits a message's attachments into pictures (shown inline) and other files (chips). */
export function splitAttachments(items = []) {
  const images = items.filter(isViewableImage)
  const others = items.filter(item => !isViewableImage(item))
  return { images, others }
}
