// The Create VM window asks the parent which images the picked machine has, and the lines under the Image select can change the window's height when the answer arrives.
// A test that is about to press Create waits for the answer first, the way a person would not click while the form is still moving.
import type { Browse } from './page.ts'

const WAIT_MS = 10000
const UNREADABLE_NOTE = 'could not be read'

/** The window's Image list has arrived (or the page gave up on it and said so). */
export const imageListArrived = (b: Browse) =>
  b.until((note) => document.querySelectorAll('#vm-create-image option').length > 1 || document.querySelector('dialog[open]')?.textContent?.includes(note) === true, { timeout: WAIT_MS }, UNREADABLE_NOTE)
