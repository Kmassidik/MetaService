// The SSH keys dialog in a real browser against the stand-in Root: the icon on every VM row, adding a good key, refusals, the red confirm before Remove,
// five rapid Add clicks sending one request, the status lines, a phone-width screen, and that only the fingerprint of a key is ever shown.
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { burst, fresh, openTable } from './guard.ts'
import type { StandIn } from './standin.ts'

export const MACHINE_VMS = '#/machines/details?id=studio&tab=vms'
const ALL_VMS = '#/vms'
export const VM_PAGE = '#/machines/details?id=studio&vm=vm1'
export const PASTE_BOX = 'dialog[open] #ssh-key-paste'
export const SHORT_WAIT_MS = 8000
const SLOW_MS = 800
const RAPID_CLICKS = 5
const SETTLE_MS = 1600
export const PHONE = { width: 400, height: 844 }
export const DESKTOP = { width: 1280, height: 800 }
const VMS_ON_STUDIO = ['vm1', 'vm2', 'vm3']
const VMS_ON_ALL = ['vm1', 'vm2', 'vm3', 'vm4']

const BLOB_ONE = 'AAAAC3NzaC1lZDI1NTE5AAAAIGq3k9eX1mQ2y0pT7uV8wXyZ1aBcDeFgHiJkLmNoPqRs'
const BLOB_TWO = 'AAAAB3NzaC1yc2EAAAADAQABAAABAQDk3Lm9XvQ2y0pT7uV8wXyZ1aBcDeFgHiJkLmNoPqRsTuVwXyZ'
export const BLOB_NEW = 'AAAAC3NzaC1lZDI1NTE5AAAAIPz9yX8wV7uT6sR5qP4oN3mL2kJ1iH0gF9eD8cB7aZ6y'
export const KEY_ONE = `ssh-ed25519 ${BLOB_ONE} kurnia@laptop`
export const KEY_TWO = `ssh-rsa ${BLOB_TWO} ci-runner`
export const KEY_NEW = `ssh-ed25519 ${BLOB_NEW} new@phone`
const OPTION_KEY = `command="rm -rf /" ssh-ed25519 ${BLOB_NEW} sneaky`
const PRIVATE_KEY = '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ\n-----END OPENSSH PRIVATE KEY-----'
const DUPLICATE_TEXT = 'This key is already on this VM.'
const PRIVATE_TEXT = 'That looks like a private key'

const dialogItems = (b: Browse) => b.run(() => [...document.querySelectorAll<HTMLElement>('dialog[open] ul.keys li')].map((item) => item.innerText.replace(/\s+/g, ' ').trim()))

/** The small line next to the Add button. */
const addLine = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('dialog[open] .add .aline')?.innerText.trim() ?? '')

export async function openKeys(b: Browse, vm: string): Promise<void> {
  await b.page.click(`button[aria-label="SSH keys ${vm}"]`)
  await b.page.waitForSelector(PASTE_BOX, { timeout: SHORT_WAIT_MS })
  await b.until(() => document.querySelector('dialog[open]')?.textContent?.includes('Reading the keys') === false, { timeout: SHORT_WAIT_MS })
}

export async function pasteAndAdd(b: Browse, pasted: string): Promise<void> {
  await b.type(PASTE_BOX, pasted)
  await b.click('Add')
}

export const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth && [...document.querySelectorAll<HTMLElement>('dialog[open]')].every((dialog) => dialog.scrollWidth <= dialog.clientWidth))

export async function freshWithKeys(b: Browse, standin: StandIn, hash: string): Promise<void> {
  await fresh(b, standin, hash)
  standin.sshKeys.seed('vm1', KEY_ONE)
  standin.sshKeys.seed('vm1', KEY_TWO)
}

