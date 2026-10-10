<script>
  import RuviHero from '../RuviHero.svelte'
  import DeskStream from './DeskStream.svelte'
  import { DeskPhase } from './deskStatus.js'

  const STARTING_RUVI_WIDTH = 140

  let {
    phase = DeskPhase.HOME,
    startingText = '',
    streamSrc = '',
    reconnecting = false,
    image = '',
    takingOver = false,
    locked = false,
    hint = '',
    onClickScreenshot,
    onOpenBrowser,
    onOpenFiles,
    onEscape,
    fullScreen = false,
    onActivity,
  } = $props()
</script>

<div class="desk-stage" class:is-dark={phase === DeskPhase.STREAM} aria-busy={phase === DeskPhase.STARTING}>
  {#if phase === DeskPhase.STARTING}
    <div class="desk-stage-state" role="status"><RuviHero pose="setting-up" width={STARTING_RUVI_WIDTH} variant="inline" /><p>{startingText}</p></div>
  {:else if phase === DeskPhase.STREAM}
    <DeskStream src={streamSrc} {reconnecting} {fullScreen} {onEscape} {onActivity} />
  {:else if phase === DeskPhase.SNAPSHOT}
    <button class="desk-snapshot" class:is-interactive={takingOver} disabled={!takingOver || locked} onclick={onClickScreenshot} aria-label="Browser screenshot. While in control, click a position to interact.">
      <img src={image} alt="Latest screenshot from your bot’s browser" draggable="false" />
    </button>
  {:else}
    <div class="desk-stage-state is-home"><p>{hint}</p></div>
    <nav class="desk-dock" aria-label="Computer apps">
      <button type="button" disabled={locked} onclick={onOpenBrowser} title="Chrome">
        <span class="desk-dock-icon is-chrome" aria-hidden="true"></span><span class="sr-only">Chrome</span>
      </button>
      <button type="button" disabled={locked} onclick={onOpenFiles} title="Files">
        <span class="desk-dock-icon is-files" aria-hidden="true"></span><span class="sr-only">Files</span>
      </button>
    </nav>
  {/if}
</div>

<style>
  .desk-stage { position: relative; flex: 1; min-height: 0; display: flex; flex-direction: column; background: var(--sidebar); }
  .desk-stage.is-dark { background: var(--stream-bg); }
  .desk-stage-state {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 16px;
    padding: 32px 24px;
    color: var(--text-2);
    text-align: center;
    font: 400 var(--fs-name)/1.5 var(--font);
  }
  .desk-stage-state p { max-width: 320px; }
  .desk-stage-state.is-home { padding-bottom: 96px; }
  .desk-snapshot { flex: 1; min-height: 0; display: block; width: 100%; padding: 0; border: 0; border-radius: 0; background: var(--sidebar); cursor: default; }
  .desk-snapshot:disabled { opacity: 1; }
  .desk-snapshot.is-interactive:not(:disabled) { cursor: crosshair; }
  .desk-snapshot img { display: block; width: 100%; height: 100%; object-fit: contain; object-position: top center; user-select: none; }
  .desk-dock {
    position: absolute;
    left: 50%;
    bottom: 20px;
    transform: translateX(-50%);
    display: flex;
    gap: 8px;
    padding: 8px 10px;
    border: 1px solid var(--hairline);
    border-radius: 18px;
    background: color-mix(in srgb, var(--page) 80%, transparent);
    box-shadow: var(--shadow-float);
    backdrop-filter: blur(10px);
  }
  .desk-dock button { width: 44px; height: 44px; padding: 0; border: 0; border-radius: 12px; background: transparent; cursor: pointer; }
  .desk-dock button:hover:not(:disabled) { background: var(--tint-hover); }
  .desk-dock button:disabled { opacity: .5; cursor: default; }
  .desk-dock-icon { display: block; width: 34px; height: 34px; margin: 5px auto; border-radius: 10px; }
  /* App glyphs are drawn in CSS so the dock needs no image assets. */
  .desk-dock-icon.is-chrome {
    border-radius: 50%;
    background:
      radial-gradient(circle at 50% 50%, #fff 0 28%, transparent 29%),
      conic-gradient(from 90deg, #ea4335 0 25%, #fbbc05 0 50%, #34a853 0 75%, #4285f4 0 100%);
  }
  .desk-dock-icon.is-files { border: 1px solid var(--hairline); background: linear-gradient(180deg, var(--page), var(--bubble)); box-shadow: inset 0 -9px 0 var(--danger); }
</style>
