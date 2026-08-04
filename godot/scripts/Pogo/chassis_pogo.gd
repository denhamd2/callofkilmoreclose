class_name ChassisPogo
extends Node3D

# ------------------------ Общие параметры колёс ------------------------
@export_group("Wheel Common")
@export var wheel_radius: float = 0.335
@export var wheel_inertia: float = 10.0
@export var rest_length: float = 0.15
@export var stiffness: float = 60000.0
@export var damping_compression: float = 4000.0
@export var damping_relaxation: float = 4400.0
@export var static_load: float = 384.0
@export var max_load_factor: float = 1.5
@export var static_omega_threshold: float = 0.5
@export var slip_velocity_low: float = 1.0
@export var bump_stop_curve: Curve
@export var use_tahn_lateral: bool = true
## При модуле скорости контакта (м/с) ниже этого значения поперечная сила обнуляется.
@export var lateral_disable_threshold: float = 0.25

# ------------------------ Передняя ось ------------------------
@export_group("Front Axle")
@export var front_mu_peak: float = 1.8
@export var front_load_power: float = 1.0
#@export var front_activation_speed: float = 0.05
#@export var front_speed_ramp_threshold: float = 0.3
@export var front_brake_activation_speed: float = 0.01
@export var front_traction_curve: Curve
@export var front_drift_factor_curve: Curve
@export var front_drift_angle_curve: Curve
@export var front_lateral_atan_angle_deg: float = 5.0
@export var front_lateral_vchar: float = 0.3

# ------------------------ Задняя ось ------------------------
@export_group("Rear Axle")
@export var rear_mu_peak: float = 1.8
@export var rear_lateral_vchar: float = 0.3
@export var rear_slip_threshold: float = 0.3
@export var rear_load_power: float = 1.0
@export var rear_traction_curve: Curve
@export var rear_sliding_friction: float = 2.0
@export var rear_slip_factor_falloff: float = 0.8
@export var rear_slip_cutoff_threshold: float = 0.1
@export var rear_slip_response_rate: float = 8.0
@export var rear_lateral_falloff_curve: Curve
@export var rear_lateral_falloff_speed_curve: Curve
@export var rear_lateral_atan_angle_deg: float = 5.0

# ------------------------ Привязка колёс ------------------------
@export var drive_wheel_paths: Array[NodePath] = []
@export var steer_wheel_paths: Array[NodePath] = []

var _drive_wheels: Array[SuspensionPogo] = []
var _all_wheels: Array[SuspensionPogo] = []
var car: CarPogo

func set_car(c: CarPogo) -> void:
	car = c

func _ready() -> void:
	for child in get_children():
		if child is SuspensionPogo:
			_all_wheels.append(child)

	for path in drive_wheel_paths:
		var node = get_node(path)
		if node is SuspensionPogo and node not in _drive_wheels:
			_drive_wheels.append(node)

	var steer_wheels: Array[SuspensionPogo] = []
	for path in steer_wheel_paths:
		var node = get_node(path)
		if node is SuspensionPogo:
			steer_wheels.append(node)

	# Конфигурируем каждое колесо
	for w in _all_wheels:
		var config: Dictionary = {
			wheel_radius = wheel_radius,
			wheel_inertia = wheel_inertia,
			rest_length = rest_length,
			stiffness = stiffness,
			damping_compression = damping_compression,
			damping_relaxation = damping_relaxation,
			static_load = static_load,
			static_omega_threshold = static_omega_threshold,
			slip_velocity_low = slip_velocity_low,
			max_load_factor = max_load_factor,
			is_drive = w in _drive_wheels,
			is_steer = w in steer_wheels,
			lateral_disable_threshold = lateral_disable_threshold,
		}

		if config.is_steer:
			config["mu_peak"] = front_mu_peak
			config["load_power"] = front_load_power
			#config["activation_speed"] = front_activation_speed
			#config["speed_ramp_threshold"] = front_speed_ramp_threshold
			config["brake_activation_speed"] = front_brake_activation_speed
			config["traction_curve"] = front_traction_curve
			config["slip_threshold"] = 0.0
			config["sliding_friction"] = 0.0
			config["lateral_vchar"] = 0.0
			config["slip_factor_falloff"] = 0.0
			config["front_drift_factor_curve"] = front_drift_factor_curve
			config["front_drift_angle_curve"] = front_drift_angle_curve
			config["lateral_falloff_speed_curve"] = rear_lateral_falloff_speed_curve
			config["bump_stop_curve"] = bump_stop_curve
			config["use_tanh_lateral"] = use_tahn_lateral
			config["lateral_atan_angle_deg"] = front_lateral_atan_angle_deg
			config["lateral_vchar"] = front_lateral_vchar
		else:
			config["mu_peak"] = rear_mu_peak
			config["load_power"] = rear_load_power
			config["activation_speed"] = 0.0
			config["speed_ramp_threshold"] = 0.0
			config["brake_activation_speed"] = 0.0
			config["traction_curve"] = rear_traction_curve
			config["slip_threshold"] = rear_slip_threshold
			config["sliding_friction"] = rear_sliding_friction
			config["lateral_vchar"] = rear_lateral_vchar
			config["slip_factor_falloff"] = rear_slip_factor_falloff
			config["slip_cutoff_threshold"] = rear_slip_cutoff_threshold
			config["slip_response_rate"] = rear_slip_response_rate
			config["lateral_falloff_curve"] = rear_lateral_falloff_curve
			config["lateral_falloff_speed_curve"] = rear_lateral_falloff_speed_curve
			config["bump_stop_curve"] = bump_stop_curve
			config["use_tanh_lateral"] = use_tahn_lateral
			config["lateral_atan_angle_deg"] = rear_lateral_atan_angle_deg
			config["lateral_vchar"] = rear_lateral_vchar
		
		w.configure(config)

func get_drive_wheels() -> Array[SuspensionPogo]:
	return _drive_wheels

func get_all_wheels() -> Array[SuspensionPogo]:
	return _all_wheels

## Основной симуляционный проход: подвеска, продольные и поперечные силы.
func simulate_suspension_and_tires(
		delta: float, drive_axle_omega: float,
		brake_torques: Array[float], steer_angle: float,
		steer_input: float) -> void:
	
	car.high_stress = false
	car.airborne = false
	for sus in _all_wheels:
		sus.is_freaking(car)
	
	# Задние колёса (ведущие)
	var rear_slip_angles: Array[float] = []
	for w in _drive_wheels:
		var idx = _all_wheels.find(w)
		if idx != -1:
			w.process_physics(delta, drive_axle_omega, brake_torques[idx], steer_angle, steer_input, car)
			var Vx = abs(w.get_last_Vx())
			var Vy = w.get_last_Vy()
			if Vx > 0.01:
				rear_slip_angles.append(rad_to_deg(atan2(Vy, Vx)))
				GuiData.set_value("rear_slip", rad_to_deg(atan2(Vy, Vx)))
	
	var avg_slip_angle: float = 0.0
	if rear_slip_angles.size() > 0:
		var sum = 0.0
		for ang in rear_slip_angles:
			sum += ang
		avg_slip_angle = sum / rear_slip_angles.size()
	
	var car_speed_kmh = Lib.ms_to_kmh(car.linear_velocity.length())
	
	# Передние колёса (управляемые)
	for i in range(_all_wheels.size()):
		var w = _all_wheels[i]
		if w.is_steer:
			w.process_physics(delta, drive_axle_omega, brake_torques[i], steer_angle, steer_input,
				car, avg_slip_angle, car_speed_kmh)
