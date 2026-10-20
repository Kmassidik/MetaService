/**
 * Object URLs for pictures, one per file id for the whole session, so a picture is downloaded at
 * most once however often it is shown (composer, message, Files tab, viewer). At most
 * `maxConcurrent` downloads run at a time; the rest wait in order. `clear()` ends the session:
 * it aborts downloads, drops waiting ones and revokes every URL.
 * `load(file, signal)` returns a Blob; it owns the type and size checks.
 */
export const MAX_CONCURRENT_DOWNLOADS = 3

interface Pictured {
  id: string
}

interface CacheOptions<F extends Pictured> {
  load: (file: F, signal: AbortSignal) => Promise<Blob>
  maxConcurrent?: number
  createUrl?: (blob: Blob) => string
  revokeUrl?: (url: string) => void
}

interface Waiting {
  start: () => Promise<void>
  reject: (error: Error) => void
}

export class CacheClearedError extends Error {
  constructor() {
    super('The picture cache was cleared.')
    this.name = 'AbortError'
  }
}

class ThumbnailCache<F extends Pictured> {
  #urls = new Map<string, string>()
  #inFlight = new Map<string, Promise<string>>()
  #waiting: Waiting[] = []
  #running = 0
  #session = new AbortController()

  readonly load: CacheOptions<F>['load']
  readonly maxConcurrent: number
  readonly createUrl: (blob: Blob) => string
  readonly revokeUrl: (url: string) => void

  constructor(options: Required<CacheOptions<F>>) {
    this.load = options.load
    this.maxConcurrent = options.maxConcurrent
    this.createUrl = options.createUrl
    this.revokeUrl = options.revokeUrl
  }

  /** Resolves to the picture's object URL, downloading it once. */
  get(file: F): Promise<string> {
    const known = this.#urls.get(file.id)
    if (known !== undefined) return Promise.resolve(known)
    const loading = this.#inFlight.get(file.id)
    if (loading) return loading
    const promise = this.#download(file).finally(() => {
      if (this.#inFlight.get(file.id) === promise) this.#inFlight.delete(file.id)
    })
    this.#inFlight.set(file.id, promise)
    return promise
  }

  /** The URL if it is already known, without downloading. */
  peek(id: string): string {
    return this.#urls.get(id) || ''
  }

  /** Uses bytes the browser already has (a finished upload) instead of downloading them again. */
  seed(id: string, blob: Blob): void {
    if (!this.#urls.has(id)) this.#urls.set(id, this.createUrl(blob))
  }

  forget(id: string): void {
    const url = this.#urls.get(id)
    if (url !== undefined) this.revokeUrl(url)
    this.#urls.delete(id)
  }

  clear(): void {
    this.#session.abort()
    this.#session = new AbortController()
    for (const job of this.#waiting) job.reject(new CacheClearedError())
    this.#waiting = []
    this.#inFlight.clear()
    for (const url of this.#urls.values()) this.revokeUrl(url)
    this.#urls.clear()
  }

  async #download(file: F): Promise<string> {
    const { signal } = this.#session
    const blob = await this.#enqueue(() => this.load(file, signal))
    if (signal.aborted) throw new CacheClearedError()
    const url = this.createUrl(blob)
    this.#urls.set(file.id, url)
    return url
  }

  #enqueue<T>(task: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      this.#waiting.push({ start: () => task().then(resolve, reject), reject })
      this.#startNext()
    })
  }

  /** The next waiting job, when a download slot is free. */
  #nextJob(): Waiting | undefined {
    return this.#running < this.maxConcurrent ? this.#waiting.shift() : undefined
  }

  #startNext(): void {
    for (let job = this.#nextJob(); job; job = this.#nextJob()) {
      this.#running += 1
      job.start().finally(() => {
        this.#running -= 1
        this.#startNext()
      })
    }
  }
}

export function createThumbnailCache<F extends Pictured>({
  load,
  maxConcurrent = MAX_CONCURRENT_DOWNLOADS,
  createUrl = blob => URL.createObjectURL(blob),
  revokeUrl = url => URL.revokeObjectURL(url),
}: CacheOptions<F>): ThumbnailCache<F> {
  return new ThumbnailCache({ load, maxConcurrent, createUrl, revokeUrl })
}
