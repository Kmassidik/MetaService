// The Helper row of the machine page and the Update helper button in a real browser against a stand-in parent: each state of the row, the button from press to result
// (updated, rolled back, failed, login needed), text from the parent that stays text, the "Update available" tag of the Machines list, and no sideways scrolling at phone width.
// Needs: a built panel (PANEL_DIST, `bunx vite build --outDir <dir>`), Google Chrome (or CHROME_PATH), `bun install` in frontend/.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/helper-update.e2e.ts
import puppeteer, { type Page } from 'puppeteer-core'
import { startFakeParent, type HelperScenario } from './machine/fake-parent.ts'
import { expandAll } from './machine/environment.ts'
import { SHORT_WAIT_MS, expectNoSideScroll, openMachine, openTab } from './machine/steps.ts'
import { check, finish } from './support/check.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const SIZES = { desktop: { width: 1280, height: 900 }, phone: { width: 400, height: 844 } }
const OLD = 'a'.repeat(64)
const NEW = 'b'.repeat(64)
const HOSTILE = '<img src=x onerror="window.pwned=1"><script>window.pwned=1</script>'
const UPDATED_TEXT = 'The helper was replaced with the newest one and it is running. Your VMs keep running.'
const ROLLED_BACK_TEXT = 'The new helper did not start, so the old one was put back and is running again. Nothing was lost.'
const LOGIN_TEXT = 'MetaService cannot log in to this computer any more: add it again once, then updates will work.'
const NO_BUILD_TEXT = 'The parent has no MetaService program for this kind of computer, so its helper cannot be updated from here.'

const answer = (result: string, message: string) => ({ status: 200, body: { result, message } })
const scenario = (extra: Partial<HelperScenario> = {}): HelperScenario => ({ build: OLD, newest: NEW, answer: answer('updated', UPDATED_TEXT), ...extra })

const helperRow = (b: Browse) => b.run(() => {
  const row = document.querySelector<HTMLElement>('section[aria-label=Software] .helper')
  const button = row?.querySelector('button')
  return row ? {
    text: row.innerText, build: row.querySelector('.build')?.textContent ?? '', status: row.querySelector('[data-helper-status]')?.textContent ?? '',
    button: button?.textContent?.trim() ?? '', disabled: button?.disabled ?? true,
  } : null
})

async function openEnvironment(b: Browse, base: string) {
  await openMachine(b, base, 'mac-studio')
  await openTab(b, 'Environment')
  await expandAll(b)
  await b.until(() => !!document.querySelector('section[aria-label=Software] .helper'), { timeout: SHORT_WAIT_MS })
}

const untilOutcome = (b: Browse, title: string) => b.until((wanted) => [...document.querySelectorAll('.outcome b')].some((node) => node.textContent === `${wanted}.`), { timeout: SHORT_WAIT_MS }, title)

async function pictures(page: Page, b: Browse, base: string, name: string) {
  for (const [size, viewport] of Object.entries(SIZES)) {
    await page.setViewport(viewport)
    await openEnvironment(b, base)
    await b.shot(`helper-${name}-${size}-light.png`, true)
    await expectNoSideScroll(b, `${name}, ${size}`)
  }
}

