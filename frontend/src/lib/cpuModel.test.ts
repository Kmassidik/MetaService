import { describe, expect, test } from 'bun:test'
import { cpuModelText, cpuTypeLabel, MAX_CPU_MODEL_CHARS } from './cpuModel.ts'

describe('cpuModelText', () => {
  test('a normal name is kept as it is', () => {
    expect(cpuModelText('AMD Ryzen 9 5950X 16-Core Processor')).toBe('AMD Ryzen 9 5950X 16-Core Processor')
    expect(cpuModelText('Apple M4')).toBe('Apple M4')
  })

  test('null, undefined, empty and blank give null', () => {
    expect(cpuModelText(null)).toBeNull()
    expect(cpuModelText(undefined)).toBeNull()
    expect(cpuModelText('')).toBeNull()
    expect(cpuModelText('  \t\n ')).toBeNull()
    expect(cpuModelText('\u0000\u001b')).toBeNull()
  })

  test('control characters go and blanks collapse', () => {
    expect(cpuModelText('  Intel(R)\tXeon(R)\u0000  CPU \u001b[31m E5   v4\n')).toBe('Intel(R) Xeon(R) CPU [31m E5 v4')
    expect(cpuModelText('a​b‮c')).toBe('abc')
  })

  test('a long name is cut to 120 characters', () => {
    expect(cpuModelText('x'.repeat(300))).toBe('x'.repeat(MAX_CPU_MODEL_CHARS))
    expect(MAX_CPU_MODEL_CHARS).toBe(120)
    expect(Array.from(cpuModelText('é'.repeat(200)) ?? '')).toHaveLength(120)
  })

  test('markup stays as plain text and is not changed', () => {
    expect(cpuModelText('<script>alert(1)</script> CPU')).toBe('<script>alert(1)</script> CPU')
  })
})

describe('cpuTypeLabel', () => {
  test('the host row names the CPU when the machine gives one', () => {
    expect(cpuTypeLabel('host', 'AMD Ryzen 9 5950X')).toBe('host (AMD Ryzen 9 5950X)')
  })

  test('the host row is plain host without a name', () => {
    expect(cpuTypeLabel('host', null)).toBe('host')
    expect(cpuTypeLabel('host', undefined)).toBe('host')
    expect(cpuTypeLabel('host', ' \u0000 ')).toBe('host')
  })

  test('other models never get the machine name', () => {
    expect(cpuTypeLabel('EPYC-Genoa', 'AMD Ryzen 9 5950X')).toBe('EPYC-Genoa')
  })

  test('a hostile name is cleaned and cut inside the label', () => {
    expect(cpuTypeLabel('host', `${'y'.repeat(300)}\u0000`)).toBe(`host (${'y'.repeat(120)})`)
    expect(cpuTypeLabel('host', '<img src=x onerror=alert(1)>')).toBe('host (<img src=x onerror=alert(1)>)')
  })
})
