import { describe, expect, test } from 'bun:test'
import { MACHINE_OFFLINE_REASON, MACHINE_UNREACHABLE_TEXT, isMachineOffline, refusalMessage, stateClass, stateWords } from './machineOffline.ts'
import { vmRowTone, vmStateText, vmTone } from './vmList.ts'

describe('machine offline helpers', () => {
  test('only the offline state is offline', () => {
    expect(isMachineOffline('offline')).toBe(true)
    expect(isMachineOffline('online')).toBe(false)
    expect(isMachineOffline('busy')).toBe(false)
    expect(isMachineOffline(undefined)).toBe(false)
  })

  test('the reason is the short sentence', () => {
    expect(MACHINE_OFFLINE_REASON).toBe('This machine is offline.')
  })

  test('machine_unreachable becomes the friendly text, whatever the message', () => {
    expect(refusalMessage('machine_unreachable', 'anything')).toBe(MACHINE_UNREACHABLE_TEXT)
  })

  test('the raw message alone is also mapped, with or without a full stop or capital', () => {
    expect(refusalMessage('error', 'the machine could not be reached')).toBe(MACHINE_UNREACHABLE_TEXT)
    expect(refusalMessage(undefined, 'The machine could not be reached.')).toBe(MACHINE_UNREACHABLE_TEXT)
  })

  test('other refusals keep their own words', () => {
    expect(refusalMessage('not_found', 'No such VM.')).toBe('No such VM.')
  })

  test('state words get (last known) only on an offline machine', () => {
    expect(stateWords('running', 'offline')).toBe('running (last known)')
    expect(stateWords('running', 'online')).toBe('running')
    expect(stateWords('Deleting…', 'offline')).toBe('Deleting…')
  })

  test('the tag colour is dropped on an offline machine', () => {
    expect(stateClass('run', 'offline')).toBe('')
    expect(stateClass('run', 'online')).toBe('run')
  })

  test('the VM list words and colour follow the machine', () => {
    expect(vmStateText('running', 'offline')).toBe('running (last known)')
    expect(vmStateText('running')).toBe('running')
    expect(vmStateText('deleting', 'offline')).toBe('Deleting…')
    expect(vmRowTone('running', 'offline')).toBe('')
    expect(vmRowTone('running', 'online')).toBe('online')
    expect(vmTone('running')).toBe('online')
  })
})
