<script lang="ts">
  import type { Snippet } from 'svelte';
  import { buildingModel, formatPct, splitPercents, type BuildingHost, type BuildingServer, type Segment, type Tenant } from '../lib/building.ts';

  /** servers: the VMs on this machine (id, display, status, cls, mem_mb, cpu, disk_gb). host: this machine's memory, cores and disk. vmLink: where a VM's own page is. */
  let { servers = [], host = null, vmLink, none = 'No VMs on this machine yet.', actions }: { servers?: BuildingServer[]; host?: BuildingHost | null; vmLink: (vmId: string) => string; none?: string; actions?: Snippet<[string]> } = $props();

  const model = $derived(buildingModel(servers, host));
  const totals = $derived(model.totals);
  const floorsTopDown = $derived(model.floors.map((segments, index) => ({ segments, number: index + 1 })).reverse());
  const split = $derived(splitPercents([totals.rentedMiB, totals.reserveMiB, totals.vacantMiB]));
  const residents = $derived([...model.tenants].sort((a, b) =>
    Number(b.home) - Number(a.home) || (a.apt || '').localeCompare(b.apt || '', undefined, { numeric: true }) || a.name.localeCompare(b.name)));
  const cpuTotal = $derived(totals.cpuTotal ?? 0);
  const cores = $derived(cpuTotal ? Array.from({ length: Math.max(cpuTotal, totals.cpuPromised) }, (_, i) => i) : []);

  const gb = (mib: number) => (mib % 1024 ? (mib / 1024).toFixed(1) : String(mib / 1024)) + ' GB';
  // Shares of this machine's memory. Normally they add up to exactly 100; when overbooked they
  // are shown against the real total so the excess is visible (and matches Occupancy).
  const share = (mib: number, index: number) => totals.overMiB ? formatPct(model.totalMiB ? mib / model.totalMiB : 0) : split[index] + '%';
  const letter = (column: number) => String.fromCharCode(65 + column);
  const range = (count: number) => Array.from({ length: count }, (_, i) => i);
  /** Only tenant segments are asked for their tenant, so this always finds it. */
  function tenantOf(segment: Segment): Tenant {
    const tenant = segment.tenant === undefined ? undefined : model.tenants[segment.tenant];
    if (!tenant) throw new Error('this segment has no tenant');
    return tenant;
  }
  const firstOf = (segment: Segment, number: number) => tenantOf(segment).apt === number + letter(segment.column);
  const STATUS_TEXT: Record<string, string> = { run: 'running', prog: 'starting', warn: 'needs attention' };
  const statusText = (tenant: Tenant) => STATUS_TEXT[tenant.cls] || tenant.status;
  const describe = (tenant: Tenant) => `Apartment ${tenant.apt}: ${tenant.name} — ${gb(tenant.memMiB)} memory (${formatPct(tenant.share)} of this machine), ${tenant.cpu} vCPU, ${tenant.status}`
   ;
  const idle = 'VMs on this machine cannot use this part yet. Nothing in the platform runs here.';
</script>

