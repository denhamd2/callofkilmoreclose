## TOUCH CONTROLS — the Android control surface.
##
## Drawn entirely in code (`_draw`), with no texture assets. That is not
## minimalism for its own sake: touch control art is the kind of thing that
## gets replaced the moment a designer looks at it, and shipping a placeholder
## PNG into the repository now means shipping it forever. Vector circles cost
## nothing, scale to any DPI, and are one function to restyle.
##
## LAYOUT — the standard two-thumb phone layout:
##   left  third of the screen : virtual stick, appears where the thumb lands
##   right two-thirds          : drag to look
##   bottom right              : action buttons
##
## The stick is FLOATING rather than fixed. A fixed stick requires the player
## to find it without looking; a floating one appears under the thumb wherever
## it touches down, which is what every shipped mobile shooter does and is
## noticeably more forgiving on a small screen.
##
## Everything here writes into the `PlayerInput` autoload. It does not talk to
## David or the car directly, so the touch layer can be removed entirely
## without any gameplay code knowing.

extends Control

## Radius of the virtual stick's travel, in design pixels.
const STICK_RADIUS := 110.0
const STICK_KNOB := 46.0
## A drag under this many pixels is treated as a tap, not a look.
const TAP_SLOP := 14.0
const TAP_TIME := 0.28

const COL_RING := Color(1.0, 1.0, 1.0, 0.22)
const COL_KNOB := Color(1.0, 1.0, 1.0, 0.38)

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO

var _look_touch := -1
var _look_last := Vector2.ZERO
var _look_start := Vector2.ZERO
var _look_time := 0.0


@onready var _buttons: Array[Button] = []


func _ready() -> void:
	# Only present on a touch device. On desktop the whole layer stays hidden
	# and costs nothing.
	visible = PlayerInput.touch_ui
	set_process(visible)
	set_process_input(visible)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Wired in code rather than through scene signal connections: a mistyped
	# connection in a .tscn fails silently at load, whereas this fails loudly.
	for child in get_children():
		if child is Button:
			_buttons.append(child)
	var interact := get_node_or_null("InteractButton")
	if interact is Button:
		interact.pressed.connect(PlayerInput.touch_interact)
	var jump := get_node_or_null("JumpButton")
	if jump is Button:
		jump.pressed.connect(PlayerInput.touch_jump)


## True if `pos` falls on one of the action buttons. The look/tap handler must
## ignore those touches, or pressing "Get in" would also register as a punch.
func _over_button(pos: Vector2) -> bool:
	for b in _buttons:
		if b.visible and b.get_global_rect().has_point(pos):
			return true
	return false


func _process(delta: float) -> void:
	if _look_touch != -1:
		_look_time += delta


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	var left := e.position.x < size.x * 0.34
	if e.pressed:
		if _over_button(e.position):
			return
		if left and _stick_touch == -1:
			_stick_touch = e.index
			_stick_origin = e.position
			_stick_pos = e.position
			queue_redraw()
		elif not left and _look_touch == -1:
			_look_touch = e.index
			_look_last = e.position
			_look_start = e.position
			_look_time = 0.0
	else:
		if e.index == _stick_touch:
			_stick_touch = -1
			PlayerInput.set_touch_move(Vector2.ZERO)
			PlayerInput.set_touch_sprint(false)
			queue_redraw()
		elif e.index == _look_touch:
			# A short, still touch on the right of the screen is a tap, and a
			# tap is melee. Getting this from the look surface rather than a
			# dedicated button keeps the HUD clear.
			var moved := e.position.distance_to(_look_start)
			if moved < TAP_SLOP and _look_time < TAP_TIME:
				PlayerInput.touch_melee()
			_look_touch = -1


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _stick_touch:
		_stick_pos = e.position
		var v := (_stick_pos - _stick_origin) / STICK_RADIUS
		if v.length() > 1.0:
			v = v.normalized()
		# Screen Y is down, movement Y is forward.
		PlayerInput.set_touch_move(Vector2(v.x, -v.y))
		# Pushing the stick to its edge is sprint — no separate button, and it
		# maps onto what the player is already doing to run.
		PlayerInput.set_touch_sprint(v.length() > 0.92)
		queue_redraw()
	elif e.index == _look_touch:
		PlayerInput.add_touch_look(e.position - _look_last)
		_look_last = e.position


func _draw() -> void:
	if _stick_touch == -1:
		return
	draw_circle(_stick_origin, STICK_RADIUS, COL_RING, false, 3.0)
	var knob := _stick_pos - _stick_origin
	if knob.length() > STICK_RADIUS:
		knob = knob.normalized() * STICK_RADIUS
	draw_circle(_stick_origin + knob, STICK_KNOB, COL_KNOB)
