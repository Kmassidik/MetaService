// The waiting times of the panel's buttons and requests, in one place so the button and the request layer agree.

/** A button shows its busy label for at least this long, so the label never flashes. */
export const MIN_BUSY_MS = 400
/** A request to the Root that gets no answer by then is given up. */
export const REQUEST_TIMEOUT_MS = 30_000
/** The routes where the Root logs in to another computer over SSH and may work for minutes. */
export const LONG_REQUEST_TIMEOUT_MS = 5 * 60_000
/** The small success line next to a button stays this long. */
export const SUCCESS_LINE_MS = 2_000

export const TIMEOUT_MESSAGE = 'The server did not answer in time. It may still be working: check the list, then try again.'
export const FAILED_MESSAGE = 'Something went wrong.'
