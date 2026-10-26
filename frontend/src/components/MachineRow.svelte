<script lang="ts">
  // One machine, as a card that always has the same six rows, whatever the machine reports: its name and state, its address, one hardware line,
  // the CPU and memory right now, the memory and disk bars, and when it was last seen with its buttons. A fact the machine does not report keeps
  // its row and shows a dash, so cards side by side line up. Both helper buttons sit in their own reserved slot, so they never move a row.
  import StatePill from './StatePill.svelte'
  import Icon from './Icon.svelte'
  import IconButton from './IconButton.svelte'
  import { CARD_ICONS, MACHINE_ICONS, OPEN_LABEL, REMOVE_LABEL, RENAME_LABEL } from '../lib/machineIcons.ts'
  import Meter from './Meter.svelte'
  import LiveLine from './monitor/LiveLine.svelte'
  import { machineHref } from '../lib/routes.ts'
  import CardUpdate from './CardUpdate.svelte'
  import CardFix from './CardFix.svelte'
  import { listTag } from '../lib/helperUpdate.ts'
  import { addressLine, hardwareLine, hardwareParts, vmsChip } from '../lib/cardFacts.ts'
  import { formatGb, formatMb, bundleFlag, relativeTime } from '../lib/format.ts'

  import type { HardwareKind } from '../lib/cardFacts.ts'
  import type { Machine, RemoteMachineInfo } from '../lib/types.ts'

  let { machine, remote, now, pinned, onRemove, onRename, onChanged, onCheck }: { machine: Machine; remote: RemoteMachineInfo | null; now: number; pinned: string | null | undefined; onRemove: (machine: Machine) => void; onRename: (machine: Machine) => void; onChanged: () => void; onCheck: (machine: Machine) => void } = $props()
  /** The machine the control panel runs on enrolls over its own loopback address. It is the parent, and machine 1. */
  const isParent = $derived(machine.ip === '127.0.0.1')
  const updateTag = $derived(listTag(machine))
  const hardware = $derived(hardwareParts(machine))
  const hardwareText = $derived(hardwareLine(machine))
  const address = $derived(addressLine(machine))
  const vms = $derived(vmsChip(machine.workloads.length))
  const awake = $derived(machine.state !== 'offline')
  const labels = $derived(machine.settings?.labels ?? [])
  const flag = $derived(bundleFlag(machine.bundle_version, pinned))
  /** The one part of the hardware line that came from the CPU keeps the card's old hook, so the CPU's name stays findable in the tests. */
  const testId = (kind: HardwareKind): string | undefined => (kind === 'cpu' ? 'machine-cpu-model' : undefined)
</script>

