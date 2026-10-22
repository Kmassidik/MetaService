// The first visit: the setup page asks for the token, shows whether the two passwords match, and has an eye to show them.
// Then the empty panel: no machines, no "Add a machine" button in the sidebar, and the empty list's own button leads to Find machines.
import { readFileSync } from 'node:fs'
import { ADMIN } from '../support/admin.ts'
import { check } from '../support/check.ts'
import { owlShown } from '../support/owls.ts'
import type { Browse } from '../support/page.ts'
import type { World } from './world.ts'

const SHORT_WAIT_MS = 10000
const WRONG_SETUP_TOKEN = 'a wrong setup token 0123456789'
const SETUP_TOKEN_LINE = /^ROOT_SETUP_TOKEN=(.+)$/m

/** Empties a field the way a person would, so the page notices. */
const clearField = (b: Browse, name: string) =>
  b.run((field) => {
    const input = document.querySelector<HTMLInputElement>(`input[name=${field}]`)
    if (!input) throw new Error(`no field ${field}`)
    input.value = ''
    input.dispatchEvent(new Event('input'))
  }, name)

const inputType = (b: Browse, name: string) => b.run((field) => document.querySelector<HTMLInputElement>(`input[name=${field}]`)?.type ?? '', name)

async function createTheAdmin(b: Browse, world: World): Promise<void> {
  await b.page.goto(world.root.base, { waitUntil: 'networkidle0' })
  const first = await b.text()
  check('a new Root asks to create the admin login and asks for the setup token', /first run/i.test(first) && /setup token/i.test(first) && !first.includes('dgx-spark'))
  const token = readFileSync(world.root.envFile, 'utf8').match(SETUP_TOKEN_LINE)?.[1]?.trim()
  if (!token) throw new Error('the Root did not write a setup token into its env file')
  await b.page.type('input[name=username]', ADMIN.username)
  await b.page.type('input[name=password]', ADMIN.password)
  await b.page.type('input[name=confirm]', 'not the same')
  await b.until(() => /don.t match/i.test(document.body.innerText), {})
  await owlShown(b, 'hero', 'the first-run page')
  await b.shot('first-run.png')
  check('different passwords are called out and the button is disabled', await b.run(() => document.querySelector<HTMLButtonElement>('button[type=submit]')?.disabled ?? false))
  check('the password is hidden until the eye is pressed', (await inputType(b, 'password')) === 'password')
  await b.page.click('button[aria-label="Show password"]')
  check('the eye shows the password', (await inputType(b, 'password')) === 'text')
  await b.page.click('button[aria-label="Hide password"]')
  await clearField(b, 'confirm')
  await b.page.type('input[name=confirm]', ADMIN.password)
  await b.until(() => /passwords match\./i.test(document.body.innerText), {})
  await b.page.type('input[name=setup_token]', WRONG_SETUP_TOKEN)
  await b.click('Create admin & sign in')
  await b.until(() => /setup is locked/i.test(document.body.innerText), { timeout: SHORT_WAIT_MS })
  check('a wrong setup token is refused', /setup is locked/i.test(await b.text()))
  await clearField(b, 'setup_token')
  await b.page.type('input[name=setup_token]', token)
  await b.click('Create admin & sign in')
  await b.until(() => document.body.innerText.includes('No machines yet'), { timeout: SHORT_WAIT_MS })
  check('the right setup token creates the admin and opens the panel', true)
}

async function theEmptyPanel(b: Browse): Promise<void> {
  const zero = await b.text()
  await owlShown(b, 'emptyMachines', 'the empty Overview')
  check('with no machine yet the page says 0 machines and 0 VMs', /machines\s*0/i.test(zero) && /vms\s*0/i.test(zero) && /no machines yet/i.test(zero), zero.slice(0, 400))
  await b.go('#/machines')
  await b.until(() => document.body.innerText.includes('No machines yet'), { timeout: SHORT_WAIT_MS })
  await owlShown(b, 'emptyMachines', 'the empty Machines list')
  check('the empty Machines list keeps its sentence next to the owl', /No machines yet\. Add the first one, and it will show up here\./.test(await b.text()))
  await b.shot('zero.png', true)
  check('the sidebar has no Add a machine button', await b.run(() => !/Add a machine/.test(document.querySelector<HTMLElement>('aside.side')?.innerText ?? '')))
  await b.click('＋ Add a machine')
  await b.until(() => location.hash === '#/machines/find' && document.body.innerText.includes('Looks at'), { timeout: SHORT_WAIT_MS })
  check('the empty list button leads to Find machines, and opens no dialog', (await b.page.$('dialog[open]')) === null && /Find machines/.test(await b.text()))
  await b.shot('empty-to-find.png')
}

export async function firstRun(b: Browse, world: World): Promise<void> {
  await createTheAdmin(b, world)
  await theEmptyPanel(b)
  await b.click('Sign out')
  await b.until(() => /sign in to manage/i.test(document.body.innerText), { timeout: SHORT_WAIT_MS })
}
