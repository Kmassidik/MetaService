// Full screen for the big computer view: the browser's Fullscreen API on the view element, or a
// fixed full-viewport CSS mode where the API is missing or refused (iOS Safari on iPhone). Plain JS
// with the document injected, so the rules are unit-tested without a browser.

/** The floating "Exit full screen" control hides after this long without pointer movement. */
export const FULL_SCREEN_CONTROLS_HIDE_MS = 3000

export const FullScreenMode = Object.freeze({
  OFF: 'off',
  NATIVE: 'native',
  FALLBACK: 'fallback',
})

export function supportsNativeFullScreen(doc) {
  return Boolean(doc?.fullscreenEnabled) && typeof doc.documentElement?.requestFullscreen === 'function'
}

/**
 * onChange receives { mode, controlsVisible } on every change. Native mode is entered only when the
 * document reports our element as fullscreen (call syncWithDocument on `fullscreenchange`), so Esc
 * pressed in the browser and the button stay in step. Methods are bound: pass them as handlers.
 */
class FullScreenController {
  #doc
  #onChange
  #hideAfterMs
  #element = null
  #hideTimer = null
  mode = FullScreenMode.OFF
  controlsVisible = false

  constructor({ doc, onChange, hideAfterMs = FULL_SCREEN_CONTROLS_HIDE_MS }) {
    this.#doc = doc
    this.#onChange = onChange
    this.#hideAfterMs = hideAfterMs
    for (const name of ['enter', 'exit', 'toggle', 'dispose', 'syncWithDocument', 'revealControls']) this[name] = this[name].bind(this)
  }

  get active() {
    return this.mode !== FullScreenMode.OFF
  }

  // A refused request (permissions policy, no user gesture) still gets the CSS full-viewport mode.
  async enter(target) {
    if (this.active || !target) return
    this.#element = target
    if (!supportsNativeFullScreen(this.#doc)) return this.#setMode(FullScreenMode.FALLBACK)
    await target.requestFullscreen().catch(() => this.#setMode(FullScreenMode.FALLBACK))
  }

  // An exit the browser refuses means the document already left full screen: re-read its state.
  async exit() {
    if (!this.active) return
    const leaveNative = this.#ownsDocumentFullScreen()
    this.#setMode(FullScreenMode.OFF)
    if (!leaveNative) return
    await this.#doc.exitFullscreen().catch(this.syncWithDocument)
  }

  toggle(target) {
    return this.active ? this.exit() : this.enter(target)
  }

  dispose() {
    clearTimeout(this.#hideTimer)
    return this.exit()
  }

  syncWithDocument() {
    if (this.#ownsDocumentFullScreen()) return this.#setMode(FullScreenMode.NATIVE)
    if (this.mode === FullScreenMode.NATIVE) this.#setMode(FullScreenMode.OFF)
  }

  revealControls() {
    if (!this.active) return
    clearTimeout(this.#hideTimer)
    this.controlsVisible = true
    this.#hideTimer = setTimeout(() => this.#hideControls(), this.#hideAfterMs)
    this.#publish()
  }

  #hideControls() {
    clearTimeout(this.#hideTimer)
    this.controlsVisible = false
    this.#publish()
  }

  #setMode(next) {
    this.mode = next
    if (next === FullScreenMode.OFF) return this.#hideControls()
    this.revealControls()
  }

  #ownsDocumentFullScreen() {
    return Boolean(this.#element) && this.#doc.fullscreenElement === this.#element
  }

  #publish() {
    this.#onChange?.({ mode: this.mode, controlsVisible: this.controlsVisible })
  }
}

export function createFullScreen(options) {
  return new FullScreenController(options)
}
