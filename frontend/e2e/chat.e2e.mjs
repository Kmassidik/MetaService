// The Ruvio chat on a machine, in a real browser: the real Ruvio chat screen served by the chat service. Opening it with the key, a conversation that
// survives a reload, a new bot, a wrong or missing key, light and dark, and a phone. No script errors, failed requests or policy violations anywhere.
import { spawn } from 'node:child_process'
import { mkdtempSync, writeFileSync, chmodSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import puppeteer from 'puppeteer-core'

const CHROME = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const SHOTS = process.env.SHOTS_DIR
const PORT = 9300 + Math.floor(Math.random() * 400)
const KEY = 'k'.repeat(43)
let passed = 0
let failed = 0
const check = (name, ok, detail = '') => {
  if (ok) passed++
  else { failed++; console.log(`FAIL  ${name} ${detail}`) }
}
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

const dir = mkdtempSync(join(tmpdir(), 'ms-chat-e2e-'))
const keyFile = join(dir, 'key')
writeFileSync(keyFile, KEY)
chmodSync(keyFile, 0o600)
const service = spawn('python3', ['../bundles/chat/service/chat.py', '--port', String(PORT), '--bind', '127.0.0.1', '--key-file', keyFile], { stdio: 'ignore' })
const browser = await puppeteer.launch({ executablePath: CHROME, headless: true })
const base = `http://127.0.0.1:${PORT}`
const problems = []

/** A page; `fresh` gives it its own clean browser profile, as a different person would have (cookies are not shared). */
async function openPage(width = 1280, height = 800, fresh = false) {
  const page = await (fresh ? await browser.createBrowserContext() : browser).newPage()
  await page.setViewport({ width, height })
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  page.on('pageerror', (error) => problems.push(`script error: ${error.message}`))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|403|404)/.test(message.text()) && problems.push(`console: ${message.text()}`))
  page.on('requestfailed', (request) => problems.push(`request failed: ${request.url()}`))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => { (window.__csp ??= []).push(`${event.violatedDirective} ${event.blockedURI}`) }))
  return page
}

try {
  for (let i = 0; i < 50; i++) {
    if (await fetch(`${base}/health`).then((r) => r.ok, () => false)) break
    await pause(100)
  }
  const page = await openPage()
  const text = () => page.$eval('body', (b) => b.innerText)
  await page.goto(`${base}/#k=${KEY}`, { waitUntil: 'networkidle0' })
  await page.waitForSelector('nav[aria-label=Conversations]', { timeout: 15000 })
  check('opening with the key lands on the Ruvio chat screen and removes the key from the address', (await page.title()) === 'Ruvio' && !page.url().includes('k=') && page.url() === `${base}/`, page.url())
  check('the bot greets you from this machine', /I'm Ruvio, running on/.test(await text()))
  check('the real Ruvio screen is there: bot list, new chat, message box', Boolean(await page.$('textarea[aria-label="Message Ruvio"]')) && Boolean(await page.$('button[aria-label="New chat"]')))
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'chat-first.png') })

  await page.type('textarea[aria-label="Message Ruvio"]', 'hello there')
  await page.keyboard.press('Enter')
  await page.waitForFunction(() => /repeat you: hello there/.test(document.body.innerText), { timeout: 15000 })
  check('your message and the reply show in the conversation', /hello there/.test(await text()))
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'chat-light.png') })

  await page.reload({ waitUntil: 'networkidle0' })
  await page.waitForFunction(() => /repeat you: hello there/.test(document.body.innerText), { timeout: 15000 })
  check('the conversation is still there after a reload', true)

  await page.click('button[aria-label="New chat"]')
  await page.waitForSelector('[role=menu] button, [role=menuitem]', { timeout: 5000 })
  const clicked = await page.evaluate(() => { const item = [...document.querySelectorAll('[role=menu] button, [role=menuitem]')].find((b) => /new bot/i.test(b.innerText)); item?.click(); return Boolean(item) })
  check('New chat offers a new bot', clicked)
  await page.waitForFunction(() => document.querySelectorAll('nav[aria-label=Conversations] button, nav[aria-label=Conversations] a').length >= 2, { timeout: 15000 })
  check('the new bot appears in the list', /New bot/.test(await page.$eval('nav[aria-label=Conversations]', (n) => n.innerText)))

  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'dark' }])
  await pause(300)
  check('dark mode follows the system', await page.evaluate(() => getComputedStyle(document.body).backgroundColor !== 'rgb(255, 255, 255)'))
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'chat-dark.png') })
  check('no policy violations on the chat screen', !((await page.evaluate(() => window.__csp)) ?? []).length, JSON.stringify(await page.evaluate(() => window.__csp)))

  const wrong = await openPage(1280, 800, true)
  await wrong.goto(`${base}/#k=wrong`, { waitUntil: 'load' })
  await wrong.waitForFunction(() => /no longer works/.test(document.body.innerText))
  check('a wrong key says the link no longer works and opens nothing', !(await wrong.$('textarea')))
  const bare = await openPage(1280, 800, true)
  await bare.goto(`${base}/`, { waitUntil: 'load' })
  check('opened without a key it says where to open it from', /Open this chat from the MetaService panel/.test(await bare.$eval('body', (b) => b.innerText)))

  const phone = await openPage(390, 780, true)
  await phone.goto(`${base}/#k=${KEY}`, { waitUntil: 'load' })
  await phone.waitForSelector('textarea[aria-label^="Message "]', { timeout: 15000 }).catch(() => null)
  await pause(400)
  check('on a phone nothing scrolls sideways', await phone.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))
  if (SHOTS) await phone.screenshot({ path: join(SHOTS, 'chat-phone.png') })
  check('no script errors or failed requests in any page', problems.length === 0, JSON.stringify(problems.slice(0, 4)))
} finally {
  await browser.close()
  service.kill()
}
console.log(`${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
