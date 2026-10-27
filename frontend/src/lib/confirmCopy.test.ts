import { describe, expect, test } from 'bun:test'
import { deleteVmCopy, removeMachineCopy, removeRemoteMachineCopy, removeSshKeyCopy } from './confirmCopy.ts'

describe('confirm dialog words', () => {
  test('Delete VM names the VM and its machine and says a backup is made first', () => {
    const copy = deleteVmCopy({ name: 'studio' }, { name: 'build-box' })
    expect(copy.what).toBe('build-box on studio will be stopped and deleted.')
    expect(copy.consequence).toContain('backup')
    expect(copy.confirmLabel).toBe('Delete VM')
    expect(copy.doneLabel).toBe('Delete started')
  })

  test('Remove machine names the machine and says its VMs keep running', () => {
    const copy = removeMachineCopy({ name: 'mac-mini' })
    expect(copy.what).toContain('mac-mini')
    expect(copy.consequence).toContain('VMs keep running')
    expect(copy.confirmLabel).toBe('Remove machine')
  })

  test('Remove key names the VM and says the key goes straight away', () => {
    const copy = removeSshKeyCopy({ name: 'vm1' })
    expect(copy.what).toBe('This key can no longer log in to vm1.')
    expect(copy.consequence).toBe('It is removed from the VM straight away if the VM is running.')
    expect(copy.confirmLabel).toBe('Remove key')
  })

  test('removing a machine installed over SSH says where it was installed and keeps the same red verb', () => {
    const copy = removeRemoteMachineCopy({ name: 'box' }, { ssh_user: 'dalang', host: '10.0.0.5' })
    expect(copy.what).toContain('dalang@10.0.0.5')
    expect(copy.confirmLabel).toBe('Remove machine')
  })
})
