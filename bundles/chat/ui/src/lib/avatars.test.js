import { describe, expect, it } from 'vitest'
import { AVATAR_SNAKES, avatarSnake, isSameAvatar, pickNewBotAvatar } from './avatars.js'

describe('avatar snakes', () => {
  it('gives every stored avatar colour its own snake', () => {
    for (const snake of AVATAR_SNAKES) expect(avatarSnake(snake.color)).toBe(snake)
    expect(new Set(AVATAR_SNAKES.map(snake => snake.color)).size).toBe(AVATAR_SNAKES.length)
  })

  it('maps other hex colours to the closest snake', () => {
    expect(avatarSnake('#3B82F6').name).toBe('Blue')
    expect(avatarSnake('#8B5CF6').name).toBe('Lavender')
    expect(avatarSnake('#EC4899').name).toBe('Coral')
  })

  it('falls back to graphite for missing or malformed colours', () => {
    for (const value of [undefined, '', 'green', '#12']) expect(avatarSnake(value).name).toBe('Graphite')
  })

  it('treats any colour that resolves to the same snake as selected', () => {
    expect(isSameAvatar({ avatarColor: '#3B82F6' }, AVATAR_SNAKES[1])).toBe(true)
    expect(isSameAvatar({ avatarColor: '#00f56d' }, AVATAR_SNAKES[1])).toBe(false)
  })
})

describe('new bot avatar', () => {
  const bot = (avatarColor, createdAt) => ({ avatarColor, createdAt })

  it('never repeats the colour of the most recently created bot', () => {
    const bots = [bot('#2563eb', '2026-09-01T00:00:00Z'), bot('#00f56d', '2026-10-01T00:00:00Z')]
    for (let step = 0; step < 20; step += 1) {
      expect(pickNewBotAvatar(bots, () => step / 20).avatarColor).not.toBe('#00f56d')
    }
  })

  it('may reuse an older bot colour', () => {
    const bots = [bot('#2563eb', '2026-09-01T00:00:00Z'), bot('#00f56d', '2026-10-01T00:00:00Z')]
    const colours = new Set(Array.from({ length: 20 }, (_, step) => pickNewBotAvatar(bots, () => step / 20).avatarColor))
    expect(colours.has('#2563eb')).toBe(true)
  })

  it('pairs each colour with its stored snake shape', () => {
    for (let step = 0; step < 6; step += 1) {
      const avatar = pickNewBotAvatar([], () => step / 6)
      expect(AVATAR_SNAKES.find(snake => snake.color === avatar.avatarColor).shape).toBe(avatar.avatarShape)
    }
  })
})
