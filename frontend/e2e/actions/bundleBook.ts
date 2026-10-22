// The chat bundles the stand-in Root has built: two versions, one pinned, one to roll back to. Pin and roll back change which one is pinned, the way the real Root does.
const VERSIONS = ['0.3.0', '0.4.0']
const START_PINNED = '0.4.0'
const START_PREVIOUS = '0.3.0'
const SHA = 'b'.repeat(64)
const SIZE_BYTES = 40_960

export interface BundleBook {
  /** The answer of GET /api/bundles. */
  overview: () => Record<string, unknown>
  pinned: () => string
  pin: (version: string) => boolean
  /** False when there is nothing earlier to go back to. */
  rollback: () => boolean
  reset: () => void
}

export function createBundleBook(): BundleBook {
  let pinned = START_PINNED
  let previous: string | null = START_PREVIOUS

  return {
    overview: () => ({
      pinned,
      previous,
      bundles: VERSIONS.map((version) => ({ version, platform: 'noarch', sha256: SHA, size: SIZE_BYTES, pinned: version === pinned })),
    }),
    pinned: () => pinned,
    pin(version) {
      if (!VERSIONS.includes(version)) return false
      previous = pinned
      pinned = version
      return true
    },
    rollback() {
      if (previous === null) return false
      ;[pinned, previous] = [previous, pinned]
      return true
    },
    reset() {
      pinned = START_PINNED
      previous = START_PREVIOUS
    },
  }
}
