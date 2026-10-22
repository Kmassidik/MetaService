// The GPU on the Live tab, as browser checks: the gauge, the four charts (use, memory, temperature, power), the card with the maker chip, the programs list and the Mac note.
// Machines: studio (one NVIDIA), duo (NVIDIA and AMD), macgpu (an Apple GPU: use and memory only) and mini (no GPU at all).
import type { Page } from 'puppeteer-core'
import { openMachine } from '../machine/steps.ts'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { MAC_NOTE } from '../../src/lib/gpuView.ts'
import { SIZES, waitForNumbers } from './live-steps.ts'
import type { StandIn } from './stand-in.ts'

const SETTLE_MS = 400

interface GpuLook {
  gauge: string
  gaugeCaption: string
  charts: string[]
  chips: string[]
  facts: string[]
  programs: number
  macNote: boolean
  legendNames: string[]
  zeroText: boolean
  cardGroups: string[]
  lineCounts: number[]
}

/** What the page shows about the GPU, read in one go. */
const look = (b: Browse): Promise<GpuLook> =>
  b.run(() => {
    const text = (selector: string) => document.querySelector<HTMLElement>(selector)?.innerText ?? ''
    const charts = [...document.querySelectorAll<HTMLElement>('[data-testid=monitor-numbers] .chart')].map((chart) => chart.dataset.testid ?? '').filter((name) => name.startsWith('chart-GPU'))
    const gpuCard = document.querySelector<HTMLElement>('section[aria-label=GPU]:not(:has(.dial))')
    return {
      gauge: text('[data-testid=gauge-gpu]'),
      gaugeCaption: document.querySelector('[data-testid=gauge-gpu]')?.closest('section')?.querySelector<HTMLElement>('.caption')?.innerText ?? '',
      charts,
      chips: [...document.querySelectorAll<HTMLElement>('[data-testid=gpu-vendor]')].map((chip) => chip.innerText),
      facts: [...document.querySelectorAll<HTMLElement>('[data-testid^=gpu-]')].map((one) => one.dataset.testid ?? '').filter((id) => /^gpu-(temperature|power|fan|clock)$/.test(id)),
      programs: document.querySelectorAll('[data-testid=gpu-programs] li').length,
      macNote: document.querySelector('[data-testid=gpu-mac-note]') !== null,
      legendNames: [...document.querySelectorAll<HTMLElement>('[data-testid="chart-GPU use"] .legend td.name')].map((cell) => cell.innerText.trim()),
      zeroText: /\b0 W\b|\b0 °C\b|\b0 MHz\b/.test(gpuCard?.innerText ?? ''),
      cardGroups: [...document.querySelectorAll<HTMLElement>('[data-testid^=band-gpu]')].map((band) => band.dataset.testid ?? ''),
      lineCounts: [...document.querySelectorAll<HTMLElement>('[data-testid="chart-GPU use"] svg path.line')].map((path) => (path.getAttribute('d') ?? '').length),
    }
  })

async function openGpuMachine(b: Browse, world: StandIn, id: string) {
  await openMachine(b, world.base, id)
  await waitForNumbers(b)
  await wait(SETTLE_MS)
}

