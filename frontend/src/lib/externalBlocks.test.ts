import { describe, expect, test } from 'bun:test'
import { externalBlocks } from './externalBlocks.ts'
import type { ExternalService } from './types.ts'

const service = (id: string, name: string, state: ExternalService['state']): ExternalService => ({ id, name, runtime: 'docker', kind: 'container', state, image: null })

describe('externalBlocks', () => {
  test('one block per service, running first, then unknown, then stopped, each group by name', () => {
    const blocks = externalBlocks([service('d:3', 'zeta', 'stopped'), service('d:1', 'beta', 'running'), service('d:4', 'mystery', 'unknown'), service('d:2', 'alpha', 'running')])
    expect(blocks.map((block) => block.name)).toEqual(['alpha', 'beta', 'mystery', 'zeta'])
    expect(blocks.map((block) => block.tone)).toEqual(['run', 'run', 'unknown', 'stop'])
  })

  test('the hover text says external, the runtime, the kind and the state', () => {
    const [block] = externalBlocks([service('docker:b9d1', 'sglang-5090', 'stopped')])
    expect(block?.title).toBe('sglang-5090: external docker container, stopped. Click for details.')
    expect(block?.tag).toBe('docker')
  })

  test('Docker blocks carry the Docker logo, the other runtimes none', () => {
    const [docker, incus] = externalBlocks([service('d:1', 'a', 'running'), { ...service('i:1', 'b', 'running'), runtime: 'incus' }])
    expect(docker?.logo).toBe('docker')
    expect(incus?.logo).toBeNull()
  })

  test('no services is no blocks', () => {
    expect(externalBlocks([])).toEqual([])
  })
})
