class_name CarPogo
extends RigidBody3D

# ------------------------ Общие настройки ------------------------
@export_file("*.json") var replay_path: String = ""

# ------------------------ Режим коробки передач ------------------------
enum TransmissionMode { MANUAL, AUTOMATIC }
## Ручное (MANUAL) или автоматическое (AUTOMATIC) переключение передач.
@export_enum("Manual", "Automatic") var transmission_mode: int = TransmissionMode.AUTOMATIC

# ------------------------ Автоматическое направление ------------------------
@export var auto_direction_enabled: bool = true
@export var direction_deadzone: float = 0.5        # м/с, зона нечувствительности продольной скорости

# ------------------------ Параметры автоматической трансмиссии ------------------------
## Обороты (RPM) до красной зоны, при которых происходит повышение передачи.
@export var redline_rpm_delta: float = 400.0
## Запас по оборотам (RPM) при понижении: если обороты на низшей передаче превысят redline + этот запас, понижение запрещено.
@export var downshift_redline_margin: float = -1000.0
## Пороговое отношение моментов на колёсах (низшая / текущая) для активации понижения. 1.0 – понижаем, как только момент становится выше.
@export var downshift_torque_ratio: float = 1.1

# ------------------------ Рулевое управление ------------------------
@export_group("Steering")
@export var max_steer_angle: float = 45.0
@export var load_transfer_factor: float = 2.0
@export var speed_threshold: float = 30.0

# ------------------------ Трансмиссия ------------------------
@export_group("Drivetrain")
@export var axle_friction: float = 0.0
@export var axle_friction_extra: float = 10.0
@export var axle_friction_moment: float = 0.0

# ссылки на компоненты
@onready var engine: EnginePogo = $Engine
@onready var chassis: ChassisPogo = $Chassis
@onready var transmission: TransmissionPogo = $Transmission
@onready var brake: BrakePogo = $Brakes

var input_agent: InputAgent
var drive_axle_omega: float = 0.0
var _clutch_was_engaged: bool = false
var _just_engaged: bool = false
var high_stress: bool = false
var airborne: bool = false
var actual_steer: float

const ROLL_STIFFNESS: float = 5000.0

func _ready() -> void:
	if replay_path:
		input_agent = ReplayAgent.new()
		input_agent.replay_path = replay_path
	else:
		input_agent = PlayerAgent.new()
	get_tree().root.add_child.call_deferred(input_agent)
	get_tree().root.move_child.call_deferred(input_agent, 0)
	input_agent.start()
	
	if inertia.is_zero_approx():
		inertia = Lib.calculate_aabb_inertia(self)
	
	chassis.set_car(self)
	transmission.set_base_min_rpm(engine.min_rpm)
	if transmission_mode == TransmissionMode.AUTOMATIC:
		transmission.gear_up()
	_create_bumpers()

func _create_bumpers() -> void:
	var wheels := chassis.get_all_wheels()
	for w in wheels:
		var col_shape := CollisionShape3D.new()
		col_shape.name = "Bumper_" + w.name
		var sphere := SphereShape3D.new()
		sphere.radius = w.wheel_radius * 0.8
		col_shape.shape = sphere
		col_shape.position = w.position
		col_shape.position.z *= 0.85
		add_child(col_shape)

func get_point_velocity(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - to_global(center_of_mass))

