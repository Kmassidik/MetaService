import { describe, expect, test } from 'bun:test'
import { UNKNOWN_TIME, UTC_ZONE, formatTime, makeTimeFormat, timeTitle, zoneName } from './securityTime.ts'

const WINTER = '2026-01-15T08:47:00Z'
const SUMMER = '2026-07-15T08:47:00Z'

describe('formatTime', () => {
  test('UTC keeps the time as given', () => {
    expect(formatTime(WINTER, UTC_ZONE)).toBe('2026-01-15 08:47 UTC')
  })
  test('Jakarta is seven hours ahead all year', () => {
    expect(formatTime(WINTER, 'Asia/Jakarta')).toBe('2026-01-15 15:47 GMT+7')
    expect(formatTime(SUMMER, 'Asia/Jakarta')).toBe('2026-07-15 15:47 GMT+7')
  })
  test('a zone with half hours and no daylight saving', () => {
    expect(formatTime(WINTER, 'Asia/Kolkata')).toBe('2026-01-15 14:17 GMT+5:30')
  })
  test('a daylight saving zone moves with the season', () => {
    expect(formatTime(WINTER, 'America/New_York')).toBe('2026-01-15 03:47 EST')
    expect(formatTime(SUMMER, 'America/New_York')).toBe('2026-07-15 04:47 EDT')
  })
  test('the date changes with the zone', () => {
    expect(formatTime('2026-12-31T20:00:00Z', 'Asia/Jakarta')).toBe('2027-01-01 03:00 GMT+7')
  })
  test('midnight is 00, not 24', () => {
    expect(formatTime('2026-01-15T00:05:00Z', UTC_ZONE)).toBe('2026-01-15 00:05 UTC')
  })
  test('a date that cannot be read is "unknown" and never throws', () => {
    for (const bad of ['', 'nonsense', null, undefined, '2026-13-45']) expect(formatTime(bad, 'Asia/Jakarta')).toBe(UNKNOWN_TIME)
  })
  test('a zone the browser does not know is shown as UTC and says so', () => {
    expect(formatTime(WINTER, 'Nowhere/Atlantis')).toBe('2026-01-15 08:47 UTC')
  })
})

describe('zoneName, timeTitle and makeTimeFormat', () => {
  test('the zone name follows daylight saving', () => {
    expect(zoneName('America/New_York', Date.parse(WINTER))).toBe('EST')
    expect(zoneName('America/New_York', Date.parse(SUMMER))).toBe('EDT')
    expect(zoneName('Nowhere/Atlantis', Date.parse(SUMMER))).toBe('UTC')
    expect(zoneName(UTC_ZONE, Number.NaN)).toBe('UTC')
  })
  test('the tooltip starts with the UTC time and adds the local one', () => {
    expect(timeTitle(WINTER, 'Asia/Jakarta')).toBe('2026-01-15 08:47 UTC (2026-01-15 15:47 GMT+7)')
    expect(timeTitle(WINTER, UTC_ZONE)).toBe('2026-01-15 08:47 UTC')
    expect(timeTitle('nonsense', 'Asia/Jakarta')).toBe(UNKNOWN_TIME)
  })
  test('Local uses the injected zone, UTC ignores it', () => {
    const local = makeTimeFormat('local', 'Asia/Jakarta', Date.parse(WINTER))
    const utc = makeTimeFormat('utc', 'Asia/Jakarta', Date.parse(WINTER))
    expect([local.label, local.show(WINTER)]).toEqual(['GMT+7', '2026-01-15 15:47 GMT+7'])
    expect([utc.label, utc.show(WINTER)]).toEqual(['UTC', '2026-01-15 08:47 UTC'])
    expect(local.title(WINTER)).toBe(utc.title(WINTER))
  })
})