async function states(page: Page, b: Browse) {
  const cases: Array<[string, HelperScenario, { build: string; status: string; label: string; disabled: boolean }]> = [
    ['available', scenario(), { build: 'aaaaaaaa', status: 'available', label: 'Update available', disabled: false }],
    ['old-helper', scenario({ build: null }), { build: 'not reported', status: 'unknown', label: 'Unknown (old helper)', disabled: false }],
    ['up-to-date', scenario({ build: NEW }), { build: 'bbbbbbbb', status: 'up_to_date', label: 'Up to date', disabled: true }],
    ['no-build', scenario({ newest: null, reason: NO_BUILD_TEXT }), { build: 'aaaaaaaa', status: 'cannot', label: 'Cannot be updated from here', disabled: true }],
    ['offline', scenario({ offline: true }), { build: 'aaaaaaaa', status: 'available', label: 'Update available', disabled: true }],
  ]
  for (const [name, helper, expected] of cases) {
    const parent = startFakeParent({ chatsBuilt: 1, dist: panelDist, helper })
    try {
      await page.setViewport(SIZES.desktop)
      await openEnvironment(b, parent.base)
      const row = await helperRow(b)
      check(`${name}: the row shows the build ${expected.build}, "${expected.label}" and a button that is ${expected.disabled ? 'off' : 'on'}`,
        row?.build === expected.build && row.status === expected.label && row.button === 'Update helper' && row.disabled === expected.disabled, JSON.stringify(row))
      check(`${name}: the row says what the button does`, row?.text.includes('Replaces the MetaService program on this computer with the newest one. Your VMs keep running.') === true)
      if (name === 'no-build') check('no-build: the parent\'s reason is shown', row?.text.includes(NO_BUILD_TEXT) === true)
      if (name === 'offline') check('offline: the row says the machine is offline', row?.text.includes('The machine is offline.') === true)
      await pictures(page, b, parent.base, name)
    } finally {
      parent.stop()
    }
  }
}

async function listTag(page: Page, b: Browse) {
  const parent = startFakeParent({ chatsBuilt: 1, dist: panelDist, helper: scenario() })
  try {
    await page.setViewport(SIZES.desktop)
    await page.goto(`${parent.base}/#/machines`, { waitUntil: 'networkidle0' })
    await b.until(() => document.querySelectorAll('article.card').length === 2, { timeout: SHORT_WAIT_MS })
    const tags = await b.run(() => [...document.querySelectorAll('article.card')].map((card) => ({ name: card.querySelector('.nm')?.textContent ?? '', tag: card.querySelector('[data-update-tag]')?.textContent ?? null })))
    check('the Machines list tags only the machine that has an update', JSON.stringify(tags.sort((a, c) => a.name.localeCompare(c.name))) === JSON.stringify([{ name: 'mac-mini', tag: null }, { name: 'mac-studio', tag: 'Update available' }]), JSON.stringify(tags))
    await b.shot('helper-list-tag-desktop-light.png', true)
    await page.setViewport(SIZES.phone)
    await expectNoSideScroll(b, 'Machines list with the tag, phone')
    await b.shot('helper-list-tag-phone-light.png', true)
  } finally {
    parent.stop()
  }
}

async function pressAndWait(page: Page, b: Browse, name: string, helper: HelperScenario, title: string, detail: string) {
  const parent = startFakeParent({ chatsBuilt: 1, dist: panelDist, helper })
  try {
    await page.setViewport(SIZES.desktop)
    await openEnvironment(b, parent.base)
    await b.click('Update helper')
    await b.until(() => document.querySelector('section[aria-label=Software] .helper button')?.textContent?.trim() === 'Updating…', { timeout: SHORT_WAIT_MS })
    const busy = await helperRow(b)
    check(`${name}: while it works the button says Updating… and cannot be pressed again`, busy?.disabled === true && busy.button === 'Updating…')
    await untilOutcome(b, title)
    const outcome = await b.run(() => document.querySelector<HTMLElement>('.outcome')?.innerText ?? '')
    check(`${name}: the result is told in words ("${title}")`, outcome.includes(title) && outcome.includes(detail), outcome)
    check(`${name}: the parent was asked once, for this machine`, parent.updates.join() === 'mac-studio', parent.updates.join())
    await b.shot(`helper-${name}-result-desktop-light.png`, true)
    await page.setViewport(SIZES.phone)
    await expectNoSideScroll(b, `${name} result, phone`)
    await b.shot(`helper-${name}-result-phone-light.png`, true)
  } finally {
    parent.stop()
  }
}

const CARD = 'article.card:has([data-update-tag]) [data-card-update] button'
const openList = async (page: Page, b: Browse, base: string) => {
  await page.goto(`${base}/#/machines`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelectorAll('article.card').length === 2, { timeout: SHORT_WAIT_MS })
}
const cardButtons = (b: Browse) => b.run(() => [...document.querySelectorAll('article.card')].map((card) => ({ name: card.querySelector('.nm')?.textContent ?? '', button: card.querySelector<HTMLElement>('[data-card-update] button')?.textContent?.trim() ?? null, note: card.querySelector<HTMLElement>('.cu-note')?.innerText ?? null })))

