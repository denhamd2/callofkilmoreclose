## Combat HUD — crosshair reticle and target health bar.
##
## A thin CanvasLayer overlay. Finds the training dummy by group and listens
## for health changes. The HP bar auto-hides when the dummy is dead and
## fades back in when it resets.
class_name CombatHUD
extends CanvasLayer

const BAR_WIDTH := 180.0
const BAR_HEIGHT := 14.0
const FADE_TIME := 0.25

var _dummy: TrainingDummy
var _dummy_max_hp := 100.0
var _last_hp := 100.0

@onready var _bar_bg: ColorRect = $HPBar/Background
@onready var _bar_fill: ColorRect = $HPBar/Fill
@onready var _bar_label: Label = $HPBar/Label


func _ready() -> void:
	# Find the training dummy — there's only one in this slice.
	for node in get_tree().get_nodes_in_group(&"combat_dummy"):
		if node is TrainingDummy:
			_dummy = node
			break
	if _dummy != null:
		_dummy.health_changed.connect(_on_dummy_health_changed)
		_dummy_max_hp = TrainingDummy.MAX_HP
	_update_bar()


func _on_dummy_health_changed(current: float, _maximum: float) -> void:
	_dummy_max_hp = _maximum
	_last_hp = current
	_update_bar()


func _update_bar() -> void:
	if _dummy == null:
		_bar_bg.visible = false
		_bar_fill.visible = false
		_bar_label.visible = false
		return
	var ratio := clampf(_last_hp / _dummy_max_hp, 0.0, 1.0)
	var show_bar := ratio > 0.0
	_bar_bg.visible = show_bar
	_bar_fill.visible = show_bar
	_bar_label.visible = show_bar
	if show_bar:
		_bar_fill.size.x = BAR_WIDTH * ratio
		_bar_label.text = "TARGET  %d" % int(ceilf(_last_hp))
