import { describe, expect, it } from 'vitest'
import { fileMeta, filterGroups, groupVersions, presentCategories, renderedPdfOf, shownVersion } from './fileList.js'

const at = minutes => new Date(Date.UTC(2026, 9, 1, 10, minutes)).toISOString()
const photo = { id: 'p', name: 'Beach.png', mediaType: 'image/png', size: 10, state: 'ready', createdAt: at(1) }
const reportV1 = { id: 'r1', artifactId: 'rep', version: 1, name: 'report.pdf', mediaType: 'application/pdf', size: 10, state: 'ready', createdAt: at(2) }
const reportV2 = { id: 'r2', artifactId: 'rep', version: 2, name: 'report-final.pdf', mediaType: 'application/pdf', size: 10, state: 'ready', createdAt: at(5) }
const sheet = { id: 's', name: 'data.csv', mediaType: 'text/csv', size: 10, state: 'ready', createdAt: at(3) }

describe('groupVersions', () => {
  it('groups an artifact\'s versions, newest version first, and lists newest groups first', () => {
    const groups = groupVersions([reportV1, photo, sheet, reportV2])
    expect(groups.map(group => group.id)).toEqual(['rep', 's', 'p'])
    expect(groups[0].items.map(item => item.id)).toEqual(['r2', 'r1'])
  })

  it('does not reorder the caller\'s files', () => {
    const files = [reportV1, reportV2]
    groupVersions(files)
    expect(files).toEqual([reportV1, reportV2])
  })
})

describe('filterGroups', () => {
  const groups = groupVersions([photo, reportV1, reportV2, sheet])

  it('matches the search text in any version, ignoring case and spaces around it', () => {
    expect(filterGroups(groups, { query: '  BEACH ' }).map(group => group.id)).toEqual(['p'])
    expect(filterGroups(groups, { query: 'report.pdf' }).map(group => group.id)).toEqual(['rep'])
  })

  it('filters by type chip and combines it with the search', () => {
    expect(filterGroups(groups, { category: 'pdf' }).map(group => group.id)).toEqual(['rep'])
    expect(filterGroups(groups, { category: 'image', query: 'data' })).toEqual([])
  })

  it('lists everything without a filter', () => {
    expect(filterGroups(groups)).toHaveLength(3)
  })
})

describe('presentCategories', () => {
  it('offers chips only for types the person has, in a fixed order', () => {
    expect(presentCategories([sheet, photo, reportV1]).map(category => category.id)).toEqual(['image', 'pdf', 'spreadsheet'])
    expect(presentCategories([])).toEqual([])
  })
})

describe('renderedPdfOf', () => {
  const doc = { id: 'd', name: 'plan.docx', previewFileId: 'dp', state: 'ready', createdAt: at(1) }
  const rendered = { id: 'dp', name: 'plan.pdf', mediaType: 'application/pdf', state: 'ready', createdAt: at(1) }

  it('finds the ready rendered PDF of a document', () => {
    expect(renderedPdfOf(doc, [doc, rendered])).toBe(rendered)
  })

  it('ignores a rendered file that is not a ready PDF', () => {
    expect(renderedPdfOf(doc, [doc, { ...rendered, state: 'uploading' }])).toBe(null)
    expect(renderedPdfOf(doc, [doc, { ...rendered, mediaType: 'text/html' }])).toBe(null)
    expect(renderedPdfOf(photo, [photo, rendered])).toBe(null)
  })
})

describe('fileMeta', () => {
  it('shows size, day and the number of versions', () => {
    const meta = fileMeta({ ...photo, size: 1536 }, 3)
    expect(meta.startsWith('1.5 KiB · ')).toBe(true)
    expect(meta.endsWith(' · 3 versions')).toBe(true)
  })

  it('says how much of an unfinished upload arrived', () => {
    expect(fileMeta({ ...photo, state: 'uploading', received: 512 })).toContain('512 B received, not ready yet')
  })
})

describe('shownVersion', () => {
  const [report] = groupVersions([reportV1, reportV2])

  it('shows the newest version unless another was picked', () => {
    expect(shownVersion(report, '').id).toBe('r2')
    expect(shownVersion(report, 'r1').id).toBe('r1')
    expect(shownVersion(report, 'gone').id).toBe('r2')
  })
})