async function cardUpdate(page: Page, b: Browse) {
  const parent = startFakeParent({ chatsBuilt: 1, dist: panelDist, helper: scenario() })
  try {
    await page.setViewport(SIZES.desktop)
    await openList(page, b, parent.base)
    const cards = (await cardButtons(b)).sort((a, c) => a.name.localeCompare(c.name))
    check('card: only the machine with an update has the Update helper button', JSON.stringify(cards.map((card) => card.button)) === JSON.stringify([null, 'Update helper']), JSON.stringify(cards))
    await b.shot('helper-card-button-desktop-light.png', true)
    await page.setViewport(SIZES.phone)
    await expectNoSideScroll(b, 'card with the button, phone')
    await b.shot('helper-card-button-phone-light.png', true)
    await page.setViewport(SIZES.desktop)
    await page.click(CARD)
    await b.until(() => document.querySelector('[data-card-update] button')?.textContent?.trim() === 'Updating…', { timeout: SHORT_WAIT_MS })
    check('card: while it works the button says Updating… and cannot be pressed again', await b.run(() => document.querySelector<HTMLButtonElement>('[data-card-update] button')?.disabled === true))
    await b.shot('helper-card-updating-desktop-light.png', true)
    await page.setViewport(SIZES.phone)
    await b.shot('helper-card-updating-phone-light.png', true)
    await b.until(() => !!document.querySelector('[data-card-outcome]'), { timeout: SHORT_WAIT_MS })
    await b.until(() => !document.querySelector('[data-update-tag]'), { timeout: SHORT_WAIT_MS })
    const after = await b.run(() => ({ outcome: document.querySelector<HTMLElement>('[data-card-outcome]')?.innerText ?? '', buttons: document.querySelectorAll('[data-card-update]').length }))
    check('card: the result is told on the card, the tag and the button are gone', after.outcome.includes('Updated.') && after.outcome.includes(UPDATED_TEXT) && after.buttons === 0, JSON.stringify(after))
    check('card: the parent was asked once, for this machine', parent.updates.join() === 'mac-studio', parent.updates.join())
    await expectNoSideScroll(b, 'card result, phone')
    await b.shot('helper-card-result-phone-light.png', true)
    await page.setViewport(SIZES.desktop)
    await b.shot('helper-card-result-desktop-light.png', true)
  } finally {
    parent.stop()
  }
}

async function cardOffline(page: Page, b: Browse) {
  const parent = startFakeParent({ chatsBuilt: 1, dist: panelDist, helper: scenario({ offline: true }) })
  try {
    await page.setViewport(SIZES.desktop)
    await openList(page, b, parent.base)
    const cards = await cardButtons(b)
    const studio = cards.find((card) => card.name === 'mac-studio')
    check('card: an offline machine has no button and says it is offline', cards.every((card) => card.button === null) && studio?.note === 'The machine is offline.', JSON.stringify(cards))
    await page.setViewport(SIZES.phone)
    await expectNoSideScroll(b, 'offline card, phone')
  } finally {
    parent.stop()
  }
}

async function cardFailure(page: Page, b: Browse) {
  const parent = startFakeParent({ chatsBuilt: 1, dist: panelDist, helper: scenario({ answer: { status: 409, body: { error: { code: 'login_needed', message: HOSTILE } } } }) })
  try {
    await page.setViewport(SIZES.desktop)
    await openList(page, b, parent.base)
    await page.click(CARD)
    await b.until(() => !!document.querySelector('[data-card-outcome]'), { timeout: SHORT_WAIT_MS })
    const outcome = await b.run(() => ({ text: document.querySelector<HTMLElement>('[data-card-outcome]')?.innerText ?? '', made: !!document.querySelector('[data-card-outcome] img') || 'pwned' in window }))
    check('card: a refusal is shown as text and the button stays for another try', outcome.text.includes('Login needed.') && outcome.text.includes(HOSTILE) && !outcome.made, JSON.stringify(outcome))
    check('card: the button is back after a refusal', (await cardButtons(b)).some((card) => card.button === 'Update helper'))
  } finally {
    parent.stop()
  }
}

