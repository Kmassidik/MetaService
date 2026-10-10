// The Ruvio chat page on a machine, in a real browser: the first screen, a message and its reply, an error, light and dark.
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

const dir = mkdtempSync(join(tmpdir(), 'ms-chat-e2e-'))
const keyFile = join(dir, 'key')
writeFileSync(keyFile, KEY)
chmodSync(keyFile, 0o600)
const service = spawn('python3', ['../bundles/chat/service/chat.py', '--port', String(PORT), '--bind', '127.0.0.1', '--key-file', keyFile], { stdio: 'ignore' })
const browser = await puppeteer.launch({ executablePath: CHROME, headless: true })
try {
  for (let i = 0; i < 50; i++) {
    if (await fetch(`http://127.0.0.1:${PORT}/health`).then((r) => r.ok, () => false)) break
    await new Promise((r) => setTimeout(r, 100))
  }
  const page = await browser.newPage()
  await page.setViewport({ width: 1100, height: 760 })
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  await page.goto(`http://127.0.0.1:${PORT}/#k=${KEY}`, { waitUntil: 'networkidle0' })
  const text = () => page.$eval('body', (b) => b.innerText)
  check('the first screen greets you as Ruvio', /Hi, I'm Ruvio/.test(await text()) && (await page.title()) === 'Ruvio')
  check('the key is removed from the address bar', !page.url().includes('#k='), page.url())
  check('the logo loads', await page.$eval('img.mark', (img) => img.complete && img.naturalWidth > 0))
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'chat-first.png') })
  await page.type('#input', 'hello there')
  await page.keyboard.press('Enter')
  await page.waitForFunction(() => document.querySelectorAll('.row.theirs .bubble').length === 1, { timeout: 10000 })
  const rows = await page.$$eval('.row', (nodes) => nodes.map((n) => [n.className, n.innerText]))
  check('your message and the reply show as bubbles, the first screen is gone', rows.length === 2 && rows[0][0].includes('mine') && rows[0][1] === 'hello there' && /repeat you: hello there/.test(rows[1][1]) && (await page.$eval('#empty', (e) => e.hidden)), JSON.stringify(rows))
  check('Shift+Enter adds a line and does not send', await (async () => {
    await page.type('#input', 'a')
    await page.keyboard.down('Shift'); await page.keyboard.press('Enter'); await page.keyboard.up('Shift')
    await page.type('#input', 'b')
    return (await page.$eval('#input', (i) => i.value)) === 'a\nb' && (await page.$$('.row')).length === 2
  })())
  await page.$eval('#input', (i) => { i.value = '' })
  const mineBackground = await page.$eval('.row.mine .bubble', (b) => getComputedStyle(b).backgroundColor)
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'chat-light.png') })
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'dark' }])
  const dark = await page.evaluate(() => [getComputedStyle(document.body).backgroundColor, getComputedStyle(document.querySelector('.row.mine .bubble')).backgroundColor])
  check('dark mode follows the system', dark[0] === 'rgb(13, 13, 14)' && dark[1] !== mineBackground, JSON.stringify(dark))
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'chat-dark.png') })
  const wrong = await browser.newPage()
  await wrong.goto(`http://127.0.0.1:${PORT}/#k=wrong`, { waitUntil: 'networkidle0' })
  await wrong.type('#input', 'hi')
  await wrong.keyboard.press('Enter')
  await wrong.waitForSelector('.row.problem')
  check('a wrong key shows a plain error bubble', /wrong access key/.test(await wrong.$eval('.row.problem', (n) => n.innerText)))
  const bare = await browser.newPage()
  await bare.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'networkidle0' })
  check('opened without a key it says where to open it from', /Open this chat from the MetaService panel/.test(await bare.$eval('body', (b) => b.innerText)) && await bare.$eval('#send', (b) => b.disabled))
  const phone = await browser.newPage()
  await phone.setViewport({ width: 390, height: 780 })
  await phone.goto(`http://127.0.0.1:${PORT}/#k=${KEY}`, { waitUntil: 'networkidle0' })
  check('on a phone nothing scrolls sideways', await phone.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))
  if (SHOTS) await phone.screenshot({ path: join(SHOTS, 'chat-phone.png') })
} finally {
  await browser.close()
  service.kill()
}
console.log(`${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
