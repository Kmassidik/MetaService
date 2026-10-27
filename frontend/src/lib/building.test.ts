import { test, expect } from 'bun:test'
// Run with `bun test`.
import { windowSizeMiB, hostMemoryMiB, buildingModel, formatPct, splitPercents, type BuildingServer } from './building.ts';

const GIB = 1024;
const host64 = { ram_total_mb: 64 * GIB, ram_reserve_mb: 8 * GIB, cpu_total: 24,
  disk_total_gb: 1000, disk_alloc_gb: 120, disk_free_gb: 700 };
const server = (id: string, status: string, memGiB: number, extra: Partial<BuildingServer> = {}): BuildingServer => ({ id, display: id, status, cls: status === 'running' ? 'run' : '',
  cpu: 2, mem_gb: memGiB, mem_mb: memGiB * GIB, disk_gb: 40, ...extra });

test('window size keeps the building at 64 windows or fewer', () => {
  expect(windowSizeMiB(64 * GIB)).toBe(1024);
  expect(windowSizeMiB(96 * GIB)).toBe(2048);
  expect(windowSizeMiB(16 * GIB)).toBe(256);
  expect(windowSizeMiB(512 * GIB)).toBe(8192);
});

test('host memory prefers exact MiB and falls back to the decimal GB field', () => {
  expect(hostMemoryMiB({ ram_total_mb: 65536, ram_total_gb: 68 })).toBe(65536);
  expect(hostMemoryMiB({ ram_total_gb: 68 })).toBe(Math.floor(68e9 / 1048576));
  expect(hostMemoryMiB(null)).toBe(0);
});

test('reserve fills the lobby, tenants at home rent the next windows, the rest is for rent', () => {
  const model = buildingModel([
    server('budi', 'running', 2),
    server('vps-1', 'running', 8, { cpu: 4 }),
    server('sari', 'stopped', 2),
  ], host64);
  expect(model.windowMiB).toBe(1024);
  expect(model.capacity).toBe(64);
  expect(model.floors.length).toBe(8);
  const kinds = model.floors.flat().flatMap(segment => Array(segment.span).fill(segment.kind));
  expect(kinds.filter(kind => kind === 'reserve').length).toEqual(8);
  expect(kinds.filter(kind => kind === 'tenant').length).toEqual(10);
  expect(kinds.filter(kind => kind === 'vacant').length).toEqual(46);
  const [budi, vps1, sari] = model.tenants;
  expect(budi?.apt).toBe('2A');
  expect(vps1?.apt).toBe('2C');
  expect(sari?.home).toBe(false);
  expect(sari?.apt).toBe(null);
});

test('floor width divides the windows so every floor is complete', () => {
  const m4max = buildingModel([], { ram_total_mb: 36 * GIB, ram_reserve_mb: 8 * GIB });
  expect(m4max.capacity).toBe(36);
  expect(m4max.perFloor).toBe(6);
  expect(m4max.floors.length).toBe(6);
  expect(m4max.floors.every(floor => floor.reduce((sum, segment) => sum + segment.span, 0) === 6)).toBeTruthy();
  expect(buildingModel([], host64).perFloor).toBe(8);
});

test('apartment numbers follow the floor width', () => {
  const model = buildingModel([server('budi', 'running', 2)], { ram_total_mb: 36 * GIB, ram_reserve_mb: 8 * GIB });
  expect(model.tenants[0]?.apt).toBe('2C');
});

test('segments merge adjacent windows of the same apartment on each floor', () => {
  const model = buildingModel([server('budi', 'running', 2), server('vps-1', 'running', 8)], host64);
  expect(model.floors[1]?.map(({ kind, span, tenant }) => [kind, span, tenant ?? null])).toEqual([
    ['tenant', 2, 0], ['tenant', 6, 1],
  ]);
  expect(model.floors[2]?.map(({ kind, span, tenant }) => [kind, span, tenant ?? null])).toEqual([
    ['tenant', 2, 1], ['vacant', 6, null],
  ]);
});

test('a deleting VM still holds its memory and is not drawn as stopped', () => {
  const model = buildingModel([server('going', 'deleting', 2, { cls: 'prog' })], host64);
  expect(model.tenants[0]?.home).toBe(true);
  expect(model.tenants[0]?.windows).toBe(2);
  expect(model.totals.away).toBe(0);
});

test('totals report rented, reserved and vacant memory plus promised cores', () => {
  const model = buildingModel([
    server('budi', 'running', 2),
    server('vps-1', 'provisioning', 8, { cpu: 4 }),
    server('sari', 'stopped', 2),
  ], host64);
  expect(model.totals.rentedMiB).toBe(10 * GIB);
  expect(model.totals.reserveMiB).toBe(8 * GIB);
  expect(model.totals.vacantMiB).toBe(46 * GIB);
  expect(model.totals.overMiB).toBe(0);
  expect(model.totals.cpuPromised).toBe(6);
  expect(model.totals.cpuTotal).toBe(24);
  expect(model.totals.home).toBe(2);
  expect(model.totals.away).toBe(1);
  expect(model.totals.diskAllocGB).toBe(120);
  expect(model.totals.diskTotalGB).toBe(1000);
});

test('tenants beyond capacity are marked over and nothing is left for rent', () => {
  const host16 = { ram_total_mb: 16 * GIB, ram_reserve_mb: 8 * GIB };
  const model = buildingModel([
    server('a', 'running', 4), server('b', 'running', 4), server('c', 'running', 4),
  ], host16);
  expect(model.windowMiB).toBe(256);
  expect(model.totals.overMiB).toBe(4 * GIB);
  expect(model.totals.vacantMiB).toBe(0);
  expect(model.tenants[0]?.over).toBe(false);
  expect(model.tenants[2]?.over).toBe(true);
  const segments = model.floors.flat();
  expect(segments.filter(segment => segment.kind === 'vacant').length).toBe(0);
  expect(segments.some(segment => segment.over)).toBeTruthy();
});

test('unknown host memory yields an empty building instead of throwing', () => {
  const model = buildingModel([server('a', 'running', 2)], null);
  expect(model.totalMiB).toBe(0);
  expect(model.floors).toEqual([]);
  expect(model.tenants.length).toBe(1);
});

test('percent labels show <1% for tiny shares', () => {
  expect(formatPct(0)).toBe('0%');
  expect(formatPct(0.004)).toBe('<1%');
  expect(formatPct(0.156)).toBe('16%');
});

test('split percentages round to a whole 100', () => {
  expect(splitPercents([10, 8, 46])).toEqual([16, 12, 72]);
  expect(splitPercents([1, 1, 1])).toEqual([34, 33, 33]);
  expect(splitPercents([0, 0, 0])).toEqual([0, 0, 0]);
});
