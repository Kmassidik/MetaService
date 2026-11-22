// The Security page's recommendations card: ranked actions derived from the same overview data
// the tables already show (PRD-security-hardening.md §3). Predicts what to do next instead of
// waiting for the accident. Pure functions so the ranking is testable.
import type { SecurityMachineLine, TopRow } from './securityTypes.ts'

export interface Recommendation {
  /** High number = show first. */
  priority: number
  /** The machine the action is for, or 'router' for the Omada rule. */
  target: string
  /** One-line action. */
  action: string
  /** Why it matters (plain words). */
  why: string
  /** The Omada rule text to paste, when the action is a router block. */
  omadaRule?: string
}

const RULE_TEMPLATE = (network: string): string =>
  `Omada ER7206 → Firewall → IP Group → ipblock → add ${network}\n(the existing "blockbot" deny rule on WAN2 IN already uses the ipblock group)`

/** The /24 network an IPv4 address belongs to (1.2.3.4 → 1.2.3.0/24). IPv6 stays the address. */
export function networkOf(address: string): string {
  const parts = address.split('.')
  if (parts.length === 4) return `${parts[0]}.${parts[1]}.${parts[2]}.0/24`
  return address
}

/** Recommendations from the machines' baselines and the attacking addresses. */
export function recommendations(machines: SecurityMachineLine[], topAddresses: TopRow[]): Recommendation[] {
  const out: Recommendation[] = []
  for (const machine of machines) {
    if (!machine.reported) continue
    const baseline = machine.baseline
    if (baseline.password_login === true) {
      out.push({
        priority: 100, target: machine.machine, action: 'Turn password login OFF',
        why: `${machine.machine} still accepts passwords. Bots are trying passwords every day; key-only SSH ends the risk.`,
      })
    }
    if (baseline.ban_tool !== 'running') {
      out.push({
        priority: 80, target: machine.machine, action: 'Enable the ban tool',
        why: `${machine.machine} watches attacks but never blocks them. Attackers can try forever.`,
      })
    }
    if (baseline.firewall === false) {
      out.push({
        priority: 50, target: machine.machine, action: 'Turn the firewall ON',
        why: `${machine.machine}'s firewall is off. SSH stays exposed; other listeners stay stealth-blocked only with the firewall on.`,
      })
    }
    if (baseline.pending_updates !== null && baseline.pending_updates !== undefined && baseline.pending_updates > 0) {
      out.push({
        priority: 30, target: machine.machine, action: `Apply ${baseline.pending_updates} pending updates`,
        why: `${machine.machine} has ${baseline.pending_updates} security updates waiting.`,
      })
    }
  }
  // top offenders: recommend a router block for the worst one and any IP with ≥50 attempts
  for (const offender of topAddresses.filter((row) => row.count >= 50).slice(0, 3)) {
    out.push({
      priority: 70, target: 'router', action: `Block ${networkOf(offender.name)} at the router`,
      why: `${offender.name} tried ${offender.count} logins. Blocking at the Omada saves the bandwidth before it reaches the machines.`,
      omadaRule: RULE_TEMPLATE(networkOf(offender.name)),
    })
  }
  return out.sort((a, b) => b.priority - a.priority)
}
