// Where the ssh command comes from, in a real browser against the stand-in Root: the reasons when there is no command, the SSH address field of the Environment tab (check, save, clear),
// the old plain line for an old parent, and the same command box on the VM page's Access tab.
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { openRow } from '../machine/environment.ts'
import { SHORT_WAIT_MS } from '../machine/steps.ts'
import { fresh, openTable } from './guard.ts'
import { DESKTOP, freshWithKeys, MACHINE_VMS, noSideScroll, openKeys, PHONE, VM_PAGE } from './ssh.ts'
import { commandShown, DEFAULT_NOTE, OFFICE_COMMAND, PASTE_NOTE, READY } from './sshSetup.ts'
import type { StandIn } from './standin.ts'

const ENVIRONMENT = '#/machines/details?id=studio&tab=environment'
const NO_JUMP = 'This machine has no SSH address yet. Set one in Environment.'
const NO_ADDRESS = 'The VM has no address yet. Start it and wait a moment.'
const HELP = "Used for the ssh command in SSH keys. Example: you@203.0.113.7 or you@studio.example.com:2222. Leave empty to use the machine's office address"
const FORM_ERROR = 'Use the form user@host or user@host:port.'
const OWN_JUMP = 'you@studio.example.com:2222'
const SETTLE_MS = 600

const field = (b: Browse) => b.run(() => ({ value: document.querySelector<HTMLInputElement>('#env-sshJump')?.value ?? null, label: document.querySelector('label[for=env-sshJump]')?.textContent?.trim() ?? '', hint: document.querySelector('#env-sshJump')?.closest('.entry')?.querySelector('.hint')?.textContent?.trim() ?? '' }))

