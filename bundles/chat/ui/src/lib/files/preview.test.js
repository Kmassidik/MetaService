import { describe, expect, it } from 'vitest'
import { MiB } from '../constants.js'
import { canExtractText, downloadUrl, fileCategory, fileIcon, isDocumentPreview, isViewableImage, looksLikeImage, previewKind } from './preview.js'

const file = (name, mediaType, size = 1000, state = 'ready') => ({ id: `id-${name}`, name, mediaType, size, state })

describe('previewKind', () => {
  it('shows PNG, JPEG, WebP and GIF pictures up to 25 MiB', () => {
    for (const type of ['image/png', 'image/jpeg', 'image/webp', 'image/gif']) expect(previewKind(file('a', type))).toBe('image')
    expect(previewKind(file('a.png', 'image/png', 25 * MiB))).toBe('image')
    expect(previewKind(file('a.png', 'image/png', 25 * MiB + 1))).toBe('')
  })

  it('never decodes other image types such as SVG or HEIC', () => {
    expect(previewKind(file('a.svg', 'image/svg+xml'))).toBe('')
    expect(previewKind(file('a.heic', 'image/heic'))).toBe('')
  })

  it('previews PDFs up to 100 MiB and HTML or CSV up to 2 MiB', () => {
    expect(previewKind(file('r.pdf', 'application/pdf', 100 * MiB))).toBe('pdf')
    expect(previewKind(file('r.pdf', 'application/pdf', 100 * MiB + 1))).toBe('')
    expect(previewKind(file('page.HTML', 'text/plain'))).toBe('html')
    expect(previewKind(file('data.csv', 'text/plain'))).toBe('csv')
    expect(previewKind(file('data', 'text/csv'))).toBe('csv')
    expect(previewKind(file('big.csv', 'text/csv', 2 * MiB + 1))).toBe('')
  })

  it('trusts the detected type over the name for pictures', () => {
    expect(previewKind(file('photo.png', 'application/octet-stream'))).toBe('')
  })
})

describe('what can be shown', () => {
  it('shows only ready pictures', () => {
    expect(isViewableImage(file('a.png', 'image/png'))).toBe(true)
    expect(isViewableImage(file('a.png', 'image/png', 1000, 'uploading'))).toBe(false)
    expect(isViewableImage(file('a.png', 'image/png', 1000, 'deleted'))).toBe(false)
    expect(isViewableImage(null)).toBe(false)
  })

  it('opens ready PDFs, HTML and CSV in the document preview, not pictures', () => {
    expect(isDocumentPreview(file('r.pdf', 'application/pdf'))).toBe(true)
    expect(isDocumentPreview(file('a.png', 'image/png'))).toBe(false)
    expect(isDocumentPreview(file('notes.txt', 'text/plain'))).toBe(false)
  })

  it('extracts text from ready pictures and PDFs up to 25 MiB', () => {
    expect(canExtractText(file('a.png', 'image/png'))).toBe(true)
    expect(canExtractText(file('r.pdf', 'application/pdf', 25 * MiB + 1))).toBe(false)
    expect(canExtractText(file('a.csv', 'text/csv'))).toBe(false)
  })

  it('guesses a picture from an upload name before the type is known', () => {
    expect(looksLikeImage('pasted-image.png')).toBe(true)
    expect(looksLikeImage('Photo.JPEG')).toBe(true)
    expect(looksLikeImage('report.pdf')).toBe(false)
  })

  it('escapes the id in the download URL', () => {
    expect(downloadUrl('a/b')).toBe('/api/files/a%2Fb/download')
  })
})

describe('fileCategory', () => {
  it('sorts files into the type chips', () => {
    expect(fileCategory(file('a.png', 'image/png'))).toBe('image')
    expect(fileCategory(file('r.pdf', 'application/pdf'))).toBe('pdf')
    expect(fileCategory(file('t.xlsx', 'application/zip'))).toBe('spreadsheet')
    expect(fileCategory(file('d.docx', 'application/zip'))).toBe('document')
    expect(fileCategory(file('s.mp3', 'audio/mpeg'))).toBe('media')
    expect(fileCategory(file('x.bin', ''))).toBe('other')
  })

  it('gives every category an icon', () => {
    expect(fileIcon(file('a.png', 'image/png'))).toBe('image')
    expect(fileIcon(file('t.csv', 'text/csv'))).toBe('sheet')
    expect(fileIcon(file('x.bin', ''))).toBe('file')
  })
})
