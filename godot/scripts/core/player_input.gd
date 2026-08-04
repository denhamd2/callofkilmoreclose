## PLAYER INPUT — one merged input surface for desktop and Android.
##
## Autoloaded as `PlayerInput` (see project.godot). Everything that reads input
## — David, the camera, the car — reads it from here and nowhere else. That is
## the whole point: the touch HUD and the keyboard feed the *same* fields, so
## there is exactly one control path to reason about and the mobile build is
## not a second, half-tested branch of the movement code.
##
## WHY THE INPUT MAP IS BUILT IN CODE RATHER THAN IN project.godot
## Godot serialises input events into project.godot as long `Object(...)`
## literals with a dozen properties each. That format is written by the editor
## and is unforgiving of a hand-typed mistake — a single bad property name
## fails project load outright. Registering the actions here instead makes the
## bindings readable, diffable, and impossible to typo into an unloadable
## project. It also puts the keyboard layout next to the touch layout, which is
## where you want it when adding a control.
##
## `_ACTIONS` is the only place a key binding is written down.

extends Node

## Emitted on the frame the action is triggered, from key OR touch button.
signal interact_pressed
signal melee_pressed
signal fire_pressed
signal jump_pressed
## Weapon selection. There was previously no keyboard route to arming David at
## all — only clicking the on-screen selector with a captured cursor — so the
## ranged half of combat could not be exercised by hand.
signal weapon_slot(slot: int)
signal weapon_cycle(dir: int)

## Keyboard bindings. action -> array of physical keycodes.
## Physical keycodes are used so the layout follows the key's *position* and
## WASD still works on an AZERTY keyboard.
const _ACTIONS := {
	"kc_forward": [KEY_W, KEY_UP],
	"kc_back": [KEY_S, KEY_DOWN],
	"kc_left": [KEY_A, KEY_LEFT],
	"kc_right": [KEY_D, KEY_RIGHT],
	"kc_sprint": [KEY_SHIFT],
	"kc_jump": [KEY_SPACE],
	"kc_interact": [KEY_F, KEY_E],
	"kc_melee": [KEY_V, KEY_Q],
	"kc_fire": [KEY_J],
	"kc_handbrake": [KEY_SPACE],
	"kc_free_cursor": [KEY_ESCAPE],
	"kc_weapon_next": [KEY_TAB],
	"kc_weapon_1": [KEY_1],
	"kc_weapon_2": [KEY_2],
	"kc_weapon_3": [KEY_3],
	"kc_weapon_4": [KEY_4],
	"kc_weapon_5": [KEY_5],
	"kc_weapon_6": [KEY_6],
	"kc_weapon_7": [KEY_7],
}

## Number-key actions, in slot order, mapped onto WeaponCatalog.list_ids().
const _WEAPON_SLOTS := [
	"kc_weapon_1", "kc_weapon_2", "kc_weapon_3", "kc_weapon_4",
	"kc_weapon_5", "kc_weapon_6", "kc_weapon_7",
]

## Mouse sensitivity, radians per pixel of motion.
const MOUSE_SENS := 0.0022
## Touch look sensitivity, radians per pixel of drag. Higher than mouse: a
## thumb travels far less distance than a mouse does.
const TOUCH_SENS := 0.0060
## Gamepad look rate, radians/second at full stick deflection.
const PAD_LOOK_RATE := 2.6
const PAD_DEADZONE := 0.18

## True when the game should present touch controls rather than expect a mouse.
var touch_ui: bool = false

# Touch state, written by the touch HUD (scripts/ui/touch_controls.gd).
var _touch_move := Vector2.ZERO
var _touch_look := Vector2.ZERO
var _touch_sprint := false

# Accumulated mouse look, consumed once per frame by the camera.
var _mouse_look := Vector2.ZERO


