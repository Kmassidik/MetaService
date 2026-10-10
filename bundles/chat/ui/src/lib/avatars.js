import green from '../assets/brand/avatars/green.webp'
import blue from '../assets/brand/avatars/blue.webp'
import amber from '../assets/brand/avatars/amber.webp'
import coral from '../assets/brand/avatars/coral.webp'
import lavender from '../assets/brand/avatars/lavender.webp'
import graphite from '../assets/brand/avatars/graphite.webp'

/**
 * Bot avatars are Ruvi's plush snake family: one snake per avatar colour.
 * `shape` is the value stored with the colour, so existing bots and the API keep working.
 */
export const AVATAR_SNAKES = [
  { name: 'Green', color: '#00f56d', shape: 'pebble', src: green },
  { name: 'Blue', color: '#2563eb', shape: 'blob', src: blue },
  { name: 'Amber', color: '#f59e0b', shape: 'bean', src: amber },
  { name: 'Coral', color: '#dc2626', shape: 'egg', src: coral },
  { name: 'Lavender', color: '#7c3aed', shape: 'squircle', src: lavender },
  { name: 'Graphite', color: '#1a1a1a', shape: 'orb', src: graphite },
]

const HEX_COLOR = /^#?([0-9a-f]{6})$/i

function rgb(hex) {
  const match = HEX_COLOR.exec(String(hex).trim())
  if (!match) return null
  const value = parseInt(match[1], 16)
  return [value >> 16, (value >> 8) & 0xff, value & 0xff]
}

function distance(a, b) {
  return a.reduce((sum, channel, index) => sum + (channel - b[index]) ** 2, 0)
}

/** The snake for a stored avatar colour; any other hex gets the closest snake, junk gets graphite. */
export function avatarSnake(color) {
  const target = rgb(color)
  if (!target) return AVATAR_SNAKES.at(-1)
  return AVATAR_SNAKES.reduce((best, snake) => (
    distance(rgb(snake.color), target) < distance(rgb(best.color), target) ? snake : best
  ))
}

/** Picker options: one per snake. */
export const avatarCatalog = AVATAR_SNAKES

export const isSameAvatar = (agent, option) => avatarSnake(agent?.avatarColor).color === option.color

/** The bot created most recently (ISO `createdAt`), or undefined for none. */
function newestBot(bots) {
  return bots.reduce((newest, bot) => (!newest || bot.createdAt > newest.createdAt ? bot : newest), undefined)
}

/**
 * A random snake for a new bot, never the colour of the bot made just before it, so two new bots
 * in a row are easy to tell apart. `random` returns [0, 1) like Math.random.
 */
export function pickNewBotAvatar(bots = [], random = Math.random) {
  const last = newestBot(bots)
  const lastColor = last ? avatarSnake(last.avatarColor).color : ''
  const choices = AVATAR_SNAKES.filter(snake => snake.color !== lastColor)
  const snake = choices[Math.floor(random() * choices.length)]
  return { avatarShape: snake.shape, avatarColor: snake.color }
}
