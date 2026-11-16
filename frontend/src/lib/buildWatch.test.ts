import { expect, test } from 'bun:test'
import { buildOf, isOutdated, latestBuild } from './buildWatch.ts'

test('the build is the script name in the page', () => {
  expect(buildOf('<script type="module" src="/assets/index-B2NS1so-.js"></script>')).toBe('assets/index-B2NS1so-.js')
  expect(buildOf('<html>development</html>')).toBeNull()
})

test('a page is old only when both builds are known and differ', () => {
  expect(isOutdated('assets/index-a.js', 'assets/index-b.js')).toBe(true)
  expect(isOutdated('assets/index-a.js', 'assets/index-a.js')).toBe(false)
  expect(isOutdated(null, 'assets/index-b.js')).toBe(false)
  expect(isOutdated('assets/index-a.js', null)).toBe(false)
})

test('an answer that cannot be read is not known, never old', async () => {
  const failing = (async () => { throw new Error('offline') }) as unknown as typeof fetch
  const refused = (async () => new Response('no', { status: 500 })) as unknown as typeof fetch
  const fine = (async () => new Response('<script src="/assets/index-z.js"></script>')) as unknown as typeof fetch
  expect(await latestBuild(failing)).toBeNull()
  expect(await latestBuild(refused)).toBeNull()
  expect(await latestBuild(fine)).toBe('assets/index-z.js')
})
