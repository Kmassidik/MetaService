// What the tests' own scripts keep on the browser's window.
interface Window {
  /** The policy violations the page reported, collected for the test to read. */
  violations?: string[]
  /** The last policy violation the page reported, collected for the test to read. */
  violation?: string
  /** Set by hostile text in a workload if the panel ever ran it. */
  __xss?: number
}
