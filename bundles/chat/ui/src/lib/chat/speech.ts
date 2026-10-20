/** The browser's speech-to-text, which TypeScript's DOM types do not describe. */

export interface SpeechResultsEvent {
  results: ArrayLike<ArrayLike<{ transcript: string }>>
}

export interface SpeechRecognitionLike {
  continuous: boolean
  interimResults: boolean
  lang: string
  onresult: ((event: SpeechResultsEvent) => void) | null
  onerror: (() => void) | null
  onend: (() => void) | null
  start(): void
  stop(): void
}

type SpeechConstructor = new () => SpeechRecognitionLike

const isConstructor = (value: unknown): value is SpeechConstructor => typeof value === 'function'

/** The browser's recognizer (standard or prefixed), or undefined when it has none. */
export function speechRecognitionClass(): SpeechConstructor | undefined {
  if (typeof window === 'undefined') return undefined
  const candidates: unknown[] = [Reflect.get(window, 'SpeechRecognition'), Reflect.get(window, 'webkitSpeechRecognition')]
  return candidates.find(isConstructor)
}
