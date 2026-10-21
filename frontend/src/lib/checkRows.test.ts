import { expect, test } from 'bun:test'
import { checkCards, checkRows, hostKeyShort, isBlocking, machineLine, manualSteps, readyCount, stoppedEarly, verdict } from './checkRows.ts'
import type { Requirement } from './types.ts'

const KEY = 'SHA256:DmQeV3tR8xYb2LfZkq0WnH5uAa7cPjE1sGdXoTi9Qki0+g'
const ok = (id: string, label: string, detail: string): Requirement => ({ id, label, ok: true, detail })
const cross = (id: string, label: string, detail: string, fix = 'Do the thing.'): Requirement => ({ id, label, ok: false, detail, fix })

/** What the parent sends for a ready Linux computer, in its own words. */
const linux = (): Requirement[] => [
  ok('login', 'Login', `Logged in as luca. Host key ${KEY}.`),
  ok('system', 'System', 'Ubuntu 24.04 · AMD Ryzen 9 5950X · x86_64'),
  ok('agent', 'MetaService program for this system', 'Found (linux-x86_64).'),
  ok('memory', 'Memory', '62 GB.'),
  ok('disk', 'Free disk space', '79 GB free.'),
  ok('vm_support', 'Can run workloads', '/dev/kvm is there: VMs and containers.'),
  ok('vm_tool', 'Incus (makes the VMs)', 'Installed. It is used as it is; nothing about it is changed.'),
  ok('python', 'Python (runs the chat)', 'Found.'),
  ok('admin', 'Admin rights (sudo)', 'Yes, with a password. The engine can get its own user.'),
  ok('port', 'Port 9101 free', 'Nothing uses it.'),
  ok('parent', 'The parent can be reached from there', 'The Agent will report to http://127.0.0.1:9102 there, which leads back through this SSH connection.'),
]
const swap = (rows: Requirement[], replacement: Requirement): Requirement[] => rows.map((row) => (row.id === replacement.id ? replacement : row))
const byId = (reqs: Requirement[], id: string) => checkRows(reqs).find((row) => row.id === id)
const need = (reqs: Requirement[], id: string) => {
  const row = byId(reqs, id)
  if (!row) throw new Error(`no row ${id}`)
  return row
}

test('a ready computer has eleven ticks in three cards, in the order of the mockup', () => {
  const cards = checkCards(checkRows(linux()))
  expect(cards.map((card) => card.title)).toEqual(['This computer', 'Software it needs', 'Connection'])
  expect(cards.map((card) => card.rows.map((row) => row.id))).toEqual([
    ['login', 'system', 'agent', 'memory', 'disk', 'vm_support'],
    ['vm_tool', 'python', 'admin'],
    ['port', 'parent'],
  ])
  expect(cards.some((card) => card.hasBlocking)).toBe(false)
  expect(readyCount(checkRows(linux()))).toEqual({ ready: 11, total: 11 })
})

test('a card with a blocking cross says so, the others do not', () => {
  const reqs = swap(linux(), cross('python', 'Python (runs the chat)', 'Not installed.'))
  expect(checkCards(checkRows(reqs)).map((card) => card.hasBlocking)).toEqual([false, true, false])
  expect(readyCount(checkRows(reqs))).toEqual({ ready: 10, total: 11 })
})

test('the NVIDIA toolkit row goes in the software card, counts, and never blocks', () => {
  const reqs = [...linux(), cross('gpu_toolkit', 'NVIDIA container toolkit (lets containers use the GPU)', 'Not installed. This computer has an NVIDIA GPU (GB10).')]
  const row = byId(reqs, 'gpu_toolkit')
  expect(row?.state).toBe('optional')
  expect(row?.group).toBe('software')
  expect(row?.label).toBe('NVIDIA toolkit for containers')
  expect(isBlocking(need(reqs, 'gpu_toolkit'))).toBe(false)
  expect(readyCount(checkRows(reqs))).toEqual({ ready: 11, total: 12 })
  expect(checkCards(checkRows(reqs)).some((card) => card.hasBlocking)).toBe(false)
})

test('a missing Incus or Python is a blocking cross', () => {
  const reqs = swap(linux(), cross('vm_tool', 'Incus (makes the VMs)', 'Not installed.'))
  expect(byId(reqs, 'vm_tool')?.state).toBe('blocking')
  expect(isBlocking(need(reqs, 'vm_tool'))).toBe(true)
})

test('ticks get a short value, from the parent\'s own words', () => {
  const value = (id: string) => byId(linux(), id)?.value
  expect(value('login')).toBe('luca')
  expect(value('system')).toBe('Ubuntu 24.04')
  expect(value('agent')).toBe('linux-x86_64')
  expect(value('memory')).toBe('62 GB')
  expect(value('disk')).toBe('79 GB')
  expect(value('vm_support')).toBe('VMs and containers')
  expect(value('vm_tool')).toBe('Installed')
  expect(value('python')).toBe('Found')
  expect(value('admin')).toBe('Yes, with a password')
  expect(value('port')).toBe('Free')
  expect(value('parent')).toBe('Yes')
})

