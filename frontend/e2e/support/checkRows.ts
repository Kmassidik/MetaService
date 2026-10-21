// The rows of the Check step as a browser test reads them. A tick or a cross is a drawn mark, not a glyph, so a row's state comes from its data-state, never from a character.
import type { Page } from 'puppeteer-core'

export interface CheckRowView {
  id: string
  /** ready (a tick), blocking (a cross that stops adding) or optional (a cross that does not). */
  state: string
  /** What a person sees in the row: the label, a short value or the sentence. The folded manual steps are not in it. */
  shown: string
  /** Everything in the row, the folded manual steps too. */
  all: string
  buttons: string[]
  marks: number
  manualSteps: boolean
}

const ROWS = 'dialog[open] .checks li'

export const readRows = (page: Page): Promise<CheckRowView[]> =>
  page.$$eval(ROWS, (items) =>
    items.map((item) => ({
      id: item.getAttribute('data-check') ?? '',
      state: item.getAttribute('data-state') ?? '',
      shown: item instanceof HTMLElement ? item.innerText.replace(/\s+/g, ' ').trim() : '',
      all: (item.textContent ?? '').replace(/\s+/g, ' ').trim(),
      buttons: [...item.querySelectorAll('button')].map((button) => (button.textContent ?? '').trim()),
      marks: item.querySelectorAll('.mark svg').length,
      manualSteps: item.querySelector('details.manual') !== null,
    })),
  )

export const findRow = (rows: CheckRowView[], id: string): CheckRowView | undefined => rows.find((row) => row.id === id)

/** True when every label of the rows starts at the same x: the mark column has one fixed width. */
export const labelsAligned = (page: Page): Promise<boolean> =>
  page.$$eval(`${ROWS} .lbl`, (labels) => new Set(labels.map((label) => Math.round(label.getBoundingClientRect().left))).size === 1)
