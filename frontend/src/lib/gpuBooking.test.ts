import { expect, test } from 'bun:test'
import { bookingPercent, bookingText, limitChipText, limitRowText, readGpuBooking, readGpuMemoryGb } from './gpuBooking.ts'

const BOOKING = { total_gb: 31, booked_gb: 8, free_gb: 23 }

test('a booking in the promised shape is read', () => {
  expect(readGpuBooking(BOOKING)).toEqual(BOOKING)
})

test('a wrong shape becomes null', () => {
  for (const junk of [null, undefined, 'x', 7, [], {}, { total_gb: 31, booked_gb: 8 }, { ...BOOKING, free_gb: '23' }, { ...BOOKING, booked_gb: -1 }, { ...BOOKING, total_gb: Number.NaN }]) {
    expect(readGpuBooking(junk)).toBeNull()
  }
})

test('a VM limit is a positive whole number or null', () => {
  expect(readGpuMemoryGb(4)).toBe(4)
  for (const junk of [null, undefined, 0, -2, 1.5, '4', {}]) expect(readGpuMemoryGb(junk)).toBeNull()
})

test('the booking line says what is booked and what is free', () => {
  expect(bookingText(BOOKING)).toBe('Booked for VMs: 8 of 31 GB · free 23 GB')
  expect(bookingText({ total_gb: 31, booked_gb: 0, free_gb: 31 })).toBe('Booked for VMs: none · 31 GB free')
})

test('the bar is the booked share of the card, capped at full', () => {
  expect(bookingPercent({ total_gb: 32, booked_gb: 8, free_gb: 24 })).toBe(25)
  expect(bookingPercent({ total_gb: 32, booked_gb: 40, free_gb: 0 })).toBe(100)
  expect(bookingPercent({ total_gb: 0, booked_gb: 0, free_gb: 0 })).toBe(0)
})

test('the chip and the row name the limit', () => {
  expect(limitChipText(4)).toBe('GPU 4 GB')
  expect(limitRowText(4)).toBe('4 GB (booked)')
})