async function iconsOnEveryRow(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, MACHINE_VMS)
  await openTable(b)
  const wanted = (names: string[]) => names.map((name) => `SSH keys ${name}`)
  const spoken = () => b.run(() => [...document.querySelectorAll<HTMLButtonElement>('tbody button[data-tip="SSH keys"]')].map((button) => button.getAttribute('aria-label') ?? '').sort())
  check('machine page Table: every VM row has the key icon named "SSH keys <vm>" with the tooltip "SSH keys"', JSON.stringify(await spoken()) === JSON.stringify(wanted(VMS_ON_STUDIO)), JSON.stringify(await spoken()))
  await b.click('Cards')
  await b.page.waitForSelector('.card')
  const cards = await b.run(() => [...document.querySelectorAll<HTMLButtonElement>('.card button[data-tip="SSH keys"]')].map((button) => button.getAttribute('aria-label') ?? '').sort())
  check('machine page Cards: every VM card has the key icon', JSON.stringify(cards) === JSON.stringify(wanted(VMS_ON_STUDIO)), JSON.stringify(cards))
  await fresh(b, standin, ALL_VMS)
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr')
  check('All VMs: every VM row has the key icon', JSON.stringify(await spoken()) === JSON.stringify(wanted(VMS_ON_ALL)), JSON.stringify(await spoken()))
}

async function listOfKeys(b: Browse, standin: StandIn): Promise<void> {
  await freshWithKeys(b, standin, MACHINE_VMS)
  await openTable(b)
  await openKeys(b, 'vm1')
  const title = await b.run(() => document.querySelector('dialog[open] h3')?.textContent?.trim())
  check('the dialog opens with the title "SSH keys for vm1"', title === 'SSH keys for vm1', `${title}`)
  const items = await dialogItems(b)
  const shownAll = items.length === 2 && items[0]?.includes('ssh-ed25519') === true && items[0].includes('kurnia@laptop') && /SHA256:\S+/.test(items[0]) && items[1]?.includes('ssh-rsa') === true && items[1].includes('ci-runner')
  check('the two keys show type, comment and a SHA256 fingerprint', shownAll, JSON.stringify(items))
  const mono = await b.run(() => getComputedStyle(document.querySelector('dialog[open] ul.keys code') as Element).fontFamily.toLowerCase().includes('mono'))
  check('the fingerprint is in the mono face', mono)
  const connect = await b.dialogText()
  check('the dialog shows Ready and the copyable "ssh -J ... root@10.0.0.1" command', connect.includes('Ready. This key can log in.') && connect.includes('ssh -J luca@202.0.113.9 root@10.0.0.1'))
  check('the help line says to paste the .pub file and never a private key', connect.includes('Paste the public key (the file that ends in .pub). Never paste a private key.'))
  check('no status line while the keys are applied and the SSH server runs', (await b.run(() => document.querySelectorAll('dialog[open] .status').length)) === 0)
  await b.shot('ssh-keys-list-desktop.png')
}

async function addingAGoodKey(b: Browse, standin: StandIn): Promise<void> {
  standin.sshKeys.requests.length = 0
  await pasteAndAdd(b, `  ${KEY_NEW}\n `)
  await b.until(() => document.querySelectorAll('dialog[open] ul.keys li').length === 3, { timeout: SHORT_WAIT_MS })
  const items = await dialogItems(b)
  check('a good key pasted with spaces around it is trimmed, accepted and listed with its type, fingerprint and comment', items.length === 3 && (items[2] ?? '').includes('new@phone') && (items[2] ?? '').includes('ssh-ed25519') && /SHA256:\S+/.test(items[2] ?? ''), JSON.stringify(items))
  await b.until(() => document.querySelector('dialog[open] .add .aline')?.textContent?.trim() === 'Added', { timeout: SHORT_WAIT_MS })
  check('the box is empty after the add and the line says Added', (await b.run((selector) => document.querySelector<HTMLTextAreaElement>(selector)?.value, PASTE_BOX)) === '')
  const exposed = await b.run((blob) => document.documentElement.innerHTML.includes(blob) || document.body.innerText.includes(blob), BLOB_NEW)
  check('the key itself is never shown on the page, only its fingerprint', !exposed)
}