async function oneNvidia(page: Page, b: Browse, world: StandIn) {
  await page.setViewport(SIZES.desktop)
  await openGpuMachine(b, world, 'studio')
  const seen = await look(b)
  check('studio: the GPU gauge is the sixth gauge and shows a percent', /^\d+%$/.test(seen.gauge) && seen.gaugeCaption.includes('NVIDIA'), `${seen.gauge} | ${seen.gaugeCaption}`)
  check('studio: the charts GPU use, memory, temperature and power are there', seen.charts.join('|') === 'chart-GPU use|chart-GPU memory|chart-GPU temperature|chart-GPU power', seen.charts.join('|'))
  check('studio: the card has the NVIDIA chip, temperature, power with its limit, fan and clock', seen.chips.join() === 'NVIDIA' && seen.facts.join() === 'gpu-temperature,gpu-power,gpu-fan,gpu-clock', `${seen.chips} ${seen.facts}`)
  const power = await b.run(() => document.querySelector<HTMLElement>('[data-testid=gpu-power]')?.innerText ?? '')
  check('studio: power is written with its limit ("120 W of 575 W")', /^\d+ W of 575 W$/.test(power), power)
  check('studio: "Programs using the GPU" lists the programs with their memory', seen.programs === 2 && (await b.text()).toLowerCase().includes('programs using the gpu') && (await b.text()).includes('llama-server'))
  check('studio: no Mac note on an NVIDIA machine', !seen.macNote)
  check('studio: one GPU is named "GPU · RTX 5090" in the legend', seen.legendNames.join() === 'GPU · RTX 5090', seen.legendNames.join())
  await b.shot('gpu-studio-desktop.png', true)
  await page.setViewport(SIZES.phone)
  await wait(SETTLE_MS)
  check('studio: no sideways scroll at 400 px', await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
  await b.shot('gpu-studio-phone.png', true)
}

async function twoMixed(page: Page, b: Browse, world: StandIn) {
  await page.setViewport(SIZES.desktop)
  await openGpuMachine(b, world, 'duo')
  const seen = await look(b)
  check('duo: the gauge is the busiest of 2 GPUs', /^\d+%$/.test(seen.gauge) && seen.gaugeCaption === 'busiest of 2 GPUs', `${seen.gauge} | ${seen.gaugeCaption}`)
  check('duo: the lines are named "GPU 0 · RTX 5090" and "GPU 1 · RX 7900 XTX"', seen.legendNames.join('|') === 'GPU 0 · RTX 5090|GPU 1 · RX 7900 XTX', seen.legendNames.join('|'))
  check('duo: both lines are drawn in the use chart', seen.lineCounts.length === 2 && seen.lineCounts.every((length) => length > 40), seen.lineCounts.join(','))
  check('duo: the card has an NVIDIA chip and an AMD chip, and programs only for NVIDIA', seen.chips.join() === 'NVIDIA,AMD' && seen.programs === 2, `${seen.chips} ${seen.programs}`)
  check('duo: the temperature and power charts have a line per GPU', await b.run(() => ['GPU temperature', 'GPU power'].every((name) => document.querySelectorAll(`[data-testid="chart-${name}"] svg path.line`).length === 2)))
  check('duo: units are not mixed: the temperature axis says °C and the power axis says W', await b.run(() => {
    const last = (chart: string) => [...document.querySelectorAll(`[data-testid="chart-${chart}"] .ylabel`)].pop()?.textContent ?? ''
    return last('GPU temperature').includes('°C') && last('GPU power').endsWith(' W')
  }))
  await b.shot('gpu-duo-desktop.png', true)
  await page.setViewport(SIZES.phone)
  await wait(SETTLE_MS)
  check('duo: no sideways scroll at 400 px', await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
  await b.shot('gpu-duo-phone.png', true)
}

async function appleOnly(page: Page, b: Browse, world: StandIn) {
  await page.setViewport(SIZES.desktop)
  await openGpuMachine(b, world, 'macgpu')
  const seen = await look(b)
  check('macgpu: the gauge and the use and memory charts are there', /^\d+%$/.test(seen.gauge) && seen.charts.join('|') === 'chart-GPU use|chart-GPU memory', `${seen.gauge} | ${seen.charts.join('|')}`)
  check('macgpu: no temperature or power chart, and no temperature, power, fan or clock line, and no 0 W or 0 °C', seen.facts.length === 0 && seen.cardGroups.join() === 'band-gpu-use' && !seen.zeroText, `${seen.facts} ${seen.cardGroups}`)
  check('macgpu: the Apple chip and the note about shared memory and administrator rights', seen.chips.join() === 'APPLE' && seen.macNote && (await b.text()).includes(MAC_NOTE))
  check('macgpu: no programs list on a Mac', seen.programs === 0 && !(await b.text()).toLowerCase().includes('programs using the gpu'))
  const memory = await b.run(() => document.querySelector<HTMLElement>('[data-testid="chart-GPU memory"] .ylabel')?.textContent ?? '')
  check('macgpu: the memory axis starts at 0', memory.trim().startsWith('0'), memory)
  await b.shot('gpu-mac-desktop.png', true)
  await page.setViewport(SIZES.phone)
  await wait(SETTLE_MS)
  check('macgpu: no sideways scroll at 400 px', await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
  await b.shot('gpu-mac-phone.png', true)
}

async function noGpu(page: Page, b: Browse, world: StandIn) {
  await page.setViewport(SIZES.desktop)
  await openGpuMachine(b, world, 'mini')
  const seen = await look(b)
  check('mini (no GPU): no GPU gauge, charts, card or note', seen.gauge === '' && seen.charts.length === 0 && seen.cardGroups.length === 0 && seen.chips.length === 0 && !seen.macNote)
  check('mini (no GPU): the page still has its other cards', await b.run(() => document.querySelectorAll('[data-testid=gauge-row] section').length === 5 && !!document.querySelector('[data-testid=band-network]')))
  await b.shot('gpu-none-desktop.png', true)
  await page.setViewport(SIZES.phone)
  await wait(SETTLE_MS)
  await b.shot('gpu-none-phone.png', true)
}

async function offlineKeepsTheHour(page: Page, b: Browse, world: StandIn) {
  await page.setViewport(SIZES.desktop)
  await openGpuMachine(b, world, 'duo')
  world.takeOffline('duo')
  await b.until(() => /offline, last seen/.test(document.body.innerText), { timeout: 9000 })
  const seen = await look(b)
  const grey = await b.run(() => getComputedStyle(document.querySelector('[data-testid=monitor-numbers]') ?? document.body).opacity)
  check('offline: the GPU charts stay with their last hour, greyed', Number(grey) < 1 && seen.charts.length === 4 && seen.lineCounts.every((length) => length > 40), `${grey} ${seen.charts.length} ${seen.lineCounts}`)
  await b.shot('gpu-duo-offline.png', true)
}

export async function gpuOnTheLiveTab(page: Page, b: Browse, world: StandIn) {
  await oneNvidia(page, b, world)
  await twoMixed(page, b, world)
  await appleOnly(page, b, world)
  await noGpu(page, b, world)
  await offlineKeepsTheHour(page, b, world)
  await page.setViewport(SIZES.desktop)
}
