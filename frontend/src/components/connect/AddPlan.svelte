<script lang="ts">
  // Step 4 before the install: what will change as numbered tiles, the machine's name, the advanced choices folded away, and one Install button. Nothing is changed before Install.
  import SecretField from '../SecretField.svelte'
  import StatusMark from './StatusMark.svelte'
  import type { AddChoices } from '../../lib/remote.ts'
  import type { ConnectForm, PlanPreview, VerifyResult } from '../../lib/types.ts'

  interface Props {
    form: ConnectForm
    result: VerifyResult
    choices: AddChoices
    password: string
    preview: PlanPreview | null
    failure: string
    busy: boolean
    ready: boolean
    nameProblem: string | null
    advancedWrong: string | null
    onChange: () => void
    onSubmit: (event: SubmitEvent) => void
    onBack: () => void
  }

  let { form, result, choices = $bindable(), password = $bindable(), preview, failure, busy, ready, nameProblem, advancedWrong, onChange, onSubmit, onBack }: Props = $props()
  const count = $derived(preview?.steps.length ?? 0)
</script>

<form onsubmit={onSubmit} novalidate>
  <h2>Ready to add {choices.name || 'this machine'}</h2>
  <p class="muted">{count === 0 ? 'Working out what will change…' : `${count} ${count === 1 ? 'thing' : 'things'} will change`} on {result.facts.user}@{form.host}. Nothing happens until you press Install.</p>
  {#if preview}
    <ol class="plan" aria-label="What will change">
      {#each preview.steps as step, index (step.id)}
        <li class="tile">
          <span class="num" aria-hidden="true">{index + 1}</span>
          <div><strong>{step.label}</strong>{#each step.changes as change (change)}<span class="change">{change}</span>{/each}</div>
        </li>
      {/each}
    </ol>
    {#each preview.notes as note (note)}<p class="note">{note}</p>{/each}
  {/if}

  <section class="card">
    <h4>Name</h4>
    <label for="remote-name">Machine name</label>
    <input id="remote-name" bind:value={choices.name} onchange={onChange} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" aria-invalid={nameProblem ? 'true' : 'false'} aria-describedby="remote-name-hint" />
    <p class="hint {nameProblem ? 'bad' : ''}" id="remote-name-hint">{nameProblem ?? 'How it shows in Machines. Small letters, numbers and dashes.'}</p>
  </section>

  <details class="advanced card">
    <summary>More choices (most people skip this)</summary>
    <label for="remote-box">Box folder</label>
    <input id="remote-box" bind:value={choices.box} onchange={onChange} autocomplete="off" spellcheck="false" placeholder="/home/build/metaservice-box" />
    <p class="hint">Empty: a folder named metaservice-box in that user's home.</p>
    <label for="remote-ssh">Folder for the key line</label>
    <input id="remote-ssh" bind:value={choices.sshDir} onchange={onChange} autocomplete="off" spellcheck="false" placeholder="/home/build/.ssh" />
    <p class="hint">Empty: .ssh in that user's home.</p>
    <label for="remote-port">Port of the program</label>
    <input id="remote-port" bind:value={choices.agentPort} onchange={onChange} inputmode="numeric" autocomplete="off" placeholder="9101" />
    <label class="check"><input type="checkbox" bind:checked={choices.installKey} onchange={onChange} /> <span>Let the parent send commands (adds one restricted line to authorized_keys). Without it the machine can report in, but cannot be controlled.</span></label>
    {#if advancedWrong}<p class="hint bad" role="alert">{advancedWrong}</p>{/if}
  </details>

  {#if !form.useKey}<SecretField label="Password (typed again, used once)" name="password" bind:value={password} />{/if}
  {#if failure}
    <div class="problem" role="alert"><StatusMark kind="blocking" /><span>{failure}</span></div>
  {/if}
  <div class="foot">
    <button class="btn line" type="button" onclick={onBack}>Back</button>
    <button class="btn green" type="submit" disabled={!ready}>{busy ? 'Starting…' : 'Install'}</button>
  </div>
</form>

<style>
  form { display: grid; gap: 12px; }
  h2 { margin: 0; font-size: 18px; line-height: 1.25; }
  p { margin: 0; }
  .plan { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; }
  .tile { display: flex; gap: 12px; padding: 12px 14px; border: 1px solid var(--gray); background: var(--gray2); }
  .num { flex: none; width: 28px; height: 28px; display: grid; place-items: center; border-radius: 50%; background: var(--green); color: var(--black); font-weight: 700; }
  .tile div { min-width: 0; overflow-wrap: anywhere; }
  .tile strong { display: block; }
  .change { display: block; color: var(--m70); font-size: 13px; }
  .note { font-size: 12px; color: var(--m70); }
  .card { padding: 10px 14px 12px; border: 1px solid var(--gray); background: var(--gray2); }
  h4 { margin: 0 0 6px; font-family: var(--mono); font-size: 12px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--m70); }
  label { display: block; margin: 10px 0 4px; font-size: 13px; font-weight: 600; }
  input:not([type='checkbox']) { display: block; width: 100%; min-height: 42px; padding: 9px 10px; border: 1px solid var(--m50); background: var(--white); color: var(--black); font-family: var(--sans); font-size: 14px; }
  input:focus-visible, summary:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }
  .hint { margin-top: 4px; font-size: 12px; color: var(--m70); }
  .bad { color: var(--danger); }
  .advanced { padding-top: 0; }
  summary { padding: 8px 0; font-weight: 600; cursor: pointer; }
  .check { display: flex; gap: 8px; align-items: flex-start; margin-top: 12px; font-weight: 400; }
  .check input { flex: none; width: 20px; height: 20px; margin: 1px 0 0; accent-color: var(--green); }
  .problem { display: flex; gap: 10px; padding: 10px 12px; border: 1px solid var(--gray); border-left: 4px solid var(--danger); background: var(--gray2); font-weight: 600; overflow-wrap: anywhere; }
  .foot { display: flex; justify-content: space-between; gap: 10px; }
  .btn.line { border-color: var(--black); }
  @media (max-width: 520px) { .foot { flex-direction: column-reverse; } }
</style>
