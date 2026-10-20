<script lang="ts">
  import type { Dict } from '../../../lib/check.ts'
  import type { Approval, Ask, AppResult, RunCard } from '../../../lib/types.ts'
  import AskCard from './AskCard.svelte'
  import TakeoverCard from './TakeoverCard.svelte'
  import ConnectCard from './ConnectCard.svelte'
  import SecretCard from './SecretCard.svelte'
  import SuggestBotCard from './SuggestBotCard.svelte'
  import ApprovalCard from './ApprovalCard.svelte'
  import AppSendCard from './AppSendCard.svelte'
  import AppResultCard from './AppResultCard.svelte'

  // Picks the card for whatever the current run is waiting on; an ask wins over other cards.
  interface Props {
    activeAsk?: Ask | null
    answeredAsks?: Dict<string[]>
    askMulti?: Dict<string[]>
    askFocus?: number
    askLocked?: boolean
    activeCard?: RunCard | null
    appResults?: Array<AppResult & { cardId?: string }>
    cardSecret?: string
    cardBusy?: string
    takingOver?: boolean
    agentLimitReached?: boolean
    pendingApprovals?: Approval[]
    approvalBusy?: boolean
    toggleAskOption: (optionId: string) => unknown
    submitAsk: (labels: string[]) => unknown
    skipAsk: () => unknown
    askKeydown: (event: KeyboardEvent) => unknown
    resolveCard: (decision: string, extra?: Dict<unknown>) => unknown
    onApproveApproval?: ((approval: Approval) => unknown) | null
    onDenyApproval?: ((approval: Approval) => unknown) | null
  }

  let {
    activeAsk = null,
    answeredAsks = {},
    askMulti = {},
    askFocus = -1,
    askLocked = false,
    activeCard = null,
    appResults = [],
    cardSecret = $bindable(''),
    cardBusy = '',
    takingOver = false,
    agentLimitReached = false,
    pendingApprovals = [],
    approvalBusy = false,
    toggleAskOption,
    submitAsk,
    skipAsk,
    askKeydown,
    resolveCard,
    onApproveApproval,
    onDenyApproval,
  }: Props = $props()

  const busy = $derived(Boolean(cardBusy))
</script>

{#each appResults as result, index (result.cardId ?? index)}
  <AppResultCard {result} />
{/each}
{#if activeAsk}
  {#key activeAsk.askId}
    <AskCard
      ask={activeAsk}
      locked={askLocked}
      picked={answeredAsks[activeAsk.askId] || []}
      multiSelected={askMulti[activeAsk.askId] || []}
      focusIndex={askFocus}
      onToggle={toggleAskOption}
      onSubmit={submitAsk}
      onSkip={skipAsk}
      onKeydown={askKeydown}
    />
  {/key}
{:else if activeCard?.kind === 'takeover'}
  <TakeoverCard card={activeCard} {busy} {takingOver} onResolve={resolveCard} />
{:else if activeCard?.kind === 'connect'}
  <ConnectCard card={activeCard} {busy} onResolve={resolveCard} />
{:else if activeCard?.kind === 'secret'}
  <SecretCard card={activeCard} {busy} bind:secret={cardSecret} onResolve={resolveCard} />
{:else if activeCard?.kind === 'app_send'}
  {#key activeCard.cardId}
    <AppSendCard card={activeCard} {busy} onResolve={resolveCard} />
  {/key}
{:else if activeCard?.kind === 'suggest'}
  <SuggestBotCard card={activeCard} {busy} limitReached={agentLimitReached} onResolve={resolveCard} />
{/if}
{#each pendingApprovals as approval (approval.id)}
  <ApprovalCard {approval} busy={approvalBusy} onApprove={onApproveApproval} onDeny={onDenyApproval} />
{/each}
