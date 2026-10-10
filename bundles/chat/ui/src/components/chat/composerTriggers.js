// Inline picker triggers for the composer: "/" opens skills, "@" opens mentions.

export const SKILL_TRIGGER = '/'
export const MENTION_TRIGGER = '@'
const WORD_BOUNDARY = /\s/

function typedAtStart(value, caret) {
  return caret === 1 && value.startsWith(SKILL_TRIGGER)
}

function typedAfterBoundary(value, caret) {
  const before = value.charAt(caret - 2)
  return caret === 1 || WORD_BOUNDARY.test(before)
}

/**
 * Which picker the keystroke should open: 'skill', 'mention' or ''.
 * A skill trigger only counts as the first character, so paths like "a/b" stay text;
 * a mention trigger needs a word boundary, so e-mail addresses stay text.
 */
export function composerTrigger(value, caret, typed) {
  if (typed === SKILL_TRIGGER && typedAtStart(value, caret)) return 'skill'
  if (typed === MENTION_TRIGGER && typedAfterBoundary(value, caret)) return 'mention'
  return ''
}

/** The draft with the just-typed trigger character removed, so the picker owns the query. */
export function withoutTrigger(value, caret) {
  return value.slice(0, caret - 1) + value.slice(caret)
}
