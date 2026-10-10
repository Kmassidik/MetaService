// Run with `npm test` (node:test, no dependencies).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { windowSizeMiB, hostMemoryMiB, buildingModel, formatPct, splitPercents } from './building.js';

const GIB = 1024;
const host64 = { ram_total_mb: 64 * GIB, ram_reserve_mb: 8 * GIB, cpu_total: 24,
  disk_total_gb: 1000, disk_alloc_gb: 120, disk_free_gb: 700 };
const server = (id, status, memGiB, extra = {}) => ({ id, display: id, status, cls: status === 'running' ? 'run' : '',
  bundle: 'openclaw', cpu: 2, mem_gb: memGiB, mem_mb: memGiB * GIB, disk_gb: 40, worker: false, user_environment: false, ...extra });

test('window size keeps the building at 64 windows or fewer', () => {
  assert.equal(windowSizeMiB(64 * GIB), 1024);
  assert.equal(windowSizeMiB(96 * GIB), 2048);
  assert.equal(windowSizeMiB(16 * GIB), 256);
  assert.equal(windowSizeMiB(512 * GIB), 8192);
});

test('host memory prefers exact MiB and falls back to the decimal GB field', () => {
  assert.equal(hostMemoryMiB({ ram_total_mb: 65536, ram_total_gb: 68 }), 65536);
  assert.equal(hostMemoryMiB({ ram_total_gb: 68 }), Math.floor(68e9 / 1048576));
  assert.equal(hostMemoryMiB(null), 0);
});

test('reserve fills the lobby, tenants at home rent the next windows, the rest is for rent', () => {
  const model = buildingModel([
    server('budi', 'running', 2, { user_environment: true }),
    server('vps-1', 'running', 8, { cpu: 4 }),
    server('sari', 'stopped', 2, { user_environment: true }),
  ], host64);
  assert.equal(model.windowMiB, 1024);
  assert.equal(model.capacity, 64);
  assert.equal(model.floors.length, 8);
  const kinds = model.floors.flat().flatMap(segment => Array(segment.span).fill(segment.kind));
  assert.deepEqual(kinds.filter(kind => kind === 'reserve').length, 8);
  assert.deepEqual(kinds.filter(kind => kind === 'tenant').length, 10);
  assert.deepEqual(kinds.filter(kind => kind === 'vacant').length, 46);
  const [budi, vps1, sari] = model.tenants;
  assert.equal(budi.apt, '2A');
  assert.equal(vps1.apt, '2C');
  assert.equal(sari.home, false);
  assert.equal(sari.apt, null);
});

test('floor width divides the windows so every floor is complete', () => {
  const m4max = buildingModel([], { ram_total_mb: 36 * GIB, ram_reserve_mb: 8 * GIB });
  assert.equal(m4max.capacity, 36);
  assert.equal(m4max.perFloor, 6);
  assert.equal(m4max.floors.length, 6);
  assert.ok(m4max.floors.every(floor => floor.reduce((sum, segment) => sum + segment.span, 0) === 6));
  assert.equal(buildingModel([], host64).perFloor, 8);
});

test('apartment numbers follow the floor width', () => {
  const model = buildingModel([server('budi', 'running', 2)], { ram_total_mb: 36 * GIB, ram_reserve_mb: 8 * GIB });
  assert.equal(model.tenants[0].apt, '2C');
});

test('segments merge adjacent windows of the same apartment on each floor', () => {
  const model = buildingModel([server('budi', 'running', 2), server('vps-1', 'running', 8)], host64);
  assert.deepEqual(model.floors[1].map(({ kind, span, tenant }) => [kind, span, tenant ?? null]), [
    ['tenant', 2, 0], ['tenant', 6, 1],
  ]);
  assert.deepEqual(model.floors[2].map(({ kind, span, tenant }) => [kind, span, tenant ?? null]), [
    ['tenant', 2, 1], ['vacant', 6, null],
  ]);
});

test('totals report rented, reserved and vacant memory plus promised cores', () => {
  const model = buildingModel([
    server('budi', 'running', 2),
    server('vps-1', 'provisioning', 8, { cpu: 4 }),
    server('sari', 'stopped', 2),
  ], host64);
  assert.equal(model.totals.rentedMiB, 10 * GIB);
  assert.equal(model.totals.reserveMiB, 8 * GIB);
  assert.equal(model.totals.vacantMiB, 46 * GIB);
  assert.equal(model.totals.overMiB, 0);
  assert.equal(model.totals.cpuPromised, 6);
  assert.equal(model.totals.cpuTotal, 24);
  assert.equal(model.totals.home, 2);
  assert.equal(model.totals.away, 1);
  assert.equal(model.totals.diskAllocGB, 120);
  assert.equal(model.totals.diskTotalGB, 1000);
});

test('tenants beyond capacity are marked over and nothing is left for rent', () => {
  const host16 = { ram_total_mb: 16 * GIB, ram_reserve_mb: 8 * GIB };
  const model = buildingModel([
    server('a', 'running', 4), server('b', 'running', 4), server('c', 'running', 4),
  ], host16);
  assert.equal(model.windowMiB, 256);
  assert.equal(model.totals.overMiB, 4 * GIB);
  assert.equal(model.totals.vacantMiB, 0);
  assert.equal(model.tenants[0].over, false);
  assert.equal(model.tenants[2].over, true);
  const segments = model.floors.flat();
  assert.equal(segments.filter(segment => segment.kind === 'vacant').length, 0);
  assert.ok(segments.some(segment => segment.over));
});

test('unknown host memory yields an empty building instead of throwing', () => {
  const model = buildingModel([server('a', 'running', 2)], null);
  assert.equal(model.totalMiB, 0);
  assert.deepEqual(model.floors, []);
  assert.equal(model.tenants.length, 1);
});

test('percent labels show <1% for tiny shares', () => {
  assert.equal(formatPct(0), '0%');
  assert.equal(formatPct(0.004), '<1%');
  assert.equal(formatPct(0.156), '16%');
});

test('split percentages round to a whole 100', () => {
  assert.deepEqual(splitPercents([10, 8, 46]), [16, 12, 72]);
  assert.deepEqual(splitPercents([1, 1, 1]), [34, 33, 33]);
  assert.deepEqual(splitPercents([0, 0, 0]), [0, 0, 0]);
});
