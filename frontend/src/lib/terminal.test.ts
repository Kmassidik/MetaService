import { expect, test } from 'bun:test'
import { isDead, isLive, nextState, parseTicket, resizeMessage, roundBox, shouldRefit, statusText, statusTone, terminalSocketUrl } from './terminal.ts'

test('the socket address follows the page: wss on https, ws on http, ticket escaped', () => {
  expect(terminalSocketUrl({ protocol: 'https:', host: 'meta.ruvio.site' }, 'abc')).toBe('wss://meta.ruvio.site/api/terminal/abc')
  expect(terminalSocketUrl({ protocol: 'http:', host: '127.0.0.1:8080' }, 'abc')).toBe('ws://127.0.0.1:8080/api/terminal/abc')
  expect(terminalSocketUrl({ protocol: 'http:', host: 'h' }, 'a/b?c')).toBe('ws://h/api/terminal/a%2Fb%3Fc')
})

test('the resize message is the parent\'s frame, kept inside its limits', () => {
  expect(resizeMessage(80, 24)).toBe('{"resize":[80,24]}')
  expect(resizeMessage(0, 0)).toBe('{"resize":[1,1]}')
  expect(resizeMessage(9999, 9999)).toBe('{"resize":[500,300]}')
  expect(resizeMessage(80.4, 23.6)).toBe('{"resize":[80,24]}')
})

test('the status goes connecting, connected, then disconnected; an error then a close ends disconnected', () => {
  expect(nextState('disconnected', 'connect')).toBe('connecting')
  expect(nextState('connecting', 'open')).toBe('connected')
  expect(nextState('connected', 'close')).toBe('disconnected')
  expect(nextState('connecting', 'error')).toBe('error')
  expect(nextState(nextState('connecting', 'error'), 'close')).toBe('disconnected')
  expect(nextState('disconnected', 'open')).toBe('disconnected')
})

test('the status words, with the reason of a close', () => {
  expect(statusText('connecting')).toBe('connecting…')
  expect(statusText('connected')).toBe('connected')
  expect(statusText('error')).toBe('error')
  expect(statusText('disconnected')).toBe('disconnected')
  expect(statusText('disconnected', 'the shell ended')).toBe('disconnected · the shell ended')
  expect(statusText('error', 'the machine is offline')).toBe('error · the machine is offline')
  expect(statusText('connected', 'ignored')).toBe('connected')
})

test('the dot is green when connected, red when dead, plain while connecting', () => {
  expect(statusTone('connected')).toBe('ok')
  expect(statusTone('connecting')).toBe('')
  expect(statusTone('disconnected')).toBe('no')
  expect(statusTone('error')).toBe('no')
})

test('Reconnect is offered only when dead; a live socket blocks a second one', () => {
  expect(isDead('disconnected')).toBe(true)
  expect(isDead('error')).toBe(true)
  expect(isDead('connected')).toBe(false)
  expect(isDead('connecting')).toBe(false)
  expect([0, 1, 2, 3].map(isLive)).toEqual([true, true, false, false])
})

test('the refit guard skips an unchanged box and rounds first', () => {
  const last = roundBox({ width: 800.2, height: 600.4 })
  expect(last).toEqual({ width: 800, height: 600 })
  expect(shouldRefit(last, roundBox({ width: 800.4, height: 599.6 }))).toBe(false)
  expect(shouldRefit(last, { width: 801, height: 600 })).toBe(true)
  expect(shouldRefit(last, { width: 800, height: 700 })).toBe(true)
})

test('the ticket reply is read with checks', () => {
  expect(parseTicket({ ticket: 'x'.repeat(40), expires_in: 30 })).toEqual({ ticket: 'x'.repeat(40), expiresIn: 30 })
  expect(parseTicket(null)).toBeUndefined()
  expect(parseTicket([])).toBeUndefined()
  expect(parseTicket({})).toBeUndefined()
  expect(parseTicket({ ticket: '', expires_in: 30 })).toBeUndefined()
  expect(parseTicket({ ticket: 7, expires_in: 30 })).toBeUndefined()
  expect(parseTicket({ ticket: 'abc', expires_in: '30' })).toBeUndefined()
  expect(parseTicket({ ticket: 'abc', expires_in: 0 })).toBeUndefined()
  expect(parseTicket({ ticket: 'abc' })).toBeUndefined()
})
