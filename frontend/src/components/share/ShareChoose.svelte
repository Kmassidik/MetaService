<script lang="ts">
  // The three buttons (Mac, Windows, Linux), the CPU choices with the state of each build, and the command for the far PC.
  // The command is made by the hub; the panel only shows it and copies it.
  import ActionButton from '../ActionButton.svelte'
  import { shareMakeCommand } from '../../lib/api.ts'
  import { copyText } from '../../lib/clipboard.ts'
  import type { JoinCommand, OsChoice, ShareCpu, ShareOs } from '../../lib/share.ts'
  import { LOGOS } from '../../lib/logos.ts'
  import { choosable, cpuNote, CPU_NAMES, OS_LOGOS, OS_NAMES, stateText } from '../../lib/shareText.ts'
  import { timeLeft } from '../../lib/shareText.ts'

  let { supported, now }: { supported: OsChoice[]; now: number } = $props()
  let os = $state<ShareOs | ''>('')
  let cpu = $state<ShareCpu | ''>('')
  let made = $state<JoinCommand | null>(null)
  let copyNote = $state('')
  const row = $derived(supported.find((entry) => entry.os === os))
  const note = $derived(cpuNote(row, cpu))
  const canMake = $derived(os !== '' && cpu !== '')

  function pickOs(next: ShareOs) {
    os = next
    cpu = ''
    made = null
  }

  function pickCpu(next: ShareCpu) {
    cpu = next
    made = null
    copyNote = ''
  }

  async function make() {
    if (os === '' || cpu === '') return
    made = await shareMakeCommand(os, cpu)
    copyNote = ''
  }

  async function copy() {
    if (!made) return
    copyNote = (await copyText(made.command)) ? 'Copied' : 'Copying was refused: select the command and copy it yourself.'
  }
</script>

<section class="choose" aria-label="Add a far PC" data-testid="choose">
  <h2>1. Which computer is it?</h2>
  <div class="choices" role="group" aria-label="System">
    {#each supported as entry (entry.os)}
      <button class="choice" type="button" aria-pressed={os === entry.os} onclick={() => pickOs(entry.os)}><img class="oslogo" src={LOGOS[OS_LOGOS[entry.os]]} alt="" width="22" height="22" />{OS_NAMES[entry.os]}</button>
    {/each}
  </div>

  {#if row}
    <div class="choices" role="group" aria-label="Processor">
      {#each row.cpus as entry (entry.cpu)}
        {@const words = stateText(entry.state)}
        <button class="choice cpu" type="button" aria-pressed={cpu === entry.cpu} disabled={!choosable(entry.state)} onclick={() => pickCpu(entry.cpu)}>
          <span>{CPU_NAMES[entry.cpu]}</span>
          <span class="tag" class:run={words.tone === 'run'} class:warn={words.tone === 'warn'}>{words.tag}</span>
          {#if !choosable(entry.state)}<span class="why">{words.why}</span>{/if}
        </button>
      {/each}
    </div>
  {/if}
  <p class="note" data-testid="cpu-note">{note}</p>

  <h2>2. Run this on that computer</h2>
  <ActionButton label="Make the command" busyLabel="Making…" doneLabel="Made" variant="green" disabled={!canMake} onrun={make} />
  {#if made}
    <div class="commandbox" data-testid="command-box">
      <pre data-testid="command">{made.command}</pre>
      <div class="copyline">
        <button class="btn line sm" type="button" onclick={copy}>Copy</button>
        <span class="small" role="status">{copyNote}</span>
      </div>
      <p class="note">Run it once on the {os ? OS_NAMES[os] : ''} computer. {timeLeft(made.expiresAt, now)}.</p>
    </div>
  {/if}
</section>

<style>
  .choose { padding: 20px 28px; border-bottom: 1px solid var(--line); display: grid; gap: 12px; justify-items: start; }
  h2 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  h2:not(:first-child) { margin-top: 8px; }
  .choices { display: flex; gap: 10px; flex-wrap: wrap; max-width: 100%; }
  .choice { border: 1px solid var(--line); background: var(--surface); color: var(--text); padding: 12px 16px; min-width: 150px; text-align: left; display: grid; gap: 6px; justify-items: start; align-content: start; font-family: var(--mono); font-size: 13px; font-weight: 700; }
  .oslogo { flex: none; }
  .choice:has(.oslogo) { display: flex; align-items: center; gap: 10px; }
  .choice:hover:not(:disabled) { border-color: var(--line-strong); }
  .choice[aria-pressed='true'] { border-color: var(--line-strong); box-shadow: inset 0 0 0 1px var(--line-strong); background: var(--surface-2); }
  .choice:disabled { cursor: not-allowed; color: var(--m50); background: var(--surface-2); }
  .choice:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; }
  .cpu { max-width: 270px; }
  .why { font-size: 11px; font-weight: 400; line-height: 1.4; color: var(--m50); }
  .note { margin: 0; min-height: 1px; font-size: 13px; line-height: 1.6; color: var(--m60); }
  .commandbox { display: grid; gap: 10px; width: 100%; }
  pre { margin: 0; padding: 14px 16px; background: var(--inverse-bg); color: var(--inverse-text); font-size: 12.5px; white-space: pre-wrap; overflow-wrap: anywhere; user-select: all; }
  .copyline { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .small { font-family: var(--mono); font-size: 11px; color: var(--m60); }
  @media (max-width: 820px) { .choose { padding: 16px; } .choice { flex: 1 1 140px; } .cpu { max-width: none; } }
</style>
