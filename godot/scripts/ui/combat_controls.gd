## On-screen Punch / Fire buttons (desktop + touch).

extends Control

@onready var _fire_btn: Button = $FireButton
@onready var _punch_btn: Button = $PunchButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20
	if _fire_btn != null:
		_fire_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_fire_btn.pressed.connect(_on_fire_pressed)
	if _punch_btn != null:
		_punch_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_punch_btn.pressed.connect(_on_punch_pressed)


func _on_punch_pressed() -> void:
	PlayerInput.touch_melee()


func _on_fire_pressed() -> void:
	PlayerInput.touch_fire()
