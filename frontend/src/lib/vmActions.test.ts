import { describe, expect, test } from 'bun:test'
import { vmActionFacts, vmActions } from './vmActions.ts'

describe('the action buttons of a VM row', () => {
  test('a running VM with no chat: Terminal, Stop, Install chat, then Delete alone and last', () => {
    expect(vmActions({ state: 'running', chatInstalled: false })).toEqual({ main: ['terminal', 'stop', 'install-chat'], danger: ['delete'] })
  })

  test('a running VM with a chat adds Open chat between Stop and Install chat', () => {
    expect(vmActions({ state: 'running', chatInstalled: true }).main).toEqual(['terminal', 'stop', 'open-chat', 'install-chat'])
  })

  test('a stopped VM offers Start, and no Install chat', () => {
    expect(vmActions({ state: 'stopped', chatInstalled: false }).main).toEqual(['terminal', 'start'])
  })

  test('a stopped VM with a chat still offers Open chat', () => {
    expect(vmActions({ state: 'stopped', chatInstalled: true }).main).toEqual(['terminal', 'start', 'open-chat'])
  })

  test('a VM being made has Terminal (switched off by its own rules) and Delete only', () => {
    expect(vmActions({ state: 'creating', chatInstalled: false })).toEqual({ main: ['terminal'], danger: ['delete'] })
  })

  test('Delete is never in the main group and never missing', () => {
    for (const state of ['running', 'stopped', 'creating', 'failed']) {
      const layout = vmActions({ state, chatInstalled: true })
      expect(layout.main).not.toContain('delete')
      expect(layout.danger).toEqual(['delete'])
    }
  })

  test('the facts come from the workload: an empty bundle version means no chat', () => {
    expect(vmActionFacts({ state: 'running', bundle_version: null })).toEqual({ state: 'running', chatInstalled: false })
    expect(vmActionFacts({ state: 'running', bundle_version: '0.3.0' }).chatInstalled).toBe(true)
  })
})
