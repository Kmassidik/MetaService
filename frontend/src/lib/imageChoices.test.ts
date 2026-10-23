import { expect, test } from 'bun:test'
import { bundleOfFramework, frameworkCards, frameworkOfBundle, NO_FRAMEWORK, serverCards } from './imageChoices.ts'
import { imageAfterChange, imageBundle, imageOptions, parseMachineImages, STOCK_IMAGE } from './images.ts'
import { LOGOS } from './logos.ts'

const COMING_SOON = 'Coming soon: needs the image to be prepared on the machine'
const WAITING = 'Waiting for a pinned release and checksum'
const stock = { id: 'blank', title: 'Blank (plain Ubuntu)', description: 'Plain.', state: 'ready', ready: true, available: true, reason: null }
const openclaw = { id: 'openclaw', title: 'OpenClaw', description: 'Blank, plus OpenClaw.', state: 'planned', ready: false, available: false, reason: COMING_SOON }
const hermes = { id: 'hermes', title: 'Hermes', description: 'Blank, plus Hermes.', state: 'ready', ready: false, available: false, reason: WAITING }
const catalog = (images: unknown[]) => imageOptions(parseMachineImages({ helper: 'answered', images }))
const real = catalog([stock, openclaw, hermes])
const openclawReady = catalog([stock, { ...openclaw, state: 'ready', ready: true, available: true, reason: null }, hermes])

test('Server image lists the stock Ubuntu first, selectable and the default, then five systems that are only previews', () => {
  const cards = serverCards(real)
  expect(cards.map((card) => card.title)).toEqual(['Ubuntu Server 24.04 LTS', 'Debian 12', 'Fedora Server', 'Rocky Linux', 'AlmaLinux', 'Alpine Linux'])
  expect(cards[0]).toEqual({ id: STOCK_IMAGE, title: 'Ubuntu Server 24.04 LTS', caption: 'Plain Ubuntu with the usual server tools. Nothing else.', disabled: false, tag: 'Default', logo: LOGOS.ubuntu })
  for (const card of cards.slice(1)) expect(card).toMatchObject({ disabled: true, tag: 'Coming soon', caption: 'Coming soon: not tested on this machine yet' })
  expect(cards.every((card) => card.logo !== undefined)).toBe(true)
  expect(cards.some((card) => card.title.includes('Blank'))).toBe(false)
})

test('before the answer, or when it cannot be read, the stock Ubuntu is still the selectable default', () => {
  expect(serverCards(imageOptions(null))[0]).toMatchObject({ id: STOCK_IMAGE, disabled: false, tag: 'Default' })
})

test('if the machine does not offer the stock image it is greyed out with the catalog reason', () => {
  const off = catalog([{ ...stock, state: 'planned', ready: false, available: false, reason: 'Not on this machine' }])
  expect(serverCards(off)[0]).toMatchObject({ disabled: true, caption: 'Not on this machine', title: 'Ubuntu Server 24.04 LTS' })
  expect(serverCards([])[0]).toMatchObject({ disabled: true, caption: 'not available yet' })
})

test('the preview rows can never become a request value', () => {
  for (const card of [...serverCards(real), ...frameworkCards(real)].filter((entry) => entry.id.startsWith('preview-'))) {
    expect(card.disabled).toBe(true)
    expect(bundleOfFramework(card.id)).toBe(STOCK_IMAGE)
  }
})

test('Install on top starts with None, then OpenClaw and Hermes with their catalog reasons, and nothing else', () => {
  const cards = frameworkCards(real)
  expect(cards.map((card) => card.title)).toEqual(['None — just the server', 'OpenClaw', 'Hermes'])
  expect(cards[0]).toMatchObject({ id: NO_FRAMEWORK, disabled: false, glyph: 'none' })
  expect(cards[0]?.logo).toBeUndefined()
  expect(cards[1]).toMatchObject({ id: 'openclaw', disabled: true, caption: COMING_SOON, tag: 'Coming soon', logo: LOGOS.openclaw })
  expect(cards[2]).toMatchObject({ id: 'hermes', disabled: true, caption: WAITING, tag: 'Waiting', logo: LOGOS.hermes })
})

test('None sends the stock image like before, and a framework the catalog makes ready sends its own id', () => {
  expect(bundleOfFramework(NO_FRAMEWORK)).toBe(STOCK_IMAGE)
  expect(imageBundle(bundleOfFramework(NO_FRAMEWORK))).toBeUndefined()
  const card = frameworkCards(openclawReady).find((entry) => entry.id === 'openclaw')
  expect(card).toMatchObject({ disabled: false, caption: 'Blank, plus OpenClaw.', tag: 'Installs on start' })
  expect(imageBundle(bundleOfFramework('openclaw'))).toBe('openclaw')
  expect(imageAfterChange(openclawReady, 'openclaw')).toBe('openclaw')
  expect(imageAfterChange(real, 'openclaw')).toBe(STOCK_IMAGE)
})

test('the form bundle and the Install on top row map to each other', () => {
  expect(frameworkOfBundle(undefined)).toBe(NO_FRAMEWORK)
  expect(frameworkOfBundle('')).toBe(NO_FRAMEWORK)
  expect(frameworkOfBundle(STOCK_IMAGE)).toBe(NO_FRAMEWORK)
  expect(frameworkOfBundle('openclaw')).toBe('openclaw')
})

test('hostile catalog text stays text and a hostile framework stays as greyed out as the catalog says', () => {
  const hostile = '<img src=x onerror=alert(1)>'
  const card = frameworkCards(catalog([stock, { ...openclaw, title: hostile, reason: hostile }]))[1]
  expect(card).toMatchObject({ title: hostile, caption: hostile, disabled: true })
})
