import { test, expect } from 'bun:test'
import { imageAfterChange, imageBundle, imageCards, imageOptions, parseMachineImages, STOCK_IMAGE, type ImageHelper, type MachineImages } from './images.ts'
import { UnreadableAnswer } from './machineDetail.ts'

const COMING_SOON = 'Coming soon: needs the image to be prepared on the machine'
const WAITING = 'Waiting for a pinned release and checksum'

const blank = { id: 'blank', title: 'Blank (plain Ubuntu)', description: 'Ubuntu 24.04 with the usual server tools. Nothing else.', state: 'ready', ready: true, available: true, reason: null }
const openclaw = { id: 'openclaw', title: 'OpenClaw', description: 'Blank, plus the OpenClaw assistant already installed.', state: 'planned', ready: false, available: false, reason: COMING_SOON }
const hermes = { id: 'hermes', title: 'Hermes', description: 'Blank, plus the Hermes assistant already installed.', state: 'planned', ready: false, available: false, reason: WAITING }
const answer = (changes: Record<string, unknown> = {}) => ({ helper: 'answered', images: [blank, openclaw, hermes], ...changes })
const parsed = (): MachineImages => parseMachineImages(answer())

test('the stock image is called blank', () => {
  expect(STOCK_IMAGE).toBe('blank')
})

test('a good answer is read as it is', () => {
  expect(parsed().helper).toBe('answered')
  expect(parsed().images.map((image) => image.id)).toEqual(['blank', 'openclaw', 'hermes'])
  expect(parsed().images[1]).toMatchObject(openclaw)
})

test('every helper word is accepted and any other is refused', () => {
  const helpers: ImageHelper[] = ['answered', 'old_helper', 'unreachable']
  for (const helper of helpers) expect(parseMachineImages(answer({ helper })).helper).toBe(helper)
  expect(() => parseMachineImages(answer({ helper: 'maybe' }))).toThrow(UnreadableAnswer)
})

test('anything that is not the promised shape is refused', () => {
  const bad: unknown[] = [null, 'x', 5, [], {}, { helper: 'answered' }, answer({ images: 'blank' }), answer({ images: [null] }), answer({ images: [{ ...blank, id: '' }] }),
    answer({ images: [{ ...blank, id: 7 }] }), answer({ images: [{ ...blank, title: undefined }] }), answer({ images: [{ ...blank, description: 3 }] }),
    answer({ images: [{ ...blank, state: 'soon' }] }), answer({ images: [{ ...blank, ready: 'yes' }] }), answer({ images: [{ ...blank, available: 1 }] }),
    answer({ images: [{ ...blank, reason: 4 }] }), answer({ images: [{ ...blank, reason: undefined }] }), answer({ images: [blank, blank] })]
  for (const item of bad) expect(() => parseMachineImages(item)).toThrow(UnreadableAnswer)
})

test('a planned image that claims to be available is refused', () => {
  expect(() => parseMachineImages(answer({ images: [blank, { ...openclaw, available: true }] }))).toThrow(UnreadableAnswer)
})

test('Blank is selectable and OpenClaw and Hermes are disabled with their reasons', () => {
  const options = imageOptions(parsed())
  expect(options.map((option) => [option.id, option.disabled])).toEqual([['blank', false], ['openclaw', true], ['hermes', true]])
  expect(options[0]?.title).toBe('Blank (plain Ubuntu)')
  expect(options[1]).toMatchObject({ title: 'OpenClaw', reason: COMING_SOON })
  expect(options[2]).toMatchObject({ title: 'Hermes', reason: WAITING })
})

test('before the answer arrives, or when it cannot be read, only Blank is offered', () => {
  const options = imageOptions(null)
  expect(options.map((option) => [option.id, option.disabled])).toEqual([['blank', false]])
  expect(options[0]?.title).toBe('Blank (plain Ubuntu)')
})

test('the cards say what Blank is, and give the reason as the caption of each image that cannot be picked', () => {
  const cards = imageCards(imageOptions(parsed()))
  expect(cards).toEqual([
    { id: 'blank', title: 'Blank (plain Ubuntu)', caption: 'Ubuntu 24.04 with the usual server tools. Nothing else.', disabled: false, tag: 'Default' },
    { id: 'openclaw', title: 'OpenClaw', caption: COMING_SOON, disabled: true, tag: 'Coming soon' },
    { id: 'hermes', title: 'Hermes', caption: WAITING, disabled: true, tag: 'Coming soon' },
  ])
  expect(imageCards(imageOptions(null)).map((card) => card.id)).toEqual(['blank'])
})

test('an image that cannot be picked and gave no reason still says so', () => {
  const quiet = parseMachineImages(answer({ images: [blank, { ...openclaw, reason: null }] }))
  expect(imageCards(imageOptions(quiet))[1]?.caption).toBe('not available yet')
})

test('the description of an image is what its card shows while it can be picked', () => {
  expect(imageOptions(parsed())[0]?.description).toBe('Ubuntu 24.04 with the usual server tools. Nothing else.')
})

test('hostile text from the parent stays text and changes nothing about who can be picked', () => {
  const hostile = '<img src=x onerror=alert(1)><script>window.pwned=1</script>'
  const evil = parseMachineImages(answer({ images: [blank, { ...openclaw, title: hostile, reason: hostile }] }))
  const options = imageOptions(evil)
  expect(imageCards(options)[1]).toEqual({ id: 'openclaw', title: hostile, caption: hostile, disabled: true, tag: 'Coming soon' })
  expect(options[1]?.disabled).toBe(true)
})

test('the choice stays when it can still be picked and goes back to Blank when it cannot', () => {
  const options = imageOptions(parsed())
  expect(imageAfterChange(options, 'blank')).toBe('blank')
  expect(imageAfterChange(options, 'openclaw')).toBe('blank')
  expect(imageAfterChange(options, 'hermes')).toBe('blank')
  expect(imageAfterChange(options, 'gone')).toBe('blank')
  const later = imageOptions(parseMachineImages(answer({ images: [blank, { ...openclaw, state: 'ready', ready: true, available: true, reason: null }] })))
  expect(imageAfterChange(later, 'openclaw')).toBe('openclaw')
})

test('the bundle is sent only when it is not Blank', () => {
  expect(imageBundle('blank')).toBeUndefined()
  expect(imageBundle(undefined)).toBeUndefined()
  expect(imageBundle('')).toBeUndefined()
  expect(imageBundle('openclaw')).toBe('openclaw')
})

test('an image that is not built yet is tagged Coming soon, one only waiting to be prepared on this machine is tagged Waiting', () => {
  const preparing = parseMachineImages(answer({ images: [blank, { ...hermes, state: 'ready', reason: WAITING }] }))
  expect(imageCards(imageOptions(preparing)).map((card) => card.tag)).toEqual(['Default', 'Waiting'])
  expect(imageCards(imageOptions(parsed())).map((card) => card.tag)).toEqual(['Default', 'Coming soon', 'Coming soon'])
})
