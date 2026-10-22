import { test, expect } from 'bun:test'
import { UnreadableAnswer, parseMachineExtras } from './machineDetail.ts'

test('the real mac-studio answer: everything the helper did not report is null', () => {
  const answer = { id: 'mac-studio', name: 'mac-studio', agent_version: null, engine: null, box: null, agent_port: null, ruvio: null }
  expect(parseMachineExtras(answer)).toEqual({ agent_version: null, agent_build: null, engine: null, box: null, agent_port: null, ruvio: null })
})

test('a full answer is read', () => {
  const answer = {
    agent_version: '0.3.0', agent_build: 'a'.repeat(64), update: { available: true, current_build: 'a'.repeat(64), newest_build: 'b'.repeat(64), reason: null },
    engine: { name: 'apple', version: '1.5.0', ready: true }, box: '~/metaservice-box', agent_port: 8447,
    ruvio: { installed: '0.4.0', pinned: '0.4.0', state: 'on' },
  }
  expect<unknown>(parseMachineExtras(answer)).toEqual(answer)
})

test('a parent that sends no update leaves it out, and one that sends a broken update is refused', () => {
  expect('update' in parseMachineExtras({})).toBe(false)
  expect(() => parseMachineExtras({ update: { available: 'yes' } })).toThrow(UnreadableAnswer)
  expect(() => parseMachineExtras({ agent_build: 5 })).toThrow(UnreadableAnswer)
})

test('fields left out are null, an engine with no version keeps its name', () => {
  expect<unknown>(parseMachineExtras({ engine: { name: 'incus', ready: false } })).toEqual({ agent_version: null, agent_build: null, engine: { name: 'incus', version: null, ready: false }, box: null, agent_port: null, ruvio: null })
})

test('every state of Ruvio is accepted, an unknown one is refused', () => {
  for (const state of ['unavailable', 'off', 'on', 'outdated', 'installing', 'removing']) expect(parseMachineExtras({ ruvio: { installed: null, pinned: null, state } }).ruvio?.state).toBe<string | undefined>(state)
  expect(() => parseMachineExtras({ ruvio: { installed: null, pinned: null, state: 'exploding' } })).toThrow(UnreadableAnswer)
})

test('a wrong shape is refused, not trusted', () => {
  for (const bad of [null, 'text', 7, [], { agent_version: 5 }, { box: {} }, { agent_port: '8447' }, { agent_port: 1.5 }, { engine: 'apple' }, { engine: { name: 'apple' } }, { engine: { name: 1, ready: true } }, { engine: { name: 'a', ready: true, version: 3 } }, { ruvio: 'on' }, { ruvio: { state: 'on', installed: 4 } }]) {
    expect(() => parseMachineExtras(bad)).toThrow(UnreadableAnswer)
  }
})
