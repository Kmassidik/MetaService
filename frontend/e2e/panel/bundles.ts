// The chat bundle: pinning a version, turning Ruvio on for a machine, upgrading by a newer pin, and rolling back.
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { openTab, pressSwitch, untilSwitch } from '../machine/steps.ts'
import { startAgent, type World } from './world.ts'

const SHORT_WAIT_MS = 10000
const INSTALL_WAIT_MS = 30000
const UPGRADE_WAIT_MS = 60000
const MACHINE = 'chat-mac'

const pinTo = (b: Browse, version: string) =>
  b.run((wanted) => [...document.querySelectorAll('section[aria-label="Chat bundle"] li')].find((item) => item instanceof HTMLElement && item.innerText.includes(wanted))?.querySelector('button')?.click(), version)

const waitForChatVersion = (b: Browse, version: string, timeout: number) => b.until((wanted) => document.body.innerText.includes(`chat ${wanted}`), { timeout }, version)

export async function bundleScenario(b: Browse, world: World): Promise<void> {
  const agent = await startAgent(world, MACHINE)
  try {
    await b.go('#/machines')
    await b.until((name) => document.body.innerText.includes(name), { timeout: 20000 }, MACHINE)
    await b.go('#/settings')
    await b.until(() => /chat bundle/i.test(document.body.innerText), {})
    await pinTo(b, '0.1.0')
    await b.until(() => /0\.1\.0[\s\S]*pinned/.test(document.body.innerText), { timeout: SHORT_WAIT_MS })
    check('pinning a version marks it pinned', true)
    await b.go(`#/machines/details?id=${MACHINE}`)
    await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, MACHINE)
    await openTab(b, 'Environment')
    await b.until(() => document.querySelector<HTMLButtonElement>('button[role=switch]')?.disabled === false, { timeout: SHORT_WAIT_MS })
    await pressSwitch(b)
    await untilSwitch(b, true)
    await b.until((wanted) => new RegExp(`Installed version\\s*${wanted}`, 'i').test(document.body.innerText), { timeout: INSTALL_WAIT_MS }, '0\\.1\\.0')
    check('turning Ruvio on from the Environment tab shows its installed version', true)
    await b.click('Open chat')
    await b.page.waitForSelector('dialog[open] a')
    check('the chat link opens in a new tab without leaking the referrer', (await b.page.$eval('dialog[open] a', (link) => link instanceof HTMLAnchorElement ? link.rel : '')).includes('noopener'))
    await b.click('Close')
    await b.go('#/settings')
    await pinTo(b, '0.2.0')
    await b.go('#/machines')
    await waitForChatVersion(b, '0.2.0', UPGRADE_WAIT_MS)
    check('a newer pin upgrades the installed chat by itself', true)
    await b.go('#/settings')
    await b.click('Roll back to 0.1.0')
    await b.go('#/machines')
    await waitForChatVersion(b, '0.1.0', UPGRADE_WAIT_MS)
    check('a rollback puts the older chat back', true)
    await b.shot('bundles.png', true)
  } finally {
    agent.kill()
  }
}