async function refusals(b: Browse, standin: StandIn): Promise<void> {
  standin.sshKeys.requests.length = 0
  await pasteAndAdd(b, OPTION_KEY)
  await b.until(() => (document.querySelector('dialog[open] .add .aline.bad')?.textContent ?? '') !== '', { timeout: SHORT_WAIT_MS })
  const refusal = await addLine(b)
  check('a key with an option in front shows the parent words under the box and adds nothing', refusal.includes('options') && (await dialogItems(b)).length === 3, refusal)
  await b.shot('ssh-keys-refusal-desktop.png')
  standin.sshKeys.requests.length = 0
  await pasteAndAdd(b, PRIVATE_KEY)
  await b.until((text) => (document.querySelector('dialog[open] .add .aline')?.textContent ?? '').includes(text), { timeout: SHORT_WAIT_MS }, PRIVATE_TEXT)
  await wait(SETTLE_MS / 4)
  check('a pasted private key is refused in the panel and no request is sent', standin.sshKeys.requests.length === 0, standin.sshKeys.requests.join())
  standin.sshKeys.requests.length = 0
  await pasteAndAdd(b, KEY_ONE)
  await b.until((text) => (document.querySelector('dialog[open] .add .aline')?.textContent ?? '') === text, { timeout: SHORT_WAIT_MS }, DUPLICATE_TEXT)
  check('a key that is already there shows the duplicate text and the list stays at 3', (await dialogItems(b)).length === 3 && standin.sshKeys.requests.join() === 'POST vm1')
}

/** The confirm dialog is the last open dialog (it sits on top of the keys dialog). */
const topDialog = (b: Browse) => b.run(() => {
  const open = [...document.querySelectorAll<HTMLElement>('dialog[open]')]
  const top = open[open.length - 1]
  return { count: open.length, title: top?.querySelector('h3')?.textContent?.trim() ?? '', text: top?.innerText ?? '', red: top?.querySelector('button.btn.danger')?.textContent?.trim() ?? '' }
})

async function removing(b: Browse, standin: StandIn): Promise<void> {
  standin.sshKeys.requests.length = 0
  await b.page.click('button[aria-label="Remove key ci-runner"]')
  await b.until(() => document.querySelectorAll('dialog[open]').length === 2, { timeout: SHORT_WAIT_MS })
  const confirm = await topDialog(b)
  check('Remove opens the shared red dialog first, with the words for this VM', confirm.title === 'Remove this key?' && confirm.red === 'Remove key' && confirm.text.includes('This key can no longer log in to vm1') && confirm.text.includes('removed from the VM straight away'), JSON.stringify(confirm))
  await wait(SETTLE_MS / 4)
  check('nothing is sent before the red button is pressed', standin.sshKeys.requests.length === 0)
  await b.shot('ssh-keys-remove-confirm-desktop.png')
  await b.click('Remove key')
  await b.until(() => document.querySelectorAll('dialog[open]').length === 1 && document.querySelectorAll('dialog[open] ul.keys li').length === 2, { timeout: SHORT_WAIT_MS })
  const left = await dialogItems(b)
  check('after the red button the key is gone and one DELETE was sent', standin.sshKeys.requests.join() === 'DELETE vm1' && !left.join().includes('ci-runner'), `${standin.sshKeys.requests.join()} ${JSON.stringify(left)}`)
}

async function fiveQuickClicks(b: Browse, standin: StandIn): Promise<void> {
  standin.sshKeys.requests.length = 0
  standin.sshKeys.delayMs = SLOW_MS
  await b.type(PASTE_BOX, `ssh-ed25519 ${BLOB_TWO} quick@click`)
  await burst(b, 'Add', RAPID_CLICKS)
  await wait(SETTLE_MS + SLOW_MS)
  check(`${RAPID_CLICKS} rapid Add clicks send exactly 1 request`, standin.sshKeys.requests.join() === 'POST vm1', standin.sshKeys.requests.join())
}

