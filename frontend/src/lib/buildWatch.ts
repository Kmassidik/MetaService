// A panel tab never reloads itself, so after an update it keeps running the old build next to the new server: old buttons, old words, new answers. This notices it:
// the running page names its script (assets/index-<hash>.js), the server's index names the newest one, and when they differ the panel says so and offers a reload.
const BUILD_PATTERN = /assets\/index-[A-Za-z0-9_-]+\.js/

/** The script name in a page's HTML, or null when there is none (a development page). */
export function buildOf(html: string): string | null {
  return BUILD_PATTERN.exec(html)?.[0] ?? null
}

/** True when the server's page names a different build than the running one. A page without a build name (development) never says it is old. */
export function isOutdated(running: string | null, latest: string | null): boolean {
  return running !== null && latest !== null && running !== latest
}

export const OUTDATED_TEXT = 'This panel was updated. Reload to use the newest version: what you see here may be old.'
export const BUILD_CHECK_MS = 60_000

/** Asks the server for its newest build. A failed or odd answer is "not known", never "outdated". */
export async function latestBuild(fetcher: typeof fetch = fetch): Promise<string | null> {
  try {
    const reply = await fetcher('/', { cache: 'no-store' })
    return reply.ok ? buildOf(await reply.text()) : null
  } catch {
    return null
  }
}
