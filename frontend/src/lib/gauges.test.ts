import { describe, expect, test } from 'bun:test'
import { gaugeSpecs, loadGauge, rootDisk } from './gauges.ts'
import { sampleStats } from './stats.test.ts'

const spec = (key: string, stats = sampleStats()) => gaugeSpecs(stats).find((gauge) => gauge.key === key)

describe('the five gauges', () => {
  test('are CPU, memory, load, swap and disk, in that order', () => {
    expect(gaugeSpecs(sampleStats()).map((gauge) => gauge.key)).toEqual(['cpu', 'memory', 'load', 'swap', 'disk'])
  })

  test('CPU says the percent and a screen reader hears it in words', () => {
    expect(spec('cpu')).toMatchObject({ percent: 12.5, value: '13%', describe: 'CPU 13 percent', level: 'normal' })
  })

  test('CPU still measuring is an empty arc that says so, never 0', () => {
    const measuring = sampleStats({ cpu: { ...sampleStats().cpu, total_percent: null } })
    expect(spec('cpu', measuring)).toMatchObject({ percent: null, value: 'measuring…', describe: 'CPU still being measured' })
  })

  test('memory is used over total with the sizes under it', () => {
    expect(spec('memory')).toMatchObject({ percent: 50, value: '50%', caption: '4 GB of 8 GB' })
  })

  test('colour follows the number but the number is always there', () => {
    const busy = sampleStats({ cpu: { ...sampleStats().cpu, total_percent: 95 } })
    expect(spec('cpu', busy)).toMatchObject({ level: 'critical', value: '95%' })
    const high = sampleStats({ cpu: { ...sampleStats().cpu, total_percent: 80 } })
    expect(spec('cpu', high)?.level).toBe('high')
  })
})

describe('load', () => {
  test('is the 5 minute load against the number of CPUs and shows the load itself', () => {
    expect(loadGauge(sampleStats())).toMatchObject({ percent: 45, value: '0.90', caption: 'of 2 CPUs' })
  })

  test('a load above the CPU count is a full arc, not more', () => {
    const swamped = sampleStats({ cpu: { ...sampleStats().cpu, load: { one: 9, five: 9, fifteen: 9 } } })
    expect(loadGauge(swamped)).toMatchObject({ percent: 100, level: 'critical', value: '9.00' })
  })

  test('a load the system cannot say is empty', () => {
    const unknown = sampleStats({ cpu: { ...sampleStats().cpu, load: { one: null, five: null, fifteen: null } } })
    expect(loadGauge(unknown)).toMatchObject({ percent: null, value: '–', describe: 'Load not known' })
  })
})

describe('swap and disk', () => {
  test('no swap says none instead of 0 percent', () => {
    expect(spec('swap')).toMatchObject({ percent: null, value: 'none' })
  })

  test('swap in use is a percent of the swap', () => {
    const swapping = sampleStats({ memory: { ...sampleStats().memory, swap_total_bytes: 1000, swap_used_bytes: 250 } })
    expect(spec('swap', swapping)).toMatchObject({ percent: 25, value: '25%' })
  })

  test('disk is the root volume, or the first one', () => {
    expect(spec('disk')).toMatchObject({ percent: 40, caption: '/ · 40 GB of 100 GB' })
    const disks = [{ mount: '/Volumes/Data', name: 'D', fs: 'apfs', total_bytes: 100, used_bytes: 10, free_bytes: 90 }, { mount: '/', name: 'R', fs: 'apfs', total_bytes: 100, used_bytes: 90, free_bytes: 10 }]
    expect(rootDisk(disks)?.name).toBe('R')
    expect(rootDisk(disks.slice(0, 1))?.name).toBe('D')
    expect(rootDisk([])).toBeNull()
  })

  test('no disk at all is an empty gauge', () => {
    expect(spec('disk', sampleStats({ disks: [] }))).toMatchObject({ percent: null, value: '–' })
  })
})