<article class="card" class:offline={!awake}>
  <div class="head">
    <div class="top">
      <a class="nm" href={machineHref(machine.id)} title={machine.name}>{machine.name}</a>
      <span class="tags">
        {#if isParent}<span class="tag run">Parent</span>{/if}
        {#if machine.problems?.length}<span class="tag warn">Needs setup</span>{/if}
        {#if updateTag}<span class="tag warn" data-update-tag>{updateTag}</span>{/if}
        {#if machine.bundle_version}<span class="tag" class:stale={flag.stale}>{flag.text}</span>{/if}
        {#each labels as label (label)}<span class="tag">{label}</span>{/each}
      </span>
      <span class="marks">
        <StatePill state={machine.state} />
        <span class="chip" data-testid="machine-vms"><Icon path={CARD_ICONS.vms} />{vms}</span>
      </span>
    </div>
    <div class="line" data-testid="machine-address" title={address}>
      <Icon path={CARD_ICONS.network} />
      <span class="cut">{address}</span>
    </div>
    <div class="line" data-testid="machine-hardware" title={hardwareText}>
      <Icon path={CARD_ICONS.computer} />
      <span class="cut">
        {#each hardware as part, index (part.kind)}{#if index > 0}<span class="dot">{' · '}</span>{/if}<span data-testid={testId(part.kind)}>{part.text}</span>{/each}
      </span>
    </div>
    <div class="hand">
      <CardUpdate {machine} {onChanged} />
      <CardFix {machine} {remote} onCheck={() => onCheck(machine)} />
    </div>
  </div>

  <LiveLine machineId={machine.id} live={awake} />

  <div class="meters">
    <Meter label="Memory" free={machine.free_ram_mb} total={machine.ram_total_mb} format={formatMb} icon={CARD_ICONS.memory} />
    <Meter label="Disk" free={machine.free_disk_gb} total={machine.disk_total_gb} format={formatGb} icon={CARD_ICONS.disk} />
  </div>

  {#if machine.problems?.length}
    <div class="problems" role="alert">
      <strong>VMs can't be created on this machine yet.</strong>
      <ul>
        {#each machine.problems as problem (problem.code)}
          <li><span>{problem.message}</span><span class="fix">{problem.fix}</span></li>
        {/each}
      </ul>
    </div>
  {/if}

  <div class="acts">
    <span class="id seen"><Icon path={CARD_ICONS.clock} />seen {relativeTime(machine.last_seen, now)}</span>
    <span class="tools">
      <IconButton label={OPEN_LABEL} subject={machine.name} icon={MACHINE_ICONS.open} text="Open" href={machineHref(machine.id)} />
      <IconButton label={RENAME_LABEL} subject={machine.name} icon={MACHINE_ICONS.pencil} text="Rename" onclick={() => onRename(machine)} />
      <IconButton label={REMOVE_LABEL} subject={machine.name} icon={MACHINE_ICONS.trash} text="Remove" variant="danger" onclick={() => onRemove(machine)} />
    </span>
  </div>
</article>

<style>
  /* Tall enough for the six rows and the helper slot, so a card with nothing to say is as tall as one that says everything. */
  .card { min-height: 330px; }
  .card.offline { opacity: 0.7; }
  .head { padding: 15px 16px 12px; border-bottom: 1px solid var(--line); }
  .top { display: flex; align-items: center; gap: 8px; min-height: 22px; overflow: hidden; }
  .nm { flex: 0 1 auto; min-width: 12ch; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 700; font-size: 15px; }
  /* The chips that come and go share one slot: when the header has no room left, they are clipped, never the name, the state or the VMs. */
  .tags { display: flex; flex: 0 1 auto; gap: 6px; min-width: 0; overflow: hidden; white-space: nowrap; }
  .marks { display: inline-flex; flex: none; align-items: center; gap: 6px; margin-left: auto; }
  /* The one word of the header's chip, in the words the card uses: "No VMs", "2 VMs". */
  .chip { display: inline-flex; align-items: center; gap: 5px; padding: 3px 7px; border: 1px solid var(--line); font-family: var(--mono); font-size: 10px; font-weight: 700; color: var(--m60); white-space: nowrap; }
  .line { display: flex; align-items: center; gap: 6px; min-height: 18px; margin-top: 4px; font-family: var(--mono); font-size: 11px; color: var(--m50); }
  .cut { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .dot { color: var(--m40); }
  /* The slot of the two helper buttons is there even when neither is offered, so the rows below never move. */
  .hand { display: flex; flex-wrap: nowrap; align-items: flex-start; gap: 8px; min-height: 36px; margin-top: 10px; }
  .meters { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; padding: 14px 16px; border-bottom: 1px solid var(--line); }
  .problems { display: grid; gap: 6px; padding: 12px 16px; background: var(--warn-bg); color: var(--warn); border-bottom: 1px solid var(--warn-line); font-size: 13px; }
  .problems ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
  .problems li { display: grid; gap: 2px; }
  .fix { color: var(--text); font-family: var(--mono); font-size: 11px; }
  /* The footer sits at the bottom of the card, so a card stretched by a taller neighbour keeps its rows in place. */
  .acts { margin-top: auto; }
  .seen { display: inline-flex; align-items: center; gap: 6px; }
  .tools { display: inline-flex; gap: 8px; margin-left: auto; }
  .stale { color: var(--warn); font-weight: 700; }
  /* On a phone the list is one card wide, so the chips may take a line of their own rather than be cut: the name and state stay on the first. */
  @media (max-width: 640px) {
    .top { flex-wrap: wrap; }
    .nm { order: 1; }
    .marks { order: 2; }
    .tags { order: 3; flex: 0 0 100%; }
  }
</style>
