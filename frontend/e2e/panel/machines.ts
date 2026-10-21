// Signing in, the Overview, the sidebar, and the Machines list: its problems, hostile text, and removing a machine.
import { ADMIN } from '../support/admin.ts'
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import type { World } from './world.ts'

const SHORT_WAIT_MS = 10000
const REMOVE_WAIT_MS = 5000
/** The sidebar as the MAAS panel has it. Machines is a dropdown: closed it is one row; open it holds the machine list and Find machines. */
const SIDEBAR_CLOSED = ['Operator', 'Overview', 'Token ledger', 'Settings', 'Health & alerts', 'Infrastructure', 'Machines', 'External monitoring', 'Beszel not configured']
const DROPDOWN_ENDS = ['Machine list', 'Find machines']

const inputField = (b: Browse, name: string) => b.page.type(`input[name=${name}]`, name === 'username' ? ADMIN.username : ADMIN.password)

export async function signInWithAWrongThenTheRightPassword(b: Browse, world: World): Promise<void> {
  await b.page.goto(world.root.base, { waitUntil: 'networkidle0' })
  const gate = await b.text()
  check('the first thing shown is the sign-in page, with no machines and no Google', /sign in to manage/i.test(gate) && !gate.includes('dgx-spark') && !/google/i.test(gate))
  await b.shot('login.png')
  await inputField(b, 'username')
  await b.page.type('input[name=password]', 'a wrong password')
  await b.click('Sign in')
  await b.until(() => document.body.innerText.includes('wrong username or password'), { timeout: SHORT_WAIT_MS })
  check('a wrong password is refused in plain words', !(await b.text()).includes('dgx-spark'))
  await b.run(() => {
    const input = document.querySelector<HTMLInputElement>('input[name=password]')
    if (!input) return
    input.value = ''
    input.dispatchEvent(new Event('input'))
  })
  await inputField(b, 'password')
  await b.click('Sign in')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Overview', { timeout: SHORT_WAIT_MS })
}

export async function overviewAndSidebar(b: Browse): Promise<void> {
  const overview = await b.text()
  check('the right password opens the Overview', overview.includes(ADMIN.username) && /Operator › Overview/.test(overview))
  await b.shot('overview.png')
  check('the Overview counts the machines and VMs', /MACHINES\s*2/i.test(overview) && /VMS\s*2/i.test(overview) && /NEED ATTENTION\s*1/i.test(overview), overview.slice(0, 200))
  check('the Overview says what needs attention, with the fix', /dgx-spark/.test(overview) && overview.includes('metaservice-agent setup --yes'))
  const items = () => b.page.$$eval('aside.side h3, aside.side nav a, aside.side nav button, aside.side .nav-unavailable', (nodes) => nodes.map((node) => node.textContent?.trim() ?? ''))
  const closed = await items()
  check('the sidebar has the MAAS groups and names, and Machines is a closed dropdown on the Overview', JSON.stringify(closed) === JSON.stringify(SIDEBAR_CLOSED), JSON.stringify(closed))
  await b.click('Machines')
  const open = await items()
  const inside = open.slice(open.indexOf('Machines') + 1, open.indexOf('External monitoring'))
  check('opening it shows the machine list then Find machines, and no machine names', JSON.stringify(inside) === JSON.stringify(DROPDOWN_ENDS), JSON.stringify(open))
  check('the Machines button says whether it is open', await b.run(() => document.querySelector('aside.side nav button')?.getAttribute('aria-expanded') === 'true'))
  await b.shot('sidebar-open.png')
  await b.click('Machines')
  check('pressing it again closes the dropdown', JSON.stringify(await items()) === JSON.stringify(SIDEBAR_CLOSED))
  check('with machines added the sidebar still has no Add a machine button', await b.run(() => !/Add a machine/.test(document.querySelector<HTMLElement>('aside.side')?.innerText ?? '')))
}

export async function machinesList(b: Browse): Promise<void> {
  await b.go('#/machines')
  await b.until(() => document.body.innerText.includes('dgx-spark'), { timeout: SHORT_WAIT_MS })
  const body = await b.text()
  await b.shot('machines.png')
  check('Machines lists the machines', body.includes('dgx-spark') && body.includes('mac-mini'))
  check('a machine with a host problem says it needs setup and shows the fix', /needs setup/i.test(body) && body.includes('is not trusted') && body.includes('metaservice-agent setup --yes'))
  check('only the machine that reported a problem is marked', (body.match(/needs setup/gi) ?? []).length === 1)
  check('a list with machines has no Add a machine button of its own', !body.includes('＋ Add a machine'))
  await b.shot('needs-setup.png', true)
}

export async function hostileTextIsShownAsText(b: Browse): Promise<void> {
  await b.go('#/machines/details?id=dgx-spark')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'dgx-spark', { timeout: SHORT_WAIT_MS })
  await openTab(b, 'Deployments')
  await b.page.waitForSelector('.segmented')
  await pickView(b, 'Table')
  await b.until(() => document.body.innerText.includes('<img src=x'), {})
  check('hostile workload text is shown as text, not run', (await b.run(() => window.__xss)) === undefined && (await b.page.$('img[src="x"]')) === null)
}

export async function removeAMachine(b: Browse): Promise<void> {
  await b.go('#/machines')
  await b.page.click('button[aria-label="Remove mac-mini"]')
  await b.page.waitForSelector('dialog[open]')
  check('remove asks first and says what happens', (await b.text()).includes('Its VMs keep running'))
  await b.click('Remove machine')
  await b.until(() => !document.body.innerText.includes('mac-mini'), { timeout: REMOVE_WAIT_MS })
  check('a removed machine disappears', !(await b.text()).includes('mac-mini'))
}

/** Opens one of a machine page's tabs, such as Deployments or Activity. */
export const openTab = (b: Browse, label: string) => b.run((wanted) => [...document.querySelectorAll<HTMLElement>('[role=tab]')].find((tab) => tab.textContent?.trim().startsWith(wanted))?.click(), label)

/** Picks one of the Deployments views: Building, Table or Cards. */
export const pickView = (b: Browse, label: string) => b.run((wanted) => [...document.querySelectorAll<HTMLElement>('.segmented button')].find((button) => button.textContent?.trim() === wanted)?.click(), label)
