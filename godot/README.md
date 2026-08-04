# Call of Kilmore Close — Godot port

Phase 1 vertical slice. This directory is a **complete, self-contained Godot
project**. It does not share code with the Three.js prototype in `../src`, and
nothing here imports from it.

Verified against the **Godot 4.6 stable** documentation.

---

## Run it on desktop (5 minutes)

1. Open Godot 4.6.
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
- Godot 4.6 generates a debug keystore for you. If it does not, create one:

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
| Street | A representative stretch of Kilmore Close — 5 joined semi-detached pairs a side, 20 houses, at the real measured spacing |
| House archetype | White pebbledash, painted band, 2 upstairs windows, 1 downstairs + door, porch with glazed sliding door, single-storey side garage |
| David | Third-person, spawns outside no. 18, unarmed / melee-ready |
| Camera | Over-the-shoulder spring-arm boom with wall collision |
| Car | Parked at the kerb outside 18; enter, drive, exit |
| Mobile | Touch control layer, GL Compatibility renderer, Android export preset |

### What it deliberately does **not** contain

Stated plainly so nobody goes looking: no AI or other characters, no weapons,
no interiors, no audio, no mission logic, no damage model, no skeletal
animation. Those are later phases. Pass 1 is about proving the shape of the
thing in Godot, not reproducing the prototype.

---

## Project layout

```
godot/
  project.godot            Engine config. Renderer, display, autoloads.
  export_presets.cfg       Android + Linux export presets.
  data/
    kilmore_close.gd       THE MEASURED STREET. Single source of truth for
                           every dimension on the map.
  scenes/
    main.tscn              Entry point: environment, sun, street, actors, HUD.
    player/david.tscn      David's body, collider and camera rig.
    vehicle/car.tscn       The car's meshes and collider.
    ui/touch_controls.tscn Touch HUD.
  scripts/
    core/player_input.gd   Autoload. Merges keyboard/mouse/pad/touch.
    core/main.gd           Places actors from the street data.
    world/street_builder.gd  Generates the whole slice at load time.
    player/david_controller.gd
    player/third_person_camera.gd
    vehicle/car.gd
    ui/touch_controls.gd
  tools/
    validate_project.py    Structural checks on the scene/script files.
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

---

## Validating

```sh
python3 godot/tools/validate_project.py
```

Catches broken resource references, missing files, load-order mistakes and
malformed scene files. It **cannot** type-check GDScript or verify engine API
usage — only opening the project in Godot does that.
