import { expect, test } from 'bun:test'
import { parseExternalServices } from './externalServices.ts'
import type { ExternalService, ExternalServicesReply } from './types.ts'
import { UnreadableAnswer } from './unreadable.ts'

const service = (extra: Record<string, unknown> = {}) => ({ id: 'docker:abc123', name: 'postgres', runtime: 'docker', kind: 'container', state: 'running', image: 'postgres:18', ...extra } as ExternalService)
const answer = (extra: Record<string, unknown> = {}) => ({ services: [service()], warnings: [{ runtime: 'incus', message: 'Could not list instances.' }], ...extra })

test('discovery keeps external services and warnings in their own model', () => {
  expect(parseExternalServices(answer({
    services: [
      service(),
      service({ id: 'incus:build', name: 'build', runtime: 'incus', kind: 'vm', state: 'stopped', image: undefined }),
      service({ id: 'apple:uuid', name: 'mac guest', runtime: 'apple', kind: 'vm', state: 'unknown', image: null }),
    ],
  }))).toEqual({
    services: [
      service(),
      { id: 'incus:build', name: 'build', runtime: 'incus', kind: 'vm', state: 'stopped', image: null },
      { id: 'apple:uuid', name: 'mac guest', runtime: 'apple', kind: 'vm', state: 'unknown', image: null },
    ],
    warnings: [{ runtime: 'incus', message: 'Could not list instances.' }],
  } satisfies ExternalServicesReply)
  expect(parseExternalServices({ services: [], warnings: [] })).toEqual({ services: [], warnings: [] })
})

test('missing lists and malformed services are unreadable, never an empty discovery', () => {
  const bad: unknown[] = [null, {}, { services: [] }, { warnings: [] }, answer({ services: null }), answer({ warnings: null }), answer({ services: [null] })]
  for (const value of bad) expect(() => parseExternalServices(value)).toThrow(UnreadableAnswer)
})

test('only promised runtime, kind and state words are accepted', () => {
  for (const key of ['runtime', 'kind', 'state']) expect(() => parseExternalServices(answer({ services: [service({ [key]: 'future' })] }))).toThrow(UnreadableAnswer)
  expect(() => parseExternalServices(answer({ warnings: [{ runtime: 'other', message: 'warning' }] }))).toThrow(UnreadableAnswer)
})

test('required text and optional image are checked', () => {
  for (const key of ['id', 'name']) expect(() => parseExternalServices(answer({ services: [service({ [key]: 7 })] }))).toThrow(UnreadableAnswer)
  expect(() => parseExternalServices(answer({ services: [service({ image: 7 })] }))).toThrow(UnreadableAnswer)
  expect(() => parseExternalServices(answer({ warnings: [{ runtime: 'docker', message: null }] }))).toThrow(UnreadableAnswer)
})
