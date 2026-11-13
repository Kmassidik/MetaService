import { expect, test } from 'bun:test'
import { DEFAULT_NET_RANGE, NET_RANGES, latencyNoteOf, latencyRangeOf, pollMsOf, windowOf } from './netRange.ts'

test('the switch offers 1 hour, 24 hours, 7 days and 30 days, and opens on the hour', () => {
  expect(NET_RANGES.map((range) => windowOf(range).label)).toEqual(['1 hour', '24 hours', '7 days', '30 days'])
  expect(DEFAULT_NET_RANGE).toBe('1h')
})

test('a range spans its length in seconds', () => {
  expect(windowOf('1h').windowSeconds).toBe(3600)
  expect(windowOf('24h').windowSeconds).toBe(86_400)
  expect(windowOf('30d').windowSeconds).toBe(30 * 86_400)
})

test('the hour is asked for every 10 seconds, the longer ranges every minute', () => {
  expect(pollMsOf('1h')).toBe(10_000)
  expect(NET_RANGES.filter((range) => range !== '1h').map(pollMsOf)).toEqual([60_000, 60_000, 60_000])
})

test('30 days uses the 7 day latency probes and says so', () => {
  expect(latencyRangeOf('30d')).toBe('7d')
  expect(latencyRangeOf('24h')).toBe('24h')
  expect(latencyNoteOf('30d')).toBe('Latency shows the last 7 days.')
  expect(latencyNoteOf('7d')).toBe('')
})
