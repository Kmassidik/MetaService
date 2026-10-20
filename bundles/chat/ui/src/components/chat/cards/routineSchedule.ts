/** The `schedule` of a routine, as the server sends it (which fields exist depends on `scheduleKind`). */
export interface ScheduleFields {
  time?: string
  weekday?: number
  hours?: number
}

/** The part of a routine the sentence reads. The server sends `schedule` as an object; a plain string has no fields. */
export interface RoutineLike {
  triggerKind?: string | undefined
  scheduleKind?: string | undefined
  schedule?: ScheduleFields | string | undefined
}

// Routine card copy: one plain sentence for a routine's trigger ("Runs every weekday at 8:00").
// Mirrors the server's schedule kinds (ChatStore+SkillsMemoryRoutines.swift): weekday 1 = Sunday.
const DEFAULT_TIME = '09:00'
const DEFAULT_WEEKDAY = 2
const WEEKDAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
const WEBHOOK_TRIGGER = 'webhook'

// "08:00" → "8:00"; the card shows the routine's own clock time, not converted.
export function routineTime(time: string = DEFAULT_TIME): string {
  const [hours, minutes] = String(time).split(':')
  return `${Number(hours)}:${minutes}`
}

function everyHours(hours: number | undefined): string {
  return Number(hours) === 1 ? 'Runs every hour' : `Runs every ${hours} hours`
}

const DESCRIBE_KIND: Record<string, (schedule: ScheduleFields) => string> = {
  daily: schedule => `Runs every day at ${routineTime(schedule.time)}`,
  weekdays: schedule => `Runs every weekday at ${routineTime(schedule.time)}`,
  weekly: schedule => `Runs every ${WEEKDAY_NAMES[(schedule.weekday ?? DEFAULT_WEEKDAY) - 1] ?? ''} at ${routineTime(schedule.time)}`,
  every_hours: schedule => everyHours(schedule.hours),
}

function scheduleFields(schedule: RoutineLike['schedule']): ScheduleFields {
  return typeof schedule === 'object' ? schedule : {}
}

export function describeRoutine(routine: RoutineLike | null | undefined): string {
  if (routine?.triggerKind === WEBHOOK_TRIGGER) return 'Runs when its webhook is called'
  const describe = routine?.scheduleKind ? DESCRIBE_KIND[routine.scheduleKind] : undefined
  return describe ? describe(scheduleFields(routine?.schedule)) : 'Runs on its schedule'
}
