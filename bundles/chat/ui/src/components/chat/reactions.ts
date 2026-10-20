import type { Reaction } from '../../lib/types.ts'

// Reactions; `emoji` is the stored key the API expects.
export const REACTIONS: ReadonlyArray<{ emoji: string; icon: string; label: string }> = [
  { emoji: 'check', icon: 'check', label: 'Acknowledge' },
  { emoji: 'eyes', icon: 'eye', label: 'Looking' },
  { emoji: 'heart', icon: 'heart', label: 'Love' },
]

export function reactionCount(reactions: readonly Reaction[] = [], emoji: string): number {
  return reactions.find(reaction => reaction.emoji === emoji)?.count || 0
}