async function statusLines(b: Browse, standin: StandIn): Promise<void> {
  await b.page.keyboard.press('Escape')
  standin.sshKeys.applied = false
  await openKeysFresh(b, standin, 'vm1')
  check('running VM, not applied: "the machine did not answer. It will retry."', (await b.dialogText()).includes('Saved, not applied yet: the machine did not answer. It will retry.'))
  await b.page.keyboard.press('Escape')
  await openKeysFresh(b, standin, 'vm2')
  check('stopped VM, not applied: "will be written into the VM when the VM is running."', (await b.dialogText()).includes('Saved. It will be written into the VM when the VM is running.'))
  await b.page.keyboard.press('Escape')
  standin.sshKeys.applied = true
  standin.sshKeys.sshd = 'missing'
  await openKeysFresh(b, standin, 'vm1')
  check('sshd missing: "No SSH server was found in this VM..."', (await b.dialogText()).includes('No SSH server was found in this VM. Keys are saved, but nobody can log in until the image runs one.'))
  await b.shot('ssh-keys-sshd-missing-desktop.png')
  await b.page.keyboard.press('Escape')
  standin.sshKeys.sshd = 'installed'
  await openKeysFresh(b, standin, 'vm1')
  check('sshd installed: "An SSH server is installed in this VM but not running."', (await b.dialogText()).includes('An SSH server is installed in this VM but not running.'))
  await b.page.keyboard.press('Escape')
  standin.sshKeys.sshd = 'unknown'
  await openKeysFresh(b, standin, 'vm1')
  check('sshd unknown and applied: no status line', (await b.run(() => document.querySelectorAll('dialog[open] .status').length)) === 0)
  await b.page.keyboard.press('Escape')
}

async function openKeysFresh(b: Browse, standin: StandIn, vm: string): Promise<void> {
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
  standin.sshKeys.delayMs = 0
  await openKeys(b, vm)
}

async function onAPhone(b: Browse, standin: StandIn): Promise<void> {
  await b.page.setViewport(PHONE)
  standin.sshKeys.applied = true
  standin.sshKeys.sshd = 'running'
  await freshWithKeys(b, standin, MACHINE_VMS)
  await openTable(b)
  await openKeys(b, 'vm1')
  check('phone 400px: the list does not scroll sideways', await noSideScroll(b))
  await b.shot('ssh-keys-list-phone.png')
  await b.type(PASTE_BOX, OPTION_KEY)
  await b.click('Add')
  await b.until(() => (document.querySelector('dialog[open] .add .aline.bad')?.textContent ?? '') !== '', { timeout: SHORT_WAIT_MS })
  check('phone 400px: a refusal does not scroll sideways', await noSideScroll(b))
  await b.shot('ssh-keys-refusal-phone.png')
  await b.page.keyboard.press('Escape')
  standin.sshKeys.sshd = 'missing'
  await openKeysFresh(b, standin, 'vm1')
  check('phone 400px: the SSH-server-missing line does not scroll sideways', await noSideScroll(b))
  await b.shot('ssh-keys-sshd-missing-phone.png')
  await b.page.setViewport(DESKTOP)
}

async function fromTheVmPage(b: Browse, standin: StandIn): Promise<void> {
  await freshWithKeys(b, standin, VM_PAGE)
  await b.run(() => [...document.querySelectorAll<HTMLElement>('[role=tab]')].find((tab) => tab.textContent?.trim() === 'Access')?.click())
  await b.click('Manage SSH keys')
  await b.page.waitForSelector(PASTE_BOX, { timeout: SHORT_WAIT_MS })
  await b.until(() => document.querySelectorAll('dialog[open] ul.keys li').length === 2, { timeout: SHORT_WAIT_MS })
  check('the VM page Access tab opens the same dialog with the same keys', (await b.run(() => document.querySelector('dialog[open] h3')?.textContent?.trim())) === 'SSH keys for vm1')
}

export async function sshKeysDialogWorks(b: Browse, standin: StandIn): Promise<void> {
  await iconsOnEveryRow(b, standin)
  await listOfKeys(b, standin)
  await addingAGoodKey(b, standin)
  await refusals(b, standin)
  await removing(b, standin)
  await fiveQuickClicks(b, standin)
  await statusLines(b, standin)
  await onAPhone(b, standin)
  await fromTheVmPage(b, standin)
}
