import { describe, expect, it } from 'bun:test'
import { file } from '../testFixtures.ts'
import { gridColumns, splitAttachments } from './imageGrid.ts'

describe('gridColumns', () => {
  it('shows one picture on its own', () => {
    expect(gridColumns(1)).toBe(1)
    expect(gridColumns(0)).toBe(1)
  })

  it('pairs two and four pictures', () => {
    expect(gridColumns(2)).toBe(2)
    expect(gridColumns(4)).toBe(2)
  })

  it('puts three, five and more in rows of three', () => {
    expect(gridColumns(3)).toBe(3)
    expect(gridColumns(5)).toBe(3)
    expect(gridColumns(10)).toBe(3)
  })
})

describe('splitAttachments', () => {
  const png = file({ id: 'p', name: 'a.png', mediaType: 'image/png' })
  const pdf = file({ id: 'd', name: 'r.pdf', mediaType: 'application/pdf' })
  const gone = file({ id: 'g', name: 'File no longer available', state: 'deleted', size: 0, mediaType: '' })
  const svg = file({ id: 's', name: 'logo.svg', mediaType: 'image/svg+xml' })

  it('shows ready pictures inline and keeps the rest as file chips, in order', () => {
    expect(splitAttachments([pdf, png, gone, svg])).toEqual({ images: [png], others: [pdf, gone, svg] })
  })

  it('handles a message without attachments', () => {
    expect(splitAttachments()).toEqual({ images: [], others: [] })
  })
})
