import { describe, expect, it } from 'vitest'
import { CSV_MAX_COLUMNS, CSV_MAX_ROWS, decodeText, parseCsvPreview } from './textPreview.js'
import { pdfScale, PDF_MAX_PIXELS } from './pdfPreview.js'

describe('parseCsvPreview', () => {
  it('keeps cells as text and never evaluates formulas', () => {
    expect(parseCsvPreview('a,b\n=1+1,2\n')).toEqual({ rows: [['a', 'b'], ['=1+1', '2']], truncated: false })
  })

  it('caps rows and columns and says so', () => {
    const wide = Array.from({ length: CSV_MAX_COLUMNS + 5 }, (_, index) => `c${index}`).join(',')
    const long = Array.from({ length: CSV_MAX_ROWS + 10 }, (_, index) => `${index}`).join('\n')
    expect(parseCsvPreview(wide).rows[0]).toHaveLength(CSV_MAX_COLUMNS)
    expect(parseCsvPreview(wide).truncated).toBe(true)
    expect(parseCsvPreview(long).rows).toHaveLength(CSV_MAX_ROWS)
    expect(parseCsvPreview(long).truncated).toBe(true)
  })

  it('refuses malformed CSV', () => {
    expect(() => parseCsvPreview('a,"b\n1,2')).toThrow('CSV could not be safely parsed')
  })
})

describe('decodeText', () => {
  it('refuses bytes that are not UTF-8', () => {
    expect(decodeText(new TextEncoder().encode('héllo'))).toBe('héllo')
    expect(() => decodeText(new Uint8Array([0xff, 0xfe, 0xfd]))).toThrow()
  })
})

describe('pdfScale', () => {
  it('renders small pages at 1.5x', () => {
    expect(pdfScale({ width: 600, height: 800 })).toBe(1.5)
  })

  it('keeps big pages under the pixel and side caps', () => {
    const scale = pdfScale({ width: 5000, height: 5000 })
    expect(5000 * scale).toBeLessThanOrEqual(4096)
    expect(5000 * 5000 * scale * scale).toBeLessThanOrEqual(PDF_MAX_PIXELS + 1)
  })

  it('rejects broken page sizes', () => {
    expect(() => pdfScale({ width: 0, height: 10 })).toThrow('invalid')
    expect(() => pdfScale({ width: Infinity, height: 10 })).toThrow('invalid')
  })
})
