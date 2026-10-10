export const NEW_BOT_NAME = 'New bot'

export const MiB = 1024 * 1024

// The width at which the bot list becomes a drawer; style.css lists every breakpoint.
export const DRAWER_MAX_WIDTH = 820

export const terminalRunStates = ['succeeded', 'failed', 'cancelled', 'interrupted']
// The one-time wait for a new private computer, quoted while a first message waits for it.
export const SETUP_EXPECTED_SECONDS = 15
// A task's external-action approval that still waits for the owner (the server's state name).
export const APPROVAL_PENDING = 'pending'

/** The Ruvio green snake: the face of the first-run empty state. */
export const DEFAULT_AVATAR_SHAPE = 'pebble'
export const DEFAULT_AVATAR_COLOR = '#00f56d'

// Group chats are capped per account, separate from the plan's bot limit; the API enforces it too.
export const MAX_GROUP_CHATS = 3
// One lead plus up to this many members per group chat (the API rejects more).
export const MAX_GROUP_MEMBERS = 4
export const botLimitReason = max => `You’ve reached your limit of ${max} bots. Delete one from its ⋯ menu to make room.`
export const GROUP_LIMIT_REASON = `All ${MAX_GROUP_CHATS} group chat slots are in use.`

/** A bot profile's field limits in UTF-8 bytes; the API enforces the same. */
export const PROFILE_LIMITS = Object.freeze({ name: 120, title: 60, summary: 200, instructions: 4000 })

/** Ids of the sheets WorkspaceModals can show (chat.modal); `openModal(MODALS.x)` opens one. */
export const MODALS = Object.freeze({
  account: 'account',
  create: 'create',
  createTeam: 'create-team',
  delete: 'delete',
  edit: 'edit',
  help: 'help',
  marketplace: 'marketplace',
})

export const instructionPresets = [
  { id: 'assistant', name: 'Personal assistant', text: 'Help me plan and organize my work. Be practical, concise and friendly. Clarify ambiguous requests, present actionable next steps, and never claim an action is complete without evidence.' },
  { id: 'research', name: 'Research partner', text: 'Help me research questions and compare options. Cite consulted sources, distinguish facts from assumptions, and explain uncertainty. Summarize findings clearly and do not invent references.' },
  { id: 'coding', name: 'Coding partner', text: 'Help me understand and improve code. Prioritize correctness, security and maintainability. Explain tradeoffs concisely, respect the existing stack, and distinguish tested behavior from suggestions.' },
  { id: 'creative', name: 'Creative partner', text: 'Help me brainstorm, write and refine content. Ask about audience and tone when unclear. Offer distinct options, preserve my intent, and clearly label fictional examples and unverified claims.' },
  { id: 'analyst', name: 'Data analyst', text: 'Help me analyze data and communicate findings. Check units, assumptions and calculations. Explain missing data and limitations, separate correlation from causation, and never invent results.' },
]

export const goalOptions = [
  ['personal_assistant', 'Personal assistant'],
  ['research', 'Research & learning'],
  ['business', 'Business operations'],
  ['content', 'Content & marketing'],
  ['coding', 'Coding & technical work'],
  ['automation', 'Automation'],
  ['other', 'Something else'],
]

export const sourceOptions = [
  ['friend', 'Friend or colleague'],
  ['social', 'Social media'],
  ['search', 'Search engine'],
  ['community', 'Online community'],
  ['event', 'Event or meetup'],
  ['other', 'Somewhere else'],
]

/** Icon sizes in px: chevrons, inline row buttons, list icons, header buttons. */
export const ICON_SIZE = Object.freeze({ chevron: 15, inline: 16, list: 17, header: 19 })
