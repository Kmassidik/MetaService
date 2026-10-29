// Read the parent's external-service discovery answer before the panel trusts it.
// Discovery is represented separately from managed workloads so external IDs can never enter VM placement or actions.
import { isFields, optionalText, UnreadableAnswer, type Fields } from './unreadable.ts'
import type { ExternalRuntime, ExternalService, ExternalServicesReply, ExternalServiceState, ExternalWarning, WorkloadKind } from './types.ts'

const RUNTIMES: readonly ExternalRuntime[] = ['docker', 'incus', 'apple']
const KINDS: readonly WorkloadKind[] = ['vm', 'container']
const STATES: readonly ExternalServiceState[] = ['running', 'stopped', 'unknown']

function text(source: Fields, key: string): string {
  const value = source[key]
  if (typeof value !== 'string') throw new UnreadableAnswer(`${key} is not text`)
  return value
}

function oneOf<T extends string>(value: unknown, allowed: readonly T[], what: string): T {
  const found = allowed.find((word) => word === value)
  if (found === undefined) throw new UnreadableAnswer(`${what} is not one the panel knows`)
  return found
}

function service(value: unknown): ExternalService {
  if (!isFields(value)) throw new UnreadableAnswer('an external service is not an object')
  return {
    id: text(value, 'id'),
    name: text(value, 'name'),
    runtime: oneOf(value.runtime, RUNTIMES, 'runtime'),
    kind: oneOf(value.kind, KINDS, 'kind'),
    state: oneOf(value.state, STATES, 'state'),
    image: optionalText(value, 'image'),
  }
}

function warning(value: unknown): ExternalWarning {
  if (!isFields(value)) throw new UnreadableAnswer('an external-service warning is not an object')
  return { runtime: oneOf(value.runtime, RUNTIMES, 'warning runtime'), message: text(value, 'message') }
}

/** Anything that is not the promised shape throws UnreadableAnswer; it is never treated as an empty list. */
export function parseExternalServices(raw: unknown): ExternalServicesReply {
  if (!isFields(raw)) throw new UnreadableAnswer('the external-services answer is not an object')
  if (!Array.isArray(raw.services)) throw new UnreadableAnswer('services is not a list')
  if (!Array.isArray(raw.warnings)) throw new UnreadableAnswer('warnings is not a list')
  return { services: raw.services.map(service), warnings: raw.warnings.map(warning) }
}