func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("reset"):
		apply_central_force(global_basis.y * 30000)

	var raw_throttle = input_agent.get_strength(Lib.InputType.THROTTLE)
	var raw_brake = input_agent.get_strength(Lib.InputType.BRAKE)
	var clutch_input = input_agent.get_strength(Lib.InputType.CLUTCH)
	var steer_input = input_agent.get_strength(Lib.InputType.STEER)

	# Управление передачами (ручное)
	if input_agent.get_strength(Lib.InputType.GEAR_UP) > 0.0:
		transmission.gear_up()
		#GuiData.set_str_value("gear", transmission.get_gear_display())
	if input_agent.get_strength(Lib.InputType.GEAR_DOWN) > 0.0:
		transmission.gear_down()
		#GuiData.set_str_value("gear", transmission.get_gear_display())
	transmission.set_manual_clutch(clutch_input > 0.5)

	# Автоматическое переключение (если включено)
	var long_speed = linear_velocity.dot(global_basis.x)
	if transmission_mode == TransmissionMode.AUTOMATIC and not transmission.manual_clutch:
		if transmission.current_gear_state >= 0:  # Передние передачи или нейтраль
			# Если стоим/медленно движемся вперёд и нажат тормоз – включаем заднюю
			if long_speed < direction_deadzone and raw_brake > 0.0 and raw_throttle == 0.0:
				transmission.set_gear_state(TransmissionPogo.GearState.REVERSE)
		elif transmission.current_gear_state == TransmissionPogo.GearState.REVERSE:
			# Если на задней и нажат газ (throttle) при очень малой скорости назад – возвращаемся на D
			if long_speed > -direction_deadzone and raw_throttle > 0.0 and raw_brake == 0.0:
				transmission.set_gear_state(0)  # Первая передача

	# Инверсия педалей, если включена задняя передача (и в автомате, и в ручном режиме)
	var throttle: float
	var brake_input: float
	if transmission.current_gear_state == TransmissionPogo.GearState.REVERSE \
			and transmission_mode == TransmissionMode.AUTOMATIC:
		throttle = raw_brake
		brake_input = raw_throttle
	else:
		throttle = raw_throttle
		brake_input = raw_brake

	# Автоматическое переключение передних передач
	if transmission_mode == TransmissionMode.AUTOMATIC and not transmission.manual_clutch:
		_auto_shift_gears()

	var old_engine_omega = engine.get_omega()
	var engine_rpm = Lib.omega_to_rpm(old_engine_omega)
	GuiData.set_value("engine_rpm", engine_rpm)
	GuiData.set_value("speed", Lib.ms_to_kmh(linear_velocity.dot(global_basis.x)))
	transmission.update_clutch(engine_rpm, throttle)
	var engaged = transmission.is_clutch_engaged()

	if engaged and not _clutch_was_engaged:
		_engage_clutch_conserving_momentum(old_engine_omega)
		_just_engaged = true
	_clutch_was_engaged = engaged

	if engaged and not _just_engaged:
		engine.set_omega(drive_axle_omega * transmission.get_total_ratio())

	var engine_torque = engine.get_torque(delta, throttle, not engaged)  * 2

	var steering_angle = _compute_steering_angle(steer_input)
	var brake_torques = _apply_wheel_physics(delta, brake_input, steering_angle)
	
	apply_anti_roll()
	GuiData.set_value("y_stress", 1 if high_stress else 0)
	if not engaged and _should_lock_drive_axle(brake_input, brake_torques):
		drive_axle_omega = 0.0
	else:
		_update_drive_axle(delta, engine_torque, brake_torques, engaged, brake_input)

	_just_engaged = false


func _auto_shift_gears() -> void:
	var gear_idx = transmission.current_gear_state
	if gear_idx < 0:
		return
	var max_gear = transmission.forward_ratios.size() - 1
	if gear_idx > max_gear:
		return

	var long_speed = linear_velocity.dot(global_basis.x)
	var wheel_radius = chassis.wheel_radius
	var wheel_omega = long_speed / wheel_radius
	var current_ratio = transmission.get_total_ratio()
	var current_engine_omega = wheel_omega * current_ratio
	var current_rpm = Lib.omega_to_rpm(current_engine_omega)
	var redline = engine.get_engine_redline()

	# Повышение передачи: только при упоре в отсечку
	if gear_idx < max_gear:
		if current_rpm >= redline - redline_rpm_delta:
			transmission.gear_up()
			return

	# Понижение передачи: сравниваем момент на колёсах
	if gear_idx > 0:
		var lower_gear_state = gear_idx - 1
		var lower_ratio = transmission.get_total_ratio_for_state(lower_gear_state)
		var lower_engine_omega = wheel_omega * lower_ratio
		var lower_rpm = Lib.omega_to_rpm(lower_engine_omega)

		# Проверяем, что на пониженной передаче обороты не улетят выше redline + запас
		if lower_rpm > redline + downshift_redline_margin:
			return

		var torque_curve = engine.torque_curve
		if torque_curve:
			var engine_torque_current = torque_curve.sample(current_rpm)
			var wheel_torque_current = engine_torque_current * abs(current_ratio)
			var engine_torque_lower = torque_curve.sample(lower_rpm)
			var wheel_torque_lower = engine_torque_lower * abs(lower_ratio)

			if wheel_torque_lower > wheel_torque_current * downshift_torque_ratio:
				transmission.gear_down()
				return

func apply_anti_roll() -> void:
	var wheels: Array[SuspensionPogo] = chassis.get_all_wheels()
	_apply_axle_anti_roll(wheels[0], wheels[1], ROLL_STIFFNESS)
	_apply_axle_anti_roll(wheels[2], wheels[3], ROLL_STIFFNESS)

func _apply_axle_anti_roll(left: SuspensionPogo, right: SuspensionPogo, stiffness: float) -> void:
	if not left.raycast.is_colliding() or not right.raycast.is_colliding():
		return
	var left_comp = left.get_compression()
	var right_comp = right.get_compression()
	var diff = left_comp - right_comp
	var track_width = abs(right.global_position.x - left.global_position.x)
	if track_width < 0.01:
		return
	var roll_angle = atan(diff / track_width)
	var roll_torque = roll_angle * stiffness * global_transform.basis.x
	apply_torque(roll_torque)

