/**
 * Starter ideas on a New bot's welcome card. Tapping one sends its `message` as the owner's first
 * message; the bot then names and sets itself up for that job. `goals` are onboarding goal ids
 * (constants.js goalOptions), so the card leads with ideas for what the owner said they want.
 */

export const WELCOME_IDEA_COUNT = 6
export const IDEA_LIMITS = { label: 60, subtitle: 120, message: 500 }

export const starterIdeas = [
  {
    id: 'inbox-triage', label: 'Inbox triage', subtitle: 'Sort email and draft replies',
    message: 'Be my inbox triage bot: go through my unread email, tell me what needs me today and draft replies for me to approve.',
    goals: ['personal_assistant', 'business'],
  },
  {
    id: 'daily-brief', label: 'Daily brief', subtitle: 'A short brief every morning',
    message: 'Be my daily brief bot: every weekday morning give me my calendar, the emails that matter and news on topics I follow.',
    goals: ['personal_assistant', 'automation'],
  },
  {
    id: 'deep-research', label: 'Deep research', subtitle: 'Sourced reports on any question',
    message: 'Be my research bot: investigate questions I give you and write short reports with sources.',
    goals: ['research', 'other'],
  },
  {
    id: 'content-writer', label: 'Content writer', subtitle: 'Drafts in your voice',
    message: 'Be my writing partner: help me draft posts and newsletters in my voice.',
    goals: ['content'],
  },
  {
    id: 'code-helper', label: 'Code helper', subtitle: 'Debug, refactor and test',
    message: 'Be my coding partner: help me debug, refactor and test code on your computer.',
    goals: ['coding'],
  },
  {
    id: 'data-analyst', label: 'Data analyst', subtitle: 'Spreadsheets in, findings out',
    message: 'Be my data analyst: analyze spreadsheets or CSV files I upload and explain what you find.',
    goals: ['research', 'business', 'coding'],
  },
  {
    id: 'calendar-coordinator', label: 'Calendar coordinator', subtitle: 'Find time and prep meetings',
    message: 'Be my calendar coordinator: find free time, protect focus blocks and prepare me for meetings.',
    goals: ['personal_assistant', 'business'],
  },
  {
    id: 'meeting-notes', label: 'Meeting notes', subtitle: 'Decisions and action items',
    message: 'Turn my meeting notes into decisions, action items with owners and a follow-up email.',
    goals: ['business', 'personal_assistant'],
  },
  {
    id: 'task-keeper', label: 'Task keeper', subtitle: 'To-dos and reminders',
    message: 'Be my task keeper: keep my to-do list and remind me about what is slipping.',
    goals: ['personal_assistant', 'automation'],
  },
  {
    id: 'competitor-watch', label: 'Competitor watch', subtitle: 'Weekly changes across rivals',
    message: 'Watch my competitors’ websites every week and tell me only what changed.',
    goals: ['research', 'business', 'automation'],
  },
  {
    id: 'topic-digest', label: 'Topic digest', subtitle: 'News on topics you follow',
    message: 'Send me a digest on the topics I follow, with sources, at a time I choose.',
    goals: ['research', 'content', 'automation'],
  },
  {
    id: 'smart-shopper', label: 'Smart shopper', subtitle: 'Compare before you buy',
    message: 'Help me compare options before I buy something, with prices and a clear pick.',
    goals: ['personal_assistant', 'research'],
  },
  {
    id: 'pr-reviewer', label: 'PR reviewer', subtitle: 'Bugs, risks and missing tests',
    message: 'Review my pull requests for bugs, risks and missing tests.',
    goals: ['coding'],
  },
  {
    id: 'release-notes', label: 'Release notes', subtitle: 'Changelogs from merged work',
    message: 'Write release notes from the work we merged.',
    goals: ['coding', 'content'],
  },
  {
    id: 'social-media', label: 'Social media', subtitle: 'Plan and draft posts',
    message: 'Plan and draft my social media posts; I approve each one before it goes out.',
    goals: ['content', 'business'],
  },
  {
    id: 'support-desk', label: 'Support desk', subtitle: 'Triage tickets, draft replies',
    message: 'Help me answer customer support requests with accurate draft replies.',
    goals: ['business'],
  },
  {
    id: 'web-chores', label: 'Web chores', subtitle: 'Repetitive browser tasks',
    message: 'Do a repetitive task on a website for me, in your own browser.',
    goals: ['automation', 'other'],
  },
]

const card = ({ id, label, subtitle, message }) => ({ id, label, subtitle, message })

/**
 * The ideas for a welcome card: those that match the onboarding goal first, then the general
 * favourites in catalogue order, without repeats. Unknown or missing goals get the favourites.
 */
export function welcomeIdeas(goal, catalogue = starterIdeas, count = WELCOME_IDEA_COUNT) {
  const matching = catalogue.filter(idea => idea.goals.includes(goal))
  const rest = catalogue.filter(idea => !matching.includes(idea))
  return [...matching, ...rest].slice(0, count).map(card)
}
