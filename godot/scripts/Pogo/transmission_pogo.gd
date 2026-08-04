class_name TransmissionPogo
extends Node

## Передаточные числа передних передач (1-я, 2-я, …). Индекс 0 → 1-я передача.
@export var forward_ratios: Array[float] = [3.8, 2.32, 1.62, 1.27, 1.0, 0.8]
## Передаточное число заднего хода (должно быть отрицательным).
@export var reverse_ratio: float = -3.0
## Главная пара (передаточное число дифференциала). Больше – выше тяга, меньше максимальная скорость.
@export var final_drive: float = 3.9
## Превышение над min_rpm для включения сцепления (RPM).
@export var clutch_engage_rpm_delta: float = 500.0
## Снижение оборотов для автоматического размыкания сцепления (обычно отрицательное).
@export var clutch_disengage_rpm_delta: float = -100.0
## Пороговые обороты для размыкания при торможении двигателем (RPM).
@export var clutch_braking_rpm_delta: float = 800.0
## Время переключения (сек), в течение которого сцепление разомкнуто.
@export var shift_duration: float = 0.2

# Состояния передач
enum GearState { REVERSE = -2, NEUTRAL = -1, FIRST = 0 }

var base_min_rpm: float = 1000.0
var engage_rpm: float
var disengage_rpm: float
var braking_rpm: float

var current_gear_state: int = GearState.NEUTRAL   # REVERSE, NEUTRAL или индекс в forward_ratios
var clutch_engaged: bool = false
var shifting: bool = false
var manual_clutch: bool = false

func _ready() -> void:
	_recalc_thresholds()

func set_base_min_rpm(rpm: float) -> void:
	base_min_rpm = rpm
	_recalc_thresholds()

func _recalc_thresholds() -> void:
	engage_rpm = base_min_rpm + clutch_engage_rpm_delta
	disengage_rpm = base_min_rpm + clutch_disengage_rpm_delta
	braking_rpm = base_min_rpm + clutch_braking_rpm_delta

## Возвращает общее передаточное отношение (учёт передачи и главной пары). Для нейтрали возвращает 0.
func get_total_ratio() -> float:
	if current_gear_state == GearState.NEUTRAL:
		return 0.0
	var ratio: float
	if current_gear_state == GearState.REVERSE:
		ratio = reverse_ratio
	elif current_gear_state >= 0 and current_gear_state < forward_ratios.size():
		ratio = forward_ratios[current_gear_state]
	else:
		return 0.0
	return ratio * final_drive

## Переключить вверх (R -> N -> 1 -> 2 -> ...)
func gear_up() -> void:
	if shifting:
		return
	match current_gear_state:
		GearState.REVERSE:
			current_gear_state = GearState.NEUTRAL
		GearState.NEUTRAL:
			if forward_ratios.size() > 0:
				current_gear_state = 0   # 1-я передача
		_:
			if current_gear_state < forward_ratios.size() - 1:
				current_gear_state += 1
	_start_shift()

## Переключить вниз (... -> 2 -> 1 -> N -> R)
func gear_down() -> void:
	if shifting:
		return
	match current_gear_state:
		GearState.REVERSE:
			return   # уже на самой нижней
		GearState.NEUTRAL:
			current_gear_state = GearState.REVERSE
		_:
			if current_gear_state > 0:
				current_gear_state -= 1
			else:   # была 1-я передача -> N
				current_gear_state = GearState.NEUTRAL
	_start_shift()

## Принудительно установить конкретную передачу (используется автоматикой)
func set_gear_state(new_state: int) -> void:
	if new_state == current_gear_state:
		return
	if new_state < GearState.REVERSE or (new_state >= forward_ratios.size() and new_state >= 0):
		return
	current_gear_state = new_state
	_start_shift()

func _start_shift() -> void:
	shifting = true
	clutch_engaged = false
	GuiData.set_str_value("gear", get_gear_display())
	await get_tree().create_timer(shift_duration).timeout
	shifting = false

func set_manual_clutch(active: bool) -> void:
	manual_clutch = active

func is_clutch_engaged() -> bool:
	return clutch_engaged

## Обновляет состояние сцепления. В нейтрали сцепление всегда выключено.
func update_clutch(engine_rpm: float, throttle: float) -> void:
	if manual_clutch or shifting or current_gear_state == GearState.NEUTRAL:
		clutch_engaged = false
		return
	if throttle < 0.1:
		if engine_rpm < braking_rpm:
			clutch_engaged = false
			return
	clutch_engaged = (engine_rpm >= engage_rpm)
	if engine_rpm < disengage_rpm:
		clutch_engaged = false

## Строковое представление передачи для UI.
func get_gear_display() -> String:
	match current_gear_state:
		GearState.REVERSE: return "R"
		GearState.NEUTRAL: return "N"
		_: return str(current_gear_state + 1)


## Возвращает общее передаточное отношение для заданного состояния передачи (без учёта нейтрали).
func get_total_ratio_for_state(state: int) -> float:
	if state == GearState.NEUTRAL:
		return 0.0
	var ratio: float
	if state == GearState.REVERSE:
		ratio = reverse_ratio
	elif state >= 0 and state < forward_ratios.size():
		ratio = forward_ratios[state]
	else:
		return 0.0
	return ratio * final_drive
