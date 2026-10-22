import { describe, expect, test } from 'bun:test'
import { parseSshKeyList } from './sshKeys.ts'
import { DEFAULT_JUMP_NOTE, FAILED_FALLBACK_TEXT, NO_JUMP_TEXT, NO_VM_ADDRESS_TEXT, parseConnect, parseProgress, setupBlock, shouldPoll, SSH_POLL_MS } from './sshSetup.ts'
import type { SshConnect, SshKeyList } from './types.ts'

const COMMAND = 'ssh -J you@203.0.113.7 root@10.0.0.1'
const CONNECT: SshConnect = { jump: 'you@203.0.113.7', jumpIsDefault: false, vmAddress: '10.0.0.1', command: COMMAND }

const list = (extra: Partial<SshKeyList> = {}): SshKeyList => ({ keys: [], applied: true, sshd: 'running', sshdState: 'idle', sshdMessage: null, connect: CONNECT, ...extra })

describe('reading the new fields', () => {
  test('a full answer is read as it is', () => {
    const body = { keys: [], applied: true, sshd: 'running', sshd_state: 'installing', sshd_message: 'working', connect: { jump: 'you@h', jump_is_default: true, vm_address: '10.0.0.2', command: 'ssh -J you@h root@10.0.0.2' } }
    expect(parseSshKeyList(body)).toMatchObject({ sshdState: 'installing', sshdMessage: 'working', connect: { jump: 'you@h', jumpIsDefault: true, vmAddress: '10.0.0.2', command: 'ssh -J you@h root@10.0.0.2' } })
  })

  test('missing or unknown fields from an old parent mean idle, no message and no connect', () => {
    expect(parseSshKeyList({ keys: [], applied: true, sshd: 'running' })).toMatchObject({ sshdState: 'idle', sshdMessage: null, connect: null })
    expect(parseProgress('weird')).toBe('idle')
    expect(parseProgress(undefined)).toBe('idle')
    expect(parseProgress('failed')).toBe('failed')
  })

  test('connect fields that are null, empty or odd become null; a connect that is not an object is missing', () => {
    expect(parseConnect({ jump: null, jump_is_default: false, vm_address: '', command: 5 })).toEqual({ jump: null, jumpIsDefault: false, vmAddress: null, command: null })
    expect(parseConnect('x')).toBeNull()
    expect(parseConnect([])).toBeNull()
  })
})

describe('when the dialog asks again', () => {
  test('only while installing, every 3 seconds', () => {
    expect(shouldPoll(list({ sshdState: 'installing' }))).toBe(true)
    expect(shouldPoll(list({ sshdState: 'idle' }))).toBe(false)
    expect(shouldPoll(list({ sshdState: 'failed' }))).toBe(false)
    expect(shouldPoll(null)).toBe(false)
    expect(SSH_POLL_MS).toBe(3000)
  })
})

describe('which block shows', () => {
  test('nothing before the list is read', () => {
    expect(setupBlock(null, 'running')).toEqual({ kind: 'none' })
  })

  test('installing wins over everything, even a not yet applied list', () => {
    expect(setupBlock(list({ sshdState: 'installing', applied: false, sshd: 'missing' }), 'running')).toEqual({ kind: 'installing' })
  })

  test('failed shows the parent message, or a plain fallback', () => {
    expect(setupBlock(list({ sshdState: 'failed', sshdMessage: 'apt failed' }), 'running')).toEqual({ kind: 'failed', message: 'apt failed' })
    expect(setupBlock(list({ sshdState: 'failed' }), 'running')).toEqual({ kind: 'failed', message: FAILED_FALLBACK_TEXT })
  })

  test('ready needs applied, a running SSH server, idle and a running VM', () => {
    expect(setupBlock(list(), 'running')).toEqual({ kind: 'ready', command: COMMAND, jumpIsDefault: false })
    expect(setupBlock(list({ applied: false }), 'running')).toEqual({ kind: 'none' })
    expect(setupBlock(list({ sshd: 'installed' }), 'running')).toEqual({ kind: 'none' })
    expect(setupBlock(list({ sshd: 'missing' }), 'running')).toEqual({ kind: 'none' })
    expect(setupBlock(list(), 'stopped')).toEqual({ kind: 'none' })
  })

  test('the office address is flagged so the dialog can say where it comes from', () => {
    expect(setupBlock(list({ connect: { ...CONNECT, jumpIsDefault: true } }), 'running')).toEqual({ kind: 'ready', command: COMMAND, jumpIsDefault: true })
    expect(DEFAULT_JUMP_NOTE).toContain('Environment')
  })

  test('no command: no VM address is its own reason, no jump sends to Environment', () => {
    expect(setupBlock(list({ connect: { jump: 'you@h', jumpIsDefault: false, vmAddress: null, command: null } }), 'running')).toEqual({ kind: 'no-command', text: NO_VM_ADDRESS_TEXT, needsEnvironment: false })
    expect(setupBlock(list({ connect: { jump: null, jumpIsDefault: false, vmAddress: '10.0.0.1', command: null } }), 'running')).toEqual({ kind: 'no-command', text: NO_JUMP_TEXT, needsEnvironment: true })
  })

  test('an old parent without connect keeps the old plain line', () => {
    expect(setupBlock(list({ connect: null }), 'running')).toEqual({ kind: 'legacy' })
    expect(setupBlock(list({ connect: null, applied: false }), 'stopped')).toEqual({ kind: 'legacy' })
  })
})
