import green from '../assets/brand/avatars/green.webp'
import blue from '../assets/brand/avatars/blue.webp'
import amber from '../assets/brand/avatars/amber.webp'
import coral from '../assets/brand/avatars/coral.webp'
import lavender from '../assets/brand/avatars/lavender.webp'
import graphite from '../assets/brand/avatars/graphite.webp'
import type { Agent, AvatarChoice } from './types.ts'

/**
 * Bot avatars are Ruvi's plush snake family: one snake per avatar colour.
 * `shape` is the value stored with the colour, so existing bots and the API keep working.
 */
export interface AvatarSnake {
  name: string
  color: string
  shape: string
  src: string
}

/** The calm default: what junk colours fall back to. */
const GRAPHITE: AvatarSnake = { name: 'Graphite', color: '#1a1a1a', shape: 'orb', src: graphite }

export const AVATAR_SNAKES: readonly [AvatarSnake, ...AvatarSnake[]] = [
  { name: 'Green', color: '#00f56d', shape: 'pebble', src: green },
  { name: 'Blue', color: '#2563eb', shape: 'blob', src: blue },
  { name: 'Amber', color: '#f59e0b', shape: 'bean', src: amber },
  { name: 'Coral', color: '#dc2626', shape: 'egg', src: coral },
  { name: 'Lavender', color: '#7c3aed', shape: 'squircle', src: lavender },
  GRAPHITE,
]

const HEX_COLOR = /^#?([0-9a-f]{6})$/i

type Rgb = [number, number, number]
type BotLook = Pick<Agent, 'avatarColor' | 'createdAt'>

function rgb(hex: unknown): Rgb | null {
  const digits = HEX_COLOR.exec(String(hex).trim())?.[1]
  if (!digits) return null
  const value = parseInt(digits, 16)
  return [value >> 16, (value >> 8) & 0xff, value & 0xff]
}

function distance(a: Rgb, b: Rgb): number {
  return a.reduce((sum, channel, index) => sum + (channel - (b[index] ?? 0)) ** 2, 0)
}

const snakeRgb = (snake: AvatarSnake): Rgb => rgb(snake.color) ?? [0, 0, 0]

/** The snake for a stored avatar colour; any other hex gets the closest snake, junk gets graphite. */
export function avatarSnake(color: unknown): AvatarSnake {
  const target = rgb(color)
  if (!target) return GRAPHITE
  return AVATAR_SNAKES.reduce((best, snake) => (
    distance(snakeRgb(snake), target) < distance(snakeRgb(best), target) ? snake : best
  ))
}

/** Picker options: one per snake. */
export const avatarCatalog = AVATAR_SNAKES

export const isSameAvatar = (agent: Pick<Agent, 'avatarColor'> | null | undefined, option: AvatarSnake): boolean =>
  avatarSnake(agent?.avatarColor).color === option.color

/** The bot created most recently (ISO `createdAt`), or undefined for none. */
function newestBot(bots: readonly BotLook[]): BotLook | undefined {
  return bots.reduce<BotLook | undefined>((newest, bot) => (!newest || bot.createdAt > newest.createdAt ? bot : newest), undefined)
}

/**
 * A random snake for a new bot, never the colour of the bot made just before it, so two new bots
 * in a row are easy to tell apart. `random` returns [0, 1) like Math.random.
 */
export function pickNewBotAvatar(bots: readonly BotLook[] = [], random: () => number = Math.random): AvatarChoice {
  const last = newestBot(bots)
  const lastColor = last ? avatarSnake(last.avatarColor).color : ''
  const choices = AVATAR_SNAKES.filter(snake => snake.color !== lastColor)
  const snake = choices[Math.floor(random() * choices.length)] ?? GRAPHITE
  return { avatarShape: snake.shape, avatarColor: snake.color }
}
