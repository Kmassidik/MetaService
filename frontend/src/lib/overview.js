// What the Overview, Deployments, Token ledger and Health pages show, worked out from the machines and the AI usage the Root reports.

/** Every VM on every machine, with the machine it lives on. */
export function allVms(machines) {
  return machines.flatMap((machine) => machine.workloads.map((workload) => ({ machine, workload })))
}

export function overviewCounts(machines) {
  const vms = allVms(machines)
  return {
    machines: machines.length,
    online: machines.filter((machine) => machine.state !== 'offline').length,
    vms: vms.length,
    running: vms.filter(({ workload }) => workload.state === 'running').length,
    needAttention: machines.filter((machine) => machine.state === 'offline' || machine.problems?.length).length,
  }
}

/** One line per thing that needs the operator: an offline machine or a machine with a problem, in plain words. */
export function attentionItems(machines) {
  return machines.flatMap((machine) => {
    if (machine.state === 'offline') return [{ machine: machine.name, kind: 'offline', message: 'This machine is offline.', fix: 'Check that the computer is on and MetaService is running.' }]
    return (machine.problems ?? []).map((problem) => ({ machine: machine.name, kind: 'problem', message: problem.message, fix: problem.fix }))
  })
}

export function usageTotals(rows) {
  return rows.reduce((sum, row) => ({
    requests: sum.requests + row.requests,
    promptTokens: sum.promptTokens + row.prompt_tokens,
    completionTokens: sum.completionTokens + row.completion_tokens,
  }), { requests: 0, promptTokens: 0, completionTokens: 0 })
}

export const usageName = (row) => (row.workload ? `${row.machine} / ${row.workload}` : row.machine)
