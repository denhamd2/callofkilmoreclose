class_name EnginePogo
extends Node

## Кривая крутящего момента двигателя (Н·м) от оборотов (RPM).
@export var torque_curve: Curve
## Минимальные обороты холостого хода (RPM). Ниже – двигатель глохнет или включается авто-газ.
@export var min_rpm: float = 1000.0
## Момент инерции двигателя (кг·м²). Больше – медленнее раскручивается, плавнее реакция на газ.
@export var moment_of_inertia: float = 0.1
## Коэффициент вязкого трения в двигателе. Больше – сильнее внутреннее сопротивление, падает мощность.
@export var friction_coefficient: float = 0.1
## Тормозной момент двигателя при закрытом дросселе (Н·м). Больше – сильнее замедление при сбросе газа.
@export var engine_brake_torque: float = 2.0

var max_omega: float
var omega: float = 0.0
var peak_torque_rpm: float = 0.0

func _ready() -> void:
	if torque_curve:
		max_omega = Lib.rpm_to_omega(torque_curve.max_domain)
		# Поиск RPM с максимальным крутящим моментом
		var best_rpm = 0.0
		var best_torque = -INF
		var step = 100.0
		var rpm = min_rpm
		while rpm <= torque_curve.max_domain:
			var t = torque_curve.sample(rpm)
			if t > best_torque:
				best_torque = t
				best_rpm = rpm
			rpm += step
		peak_torque_rpm = best_rpm
	else:
		max_omega = 1000.0

func get_engine_redline() -> float:
	return torque_curve.max_domain if torque_curve else 0.0

func set_omega(value: float) -> void:
	omega = clamp(value, 0.0, max_omega)

func get_omega() -> float:
	return omega

func get_torque(delta: float, throttle: float, is_free: bool) -> float:
	var rpm = Lib.omega_to_rpm(omega)
	if rpm >= torque_curve.max_domain:
		throttle = 0.0
	if is_free and rpm < min_rpm:
		throttle = max(throttle, 1.0)
	var sample_rpm = clamp(rpm, 0.0, torque_curve.max_domain)
	var raw_torque = torque_curve.sample(sample_rpm) * throttle
	raw_torque -= engine_brake_torque * (1.0 - throttle)
	var friction_torque = friction_coefficient * omega
	var net_torque = raw_torque - friction_torque
	if is_free:
		omega += net_torque * delta / moment_of_inertia
		omega = clamp(omega, 0.0, max_omega)
	return net_torque
