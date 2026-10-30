// Share a PC page, against a stand-in parent with a small hub behind /api/join-share/*:
// the sidebar entry, the three buttons and CPU states, the command and Copy, approve (wrong code, then the right one, name taken), refuse,
// the joined list and Remove, the not set up and hub-not-answering states, hostile host names, polling, and no script errors.
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { wait } from './support/net.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { RIGHT_CODE, startHub } from './share/hub.ts'

const POLL_WAIT_MS = 12_000
const QUIET_MS = 9_000
const hub = await startHub()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport({ width: 1440, height: 900 })
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  // The clipboard is not available to a headless page; this stand-in keeps what Copy wrote.
  await page.evaluateOnNewDocument(() => {
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: async (text: string) => { (window as unknown as Record<string, string>).__copied = text } } })
  })
  const b = browse(page)
  const pageText = () => b.run(() => document.querySelector<HTMLElement>('main')?.innerText ?? '')
  const field = (label: string) => `input[aria-label="${label}"]`

  await page.goto(`${hub.base}/#/`, { waitUntil: 'networkidle0' })
  check('Share a PC has no row of its own in the sidebar: it is one of the Machines pages', await b.run(() =>
    [...document.querySelectorAll('aside.side nav > div > a')].every((link) => link.textContent?.trim() !== 'Share a PC')))
  await page.click('aside.side button[aria-controls="machines-menu"]')
  await b.until(() => document.querySelector('#machines-menu a[href="#/share"]') !== null)
  check('the Machines dropdown lists Machine list, Find machines, Share a PC', await b.run(() =>
    [...document.querySelectorAll('#machines-menu a')].map((link) => link.textContent?.trim()).join('|') === 'Machine list|Find machines|Share a PC'))
  await page.click('#machines-menu a[href="#/share"]')
  await b.until(() => document.querySelector('h1')?.textContent === 'Share a PC')
  check('the entry opens the page, is marked, and the Machines row is marked too', await b.run(() =>
    document.querySelector('#machines-menu a[href="#/share"]')?.getAttribute('aria-current') === 'page' && document.querySelector('aside.side button.group')?.classList.contains('here') === true))

  // ---- the buttons and the CPU states ----
  await b.until(() => document.querySelectorAll('[aria-label="System"] button').length === 3)
  check('the three buttons are Mac, Windows and Linux', (await b.run(() => [...document.querySelectorAll('[aria-label="System"] button')].map((x) => x.textContent?.trim()))).join() === 'Mac,Windows,Linux')
  check('before a system is chosen the page says so and the command cannot be made', (await pageText()).includes('Choose a system first.') && await b.isDisabled('Make the command'))
  await b.click('Windows')
  const windowsText = (await pageText()).toLowerCase()
  check('Windows: no build yet and coming soon, both off, with a reason', windowsText.includes('no build yet') && windowsText.includes('coming soon') && windowsText.includes('this system is coming soon.') && windowsText.includes('there is no helper build for this computer yet.'))
  check('Windows: no CPU can be chosen', await b.run(() => [...document.querySelectorAll('[aria-label="Processor"] button')].every((x) => (x as HTMLButtonElement).disabled)))
  await b.click('Mac')
  const macState = await b.run(() => [...document.querySelectorAll('[aria-label="Processor"] button')].map((x) => `${(x as HTMLButtonElement).disabled}:${x.querySelector('.tag')?.textContent}`).join('|'))
  check('Mac: Apple silicon is ready, Intel is not tested yet, both can be chosen', macState === 'false:ready|false:not tested yet', macState)
  await b.shot('share-choose-1440.png')

  // ---- the command and Copy ----
  await page.click('[aria-label="Processor"] button:nth-child(2)')
  check('an untested build warns when chosen', (await b.run(() => document.querySelector('[data-testid="cpu-note"]')?.textContent ?? '')).includes('may not work'))
  await page.click('[aria-label="Processor"] button:nth-child(1)')
  await b.click('Make the command')
  await b.until(() => document.querySelector('[data-testid="command"]') !== null)
  const command = await b.run(() => document.querySelector('[data-testid="command"]')?.textContent ?? '')
  check('the command comes from the hub for that system and CPU', command.includes('os=mac&cpu=arm64') && command.endsWith('| sh'), command)
  await b.click('Copy')
  await b.until(() => document.body.innerText.includes('Copied'))
  check('Copy puts the command on the clipboard', (await b.run(() => (window as unknown as Record<string, string>).__copied)) === command)
  await b.click('Linux')
  check('choosing another system hides the old command', await b.run(() => document.querySelector('[data-testid="command"]') === null))

  // ---- waiting machines ----
  const waiting = (await pageText()).toLowerCase()
  check('the waiting machines are listed with their time and tries', waiting.includes('far mac') && waiting.includes('5 tries left') && waiting.includes('min left'))
  check('the name defaults to the host name and the share to what was asked', await b.run(() => (document.querySelector('input[aria-label="Name for Far Mac"]') as HTMLInputElement).value === 'far-mac' && (document.querySelector('input[aria-label="Cores for Far Mac"]') as HTMLInputElement).value === '4'))
  const hostile = await b.run(() => ({ shown: document.querySelectorAll('[data-testid="pending-host"]')[1]?.textContent ?? '', images: document.querySelectorAll('main img').length, pwned: (window as unknown as Record<string, unknown>).__pwned }))
  check('a hostile host name is shown as text and runs nothing', hostile.shown.startsWith('<img src=x') && hostile.images === 0 && hostile.pwned === undefined, JSON.stringify(hostile))

  await b.click('Approve')
  await b.until(() => document.body.innerText.includes('Type the 6-digit code'))
  check('Approve without a code asks for it and sends nothing', hub.approvals.length === 0)
  await b.type(field('Code from Far Mac'), '000000')
  await page.click('tbody tr:first-child td:last-child .abtn button')
  await b.until(() => document.body.innerText.includes('That code is wrong. 4 tries left.'))
  check('a wrong code shows the tries left and clears the code field', await b.run(() => (document.querySelector('input[aria-label="Code from Far Mac"]') as HTMLInputElement).value === ''))
  await b.type(field('Code from Far Mac'), RIGHT_CODE)
  await page.click('tbody tr:first-child td:last-child .abtn button')
  await b.until(() => document.querySelector('input[aria-label="Code from Far Mac"]') === null)
  const approval = JSON.stringify(hub.approvals.at(-1))
  check('the right code approves with the name and the asked share', approval === JSON.stringify({ code: RIGHT_CODE, name: 'far-mac', share: { cores: 4, ram_mb: 8192, disk_gb: 100 } }), approval)
  check('the approved machine is in the joined list', (await pageText()).includes('far-mac') && hub.peers.some((peer) => peer.name === 'far-mac'))

  await b.type(field('Code from busy-box'), RIGHT_CODE)
  await page.click('tbody tr:nth-child(2) td:last-child .abtn button')
  await b.until(() => document.body.innerText.includes('That name is already used.'))
  check('a name already used shows a plain message and the row stays', await b.run(() => document.querySelector('input[aria-label="Code from busy-box"]') !== null))

  await b.click('Refuse')
  await b.until(() => !document.body.innerText.includes('<img src=x'))
  check('Refuse takes the machine out of the list', !hub.pending.some((row) => row.id === 'p2'))

  // ---- joined machines ----
  const joined = await pageText()
  check('the joined machines show their last handshake', joined.includes('busy-box') && joined.includes('42 s ago') && joined.includes('never'))
  await page.click('button[aria-label="Remove far-mac"]')
  const asked = await b.dialogText()
  check('Remove asks first, by name', asked.includes('Remove this machine?') && asked.includes('far-mac'), asked)
  await b.click('Remove machine')
  await b.until(() => !document.body.innerText.includes('far-mac will be taken'))
  await b.until(() => !document.body.innerText.includes('far-mac'))
  check('Remove takes the machine out of the hub', !hub.peers.some((peer) => peer.name === 'far-mac'))

  // ---- polling: a changed list does not wipe a half-typed code ----
  await b.type(field('Code from busy-box'), '123')
  const before = hub.calls.filter((call) => call === 'GET pending').length
  const triesAtStart = hub.pending[0]?.tries_left
  if (hub.pending[0]) hub.pending[0].tries_left = Number(triesAtStart) - 2
  await b.until((tries: number) => document.body.innerText.includes(`${tries} tries left`), { timeout: POLL_WAIT_MS }, Number(triesAtStart) - 2)
  const after = hub.calls.filter((call) => call === 'GET pending').length
  const kept = await b.run(() => (document.querySelector('input[aria-label="Code from busy-box"]') as HTMLInputElement).value)
  check('the page polls by itself and shows the changed row', after > before)
  check('a half-typed code survives a refresh that changed the list', kept === '123', kept)
  await b.shot('share-page-1440.png', true)

  // ---- a new waiting machine shows up by itself, a closed page stops polling ----
  hub.addPending('p9', 'late-comer')
  await b.until(() => document.body.innerText.includes('late-comer'), { timeout: POLL_WAIT_MS })
  check('a machine that arrives later shows up without a reload', true)
  await b.go('#/machines')
  await wait(500)
  const closedAt = hub.calls.length
  await wait(QUIET_MS)
  check('polling stops when the page is closed', hub.calls.length === closedAt, `${hub.calls.length - closedAt} calls after closing`)

  // ---- the hub does not answer, then is not set up ----
  hub.mode = 'hub_unreachable'
  await b.go('#/share')
  await b.until(() => document.querySelector('[data-testid="share-problem"]') !== null)
  check('the hub not answering has its own text', (await pageText()).includes('does not answer') && await b.run(() => document.querySelector('[data-testid="choose"]') === null))
  hub.mode = 'not_configured'
  await b.click('Check again')
  await b.until(() => document.body.innerText.includes('Share a PC is not set up on this parent.'))
  check('not set up has its own text', true)
  await b.shot('share-problem-1440.png')
  hub.mode = 'ok'
  await b.click('Check again')
  await b.until(() => document.querySelectorAll('[aria-label="System"] button').length === 3)
  check('the page recovers when the hub is back', true)

  // ---- empty states, and a phone ----
  hub.pending.length = 0
  hub.peers.length = 0
  await page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('[data-testid="pending-empty"]') !== null && document.querySelector('[data-testid="peers-empty"]') !== null)
  const empty = await pageText()
  check('empty lists have their own text', empty.includes('Nobody is waiting.') && empty.includes('No machine has joined yet.'))

  hub.addPending('p5', 'Far Mac')
  hub.peers.push({ name: 'busy-box', address: '10.77.0.9', public_key: 'AbCdEfGh', os: 'linux', cpu: 'x86_64', last_handshake_secs_ago: 42 })
  await page.setViewport({ width: 390, height: 844 })
  await page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.body.innerText.includes('Far Mac') && document.body.innerText.includes('busy-box'))
  await b.click('Mac')
  await b.shot('share-page-390.png', true)
  const overflow = await b.run(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  check('no sideways scroll at 390 px', overflow <= 0, `${overflow}px`)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  hub.close()
}
finish()
