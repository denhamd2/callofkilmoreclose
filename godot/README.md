# Call of Kilmore Close — Godot 4.7 port

**Phases 1–5 complete and frozen.** Reference branch: `claude/godot-phase-5-visual-polish`, tag `godot-phase-5`.

**Handoff:** read [HANDOFF.md](HANDOFF.md) for setup, validation gates, platform notes, and what is out of scope. Do not add features on the frozen branch.

| Phase | Tag | Summary |
|---|---|---|
| 1 | `godot-phase-1` | Core loop: David, camera, car, touch, daylight |
| 2 | `godot-phase-2` | Full street (52 houses) + idle cast |
| 3 | `godot-phase-3` | Procedural ambience, footsteps, melee thud |
| 4 | `godot-phase-4` | Performance profile; collision/shadow hardening |
| 5 | `godot-phase-5` | Street materials + car/person glTF visual polish |

This directory is a **complete, self-contained Godot project**. It does not
share code with the Three.js prototype in `../src`, and nothing here imports
from it.

Verified against the **Godot 4.7 stable** documentation (4.7.0 stable, June 2026; 4.7.1 current). Every engine API used has been checked against the 4.7 class reference.

---

## Run it on desktop (5 minutes)

1. Open Godot 4.7.
2. **Import** → browse to this `godot/` folder → pick `project.godot` → **Import & Edit**.
3. Press **F5** (Run Project).

On first import Godot writes a `.godot/` cache folder. That is generated, not
source, and is git-ignored.

**Controls (desktop)**

| | |
|---|---|
| Move | `W A S D` |
| Look | mouse |
| Sprint | `Shift` |
| Jump | `Space` |
| Punch | `V` or left mouse |
| Get in / out of car | `F` |
| Free the mouse cursor | `Esc` |

David starts on the footpath outside **18 Kilmore Close**, facing his own front
door. The car is at the kerb a couple of metres up the road. Walk to it and the
prompt appears.

**Testing the touch controls without a phone**

The touch HUD hides itself on desktop, so it is off by default when you press
F5. To exercise the mobile control path with a mouse, run with `--touch`:

```sh
godot --path godot -- --touch
```

The bare `--` matters: everything after it is passed to the game rather than to
the engine. `pointing/emulate_touch_from_mouse` is already on in
`project.godot`, so the mouse then drives the on-screen stick, the drag-to-look
surface and the buttons exactly as a thumb would.

---

## Run it on Android

This is a **one-time setup on your machine**, then it is a single button.
It is the fiddliest part of the whole project, so it is written out in full.

### Step 1 — Install OpenJDK 17

