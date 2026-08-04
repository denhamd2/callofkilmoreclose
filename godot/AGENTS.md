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
  - Street layout generation tables in `scripts/world/street_builder.gd` (except collision attachment when required)
  - Sky3D static overcast daytime in `scenes/sky_kilmore.tscn` (no time progression)
  - Car enter/drive/exit flow
- **Cast** uses the same Quaternius mannequin as David (doorstep idle / talking; locomotion-ready driver).
- **Current slice:** Quaternius Universal Animation Library mannequin + shared `QuaterniusAnimDriver` (David, cast, training dummy); melee + raycast pistol.

## Workflow

1. Unless the user invoked `@ziva`, implement in **Cursor**.
2. If `@ziva` / explicit Ziva request: paste or run the task in the **Ziva** panel in Godot.
3. Keep changes **minimal** and **incremental**.
4. Verify after each step:

```sh
python3 godot/tools/validate_project.py
godot --path godot --headless -- --probe
```

## Ziva customization

Ziva reads this file automatically. Add project-specific instructions here as the slice evolves.
