<script lang="ts">
  // "Extra CPU flags" of a new VM, as in Proxmox: one row per flag with Off, Default and On, what the flag does, and the machines whose helper can switch it.
  // Default leaves the flag to the CPU model and is never sent. A flag this machine cannot switch stays on Default with its buttons off.
  import { CPU_FLAGS, FLAG_SETTINGS, flagMachines, flagSetting, withFlag, type CpuOffer, type FlagSetting } from '../../../lib/cpuOptions.ts'
  import type { Machine, WorkloadForm } from '../../../lib/types.ts'

  const LABEL_ID = 'vm-create-flags-label'
  const WORDS: Record<FlagSetting, string> = { off: 'Off', default: 'Default', on: 'On' }
  const NOBODY = 'none of your machines'

  let { form = $bindable(), offer, machines }: { form: WorkloadForm; offer: CpuOffer; machines: Machine[] } = $props()
</script>

<div class="flags" role="group" aria-labelledby={LABEL_ID} data-cpu-flags>
  <p class="label" id={LABEL_ID}>Extra CPU flags:</p>
  <table>
    <thead><tr><th scope="col">Value</th><th scope="col">Flag</th><th scope="col">Description</th><th scope="col">Supported on</th></tr></thead>
    <tbody>
      {#each CPU_FLAGS as flag (flag.id)}
        {@const offered = offer.flags.includes(flag.id)}
        {@const lit = flagSetting(form, flag.id)}
        {@const where = flagMachines(machines, flag.id)}
        <tr data-flag={flag.id} class:off={!offered}>
          <td class="value">
            <span class="segmented" role="radiogroup" aria-label={flag.id}>
              {#each FLAG_SETTINGS as setting (setting)}
                <label class:on={lit === setting} data-setting={setting}>
                  <input type="radio" name="vm-create-flag-{flag.id}" value={setting} checked={lit === setting} disabled={!offered} onchange={() => (form.cpuFlags = withFlag(form.cpuFlags, flag.id, setting))} />
                  <span>{WORDS[setting]}</span>
                </label>
              {/each}
            </span>
          </td>
          <td class="flag">{flag.id}</td>
          <td class="what">{flag.description}</td>
          <td class="where">{where.length > 0 ? where.join(', ') : NOBODY}</td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<style>
  .flags { grid-column: 1 / -1; display: grid; gap: 8px; min-width: 0; }
  .label { margin: 0; font: 400 13px/1.4 var(--sans); color: var(--text); }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; border: 1px solid var(--reserve-line); background: var(--surface); font: 400 13px/1.4 var(--sans); }
  th { padding: 6px 9px; background: var(--surface-2); border-bottom: 1px solid var(--reserve-line); color: var(--m70); font-weight: 600; text-align: left; }
  th + th, td + td { border-left: 1px solid var(--line); }
  th:nth-child(1) { width: 196px; }
  th:nth-child(2) { width: 104px; }
  th:nth-child(4) { width: 150px; }
  td { padding: 7px 9px; vertical-align: top; }
  tr + tr td { border-top: 1px solid var(--line); }
  .flag { font-family: var(--mono); font-size: 12px; }
  .what { color: var(--m70); }
  .where { color: var(--m60); overflow-wrap: anywhere; }
  tr.off .flag, tr.off .what { color: var(--m50); }
  .segmented { display: inline-flex; border: 1px solid var(--reserve-line); }
  .segmented label { position: relative; display: inline-grid; place-items: center; min-width: 54px; padding: 4px 8px; background: var(--surface); color: var(--m60); font-size: 12px; font-weight: 600; cursor: pointer; }
  .segmented label + label { border-left: 1px solid var(--reserve-line); }
  .segmented label:hover { background: var(--surface-2); }
  .segmented label.on { background: var(--accent); color: var(--accent-text); }
  .segmented input { position: absolute; opacity: 0; width: 1px; height: 1px; margin: 0; pointer-events: none; }
  .segmented label:has(input:focus-visible) { outline: 2px solid var(--accent-mark); outline-offset: 1px; z-index: 1; }
  .segmented label:has(input:disabled) { cursor: not-allowed; color: var(--m40); background: var(--surface-2); }
  .segmented label.on:has(input:disabled) { background: var(--reserve-bg); color: var(--m60); }
  /* On a phone each flag stacks: the buttons and its name, what it does, where it works. */
  @media (max-width: 640px) {
    table, tbody, tr, td { display: block; }
    thead { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
    td + td { border-left: 0; }
    td, tr + tr td { padding: 3px 9px; border-top: 0; }
    tr { padding: 6px 0; }
    tr + tr { border-top: 1px solid var(--line); }
    .where::before { content: 'Supported on: '; color: var(--m50); }
  }
</style>
