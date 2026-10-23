// The Terminal button on Linux machines: a container on a machine whose helper says it serves a terminal opens a real console and shows its echo;
// a container on a machine whose helper does not say it is off and tells the person to update the helper; a VM on a Linux machine is off with "Containers only for now".
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { startLinuxFake, type LinuxFake } from './linux-fake.ts'
import { facts, press } from './terminal-buttons.ts'
import { isOpen, typeLine, untilConnected, untilScreenHas } from './terminal.ts'
import { resendHeartbeats, type World } from './world.ts'

const FLAGGED_MACHINE = 'rtx-linux'
const OLD_MACHINE = 'old-linux'
const CONTAINER = 'shell-box'
const VM = 'vm-box'
const OLD_CONTAINER = 'plain-box'
const ROWS = 'table[aria-label="VMs"] tbody tr'
const SHORT_WAIT_MS = 10000
/** The panel reads the machines again every 15 seconds. */
const LIST_WAIT_MS = 20000
const CLOSE_SETTLE_MS = 1500
const ECHO = 'echo linux-$((40+2))'
const ECHOED = /^linux-42$/m

async function openTheList(b: Browse, world: World): Promise<void> {
  await resendHeartbeats(world)
  await b.go('#/vms')
  await b.page.waitForSelector(ROWS)
  for (const name of [CONTAINER, VM, OLD_CONTAINER]) await b.until((text) => document.body.innerText.includes(text), { timeout: LIST_WAIT_MS }, name)
}

async function opensAndEchoes(b: Browse): Promise<void> {
  const button = await facts(b, ROWS, CONTAINER)
  check('a container on a Linux machine whose helper says terminal has an enabled Terminal button', button.found && !button.disabled, JSON.stringify(button))
  await press(b, ROWS, CONTAINER)
  await b.page.waitForSelector('.term-box .xterm')
  await untilConnected(b)
  await typeLine(b, ECHO)
  check('the Linux console shows the echo of what was typed', ECHOED.test(await untilScreenHas(b, ECHOED)))
  await b.shot('terminal-linux-open.png')
  await b.click('✕ Close')
  await b.until(() => document.querySelector('.term-box') === null, { timeout: SHORT_WAIT_MS })
  check('Close closes the Linux console', !(await isOpen(b)))
  await new Promise((done) => setTimeout(done, CLOSE_SETTLE_MS))
}

async function refusals(b: Browse): Promise<void> {
  const old = await facts(b, ROWS, OLD_CONTAINER)
  check('a container on a Linux machine without the flag is off and says "Update the helper to use the terminal"', old.found && old.disabled && /Update the helper to use the terminal/.test(old.label), JSON.stringify(old))
  const vm = await facts(b, ROWS, VM)
  check('a VM on a Linux machine is off and says "Containers only for now"', vm.found && vm.disabled && /Containers only for now/.test(vm.label), JSON.stringify(vm))
  await b.shot('terminal-linux-disabled.png')
}

export async function terminalLinuxScenario(b: Browse, world: World): Promise<void> {
  const started: LinuxFake[] = []
  try {
    started.push(await startLinuxFake(world, FLAGGED_MACHINE, { terminal: true, workloads: [`${CONTAINER}:container`, `${VM}:vm`] }))
    started.push(await startLinuxFake(world, OLD_MACHINE, { terminal: false, workloads: [`${OLD_CONTAINER}:container`] }))
    await openTheList(b, world)
    await opensAndEchoes(b)
    await refusals(b)
  } finally {
    for (const fake of started) fake.child.kill()
  }
}
