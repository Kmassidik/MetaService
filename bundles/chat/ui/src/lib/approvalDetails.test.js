import { describe, expect, it } from 'vitest'
import { actionRows, humanizeKey, parameterRows } from './approvalDetails.js'

const rows = json => parameterRows(json).map(row => `${row.label}: ${row.value}`)

describe('humanizeKey', () => {
  it('turns code keys into words', () => {
    expect(humanizeKey('max_results')).toBe('Max results')
    expect(humanizeKey('maxResults')).toBe('Max results')
    expect(humanizeKey('to')).toBe('To')
    expect(humanizeKey('reply-to')).toBe('Reply to')
  })
})

describe('parameterRows', () => {
  it('shows each parameter as a readable row', () => {
    const json = JSON.stringify({ to: 'ada@example.com', subject: 'Hi', sendNow: true, retries: 0 })
    expect(rows(json)).toEqual(['To: ada@example.com', 'Subject: Hi', 'Send now: Yes', 'Retries: 0'])
  })

  it('flattens nested objects with a path label', () => {
    const json = JSON.stringify({ post: { text: 'Hello', reply_settings: { audience: 'everyone' } } })
    expect(rows(json)).toEqual(['Post › Text: Hello', 'Post › Reply settings › Audience: everyone'])
  })

  it('joins simple lists and numbers lists of objects', () => {
    expect(rows(JSON.stringify({ tags: ['a', 'b', 3] }))).toEqual(['Tags: a, b, 3'])
    expect(rows(JSON.stringify({ items: [{ name: 'Pen' }, { name: 'Ink' }] }))).toEqual(['Items › 1 › Name: Pen', 'Items › 2 › Name: Ink'])
  })

  it('says None for empty values', () => {
    expect(rows(JSON.stringify({ cc: [], note: '', extra: null, meta: {} }))).toEqual(['Cc: None', 'Note: None', 'Extra: None', 'Meta: None'])
  })

  it('handles a bare value and text that is not JSON', () => {
    expect(rows('"just text"')).toEqual(['Value: just text'])
    expect(rows('not json {')).toEqual(['Details: not json {'])
  })

  it('is empty when there are no parameters', () => {
    expect(parameterRows('')).toEqual([])
    expect(parameterRows(undefined)).toEqual([])
  })
})

describe('actionRows', () => {
  it('lists the action, website and tool, skipping empty ones', () => {
    const approval = { action: 'Post a tweet', destination: 'x.com', tool: 'maas_connectors' }
    expect(actionRows(approval)).toEqual([
      { label: 'Action', value: 'Post a tweet' },
      { label: 'Website', value: 'x.com' },
      { label: 'Tool', value: 'maas_connectors' },
    ])
    expect(actionRows({ action: 'Send', destination: '', tool: 'browser' }).map(row => row.label)).toEqual(['Action', 'Tool'])
  })
})
