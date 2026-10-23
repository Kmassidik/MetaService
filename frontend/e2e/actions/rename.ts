// Renaming a machine in a real browser against the stand-in Root: the pencil in the header and on every list row, the window prefilled, the plain words for a bad name,
// Escape and Cancel sending nothing, a name that clashes in other capitals refused inside the window, a tricky legal name saved by five rapid clicks as ONE request
// and shown in the header and the list without a reload while the address keeps the id, and a phone-width screen.
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { burst, fresh } from './guard.ts'
import type { StandIn } from './standin.ts'

const LIST = '#/machines'
const DETAIL = '#/machines/details?id=studio'
const INPUT = 'dialog[open] #rename-machine-name'
const SHORT_WAIT_MS = 8000
const SLOW_MS = 700
const SETTLE_MS = 1500
const RAPID_CLICKS = 5
const TRICKY_NAME = "Luca's PC (RTX)"
const RULE_WORDS = "Use letters, numbers, spaces and - _ . ( ) ' &, up to 48 characters."
const CLASH_WORDS = 'another machine already has that name'
export const PHONE = { width: 400, height: 844 }
export const DESKTOP = { width: 1280, height: 800 }

const pencils = (b: Browse) => b.run(() => [...document.querySelectorAll<HTMLButtonElement>('button[data-tip="Rename machine"]')].map((button) => button.getAttribute('aria-label') ?? '').sort())
const dialogOpen = (b: Browse) => b.run(() => document.querySelector('dialog[open]') !== null)
const inputValue = (b: Browse) => b.run(() => document.querySelector<HTMLInputElement>('dialog[open] #rename-machine-name')?.value ?? null)
const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth && [...document.querySelectorAll<HTMLElement>('dialog[open]')].every((dialog) => dialog.scrollWidth <= dialog.clientWidth))
const headerName = (b: Browse) => b.run(() => document.querySelector('h1.name')?.textContent?.trim() ?? '')
const listNames = (b: Browse) => b.run(() => [...document.querySelectorAll('article.card a.nm')].map((link) => link.textContent?.trim() ?? ''))
const modalLine = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('dialog[open] .aline')?.innerText.trim() ?? '')
const hint = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('dialog[open] .hint')?.innerText.trim() ?? '')

async function openRename(b: Browse, label: string): Promise<void> {
  await b.page.click(`button[aria-label="${label}"]`)
  await b.page.waitForSelector(INPUT, { timeout: SHORT_WAIT_MS })
}

async function pencilsAreThere(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, LIST)
  await b.page.waitForSelector('article.card')
  const rows = await pencils(b)
  check('every list row has the pencil, named "Rename machine <name>" with the tooltip "Rename machine"', JSON.stringify(rows) === JSON.stringify(['Rename machine mini', 'Rename machine studio']), JSON.stringify(rows))
  await b.shot('rename-list-desktop.png')
  await fresh(b, standin, DETAIL)
  await b.page.waitForSelector('h1.name')
  const header = await pencils(b)
  check('the machine page header has the pencil, named with the machine name', JSON.stringify(header) === JSON.stringify(['Rename machine studio']), JSON.stringify(header))
  await b.shot('rename-header-desktop.png')
}

async function opensPrefilledAndSendsNothingWhenLeft(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, DETAIL)
  await openRename(b, 'Rename machine studio')
  const title = await b.run(() => document.querySelector('dialog[open] h3')?.textContent?.trim())
  check('the window is titled "Rename machine" and the box holds the current name', title === 'Rename machine' && (await inputValue(b)) === 'studio', `${title} ${await inputValue(b)}`)
  check('Save is off while the name is unchanged', await b.isDisabled('Save'))
  await b.shot('rename-modal-desktop.png')
  await b.page.keyboard.press('Escape')
  await wait(SETTLE_MS / 5)
  check('Escape closes the window and sends nothing', !(await dialogOpen(b)) && standin.settingsPatches.length === 0)
  await openRename(b, 'Rename machine studio')
  await b.click('Cancel')
  await wait(SETTLE_MS / 5)
  check('Cancel closes the window and sends nothing', !(await dialogOpen(b)) && standin.settingsPatches.length === 0)
}

