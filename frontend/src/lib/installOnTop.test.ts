import { expect, test } from 'bun:test'
import { bundleOfFramework, frameworkCards } from './imageChoices.ts'
import { imageAfterChange, imageBundle, imageOptions, parseMachineImages, STOCK_IMAGE } from './images.ts'
import { LOGOS } from './logos.ts'

const CAPTION = 'Installs after the VM starts, about 2 minutes'
const OLD_HELPER = 'Update the helper on this machine first'
const stock = { id: 'blank', title: 'Blank (plain Ubuntu)', description: 'Plain.', state: 'ready', ready: true, available: true, reason: null }
const app = (id: string, title: string, overrides: Record<string, unknown>) => ({ id, title, description: CAPTION, state: 'ready', ready: true, available: true, reason: null, ...overrides })
const catalog = (images: unknown[]) => imageOptions(parseMachineImages({ helper: 'answered', images }))

const bothReady = catalog([stock, app('openclaw', 'OpenClaw', {}), app('hermes', 'Hermes', {})])
const oldHelper = catalog([stock, app('openclaw', 'OpenClaw', { available: false, reason: OLD_HELPER }), app('hermes', 'Hermes', { available: false, reason: OLD_HELPER })])

test('when the catalog makes OpenClaw and Hermes ready both can be picked, with the catalog caption, an Installs on start chip, and their id as the bundle', () => {
  const [, openclaw, hermes] = frameworkCards(bothReady)
  for (const card of [openclaw, hermes]) expect(card).toMatchObject({ disabled: false, caption: CAPTION, tag: 'Installs on start' })
  expect(openclaw?.logo).toBe(LOGOS.openclaw)
  expect(hermes?.logo).toBe(LOGOS.hermes)
  expect(imageBundle(bundleOfFramework('openclaw'))).toBe('openclaw')
  expect(imageBundle(bundleOfFramework('hermes'))).toBe('hermes')
  expect(imageAfterChange(bothReady, 'hermes')).toBe('hermes')
})

test('for an old helper both stay greyed out with the catalog reason and not the Installs on start chip', () => {
  const [, openclaw, hermes] = frameworkCards(oldHelper)
  for (const card of [openclaw, hermes]) {
    expect(card).toMatchObject({ disabled: true, caption: OLD_HELPER })
    expect(card?.tag).not.toBe('Installs on start')
  }
  expect(imageAfterChange(oldHelper, 'openclaw')).toBe(STOCK_IMAGE)
})

test('the plain Ubuntu choice still sends no bundle at all', () => {
  expect(imageBundle(bundleOfFramework('none'))).toBeUndefined()
})

test('the logos of OpenClaw and Hermes are bundled files, the Hermes one a webp picture', () => {
  expect(LOGOS.openclaw).toMatch(/openclaw.*\.svg$/)
  expect(LOGOS.hermes).toMatch(/hermes.*\.webp$/)
})
