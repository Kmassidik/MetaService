// The AI access (MCP) section of Settings, against a stand-in parent that plays /api/mcp/*:
// it appears on Settings; Connect shows the endpoint and the copy lines with a placeholder; a token is made and shown once (copy works, closing
// removes it, it is in no storage and no address); the list shows it; Revoke asks first; approvals are approved and denied in plain words;
// recent activity; a parent without the feature; hostile text; polling keeps what is typed and stops when the page closes; no script errors.
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { wait } from './support/net.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { ENDPOINT, startParent } from './mcp/parent.ts'

const POLL_WAIT_MS = 12_000
const QUIET_MS = 11_000
const parent = await startParent()
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
  const section = () => b.run(() => document.querySelector<HTMLElement>('[data-testid="mcp-section"]')?.innerText ?? '')
  const copied = () => b.run(() => (window as unknown as Record<string, string>).__copied)
  const asks = () => b.run(() => [...document.querySelectorAll('[data-testid="ask-text"]')].map((x) => x.textContent?.trim()))
  const pressIn = (scope: string, label: string) => b.run((where, wanted) => {
    const button = [...document.querySelectorAll<HTMLButtonElement>(`${where} button`)].find((x) => x.textContent?.trim() === wanted)
    if (!button) throw new Error(`no button ${wanted}`)
    button.click()
  }, scope, label)

  // ---- the section is on Settings, with the others ----
  await page.goto(`${parent.base}/#/settings`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('[data-testid="mcp-connect"]') !== null)
  check('Settings has the AI access (MCP) section, after the other sections', await b.run(() =>
    [...document.querySelectorAll('main section h2')].map((x) => x.textContent).join('|') === 'AI provider|Chat bundle|AI access (MCP)'))
  check('there is no sidebar row of its own', await b.run(() => ![...document.querySelectorAll('aside.side a')].some((x) => /AI access|MCP/i.test(x.textContent ?? ''))))
  check('the section lists Connect, Tokens, Waiting for approval and Recent activity', await b.run(() =>
    [...document.querySelectorAll('[data-testid="mcp-section"] > h3')].map((x) => x.textContent?.trim().replace(/ \(\d+\)$/, '')).join('|') === 'Connect|Tokens|Waiting for approval|Recent activity'))

  // ---- Connect ----
  check('Connect shows the endpoint of the parent', await b.run(() => document.querySelector('[data-testid="mcp-endpoint"]')?.textContent) === ENDPOINT)
  const claude = await b.run(() => document.querySelector('[data-testid="code-Claude-Code-line"]')?.textContent ?? '')
  check('the Claude Code line has the endpoint and a placeholder token', claude === `claude mcp add --transport http metaservice ${ENDPOINT} --header "Authorization: Bearer <YOUR_TOKEN>"`, claude)
  const json = await b.run(() => document.querySelector('[data-testid="code-JSON-for-another-client"]')?.textContent ?? '')
  check('the JSON for another client has the endpoint and a placeholder token', json.includes(ENDPOINT) && json.includes('Bearer <YOUR_TOKEN>') && !json.includes('msk_'))
  await page.click('button[aria-label="Copy Claude Code line"]')
  await b.until(() => (window as unknown as Record<string, string>).__copied !== undefined)
  check('Copy puts the Claude Code line on the clipboard', (await copied()) === claude)
  await page.click('button[aria-label="Copy JSON for another client"]')
  await b.until((text: string) => (window as unknown as Record<string, string>).__copied === text, {}, json)
  check('Copy puts the JSON on the clipboard', true)
  const tools = await b.run(() => [...document.querySelectorAll('[data-testid="mcp-tools"] tbody tr')].map((row) => [...row.querySelectorAll('td')].slice(0, 2).map((cell) => cell.textContent?.trim()).join(':')))
  check('the tools are listed with their scope', tools.length === 9 && tools.includes('create_vm:create') && tools.includes('delete_vm:destroy') && tools.includes('list_machines:read'), tools.join(','))

  // ---- tokens ----
  check('the list shows the existing token with prefix, scopes, limits, last used and expiry', await b.run(() => {
    const row = document.querySelector('[data-testid="mcp-tokens"] tbody tr')?.textContent ?? ''
    return row.includes('my laptop') && row.includes('msk_') && row.includes('readcreate') && row.includes('3 VMs · 8 vCPU · 16 GB RAM · 200 GB disk · 10 creates/day') && row.includes('5 min ago') && row.includes('in 89 days')
  }))
  await b.shot('mcp-settings-1440.png', true)
  await b.click('Create token')
  await b.until(() => document.querySelector('dialog[open]') !== null)
  check('Create token opens a window with the spec defaults', await b.run(() => {
    const value = (label: string) => (document.querySelector(`dialog[open] input[aria-label="${label}"]`) as HTMLInputElement).value
    const box = (label: string) => (document.querySelector(`dialog[open] input[aria-label="${label}"]`) as HTMLInputElement).checked
    return value('VMs alive at once') === '3' && value('vCPU in total') === '8' && value('RAM in total in GB') === '16' && value('Disk in total in GB') === '200' && value('Creates per day') === '10' && value('Days until it expires') === '90'
      && box('Scope read') && box('Scope create') && !box('Scope destroy') && !box('Scope gpu') && !box('Scope shared') && !box('Auto-approve')
  }))
  const explained = await b.dialogText()
  check('every scope has a plain explanation', ['See machines', 'Create, start and stop', 'Delete VMs', 'GPU memory limit', 'Share a PC'].every((words) => explained.includes(words)))
  await b.shot('mcp-create-1440.png')
  await b.click('Create token')
  await b.until(() => document.body.innerText.includes('Give the token a name'))
  check('a token without a name is not sent', parent.made.length === 0)
  await b.type('dialog[open] input[aria-label="Token name"]', 'ci <b>box</b>')
  await page.click('dialog[open] input[aria-label="Scope gpu"]')
  await b.until(() => document.querySelector('dialog[open] input[aria-label="GPU memory in GB"]') !== null)
  await page.click('dialog[open] input[aria-label="Auto-approve"]')
  await b.until(() => document.querySelector('[data-testid="auto-warning"]') !== null)
  check('auto-approve shows a warning', (await b.dialogText()).includes('without asking you'))
  await page.click('dialog[open] input[aria-label="Auto-approve"]')
  await b.type('dialog[open] input[aria-label="Days until it expires"]', '30')
  await b.click('Create token')
  await b.until(() => document.querySelector('[data-testid="token-warning"]') !== null)
  const made = JSON.stringify(parent.made.at(-1))
  check('the request carries the name, scopes, quotas in MB, expiry and auto-approve off', made === JSON.stringify({ name: 'ci <b>box</b>', scopes: ['read', 'create', 'gpu'], quotas: { max_vms: 3, max_vcpu: 8, max_ram_mb: 16384, max_disk_gb: 200, creates_per_day: 10, gpu_memory_gb: 8 }, expires_in_days: 30, auto_approve: false }), made)
  const shown = await b.run(() => document.querySelector('[data-testid="code-new-token"]')?.textContent ?? '')
  check('the new token is shown once, in full', shown === parent.lastSecret && shown.startsWith('msk_'), shown)
  check('the window warns that it cannot be shown again', (await b.dialogText()).includes('cannot be shown again'))
  await b.shot('mcp-token-made-1440.png')
  await page.click('dialog[open] button[aria-label="Copy new token"]')
  await b.until(() => (window as unknown as Record<string, string>).__copied?.startsWith('msk_'))
  check('Copy puts the token on the clipboard', (await copied()) === parent.lastSecret)
  await b.click('Done')
  await b.until(() => document.querySelector('dialog[open]') === null)
  const secret = parent.lastSecret
  check('closing the window removes the token from the page', await b.run((text: string) => !document.documentElement.outerHTML.includes(text), secret))
  check('the token is in no storage and not in the address', await b.run((text: string) => {
    const stored = JSON.stringify({ ...localStorage }) + JSON.stringify({ ...sessionStorage }) + document.cookie
    return !stored.includes(text) && !location.href.includes(text)
  }, secret))
  check('the new token is in the list, with its prefix only and as text', await b.run(() => {
    const names = [...document.querySelectorAll('[data-testid="token-name"]')].map((x) => x.textContent ?? '')
    return names.some((name) => name.startsWith('ci <b>box</b>')) && document.querySelectorAll('[data-testid="mcp-tokens"] b').length === 0
  }))
  check('reopening Create token starts clean', await (async () => {
    await b.click('Create token')
    await b.until(() => document.querySelector('dialog[open]') !== null)
    const clean = await b.run(() => (document.querySelector('dialog[open] input[aria-label="Token name"]') as HTMLInputElement).value === '' && document.querySelector('[data-testid="code-new-token"]') === null)
    await b.click('Cancel')
    await b.until(() => document.querySelector('dialog[open]') === null)
    return clean
  })())

  // ---- revoke ----
  await page.click('button[aria-label="Revoke ci <b>box</b>"]')
  const asked = await b.dialogText()
  check('Revoke asks first, by name', asked.toLowerCase().includes('revoke this token?') && asked.includes('ci <b>box</b>'), asked)
  await b.click('Cancel')
  await b.until(() => document.querySelector('dialog[open]') === null)
  check('Cancel revokes nothing', !parent.tokens.some((row) => row.revoked_at))
  await page.click('button[aria-label="Revoke ci <b>box</b>"]')
  await b.click('Revoke token')
  await b.until(() => document.querySelector('button[aria-label="Revoke ci <b>box</b>"]') === null)
  check('Revoke marks the token revoked on the parent and in the list', parent.tokens.some((row) => row.name === 'ci <b>box</b>' && row.revoked_at) && (await section()).includes('revoked'))

  // ---- approvals ----
  const waiting = await asks()
  check('each request is told in plain words', waiting[0] === 'my laptop wants to create a medium VM on rtx-pc with a 4 GB GPU limit', waiting[0])
  check('a delete request names the VM and the machine', waiting[1]?.endsWith('wants to delete VM <b>victim</b> on rtx-pc') === true, waiting[1])
  const hostile = await b.run(() => ({ images: document.querySelectorAll('main img').length, bold: document.querySelectorAll('[data-testid="ask-text"] b').length, pwned: (window as unknown as Record<string, unknown>).__pwned }))
  check('hostile names are shown as text and run nothing', hostile.images === 0 && hostile.bold === 0 && hostile.pwned === undefined && (await section()).includes('<img src=x'), JSON.stringify(hostile))
  await b.shot('mcp-approvals-1440.png')
  await pressIn('[data-testid="mcp-pending"] li:first-child', 'Approve')
  await b.until(() => document.querySelectorAll('[data-testid="ask-text"]').length === 1)
  check('Approve sends the approval and moves the request to decided', parent.calls.includes('POST approvals') && parent.recent.some((row) => row.id === 'r1' && row.state === 'done') && (await section()).includes('approved, done by kurnia'))
  await pressIn('[data-testid="mcp-pending"] li:first-child', 'Deny')
  await b.until(() => document.querySelector('[data-testid="mcp-approvals-empty"]') !== null)
  check('Deny sends the denial and the waiting list is empty', parent.recent.some((row) => row.id === 'r2' && row.state === 'denied') && (await section()).includes('Nothing is waiting.'))
  check('the decided requests are listed below', (await section()).includes('denied by kurnia') && (await section()).includes('wanted to create a medium VM'))

  // ---- recent activity ----
  const rows = await b.run(() => [...document.querySelectorAll('[data-testid="mcp-activity"] tbody tr')].map((row) => [...row.querySelectorAll('td')].map((cell) => cell.textContent?.trim()).join(' | ')))
  check('recent activity shows time, token, tool, target and result', rows[0] === '2 min ago | my laptop | list_vms | — | ok' && rows[1] === '9 min ago | my laptop | create_vm | rtx-pc/box | ok', rows.join(' ; '))
  check('every write carried the CSRF header', parent.withoutCsrf.length === 0, parent.withoutCsrf.join(','))

  // ---- polling keeps what is typed, a new request shows up by itself ----
  await b.click('Create token')
  await b.type('dialog[open] input[aria-label="Token name"]', 'half typed')
  const before = parent.calls.filter((call) => call === 'GET approvals').length
  parent.addPending('r3', 'night job', 'stop', { machine_name: 'mini', vm_name: 'web' })
  await b.until(() => document.body.innerText.includes('night job wants to stop VM web on mini'), { timeout: POLL_WAIT_MS })
  check('the section polls by itself and shows the new request without a reload', parent.calls.filter((call) => call === 'GET approvals').length > before)
  check('a refresh that changed the list does not wipe what is typed', await b.run(() => (document.querySelector('dialog[open] input[aria-label="Token name"]') as HTMLInputElement).value) === 'half typed')
  await b.click('Cancel')
  await b.until(() => document.querySelector('dialog[open]') === null)

  // ---- a closed page stops polling ----
  await b.go('#/machines')
  await wait(500)
  const closedAt = parent.calls.length
  await wait(QUIET_MS)
  check('polling stops when the Settings page is closed', parent.calls.length === closedAt, `${parent.calls.length - closedAt} calls after closing`)

  // ---- empty lists, errors, and a parent without the feature ----
  parent.tokens.length = 0
  parent.pending.length = 0
  parent.recent.length = 0
  parent.activity.length = 0
  await b.go('#/settings')
  await b.until(() => document.querySelector('[data-testid="mcp-tokens-empty"]') !== null)
  const empty = await section()
  check('empty lists have their own text', empty.includes('No tokens yet.') && empty.includes('Nothing is waiting.') && empty.includes('No calls yet.'))
  parent.mode = 'broken'
  await page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('[data-testid="mcp-failure"]') !== null)
  check('an error shows its plain reason and a way to try again', (await section()).includes('The AI access store could not be read.') && (await section()).includes('Try again'))
  parent.mode = 'ok'
  await b.click('Try again')
  await b.until(() => document.querySelector('[data-testid="mcp-connect"]') !== null)
  check('the section recovers when the parent is back', true)
  parent.mode = 'old'
  await page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('[data-testid="mcp-unavailable"]') !== null)
  check('a parent without AI access says so', (await section()).includes('AI access is not available on this parent.') && await b.run(() => document.querySelector('[data-testid="mcp-connect"]') === null))
  check('the rest of Settings still works then', await b.run(() => document.querySelectorAll('main section h2').length === 3))
  await b.shot('mcp-unavailable-1440.png')
  parent.mode = 'ok'

  // ---- a phone ----
  parent.tokens.push({ id: 't9', name: 'phone-size token with a rather long name', prefix: 'abcd1234', scopes: ['read', 'create', 'destroy', 'gpu', 'shared'], quotas: { max_vms: 3, max_vcpu: 8, max_ram_mb: 16384, max_disk_gb: 200, creates_per_day: 10, gpu_memory_gb: 8 }, auto_approve: true, created_at: new Date().toISOString(), expires_at: new Date(Date.now() + 5 * 86_400_000).toISOString(), last_used_at: null, revoked_at: null })
  parent.addPending('r4', 'phone-size token with a rather long name', 'create', { size: 'custom', vcpu: 12, ram_mb: 32768, disk_gb: 300 })
  parent.activity.push({ at: new Date().toISOString(), actor: 'mcp:phone-size token with a rather long name', action: 'mcp.create_vm', target: 'a-machine-with-a-long-name/a-vm-with-a-long-name', status: 'needs_approval' })
  await page.setViewport({ width: 390, height: 844 })
  await page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('[data-testid="mcp-activity"]') !== null)
  check('a custom request lists its numbers', (await section()).includes('create a custom VM (12 vCPU, 32 GB RAM, 300 GB disk) on the least loaded machine that fits'))
  await b.shot('mcp-settings-390.png', true)
  await b.click('Create token')
  await b.until(() => document.querySelector('dialog[open]') !== null)
  await page.click('dialog[open] input[aria-label="Scope gpu"]')
  await b.shot('mcp-create-390.png')
  await b.click('Cancel')
  const overflow = await b.run(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  check('no sideways scroll at 390 px', overflow <= 0, `${overflow}px`)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  parent.close()
}
finish()
