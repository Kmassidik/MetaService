// Routine card copy: one plain sentence for a routine's trigger ("Runs every weekday at 8:00").
// Mirrors the server's schedule kinds (ChatStore+SkillsMemoryRoutines.swift): weekday 1 = Sunday.
const DEFAULT_TIME = '09:00'
const DEFAULT_WEEKDAY = 2
const WEEKDAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
const WEBHOOK_TRIGGER = 'webhook'

// "08:00" → "8:00"; the card shows the routine's own clock time, not converted.
export function routineTime(time = DEFAULT_TIME) {
  const [hours, minutes] = String(time).split(':')
  return `${Number(hours)}:${minutes}`
}

function everyHours(hours) {
  return Number(hours) === 1 ? 'Runs every hour' : `Runs every ${hours} hours`
}

const DESCRIBE_KIND = {
  daily: schedule => `Runs every day at ${routineTime(schedule.time)}`,
  weekdays: schedule => `Runs every weekday at ${routineTime(schedule.time)}`,
  weekly: schedule => `Runs every ${WEEKDAY_NAMES[(schedule.weekday ?? DEFAULT_WEEKDAY) - 1]} at ${routineTime(schedule.time)}`,
  every_hours: schedule => everyHours(schedule.hours),
}

export function describeRoutine(routine) {
  if (routine?.triggerKind === WEBHOOK_TRIGGER) return 'Runs when its webhook is called'
  const describe = DESCRIBE_KIND[routine?.scheduleKind]
  return describe ? describe(routine.schedule || {}) : 'Runs on its schedule'
}
