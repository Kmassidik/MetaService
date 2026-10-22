import { describe, expect, test } from 'bun:test'
import { addedText, addRefusalText, checkPastedKey, connectionLine, MAX_SSH_KEYS, parseSshKeyList, statusLines } from './sshKeys.ts'

const KEY = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample me@laptop'

describe('checking a pasted key', () => {
  test('surrounding spaces and line breaks are trimmed before sending', () => {
    expect(checkPastedKey(`  \n${KEY}\n `)).toEqual({ ok: true, key: KEY })
  })

  test('nothing pasted is not sent', () => {
    expect(checkPastedKey(' \n ')).toEqual({ ok: false, text: 'Paste a public key first.' })
  })

  test('a private key is refused and never sent', () => {
    const result = checkPastedKey('-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaA\n-----END OPENSSH PRIVATE KEY-----')
    expect(result.ok).toBe(false)
    expect(result.ok ? '' : result.text).toContain('private key')
  })

  test('a key whose comment mentions nothing odd passes', () => {
    expect(checkPastedKey('ssh-rsa AAAAB3 build-box').ok).toBe(true)
  })
})

describe('refusal words', () => {
  test('duplicate and too many have our own plain text', () => {
    expect(addRefusalText({ code: 'duplicate_key', message: 'x' })).toBe('This key is already on this VM.')
    expect(addRefusalText({ code: 'too_many_keys', message: 'x' })).toContain(`${MAX_SSH_KEYS} keys`)
  })

  test('any other refusal shows the parent words', () => {
    expect(addRefusalText({ code: 'error', message: 'That is not a public key.' })).toBe('That is not a public key.')
  })
})

describe('status lines under the list', () => {
  test('applied and sshd running or unknown: nothing to say', () => {
    expect(statusLines({ applied: true, sshd: 'running' }, 'running')).toEqual([])
    expect(statusLines({ applied: true, sshd: 'unknown' }, 'stopped')).toEqual([])
  })

  test('not applied while the VM is stopped: it will be written when it runs', () => {
    expect(statusLines({ applied: false, sshd: 'unknown' }, 'stopped')).toEqual(['Saved. It will be written into the VM when the VM is running.'])
  })

  test('not applied while the VM runs: the machine did not answer', () => {
    expect(statusLines({ applied: false, sshd: 'unknown' }, 'running')).toEqual(['Saved, not applied yet: the machine did not answer. It will retry.'])
  })

  test('sshd missing and installed each have a line, after the applied line', () => {
    expect(statusLines({ applied: false, sshd: 'missing' }, 'stopped')[1]).toContain('No SSH server was found')
    expect(statusLines({ applied: true, sshd: 'installed' }, 'running')).toEqual(['An SSH server is installed in this VM but not running.'])
  })
})

describe('reading the answer', () => {
  const body = { keys: [{ id: 'k1', type: 'ssh-ed25519', fingerprint: 'SHA256:abc', comment: 'me@laptop', added_at: 1_700_000_000 }], applied: true, sshd: 'running' }

  test('a good answer is read as it is', () => {
    expect(parseSshKeyList(body)).toEqual(body)
  })

  test('an unreadable key is dropped, an odd sshd becomes unknown, a missing applied is false', () => {
    const odd = parseSshKeyList({ keys: [body.keys[0], { id: 7 }], sshd: 'weird' })
    expect(odd?.keys).toHaveLength(1)
    expect(odd?.sshd).toBe('unknown')
    expect(odd?.applied).toBe(false)
  })

  test('an answer with no key list is not an answer', () => {
    expect(parseSshKeyList({})).toBeNull()
    expect(parseSshKeyList(null)).toBeNull()
  })
})

describe('small formatting', () => {
  test('the added time counts from Unix seconds', () => {
    const added = 1_700_000_000
    expect(addedText({ added_at: added }, (added + 3 * 3600) * 1000)).toBe('3h ago')
  })

  test('the connection line needs an address', () => {
    expect(connectionLine('10.0.0.5')).toBe('ssh root@10.0.0.5')
    expect(connectionLine(null)).toBeNull()
    expect(connectionLine('')).toBeNull()
  })
})
