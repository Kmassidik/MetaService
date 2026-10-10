import { describe, expect, it } from 'vitest'
import { DeskPhase, canTakeOver, deskPhase, homeHint, isStreamReconnecting, liveLabel, previewStreamSource, streamSource } from './deskStatus.js'

const bigImage = `data:image/jpeg;base64,${'a'.repeat(20000)}`
const stream = { mode: 'stream', state: 'running', wsPath: '/ws/desktop/abc' }

describe('deskPhase', () => {
  it('prefers a ready stream over a screenshot', () => {
    expect(deskPhase({ desktop: stream, image: bigImage, message: '', busy: true })).toBe(DeskPhase.STREAM)
  })

  it('shows a useful screenshot when there is no stream', () => {
    expect(deskPhase({ desktop: null, image: bigImage, message: '', busy: false })).toBe(DeskPhase.SNAPSHOT)
  })

  it('treats a blocked page as not useful', () => {
    expect(deskPhase({ desktop: null, image: bigImage, message: 'HTTP 403 blocked', busy: false })).toBe(DeskPhase.HOME)
  })

  it('is starting while busy or while a stream has no socket yet', () => {
    expect(deskPhase({ desktop: null, image: '', message: '', busy: true })).toBe(DeskPhase.STARTING)
    expect(deskPhase({ desktop: { mode: 'stream', state: 'starting', wsPath: '' }, image: '', busy: false })).toBe(DeskPhase.STARTING)
  })

  it('falls back to the desktop home when the stream failed', () => {
    expect(deskPhase({ desktop: { ...stream, state: 'failed' }, image: '', busy: false })).toBe(DeskPhase.HOME)
  })
})

describe('stream helpers', () => {
  it('builds an encoded noVNC source only for a ready stream', () => {
    expect(streamSource(stream)).toBe('/novnc/index.html?path=%2Fws%2Fdesktop%2Fabc')
    expect(streamSource({ ...stream, state: 'error' })).toBe('')
  })

  it('previews the real desktop watch-only on the account socket, never a bot socket', () => {
    expect(previewStreamSource({ mode: 'desktop', state: 'running' })).toBe('/novnc/index.html?path=%2Fapi%2Fcomputer%2Fdesktop%2Fws&view=1')
    expect(previewStreamSource({ state: 'running', image: bigImage })).toBe('')
    expect(previewStreamSource(null)).toBe('')
  })

  it('reports reconnecting from the desktop state', () => {
    expect(isStreamReconnecting({ ...stream, state: 'reconnecting' })).toBe(true)
    expect(isStreamReconnecting(stream)).toBe(false)
  })
})

describe('labels', () => {
  it('labels live and snapshot phases only', () => {
    expect(liveLabel(DeskPhase.STREAM, '')).toBe('Live')
    expect(liveLabel(DeskPhase.SNAPSHOT, '12:01')).toBe('Snapshot · 12:01')
    expect(liveLabel(DeskPhase.HOME, '12:01')).toBe('')
  })

  it('allows take over only when there is a screen', () => {
    expect(canTakeOver(DeskPhase.STREAM)).toBe(true)
    expect(canTakeOver(DeskPhase.STARTING)).toBe(false)
  })

  it('explains a blocked site before a blank page', () => {
    expect(homeHint({ message: 'blocked', image: 'x' })).toMatch(/blocked/)
    expect(homeHint({ message: '', image: 'x' })).toMatch(/blank/)
  })
})
