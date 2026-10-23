import { expect, test } from 'bun:test'
import { dirtySections, errorSections, isDirty, undoneForm } from './environmentDirty.ts'
import { formErrors, formFromMachine } from './environmentForm.ts'
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

test('an untouched form has no changed section', () => {
  expect(dirtySections(saved(), saved())).toEqual([])
})

test('one edit changes only its own section', () => {
  expect(dirtySections({ ...saved(), vmRamMb: '4096' }, saved())).toEqual(['vmDefaults'])
  expect(dirtySections({ ...saved(), allowGpu: false }, saved())).toEqual(['limits'])
  expect(dirtySections({ ...saved(), notes: 'x' }, saved())).toEqual(['names'])
})

test('edits in two sections name both, in page order', () => {
  expect(dirtySections({ ...saved(), name: 'other', ramReserveMb: '1' }, saved())).toEqual(['limits', 'names'])
})

test('editing back, and Save, leave no changed section', () => {
  const form = { ...saved(), vmCpu: '8' }
  form.vmCpu = '4'
  expect(dirtySections(form, saved())).toEqual([])
  const edited = { ...saved(), vmCpu: '8' }
  expect(dirtySections(edited, { ...edited })).toEqual([])
})

const SECTION_OF_ERROR_FIELD = {
  ramReserveMb: 'limits', diskReserveGb: 'limits', ramAllowanceMb: 'limits', diskAllowanceGb: 'limits', vmMaxRunning: 'limits',
  vmCpu: 'vmDefaults', vmRamMb: 'vmDefaults', vmDiskGb: 'vmDefaults', vmImage: 'vmDefaults',
  name: 'names', labels: 'names', notes: 'names', subdomain: 'names', aiModel: 'names', sshJump: 'names',
} as const

test('no errors means no section with an error', () => {
  expect(errorSections({})).toEqual([])
  expect(errorSections(formErrors(saved()))).toEqual([])
})

test('an error in every field lands in its own section', () => {
  for (const [field, section] of Object.entries(SECTION_OF_ERROR_FIELD)) {
    expect(errorSections({ [field]: 'bad' })).toEqual([section])
  }
})

test('errors in two sections name both, in page order', () => {
  expect(errorSections({ sshJump: 'bad', vmCpu: 'bad', ramReserveMb: 'bad' })).toEqual(['limits', 'vmDefaults', 'names'])
})
