// What the service sends for POST /api/files/:file/extract (NativeOCR/main.swift Result, relayed by NativeExtraction.swift).
import { describe, expect, it } from 'bun:test'
import { extractedText, readExtraction } from './extraction.ts'

const real = {
  requestId: 'req1',
  extraction: {
    engine: 'apple-vision-text+pdfkit',
    revision: 3,
    warnings: ['table_structure_not_extracted', 'page_2_no_text_detected'],
    pages: [
      { page: 1, text: 'Hello', source: 'ocr', regions: [{ text: 'Hello', confidence: 0.9, x: 0, y: 0, width: 1, height: 1 }] },
      { page: 2, text: '', source: 'pdf_text', regions: [] },
    ],
  },
}

const answer = (body: unknown) => new Response(JSON.stringify(body), { status: 200 })

describe('readExtraction', () => {
  it('keeps the engine, revision, warnings and page details', async () => {
    const extraction = await readExtraction(answer(real))
    expect(extraction.engine).toBe('apple-vision-text+pdfkit')
    expect(extraction.revision).toBe(3)
    expect(extraction.warnings).toEqual(real.extraction.warnings)
    expect(extraction.pages.map(page => [page.page, page.source])).toEqual([[1, 'ocr'], [2, 'pdf_text']])
    expect(extractedText(extraction)).toBe('Hello\n\n')
  })

  it('refuses an extraction without its engine, revision, warnings, or page details', async () => {
    const { extraction } = real
    const without = (field: string) => Object.fromEntries(Object.entries(extraction).filter(([key]) => key !== field))
    for (const field of ['engine', 'revision', 'warnings']) {
      await expect(readExtraction(answer({ extraction: without(field) }))).rejects.toThrow('unreadable extraction')
    }
    const barePage = { ...extraction, pages: [{ text: 'Hello' }] }
    await expect(readExtraction(answer({ extraction: barePage }))).rejects.toThrow('unreadable extraction')
  })

  it('refuses a revision that is not a number', async () => {
    await expect(readExtraction(answer({ extraction: { ...real.extraction, revision: 'v3' } }))).rejects.toThrow('unreadable extraction')
  })
})