func _compute_steering_angle(steer_input: float) -> float:
	var speed = linear_velocity.length()
	var speed_factor = 1.0 / (1.0 + speed / speed_threshold)
	var max_rad_current = deg_to_rad(max_steer_angle) * speed_factor * speed_factor
	var base_angle = max_rad_current * steer_input

	var front_load = 0.0
	var static_load_front = 0.0
	for w in chassis.get_all_wheels():
		if w.is_steer:
			front_load += w.get_last_upwards_force()
			static_load_front += w.get_static_load()
	
	var absolute_max = deg_to_rad(max_steer_angle * 1.5)
	var enhanced_max = max_rad_current

	if not high_stress:
		if static_load_front > 0.0:
			var load_ratio = front_load / static_load_front
			enhanced_max = max_rad_current * (1.0 + load_transfer_factor * (load_ratio - 1.0))
			enhanced_max = clamp(enhanced_max, 0.0, absolute_max)
	else:
		enhanced_max = clamp(enhanced_max, 0.0, absolute_max)

	base_angle = clamp(base_angle, -enhanced_max, enhanced_max)
	if abs(base_angle) > abs(actual_steer):
		actual_steer = move_toward(actual_steer, base_angle, 0.016)
	else:
		actual_steer = base_angle
	return actual_steer

func _should_lock_drive_axle(brake_input: float, brake_torques: Array[float]) -> bool:
	if brake_input <= 0.0 or abs(drive_axle_omega) >= chassis.static_omega_threshold:
		return false
	var total_brake = 0.0
	var total_tire_torque = 0.0
	for w in chassis.get_drive_wheels():
		var idx = chassis.get_all_wheels().find(w)
		if idx != -1:
			total_brake += brake_torques[idx]
		total_tire_torque += abs(w.get_last_Fx() * w.get_wheel_radius())
	return total_brake >= total_tire_torque

func _engage_clutch_conserving_momentum(old_engine_omega: float) -> void:
	var ratio = transmission.get_total_ratio()
	var wheels_inertia = _sum_wheels_inertia()
	var reflected_inertia = engine.moment_of_inertia * ratio * ratio
	var total_inertia = wheels_inertia + reflected_inertia
	var new_axle_omega = (engine.moment_of_inertia * old_engine_omega \
			* ratio + wheels_inertia * drive_axle_omega) / total_inertia
	drive_axle_omega = new_axle_omega
	engine.set_omega(drive_axle_omega * ratio)

func _sum_wheels_inertia() -> float:
	var total = 0.0
	for w in chassis.get_drive_wheels():
		total += w.wheel_inertia
	return total

func _apply_wheel_physics(delta: float, brake_input: float, steer_angle: float) -> Array[float]:
	var brake_torques: Array[float] = []
	for w in chassis.get_all_wheels():
		brake_torques.append(brake.get_brake_torque(brake_input))
	chassis.simulate_suspension_and_tires(
		delta, drive_axle_omega, brake_torques, steer_angle,
		input_agent.get_strength(Lib.InputType.STEER),
	)
	if high_stress and not airborne:
		var vertical_vel = linear_velocity.dot(Vector3.UP)
		if vertical_vel < 0.0:
			apply_central_impulse(Vector3.UP * mass * abs(vertical_vel) * 0.0)
	return brake_torques

func _update_drive_axle(delta: float, engine_torque: float,
		brake_torques: Array[float], engaged: bool, brake_input: float) -> void:
	var resist_torque = _compute_drive_axle_resist_torque(brake_torques)
	var wheels_inertia = _sum_wheels_inertia()
	
	var axle_friction_torque = axle_friction * drive_axle_omega
	
	var net_torque = -resist_torque - axle_friction_torque
	if engaged:
		net_torque += engine_torque * transmission.get_total_ratio()

	var new_omega = drive_axle_omega + net_torque * delta / wheels_inertia
	if not engaged and brake_input <= 0.0:
		axle_friction_torque += axle_friction_extra * drive_axle_omega + axle_friction_moment
		new_omega = drive_axle_omega + (-resist_torque - axle_friction_torque) * delta / wheels_inertia
	if not engaged and brake_input > 0.0 and drive_axle_omega * new_omega < 0.0:
		var total_brake = 0.0
		for i in chassis.get_all_wheels().size():
			if chassis.get_all_wheels()[i].is_drive:
				total_brake += brake_torques[i]
		var tire_torque = 0.0
		for w in chassis.get_drive_wheels():
			tire_torque += abs(w.get_last_Fx() * w.get_wheel_radius())
		if total_brake >= tire_torque:
			new_omega = 0.0
	drive_axle_omega = new_omega

func _compute_drive_axle_resist_torque(brake_torques: Array[float]) -> float:
	var total = 0.0
	var all = chassis.get_all_wheels()
	for i in all.size():
		var w = all[i]
		if w.is_drive:
			total += w.get_last_Fx() * w.get_wheel_radius()
			total += sign(drive_axle_omega) * brake_torques[i]
	return total
