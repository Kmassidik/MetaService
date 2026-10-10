import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { FULL_SCREEN_CONTROLS_HIDE_MS, FullScreenMode, createFullScreen, supportsNativeFullScreen } from './fullScreen.js'

// A document whose Fullscreen API behaves like a browser's: requests resolve, then `fullscreenchange`.
function fakeDocument({ enabled = true, refuse = false } = {}) {
  const doc = {
    fullscreenEnabled: enabled,
    fullscreenElement: null,
    documentElement: { requestFullscreen() {} },
    exitFullscreen: vi.fn(async () => { doc.fullscreenElement = null }),
  }
  const element = {
    requestFullscreen: vi.fn(async () => {
      if (refuse) throw new TypeError('Permissions check failed')
      doc.fullscreenElement = element
    }),
  }
  return { doc, element }
}

function setup(options) {
  const { doc, element } = fakeDocument(options)
  const changes = []
  const fullScreen = createFullScreen({ doc, onChange: change => changes.push(change) })
  return { doc, element, changes, fullScreen }
}

describe('supportsNativeFullScreen', () => {
  it('needs the API and permission to use it', () => {
    expect(supportsNativeFullScreen(fakeDocument().doc)).toBe(true)
    expect(supportsNativeFullScreen(fakeDocument({ enabled: false }).doc)).toBe(false)
    expect(supportsNativeFullScreen({ fullscreenEnabled: undefined, documentElement: {} })).toBe(false)
    expect(supportsNativeFullScreen(null)).toBe(false)
  })
})

describe('createFullScreen', () => {
  beforeEach(() => { vi.useFakeTimers() })
  afterEach(() => { vi.useRealTimers() })

  it('enters native full screen on the element once the document reports it', async () => {
    const { doc, element, fullScreen } = setup()
    await fullScreen.enter(element)
    expect(element.requestFullscreen).toHaveBeenCalledOnce()
    expect(fullScreen.mode).toBe(FullScreenMode.OFF)
    fullScreen.syncWithDocument()
    expect(doc.fullscreenElement).toBe(element)
    expect(fullScreen.mode).toBe(FullScreenMode.NATIVE)
    expect(fullScreen.controlsVisible).toBe(true)
  })

  it('exits through the document and turns off at once', async () => {
    const { doc, element, fullScreen } = setup()
    await fullScreen.enter(element)
    fullScreen.syncWithDocument()
    await fullScreen.exit()
    expect(doc.exitFullscreen).toHaveBeenCalledOnce()
    expect(fullScreen.active).toBe(false)
    expect(fullScreen.controlsVisible).toBe(false)
  })

  it('follows Esc pressed in the browser (fullscreenchange without our element)', async () => {
    const { doc, element, fullScreen } = setup()
    await fullScreen.enter(element)
    fullScreen.syncWithDocument()
    doc.fullscreenElement = null
    fullScreen.syncWithDocument()
    expect(fullScreen.mode).toBe(FullScreenMode.OFF)
  })

  it('ignores another element going full screen', () => {
    const { doc, fullScreen } = setup()
    doc.fullscreenElement = { other: true }
    fullScreen.syncWithDocument()
    expect(fullScreen.mode).toBe(FullScreenMode.OFF)
  })

  it('toggles between on and off', async () => {
    const { element, fullScreen } = setup()
    await fullScreen.toggle(element)
    fullScreen.syncWithDocument()
    expect(fullScreen.active).toBe(true)
    await fullScreen.toggle(element)
    expect(fullScreen.active).toBe(false)
  })

  it('falls back to the full-viewport mode without the API', async () => {
    const { doc, element, fullScreen } = setup({ enabled: false })
    await fullScreen.enter(element)
    expect(element.requestFullscreen).not.toHaveBeenCalled()
    expect(fullScreen.mode).toBe(FullScreenMode.FALLBACK)
    await fullScreen.exit()
    expect(doc.exitFullscreen).not.toHaveBeenCalled()
    expect(fullScreen.mode).toBe(FullScreenMode.OFF)
  })

  it('falls back when the browser refuses the request', async () => {
    const { element, fullScreen } = setup({ refuse: true })
    await fullScreen.enter(element)
    expect(fullScreen.mode).toBe(FullScreenMode.FALLBACK)
  })

  it('hides the exit control after the idle time and shows it again on movement', async () => {
    const { element, fullScreen } = setup({ enabled: false })
    await fullScreen.enter(element)
    vi.advanceTimersByTime(FULL_SCREEN_CONTROLS_HIDE_MS - 1)
    expect(fullScreen.controlsVisible).toBe(true)
    vi.advanceTimersByTime(1)
    expect(fullScreen.controlsVisible).toBe(false)
    fullScreen.revealControls()
    expect(fullScreen.controlsVisible).toBe(true)
  })

  it('restarts the idle time on every movement', async () => {
    const { element, fullScreen } = setup({ enabled: false })
    await fullScreen.enter(element)
    vi.advanceTimersByTime(FULL_SCREEN_CONTROLS_HIDE_MS - 100)
    fullScreen.revealControls()
    vi.advanceTimersByTime(FULL_SCREEN_CONTROLS_HIDE_MS - 100)
    expect(fullScreen.controlsVisible).toBe(true)
  })

  it('never shows the exit control while off', () => {
    const { changes, fullScreen } = setup()
    fullScreen.revealControls()
    expect(fullScreen.controlsVisible).toBe(false)
    expect(changes).toEqual([])
  })

  it('reports each change', async () => {
    const { element, changes, fullScreen } = setup({ enabled: false })
    await fullScreen.enter(element)
    vi.advanceTimersByTime(FULL_SCREEN_CONTROLS_HIDE_MS)
    await fullScreen.exit()
    expect(changes).toEqual([
      { mode: FullScreenMode.FALLBACK, controlsVisible: true },
      { mode: FullScreenMode.FALLBACK, controlsVisible: false },
      { mode: FullScreenMode.OFF, controlsVisible: false },
    ])
  })

  it('dispose leaves full screen and stops the timer', async () => {
    const { doc, element, fullScreen } = setup()
    await fullScreen.enter(element)
    fullScreen.syncWithDocument()
    await fullScreen.dispose()
    expect(doc.exitFullscreen).toHaveBeenCalledOnce()
    expect(vi.getTimerCount()).toBe(0)
  })
})
