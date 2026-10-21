// What the browser tests do on a page again and again: read its text, press a button by its label, type into a field, wait for something to show.
// Headless Chrome now and then swaps the page's frame between two calls; Puppeteer reports that as an error although nothing went wrong.
// Every read and wait here is tried again then, and any other error still fails the test.
import type { Page } from 'puppeteer-core'
import { wait } from './net.ts'
import { screenshotDir } from './paths.ts'

const FRAME_SWAP = /detached Frame|Execution context was destroyed/
const ATTEMPTS = 4
const RETRY_PAUSE_MS = 300
const HASH_SETTLE_MS = 300

async function retrying<T>(action: () => Promise<T>): Promise<T> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await action()
    } catch (error) {
      const swapped = error instanceof Error && FRAME_SWAP.test(error.message)
      if (attempt >= ATTEMPTS || !swapped) throw error
      await wait(RETRY_PAUSE_MS)
    }
  }
}

export function browse(page: Page) {
  /** Runs a function inside the page and gives back what it returns. */
  const run: Page['evaluate'] = (work, ...args) => retrying(() => page.evaluate(work, ...args))

  /** Waits until a function inside the page gives a true answer: `until(check, { timeout }, ...arguments)`. */
  const until: Page['waitForFunction'] = (ready, options, ...args) => retrying(() => page.waitForFunction(ready, options, ...args))

  const text = () => run(() => document.body.innerText)

  /** What the open dialog says, or the empty string when none is open. */
  const dialogText = () => run(() => document.querySelector<HTMLElement>('dialog[open]')?.innerText ?? '')

  /** Presses the button with this label, in the open dialog when there is one. */
  async function click(label: string): Promise<void> {
    const found = await run((wanted) => {
      const inDialog = document.querySelector('dialog[open]') !== null
      const buttons = [...(inDialog ? document.querySelectorAll('dialog[open] button') : document.querySelectorAll('button'))]
      return { inDialog, index: buttons.findIndex((button) => button.textContent?.trim() === wanted) }
    }, label)
    const button = (await page.$$(found.inDialog ? 'dialog[open] button' : 'button'))[found.index]
    if (found.index < 0 || !button) throw new Error(`there is no button "${label}"`)
    await button.click()
  }

  /** True when the button with this label (in the open dialog, if any) is switched off. */
  const isDisabled = (label: string) =>
    run((wanted) => [...(document.querySelector('dialog[open]') ?? document).querySelectorAll('button')].find((b) => b.textContent?.trim() === wanted)?.disabled ?? false, label)

  /** Empties a field the way a person would, so the page notices, then types the value. */
  async function type(selector: string, value: string): Promise<void> {
    await run((where) => {
      const input = document.querySelector<HTMLInputElement>(where)
      if (!input) throw new Error(`no field ${where}`)
      input.value = ''
      input.dispatchEvent(new Event('input', { bubbles: true }))
    }, selector)
    await page.type(selector, value)
  }

  /** Moves between the panel's pages the way a person does: through the address. */
  async function go(hash: string): Promise<void> {
    await run((wanted) => { location.hash = wanted }, hash)
    await wait(HASH_SETTLE_MS)
  }

  /** Opens the Machines dropdown in the sidebar when it is closed (it opens by itself on a machines page). */
  async function openMachinesMenu(): Promise<void> {
    const expanded = await run(() => document.querySelector('aside.side nav button[aria-controls="machines-menu"]')?.getAttribute('aria-expanded') === 'true')
    if (!expanded) await page.click('aside.side nav button[aria-controls="machines-menu"]')
    await page.waitForSelector('#machines-menu')
  }

  /** Saves a picture when a screenshots folder was asked for (SHOTS_DIR). */
  async function shot(name: `${string}.png`, fullPage = false): Promise<void> {
    if (screenshotDir) await page.screenshot({ path: `${screenshotDir}/${name}`, fullPage })
  }

  return { page, run, until, text, dialogText, click, isDisabled, type, go, openMachinesMenu, shot }
}

export type Browse = ReturnType<typeof browse>