{#if !host}
  <div class="empty">Waiting for this machine to report…</div>
{:else}
<section class="bv" aria-label="This machine drawn as an apartment building">
  <div class="bv-col">
    <div class="bv-building">
      <div class="bv-roof">
        <b>{host.chip || 'Machine'}</b>
        <span>{gb(model.totalMiB)} memory · one window = {gb(model.windowMiB)}</span>
      </div>
      <div class="bv-floor bv-dark" title={idle}>
        <span class="bv-fl">GPU</span>
        <div class="bv-darkbody"><span class="bv-panes" aria-hidden="true">{#each range(model.perFloor) as _}<i></i>{/each}</span><em>GPU · not used by VMs yet</em></div>
      </div>
      {#if host.apple}
        <div class="bv-floor bv-dark" title={idle}>
          <span class="bv-fl">NE</span>
          <div class="bv-darkbody"><span class="bv-panes" aria-hidden="true">{#each range(model.perFloor) as _}<i></i>{/each}</span><em>Neural Engine · not rented</em></div>
        </div>
      {/if}
      <div class="bv-floor bv-cores" title="vCPUs are time-shared, so cores are promised to VMs rather than handed over.">
        <span class="bv-fl">CPU</span>
        <div class="bv-corebody">
          {#if cores.length}
            <span class="bv-coregrid" aria-hidden="true">{#each cores as i}<i class:on={i < totals.cpuPromised && i < cpuTotal} class:over={i >= cpuTotal}></i>{/each}</span>
            <em>{totals.cpuPromised} / {totals.cpuTotal} cores promised · {formatPct(totals.cpuPromised / cpuTotal)}</em>
          {:else}
            <em>{totals.cpuPromised} vCPU promised to running VMs</em>
          {/if}
        </div>
      </div>
      {#each floorsTopDown as floor (floor.number)}
        <div class="bv-floor">
          <span class="bv-fl">{floor.number}</span>
          <div class="bv-wins" style:grid-template-columns="repeat({model.perFloor},minmax(0,1fr))">
            {#each floor.segments as segment}
              {#if segment.kind === 'tenant'}
                {@const tenant = tenantOf(segment)}
                <div class="bv-seg bv-apt {tenant.cls}" class:bv-over={segment.over} style:grid-column="span {segment.span}" role="group" title={describe(tenant)} aria-label={describe(tenant)}>
                  <a class="bv-hit" href={vmLink(tenant.id)} aria-label="Open {tenant.name}"></a>
                  <span class="bv-panes" aria-hidden="true">{#each range(segment.span) as _}<i></i>{/each}</span>
                  {#if firstOf(segment, floor.number)}
                    <span class="bv-label">
                      <b>{tenant.apt}{segment.span > 2 ? ' · ' + tenant.name : ''}</b>
                      {#if segment.span > 1}<small>{gb(tenant.memMiB)} · {formatPct(tenant.share)}</small>{/if}
                    </span>
                  {/if}
                </div>
              {:else}
                <div class="bv-seg bv-{segment.kind}" class:bv-over={segment.over} style:grid-column="span {segment.span}">
                  <span class="bv-panes" aria-hidden="true">{#each range(segment.span) as _}<i></i>{/each}</span>
                  {#if segment.kind === 'reserve' && segment.column === 0 && floor.number === 1}<span class="bv-label"><b>system</b><small>{gb(totals.reserveMiB)} kept free</small></span>{/if}
                  {#if segment.kind === 'vacant' && segment.span > 1}<span class="bv-label bv-quiet"><b>free</b></span>{/if}
                </div>
              {/if}
            {/each}
          </div>
        </div>
      {/each}
      <div class="bv-ground" aria-hidden="true"></div>
      <div class="bv-floor bv-basement" title="Every VM keeps its disk here, even while stopped. Disks are sparse, so real use grows as they fill.">
        <span class="bv-fl">B</span>
        <div class="bv-basebody">
          <em>Disk · {totals.diskAllocGB} / {totals.diskTotalGB} GB allocated · {formatPct(totals.diskTotalGB ? totals.diskAllocGB / totals.diskTotalGB : 0)}</em>
          <span class="bv-lockers" aria-hidden="true">
            {#each model.tenants as tenant}<i class:away={!tenant.home} style:flex="{tenant.diskGB}" title="{tenant.name} · {tenant.diskGB} GB"></i>{/each}
            <i class="free" style:flex="{Math.max(0, totals.diskTotalGB - totals.diskAllocGB)}"></i>
          </span>
        </div>
      </div>
    </div>
    <div class="bv-legend">
      <span><i class="k-home"></i>Running</span>
      <span><i class="k-prog"></i>Starting</span>
      <span><i class="k-reserve"></i>Kept for the system</span>
      <span><i class="k-vacant"></i>Free</span>
      <span><i class="k-dark"></i>Not used</span>
      {#if totals.overMiB}<span><i class="k-over"></i>Over capacity</span>{/if}
    </div>
  </div>

  <aside class="bv-side">
    <div class="bv-occ">
      <span>Memory in use</span>
      <b>{formatPct(model.totalMiB ? totals.rentedMiB / model.totalMiB : 0)}</b>
      <small>of memory used by {totals.home} running VM{totals.home === 1 ? '' : 's'}</small>
    </div>
    <div class="bv-stack" role="img" aria-label="Used {split[0]}%, system {split[1]}%, free {split[2]}%">
      <i class="k-home" style:width="{split[0]}%"></i><i class="k-reserve" style:width="{split[1]}%"></i><i class="k-vacant" style:width="{split[2]}%"></i>
    </div>
    <dl class="bv-split">
      <div><dt><i class="k-home"></i>Used by VMs</dt><dd>{gb(totals.rentedMiB)} · {share(totals.rentedMiB, 0)}</dd></div>
      <div><dt><i class="k-reserve"></i>Kept for the system</dt><dd>{gb(totals.reserveMiB)} · {share(totals.reserveMiB, 1)}</dd></div>
      <div><dt><i class="k-vacant"></i>Free</dt><dd>{gb(totals.vacantMiB)} · {share(totals.vacantMiB, 2)}</dd></div>
    </dl>
    {#if totals.overMiB}<p class="bv-alert" role="alert">Over capacity by {gb(totals.overMiB)}: VMs running plus the system reserve exceed this machine’s memory.</p>{/if}
    <dl class="bv-facts">
      <div><dt>CPU cores</dt><dd>{totals.cpuTotal ? `${totals.cpuPromised} / ${totals.cpuTotal} promised` : `${totals.cpuPromised} vCPU promised`}</dd></div>
      <div><dt>Storage</dt><dd>{totals.diskAllocGB} / {totals.diskTotalGB} GB</dd></div>
      <div><dt>VMs</dt><dd>{totals.home} running · {totals.away} stopped</dd></div>
    </dl>
    <h3>VMs</h3>
    {#if residents.length === 0}
      <p class="bv-none">{none}</p>
    {:else}
      <ul class="bv-tenants">
        {#each residents as tenant (tenant.id)}
          <li class:away={!tenant.home}>
            <span class="bv-badge {tenant.cls}">{tenant.apt || '—'}</span>
            <div>
              <a class="bv-name" href={vmLink(tenant.id)}><b>{tenant.name}</b></a>
              <span class="tag {tenant.cls}">{tenant.home ? statusText(tenant) : 'stopped'}</span>
              <small>{gb(tenant.memMiB)} · {formatPct(tenant.share)} of memory · {tenant.cpu} vCPU · {tenant.diskGB} GB disk</small>
              <small class="bv-live">{tenant.home ? tenant.status : 'keeps its disk · uses no memory while stopped'}</small>
              {#if actions}<span class="bv-act">{@render actions(tenant.id)}</span>{/if}
            </div>
          </li>
        {/each}
      </ul>
    {/if}
  </aside>
</section>
{/if}

<style>
  .bv{display:grid;grid-template-columns:minmax(0,7fr) minmax(280px,3fr);gap:24px;padding:8px 0 24px;align-items:start}
  .bv-col{min-width:0}
  .bv-building{border:1px solid var(--line-strong);background:var(--surface)}
  .bv-roof{display:flex;justify-content:space-between;align-items:baseline;gap:12px;padding:12px 14px;background:var(--inverse-bg);color:var(--inverse-text);font-family:var(--mono);font-size:11px;flex-wrap:wrap}
  .bv-roof b{font-size:13px;letter-spacing:.08em;text-transform:uppercase}
  .bv-roof span{color:var(--inverse-text-mid)}
  .bv-floor{display:flex;align-items:stretch;border-top:1px solid var(--line-strong);min-height:54px}
  .bv-fl{width:40px;flex-shrink:0;display:flex;align-items:center;justify-content:center;border-right:1px solid var(--line-strong);font-family:var(--mono);font-size:10px;font-weight:700;color:var(--m60);background:var(--surface-2)}
  .bv-wins{flex:1;display:grid;gap:4px;padding:5px}
  .bv-seg{position:relative;display:block;min-width:0;border:1px solid var(--line-strong);overflow:hidden}
  .bv-panes{position:absolute;inset:0;display:flex}
  .bv-panes i{flex:1;border-right:1px solid var(--pane-line)}
  .bv-panes i:last-child{border-right:0}
  .bv-apt{background:var(--accent);color:var(--text)}
  .bv-apt:hover,.bv-apt:focus-visible{outline:2px solid var(--line-strong);outline-offset:1px;z-index:2}
  .bv-apt.prog{background:var(--warn-bg);border-color:var(--warn-line);animation:bv-pulse 1.6s ease-in-out infinite}
  .bv-apt.warn{border:2px dashed var(--warn-line)}
  .bv-reserve{background:var(--reserve-bg);border-color:var(--reserve-line)}
  .bv-vacant{background:repeating-linear-gradient(135deg,var(--surface) 0 6px,var(--surface-2) 6px 8px);border-color:var(--line)}
  .bv-over,.bv-apt.bv-over,.bv-apt.prog.bv-over,.bv-apt.warn.bv-over{background:repeating-linear-gradient(135deg,var(--danger-bg) 0 6px,var(--danger-hatch) 6px 8px);border-color:var(--danger)}
  .bv-label{position:relative;display:flex;flex-direction:column;gap:1px;padding:5px 7px;font-family:var(--mono);line-height:1.25;max-width:100%}
  .bv-label b{font-size:10.5px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .bv-label small{font-size:9.5px;color:var(--m70);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .bv-quiet b{color:var(--m40);font-weight:400}
  .bv-dark{background:var(--inverse-bg)}
  .bv-dark .bv-fl{background:var(--inverse-2);color:var(--inverse-text-dim);border-right-color:var(--inverse-line)}
  .bv-darkbody,.bv-corebody,.bv-basebody{flex:1;position:relative;display:flex;align-items:center;padding:8px 12px;gap:12px}
  .bv-darkbody .bv-panes{inset:6px 6px;gap:4px}
  .bv-darkbody .bv-panes i{border:1px solid var(--inverse-line);background:var(--inverse-2)}
  .bv-darkbody em{position:relative;font-style:normal;font-family:var(--mono);font-size:11px;color:var(--inverse-text-soft);background:var(--inverse-bg);padding:2px 6px}
  .bv-corebody,.bv-basebody{font-family:var(--mono);font-size:11px;color:var(--m70)}
  .bv-corebody em,.bv-basebody em{font-style:normal}
  .bv-coregrid{display:flex;flex-wrap:wrap;gap:3px;max-width:60%}
  .bv-coregrid i{width:11px;height:11px;border:1px solid var(--line-strong);background:var(--surface)}
  .bv-coregrid i.on{background:var(--accent)}
  .bv-coregrid i.over{background:var(--danger-hatch);border-color:var(--danger)}
  .bv-ground{height:6px;background:var(--inverse-bg)}
  .bv-basement{background:var(--surface-2);border-top:0}
  .bv-basebody{flex-direction:column;align-items:stretch;gap:7px}
  .bv-lockers{display:flex;gap:2px;height:14px}
  .bv-lockers i{min-width:3px;background:var(--inverse-bg)}
  .bv-lockers i.away{background:var(--m40)}
  .bv-lockers i.free{background:var(--surface);border:1px solid var(--line)}
  .bv-legend{display:flex;flex-wrap:wrap;justify-content:flex-start;gap:8px 18px;margin:14px 0 0;font-family:var(--mono);font-size:10.5px;color:var(--m60)}
  .bv-legend span{display:inline-flex;align-items:center;gap:6px}
  .bv-legend i,.bv-split dt i{display:inline-block;width:12px;height:12px;border:1px solid var(--line-strong)}
  .k-home{background:var(--accent)}
  .k-prog{background:var(--warn-bg);border-color:var(--warn-line)!important}
  .k-reserve{background:var(--reserve-bg)}
  .k-vacant{background:repeating-linear-gradient(135deg,var(--surface) 0 3px,var(--line) 3px 4px)}
  .k-dark{background:var(--inverse-bg)}
  .k-over{background:var(--danger-hatch);border-color:var(--danger)!important}
  .bv-side{border:1px solid var(--line);padding:18px;position:sticky;top:12px}
  .bv-occ span{display:block;font-family:var(--mono);font-size:10px;letter-spacing:.14em;text-transform:uppercase;color:var(--m50)}
  .bv-occ b{display:block;font-family:var(--mono);font-size:44px;line-height:1.1;margin-top:4px}
  .bv-occ small{display:block;font-size:12px;color:var(--m60)}
  .bv-stack{display:flex;height:12px;margin:14px 0 10px;border:1px solid var(--line-strong)}
  .bv-stack i{display:block;height:100%}
  .bv-split,.bv-facts{margin:0;display:grid;gap:6px;font-family:var(--mono);font-size:11px}
  .bv-split div,.bv-facts div{display:flex;justify-content:space-between;gap:10px}
  .bv-split dt{display:flex;align-items:center;gap:7px;color:var(--m70)}
  .bv-split dd,.bv-facts dd{margin:0;font-weight:700}
  .bv-facts{margin-top:14px;padding-top:12px;border-top:1px solid var(--line)}
  .bv-facts dt{color:var(--m60)}
  .bv-alert{margin:10px 0 0;padding:8px 10px;border:1px solid var(--danger-line);background:var(--danger-bg);color:var(--danger-ink);font-family:var(--mono);font-size:11px}
  .bv-side h3{margin:18px 0 8px;font-family:var(--mono);font-size:10px;letter-spacing:.14em;text-transform:uppercase;color:var(--m50);font-weight:400}
  .bv-none{margin:0;font-size:12px;color:var(--m50)}
  .bv-tenants{list-style:none;margin:0;padding:0;display:grid;gap:10px}
  .bv-tenants li{display:flex;gap:10px;align-items:flex-start;padding-bottom:10px;border-bottom:1px solid var(--line)}
  .bv-tenants li:last-child{border-bottom:0;padding-bottom:0}
  .bv-tenants li.away{opacity:.72}
  .bv-act{display:block;margin-top:6px}
  .bv-hit{position:absolute;inset:0;z-index:1}
  .bv-name{font-size:13px;margin-right:6px;color:inherit;text-decoration:none}
  .bv-name:hover b{text-decoration:underline}
  .bv-tenants small{display:block;margin-top:3px;font-family:var(--mono);font-size:10.5px;color:var(--m60)}
  .bv-tenants .bv-live{color:var(--m50)}
  .bv-badge{flex-shrink:0;min-width:34px;text-align:center;font-family:var(--mono);font-size:11px;font-weight:700;border:1px solid var(--line-strong);padding:3px 4px;background:var(--accent)}
  .bv-badge.prog{background:var(--warn-bg);border-color:var(--warn-line)}
  .bv-tenants li.away .bv-badge{background:var(--surface);color:var(--m50);border-color:var(--line)}
  @keyframes bv-pulse{50%{opacity:.55}}
  @media (prefers-reduced-motion:reduce){.bv-apt.prog{animation:none}}
  @media (max-width:1100px){.bv{grid-template-columns:1fr}.bv-side{position:static}}
  @media (max-width:820px){.bv{padding:8px 0 16px}.bv-fl{width:30px}.bv-label small{display:none}}
</style>
