import { describe, expect, it } from 'vitest'
import {
  appResults, approvalEditable, approvalLabel, approvalTitle, approvalWhere, cardAwaitsOwner, messageToSend, resolvedCardIds,
  resultLine, resultLinkLabel, resultTitle,
} from './appCards.js'

const sendCard = { kind: 'app_send', cardId: 'a', app: 'whatsapp', appName: 'WhatsApp', target: 'Febi', text: 'On my way' }
const resultCard = { kind: 'app_result', cardId: 'r', app: 'whatsapp', appName: 'WhatsApp', target: 'Febi', ok: true, delivery: 'delivered' }
const event = (kind, payload) => ({ kind, payload })

describe('app tool cards', () => {
  it('a send card waits for the owner until it is resolved here or on the server', () => {
    expect(cardAwaitsOwner(sendCard, {}, new Set())).toBe(true)
    expect(cardAwaitsOwner(sendCard, { a: 'send' }, new Set())).toBe(false)
    expect(cardAwaitsOwner(sendCard, {}, resolvedCardIds([event('card_resolved', { cardId: 'a' })]))).toBe(false)
  })

  it('a result card is a record, never waiting', () => {
    expect(cardAwaitsOwner(resultCard, {}, new Set())).toBe(false)
  })

  it('lists result cards in order and shows the app\'s proof, not prose', () => {
    const failed = { ...resultCard, cardId: 'f', ok: false, reason: 'No contact named Zed on WhatsApp.' }
    const events = [event('card', sendCard), event('card', resultCard), event('ask', {}), event('card', failed)]
    expect(appResults(events)).toEqual([resultCard, failed])
    expect(resultTitle(resultCard)).toBe('Sent to Febi on WhatsApp')
    expect(resultLine(resultCard)).toBe('Delivered ✓✓')
    expect(resultLine({ ...resultCard, delivery: 'sent' })).toBe('Sent ✓')
    expect(resultTitle(failed)).toBe('Not sent to Febi on WhatsApp')
    expect(resultLine(failed)).toBe('No contact named Zed on WhatsApp.')
  })

  it('a message card (and one from before cards had a subject) asks to send on the app', () => {
    for (const card of [sendCard, { ...sendCard, subject: 'message' }]) {
      expect(approvalTitle(card)).toBe('Send on WhatsApp to Febi?')
      expect(approvalLabel(card)).toBe('Approve message to Febi')
      expect(approvalWhere(card)).toBe('From your WhatsApp · to Febi')
      expect(approvalEditable(card)).toBe(true)
    }
    expect(resultLinkLabel(resultCard)).toBe('Open chat')
  })

  it('calendar cards say what changes, never "Send" or "Sent", and cannot be edited', () => {
    const calendar = { ...sendCard, app: 'calendar', appName: 'Google Calendar', subject: 'event', target: 'Team sync' }
    expect(approvalTitle({ ...calendar, change: 'create' })).toBe('Create event on Google Calendar?')
    expect(approvalTitle({ ...calendar, change: 'move' })).toBe('Move event on Google Calendar?')
    expect(approvalTitle({ ...calendar, change: 'cancel' })).toBe('Cancel event on Google Calendar?')
    expect(approvalWhere(calendar)).toBe('Your Google Calendar · Team sync')
    expect(approvalEditable(calendar)).toBe(false)
    const done = { ...resultCard, app: 'calendar', appName: 'Google Calendar', subject: 'event', target: 'Team sync', delivery: 'sent' }
    expect(resultLine({ ...done, change: 'create' })).toBe('Event created ✓')
    expect(resultLine({ ...done, change: 'move' })).toBe('Event moved ✓')
    expect(resultLine({ ...done, change: 'cancel' })).toBe('Event cancelled ✓')
    expect(resultTitle(done)).toBe('Team sync · Google Calendar')
    expect(resultTitle({ ...done, ok: false, reason: 'No event named Team sync.' })).toBe('Google Calendar not changed: Team sync')
    expect(resultLinkLabel(done)).toBe('Open event')
    for (const card of [calendar, done]) expect(`${approvalTitle(card)} ${resultLine(done)} ${resultTitle(done)}`).not.toMatch(/\bSen[dt]\b/)
  })

  it('email and post cards read as an email and a post', () => {
    const email = { ...sendCard, app: 'gmail', appName: 'Gmail', subject: 'email', target: 'budi@example.com' }
    expect(approvalTitle(email)).toBe('Send email to budi@example.com?')
    expect(resultLine({ ...email, ok: true, delivery: 'sent' })).toBe('Email sent ✓')
    expect(resultTitle({ ...email, ok: true, delivery: 'sent' })).toBe('Emailed budi@example.com from Gmail')
    expect(resultLinkLabel(email)).toBe('Open email')
    const post = { ...sendCard, app: 'x', appName: 'X', subject: 'post', target: 'your followers (@ruvio)' }
    expect(approvalTitle(post)).toBe('Post on X?')
    expect(approvalWhere(post)).toBe('From your X · to your followers (@ruvio)')
    expect(resultLine({ ...post, ok: true, delivery: 'sent' })).toBe('Posted ✓')
    expect(resultTitle({ ...post, ok: false, reason: 'Not signed in.' })).toBe('Not posted on X')
  })

  it('Send sends the bot\'s text, or the owner\'s edit when it is not empty', () => {
    expect(messageToSend('On my way', null)).toEqual({ text: 'On my way', valid: true })
    expect(messageToSend('On my way', '10 min late')).toEqual({ text: '10 min late', valid: true })
    expect(messageToSend('On my way', '   ').valid).toBe(false)
    expect(messageToSend('On my way', 'x'.repeat(2001)).valid).toBe(false)
  })
})
