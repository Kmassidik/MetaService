// The AI access (MCP) section of Settings, against a stand-in parent that plays /api/mcp/*:
// it appears on Settings; Connect shows the endpoint and a tab per app with its copy line and a placeholder; people are added, edited, disabled and enabled; a token is made
// for a person and shown once (copy works, closing removes it, it is in no storage and no address); the list shows it with its person; Revoke asks first;
// there is no approval anywhere; recent activity names the person; a parent without the feature; hostile text; polling keeps what is typed and stops when the page closes; no script errors.
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
  const pwned = () => b.run(() => (window as unknown as Record<string, unknown>).__pwned === undefined && document.querySelectorAll('main img:not(.oslogo)').length === 0 && document.querySelectorAll('[data-testid="mcp-people"] b').length === 0)
  const copied = () => b.run(() => (window as unknown as Record<string, string>).__copied)
  const cells = (table: string) => b.run((where) => [...document.querySelectorAll(`[data-testid="${where}"] tbody tr`)].map((row) => [...row.querySelectorAll('td')].map((cell) => cell.textContent?.trim()).join(' | ')), table)
  const value = (label: string) => b.run((wanted) => (document.querySelector(`dialog[open] input[aria-label="${wanted}"]`) as HTMLInputElement).value, label)
  const closeDialog = async (button: string) => {
    await b.click(button)
    await b.until(() => document.querySelector('dialog[open]') === null)
  }

  // ---- its own page, reached from the Settings dropdown of the sidebar ----
  await page.goto(`${parent.base}/#/settings`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('aside.side button[aria-controls="settings-menu"]') !== null)
  check('the General settings page no longer holds the AI access section', await b.run(() => document.querySelector('[data-testid="mcp-section"]') === null))
  check('Settings is a dropdown of the sidebar that opens by itself on its own page, with General and AI access (MCP)', await b.run(() =>
    [...document.querySelectorAll('#settings-menu a')].map((x) => x.textContent?.trim()).join('|') === 'General|AI access (MCP)'))
  check('there is no extra sidebar row for it', await b.run(() => ![...document.querySelectorAll('aside.side nav > div > a')].some((x) => /AI access|MCP/i.test(x.textContent ?? ''))))
  await page.click('#settings-menu a[href="#/mcp"]')
  await b.until(() => document.querySelector('[data-testid="mcp-connect"]') !== null)
  check('the sidebar item opens the page and is marked, and so is Settings', await b.run(() =>
    document.querySelector('#settings-menu a[href="#/mcp"]')?.getAttribute('aria-current') === 'page' && document.querySelector('aside.side button[aria-controls="settings-menu"]')?.classList.contains('here') === true &&
    document.querySelector('h1')?.textContent === 'AI access (MCP)'))
  check('the section lists Connect, People, Tokens and Recent activity, and has no approval block', await b.run(() =>
    [...document.querySelectorAll('[data-testid="mcp-section"] > h3')].map((x) => x.textContent?.trim()).join('|') === 'Connect|People|Tokens|Recent activity'))
  check('no approval word anywhere in the section', !(await section()).toLowerCase().includes('approv'))

  // ---- Connect ----
  check('Connect shows the endpoint of the parent', await b.run(() => document.querySelector('[data-testid="mcp-endpoint"]')?.textContent) === ENDPOINT)
  const APPS: Array<[string, string, string]> = [
    ['Claude Code', 'Run this in a terminal.', `claude mcp add --transport http metaservice ${ENDPOINT} --header "Authorization: Bearer <YOUR_TOKEN>"`],
    ['Cursor', 'Put this in ~/.cursor/mcp.json', JSON.stringify({ mcpServers: { metaservice: { url: ENDPOINT, headers: { Authorization: 'Bearer <YOUR_TOKEN>' } } } }, null, 2)],
    ['VS Code', 'Put this in .vscode/mcp.json', JSON.stringify({ servers: { metaservice: { type: 'http', url: ENDPOINT, headers: { Authorization: 'Bearer <YOUR_TOKEN>' } } } }, null, 2)],
    ['OpenCode', 'Put this in opencode.json', JSON.stringify({ mcp: { metaservice: { type: 'remote', url: ENDPOINT, headers: { Authorization: 'Bearer <YOUR_TOKEN>' } } } }, null, 2)],
    ['Gemini CLI', 'Put this in ~/.gemini/settings.json', JSON.stringify({ mcpServers: { metaservice: { httpUrl: ENDPOINT, headers: { Authorization: 'Bearer <YOUR_TOKEN>' } } } }, null, 2)],
    ['Other apps', 'Any app that reads a JSON file of MCP servers takes this.', JSON.stringify({ mcpServers: { metaservice: { type: 'http', url: ENDPOINT, headers: { Authorization: 'Bearer <YOUR_TOKEN>' } } } }, null, 2)],
  ]
  const tabNames = () => b.run(() => [...document.querySelectorAll('[data-testid="mcp-apps"] [role="tab"]')].map((x) => x.textContent?.trim()).join('|'))
  const panel = () => b.run(() => ({
    where: document.querySelector('[data-testid="mcp-app-where"]')?.textContent ?? '',
    code: document.querySelector('[data-testid="mcp-app-panel"] pre')?.textContent ?? '',
    caution: document.querySelector('[data-testid="mcp-app-caution"]')?.textContent ?? '',
    selected: [...document.querySelectorAll('[data-testid="mcp-apps"] [role="tab"]')].filter((x) => x.getAttribute('aria-selected') === 'true').map((x) => x.textContent?.trim()),
  }))
  check('Connect has one tab per app, in order, Claude Code first and selected', (await tabNames()) === APPS.map((app) => app[0]).join('|') && (await panel()).selected.join() === 'Claude Code')
  check('the tab strip is a tablist whose tab owns the panel', await b.run(() => document.querySelector('[data-testid="mcp-apps"] [role="tablist"]') !== null && document.querySelector('[role="tab"][aria-selected="true"]')?.getAttribute('aria-controls') === document.querySelector('[role="tabpanel"]')?.id))
  for (const [label, where, code] of APPS) {
    await b.click(label)
    await b.until((name: string) => document.querySelector('[role="tab"][aria-selected="true"]')?.textContent?.trim() === name, {}, label)
    const shown = await panel()
    check(`${label}: says where it goes and shows the snippet with the endpoint and a placeholder`, shown.where === where && shown.code === code && shown.code.includes(ENDPOINT) && shown.code.includes('Bearer <YOUR_TOKEN>') && !shown.code.includes('msk_'), shown.code)
    const honest = label === 'Claude Code' || label === 'Other apps' ? '' : `Check ${label}'s own docs if the setting names changed.`
    check(`${label}: ${honest === '' ? 'has no docs line' : 'carries the short docs line'}`, shown.caution === honest, shown.caution)
    await page.click(`button[aria-label="Copy ${label} snippet"]`)
    await b.until((text: string) => (window as unknown as Record<string, string>).__copied === text, {}, code)
    check(`${label}: Copy puts the snippet on the clipboard`, true)
  }
  const bridge = await b.run(() => document.querySelector('[data-testid="code-Other-apps-bridge-line"]')?.textContent ?? '')
  check('Other apps adds the bridge line with the endpoint and a placeholder, and says OAuth is not offered yet', bridge === `npx mcp-remote ${ENDPOINT} --header "Authorization: Bearer <YOUR_TOKEN>"` && await b.run(() => document.querySelector('[data-testid="mcp-app-footer"]')?.textContent?.includes('OAuth') === true))
  await page.click('button[aria-label="Copy Other apps bridge line"]')
  await b.until((text: string) => (window as unknown as Record<string, string>).__copied === text, {}, bridge)
  check('Copy puts the bridge line on the clipboard', true)
  await b.shot('mcp-connect-other-1440.png')
  await b.click('Claude Code')
  await page.keyboard.press('ArrowLeft')
  check('ArrowLeft from the first tab wraps to the last, selects it and moves focus', (await panel()).selected.join() === 'Other apps' && await b.run(() => document.activeElement?.textContent?.trim() === 'Other apps'))
  await page.keyboard.press('Home')
  await page.keyboard.press('ArrowRight')
  check('Home then ArrowRight reaches Cursor', (await panel()).selected.join() === 'Cursor' && (await panel()).where === 'Put this in ~/.cursor/mcp.json')
  await page.keyboard.press('End')
  check('End reaches the last tab', (await panel()).selected.join() === 'Other apps')
  check('only the picked tab is in the tab order', await b.run(() => [...document.querySelectorAll('[data-testid="mcp-apps"] [role="tab"]')].filter((x) => x.getAttribute('tabindex') === '0').length === 1))
  check('nothing about the tab is in storage or the address', await b.run(() => localStorage.length === 0 && sessionStorage.length === 0 && !location.href.includes('cursor')))
  await b.click('Claude Code')
  await b.shot('mcp-connect-claude-1440.png')

  await page.setViewport({ width: 390, height: 844 })
  await b.until(() => document.documentElement.clientWidth <= 390)
  check('at 390 px the page does not scroll sideways, on every tab', await (async () => {
    for (const [label] of APPS) {
      await b.click(label)
      if (await b.run(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)) return false
    }
    return true
  })())
  check('at 390 px the strip scrolls inside itself and the active snippet stays inside the screen', await b.run(() => {
    const strip = document.querySelector('[data-testid="mcp-apps"] [role="tablist"]') as HTMLElement
    const box = document.querySelector('[data-testid="mcp-app-panel"] pre')!.getBoundingClientRect()
    return strip.scrollWidth > strip.clientWidth && strip.getBoundingClientRect().right <= 390 && box.right <= 390
  }))
  await b.click('Cursor')
  await b.shot('mcp-connect-cursor-390.png')
  await page.setViewport({ width: 1440, height: 900 })
  await b.until(() => document.documentElement.clientWidth > 1000)
  const tools = await b.run(() => [...document.querySelectorAll('[data-testid="mcp-tools"] tbody tr')].map((row) => [...row.querySelectorAll('td')].slice(0, 2).map((cell) => cell.textContent?.trim()).join(':')))
  check('the tools are listed with their scope', tools.length === 9 && tools.includes('create_vm:create') && tools.includes('delete_vm:destroy') && tools.includes('list_machines:read'), tools.join(','))

  // ---- people ----
  const people = await cells('mcp-people')
  check('the people are listed with scopes, limits, tokens, VMs alive and last used', people[0] === 'Ayu | readcreate | 3 VMs · 8 vCPU · 16 GB RAM · 200 GB disk · 10 creates/day | 1 token | 2 | 5 min ago | Edit Disable', people[0])
  check('a person without tokens says so', people[1]?.includes('no tokens') === true && people[1]?.includes('never') === true && people[1]?.includes('GPU up to 8 GB') === false, people[1])
  check('hostile names are shown as text', people[2]?.startsWith('<b>Eve</b><img') === true && await pwned())
  await b.shot('mcp-settings-1440.png', true)

  await b.click('Add person')
  await b.until(() => document.querySelector('dialog[open]') !== null)
  check('Add person opens with the spec defaults', await b.run(() => {
    const field = (label: string) => (document.querySelector(`dialog[open] input[aria-label="${label}"]`) as HTMLInputElement)
    return field('VMs alive at once').value === '3' && field('vCPU in total').value === '8' && field('RAM in total in GB').value === '16' && field('Disk in total in GB').value === '200' && field('Creates per day').value === '10'
      && field('Scope read').checked && field('Scope create').checked && !field('Scope destroy').checked && !field('Scope gpu').checked && !field('Scope shared').checked
  }))
  await b.shot('mcp-person-1440.png')
  await b.click('Add person')
  await b.until(() => document.body.innerText.includes('The name may have 1 to 40'))
  check('a person without a valid name is not sent', parent.saved.length === 0)
  await b.type('dialog[open] input[aria-label="Person name"]', 'Ayu')
  await b.click('Add person')
  await b.until(() => document.body.innerText.includes('There is already a person with that name.'))
  check('a name already used shows the parent plain reason and keeps the window', parent.saved.length === 1 && await b.run(() => document.querySelector('dialog[open]') !== null))
  await b.type('dialog[open] input[aria-label="Person name"]', 'Cem')
  await page.click('dialog[open] input[aria-label="Scope gpu"]')
  await b.until(() => document.querySelector('dialog[open] input[aria-label="GPU memory in GB"]') !== null)
  await b.click('Add person')
  await b.until(() => document.querySelector('dialog[open]') === null)
  check('the new person is sent with scopes and quotas in MB, and is listed', JSON.stringify(parent.saved.at(-1)) === JSON.stringify({ name: 'Cem', scopes: ['read', 'create', 'gpu'], quotas: { max_vms: 3, max_vcpu: 8, max_ram_mb: 16384, max_disk_gb: 200, creates_per_day: 10, gpu_memory_gb: 8 } }) && (await cells('mcp-people')).some((row) => row.startsWith('Cem | readcreategpu')))

  await page.click('button[aria-label="Edit Budi"]')
  await b.until(() => document.querySelector('dialog[open]') !== null)
  check('Edit person shows the person own values and no name field', (await value('VMs alive at once')) === '3' && await b.run(() => document.querySelector('dialog[open] input[aria-label="Person name"]') === null && (document.querySelector('dialog[open] input[aria-label="Scope gpu"]') as HTMLInputElement).checked) && (await b.dialogText()).toLowerCase().includes('edit budi'))
  await b.type('dialog[open] input[aria-label="VMs alive at once"]', '5')
  await page.click('dialog[open] input[aria-label="Scope destroy"]')
  await b.click('Save')
  await b.until(() => document.querySelector('dialog[open]') === null)
  check('Edit sends scopes and quotas only, and the list shows them', JSON.stringify(parent.saved.at(-1)) === JSON.stringify({ scopes: ['read', 'create', 'gpu'], quotas: { max_vms: 5, max_vcpu: 8, max_ram_mb: 16384, max_disk_gb: 200, creates_per_day: 10, gpu_memory_gb: 8 } }) && (await cells('mcp-people')).some((row) => row.startsWith('Budi | readcreategpu | 5 VMs')))

  await page.click('button[aria-label="Disable Cem"]')
  const disabling = await b.dialogText()
  check('Disable asks first, by name, and says what stays', disabling.toLowerCase().includes('disable this person?') && disabling.includes('Cem') && disabling.includes('keep running'), disabling)
  await b.click('Cancel')
  await b.until(() => document.querySelector('dialog[open]') === null)
  check('Cancel disables nothing', !parent.people.some((row) => row.disabled_at))
  await page.click('button[aria-label="Disable Cem"]')
  await b.click('Disable person')
  await b.until(() => document.querySelector('[data-testid="mcp-people"] .tag.off') !== null)
  check('Disable marks the person disabled and offers Enable', parent.people.some((row) => row.name === 'Cem' && row.disabled_at) && (await cells('mcp-people')).some((row) => row.includes('Cem') && row.includes('disabled') && row.endsWith('Enable')))

  // ---- tokens ----
  check('the list shows the existing token with its person, prefix, scopes, last used and expiry', await b.run(() => {
    const row = document.querySelector('[data-testid="mcp-tokens"] tbody tr')?.textContent ?? ''
    return row.includes('my laptop') && row.includes('Ayu') && row.includes('msk_') && row.includes('readcreate') && row.includes('5 min ago') && row.includes('in 89 days') && !row.includes('GB RAM')
  }))
  await b.click('Create token')
  await b.until(() => document.querySelector('dialog[open]') !== null)
  const persons = await b.run(() => [...document.querySelectorAll('dialog[open] select option')].map((x) => x.textContent))
  check('Create token asks which person, and offers only people who are not disabled', persons.join('|') === 'Ayu|Budi|<b>Eve</b><img src=x onerror="window.__pwned=1">', persons.join('|'))
  const asked = (await b.dialogText()).toLowerCase()
  check('Create token has no limits fields (they are the person\'s) and no approval wording', !asked.includes('vms alive') && !asked.includes('creates per day') && !asked.includes('approv') && asked.includes('never more than the person may'))
  await b.shot('mcp-create-1440.png')
  await b.click('Create token')
  await b.until(() => document.body.innerText.includes('The name may have 1 to 40'))
  check('a token without a name is not sent', parent.made.length === 0)
  await page.select('dialog[open] select', 'p2')
  check('choosing a person offers that person scopes', await b.run(() => ['read', 'create', 'gpu'].every((scope) => (document.querySelector(`dialog[open] input[aria-label="Scope ${scope}"]`) as HTMLInputElement | null)?.checked === true) && document.querySelector('dialog[open] input[aria-label="Scope destroy"]') === null))
  await b.type('dialog[open] input[aria-label="Token name"]', 'ci box')
  await page.click('dialog[open] input[aria-label="Scope gpu"]')
  await b.type('dialog[open] input[aria-label="Days until it expires"]', '30')
  await b.click('Create token')
  await b.until(() => document.querySelector('[data-testid="token-warning"]') !== null)
  const made = JSON.stringify(parent.made.at(-1))
  check('the request carries the person, the name, fewer scopes and the expiry, and no quotas', made === JSON.stringify({ name: 'ci box', person_id: 'p2', scopes: ['read', 'create'], expires_in_days: 30 }), made)
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
  const tokens = await cells('mcp-tokens')
  check('the new token is in the list with its person, and Budi now has 1 token', tokens.some((row) => row.startsWith('ci box | Budi | msk_')) && (await cells('mcp-people')).some((row) => row.startsWith('Budi') && row.includes('1 token')), tokens.join(' ; '))
  check('reopening Create token starts clean', await (async () => {
    await b.click('Create token')
    await b.until(() => document.querySelector('dialog[open]') !== null)
    const clean = await b.run(() => (document.querySelector('dialog[open] input[aria-label="Token name"]') as HTMLInputElement).value === '' && document.querySelector('[data-testid="code-new-token"]') === null)
    await closeDialog('Cancel')
    return clean
  })())

  // ---- revoke ----
  await page.click('button[aria-label="Revoke ci box"]')
  const revoking = await b.dialogText()
  check('Revoke asks first, by name', revoking.toLowerCase().includes('revoke this token?') && revoking.includes('ci box'), revoking)
  await closeDialog('Cancel')
  check('Cancel revokes nothing', !parent.tokens.some((row) => row.revoked_at))
  await page.click('button[aria-label="Revoke ci box"]')
  await b.click('Revoke token')
  await b.until(() => document.querySelector('button[aria-label="Revoke ci box"]') === null)
  check('Revoke marks the token revoked on the parent and in the list', parent.tokens.some((row) => row.name === 'ci box' && row.revoked_at) && (await section()).includes('revoked'))

  // ---- Enable, and no one to make a token for ----
  await b.run(() => document.querySelector<HTMLButtonElement>('[data-testid="mcp-people"] tbody tr.gone .btn.green')?.click())
  await b.until(() => document.querySelector('[data-testid="mcp-people"] .tag.off') === null)
  check('Enable switches the person back on', parent.people.every((row) => !row.disabled_at))

  // ---- recent activity ----
  const rows = await cells('mcp-activity')
  check('recent activity shows time, person, tool, target and result', rows[0] === '2 min ago | Ayu | list_vms | — | ok' && rows[1] === '9 min ago | Ayu | create_vm | rtx-pc/box | ok', rows.join(' ; '))
  check('every write carried the CSRF header', parent.withoutCsrf.length === 0, parent.withoutCsrf.join(','))

  // ---- polling keeps what is typed, a new call shows up by itself ----
  await b.click('Add person')
  await b.type('dialog[open] input[aria-label="Person name"]', 'half typed')
  const before = parent.calls.filter((call) => call === 'GET people').length
  parent.activity.unshift({ at: new Date().toISOString(), actor: 'mcp:Budi', action: 'mcp.delete_vm', target: 'mini/web', status: 'refused' })
  await b.until(() => document.body.innerText.includes('mini/web'), { timeout: POLL_WAIT_MS })
  check('the section polls by itself and shows the new call without a reload', parent.calls.filter((call) => call === 'GET people').length > before)
  check('a refresh that changed the list does not wipe what is typed', (await value('Person name')) === 'half typed')
  await closeDialog('Cancel')

  // ---- a closed page stops polling ----
  await b.go('#/machines')
  await wait(500)
  const closedAt = parent.calls.length
  await wait(QUIET_MS)
  check('polling stops when the Settings page is closed', parent.calls.length === closedAt, `${parent.calls.length - closedAt} calls after closing`)

  // ---- empty lists, errors, and a parent without the feature ----
  parent.tokens.length = 0
  parent.people.length = 0
  parent.activity.length = 0
  await b.go('#/mcp')
  await b.until(() => document.querySelector('[data-testid="mcp-tokens-empty"]') !== null)
  const empty = await section()
  check('empty lists have their own text', empty.includes('No one yet.') && empty.includes('No tokens yet.') && empty.includes('No calls yet.'))
  await b.click('Create token')
  await b.until(() => document.querySelector('[data-testid="no-person"]') !== null)
  check('Create token with no person says to add one first', (await b.dialogText()).includes('Add a person first.'))
  await closeDialog('Close')
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
  await b.go('#/settings')
  await b.until(() => document.querySelectorAll('main section h2').length === 2)
  check('the General settings page still works then', await b.run(() => [...document.querySelectorAll('main section h2')].map((x) => x.textContent).join('|') === 'AI provider|Chat bundle'))
  await b.go('#/mcp')
  await b.until(() => document.querySelector('[data-testid="mcp-unavailable"]') !== null)
  await b.shot('mcp-unavailable-1440.png')
  parent.mode = 'ok'

  // ---- a phone ----
  const longName = 'phone-size person with a rather long name'
  parent.people.push({ id: 'p9', name: longName, scopes: ['read', 'create', 'destroy', 'gpu', 'shared'], quotas: { max_vms: 3, max_vcpu: 8, max_ram_mb: 16384, max_disk_gb: 200, creates_per_day: 10, gpu_memory_gb: 8 }, tokens: 1, vms_alive: 2, last_used_at: null, disabled_at: null })
  parent.tokens.push({ id: 't9', name: 'phone-size token with a rather long name', prefix: 'abcd1234', scopes: ['read', 'create', 'destroy', 'gpu', 'shared'], person_id: 'p9', person_name: longName, created_at: new Date().toISOString(), expires_at: new Date(Date.now() + 5 * 86_400_000).toISOString(), last_used_at: null, revoked_at: null })
  parent.activity.push({ at: new Date().toISOString(), actor: `mcp:${longName}`, action: 'mcp.create_vm', target: 'a-machine-with-a-long-name/a-vm-with-a-long-name', status: 'ok' })
  await page.setViewport({ width: 390, height: 844 })
  await page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('[data-testid="mcp-activity"]') !== null)
  await b.shot('mcp-settings-390.png', true)
  await b.click('Add person')
  await b.until(() => document.querySelector('dialog[open]') !== null)
  await page.click('dialog[open] input[aria-label="Scope gpu"]')
  await b.shot('mcp-person-390.png')
  await closeDialog('Cancel')
  await b.click('Create token')
  await b.until(() => document.querySelector('dialog[open]') !== null)
  await b.shot('mcp-create-390.png')
  await closeDialog('Cancel')
  const overflow = await b.run(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  check('no sideways scroll at 390 px', overflow <= 0, `${overflow}px`)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  parent.close()
}
finish()
