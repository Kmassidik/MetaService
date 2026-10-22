import { expect, test } from 'bun:test'
import { isDirty, undoneForm } from './environmentDirty.ts'
import { formFromMachine } from './environmentForm.ts'
import { machine } from './testing.ts'

const saved = () => formFromMachine(machine({ name: 'mac-studio', settings: { labels: ['lab'], notes: '', allow_gpu: true, vm_cpu: 4 } }))

test('an untouched form is clean', () => {
  expect(isDirty(saved(), saved())).toBe(false)
})

test('an edit makes the form dirty, a checkbox too', () => {
  expect(isDirty({ ...saved(), vmCpu: '8' }, saved())).toBe(true)
  expect(isDirty({ ...saved(), allowGpu: false }, saved())).toBe(true)
})

test('editing a value back to the original is clean again', () => {
  const form = { ...saved(), notes: 'x' }
  expect(isDirty(form, saved())).toBe(true)
  form.notes = ''
  expect(isDirty(form, saved())).toBe(false)
})

test('after Save the saved values are the form, so it is clean', () => {
  const form = { ...saved(), vmCpu: '8' }
  expect(isDirty(form, { ...form })).toBe(false)
})

test('undo returns the saved values as a separate copy, so later typing cannot change them', () => {
  const was = saved()
  const form = undoneForm(was)
  expect(form).toEqual(was)
  expect(form).not.toBe(was)
  form.vmCpu = '9'
  expect(was.vmCpu).toBe('4')
  expect(isDirty(form, was)).toBe(true)
  expect(isDirty(undoneForm(was), was)).toBe(false)
})
