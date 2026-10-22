// What the browser tests ask about the owl pictures: the one that belongs on a screen is there, it really loaded, the Root served it as a WebP, and nothing scrolls sideways.
import { check } from './check.ts'
import type { Browse } from './page.ts'

const OWL_WAIT_MS = 10000
const WEBP_TYPE = 'image/webp'
const SERVED_FOR_A_YEAR = /immutable/

interface Shown {
  loaded: boolean
  src: string
  width: number
  decorative: boolean
}

const find = (b: Browse, name: string): Promise<Shown | null> =>
  b.run((owl) => {
    const image = document.querySelector<HTMLImageElement>(`img[data-owl="${owl}"]`)
    if (!image) return null
    return { loaded: image.complete && image.naturalWidth > 0, src: image.currentSrc, width: image.getBoundingClientRect().width, decorative: image.alt === '' && image.getAttribute('aria-hidden') === 'true' }
  }, name)

/** The Root's own answer for the picture's address, asked from inside the page so the page policy applies. */
const served = (b: Browse, src: string) =>
  b.run(async (address) => {
    const reply = await fetch(address)
    return { status: reply.status, type: reply.headers.get('content-type') ?? '', cache: reply.headers.get('cache-control') ?? '', url: reply.url, redirected: reply.redirected, where: location.href }
  }, src)

/** Checks that the owl called `name` is on the screen, loaded, drawn at a real size, served as a WebP, and marked as decoration. */
export async function owlShown(b: Browse, name: string, where: string): Promise<void> {
  await b.until((owl) => document.querySelector<HTMLImageElement>(`img[data-owl="${owl}"]`)?.complete === true, { timeout: OWL_WAIT_MS }, name)
  await b.run((owlName) => document.querySelector<HTMLImageElement>(`img[data-owl="${owlName}"]`)?.decode(), name)
  const owl = await find(b, name)
  if (!owl) return check(`${where} shows the ${name} owl`, false, 'no picture on the page')
  const reply = await served(b, owl.src)
  const ok = owl.loaded && owl.width > 0 && owl.decorative && reply.status === 200 && reply.type === WEBP_TYPE
  check(`${where} shows the ${name} owl, loaded, served as a WebP`, ok, JSON.stringify({ owl, reply }))
}

/** Checks that the Root hands the owl picture out with the year-long cache of its other hashed files (only the real Root does; the stand-ins do not). */
export async function owlCachedForAYear(b: Browse, name: string): Promise<void> {
  const owl = await find(b, name)
  const reply = owl ? await served(b, owl.src) : null
  check(`the ${name} owl is cached for a year`, reply !== null && SERVED_FOR_A_YEAR.test(reply.cache), JSON.stringify(reply))
}

/** Checks that no owl of this name is on the screen. */
export async function owlAbsent(b: Browse, name: string, where: string): Promise<void> {
  check(`${where} shows no ${name} owl`, (await find(b, name)) === null)
}

/** Checks that the page does not scroll sideways at the current size. */
export async function noSideScroll(b: Browse, where: string): Promise<void> {
  check(`${where} has no sideways scrolling`, await b.run(() => document.documentElement.scrollWidth <= window.innerWidth))
}