async function badNameIsRefusedInThePageWithPlainWords(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, DETAIL)
  await openRename(b, 'Rename machine studio')
  await b.type(INPUT, 'a;b')
  check('a name with a semicolon shows the plain rule and Save is off', (await hint(b)) === RULE_WORDS && (await b.isDisabled('Save')), await hint(b))
  await b.page.keyboard.press('Enter')
  await wait(SETTLE_MS / 3)
  check('Enter on a bad name sends nothing', standin.settingsPatches.length === 0 && (await dialogOpen(b)))
}

async function clashShowsInsideTheWindow(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, DETAIL)
  await openRename(b, 'Rename machine studio')
  await b.type(INPUT, 'MINI')
  await b.click('Save')
  await b.until(() => !!document.querySelector('dialog[open] .aline.bad'), { timeout: SHORT_WAIT_MS })
  check('a name that differs only in capitals from another machine is refused with the server words, inside the window', (await modalLine(b)) === CLASH_WORDS && (await dialogOpen(b)), await modalLine(b))
  await b.shot('rename-refusal-desktop.png')
  check('the refused rename changed nothing on the page', (await inputValue(b)) === 'MINI' && !(await b.isDisabled('Save')))
  await b.click('Cancel')
}

async function trickyNameSavesOnceAndShowsEverywhere(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, DETAIL)
  standin.behaviour.delayMs = SLOW_MS
  await openRename(b, 'Rename machine studio')
  await b.type(INPUT, TRICKY_NAME)
  await burst(b, 'Save', RAPID_CLICKS)
  await wait(SLOW_MS / 3)
  check('while it saves the window stays open and locked', (await dialogOpen(b)) && (await b.isDisabled('Cancel')))
  await b.page.keyboard.press('Escape')
  check('Escape does not close the window while it saves', await dialogOpen(b))
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
  check(`${RAPID_CLICKS} rapid Save clicks send ONE request with only the name`, standin.settingsPatches.length === 1 && JSON.stringify(standin.settingsPatches[0]) === JSON.stringify({ name: TRICKY_NAME }), JSON.stringify(standin.settingsPatches))
  check('the header shows the new name without a reload', (await headerName(b)) === TRICKY_NAME, await headerName(b))
  check('the address still holds the machine id', (await b.run(() => location.hash)) === DETAIL)
  await b.go(LIST)
  await b.page.waitForSelector('article.card')
  check('the list shows the new name, as text', (await listNames(b)).includes(TRICKY_NAME), JSON.stringify(await listNames(b)))
  await b.shot('rename-list-renamed-desktop.png')
  standin.behaviour.delayMs = 0
}

async function listPencilWorksAndPhoneFits(b: Browse, standin: StandIn): Promise<void> {
  await b.page.setViewport(PHONE)
  await fresh(b, standin, LIST)
  await b.page.waitForSelector('article.card')
  check('phone: the list has no sideways scroll with the pencils', await noSideScroll(b))
  await b.shot('rename-list-phone.png', true)
  await openRename(b, 'Rename machine mini')
  check('phone: the list pencil opens the window for that row, prefilled', (await inputValue(b)) === 'mini')
  await b.type(INPUT, 'a;b')
  check('phone: no sideways scroll in the window, with the refusal showing', await noSideScroll(b))
  await b.shot('rename-modal-phone.png')
  await b.type(INPUT, 'Mac Studio (office)')
  await b.click('Save')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
  check('phone: saving from the list shows the new name on its row', (await listNames(b)).includes('Mac Studio (office)'), JSON.stringify(await listNames(b)))
  await fresh(b, standin, DETAIL)
  await b.page.waitForSelector('h1.name')
  check('phone: no sideways scroll on the machine page header with the pencil', await noSideScroll(b))
  await b.shot('rename-header-phone.png')
  await b.page.setViewport(DESKTOP)
}

export async function renameWorks(b: Browse, standin: StandIn): Promise<void> {
  await pencilsAreThere(b, standin)
  await opensPrefilledAndSendsNothingWhenLeft(b, standin)
  await badNameIsRefusedInThePageWithPlainWords(b, standin)
  await clashShowsInsideTheWindow(b, standin)
  await trickyNameSavesOnceAndShowsEverywhere(b, standin)
  await listPencilWorksAndPhoneFits(b, standin)
}
