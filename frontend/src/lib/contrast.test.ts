import { test, expect } from 'bun:test'
import { AA_LARGE_TEXT_AND_MARKS, AA_TEXT, contrastRatio, meetsContrast, parseColor } from './contrast.ts'

test('parseColor reads short and long hex colours', () => {
  expect(parseColor('#fff')).toEqual({ r: 255, g: 255, b: 255, a: 1 })
  expect(parseColor('#7DB26B')).toEqual({ r: 125, g: 178, b: 107, a: 1 })
  expect(parseColor(' #053 ')).toEqual({ r: 0, g: 85, b: 51, a: 1 })
})

test('parseColor reads rgb and rgba with or without a leading zero on the alpha', () => {
  expect(parseColor('rgb(10, 20, 30)')).toEqual({ r: 10, g: 20, b: 30, a: 1 })
  expect(parseColor('rgba(17,17,17,.4)')).toEqual({ r: 17, g: 17, b: 17, a: 0.4 })
  expect(parseColor('rgba(255, 255, 255, 0.72)')).toEqual({ r: 255, g: 255, b: 255, a: 0.72 })
})

test('parseColor refuses what it does not know', () => {
  expect(() => parseColor('green')).toThrow('not a colour it can read')
  expect(() => parseColor('#12')).toThrow('not a colour it can read')
  expect(() => parseColor('var(--x)')).toThrow('not a colour it can read')
})

test('contrastRatio matches the published values', () => {
  expect(contrastRatio('#000', '#fff')).toBeCloseTo(21, 5)
  expect(contrastRatio('#fff', '#fff')).toBeCloseTo(1, 5)
  expect(contrastRatio('#777777', '#ffffff')).toBeCloseTo(4.48, 2)
  expect(contrastRatio('#767676', '#ffffff')).toBeCloseTo(4.54, 2)
})

test('contrastRatio does not care which colour is the lighter one', () => {
  expect(contrastRatio('#fff', '#000')).toBeCloseTo(contrastRatio('#000', '#fff'), 8)
})

test('a see-through colour is laid over the background before it is measured', () => {
  const half = contrastRatio('rgba(0,0,0,.5)', '#ffffff')
  expect(half).toBeCloseTo(contrastRatio('#808080', '#ffffff'), 1)
  expect(contrastRatio('rgba(0,0,0,0)', '#ffffff')).toBeCloseTo(1, 5)
})

test('meetsContrast applies the two WCAG AA limits', () => {
  expect(AA_TEXT).toBe(4.5)
  expect(AA_LARGE_TEXT_AND_MARKS).toBe(3)
  expect(meetsContrast('#767676', '#fff', AA_TEXT)).toBe(true)
  expect(meetsContrast('#777777', '#fff', AA_TEXT)).toBe(false)
  expect(meetsContrast('#777777', '#fff', AA_LARGE_TEXT_AND_MARKS)).toBe(true)
})
