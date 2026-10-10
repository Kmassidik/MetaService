import { describe, expect, it } from 'vitest'
import { goalOptions } from './constants.js'
import { IDEA_LIMITS, WELCOME_IDEA_COUNT, starterIdeas, welcomeIdeas } from './starterIdeas.js'

const goalIds = goalOptions.map(([id]) => id)

describe('starter ideas', () => {
  it('have unique ids and fit what the server stores', () => {
    expect(new Set(starterIdeas.map(idea => idea.id)).size).toBe(starterIdeas.length)
    for (const idea of starterIdeas) {
      expect(idea.label.length).toBeLessThanOrEqual(IDEA_LIMITS.label)
      expect(idea.subtitle.length).toBeLessThanOrEqual(IDEA_LIMITS.subtitle)
      expect(idea.message.length).toBeLessThanOrEqual(IDEA_LIMITS.message)
    }
  })

  it('only tag real onboarding goals', () => {
    for (const idea of starterIdeas) for (const goal of idea.goals) expect(goalIds).toContain(goal)
  })

  it.each(goalIds)('gives a full card for the %s goal, matching ideas first', goal => {
    const picks = welcomeIdeas(goal)
    expect(picks).toHaveLength(WELCOME_IDEA_COUNT)
    expect(new Set(picks.map(idea => idea.id)).size).toBe(WELCOME_IDEA_COUNT)
    const matching = starterIdeas.filter(idea => idea.goals.includes(goal)).map(idea => idea.id)
    expect(picks.slice(0, Math.min(matching.length, WELCOME_IDEA_COUNT)).map(idea => idea.id))
      .toEqual(matching.slice(0, WELCOME_IDEA_COUNT))
  })

  it('leads with coding ideas for a coder', () => {
    expect(welcomeIdeas('coding').slice(0, 3).map(idea => idea.label)).toEqual(['Code helper', 'Data analyst', 'PR reviewer'])
  })

  it('falls back to the favourites without a goal', () => {
    expect(welcomeIdeas(undefined).map(idea => idea.id)).toEqual(starterIdeas.slice(0, WELCOME_IDEA_COUNT).map(idea => idea.id))
  })

  it('sends only what the card shows', () => {
    expect(Object.keys(welcomeIdeas('research')[0]).sort()).toEqual(['id', 'label', 'message', 'subtitle'])
  })
})
