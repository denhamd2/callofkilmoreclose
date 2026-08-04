# Kilmore Close — Godot handoff (frozen)

**Status:** Phases 1–7 complete. **This branch is stopped.** Do not add features, art, or tuning here unless a real bug is found.

| Item | Value |
|---|---|
| Engine | Godot **4.7.1** (4.7.x stable) |
| Frozen branch | `claude/godot-phase-7-reference-fidelity` |
| Frozen tags | `godot-phase-7` (art baseline) · `godot-frozen` (handoff + verified) |
| Project root | `godot/project.godot` |
| Reference plates | `godot/assets/reference/` (four Street View screenshots) |
| Three.js prototype | `../src/` — **not used by Godot; do not wire back** |

---

## 1. Handoff checklist

### Frozen (done on this branch)

- [x] Phase 1 — core loop: walk, camera, car, touch, fixed daylight
- [x] Phase 2 — full street (52 houses) + idle cast at doors
- [x] Phase 3 — procedural audio (ambience, footsteps, melee thud)
- [x] Phase 4 — performance profile; collision 185→27; wall/roof shadows only
- [x] Phase 5 — tileable materials; `car.glb` / `person.glb`
- [x] Phase 6 — reference match (boundaries, facades, dressing, overcast sky)
- [x] Phase 7 — reference fidelity (material contrast, facade depth, hero glTFs, plaques, sky clouds)
- [x] Tags `godot-phase-1` … `godot-phase-7` + `godot-frozen`
- [x] Export presets: Android, macOS, Linux (project-level)
- [x] `validate_project.py` — structural checks pass
- [x] `--probe` — exit 0 (`ok: true`, 27 collision shapes, 52 houses, 5 cast)
- [x] `--profile` — physics p50 ~0.003 ms (no regression vs phase 4 budget)

### Your machine (before any new work)

- [ ] Install Godot **4.7.1** + matching export templates
- [ ] Run validation gates below on your hardware
- [ ] (Android) Complete one-time SDK/JDK setup per § Android notes
- [ ] Start the **next** scope on a **new branch** from `godot-frozen` or `godot-phase-7`

### Validation gates (run from repo root)

```sh
python3 godot/tools/validate_project.py
godot --path godot --headless -- --probe          # must exit 0
godot --path godot --headless -- --profile        # optional; prints JSON metrics
```

`--probe` checks spawn@18, movement, enter/drive/exit, 52 houses, 5 cast, audio
safety (disabled headless), collision budget (≤ 35 shapes), daylight (sun > 1.0).

---

## 2. What the frozen branch contains

A **playable, offline** Godot 4.7 slice of measured Kilmore Close:

| System | State |
|---|---|
| **Street** | 13 semi-D pairs/side, 52 houses, generated from `data/kilmore_close.gd` |
| **Player** | David — third-person walk/sprint/jump/melee; spawns outside no. 18 |
| **Car** | Kinematic hatchback at kerb outside 18; enter / drive / exit |
| **Cast** | MickMcCabe, Deco McCabe, Oysters, Angela Carpenter, Paddy Mason — idle at doors |
| **Audio** | Procedural ambience, footsteps, melee thud (`StreetAudio` autoload) |
| **Touch** | On-screen stick, drag-look, buttons (`--touch` on desktop) |
| **Visuals** | Phase 7 reference-fidelity suburban Dublin estate (see § Reference match) |
| **Performance** | MultiMesh batching, 27 collision shapes, prop shadows off |
| **Renderer** | `gl_compatibility` on desktop and Android (same path) |
| **Lighting** | Fixed overcast-bright daytime — **no day/night** |

**Not included:** combat AI, missions, interiors, weapons beyond melee, skeletal animation, music/VO, traffic sim, map expansion, `src/` integration.

---

## Reference-match summary (phases 6–7)

Compared against the four Street View plates in `godot/assets/reference/`:

| Reference trait | How it was matched |
|---|---|
| Cream pebbledash semis | Higher-contrast `pebbledash` triplanar + measured pair shell |
| Salmon/red-brown facade bands | `band_mid` panels between window tiers + porch surround |
| Red brick porch accents | `brick_red` porch surround + brick chimney stacks |
| Tripartite windows | Three-pane glazing + vertical mullions per opening |
| Garage lintel panes | Three small `glass` panes above garage door |
| Dark gray tiled roofs | `roof` texture + prism meshes; gutter strip at eaves |
| Brown window/door/garage trim | Mahogany `frame`; textured `garage_door` |
| Lean-to porch roofs | Porch flat lid → small pitched `roof` prism |
| Gutters / downpipes | `pipe` MultiMesh at eaves and outer corners |
| Low front walls + coping | `block_wall` + `coping` replace phase-5 hedges |
| Black gates / railings | `metal_black` pedestrian gates + wall-top rails |
| Driveways + remnant lawns | `drive` hardstanding to garage; shrunk `grass` patches |
| Pale road / footpath / kerb | `tarmac` / slab-joint `path` / `kerb` + roadside verge |
| Trees, wires, bins, parked cars | `tree.glb` instances + wheelie bins + 5 `car.glb` |
| House numbers on gate piers | Dark `number_plaque` + 7-segment digit geometry (no Label3D) |
| David's door / mailbox | Door digits + black mailbox at no. 18 |
| Cloudy-bright overcast mood | `ProceduralSkyMaterial` with `sky_cover` cloud masses |

**Closest practical match:** strong mid-distance typology with improved close-up facade depth and hero assets; houses remain one procedural archetype (no per-door OSM meshes). Phase 7 is the **visual stop point** — further art belongs on a new branch.

---

## What phases 1–7 accomplished

| Phase | Tag | Delivered |
|---|---|---|
| **1** | `godot-phase-1` | Godot 4.7 vertical slice: David third-person, SpringArm camera, kinematic car, touch HUD, measured street sample, fixed midday lighting, Android export preset |
| **2** | `godot-phase-2` | Full Kilmore Close row (13 pairs/side, 52 houses); cast at doors (MickMcCabe, Deco McCabe, Oysters, Angela Carpenter, Paddy Mason); macOS export preset |
| **3** | `godot-phase-3` | `StreetAudio` autoload: looping ambience, cadence footsteps, melee thud — all procedural, no asset files |
| **4** | `godot-phase-4` | Profiled street cost; collision shapes 185→27; MultiMesh shadows limited to wall/roof; probe collision budget |
| **5** | `godot-phase-5` | Tileable street materials (triplanar MultiMesh dress); low-poly `car.glb` / `person.glb`; cast jacket tints preserved |
| **6** | `godot-phase-6` | Reference-matched boundaries (block walls, driveways), facade trim (brown frames, mid panels, gutters/pipes, porch roofs), trees/wires/bins/parked cars, overcast sky grade |
| **7** | `godot-phase-7` | Reference fidelity: contrast textures, tripartite windows, brick porch/chimney, garage lintel, hero `person`/`car`/`tree` glTFs, wheelie bins, gate plaques, cloudy sky |

### Architecture decisions (frozen — do not reopen)

- Custom third-person controller, SpringArm camera, touch controls, InputMap bridge
- `gl_compatibility` renderer on desktop **and** mobile (same visual path)
- One fixed DirectionalLight3D — **no day/night cycle** (overcast grade is still permanent)
- Street built from `data/kilmore_close.gd` via MultiMesh batching
- Kinematic car (not `VehicleBody3D`)
- No third-party addons
- Phase 7 art stays on shared materials + few static glTFs (no skeletal animation, no per-house meshes)

---

## 3. macOS notes

### Run in editor

