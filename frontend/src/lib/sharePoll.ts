// When the Share a PC page asks again, and when it redraws. Pure, so the rules are tested without a browser.
import type { PageProblem } from './shareErrors.ts'

/** The page reads the waiting and joined machines this often while it is open. */
export const SHARE_POLL_MS = 4_000

export interface PollFacts {
  /** The browser tab is in the background. */
  hidden: boolean
  /** The problem that replaces the page, if any. */
  problem: PageProblem | null
}

/** Ask again unless the tab is hidden or the feature is not set up (that does not change by itself). A hub that does not answer is asked again, so the page recovers. */
export const shouldPoll = (facts: PollFacts): boolean => !facts.hidden && facts.problem !== 'not_configured'

/** A list's fingerprint. Two answers with the same fingerprint are the same list. */
export const signatureOf = (list: unknown): string => JSON.stringify(list)

/** True when the new list differs from the one on screen. A list that did not change is not redrawn, so nothing typed beside it is disturbed. */
export const listChanged = (shownSignature: string | null, next: unknown): boolean => shownSignature !== signatureOf(next)
