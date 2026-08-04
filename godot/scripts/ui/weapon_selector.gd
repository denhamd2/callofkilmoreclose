## On-screen weapon picker (Cogito hotbar-style, Kilmore-owned).
##
## Always visible during play. David starts unarmed; tap a slot to equip.

class_name WeaponSelector
extends PanelContainer

signal weapon_selected(id: StringName)

const SLOT_SIZE := 52.0

var _david: DavidController = null
var _buttons: Dictionary[StringName, Button] = {}

@onready var _row: HBoxContainer = $MarginContainer/HBoxContainer


func bind_player(player: DavidController) -> void:
	_david = player
	if _david != null:
		_david.weapon_changed.connect(_on_weapon_changed)
		_on_weapon_changed(_david.weapon_id)


func _ready() -> void:
	_build_slots()


func _build_slots() -> void:
	for child in _row.get_children():
		child.queue_free()
	_buttons.clear()
	for id in WeaponCatalog.list_ids():
		var entry := WeaponCatalog.get_entry(id)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		btn.text = str(entry.get("label", id))
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_slot_pressed.bind(id))
		_row.add_child(btn)
		_buttons[id] = btn
	_highlight(WeaponCatalog.UNARMED)


func _on_slot_pressed(id: StringName) -> void:
	weapon_selected.emit(id)
	if _david != null:
		_david.equip_weapon(id)
	else:
		_highlight(id)


func _on_weapon_changed(id: StringName) -> void:
	_highlight(id)


func _highlight(id: StringName) -> void:
	for key in _buttons.keys():
		var btn := _buttons[key] as Button
		if btn == null:
			continue
		var on: bool = key == id
		btn.modulate = Color(1.0, 0.92, 0.55, 1.0) if on else Color(1, 1, 1, 0.82)