1. Install [Godot 4.7.1](https://godotengine.org/download/archive/4.7.1-stable/).
2. Import `godot/project.godot` → **F5** to play.
3. CLI: `godot --path godot` (or `~/Applications/Godot.app/Contents/MacOS/Godot --path godot`).

### Test touch controls on desktop

```sh
godot --path godot -- --touch
```

### Export a `.app`

1. **Editor → Manage Export Templates** → install 4.7 templates.
2. **Project → Export → macOS** (preset in `export_presets.cfg`).
3. Export to `build/macos/kilmore-close.app`.
4. Universal binary (`arm64` + `x86_64`); minimum macOS **11.0**.
5. First launch: if Gatekeeper blocks the app, use **System Settings → Privacy & Security → Open Anyway** (unsigned debug export).

No JDK or Android SDK required for macOS-only work.

---

## 4. Android notes

### One-time machine setup

1. **OpenJDK 17** — [Adoptium](https://adoptium.net/temurin/releases/?variant=openjdk17&version=17).
2. **Android SDK** — Android Studio SDK Manager or `sdkmanager` (platform-tools 35+, build-tools 35.0.1, platform 35).
3. **Godot Editor Settings → Export → Android** — set Java SDK Path and Android SDK Path.
4. **Export templates** — Editor → Manage Export Templates.
5. **Debug keystore** — Godot can generate one; never commit keystore or passwords.

Full step-by-step: see [README.md](README.md) § “Run it on Android”.

### Export APK

- Preset: **Android** in `export_presets.cfg` → `build/android/kilmore-close.apk`
- Architecture: **arm64-v8a only** (Play Store 64-bit requirement).
- Gradle build: **off** (prebuilt template path).
- Permissions: **none** (offline game).

### On-device checks

- Landscape, touch stick + drag-look + buttons
- Same `gl_compatibility` renderer as desktop
- Audio should play on boot (ambience), when walking (footsteps), on melee hit (thud)
- Street should read as suburban Dublin under overcast daylight without fill-rate stalls

---

## 5. What remains intentionally out of scope

Do **not** expect these on the frozen branch; they require a **new phase** and **new branch**:

- Further visual polish on this branch (phase 7 is the art stop point)
- Combat AI, pathfinding, missions, police, duels
- Weapons beyond unarmed melee
- Interiors, enterable houses, damage/health systems
- Skeletal animation / animation trees
- Full house glTF library, traffic simulation
- Music, voice acting, dialogue trees
- Day/night, weather, crowds, dynamic traffic
- Map expansion beyond measured Kilmore Close data
- Changes to `../src/` (Three.js prototype)
- New export targets or addon churn
- Vulkan/Forward+ renderer switch without explicit mobile re-baseline

---

## Branch and tag map

| Branch | Role |
|---|---|
| `claude/godot-phase-7-reference-fidelity` | **Frozen reference** (use this) |
| Tag `godot-frozen` | Handoff-verified stop point |
| Tag `godot-phase-7` | Phase 7 art baseline |
| `claude/godot-phase-6-reference-match` | Phase 6 snapshot |
| `claude/godot-phase-5-visual-polish` | Phase 5 snapshot |
| `claude/godot-phase-4-performance` | Phase 4 snapshot |
| `claude/godot-phase-3-audio` | Phase 3 snapshot |
| `main` | Upstream fork root (CLAUDE.md only; Godot lives on branches above) |

To resume development:

```sh
git checkout claude/godot-phase-7-reference-fidelity   # or: git checkout godot-frozen
git checkout -b claude/godot-phase-8-<scope>
```

---

## Release notes (v1.1 — frozen)

**Kilmore Close — Godot port, phases 1–7 (complete)**

- Walk and drive a full measured Kilmore Close street in fixed overcast daylight
- David spawns outside number 18; car at the kerb
- Five named neighbours idle at their doors
- Procedural street audio
- Reference-fidelity suburban dressing: tripartite windows, brick porch accents, gate plaques, wheelie bins, hero car/person/tree models, cloudy sky
- Optimised for mobile: MultiMesh street, 27 collision shapes, wall/roof shadows only, VRAM-compressed textures
- macOS and Android export presets included

**Known limitations:** No GPU frame-time capture in headless CI; validate on device before shipping APK. Android SDK paths are per-machine editor settings. House numbers are a documented convention, not OSM survey data.

---

## 6. Final freeze verdict

**READY TO STOP.**

- Branch `claude/godot-phase-7-reference-fidelity` is the authoritative Godot artifact.
- Phase 7 art closes the largest remaining gaps vs the Street View reference plates within the MultiMesh performance budget.
- Gameplay, layout, controllers, audio, and performance budget are unchanged from validated phase 4/5 gates.
- No further feature, art, or tuning work on this branch unless a **real bug** is found (regression in probe, export, or crash).

Any new scope — skeletal cast, combat AI, interiors, map growth — requires a **new branch** from `godot-frozen`.
