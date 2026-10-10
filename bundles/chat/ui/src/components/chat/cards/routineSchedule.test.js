import { describe, expect, it } from 'vitest'
import { describeRoutine, routineTime } from './routineSchedule.js'

describe('describeRoutine', () => {
  it('describes weekday schedules like the reference', () => {
    expect(describeRoutine({ scheduleKind: 'weekdays', schedule: { time: '08:00' } })).toBe('Runs every weekday at 8:00')
  })
  it('describes daily, weekly and hourly schedules', () => {
    expect(describeRoutine({ scheduleKind: 'daily', schedule: { time: '18:30' } })).toBe('Runs every day at 18:30')
    expect(describeRoutine({ scheduleKind: 'weekly', schedule: { weekday: 2, time: '09:00' } })).toBe('Runs every Monday at 9:00')
    expect(describeRoutine({ scheduleKind: 'every_hours', schedule: { hours: 1 } })).toBe('Runs every hour')
    expect(describeRoutine({ scheduleKind: 'every_hours', schedule: { hours: 6 } })).toBe('Runs every 6 hours')
  })
  it('uses the server defaults when fields are missing', () => {
    expect(describeRoutine({ scheduleKind: 'weekly', schedule: {} })).toBe('Runs every Monday at 9:00')
  })
  it('describes webhooks and unknown kinds without inventing a time', () => {
    expect(describeRoutine({ triggerKind: 'webhook', scheduleKind: 'daily' })).toBe('Runs when its webhook is called')
    expect(describeRoutine({ scheduleKind: 'cron' })).toBe('Runs on its schedule')
    expect(describeRoutine(null)).toBe('Runs on its schedule')
  })
})

describe('routineTime', () => {
  it('drops the leading zero of the hour', () => {
    expect(routineTime('08:05')).toBe('8:05')
    expect(routineTime()).toBe('9:00')
  })
})
