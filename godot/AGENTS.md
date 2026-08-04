# Godot agents — Kilmore Close

**Ziva source of truth:** [Ziva on the Godot Asset Store](https://store.godotengine.org/asset/ziva/ziva/)

**Ziva is opt-in only** — freemium credits run out. Do **not** use Ziva unless the task
explicitly invokes it (e.g. `@ziva`, “use Ziva”, “in the Godot editor with Ziva”).
Default Godot work stays in **Cursor** (or your usual agent).

## Install Ziva (if missing)

Ziva is a **GDExtension** addon at `addons/ziva_agent/` (not a `plugin.cfg` editor plugin).

**macOS (recommended):**

```sh
bash godot/tools/install_ziva.sh
```

Or: `curl -fsSL https://ziva.sh/install.sh | bash` (GUI installer), then copy `addons/ziva_agent/` into this project.

**Manual:** Download from [ziva.sh/download](https://ziva.sh/download), extract `addons/ziva_agent/` into `godot/addons/`.

**Enable:** Open `godot/project.godot` in Godot **4.7+**. The extension auto-registers (`ziva_agent.gdextension`). Restart the editor if the Ziva panel does not appear.

Do **not** commit API keys or Ziva credentials to this repo.

## Account and provider setup (required before first use)

1. Create a free account at [ziva.sh](https://ziva.sh) (Hobby tier: $3/month AI balance, unlimited free model tier).
2. In Godot, open the **Ziva** panel and sign in.
3. Choose a provider and enter credentials **in Ziva settings only** (never in `project.godot` or scripts):
   - OpenAI (ChatGPT)
   - Anthropic (Claude)
   - Google (Gemini)
   - MiniMax, or local Ollama / LM Studio
4. Review each provider’s data-retention policy in the Ziva UI before sending project code.

**Smoke test prompts:**

- List scenes under `res://scenes/`
- Read `res://scripts/player/david_controller.gd` and summarize collision layers

## Use Ziva only when explicitly invoked

Invoke with `@ziva`, “use Ziva”, or an explicit “run this in Ziva” request. Then use Ziva
(in the Godot editor) for:

- Editing or creating Godot scenes (`.tscn`)
- Scene trees, nodes, signals, resources, project settings
- GDScript that depends on existing scene structure
- Player controllers, animation, collisions, cameras, combat wiring, UI scenes
- Debugging Godot editor/runtime errors
- Godot documentation lookup and scene-aware context

## Default: Cursor for everything else

Unless `@ziva` / explicit Ziva invocation:

- Godot-native implementation in Cursor (read scenes/scripts first; no speculative edits)
- Planning and architecture notes
- Markdown, docs, and specs
- Repo search and summarization
- Git operations
- Shell tasks that do not need the Godot editor
- Non-Godot config unless explicitly requested

## Project constraints (frozen baseline)

- **Do not change** unless the task explicitly says otherwise:
  - Street measurements and house count: `data/kilmore_close.gd`
  - The fact that time never advances — one fixed sun, no day/night
  - Car enter/drive/exit flow
- **Renderer is `forward_plus`, desktop-first.** Android was dropped; do not
  reinstate mobile fill-rate rules (no normal maps, opaque glass, shadows off) by
  inertia. The post-processing stack lives in `scripts/world/kilmore_sky.gd`,
  because Sky3D builds the `Environment` at runtime and no Environment resource
  is authored anywhere.
- **Cast** roam a navmesh (`CharacterBody3D` + `NavigationAgent3D`), carry
  `Health`, belong to factions, and fight via `scripts/ai/combat_brain.gd`.
- **Current slice:** Quaternius mannequin + shared `QuaterniusAnimDriver` for
  David, cast and the training dummy; melee plus a 7-weapon catalogue.
- **Two traps worth knowing before you touch either file:**
  - `QuaterniusAnimDriver` one-shots switch the `AnimationTree` off. Turning it
    back on must re-seat the state machine playback, or `_travel()` no-ops and the
    skeleton falls back to its rest T-pose — this froze every actor permanently on
    their first jump or punch.
  - `AnimationTree.root_node` resolves only because assigning `anim_player` copies
    the player's resolved root. Do not set `root_node` by hand and do not reparent
    the tree, or every clip silently stops resolving with no error.

## Workflow

1. Unless the user invoked `@ziva`, implement in **Cursor**.
2. If `@ziva` / explicit Ziva request: paste or run the task in the **Ziva** panel in Godot.
3. Keep changes **minimal** and **incremental** — one subsystem per pass.
4. **Read real files** before editing scenes or scripts; never guess node paths.
5. Verify after each pass (all four gates). **Open `godot/shots/` and look** at PNGs
   for anything touching rendering, materials, animation, combat, or street dressing.

**Entry scene:** `scenes/ui/title.tscn` is the player-facing boot screen. Gate runs
(`--probe`, `--shot`, `--profile`) auto-skip it and load `scenes/main.tscn` directly.

```sh
python3 godot/tools/validate_project.py     # structural; must print OK
godot --path godot --headless -- --probe    # gameplay/nav/combat; must exit 0
godot --path godot -- --shot                # windowed; inspect godot/shots/
godot --path godot -- --profile             # windowed; real render budget
```

Targeted visual checks:

```sh
godot --path godot -- --shot --shot-drive   # car cabin / bloodied glass
godot --path godot -- --shot --shot-fight   # brawl test; read FIGHT_TEST line in log
godot --path godot -- --shot --shot-anim    # flinch/one-shot playback diagnostic
```

Windowed bisect for FPS regressions: combine `--profile` with flags documented in
`scripts/core/profile_toggles.gd` (`--profile-no-sdfgi`, `--profile-no-ai`, etc.).
Record ranked results in root `CLAUDE.md`.

## Patterns to follow

| Concern | Pattern |
|---------|---------|
| Damage | `Damage.apply(target, amount, source)` → `Health` child |
| Combat AI | `CombatBrain` child; perception at 6 Hz; seeded RNG |
| One-shot anims | `_player.active = true` when tree off; priority death > flinch > attack |
| Street FX | `DecalPool.project()` at hit position + normal |
| Cars | One physics `Car`; `park_slots` possession; `Health` + `apply_car_damage` |
| Trees | `dress_tree()` paints canopy + procedural `GeneratedTrunk` cylinder |
| Probes | Extend `runtime_probe.gd` when adding gameplay contracts |

`--headless` runs a dummy RenderingDevice, so it cannot verify a single pixel and
every `RENDER_*` monitor reads 0. After adding a new `class_name`, rescan or
nothing referencing it will parse:

```sh
godot --path godot --headless --editor --quit
```

## Ziva customization

Ziva reads this file automatically. Add project-specific instructions here as the slice evolves.