test('the short values of the other kinds of computer', () => {
  const value = (req: Requirement) => byId([req], req.id)?.value
  expect(value(ok('vm_support', 'Can run workloads', 'Containers only: there is no /dev/kvm, so full VMs cannot run (they need virtualization turned on in the BIOS).'))).toBe('Containers only')
  expect(value(ok('vm_support', 'Can run VMs', 'Apple Silicon can.'))).toBe('Apple Silicon')
  expect(value(ok('admin', 'Admin rights (sudo)', 'No. The engine goes in a folder of luca instead of getting its own user.'))).toBe('No')
  expect(value(ok('port', 'Port 9101 free', "MetaService's own program from an earlier install is running there. Adding the computer replaces it."))).toBe('Ours, replaced')
  expect(value(ok('port', 'Port 9101 free', 'Could not check it.'))).toBe('Not checked')
  expect(value(ok('disk', 'Free disk space', '2834 GB free.'))).toBe('2834 GB')
})

test('the labels are short, and a label the panel does not know stays as the parent wrote it', () => {
  expect(byId(linux(), 'agent')?.label).toBe('MetaService program')
  expect(byId(linux(), 'admin')?.label).toBe('Admin rights')
  expect(byId(linux(), 'parent')?.label).toBe('Parent can reach it')
  expect(byId(linux(), 'vm_tool')?.label).toBe('Incus (makes the VMs)')
  expect(byId(linux(), 'port')?.label).toBe('Port 9101 free')
})

test('a cross says one plain sentence, without file paths or commands in it', () => {
  const sentence = (req: Requirement) => byId([req], req.id)?.sentence
  expect(sentence(cross('vm_tool', 'Incus (makes the VMs)', 'Not installed. MetaService needs it to make VMs.'))).toBe('Incus is the tool that makes the VMs. It is not installed on this computer.')
  expect(sentence(cross('vm_tool', "Apple's container tool (makes the VMs)", 'Not installed.'))).toBe("Apple's container tool makes the VMs. It is not installed on this computer.")
  expect(sentence(cross('python', 'Python (runs the chat)', 'Not installed.'))).toBe('Python runs the chat. It is not installed on this computer.')
  expect(sentence(cross('agent', 'MetaService program for this system', 'The parent has no MetaService program for linux-arm64 yet.', 'Put it in the parent\'s state/agent-builds folder'))).toBe('MetaService has no helper program for this kind of computer yet, so it cannot be installed here.')
  expect(sentence(cross('memory', 'Memory', '2048 MB; VMs need at least 4 GB.'))).toBe('This computer has too little memory. VMs need at least 4 GB.')
  expect(sentence(cross('memory', 'Memory', 'Could not read it.'))).toBe('MetaService could not read how much memory this computer has.')
  expect(sentence(cross('disk', 'Free disk space', '3 GB free; VMs need at least 20 GB.'))).toBe('This computer has too little free disk space. VMs need at least 20 GB.')
  expect(sentence(cross('port', 'Port 9101 free', 'Something already listens on 9101. Stop it first, or MetaService cannot start there.'))).toBe('Something else already uses port 9101. Stop it, then check again.')
  expect(sentence(cross('vm_support', 'Can run VMs', "Apple's container tool needs Apple Silicon."))).toBe("Apple's container tool needs a Mac with Apple Silicon.")
  expect(sentence(cross('gpu_toolkit', 'NVIDIA container toolkit', 'Not installed.'))).toBe('This small add-on lets containers use the graphics card. It is missing, but you can still add the machine.')
  expect(sentence(cross('gpu_toolkit', 'NVIDIA container toolkit', 'Not installed. This computer has an NVIDIA GPU (NVIDIA GeForce RTX 5090) but containers cannot use it yet.'))).toBe('This small add-on lets containers use the graphics card (NVIDIA GeForce RTX 5090). It is missing, but you can still add the machine.')
})

test('a Windows computer is a Login tick and a System cross with its own sentence', () => {
  const reqs = [ok('login', 'Login', `Logged in as office. Host key ${KEY}.`), cross('system', 'System', 'Windows is not supported yet. MetaService\'s check and its helper program are made for macOS and Linux; there is no Windows helper.', 'Use a Mac or a Linux computer (x86_64 or ARM).')]
  const rows = checkRows(reqs)
  expect(rows.map((row) => row.state)).toEqual(['ready', 'blocking'])
  expect(rows[1]?.sentence).toBe('Windows is not supported yet. Please use a Linux or Mac computer for now.')
  expect(readyCount(rows)).toEqual({ ready: 1, total: 2 })
  expect(stoppedEarly(rows)).toBe(true)
  expect(stoppedEarly(checkRows(linux()))).toBe(false)
})

