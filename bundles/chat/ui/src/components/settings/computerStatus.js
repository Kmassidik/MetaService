/** Words for Settings › Computer: the status, a one-line note, and storage warnings. */

const STATUS_LABELS = {
  ready: 'Ready',
  suspended: 'Asleep',
  provisioning: 'Setting up',
  deleting: 'Deleting',
  failed: 'Needs attention',
}
const ACTION_LABELS = { wake: 'Waking…', suspend: 'Going to sleep…', delete: 'Deleting…' }
const STATUS_NOTES = {
  ready: 'One private machine shared by all your bots. Sleep it to free host resources.',
  suspended: 'Asleep. Any message wakes it, or wake it here.',
  deleting: 'Deleting. You can close Settings; cleanup continues.',
  failed: 'Needs attention. See the error below.',
}
const NO_COMPUTER = 'Not created'
export const NO_COMPUTER_NOTE = 'Created with your first bot.'
const SETTING_UP_NOTE = 'Setting up your computer…'
const WARN_STATES = ['full', 'warning']
const BYTES_PER_GB = 1e9
const GB_FORMAT = new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 })

/** A running action (Waking…) wins over the stored state. */
export function computerStatusLabel(environment, action) {
  if (ACTION_LABELS[action]) return ACTION_LABELS[action]
  if (!environment) return NO_COMPUTER
  return STATUS_LABELS[environment.state] || environment.state
}

export function computerStatusNote(environment) {
  if (!environment) return NO_COMPUTER_NOTE
  return STATUS_NOTES[environment.state] || SETTING_UP_NOTE
}

/** "Workspace is almost full." for a meter near or at its limit, otherwise ''. */
export function storageWarning(meter, noun) {
  if (!WARN_STATES.includes(meter?.state)) return ''
  return `${noun} is ${meter.state === 'full' ? 'full' : 'almost full'}.`
}

export function storageUsed(meter) {
  return `${GB_FORMAT.format((meter.usedBytes || 0) / BYTES_PER_GB)} of ${GB_FORMAT.format((meter.limitBytes || 0) / BYTES_PER_GB)} GB`
}
