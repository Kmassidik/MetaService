// When the AI access section asks again, and when it redraws. Pure, so the rules are tested without a browser.
export { listChanged, signatureOf } from './sharePoll.ts'

/** The section reads the approvals and the activity this often while the Settings page is open. */
export const MCP_POLL_MS = 5_000

export interface McpPollFacts {
  /** The browser tab is in the background. */
  hidden: boolean
  /** The parent answered that AI access does not exist there. That does not change by itself. */
  unavailable: boolean
}

/** Ask again unless the tab is hidden or the parent has no AI access. A parent that errors is asked again, so the section recovers. */
export const shouldPollMcp = (facts: McpPollFacts): boolean => !facts.hidden && !facts.unavailable
