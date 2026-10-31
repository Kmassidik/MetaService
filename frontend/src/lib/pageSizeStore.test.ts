import { afterEach, expect, test } from 'bun:test'
import { readPageSize, savePageSize, sizeOrDefault } from './pageSizeStore.ts'

const original = Object.getOwnPropertyDescriptor(globalThis, 'localStorage')

function useStorage(storage: Pick<Storage, 'getItem' | 'setItem'> | null) {
  Object.defineProperty(globalThis, 'localStorage', { value: storage, configurable: true, writable: true })
}

afterEach(() => {
  if (original) Object.defineProperty(globalThis, 'localStorage', original)
  else Reflect.deleteProperty(globalThis, 'localStorage')
})

function memory(): Pick<Storage, 'getItem' | 'setItem'> {
  const kept = new Map<string, string>()
  return { getItem: (key) => kept.get(key) ?? null, setItem: (key, value) => void kept.set(key, value) }
}

test('a saved page size comes back for the same list only', () => {
  useStorage(memory())
  expect(savePageSize('vms', 100)).toBe(true)
  expect(readPageSize('vms')).toBe(100)
  expect(readPageSize('processes')).toBeNull()
})

test('a saved value that is not an offered size is ignored', () => {
  const storage = memory()
  useStorage(storage)
  storage.setItem('metaservice.pageSize.vms', '37')
  expect(readPageSize('vms')).toBeNull()
  storage.setItem('metaservice.pageSize.vms', 'lots')
  expect(readPageSize('vms')).toBeNull()
})

test('without storage, or when it refuses, nothing is remembered and nothing throws', () => {
  const refusing = { getItem: () => { throw new Error('blocked') }, setItem: () => { throw new Error('blocked') } }
  useStorage(refusing)
  expect(readPageSize('vms')).toBeNull()
  expect(savePageSize('vms', 25)).toBe(false)
  useStorage(null)
  expect(readPageSize('vms')).toBeNull()
  expect(savePageSize('vms', 25)).toBe(false)
})

test('the fallback is used when nothing was saved', () => {
  expect(sizeOrDefault(null)).toBe(50)
  expect(sizeOrDefault(null, 25)).toBe(25)
  expect(sizeOrDefault(100, 25)).toBe(100)
})
