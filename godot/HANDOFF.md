# Kilmore Close — Godot handoff (frozen)

**Status:** Phases 1–4 complete and frozen. **Do not add features on this branch.**

| Item | Value |
|---|---|
| Engine | Godot **4.7.1** (4.7.x stable) |
| Frozen branch | `claude/godot-phase-4-performance` |
| Frozen commit | tag `godot-phase-4` |
| Project root | `godot/project.godot` |
| Three.js prototype | `../src/` — **not used by Godot; do not wire back** |

---

## Handoff checklist

- [x] Phase 1 — core loop validated (walk, camera, car, touch, fixed daylight)
- [x] Phase 2 — full street (52 houses) + idle cast at doors
- [x] Phase 3 — procedural audio (ambience, footsteps, melee thud)
- [x] Phase 4 — performance profile + collision/shadow hardening
- [x] Tags: `godot-phase-1` … `godot-phase-4` on remote
- [x] Export presets: Android, macOS, Linux (project-level; SDK/templates per machine)
- [ ] **You:** Install Godot 4.7.1 + export templates locally
- [ ] **You:** Run validation gates below before any new work
- [ ] **You:** Start the next phase on a **new branch** with a **new scope**

### Validation gates (run from repo root)

```sh
python3 godot/tools/validate_project.py
godot --path godot --headless -- --probe          # must exit 0
godot --path godot --headless -- --profile        # optional; prints JSON metrics
```

`--probe` checks spawn@18, movement, enter/drive/exit, 52 houses, 5 cast, audio
safety (disabled headless), collision budget (≤ 35 shapes).

---

## What phases 1–4 accomplished

| Phase | Tag | Delivered |
|---|---|---|
| **1** | `godot-phase-1` | Godot 4.7 vertical slice: David third-person, SpringArm camera, kinematic car, touch HUD, measured street sample, fixed midday lighting, Android export preset |
| **2** | `godot-phase-2` | Full Kilmore Close row (13 pairs/side, 52 houses); cast at doors (MickMcCabe, Deco McCabe, Oysters, Angela Carpenter, Paddy Mason); macOS export preset |
| **3** | `godot-phase-3` | `StreetAudio` autoload: looping ambience, cadence footsteps, melee thud — all procedural, no asset files |
| **4** | `godot-phase-4` | Profiled street cost; collision shapes 185→27; MultiMesh shadows limited to wall/roof; probe collision budget |

### Architecture decisions (frozen — do not reopen)

- Custom third-person controller, SpringArm camera, touch controls, InputMap bridge
- `gl_compatibility` renderer on desktop **and** mobile (same visual path)
- One fixed DirectionalLight3D — **no day/night, ever**
- Street built from `data/kilmore_close.gd` via MultiMesh batching
- Kinematic car (not `VehicleBody3D`)
- No third-party addons

---

## macOS notes

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

## Android notes

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

---

## What remains intentionally out of scope

Do **not** expect these on the frozen branch; they require a **new phase** and **new branch**:

- Combat AI, pathfinding, missions, police, duels
- Weapons beyond unarmed melee
- Interiors, enterable houses, damage/health systems
- Skeletal animation, imported character meshes
- Music, voice acting, dialogue trees
- Day/night, weather, crowds, traffic simulation
- Map expansion beyond measured Kilmore Close data
- Changes to `../src/` (Three.js prototype)
- New export targets or addon churn
- Vulkan/Forward+ renderer switch without explicit mobile re-baseline

---

## Branch and tag map

| Branch | Role |
|---|---|
| `claude/godot-phase-4-performance` | **Frozen reference** (use this) |
| `claude/godot-phase-3-audio` | Phase 3 snapshot |
| `claude/kilmore-close-restoration-672ceg` | Phase 1–2 Godot + early Three.js work history |
| `main` | Upstream fork root (CLAUDE.md only; Godot lives on branches above) |

To resume development:

```sh
git checkout claude/godot-phase-4-performance
git checkout -b claude/godot-phase-5-<scope>
```

---

## Release notes (v0.2.0 — frozen)

**Kilmore Close — Godot port, phases 1–4**

- Walk and drive a full measured Kilmore Close street in fixed bright daylight
- David spawns outside number 18; car at the kerb
- Five named neighbours idle at their doors
- Procedural street audio
- Optimised for mobile: MultiMesh street, 27 collision shapes, wall/roof shadows only
- macOS and Android export presets included

**Known limitations:** No GPU frame-time capture in headless CI; validate on device before shipping APK. Android SDK paths are per-machine editor settings.

---

## Final freeze verdict

This branch is **ready to stop**. It is the authoritative Godot artifact through phase 4. Any further work must branch from `godot-phase-4` with an explicit new scope — not incremental edits here.
