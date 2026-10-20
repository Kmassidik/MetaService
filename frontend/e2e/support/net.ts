// Small waiting and port helpers shared by the tests.
import { createServer } from 'node:net'

const HEALTH_TRIES = 100
const HEALTH_PAUSE_MS = 100

export const wait = (ms: number): Promise<void> => new Promise((done) => setTimeout(done, ms))

/** A port nothing listens on right now. */
export function freePort(): Promise<number> {
  return new Promise((done, fail) => {
    const server = createServer()
    server.on('error', fail)
    server.listen(0, '127.0.0.1', () => {
      const address = server.address()
      if (address === null || typeof address === 'string') return fail(new Error('no port was given'))
      server.close(() => done(address.port))
    })
  })
}

/** Waits until `<base>/health` answers, or throws when the program never starts. */
export async function waitForHealth(base: string, name: string): Promise<void> {
  for (let attempt = 0; attempt < HEALTH_TRIES; attempt++) {
    if (await fetch(`${base}/health`).then((reply) => reply.ok, () => false)) return
    await wait(HEALTH_PAUSE_MS)
  }
  throw new Error(`${name} did not start`)
}