async function updated(page: Page, b: Browse) {
  const parent = startFakeParent({ chatsBuilt: 1, dist: panelDist, helper: scenario({ build: null }) })
  try {
    await page.setViewport(SIZES.desktop)
    await openEnvironment(b, parent.base)
    await b.click('Update helper')
    await untilOutcome(b, 'Updated')
    await b.until(() => document.querySelector('section[aria-label=Software] .helper .build')?.textContent === 'bbbbbbbb', { timeout: SHORT_WAIT_MS })
    const row = await helperRow(b)
    check('updated: the machine is read again and the row shows the new build as Up to date, with the button off', row?.status === 'Up to date' && row.disabled === true, JSON.stringify(row))
    await b.shot('helper-updated-desktop-light.png', true)
    await page.goto(`${parent.base}/#/machines`, { waitUntil: 'networkidle0' })
    await b.until(() => document.querySelectorAll('article.card').length === 2, { timeout: SHORT_WAIT_MS })
    check('updated: the tag is gone from the Machines list', (await b.run(() => document.querySelectorAll('[data-update-tag]').length)) === 0)
  } finally {
    parent.stop()
  }
}

async function hostile(page: Page, b: Browse) {
  const helper = scenario({ newest: null, reason: HOSTILE, answer: answer('failed', HOSTILE) })
  const parent = startFakeParent({ chatsBuilt: 1, dist: panelDist, helper })
  try {
    await page.setViewport(SIZES.phone)
    await openEnvironment(b, parent.base)
    const note = await b.run(() => document.querySelector<HTMLElement>('section[aria-label=Software] .helper .note')?.innerText ?? '')
    check('hostile text: the parent\'s reason is shown as text', note === HOSTILE, note)
    check('hostile text: it made no element and ran nothing', await b.run(() => !document.querySelector('section[aria-label=Software] img') && !('pwned' in window)))
    await expectNoSideScroll(b, 'hostile reason, phone')
    await b.shot('helper-hostile-phone-light.png', true)
  } finally {
    parent.stop()
  }
  const failing = startFakeParent({ chatsBuilt: 1, dist: panelDist, helper: scenario({ answer: answer('failed', HOSTILE) }) })
  try {
    await openEnvironment(b, failing.base)
    await b.click('Update helper')
    await untilOutcome(b, 'Update failed')
    const outcome = await b.run(() => document.querySelector<HTMLElement>('.outcome')?.innerText ?? '')
    check('hostile text: a result sentence is shown as text too', outcome.includes(HOSTILE), outcome)
    check('hostile text: it made no element and ran nothing there either', await b.run(() => !document.querySelector('.outcome img') && !('pwned' in window)))
  } finally {
    failing.stop()
  }
}

const errors: string[] = []
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (403|409)/.test(message.text()) && errors.push(message.text()))
  const b = browse(page)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  await states(page, b)
  await listTag(page, b)
  await cardUpdate(page, b)
  await cardOffline(page, b)
  await cardFailure(page, b)
  await updated(page, b)
  await pressAndWait(page, b, 'rolled-back', scenario({ answer: answer('rolled_back', ROLLED_BACK_TEXT) }), 'Rolled back', ROLLED_BACK_TEXT)
  await pressAndWait(page, b, 'failed', scenario({ answer: answer('failed', 'The program could not be copied to that computer. Nothing was changed.') }), 'Update failed', 'could not be copied')
  await pressAndWait(page, b, 'login-needed', scenario({ answer: { status: 409, body: { error: { code: 'login_needed', message: LOGIN_TEXT } } } }), 'Login needed', LOGIN_TEXT)
  await hostile(page, b)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
}
finish()
