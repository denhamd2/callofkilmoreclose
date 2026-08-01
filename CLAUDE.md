# CLAUDE.md — Call of Kilmore Close

Fork of `mshumer/Claude-of-Duty`: a procedural, no-art-assets browser FPS
(Three.js r180, WebGL2, ~55k lines, 11 subsystems). This fork's job is to
retarget the *content* — the fictional Middle-Eastern market street and its
generic AI soldiers — into a real place and a named cast, without touching
the engine's architecture or performance contract.

**Read `ARCHITECTURE.md` first.** It is still the binding contract for every
subsystem in `src/`. This file only adds the constraints specific to this fork.

## Inherited, non-negotiable (from ARCHITECTURE.md)
- One subsystem owns one directory under `src/`; never edit outside the
  directory the current pass owns. Cross-system access is `ctx.get(id)`, never
  an import.
- `three` is the only dependency. No new npm packages, no CDN fetches, no
  runtime network calls — the game must run fully offline. Any Kilmore Close
  map/roster data must be checked-in static data, not fetched at runtime.
- No `Math.random()` — use `ctx.rng`. No per-frame allocation. `dispose()`
  what you create.
- `npm run build` and `node tools/capture.mjs` must stay green after every change.

## Performance floor — do not regress
Current baseline (Retina, `ultra` preset): 28–30 fps p50 / 14–17 fps p99, 0
shader compiles during play, ~3.7–4.6 s boot. Content changes are expected to
change pixels, so `tools/imagediff.mjs` isn't a zero-diff gate here — but
re-run `tools/profile.mjs` after any world/AI pass and treat a new stall,
recompile, or per-frame allocation as a regression, not a tradeoff.
Watch the point-light permutation trap in ARCHITECTURE.md (§ "point-light
count is a shader permutation key") — any new Kilmore Close street lighting
must keep the visible-light count stable.

## Content anchor: OSM way 37211091
Kilmore Close's real geometry is the ground truth for `src/world/layout.js`'s
`STREET` / `ALLEYS` / `BUILDINGS` tables, replacing the fictional market
street. Preserve the existing data schema (`id, x, z, w, d, floors, setback,
wallKey, streetSide, ...`) so `world/builder.js`, `interiors.js`, and `kit.js`
keep working unmodified — this is a data swap, not a schema change.
Coordinate conversion (lat/lon → engine metres) must be decided and confirmed
before generating building entries — don't silently pick a projection.

## Character roster
David, MickMcCabe, Deco McCabe, Paddy Mason, Oysters replace the generic,
unnamed AI variants in `src/ai/soldier.js` / `squad.js`. `ai` owns character
identity — wire names through the existing `damage:dealt` / `actor:death`
events into `ui/killfeed.js`, which already expects a nameable actor, rather
than inventing a parallel naming path. Whether these five are enemies, squad
AI, or player-selectable changes how `soldier.js`/`squad.js` get extended —
confirm this before implementing.

## Workflow: sequential passes, not parallel fan-out
This project's own history (see `README.md` "Process note") found sequential
single-owner passes beat parallel fan-out decisively (+1.00 score, defects
66→26) while parallel fan-out made things worse (+0.46, defects rose). This
fork follows the same doctrine: one subsystem/concern per pass, verified
(`npm run build` + `capture.mjs`, plus `profile.mjs` where perf-sensitive)
before starting the next. No fanning multiple agents across directories at once.

Suggested order: (1) world layout from OSM data → (2) world dressing/materials
for the new setting → (3) character roster in `ai` → (4) killfeed/UI name
wiring → (5) re-baseline performance.

## Ask before destructive changes
Confirm before: rewriting `STREET`/`ALLEYS`/`BUILDINGS` wholesale, removing
existing AI variants or subsystem files, or changing established events/surface
types. Everything else in ARCHITECTURE.md's ownership rules still applies.

## Current state
Planning only — no gameplay or content code has been touched yet.
