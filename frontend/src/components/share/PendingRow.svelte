<script lang="ts">
  // One machine waiting for a code. What is typed here (code, name, share) lives in this row only, and the row is kept
  // while the machine stays in the list, so the 4-second refresh never loses a half-typed code.
  import { untrack } from 'svelte'
  import ActionButton from '../ActionButton.svelte'
  import { shareApprove, shareRefuse, ApiError } from '../../lib/api.ts'
  import type { PendingMachine } from '../../lib/share.ts'
  import { WRONG_CODE } from '../../lib/shareErrors.ts'
  import { approveBody, draftFor, draftProblem } from '../../lib/shareDraft.ts'
  import { OS_NAMES, timeLeft } from '../../lib/shareText.ts'

  let { machine, now, onChanged }: { machine: PendingMachine; now: number; onChanged: () => Promise<void> } = $props()
  // The starting values come from the machine as it first appeared; a later refresh must not overwrite what is typed.
  const first = untrack(() => draftFor(machine))
  let code = $state(first.code)
  let name = $state(first.name)
  let cores = $state(first.cores)
  let ram = $state(first.ram_mb)
  let disk = $state(first.disk_gb)

  async function approve() {
    const draft = { code, name, cores, ram_mb: ram, disk_gb: disk }
    const problem = draftProblem(draft, machine.share)
    if (problem) throw new Error(problem)
    try {
      await shareApprove(machine.id, approveBody(draft))
    } catch (error) {
      if (error instanceof ApiError && error.code === WRONG_CODE) code = ''
      await onChanged()
      throw error
    }
    await onChanged()
  }

  async function refuse() {
    await shareRefuse(machine.id)
    await onChanged()
  }
</script>

<tr>
  <td class="c-name" data-label="Machine">
    <div data-testid="pending-host">{machine.hostname}</div>
    <div class="small">{OS_NAMES[machine.os]} {machine.cpu} · {timeLeft(machine.expiresAt, now)} · {machine.triesLeft} {machine.triesLeft === 1 ? 'try' : 'tries'} left</div>
    <input class="name" type="text" bind:value={name} spellcheck="false" autocomplete="off" aria-label="Name for {machine.hostname}" />
  </td>
  <td data-label="Share">
    <div class="share">
      <label><span>cores</span><input type="number" min="1" bind:value={cores} aria-label="Cores for {machine.hostname}" /></label>
      <label><span>RAM MB</span><input type="number" min="1" bind:value={ram} aria-label="RAM in MB for {machine.hostname}" /></label>
      <label><span>disk GB</span><input type="number" min="1" bind:value={disk} aria-label="Disk in GB for {machine.hostname}" /></label>
    </div>
  </td>
  <td data-label="Code">
    <input class="code" type="text" inputmode="numeric" maxlength="6" autocomplete="off" placeholder="000000" bind:value={code} aria-label="Code from {machine.hostname}" />
  </td>
  <td data-label="">
    <div class="acts">
      <ActionButton label="Approve" busyLabel="Approving…" doneLabel="Approved" variant="green" small onrun={approve} />
      <ActionButton label="Refuse" busyLabel="Refusing…" doneLabel="Refused" variant="danger" small onrun={refuse} />
    </div>
  </td>
</tr>

<style>
  td { vertical-align: top; }
  .small { font-family: var(--mono); font-size: 11px; font-weight: 400; color: var(--m50); margin-top: 2px; }
  input { border: 1px solid var(--line); background: var(--surface); color: var(--text); padding: 6px 8px; min-width: 0; font-family: var(--mono); font-size: 12px; }
  input:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: -1px; }
  .name { width: 100%; max-width: 220px; margin-top: 6px; }
  .share { display: flex; gap: 6px; flex-wrap: wrap; }
  .share label { display: grid; gap: 2px; font-family: var(--mono); font-size: 10px; color: var(--m40); text-transform: uppercase; letter-spacing: 0.06em; }
  .share input { width: 80px; }
  .code { width: 120px; padding: 8px 10px; letter-spacing: 0.2em; font-size: 16px; }
  .acts { display: flex; gap: 8px; flex-wrap: wrap; align-items: flex-start; }
  @media (max-width: 820px) { .name, .code { max-width: none; width: 100%; } }
</style>
