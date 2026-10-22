import { test, expect } from 'bun:test'
import { OWL_NAMES, owlFor } from './owls.ts'

const SOURCE_PX = 512

test('every owl has a WebP picture', () => {
  for (const name of OWL_NAMES) expect(owlFor(name).src).toMatch(/\.webp$/)
})

test('no owl is drawn larger than its 512 px picture', () => {
  for (const name of OWL_NAMES) {
    const { size } = owlFor(name)
    expect(size).toBeGreaterThan(0)
    expect(size).toBeLessThanOrEqual(SOURCE_PX)
  }
})

test('every owl has its own picture', () => {
  const sources = OWL_NAMES.map((name) => owlFor(name).src)
  expect(new Set(sources).size).toBe(OWL_NAMES.length)
})

test('the empty states and the error screen share one size; offline is smaller, busy smaller still', () => {
  expect(owlFor('emptyMachines').size).toBe(owlFor('emptyVms').size)
  expect(owlFor('notFound').size).toBe(owlFor('emptyVms').size)
  expect(owlFor('offline').size).toBeLessThan(owlFor('emptyVms').size)
  expect(owlFor('busy').size).toBeLessThan(owlFor('offline').size)
})
