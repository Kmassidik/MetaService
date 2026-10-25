// A storage map shaped like a 4 TB DGX Spark's disk, for the Storage tab test: models, a Hugging Face cache, Incus and Docker under /var/lib,
// a Rust and a web project (with build output and node_modules), and one folder with markup in its name. The same shape as the Fake Agent's map.
const GIB = 1024 ** 3
const MIB = 1024 ** 2
const NOW = Math.floor(Date.now() / 1000)
const DAY = 86400
export const TOTAL_BYTES = 4031 * 10 ** 9
export const HIDDEN_BYTES = 38 * GIB
export const HOSTILE_FOLDER = '<img src=x onerror=alert(3)>'

interface Entry { name: string; type: 'dir' | 'file' | 'rest'; bytes: number; files: number; items: number; kind: string; reclaim: string | null; modified: number; children: Entry[] }

const file = (name: string, bytes: number, kind = 'other', reclaim: string | null = null, ageDays = 3): Entry => ({ name, type: 'file', bytes, files: 1, items: 0, kind, reclaim, modified: NOW - ageDays * DAY, children: [] })
const rest = (items: number, bytes: number, files: number, kind = 'other', reclaim: string | null = null): Entry => ({ name: '', type: 'rest', bytes, files, items, kind, reclaim, modified: NOW - 9 * DAY, children: [] })
function dir(name: string, children: Entry[], kind = 'other', reclaim: string | null = null): Entry {
  const sorted = [...children].sort((a, b) => b.bytes - a.bytes)
  return { name, type: 'dir', bytes: 4096 + sorted.reduce((sum, child) => sum + child.bytes, 0), files: sorted.reduce((sum, child) => sum + child.files, 0), items: sorted.length, kind, reclaim,
    modified: Math.max(NOW - 30 * DAY, ...sorted.map((child) => child.modified)), children: sorted }
}

function tree(): Entry {
  const reg = 'regenerable'
  const hf = dir('huggingface', [dir('hub', [dir('models--Qwen--Qwen3-32B', [file('model-00001-of-00004.safetensors', 18 * GIB, 'cache', reg), file('model-00002-of-00004.safetensors', 17 * GIB, 'cache', reg), rest(5, 9 * GIB, 5, 'cache', reg)], 'cache', reg),
    dir('models--black-forest-labs--FLUX.1-dev', [rest(11, 23 * GIB, 11, 'cache', reg)], 'cache', reg)], 'cache', reg)], 'cache', reg)
  const cache = dir('.cache', [hf, dir('pip', [rest(820, 3 * GIB, 820, 'cache', reg)], 'cache', reg), rest(40, 900 * MIB, 610, 'cache', reg)], 'cache', reg)
  const models = dir('models', [file('deepseek-v4-q4.gguf', 61 * GIB, 'media'), file('llama-4-scout-q8.gguf', 34 * GIB, 'media'), rest(6, 4 * GIB, 6, 'media')], 'media')
  const app = dir('app', [dir('target', [dir('release', [rest(1900, 7 * GIB, 1900, 'code', 'build_output')], 'code', 'build_output')], 'code', 'build_output'), dir('.git', [rest(3, 600 * MIB, 140, 'git')], 'git'), rest(80, 120 * MIB, 300, 'code')], 'code')
  const web = dir('web', [dir('node_modules', [rest(900, 2 * GIB, 41000, 'cache', 'reinstallable')], 'cache', 'reinstallable'), rest(40, 300 * MIB, 500, 'code')], 'code')
  const projects = dir('projects', [app, web, dir(HOSTILE_FOLDER, [rest(3, 1 * GIB, 3, 'code')], 'code'), rest(30, 900 * MIB, 4000, 'code')], 'code')
  const user = dir('ops', [cache, models, projects, dir('Downloads', [rest(14, 6 * GIB, 14, 'documents')], 'documents'), rest(60, 2 * GIB, 9000)])
  const incus = dir('incus', [dir('disks', [file('default.img', 120 * GIB, 'vms')], 'vms'), dir('images', [rest(4, 6 * GIB, 4, 'vms')], 'vms'), rest(20, 300 * MIB, 200, 'vms')], 'vms')
  const docker = dir('docker', [dir('overlay2', [rest(300, 18 * GIB, 210000, 'vms')], 'vms'), rest(10, 400 * MIB, 50, 'vms')], 'vms')
  const lib = dir('lib', [incus, docker, dir('apt', [rest(50, 300 * MIB, 90)]), rest(90, 2 * GIB, 30000)])
  const variable = dir('var', [lib, dir('log', [rest(200, 3 * GIB, 400)]), rest(20, 200 * MIB, 900)])
  const usr = dir('usr', [dir('lib', [rest(2000, 9 * GIB, 60000)]), dir('local', [dir('cuda-13.0', [rest(40, 7 * GIB, 3000)])]), rest(10, 4 * GIB, 40000)])
  const tmp = dir('tmp', [rest(90, 5 * GIB, 300, 'cache', 'temporary')], 'cache', 'temporary')
  return dir('/', [dir('home', [user], 'media'), variable, usr, tmp, file('swap.img', 16 * GIB, 'other', null, 40), dir('opt', [rest(30, 6 * GIB, 9000)]), rest(12, 1 * GIB, 5000)])
}

/** The map as the parent passes it on: a flat list, each entry pointing at its folder. */
export function sparkMap(finishedAt: Date, seconds: number) {
  const nodes: Record<string, unknown>[] = []
  const stack: [Entry, number][] = [[tree(), -1]]
  while (stack.length) {
    const [entry, parent] = stack.pop() as [Entry, number]
    const place = nodes.length
    nodes.push({ parent, name: entry.name, type: entry.type, bytes: entry.bytes, files: entry.files, items: entry.items, kind: entry.kind, reclaim: entry.reclaim, modified: entry.modified })
    for (const child of [...entry.children].reverse()) stack.push([child, place])
  }
  const used = (nodes[0]?.bytes as number) + HIDDEN_BYTES
  return { root: '/', finished_at: finishedAt.toISOString().replace(/\.\d+Z$/, 'Z'), seconds, entries: 1_400_000, unreadable: 7, disk: { total_bytes: TOTAL_BYTES, used_bytes: used, free_bytes: TOTAL_BYTES - used }, nodes }
}
