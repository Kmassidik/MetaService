// Who made each VM, on the three Compute views of a machine (Building, Table, Cards), on the All VMs table and on the VM page, against the stand-in parent.
// Five kinds of VM sit in one machine: made by an AI client, made in the panel, made before creators were tracked (recorded afterwards), unknown origin, and a record that was altered.
// Needs: a built panel (`bun run build`), Google Chrome (or CHROME_PATH). Run: bun e2e/vm-origin.e2e.ts
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { startStandIn } from './actions/standin.ts'

const VMS_TAB = '#/machines/details?id=studio&tab=vms'
const HOSTILE = 'Eve <img src=x onerror="window.__pwned=1"> (MCP)'
const SEAL_OK = '7f3a9c21'
const standin = await startStandIn()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })

const entry = (id: string, createdBy?: Record<string, unknown>) => ({
  id, name: id, kind: 'vm', state: 'running', cpu: 2, ram_mb: 2048, disk_gb: 20, gpu_mode: 'none', address: `10.0.0.${id.replace(/\D/g, '')}`, bundle_version: null,
  ...(createdBy ? { created_by: createdBy } : {}),
})
const origin = (more: Record<string, unknown>) => ({
  kind: 'mcp', actor: 'mcp:Ayu', person_name: 'Ayu', token_prefix: 'AbCd1234', client: 'claude-code 2.1.0', source_ip: '203.0.113.7',
  created_at: '2026-10-31T12:00:00Z', backfilled: false, deleted_at: null, deleted_by: null, fingerprint: SEAL_OK, intact: true, ...more,
})
/** What every view must say for each VM. */
const WORDS: Record<string, string> = {
  vm1: 'Ayu (MCP) · 7f3a9c21',
  vm2: 'panel (kurnia) · 5b02d1ee',
  vm3: 'admin (recorded afterwards) · 0a1b2c3d',
  vm6: 'unknown origin',
  vm7: `${HOSTILE} · 99aa00bb`,
}

