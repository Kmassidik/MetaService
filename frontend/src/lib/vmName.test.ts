import { expect, test } from 'bun:test'
import { nameProblem } from './format.ts'
import { generateVmName, nameToSend } from './vmName.ts'

/** A random source that answers from a list, then repeats the last answer. */
const fixed = (...values: number[]) => {
  let at = 0
  return () => values[Math.min(at++, values.length - 1)] ?? 0
}

test('a generated name is "vm-" and four lowercase hex characters', () => {
  const name = generateVmName(fixed(0, 0.0625, 0.999, 0.5), new Set())
  expect(name).toBe('vm-01f8')
  expect(name).toMatch(/^vm-[0-9a-f]{4}$/)
})

test('a generated name passes the same name check as a typed one, for many random sources', () => {
  for (let seed = 0; seed < 200; seed++) expect(nameProblem(generateVmName(Math.random, new Set())), String(seed)).toBeNull()
})

test('the same random source gives the same name', () => {
  expect(generateVmName(fixed(0.3, 0.6, 0.9, 0.1), new Set())).toBe(generateVmName(fixed(0.3, 0.6, 0.9, 0.1), new Set()))
})

test('a name the machine already has is not given again', () => {
  const answers = [0, 0, 0, 0, 0.5, 0.5, 0.5, 0.5]
  expect(generateVmName(fixed(...answers), new Set(['vm-0000']))).toBe('vm-8888')
})

test('when every try at four characters is taken, a longer name is used', () => {
  expect(generateVmName(() => 0, new Set(['vm-0000']))).toBe('vm-00000')
})

test('a typed name is kept and an empty one is replaced', () => {
  expect(nameToSend('build-box', fixed(0), new Set())).toBe('build-box')
  expect(nameToSend('', fixed(0), new Set())).toBe('vm-0000')
})
