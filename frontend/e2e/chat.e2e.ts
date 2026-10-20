// The Ruvio chat on a machine, in a real browser: the real Ruvio chat screen served by the chat service. Opening it with the key, a conversation that
// survives a reload, a new bot, a wrong or missing key, light and dark, and a phone. No script errors, failed requests or policy violations anywhere.
// Needs: python3, Google Chrome (or CHROME_PATH), and `bun install` in frontend/. Run: bun e2e/chat.e2e.ts
import { spawn } from 'node:child_process'
import { chmodSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import puppeteer, { type Page } from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { wait, waitForHealth } from './support/net.ts'
import { chatService, chromePath, screenshotDir } from './support/paths.ts'

const PORT_BASE = 9300
const PORT_SPREAD = 400
const KEY = 'k'.repeat(43)
const PHONE = { width: 390, height: 780 }
const DESKTOP = { width: 1280, height: 800 }
const REPLY_WAIT_MS = 15000
const SETTLE_MS = 300

const port = PORT_BASE + Math.floor(Math.random() * PORT_SPREAD)
const base = `http://127.0.0.1:${port}`
const problems: string[] = []

const dir = mkdtempSync(join(tmpdir(), 'ms-chat-e2e-'))
const keyFile = join(dir, 'key')
writeFileSync(keyFile, KEY)
chmodSync(keyFile, 0o600)
const service = spawn('python3', [chatService, '--port', String(port), '--bind', '127.0.0.1', '--key-file', keyFile], { stdio: 'ignore' })
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true })

const bodyText = (page: Page) => page.evaluate(() => document.body.innerText)
const violations = (page: Page) => page.evaluate(() => window.violations ?? [])

/** A page; `fresh` gives it its own clean browser profile, as a different person would have (cookies are not shared). */
async function openPage(size = DESKTOP, fresh = false): Promise<Page> {
  const page = await (fresh ? await browser.createBrowserContext() : browser).newPage()
  await page.setViewport(size)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  page.on('pageerror', (error) => problems.push(`script error: ${error instanceof Error ? error.message : String(error)}`))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|403|404)/.test(message.text()) && problems.push(`console: ${message.text()}`))
  page.on('requestfailed', (request) => problems.push(`request failed: ${request.url()}`))
  await page.evaluateOnNewDocument(() => {
    document.addEventListener('securitypolicyviolation', (event) => {
      window.violations = [...(window.violations ?? []), `${event.violatedDirective} ${event.blockedURI}`]
    })
  })
  return page
}

async function shot(page: Page, name: `${string}.png`): Promise<void> {
  if (screenshotDir) await page.screenshot({ path: `${screenshotDir}/${name}` })
}

async function openedWithTheKey(page: Page): Promise<void> {
  await page.goto(`${base}/#k=${KEY}`, { waitUntil: 'networkidle0' })
  await page.waitForSelector('nav[aria-label=Conversations]', { timeout: REPLY_WAIT_MS })
  check('opening with the key lands on the Ruvio chat screen and removes the key from the address', (await page.title()) === 'Ruvio' && !page.url().includes('k=') && page.url() === `${base}/`, page.url())
  check('the bot greets you from this machine', /I'm Ruvio, running on/.test(await bodyText(page)))
  check('the real Ruvio screen is there: bot list, new chat, message box', Boolean(await page.$('textarea[aria-label="Message Ruvio"]')) && Boolean(await page.$('button[aria-label="New chat"]')))
  await shot(page, 'chat-first.png')
}

async function conversationSurvivesReload(page: Page): Promise<void> {
  await page.type('textarea[aria-label="Message Ruvio"]', 'hello there')
  await page.keyboard.press('Enter')
  await page.waitForFunction(() => /repeat you: hello there/.test(document.body.innerText), { timeout: REPLY_WAIT_MS })
  check('your message and the reply show in the conversation', /hello there/.test(await bodyText(page)))
  await shot(page, 'chat-light.png')
  await page.reload({ waitUntil: 'networkidle0' })
  await page.waitForFunction(() => /repeat you: hello there/.test(document.body.innerText), { timeout: REPLY_WAIT_MS })
  check('the conversation is still there after a reload', true)
}

async function newBot(page: Page): Promise<void> {
  await page.click('button[aria-label="New chat"]')
  await page.waitForSelector('[role=menu] button, [role=menuitem]', { timeout: 5000 })
  const clicked = await page.evaluate(() => {
    const item = [...document.querySelectorAll<HTMLElement>('[role=menu] button, [role=menuitem]')].find((entry) => /new bot/i.test(entry.innerText))
    item?.click()
    return Boolean(item)
  })
  check('New chat offers a new bot', clicked)
  await page.waitForFunction(() => document.querySelectorAll('nav[aria-label=Conversations] button, nav[aria-label=Conversations] a').length >= 2, { timeout: REPLY_WAIT_MS })
  const list = await page.$eval('nav[aria-label=Conversations]', (nav) => nav instanceof HTMLElement ? nav.innerText : '')
  check('the new bot appears in the list', /New bot/.test(list))
}

async function darkMode(page: Page): Promise<void> {
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'dark' }])
  await wait(SETTLE_MS)
  check('dark mode follows the system', await page.evaluate(() => getComputedStyle(document.body).backgroundColor !== 'rgb(255, 255, 255)'))
  await shot(page, 'chat-dark.png')
  const seen = await violations(page)
  check('no policy violations on the chat screen', seen.length === 0, JSON.stringify(seen))
}

async function wrongAndMissingKey(): Promise<void> {
  const wrong = await openPage(DESKTOP, true)
  await wrong.goto(`${base}/#k=wrong`, { waitUntil: 'load' })
  await wrong.waitForFunction(() => /no longer works/.test(document.body.innerText))
  check('a wrong key says the link no longer works and opens nothing', !(await wrong.$('textarea')))
  const bare = await openPage(DESKTOP, true)
  await bare.goto(`${base}/`, { waitUntil: 'load' })
  check('opened without a key it says where to open it from', /Open this chat from the MetaService panel/.test(await bodyText(bare)))
}

async function onAPhone(): Promise<void> {
  const phone = await openPage(PHONE, true)
  await phone.goto(`${base}/#k=${KEY}`, { waitUntil: 'load' })
  await phone.waitForSelector('textarea[aria-label^="Message "]', { timeout: REPLY_WAIT_MS })
  await wait(SETTLE_MS)
  check('on a phone nothing scrolls sideways', await phone.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))
  await shot(phone, 'chat-phone.png')
}

try {
  await waitForHealth(base, 'the chat service')
  const page = await openPage()
  await openedWithTheKey(page)
  await conversationSurvivesReload(page)
  await newBot(page)
  await darkMode(page)
  await wrongAndMissingKey()
  await onAPhone()
  check('no script errors or failed requests in any page', problems.length === 0, JSON.stringify(problems.slice(0, 4)))
} finally {
  await browser.close()
  service.kill()
}
finish()
