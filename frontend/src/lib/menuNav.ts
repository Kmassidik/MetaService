// Which line of an open list the arrow keys move to. Lines that cannot be picked are skipped. Pure functions, no DOM.

export type MenuKey = 'ArrowDown' | 'ArrowUp' | 'Home' | 'End'

const MOVING_KEYS: readonly string[] = ['ArrowDown', 'ArrowUp', 'Home', 'End']

/** True when the key moves through the list. */
export const isMenuKey = (key: string): key is MenuKey => MOVING_KEYS.includes(key)

/** The line to land on after `key`, starting at `current`; stays where it is when there is nowhere to go. `disabled` has one entry per line. */
export function nextActive(disabled: readonly boolean[], current: number, key: MenuKey): number {
  const pickable = disabled.flatMap((off, index) => (off ? [] : [index]))
  if (key === 'Home') return pickable[0] ?? current
  if (key === 'End') return pickable[pickable.length - 1] ?? current
  if (key === 'ArrowDown') return pickable.find((index) => index > current) ?? current
  return pickable.filter((index) => index < current).pop() ?? current
}

/** The first line that can be picked (0 when none can); where a list that just opened puts its cursor when the chosen line is not there. */
export const firstPickable = (disabled: readonly boolean[]): number => Math.max(0, disabled.findIndex((off) => !off))
