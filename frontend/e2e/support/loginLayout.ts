// What the browser tests ask about the sign-in page layout: one centered column, no pitch panel on the left.
import { check } from './check.ts'
import type { Browse } from './page.ts'

const CENTER_TOLERANCE_PX = 2
const PITCH_TEXT = /one panel for every machine/i

interface Centers {
  viewport: number
  card: number | null
  owl: number | null
}

const centers = (b: Browse): Promise<Centers> =>
  b.run(() => {
    const middle = (element: Element | null) => (element ? element.getBoundingClientRect().left + element.getBoundingClientRect().width / 2 : null)
    return { viewport: document.documentElement.clientWidth / 2, card: middle(document.querySelector('.login form')), owl: middle(document.querySelector('.login img[data-owl="hero"]')) }
  })

const isCentered = (middle: number | null, viewport: number) => middle !== null && Math.abs(middle - viewport) <= CENTER_TOLERANCE_PX

/** Checks that the page has no left pitch panel and that the owl and the card sit in the middle of the window. */
export async function loginIsOneCentered(b: Browse, where: string): Promise<void> {
  check(`${where} has no pitch panel on the left`, (await b.run(() => document.querySelector('.login .pitch') === null)) && !PITCH_TEXT.test(await b.text()))
  const found = await centers(b)
  check(`${where} centers the owl and the card`, isCentered(found.owl, found.viewport) && isCentered(found.card, found.viewport), JSON.stringify(found))
}
