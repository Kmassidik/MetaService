<script lang="ts">
  // Share a PC: add a far computer to the shared network. The parent passes the hub's answers through; the hub's key never reaches this page.
  // The page asks again every few seconds while it is open (and stops when it is closed), and redraws a list only when it changed.
  import { onMount } from 'svelte'
  import PeerList from '../components/share/PeerList.svelte'
  import PendingList from '../components/share/PendingList.svelte'
  import ShareChoose from '../components/share/ShareChoose.svelte'
  import { ApiError, sharePeers, sharePending, shareSupported } from '../lib/api.ts'
  import type { JoinedMachine, OsChoice, PendingMachine } from '../lib/share.ts'
  import { pageProblem, problemText, type PageProblem } from '../lib/shareErrors.ts'
  import { listChanged, shouldPoll, signatureOf, SHARE_POLL_MS } from '../lib/sharePoll.ts'
  import { UnreadableAnswer } from '../lib/unreadable.ts'

  const UNREADABLE_TEXT = 'The answer of the hub could not be read.'
  let supported = $state<OsChoice[] | null>(null)
  let pending = $state<PendingMachine[]>([])
  let peers = $state<JoinedMachine[]>([])
  let pendingSignature: string | null = null
  let peersSignature: string | null = null
  let loaded = $state(false)
  let problem = $state<PageProblem | null>(null)
  let failure = $state('')
  let now = $state(Date.now())

  /** Puts a list on screen only when it differs from the one shown. */
  function adopt<T>(shown: string | null, next: T[], put: (list: T[]) => void): string {
    if (listChanged(shown, next)) put(next)
    return signatureOf(next)
  }

  /** The plain words for a failure that is shown where it happened. */
  function failureText(error: unknown): string {
    if (error instanceof UnreadableAnswer) return UNREADABLE_TEXT
    return error instanceof ApiError ? error.message : 'Something went wrong.'
  }

  function fail(error: unknown) {
    problem = error instanceof ApiError ? pageProblem(error.code) : null
    if (!problem) failure = failureText(error)
  }

  async function refresh() {
    try {
      const [waiting, joined] = await Promise.all([sharePending(), sharePeers()])
      supported ??= await shareSupported()
      pendingSignature = adopt(pendingSignature, waiting, (list) => (pending = list))
      peersSignature = adopt(peersSignature, joined, (list) => (peers = list))
      problem = null
      failure = ''
    } catch (error) {
      fail(error)
    } finally {
      now = Date.now()
      loaded = true
    }
  }

  const tick = () => shouldPoll({ hidden: document.hidden, problem }) && refresh()

  onMount(() => {
    void refresh()
    const timer = setInterval(tick, SHARE_POLL_MS)
    document.addEventListener('visibilitychange', tick)
    return () => {
      clearInterval(timer)
      document.removeEventListener('visibilitychange', tick)
    }
  })
</script>

<div class="phead"><h1>Share a PC</h1><span class="crumb">Infrastructure › {pending.length} waiting · {peers.length} joined</span></div>

{#if !loaded}
  <p class="state" role="status" data-testid="share-loading">Reading Share a PC…</p>
{:else if problem}
  <div class="state bad" role="alert" data-testid="share-problem">
    <p>{problemText(problem)}</p>
    <button class="btn line sm" type="button" onclick={refresh}>Check again</button>
  </div>
{:else if supported === null}
  <div class="state bad" role="alert">
    <p>{failure || UNREADABLE_TEXT}</p>
    <button class="btn line sm" type="button" onclick={refresh}>Try again</button>
  </div>
{:else}
  <p class="intro">Let a computer somewhere else lend its power to this parent. Choose its system, run the command on it, then type the code it shows to approve it.</p>
  {#if failure}<p class="banner" role="alert" data-testid="share-failure">{failure}</p>{/if}
  <ShareChoose {supported} {now} />
  <h2 class="sub">Waiting for approval</h2>
  <PendingList machines={pending} {now} onChanged={refresh} />
  <h2 class="sub">Joined machines</h2>
  <PeerList {peers} onChanged={refresh} />
{/if}

<style>
  .state { margin: 0; padding: 24px 28px; font-size: 13px; color: var(--m60); display: grid; gap: 12px; justify-items: start; }
  .state p { margin: 0; line-height: 1.6; }
  .state.bad p { color: var(--danger-d); }
  .intro { margin: 0; padding: 16px 28px 0; font-size: 13px; line-height: 1.7; color: var(--m70); }
  .sub { margin: 0; padding: 22px 28px 0; font-family: var(--mono); font-size: 13px; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; }
  @media (max-width: 820px) { .state, .intro { padding-left: 16px; padding-right: 16px; } .sub { padding-left: 16px; padding-right: 16px; } }
</style>
