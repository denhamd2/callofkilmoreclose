# CLAUDE.md — Call of Kilmore Close

**The live project is the Godot 4.7 port in `godot/`.** Start there:
[`godot/README.md`](godot/README.md) for how to run it,
[`godot/HANDOFF.md`](godot/HANDOFF.md) for state and gates,
[`godot/AGENTS.md`](godot/AGENTS.md) for tooling.

Originally a fork of `mshumer/Claude-of-Duty` — a procedural, no-art-assets
browser FPS (Three.js r180, WebGL2) — retargeted from a fictional
Middle-Eastern market street onto the real Kilmore Close, Dublin, with a named
cast. That Three.js prototype still exists in `src/` but is **no longer the
target**: nothing in `godot/` imports from it, and `godot/HANDOFF.md` says
explicitly not to wire it back.

`ARCHITECTURE.md` binds `src/` only. It is not a contract for `godot/`.

## Current state

Playable Godot slice: walk or drive a measured Kilmore Close under fixed
overcast daylight, with five named neighbours who roam the street on a navmesh
and fight each other and the player unprompted.

| | |
|---|---|
| Engine | Godot **4.7.1**, `forward_plus` (Metal on macOS) |
| Target | **Desktop-first.** Android was dropped — see below |
| Street | 52 houses, 13 semi-detached pairs a side, generated from `data/kilmore_close.gd` |
| Player | David — third-person, skeletal locomotion, melee + 7 weapons, health, respawn |
| Cast | MickMcCabe, Deco McCabe, Oysters, Angela Carpenter, Paddy Mason — navmesh roaming, factions, mixed loadouts |
| Combat | `Health` / `Damage` / `Factions` + `CombatBrain`: perception, target selection, melee and hitscan ranged |
| Lighting | One fixed sun via Sky3D. No day/night, ever |
| Render | AgX tonemap, SSAO, SSIL, SSR, glow, volumetric fog, SDFGI, 4096 PCSS shadows, 4× MSAA |
| Materials | Albedo + derived normal + packed ORM (`tools/generate_pbr_maps.py`) |

Measured windowed (`-- --profile`): **~49 fps p50, 20 ms frame p50, ~490 draw
calls**. Physics p50 is ~0.003 ms and always was — that number is the profiler's
own callback cost and has never been a render measurement.

## Why Android was dropped

The port was built for a low-end phone: `gl_compatibility`, one light, no normal
maps, opaque glass, shadows stripped from ~90% of the scene. That capped the
visual ceiling hard, because `gl_compatibility` cannot do SSAO, SSIL, SSR,
volumetric fog or mesh LOD *at all*. It was also actively broken: Sky3D's shaders
treat Compatibility as a special case, and the sky rendered black.

Desktop-first was chosen deliberately, and the export preset still exists, but
mobile fill-rate is no longer a constraint on any decision. Do not reinstate the
old budget rules by inertia — the comments explaining them are gone from
`street_builder.gd` for a reason.

## Non-negotiable

- **Offline.** No runtime network calls, no CDN fetches. Map and roster data are
  checked-in static data.
- **No day/night.** One fixed sun. A moving sun means you can never tell whether
  a change improved the work or just caught better light.
- **Seeded RNG per actor**, not global randomness — the `--probe` gates assert
  reproducible combat outcomes. (The old "no `Math.random()`, use `ctx.rng`" rule
  came from the Three.js side; a seeded `RandomNumberGenerator` is its Godot
  equivalent.)
- **The street is generated, not authored.** `data/kilmore_close.gd` holds the
  measurements; hand-placing houses is how a row silently drifts out of rhythm.
- **Content anchor: OSM way 37211091.** Kilmore Close's real geometry is ground
  truth for the street tables.

## Gates — run all four after any change

```sh
python3 godot/tools/validate_project.py     # structural; must print OK
godot --path godot --headless -- --probe    # gameplay/nav/combat; must exit 0
godot --path godot -- --shot                # windowed; then LOOK at godot/shots/
godot --path godot -- --profile             # windowed; render budget
```

`--headless` uses a **dummy RenderingDevice**. It can prove gameplay, navigation
and combat; it cannot prove a single pixel, and every `RENDER_*` monitor reads 0.
Any rendering change must be verified with `--shot` and human eyes.

`--probe` asserts spawn, movement, drive, 52 houses, 5 cast, collision budget
(70–96 shapes), daylight, navmesh (>200 polys, pathable end to end), universal
health, factions, roaming displacement, and that a brawl actually breaks out.

**Adding a new `class_name` requires an editor rescan** or every reference fails
to parse with "Could not find type":

```sh
godot --path godot --headless --editor --quit
```

## Workflow: sequential passes, not parallel fan-out

This project's own history (see `README.md` "Process note") found sequential
single-owner passes beat parallel fan-out decisively (+1.00 score, defects
66→26), while parallel fan-out made things worse. One subsystem or concern per
pass, verified by the gates above before starting the next. No fanning multiple
agents across directories at once.

## Ask before destructive changes

Confirm before: rewriting the `kilmore_close.gd` street tables wholesale,
removing cast members or subsystem files, changing established signals, or
reinstating the mobile render budget.

## Known open items

- **Characters are untextured mannequins.** The Quaternius animation-library glTF
  *is* the body and contains zero textures — two flat materials, no face, hair or
  clothing. Fixing this is asset acquisition, not engineering: source a character
  on the same 53-bone Rigify rig (`DEF-hand.R` is already the weapon mount) for a
  near-zero-cost retarget. This is now the most conspicuous thing left.
- **The car cannot open its door.** `golf_mk4.glb` has no door mesh, no steering
  wheel, no seats and no interior — 58 meshes, with the entire bodyshell including
  all four door skins as a single mesh named `Roof`. The wheel and seat are
  generated in `car.gd::_build_cabin()`; a door swing needs a model that exports
  `Door_FL` separately. The driver's body is also scaled to 0.8 while seated,
  because a 1.78 m mannequin does not fit a 1.05 m cabin.
- **Houses are boxes.** Unit `BoxMesh`/`PrismMesh` scaled by transform. Normal
  maps and lighting take them a long way, but they will not stop reading as boxes
  without modelled house meshes — which contradicts "the geometry IS the data".
- Gates and railings are solid panels; real ones are see-through verticals.
- No backward or strafe locomotion clips exist in the 46-clip library, so a
  GTA-style 2D locomotion blend space is not possible. Movement-facing turning is
  the correct call and should stay.
- There is no prone or get-up clip either, so a car knockdown parks on the last
  frame of `Death01` and stands up with `Sitting_Exit`.

## Traps that have already bitten once

- **`CharacterBody3D` does not step up**, only snaps down. The 0.125 m kerb needs
  the chamfer ramp in `street_builder.gd::_build_ground()` or everyone gets stuck
  in the road.
- **`_mesh_box()` emits no collision.** Any raised visual surface needs a matching
  `_static_box`, or actors stand buried in it.
- **One `move_and_slide()` per frame.** `NavigationAgent3D`'s `velocity_computed`
  fires every frame once avoidance is on, so `cast_member.gd` moves only there.
- **`golf_mk4.glb` axis order is not the obvious one** — X is height (up is −X),
  Y is length (front is −Y), Z is width. Read it from named parts, not the AABB:
  it is 1.49 m both wide and tall.