try {
  const page = await browser.newPage()
  await page.setViewport({ width: 1440, height: 1000 })
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  const b = browse(page)

  standin.putVm('studio', entry('vm1', { kind: 'mcp', label: 'Ayu (MCP)', fingerprint: '7f3a9c21' }))
  standin.putVm('studio', entry('vm2', { kind: 'panel', label: 'panel (kurnia)', fingerprint: '5b02d1ee' }))
  standin.putVm('studio', entry('vm3', { kind: 'panel', label: 'admin (recorded afterwards)', fingerprint: '0a1b2c3d' }))
  standin.putVm('studio', entry('vm6'))
  standin.putVm('studio', entry('vm7', { kind: 'mcp', label: HOSTILE, fingerprint: '99aa00bb' }))
  standin.origins['studio/vm1'] = origin({})
  standin.origins['studio/vm2'] = origin({ kind: 'panel', actor: 'kurnia', person_name: null, token_prefix: null, client: null, source_ip: '198.51.100.4', created_at: '2026-10-30T08:15:00Z', fingerprint: '5b02d1ee' })
  standin.origins['studio/vm3'] = origin({ kind: 'panel', actor: 'admin', person_name: null, token_prefix: null, client: null, source_ip: null, created_at: null, backfilled: true, fingerprint: '0a1b2c3d' })
  standin.origins['studio/vm7'] = origin({ person_name: HOSTILE.replace(' (MCP)', ''), fingerprint: '99aa00bb', intact: false })

  const texts = (selector: string) => b.run((where) => [...document.querySelectorAll(where)].map((node) => node.textContent?.trim() ?? ''), selector)
  const pwned = () => b.run(() => (window as unknown as Record<string, unknown>).__pwned === undefined && document.querySelectorAll('main img:not(.bv-logo):not(.oslogo)').length === 0)
  const overflow = () => b.run(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  const sameWords = (found: string[]) => Object.values(WORDS).every((words) => found.includes(words)) && found.length === Object.keys(WORDS).length

  await page.goto(`${standin.base}/${VMS_TAB}`, { waitUntil: 'networkidle0' })
  await page.waitForSelector('[data-testid="bv-created-by"]')

  // ---- Building ----
  const building = (await texts('[data-testid="bv-created-by"]')).map((line) => line.replace(/^Created by /, ''))
  check('Building: every VM in the list says who made it, with the fingerprint', sameWords(building), building.join(' | '))
  check('Building: an apartment names its creator in its label too', await b.run(() => document.querySelector('.bv-apt')?.getAttribute('aria-label')?.includes('created by') === true))
  check('Building: hostile text is only text', await pwned())
  await b.shot('origin-building-1440.png', true)

  // ---- Table ----
  await b.click('Table')
  await page.waitForSelector('table.restable')
  const heads = await texts('table.restable thead th')
  check('Table: has a Created by column', heads.includes('Created by'), heads.join(','))
  const column = heads.indexOf('Created by')
  const tableWords = await b.run((index) => [...document.querySelectorAll('table.restable tbody tr')].map((row) => row.querySelectorAll('td')[index]?.textContent?.trim() ?? ''), column)
  check('Table: every VM says who made it, with the fingerprint', sameWords(tableWords), tableWords.join(' | '))
  const lefts = await b.run((index) => [...document.querySelectorAll('table.restable tbody tr')].map((row) => Math.round(row.querySelectorAll('td')[index]?.getBoundingClientRect().left ?? -1)), column)
  check('Table: the column is aligned', new Set(lefts).size === 1 && lefts[0]! > 0, lefts.join(','))
  check('Table: hostile text is only text', await pwned())
  await b.shot('origin-table-1440.png', true)

  // ---- Cards ----
  await b.click('Cards')
  await page.waitForSelector('.card')
  const cardWords = await texts('.card [data-testid="created-by"]')
  check('Cards: every VM says who made it, with the fingerprint', sameWords(cardWords), cardWords.join(' | '))
  const cardLefts = await b.run(() => [...document.querySelectorAll('.card div.by')].map((node) => Math.round(node.getBoundingClientRect().left) - Math.round(node.closest('.card')?.getBoundingClientRect().left ?? 0)))
  check('Cards: the line sits at the same place in every card', new Set(cardLefts).size === 1, cardLefts.join(','))
  check('Cards: hostile text is only text', await pwned())
  await b.shot('origin-cards-1440.png', true)

  // ---- the three views agree ----
  check('the three views and the All VMs table say the same for every VM', sameWords(building) && sameWords(tableWords) && sameWords(cardWords))
  await b.go('#/vms')
  await page.waitForSelector('table[aria-label="VMs"]')
  const allHeads = await texts('table[aria-label="VMs"] thead th')
  const allWords = await b.run((index) => [...document.querySelectorAll('table[aria-label="VMs"] tbody tr')].map((row) => row.querySelectorAll('td')[index]?.textContent?.trim() ?? ''), allHeads.indexOf('Created by'))
  check('All VMs: the table has the Created by column with the same words (the VMs of the other machine say unknown origin)', Object.values(WORDS).every((words) => allWords.includes(words)) && allWords.filter((words) => words === 'unknown origin').length >= 2, allWords.join(' | '))

  // ---- the VM page ----
  await b.go('#/machines/details?id=studio&vm=vm1')
  await page.waitForSelector('[data-testid="vm-origin"] dl')
  const rows = await b.run(() => [...document.querySelectorAll('[data-testid="vm-origin"] .kv > div')].map((row) => `${row.querySelector('dt')?.textContent}: ${row.querySelector('dd')?.textContent}`))
  check('VM page (AI client): who, client, token prefix, source IP and time', rows.join(' | ') === 'Created by: Ayu (MCP) · 7f3a9c21 | Client: claude-code 2.1.0 | Token: msk_AbCd1234… | From: 203.0.113.7 | Created: 2026-10-31 12:00 UTC', rows.join(' | '))
  check('VM page (AI client): an intact record shows no warning', await b.run(() => document.querySelector('[data-testid="origin-altered"]') === null))
  await b.shot('origin-vm-mcp-1440.png', true)

  await b.go('#/machines/details?id=studio&vm=vm2')
  await b.until(() => document.querySelector('[data-testid="vm-origin"] dl')?.textContent?.includes('panel (kurnia)') === true)
  const panelRows = await b.run(() => [...document.querySelectorAll('[data-testid="vm-origin"] .kv > div dt')].map((node) => node.textContent))
  check('VM page (panel): only the rows the record has', panelRows.join() === 'Created by,From,Created', panelRows.join())

  await b.go('#/machines/details?id=studio&vm=vm3')
  await b.until(() => document.querySelector('[data-testid="origin-backfilled"]') !== null)
  const old = await b.run(() => document.querySelector('[data-testid="vm-origin"]')?.textContent ?? '')
  check('VM page (made before tracking): says before tracking started, with the note, and no date', old.includes('before tracking started') && old.includes('Recorded afterwards: this VM was made before creators were tracked.') && old.includes('admin (recorded afterwards) · 0a1b2c3d') && !old.includes('1970'), old)
  await b.shot('origin-vm-backfilled-1440.png', true)

  await b.go('#/machines/details?id=studio&vm=vm6')
  await b.until(() => document.querySelector('[data-testid="origin-unknown"]') !== null)
  check('VM page (no record): unknown origin', (await b.run(() => document.querySelector('[data-testid="origin-unknown"]')?.textContent ?? '')).startsWith('Unknown origin'))

  await b.go('#/machines/details?id=studio&vm=vm7')
  await b.until(() => document.querySelector('[data-testid="origin-altered"]') !== null)
  const altered = await b.run(() => {
    const node = document.querySelector('[data-testid="origin-altered"]')
    return { text: node?.textContent ?? '', color: node ? getComputedStyle(node).color : '' }
  })
  check('VM page (altered record): says record altered, in red', altered.text.startsWith('record altered') && /^rgb\((1[6-9]\d|2\d\d), \d{1,2}, \d{1,2}\)$/.test(altered.color), `${altered.text} ${altered.color}`)
  check('VM page: hostile text is only text', await pwned())
  await b.shot('origin-vm-altered-1440.png', true)

  // ---- a phone ----
  await page.setViewport({ width: 390, height: 844 })
  await page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('[data-testid="origin-altered"]') !== null)
  check('VM page at 390 px: no sideways scroll', (await overflow()) <= 0, `${await overflow()}px`)
  await b.shot('origin-vm-altered-390.png', true)
  await b.go('#/machines/details?id=studio&vm=vm1')
  await b.until(() => document.querySelector('[data-testid="vm-origin"] dl') !== null)
  await b.shot('origin-vm-mcp-390.png', true)
  await b.go(VMS_TAB)
  await page.waitForSelector('[data-testid="bv-created-by"]')
  check('Building at 390 px: no sideways scroll', (await overflow()) <= 0, `${await overflow()}px`)
  await b.shot('origin-building-390.png', true)
  await b.click('Table')
  await page.waitForSelector('table.restable')
  check('Table at 390 px: no sideways scroll, every VM still says who made it', (await overflow()) <= 0 && sameWords(await texts('table.restable tbody td[data-label="Created by"]')), `${await overflow()}px`)
  await b.shot('origin-table-390.png', true)
  await b.click('Cards')
  await page.waitForSelector('.card')
  check('Cards at 390 px: no sideways scroll', (await overflow()) <= 0, `${await overflow()}px`)
  await b.shot('origin-cards-390.png', true)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  standin.close()
}
finish()
