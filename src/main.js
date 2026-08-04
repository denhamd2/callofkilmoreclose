import { Engine } from './core/engine.js';
import { createConfig } from './core/config.js';

import { RenderSystem } from './render/index.js';
import { MaterialSystem } from './materials/index.js';
import { SkySystem } from './sky/index.js';
import { WorldSystem } from './world/index.js';
import { PhysicsSystem } from './physics/index.js';
import { PlayerSystem } from './player/index.js';
import { WeaponSystem } from './weapons/index.js';
import { FxSystem } from './fx/index.js';
import { AiSystem } from './ai/index.js';
import { UiSystem } from './ui/index.js';
import { AudioSystem } from './audio/index.js';
import { VehicleSystem } from './vehicle/index.js';
import { GameSystem } from './game/index.js';

import { installShotApi } from './dev/shots.js';
import { prewarm } from './core/prewarm.js';

const params = new URLSearchParams(location.search);
const capture = params.get('capture') === '1';
// Deterministic shutter for the pixel gate: the engine does not schedule its own
// frames, the driver advances exactly N of them through window.__PUMP__. Opt-in,
// because tools that measure real frame pacing (tools/perf.mjs) need the loop to
// free-run. See the long comment in src/dev/shots.js.
const lockstep = capture && params.get('lockstep') === '1';

/**
 * Pick a starting quality preset for the hardware we are actually on.
 *
 * This used to be `params.get('q') ?? 'ultra'` unconditionally, so a phone
 * booted into the same preset as a desktop GPU — TAA, GTAO, SSR, volumetrics,
 * motion blur and 4096 shadow maps. An explicit ?q= still wins, and the capture
 * harness is untouched.
 *
 * Coarse detection on purpose. A touch-primary pointer plus either few cores or
 * little memory is a phone or a cheap tablet; that is exactly the population
 * that needs the `mobile` floor. Desktop machines with touchscreens report a
 * fine pointer, so they do not get caught by this.
 */
function detectQuality() {
  const forced = params.get('q');
  if (forced) return forced;
  if (typeof navigator === 'undefined' || typeof matchMedia === 'undefined') return 'ultra';
  const coarse = matchMedia('(pointer: coarse)').matches;
  const noHover = matchMedia('(hover: none)').matches;
  const cores = navigator.hardwareConcurrency ?? 8;
  const mem = navigator.deviceMemory ?? 8;
  if ((coarse || noHover) && (cores <= 8 || mem <= 6)) return 'mobile';
  if (cores <= 4 || mem <= 4) return 'low';
  return 'ultra';
}

const config = createConfig({
  quality: detectQuality(),
  deterministic: capture,
});
console.info(`[boot] quality preset: ${config.quality}`);

const canvas = document.getElementById('game');

const engine = new Engine({ canvas, config });

// Registration order is irrelevant — Registry topo-sorts on static deps.
engine
  .add(RenderSystem)
  .add(MaterialSystem)
  .add(SkySystem)
  .add(WorldSystem)
  .add(PhysicsSystem)
  .add(PlayerSystem)
  .add(WeaponSystem)
  .add(FxSystem)
  .add(AiSystem)
  .add(UiSystem)
  .add(AudioSystem)
  .add(VehicleSystem)
  .add(GameSystem);

try {
  await engine.init();
} catch (err) {
  console.error('[boot] init failed', err);
  document.body.insertAdjacentHTML(
    'beforeend',
    `<pre style="position:fixed;inset:0;padding:2rem;color:#f66;background:#000;
       font:12px/1.5 ui-monospace,monospace;overflow:auto;z-index:9999;white-space:pre-wrap">
BOOT FAILURE\n\n${err.stack ?? err.message}</pre>`
  );
  throw err;
}

const shotApi = installShotApi(engine, { capture, lockstep });

// Compile every shader permutation before the frame loop starts. Measured: without
// this, 86 programs compile lazily during play, up to 30 on one frame, producing
// 3.1-3.9 SECOND stalls. See src/core/prewarm.js.
//
// ON BY DEFAULT since the capture path was made frame-deterministic; opt out with
// `?prewarm=0`. It is now PROVEN pixel-neutral: `tools/baseline.mjs` with
// `--query=prewarm=0` vs `--query=prewarm=1` reports identical:true on all 11
// shots (0 changed pixels, maxDelta 0). The two things that previously made the
// ~1.4 s pre-warm spend look like a visual change were both boot-duration
// couplings OUTSIDE the subsystems: (1) the shutter frame index was latency-bound
// because the engine kept stepping through the driver's round trips — fixed by
// lockstep in src/dev/shots.js; (2) `will-change: transform` on the compass strip
// cached a composited-layer raster taken at a wall-clock-dependent moment — fixed
// in src/ui/style.js.
const warmup = params.get('prewarm') === '0' ? { ok: false, reason: 'disabled by ?prewarm=0' } : await prewarm(engine);
console.info('[boot] prewarm', warmup);
window.__PREWARM__ = warmup;

engine.start();

// Capture harness handshake: only flag ready once a frame has actually landed.
//
// BOOT_FRAMES is deliberately a frame COUNT, not a rAF race. In lockstep mode the
// engine has no loop of its own, so we hand-pump exactly this many frames and only
// then raise __READY__; the shot is therefore always applied at engine frame 3, no
// matter how long boot (or pre-warm) took in wall-clock terms.
const BOOT_FRAMES = 3;
if (lockstep) {
  await shotApi.pump(BOOT_FRAMES);
  window.__READY__ = true;
} else {
  let warm = 0;
  const readyProbe = () => {
    if (++warm >= BOOT_FRAMES) {
      window.__READY__ = true;
      return;
    }
    requestAnimationFrame(readyProbe);
  };
  requestAnimationFrame(readyProbe);
}

window.__ENGINE__ = engine;

if (import.meta.hot) {
  import.meta.hot.dispose(() => engine.dispose());
}
