<script lang="ts">
  import StatePill from './StatePill.svelte'
  import IconButton from './IconButton.svelte'
  import { MACHINE_ICONS, OPEN_LABEL, REMOVE_LABEL, RENAME_LABEL } from '../lib/machineIcons.ts'
  import Meter from './Meter.svelte'
  import LiveLine from './monitor/LiveLine.svelte'
  import { machineHref } from '../lib/routes.ts'
  import { listTag } from '../lib/helperUpdate.ts'
  import { archName, bundleFlag, formatGb, formatMb, osName, profileLabel, relativeTime } from '../lib/format.ts'

  import type { Machine } from '../lib/types.ts'

  let { machine, now, pinned, onRemove, onRename }: { machine: Machine; now: number; pinned: string | null | undefined; onRemove: (machine: Machine) => void; onRename: (machine: Machine) => void } = $props()
  const flag = $derived(bundleFlag(machine.bundle_version, pinned))
  /** The machine the control panel runs on enrolls over its own loopback address. It is the parent, and machine 1. */
  const isParent = $derived(machine.ip === '127.0.0.1')
  const chip = $derived(machine.os === 'macos' && machine.arch === 'arm64' ? 'Apple Silicon' : archName(machine.arch))
  const vmCount = $derived(machine.workloads.length)
  const settings = $derived(machine.settings)
  const updateTag = $derived(listTag(machine))
</script>

<article class="card" class:offline={machine.state === 'offline'}>
  <div class="ch">
    <div class="row1">
      <a class="nm" href={machineHref(machine.id)}>{machine.name}</a>
      {#if isParent}<span class="tag run">Parent</span>{/if}
      <StatePill state={machine.state} />
      {#if machine.problems?.length}<span class="tag warn">Needs setup</span>{/if}
      {#if updateTag}<span class="tag warn" data-update-tag>{updateTag}</span>{/if}
    </div>
    <div class="where">{machine.ip ?? 'address unknown'}{#if settings} · {profileLabel(settings.profile)}{/if}</div>
    {#if settings?.labels?.length}<div class="labels">{#each settings.labels as label (label)}<span class="tag">{label}</span>{/each}</div>{/if}
    <div class="specs">
      <span>{osName(machine.os)} · {chip}</span>
      <span>{machine.cpu_cores ?? '–'} cores</span>
      <span>{vmCount === 0 ? 'No VMs yet' : vmCount === 1 ? '1 VM' : `${vmCount} VMs`}</span>
      {#if machine.bundle_version}<span class:stale={flag.stale}>{flag.text}</span>{/if}
    </div>
  </div>

  {#if machine.state !== 'offline'}<LiveLine machineId={machine.id} />{/if}

  <div class="meters">
    <Meter label="Memory" free={machine.free_ram_mb} total={machine.ram_total_mb} format={formatMb} />
    <Meter label="Disk" free={machine.free_disk_gb} total={machine.disk_total_gb} format={formatGb} />
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
    <span class="id seen">seen {relativeTime(machine.last_seen, now)}</span>
    <span class="tools">
      <IconButton label={OPEN_LABEL} subject={machine.name} icon={MACHINE_ICONS.open} text="Open" href={machineHref(machine.id)} />
      <IconButton label={RENAME_LABEL} subject={machine.name} icon={MACHINE_ICONS.pencil} text="Rename" onclick={() => onRename(machine)} />
      <IconButton label={REMOVE_LABEL} subject={machine.name} icon={MACHINE_ICONS.trash} text="Remove" variant="danger" onclick={() => onRemove(machine)} />
    </span>
  </div>
</article>

<style>
  .card.offline { opacity: 0.7; }
  .labels { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
  .where { font-family: var(--mono); font-size: 11px; color: var(--m50); margin-top: 3px; }
  .nm { overflow-wrap: anywhere; }
  .meters { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; padding: 14px 16px; border-bottom: 1px solid var(--line); }
  .problems { display: grid; gap: 6px; padding: 12px 16px; background: var(--warn-bg); color: var(--warn); border-bottom: 1px solid var(--warn-line); font-size: 13px; }
  .problems ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
  .problems li { display: grid; gap: 2px; }
  .fix { color: var(--text); font-family: var(--mono); font-size: 11px; }
  .tools { display: inline-flex; gap: 8px; margin-left: auto; }
  .stale { color: var(--warn); font-weight: 700; }
</style>
