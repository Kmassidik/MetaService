// A machine as an apartment building (copied from the MAAS panel). Memory is split into equal windows: the system reserve
// fills the lobby, every VM that is home (running or moving in) rents windows for its RAM,
// and whatever is left is for rent. Suspended VMs are away: they keep their disk in the
// basement but hold no memory. Pure functions only, so `npm test` covers the layout.
export const WINDOWS_PER_FLOOR = 8;
// Preferred floor widths, tried in order: the first that divides the windows evenly wins,
// so a 36 GB Mac (36 windows) gets six complete floors of 6 instead of a half-built top.
const FLOOR_WIDTHS = [WINDOWS_PER_FLOOR, 6, 9, 10, 7, 12, 5, 4];
const WINDOW_SIZES_MIB = [256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536];
const HOME = new Set(['running', 'unhealthy', 'flapping', 'provisioning', 'starting', 'restarting']);
const DEFAULT_RESERVE_MIB = 8192; // what MetaService keeps for the system when nothing else is set

/** MiB drawn by one window: the smallest size that keeps the building at ≤ maxWindows. */
export function windowSizeMiB(totalMiB, maxWindows = 64) {
  return WINDOW_SIZES_MIB.find(size => Math.floor(totalMiB / size) <= maxWindows) ?? WINDOW_SIZES_MIB.at(-1);
}

/** Host memory in MiB; a decimal GB figure is accepted too. */
export function hostMemoryMiB(host) {
  if (host?.ram_total_mb > 0) return host.ram_total_mb;
  if (host?.ram_total_gb > 0) return Math.floor(host.ram_total_gb * 1e9 / 1048576);
  return 0;
}

export function formatPct(fraction) {
  if (!(fraction > 0)) return '0%';
  const value = Math.round(fraction * 100);
  return value < 1 ? '<1%' : value + '%';
}

/** Whole percentages of one total that always add up to 100 (largest remainder). */
export function splitPercents(parts) {
  const total = parts.reduce((sum, part) => sum + part, 0);
  if (!(total > 0)) return parts.map(() => 0);
  const exact = parts.map(part => part / total * 100);
  const result = exact.map(value => Math.floor(value));
  let missing = 100 - result.reduce((sum, value) => sum + value, 0);
  const order = exact.map((value, index) => [value - Math.floor(value), index])
    .sort((a, b) => b[0] - a[0] || a[1] - b[1]);
  for (const [, index] of order) {
    if (missing <= 0) break;
    result[index]++;
    missing--;
  }
  return result;
}

export function buildingModel(servers = [], host = null) {
  const totalMiB = hostMemoryMiB(host);
  const windowMiB = windowSizeMiB(totalMiB);
  const capacity = Math.floor(totalMiB / windowMiB);
  const perFloor = FLOOR_WIDTHS.find(width => capacity % width === 0) ?? WINDOWS_PER_FLOOR;
  const reserveMiB = Math.min(host?.ram_reserve_mb ?? DEFAULT_RESERVE_MIB, totalMiB);
  const tenants = (servers || []).map(server => {
    const memMiB = server.mem_mb ?? (server.mem_gb || 0) * 1024;
    return {
      id: server.id, name: server.display || server.id, status: server.status, cls: server.cls || '',
      home: HOME.has(server.status), memMiB, cpu: server.cpu || 0, diskGB: server.disk_gb || 0,
      share: totalMiB ? memMiB / totalMiB : 0, apt: null, windows: 0, over: false,
    };
  });

  const cells = [];
  if (capacity > 0) {
    for (let i = 0; i < Math.ceil(reserveMiB / windowMiB); i++) cells.push({ kind: 'reserve' });
    tenants.forEach((tenant, index) => {
      if (!tenant.home) return;
      tenant.windows = Math.max(1, Math.ceil(tenant.memMiB / windowMiB));
      for (let i = 0; i < tenant.windows; i++) cells.push({ kind: 'tenant', tenant: index });
    });
    while (cells.length < capacity) cells.push({ kind: 'vacant' });
  }

  // Floors run bottom-up; each floor merges adjacent windows of one apartment into a segment.
  const floors = [];
  cells.forEach((cell, position) => {
    const floor = Math.floor(position / perFloor);
    const column = position % perFloor;
    const over = position >= capacity;
    if (cell.kind === 'tenant') {
      const tenant = tenants[cell.tenant];
      tenant.apt ??= `${floor + 1}${String.fromCharCode(65 + column)}`;
      tenant.over ||= over;
    }
    const segments = floors[floor] ??= [];
    const last = segments.at(-1);
    if (last && last.kind === cell.kind && last.tenant === cell.tenant && last.over === over) last.span++;
    else segments.push({ kind: cell.kind, tenant: cell.tenant, over, span: 1, column });
  });

  const home = tenants.filter(tenant => tenant.home);
  const rentedMiB = home.reduce((sum, tenant) => sum + tenant.memMiB, 0);
  const totals = {
    rentedMiB, reserveMiB,
    vacantMiB: Math.max(0, totalMiB - reserveMiB - rentedMiB),
    overMiB: Math.max(0, reserveMiB + rentedMiB - totalMiB),
    cpuPromised: home.reduce((sum, tenant) => sum + tenant.cpu, 0),
    cpuTotal: host?.cpu_total > 0 ? host.cpu_total : null,
    home: home.length, away: tenants.length - home.length,
    diskAllocGB: host?.disk_alloc_gb ?? tenants.reduce((sum, tenant) => sum + tenant.diskGB, 0),
    diskTotalGB: host?.disk_total_gb ?? 0,
    diskFreeGB: host?.disk_free_gb ?? null,
  };
  return { totalMiB, windowMiB, capacity, perFloor, floors, tenants, totals };
}
