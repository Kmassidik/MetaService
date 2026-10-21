import { test, expect } from 'bun:test'
import { readTokens, resolveTokens } from './paletteTokens.ts'

const CSS = `
/* the palette */
:root { --a: #111; --b: var(--a); --c: rgba(1,2,3,.5); --size: 4px }
.other { --not-a-token-block: 1 }
:root { --d: var(--b) }
`

test('readTokens reads every :root block and nothing else', () => {
  expect(readTokens(CSS)).toEqual({ '--a': '#111', '--b': 'var(--a)', '--c': 'rgba(1,2,3,.5)', '--size': '4px', '--d': 'var(--b)' })
})

test('comments and rules of other selectors are ignored', () => {
  expect(readTokens('/* :root { --x: red } */ .box { --y: blue } :root { --z: #000 }')).toEqual({ '--z': '#000' })
})

test('a rule that lists :root among others still counts', () => {
  expect(readTokens(':root, .dark { --q: #fff }')).toEqual({ '--q': '#fff' })
})

test('resolveTokens follows references to the final value', () => {
  const resolved = resolveTokens(readTokens(CSS))
  expect(resolved['--b']).toBe('#111')
  expect(resolved['--d']).toBe('#111')
  expect(resolved['--c']).toBe('rgba(1,2,3,.5)')
})

test('a missing token and a circle are errors', () => {
  expect(() => resolveTokens(readTokens(':root { --a: var(--gone) }'))).toThrow('the token --gone is not set')
  expect(() => resolveTokens(readTokens(':root { --a: var(--b); --b: var(--a) }'))).toThrow('in a circle')
})
