<script lang="ts">
  // The filters of the event log: machine, type and a text search on the address or user. Machine and type live in the address (so a link keeps them);
  // the search text is kept by the page and applied a moment after typing stops.
  import { securityHref, type SecurityView } from '../../lib/securityRoute.ts'
  import { EVENT_TYPES, EVENT_TYPE_LABELS, type SecurityEventType } from '../../lib/securityTypes.ts'
  import type { MachineInfo } from '../../lib/securityView.ts'

  let { infos, view, text = $bindable() }: { infos: MachineInfo[]; view: SecurityView; text: string } = $props()

  const isType = (value: string): value is SecurityEventType => EVENT_TYPES.some((type) => type === value)

  function pickMachine(event: Event) {
    if (event.currentTarget instanceof HTMLSelectElement) location.hash = securityHref({ ...view, machine: event.currentTarget.value })
  }

  function pickType(event: Event) {
    if (!(event.currentTarget instanceof HTMLSelectElement)) return
    const value = event.currentTarget.value
    location.hash = securityHref({ ...view, type: isType(value) ? value : '' })
  }
</script>

<div class="filters">
  <label>Machine
    <select id="sec-machine" value={view.machine} onchange={pickMachine}>
      <option value="">All machines</option>
      {#each infos as info (info.id)}<option value={info.id}>{info.name}</option>{/each}
    </select>
  </label>
  <label>Type
    <select id="sec-type" value={view.type} onchange={pickType}>
      <option value="">All types</option>
      {#each EVENT_TYPES as type (type)}<option value={type}>{EVENT_TYPE_LABELS[type]}</option>{/each}
    </select>
  </label>
  <label class="grow">Address or user
    <input id="sec-search" type="search" placeholder="45.148.10.92 or ubuntu" maxlength="64" autocomplete="off" bind:value={text} />
  </label>
</div>

<style>
  .filters { display: flex; gap: 12px; flex-wrap: wrap; align-items: end; }
  label { display: grid; gap: 4px; font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); min-width: 0; }
  .grow { flex: 1; min-width: 180px; }
  select, input { min-height: 38px; padding: 0 10px; border: 1px solid var(--line); background: var(--surface); color: var(--text); font-family: var(--mono); font-size: 12px; text-transform: none; letter-spacing: 0; min-width: 0; max-width: 100%; }
  @media (max-width: 820px) { label { flex: 1 1 100%; } }
</style>
