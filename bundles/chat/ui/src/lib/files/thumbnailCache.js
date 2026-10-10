/**
 * Object URLs for pictures, one per file id for the whole session, so a picture is downloaded at
 * most once however often it is shown (composer, message, Files tab, viewer). At most
 * `maxConcurrent` downloads run at a time; the rest wait in order. `clear()` ends the session:
 * it aborts downloads, drops waiting ones and revokes every URL.
 * `load(file, signal)` returns a Blob; it owns the type and size checks.
 */
export const MAX_CONCURRENT_DOWNLOADS = 3

export class CacheClearedError extends Error {
  constructor() {
    super('The picture cache was cleared.')
    this.name = 'AbortError'
  }
}

class ThumbnailCache {
  #urls = new Map()
  #inFlight = new Map()
  #waiting = []
  #running = 0
  #session = new AbortController()

  constructor({ load, maxConcurrent, createUrl, revokeUrl }) {
    this.load = load
    this.maxConcurrent = maxConcurrent
    this.createUrl = createUrl
    this.revokeUrl = revokeUrl
  }

  /** Resolves to the picture's object URL, downloading it once. */
  get(file) {
    if (this.#urls.has(file.id)) return Promise.resolve(this.#urls.get(file.id))
    if (this.#inFlight.has(file.id)) return this.#inFlight.get(file.id)
    const promise = this.#download(file).finally(() => {
      if (this.#inFlight.get(file.id) === promise) this.#inFlight.delete(file.id)
    })
    this.#inFlight.set(file.id, promise)
    return promise
  }

  /** The URL if it is already known, without downloading. */
  peek(id) {
    return this.#urls.get(id) || ''
  }

  /** Uses bytes the browser already has (a finished upload) instead of downloading them again. */
  seed(id, blob) {
    if (!this.#urls.has(id)) this.#urls.set(id, this.createUrl(blob))
  }

  forget(id) {
    if (this.#urls.has(id)) this.revokeUrl(this.#urls.get(id))
    this.#urls.delete(id)
  }

  clear() {
    this.#session.abort()
    this.#session = new AbortController()
    for (const job of this.#waiting) job.reject(new CacheClearedError())
    this.#waiting = []
    this.#inFlight.clear()
    for (const url of this.#urls.values()) this.revokeUrl(url)
    this.#urls.clear()
  }

  async #download(file) {
    const { signal } = this.#session
    const blob = await this.#enqueue(() => this.load(file, signal))
    if (signal.aborted) throw new CacheClearedError()
    const url = this.createUrl(blob)
    this.#urls.set(file.id, url)
    return url
  }

  #enqueue(task) {
    return new Promise((resolve, reject) => {
      this.#waiting.push({ start: () => task().then(resolve, reject), reject })
      this.#startNext()
    })
  }

  #startNext() {
    while (this.#running < this.maxConcurrent && this.#waiting.length) {
      const job = this.#waiting.shift()
      this.#running += 1
      job.start().finally(() => {
        this.#running -= 1
        this.#startNext()
      })
    }
  }
}

export function createThumbnailCache({
  load,
  maxConcurrent = MAX_CONCURRENT_DOWNLOADS,
  createUrl = blob => URL.createObjectURL(blob),
  revokeUrl = url => URL.revokeObjectURL(url),
}) {
  return new ThumbnailCache({ load, maxConcurrent, createUrl, revokeUrl })
}