test('a system cross on another kind of computer is also plain', () => {
  expect(byId([cross('system', 'System', 'FreeBSD on amd64 is not supported. MetaService runs on macOS and Linux (x86_64 or ARM).')], 'system')?.sentence).toBe('This kind of computer is not supported yet. MetaService runs on Mac and Linux computers.')
})

test('a row the panel does not know falls back to the parent\'s own label, detail and fix', () => {
  const [tick, bad] = checkRows([ok('fan_speed', 'Fan speed', 'Quiet, 1200 rpm, all is well here.'), cross('flux', 'Flux capacitor', 'It is not charged.', 'Charge it, then check again.')])
  expect(tick).toMatchObject({ group: 'other', label: 'Fan speed', value: '', sentence: 'Quiet, 1200 rpm, all is well here.', state: 'ready' })
  expect(bad).toMatchObject({ group: 'other', label: 'Flux capacitor', sentence: 'It is not charged.', state: 'blocking' })
  expect(bad?.manual).toEqual({ text: 'Charge it, then check again.', commands: [] })
  expect(checkCards([tick, bad].flatMap((row) => (row ? [row] : []))).map((card) => card.title)).toEqual(['Other checks'])
})

test('a value that is already short stays, a long unknown detail moves under the label', () => {
  expect(byId([ok('fan_speed', 'Fan speed', 'Quiet.')], 'fan_speed')).toMatchObject({ value: 'Quiet', sentence: '' })
})

test('a known tick whose text is not what the panel expects falls back to the parent\'s sentence', () => {
  expect(byId([ok('memory', 'Memory', 'plenty')], 'memory')).toMatchObject({ value: 'plenty', sentence: '' })
  expect(byId([ok('login', 'Login', 'Welcome back, friend of the house, you are in.')], 'login')).toMatchObject({ value: '', sentence: 'Welcome back, friend of the house, you are in.' })
})

test('the offer to install is carried on the row, and only on a cross', () => {
  const offer = { part: 'vm_tool', needs_password: true }
  const reqs = swap(linux(), { ...cross('vm_tool', 'Incus (makes the VMs)', 'Not installed.'), install: offer })
  expect(byId(reqs, 'vm_tool')?.install).toEqual(offer)
  expect(byId(linux(), 'vm_tool')?.install).toBeUndefined()
})

test('the manual steps split the parent\'s fix into a sentence and the real commands', () => {
  expect(manualSteps('Run `sudo apt install incus`. That works on Debian 13 and Ubuntu 24.04 or newer. Then run `sudo incus admin init --minimal`, and check again.')).toEqual({
    text: 'Run sudo apt install incus. That works on Debian 13 and Ubuntu 24.04 or newer. Then run sudo incus admin init --minimal, and check again.',
    commands: ['sudo apt install incus', 'sudo incus admin init --minimal'],
  })
  expect(manualSteps('Use a Mac or a Linux computer.')).toEqual({ text: 'Use a Mac or a Linux computer.', commands: [] })
  expect(manualSteps(undefined)).toBeNull()
  expect(manualSteps('')).toBeNull()
})

test('the verdict counts what must be fixed and what is only missing', () => {
  expect(verdict(checkRows(linux()))).toEqual({ tone: 'ready', text: 'All 11 checks passed. This computer can be added.' })
  const one = swap(linux(), cross('python', 'Python (runs the chat)', 'Not installed.'))
  expect(verdict(checkRows(one))).toEqual({ tone: 'blocking', text: '1 thing to fix before this computer can be added.' })
  const two = swap(one, cross('vm_tool', 'Incus (makes the VMs)', 'Not installed.'))
  expect(verdict(checkRows(two)).text).toBe('2 things to fix before this computer can be added.')
  const extra = [...linux(), cross('gpu_toolkit', 'NVIDIA container toolkit', 'Not installed.')]
  expect(verdict(checkRows(extra))).toEqual({ tone: 'optional', text: 'Ready to add. One extra is missing, and it does not block adding.' })
  const windows = [ok('login', 'Login', 'Logged in as x.'), cross('system', 'System', 'Windows is not supported yet.')]
  expect(verdict(checkRows(windows))).toEqual({ tone: 'blocking', text: 'This computer cannot be added: this kind of computer is not supported yet.' })
})

test('the machine line lists what is known and leaves out what is not', () => {
  expect(machineLine({ cpu_cores: 32, ram_mb: 63488, disk_free_gb: 79, user: 'luca' })).toBe('32 cores · 62 GB memory · 79 GB free · logged in as luca')
  expect(machineLine({ cpu_cores: null, ram_mb: null, disk_free_gb: null, user: 'office' })).toBe('logged in as office')
  expect(machineLine({ cpu_cores: 8, ram_mb: null, disk_free_gb: null, user: '' })).toBe('8 cores')
})

test('the host key is shortened to its start and end', () => {
  expect(hostKeyShort(KEY)).toBe('SHA256:DmQe…i9Qki0+g')
  expect(hostKeyShort('SHA256:short')).toBe('SHA256:short')
})
