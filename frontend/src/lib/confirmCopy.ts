// The words of each red confirm dialog, in one place: what exactly goes, what is lost, and the verb on the red button. Pure, so the wording is tested.
import type { Machine, RemoteMachineInfo, Workload } from './types.ts'

export interface ConfirmCopy {
  title: string
  /** One plain sentence: what will be deleted or removed, by name. */
  what: string
  /** What is lost, or what is kept. */
  consequence: string
  /** The red button's verb: "Delete VM", "Remove machine". */
  confirmLabel: string
  busyLabel: string
  doneLabel: string
}

export function deleteVmCopy(machine: Pick<Machine, 'name'>, workload: Pick<Workload, 'name'>): ConfirmCopy {
  return {
    title: 'Delete this VM?',
    what: `${workload.name} on ${machine.name} will be stopped and deleted.`,
    consequence: 'The machine makes a backup of it first and keeps that backup; if the backup fails, nothing is deleted.',
    confirmLabel: 'Delete VM',
    busyLabel: 'Deleting…',
    doneLabel: 'Deleted',
  }
}

export function removeSshKeyCopy(workload: Pick<Workload, 'name'>): ConfirmCopy {
  return {
    title: 'Remove this key?',
    what: `This key can no longer log in to ${workload.name}.`,
    consequence: 'It is removed from the VM straight away if the VM is running.',
    confirmLabel: 'Remove key',
    busyLabel: 'Removing…',
    doneLabel: 'Removed',
  }
}

export function removeMachineCopy(machine: Pick<Machine, 'name'>): ConfirmCopy {
  return {
    title: 'Remove this machine?',
    what: `${machine.name} will disappear from MetaService and its token stops working.`,
    consequence: 'Its VMs keep running on the machine. To manage it again it must enroll with a new token.',
    confirmLabel: 'Remove machine',
    busyLabel: 'Removing…',
    doneLabel: 'Removed',
  }
}

/** The machine was installed over SSH: the same dialog, with the choice of taking MetaService off that computer or only forgetting it. */
export function removeRemoteMachineCopy(machine: Pick<Machine, 'name'>, info: Pick<RemoteMachineInfo, 'ssh_user' | 'host'>): ConfirmCopy {
  return {
    ...removeMachineCopy(machine),
    what: `${machine.name} was installed on ${info.ssh_user}@${info.host}. Removing it forgets the machine here and, if you choose, takes MetaService away from that computer.`,
    consequence: 'Its token stops working. To manage it again it must be installed or enrolled again.',
  }
}