Download from [Adoptium](https://adoptium.net/temurin/releases/?variant=openjdk17&version=17).

The Godot docs say higher JDKs also work but recommend **17** specifically for
compatibility. A newer or older JDK is the single most common cause of cryptic
Gradle failures, so take the recommendation.

### Step 2 — Install the Android SDK

Easiest route is [Android Studio](https://developer.android.com/studio/) — run
it once and let it complete SDK setup. Make sure these are installed
(SDK Manager):

- Android SDK Platform-Tools **35.0.0 or later**
- Android SDK Build-Tools **35.0.1**
- Android SDK Platform **35**
- Android SDK Command-line Tools (latest)

Command-line alternative, if you would rather not install Android Studio:

```sh
sdkmanager --sdk_root=<android_sdk_path> \
  "platform-tools" "build-tools;35.0.1" "platforms;android-35" \
  "cmdline-tools;latest" "cmake;3.10.2.4988404" "ndk;28.1.13356709"
```

> On Linux, do **not** use the Android SDK from your distribution's package
> repository — the docs warn it is usually too old.

### Step 3 — Point Godot at both

**Editor → Editor Settings → Export → Android**

- `Java SDK Path` → where you installed OpenJDK 17
- `Android SDK Path` → your SDK folder (it must contain `platform-tools/adb`)

These are *editor* settings, stored per-machine. That is why they are not in
this repository, and why each person who builds has to do this once.

### Step 4 — Export templates and a debug key

- **Editor → Manage Export Templates → Download and Install**
- Godot 4.7 generates a debug keystore for you. If it does not, create one:

```sh
keytool -v -genkey -keystore debug.keystore -alias androiddebugkey \
  -storepass android -keypass android -keyalg RSA -validity 10000
```

then set it in the same Editor Settings page. **Never commit a keystore or its
password.**

### Step 5 — Export

`export_presets.cfg` already contains an **Android** preset. With a phone
plugged in (USB debugging on), the one-click deploy button appears in the top
right of the editor. Otherwise: **Project → Export → Android → Export Project**.

**Controls (touch)** — left third of the screen is a floating movement stick
(push it to the edge to sprint); the right side is drag-to-look, and a *tap* on
that side is a punch. `GET IN` and `JUMP` are buttons, bottom right.

---

## What this slice contains

| | |
|---|---|
| Street | Full Kilmore Close — 13 joined semi-detached pairs a side, 52 houses, at the measured spacing (~251 m housing run) |
| House archetype | White pebbledash, painted band, 2 upstairs windows, 1 downstairs + door, porch with glazed sliding door, single-storey side garage (tileable materials) |
| David | Third-person, spawns outside no. 18, unarmed / melee-ready (static glTF body) |
| Camera | Over-the-shoulder spring-arm boom with wall collision |
| Car | Parked at the kerb outside 18; enter, drive, exit (static glTF mesh, kinematic drive) |
| Cast | MickMcCabe, Deco McCabe, Oysters, Angela Carpenter, Paddy Mason — idle at their front doors, named labels, jacket tints, no combat AI |
| Audio | Looping street ambience, cadence footsteps, melee thud (procedural, no asset files) |
| Addresses | Numbered gate piers on every house, so you can see you are outside 18 — and no. 18 has its own door colour |
| Lighting | Fixed bright daylight. No day/night cycle, ever |
| Mobile | Touch control layer, GL Compatibility renderer, Android + macOS export presets |

### What it deliberately does **not** contain

Stated plainly so nobody goes looking: no combat AI, no weapons beyond melee,
no interiors, no mission logic, no damage model, no skeletal animation, no
music or voice acting. Cast members are street presence only. Bodies are
static glTF (no animation trees).

---

## Project layout

```
godot/
  project.godot            Engine config. Renderer, display, autoloads.
  export_presets.cfg       Android, macOS, and Linux export presets.
  HANDOFF.md               Frozen-phase handoff (setup, gates, out of scope).
  data/
    kilmore_close.gd       THE MEASURED STREET. Single source of truth for
                           every dimension on the map.
    cast.gd                Named residents and house numbers.
  assets/
    textures/              Tileable street albedos (VRAM-compressed on import).
    models/car.glb         Low-poly hatchback visual.
    models/person.glb      Static body parts for David and cast.
  scenes/
    main.tscn              Entry point: environment, sun, street, actors, HUD.
    player/david.tscn      David's body, collider and camera rig.
    cast/cast_member.tscn  Idle neighbour + name label.
    vehicle/car.tscn       The car's mesh and collider.
    ui/touch_controls.tscn Touch HUD.
  scripts/
    audio/street_audio.gd    Autoload: ambience, footsteps, melee thud.
    audio/procedural_sounds.gd  Generated WAV buffers (no imported files).
    core/player_input.gd   Autoload. Merges keyboard/mouse/pad/touch.
    core/main.gd           Places actors and cast from the street data.
    world/street_builder.gd  Generates the whole slice at load time.
    cast/cast_member.gd    Idle doorstep presence, face-near-player.
    player/david_controller.gd
    player/third_person_camera.gd
    vehicle/car.gd
    ui/touch_controls.gd
  tools/
    validate_project.py    Structural checks on the scene/script files.
    runtime_probe.gd       Regression gate (`--probe`).
    performance_profile.gd Scene cost + frame sampling (`--profile`).
```

---

## Design decisions worth knowing

**The street is generated in code, not authored as a scene.** The geometry is
derived from measurements held in `data/kilmore_close.gd`. Hand-placing houses
is how a row silently drifts out of rhythm — which happened to the prototype.
Extending the slice to the full length of the road is two constants.

**Everything repeated is drawn with `MultiMeshInstance3D`.** One draw call per
material rather than per object. The whole street is roughly a dozen draw calls
instead of ~400. This is the main reason it should hold up on a basic phone.

**The Compatibility (OpenGL ES 3.0) renderer, on desktop too.** The docs name
it as the renderer for low-end hardware. Using it on both platforms means
desktop shows you what the phone renders — there is no second visual path to
keep in sync and be surprised by.

**Glass is opaque.** A transparent material pushes the surface into the
alpha-blended pass, which is the most expensive thing you can do on a mobile
tiled GPU. A dark, low-roughness opaque panel reads as glass at street
distance.

**The car is kinematic, not a `VehicleBody3D`.** Godot's raycast vehicle needs
suspension and friction tuning and gets unstable when the physics tick suffers
— which is exactly what happens on a slow phone. A kinematic bicycle model is
stable at any timestep and behaves identically on both platforms.

**There is only one camera.** Driving does not hand over to a vehicle camera;
it moves David into the driver's seat each physics step, so his own camera
comes along. No rig to keep in sync, no blend.

**The lighting never changes.** One DirectionalLight3D at a fixed midday
angle, neutral white, plus sky-sourced ambient. No day/night cycle, no sunset,
no weather, no time-of-day scripting — deliberately, for the whole migration.
A moving sun means you can never tell whether a change improved the work or
just caught better light. It is also the cheapest option on a basic phone.

---

## Third-party addons: what was considered, and what was rejected

Four things in this slice are the sort of thing people usually pull an addon
for. Here is the decision on each, so nobody has to re-litigate it.

| Need | Decision | Why |
|---|---|---|
| Third-person **controller** | **Custom** | The available addons are full *templates* — animation state machines, imported character models, inventory hooks. They bring far more than is needed and would actively fight the movement tuning ported from the prototype (4.57 m/s walk, 92 m/s² ground accel and the rest, calibrated against Modern Warfare). Keeping David's feel across the engine change is the point; an addon would silently replace it. ~220 lines custom. |
| Third-person **camera** | **Custom, on the engine's own `SpringArm3D`** | Godot already ships the hard part — the shape-cast boom that keeps the camera out of walls. Any camera addon is a thin wrapper over the same node. ~110 lines. |
| **Touch joystick** | **Custom — but this was the closest call** | A small virtual-joystick addon is a genuinely reasonable choice here, and if one is wanted later it should replace `scripts/ui/touch_controls.gd` wholesale and write into `PlayerInput.set_touch_move()` / `add_touch_look()`. The interface is deliberately narrow so that swap is cheap. It was not used for one blunt practical reason: **the sandbox this was built in cannot reach the Asset Library or GitHub**, so no addon could be vendored in and verified. Writing 145 lines I can read beat depending on code I could not fetch. |
| **Input action bridge** | **Rejected — no addon needed** | Godot's `InputMap` *is* the bridge. `scripts/core/player_input.gd` registers actions at runtime and merges keyboard, mouse, gamepad and touch into one surface. An addon here would add a dependency to wrap a built-in. |

The general rule applied: **use an addon where it removes real risk, not where
it removes typing.** Nothing here was rejected out of preference for writing
code — the controller and camera cases are about not inheriting a template's
assumptions, and the joystick case is an honest environment limitation with a
documented swap path.

---

## Validating

```sh
python3 godot/tools/validate_project.py
godot --path godot --headless -- --probe
```

Optional performance snapshot:

```sh
godot --path godot --headless -- --profile
```

Catches broken resource references, missing files, load-order mistakes and
malformed scene files. `--probe` is the gameplay regression gate. It **cannot**
type-check GDScript or verify engine API usage — only opening the project in
Godot does that.

See [HANDOFF.md](HANDOFF.md) for the full checklist and platform export notes.
