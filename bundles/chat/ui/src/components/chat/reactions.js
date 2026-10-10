// Reactions; `emoji` is the stored key the API expects.
export const REACTIONS = [
  { emoji: 'check', icon: 'check', label: 'Acknowledge' },
  { emoji: 'eyes', icon: 'eye', label: 'Looking' },
  { emoji: 'heart', icon: 'heart', label: 'Love' },
]

export function reactionCount(reactions = [], emoji) {
  return reactions.find(reaction => reaction.emoji === emoji)?.count || 0
}
