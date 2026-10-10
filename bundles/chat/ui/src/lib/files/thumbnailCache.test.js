import { describe, expect, it } from 'vitest'
import { createThumbnailCache } from './thumbnailCache.js'

function deferred() {
  let resolve, reject
  const promise = new Promise((ok, fail) => { resolve = ok; reject = fail })
  return { promise, resolve, reject }
}

/** A cache whose downloads finish only when the test says so. */
function harness(maxConcurrent = 2) {
  const loads = []
  const revoked = []
  let made = 0
  const cache = createThumbnailCache({
    maxConcurrent,
    load: (file, signal) => {
      const pending = deferred()
      loads.push({ id: file.id, signal, ...pending })
      return pending.promise
    },
    createUrl: () => `blob:${++made}`,
    revokeUrl: url => revoked.push(url),
  })
  return { cache, loads, revoked }
}

const file = id => ({ id })
const flush = () => new Promise(resolve => setTimeout(resolve, 0))

describe('thumbnail cache', () => {
  it('downloads a picture once and reuses its URL', async () => {
    const { cache, loads } = harness()
    const first = cache.get(file('a'))
    const again = cache.get(file('a'))
    expect(loads).toHaveLength(1)
    loads[0].resolve(new Blob(['x']))
    expect(await first).toBe('blob:1')
    expect(await again).toBe('blob:1')
    expect(await cache.get(file('a'))).toBe('blob:1')
    expect(loads).toHaveLength(1)
    expect(cache.peek('a')).toBe('blob:1')
  })

  it('runs at most maxConcurrent downloads and starts the next when one ends', async () => {
    const { cache, loads } = harness(2)
    const urls = ['a', 'b', 'c', 'd'].map(id => cache.get(file(id)))
    expect(loads.map(load => load.id)).toEqual(['a', 'b'])
    loads[0].resolve(new Blob(['a']))
    await urls[0]
    await flush()
    expect(loads.map(load => load.id)).toEqual(['a', 'b', 'c'])
    loads[1].reject(new Error('offline'))
    await expect(urls[1]).rejects.toThrow('offline')
    await flush()
    expect(loads.map(load => load.id)).toEqual(['a', 'b', 'c', 'd'])
  })

  it('retries a failed picture on the next request', async () => {
    const { cache, loads } = harness()
    const failed = cache.get(file('a'))
    loads[0].reject(new Error('offline'))
    await expect(failed).rejects.toThrow('offline')
    const retried = cache.get(file('a'))
    expect(loads).toHaveLength(2)
    loads[1].resolve(new Blob(['a']))
    expect(await retried).toBe('blob:1')
  })

  it('uses seeded upload bytes without downloading', async () => {
    const { cache, loads } = harness()
    cache.seed('a', new Blob(['local']))
    expect(await cache.get(file('a'))).toBe('blob:1')
    expect(loads).toHaveLength(0)
  })

  it('revokes a deleted file and downloads it again if asked', async () => {
    const { cache, loads, revoked } = harness()
    cache.seed('a', new Blob(['x']))
    cache.forget('a')
    expect(revoked).toEqual(['blob:1'])
    expect(cache.peek('a')).toBe('')
    cache.get(file('a'))
    expect(loads).toHaveLength(1)
  })

  it('ends the session: aborts downloads, drops waiting ones and revokes every URL', async () => {
    const { cache, loads, revoked } = harness(1)
    cache.seed('kept', new Blob(['x']))
    const running = cache.get(file('a'))
    const waiting = cache.get(file('b'))
    cache.clear()
    expect(loads[0].signal.aborted).toBe(true)
    expect(revoked).toEqual(['blob:1'])
    await expect(waiting).rejects.toThrow('cleared')
    loads[0].resolve(new Blob(['late']))
    await expect(running).rejects.toThrow('cleared')
    expect(cache.peek('a')).toBe('')
    expect(loads).toHaveLength(1)
  })
})
