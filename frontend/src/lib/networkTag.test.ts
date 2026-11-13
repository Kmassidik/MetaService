import { expect, test } from 'bun:test'
import { networkTag } from './networkTag.ts'

test('a machine joined through Share a PC is Shared', () => expect(networkTag('10.77.0.2')).toBe('Shared'))
test('an office address is Same network', () => expect(networkTag('192.168.0.40')).toBe('Same network'))
test('a public address is Other network', () => expect(networkTag('202.51.196.202')).toBe('Other network'))
test('no address gives no tag', () => expect(networkTag(undefined)).toBeNull())
