// "Check the GPU": reads the parent's answer and turns it into the words the VM page shows. Pure functions, no DOM, no network.

export type GpuHow = 'nvidia-smi' | 'device nodes' | 'none'

/** What the parent says about the GPU inside one container. `detail` and `note` came from the machine and from inside the container: show them as text only. */
export interface GpuCheckAnswer {
  gpu_visible: boolean
  how: GpuHow
  detail: string
  note: string
}

const HOWS: readonly string[] = ['nvidia-smi', 'device nodes', 'none']
const FIELDS = ['gpu_visible', 'how', 'detail', 'note']

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value)

const isHow = (value: unknown): value is GpuHow => typeof value === 'string' && HOWS.includes(value)

/** The answer when it is exactly the shape the parent promises; otherwise null. */
export function parseGpuCheck(data: unknown): GpuCheckAnswer | null {
  if (!isRecord(data) || Object.keys(data).length !== FIELDS.length) return null
  const { gpu_visible, how, detail, note } = data
  if (typeof gpu_visible !== 'boolean' || !isHow(how) || typeof detail !== 'string' || typeof note !== 'string') return null
  return { gpu_visible, how, detail, note }
}

export const GPU_VISIBLE_TEXT = 'The GPU is visible inside.'
export const GPU_HIDDEN_TEXT = 'The GPU is not visible inside.'
export const UNREADABLE_TEXT = 'The parent answered in a way this page cannot read.'

export const headline = (answer: GpuCheckAnswer): string => (answer.gpu_visible ? GPU_VISIBLE_TEXT : GPU_HIDDEN_TEXT)

const HOW_LABELS: Record<GpuHow, string> = { 'nvidia-smi': 'Seen with nvidia-smi', 'device nodes': 'Seen in the device files (no nvidia-smi)', none: 'Nothing found' }

/** The evidence line: how it was seen, and what was seen when there is something. */
export function evidence(answer: GpuCheckAnswer): string {
  const label = HOW_LABELS[answer.how]
  return answer.detail === '' ? label : `${label}: ${answer.detail}`
}