func _ready() -> void:
	_register_actions()
	# Treat a touchscreen device as touch-first. `is_touchscreen_available()`
	# is also true for touch-capable laptops, so the OS check keeps a desktop
	# with a touch monitor on mouse-and-keyboard.
	#
	# `--touch` forces the mobile control path on regardless. project.godot
	# turns on `pointing/emulate_touch_from_mouse` so the on-screen stick can be
	# driven with a mouse, but that setting is useless on its own: without an
	# override the HUD hides itself on every desktop, so the one control path
	# that cannot be tested is the one most likely to be broken. Run it with:
	#
	#     godot --path godot -- --touch
	#
	# User args (after the bare `--`) are used so this can never collide with an
	# engine flag.
	touch_ui = (DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")) \
		or OS.get_cmdline_user_args().has("--touch")
	# The touch HUD needs a visible cursor to be driven by the mouse, so the
	# capture is skipped whenever the touch path is active — on device or forced.
	if not touch_ui:
		_capture_mouse(true)
	# Keep running when the window loses focus? No — a phone backgrounding the
	# app should not keep simulating. This is the default; stated for clarity.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _register_actions() -> void:
	for action in _ACTIONS:
		var id := StringName(action)
		if not InputMap.has_action(id):
			InputMap.add_action(id, 0.2)
		for code in _ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(id, ev)
	var fire := InputEventMouseButton.new()
	fire.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event(&"kc_fire", fire)
	# RVCE Pogo reads these; KilmoreDriveAgent bridges from PlayerInput instead.
	for rvce_action in ["reset", "throttle", "brake", "steer_left", "steer_right", "clutch", "gear up", "gear down"]:
		if not InputMap.has_action(rvce_action):
			InputMap.add_action(rvce_action)


func _mouse_captured() -> bool:
	return Input.mouse_mode != Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _mouse_captured():
			_mouse_look += event.relative
		return
	if event.is_action_pressed(&"kc_free_cursor"):
		_capture_mouse(false)
		return
	# Clicking back into the window re-captures the cursor on desktop.
	if event is InputEventMouseButton and event.pressed and not touch_ui:
		if not _mouse_captured():
			_capture_mouse(true)
			return
	# Wheel cycles weapons. Handled before the action block because a wheel event
	# is a mouse button and would otherwise fall through to kc_fire.
	if event is InputEventMouseButton and event.pressed:
		var btn := (event as InputEventMouseButton).button_index
		if btn == MOUSE_BUTTON_WHEEL_UP:
			weapon_cycle.emit(1)
			return
		if btn == MOUSE_BUTTON_WHEEL_DOWN:
			weapon_cycle.emit(-1)
			return
	if event.is_action_pressed(&"kc_weapon_next"):
		weapon_cycle.emit(1)
		return
	for slot in _WEAPON_SLOTS.size():
		if event.is_action_pressed(StringName(_WEAPON_SLOTS[slot])):
			weapon_slot.emit(slot)
			return
	if event.is_action_pressed(&"kc_interact"):
		interact_pressed.emit()
	elif event.is_action_pressed(&"kc_melee"):
		melee_pressed.emit()
	elif event.is_action_pressed(&"kc_fire"):
		fire_pressed.emit()
	elif event.is_action_pressed(&"kc_jump"):
		jump_pressed.emit()


func _capture_mouse(on: bool) -> void:
	# CONFINED_HIDDEN keeps the cursor off-screen but does not warp clicks to the
	# window centre, so HUD buttons (punch / fire) still receive mouse hits.
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN if on else Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------- polling

## Movement intent. x = strafe (+right), y = forward (+forward).
## Length is clamped to 1 so diagonals are not faster than straight lines.
func move_axis() -> Vector2:
	var v := Vector2(
		Input.get_action_strength(&"kc_right") - Input.get_action_strength(&"kc_left"),
		Input.get_action_strength(&"kc_forward") - Input.get_action_strength(&"kc_back")
	)
	v += _touch_move
	v += Vector2(_pad(JOY_AXIS_LEFT_X), -_pad(JOY_AXIS_LEFT_Y))
	return v.limit_length(1.0)


## Look delta for this frame, in radians. x = yaw (+right), y = pitch (+down).
## Destructive read: calling this consumes the accumulated mouse/touch motion,
## so exactly one consumer (the camera) may call it per frame.
func consume_look(delta: float) -> Vector2:
	var out := _mouse_look * MOUSE_SENS + _touch_look * TOUCH_SENS
	out += Vector2(_pad(JOY_AXIS_RIGHT_X), _pad(JOY_AXIS_RIGHT_Y)) * PAD_LOOK_RATE * delta
	_mouse_look = Vector2.ZERO
	_touch_look = Vector2.ZERO
	return out


func sprinting() -> bool:
	return Input.is_action_pressed(&"kc_sprint") or _touch_sprint \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)


func handbrake() -> bool:
	return Input.is_action_pressed(&"kc_handbrake") or _touch_sprint


func _pad(axis: JoyAxis) -> float:
	var v := Input.get_joy_axis(0, axis)
	return 0.0 if absf(v) < PAD_DEADZONE else v


# ---------------------------------------------------- written by the touch HUD

func set_touch_move(v: Vector2) -> void:
	_touch_move = v


func add_touch_look(v: Vector2) -> void:
	_touch_look += v


func set_touch_sprint(on: bool) -> void:
	_touch_sprint = on


func touch_interact() -> void:
	interact_pressed.emit()


func touch_melee() -> void:
	melee_pressed.emit()


func touch_fire() -> void:
	fire_pressed.emit()


func touch_jump() -> void:
	jump_pressed.emit()