async function noCommandReasons(b: Browse, standin: StandIn): Promise<void> {
  await freshWithKeys(b, standin, MACHINE_VMS)
  standin.sshKeys.officeJump = null
  await openTable(b)
  await openKeys(b, 'vm1')
  const text = await b.dialogText()
  check('no jump anywhere: the dialog says the machine has no SSH address, no Ready command', text.includes(NO_JUMP) && (await commandShown(b)) === '' && !text.includes(PASTE_NOTE), text)
  const href = await b.run(() => document.querySelector<HTMLAnchorElement>('dialog[open] a.link')?.getAttribute('href') ?? '')
  check('the explanation links to the machine\'s Environment tab', href === ENVIRONMENT, href)
  await b.shot('ssh-connect-no-jump-desktop.png')
  await b.page.setViewport(PHONE)
  check('phone 400px: the explanation does not scroll sideways', await noSideScroll(b))
  await b.shot('ssh-connect-no-jump-phone.png')
  await b.page.setViewport(DESKTOP)
  await b.page.click('dialog[open] a.link')
  await b.until(() => document.querySelector('#env-sshJump') !== null && document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
  check('the link closes the dialog and opens the Environment tab with the SSH address field', true)

  await freshWithKeys(b, standin, MACHINE_VMS)
  standin.sshKeys.addressless = true
  await openTable(b)
  await openKeys(b, 'vm1')
  check('a VM with no address: "The VM has no address yet. Start it and wait a moment."', (await b.dialogText()).includes(NO_ADDRESS) && (await commandShown(b)) === '')
  await b.page.keyboard.press('Escape')
}

async function jumpFromEnvironment(b: Browse, standin: StandIn): Promise<void> {
  await freshWithKeys(b, standin, ENVIRONMENT)
  await b.page.waitForSelector('#env-sshJump')
  await openRow(b, 'Names')
  const start = await field(b)
  check('the Environment tab has the SSH address field with the exact help text', start.label === 'SSH address' && start.value === '' && start.hint === HELP, JSON.stringify(start))
  await b.type('#env-sshJump', 'studio.example.com')
  await b.until((id) => document.getElementById(id) !== null, { timeout: SHORT_WAIT_MS }, 'env-sshJump-error')
  const refusal = await b.run(() => document.querySelector<HTMLElement>('#env-sshJump-error')?.innerText ?? '')
  check('a value that is not user@host shows the plain message and Save stays off', refusal === FORM_ERROR && (await b.isDisabled('Save')), refusal)
  await b.shot('ssh-connect-env-invalid-desktop.png')
  await b.type('#env-sshJump', OWN_JUMP)
  await b.click('Save')
  await b.until(() => document.querySelector('#env-sshJump-error') === null, { timeout: SHORT_WAIT_MS })
  await wait(SETTLE_MS)
  check('Save sends only ssh_jump', JSON.stringify(standin.settingsPatches) === JSON.stringify([{ ssh_jump: OWN_JUMP }]), JSON.stringify(standin.settingsPatches))
  await b.shot('ssh-connect-env-saved-desktop.png')
  await b.page.setViewport(PHONE)
  check('phone 400px: the Environment tab with the field does not scroll sideways', await b.run(() => document.documentElement.scrollWidth <= window.innerWidth))
  await b.shot('ssh-connect-env-saved-phone.png')
  await b.page.setViewport(DESKTOP)

  await b.go(MACHINE_VMS)
  await openTable(b)
  await openKeys(b, 'vm1')
  const text = await b.dialogText()
  check('the command now goes through the saved address and drops the office note', (await commandShown(b)) === `ssh -J ${OWN_JUMP} root@10.0.0.1` && text.includes(READY) && !text.includes(DEFAULT_NOTE), text)
  await b.shot('ssh-connect-own-jump-desktop.png')
  await b.page.keyboard.press('Escape')

  await b.go(ENVIRONMENT)
  await b.page.waitForSelector('#env-sshJump')
  await openRow(b, 'Names')
  await b.until((wanted) => document.querySelector<HTMLInputElement>('#env-sshJump')?.value === wanted, { timeout: SHORT_WAIT_MS }, OWN_JUMP)
  await b.type('#env-sshJump', '')
  await b.click('Save')
  await b.until(() => (document.querySelector('[role=tab][aria-selected=true]') !== null), { timeout: SHORT_WAIT_MS })
  await wait(SETTLE_MS)
  check('clearing the field sends null', JSON.stringify(standin.settingsPatches.at(-1)) === JSON.stringify({ ssh_jump: null }), JSON.stringify(standin.settingsPatches))
  await b.go(MACHINE_VMS)
  await openTable(b)
  await openKeys(b, 'vm1')
  check('the command is back to the office address', (await commandShown(b)) === OFFICE_COMMAND)
  await b.page.keyboard.press('Escape')
}

async function oldParent(b: Browse, standin: StandIn): Promise<void> {
  await freshWithKeys(b, standin, MACHINE_VMS)
  standin.sshKeys.oldParent = true
  await openTable(b)
  await openKeys(b, 'vm1')
  const text = await b.dialogText()
  check('an old parent (no connect, no sshd_state): the old plain line and note, no Ready, no progress', (await commandShown(b)) === 'ssh root@10.0.0.1' && text.includes('ssh -J') && !text.includes(READY), text)
  await b.page.keyboard.press('Escape')
}

async function accessTab(b: Browse, standin: StandIn): Promise<void> {
  await freshWithKeys(b, standin, VM_PAGE)
  await b.run(() => [...document.querySelectorAll<HTMLElement>('[role=tab]')].find((tab) => tab.textContent?.trim() === 'Access')?.click())
  await b.until((wanted) => document.querySelector('.access .box code')?.textContent?.trim() === wanted, { timeout: SHORT_WAIT_MS }, OFFICE_COMMAND)
  const text = await b.run(() => document.querySelector<HTMLElement>('.access')?.innerText ?? '')
  check('the VM page Access tab shows the same Ready line, command box and note', text.includes(READY) && text.includes(PASTE_NOTE), text)
  await b.shot('ssh-connect-access-desktop.png')
  await fresh(b, standin, '#/machines/details?id=studio&vm=vm2')
  await b.run(() => [...document.querySelectorAll<HTMLElement>('[role=tab]')].find((tab) => tab.textContent?.trim() === 'Access')?.click())
  await wait(SETTLE_MS)
  check('a stopped VM shows no command on the Access tab', (await b.run(() => document.querySelector('.access .box') === null)))
}

export async function sshConnectWorks(b: Browse, standin: StandIn): Promise<void> {
  await noCommandReasons(b, standin)
  await jumpFromEnvironment(b, standin)
  await oldParent(b, standin)
  await accessTab(b, standin)
}
