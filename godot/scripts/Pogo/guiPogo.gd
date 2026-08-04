extends Control

@onready var label: Label = $MarginContainer/HBoxContainer/Label
@onready var monitor_2: Particle1DMonitor = $Monitor2

func _ready() -> void:
	$Monitor2.configure(
		{
			"y_min": -60000, "y_max": 60000,
			"window_duration": 3.0,
			"title": "fx",
			"series": [
				{
					"y_key": "raw_fx",
					"color": Color.CORAL, "size": 1.0,
					"solid_time": 0.3, "fade_time": 1.2,
					"trail_mode": 1, "trail_width" : 2,
				},
				{
					"y_key": "smooth_fx",
					"color": Color.CRIMSON, "size": 1.0,
					"solid_time": 0.3, "fade_time": 1.2,
					"trail_mode": 1, "trail_width" : 3,
				},
			],
			#"h_lines": {0.0: "0", -1.0: "-1.0", 1.0: "1.0"},
			"v_lines": {0.0: "0", 1.0: "1", 2.0: "2"},
			"use_particles": true,
		}
	)
	$Monitor3.configure(
		{
			"y_min": -60000, "y_max": 60000,
			"window_duration": 3.0,
			"title": "fy",
			"series": [
				{
					"y_key": "raw_fy",
					"color": Color.CORAL, "size": 1.0,
					"solid_time": 0.3, "fade_time": 1.2,
					"trail_mode": 1, "trail_width" : 2,
				},
				{
					"y_key": "smooth_fy",
					"color": Color.CRIMSON, "size": 1.0,
					"solid_time": 0.3, "fade_time": 1.2,
					"trail_mode": 1, "trail_width" : 3,
				},
			],
			#"h_lines": {0.0: "0", -1.0: "-1.0", 1.0: "1.0"},
			"v_lines": {0.0: "0", 1.0: "1", 2.0: "2"},
			"use_particles": true,
		}
	)


func _process(_delta: float) -> void:
	var speed = GuiData.get_value("speed", 0)
	var gear = GuiData.get_str_value("gear", "N")
	var rpm = GuiData.get_value("engine_rpm", 0)
	label.text = "G: %s, RPM: %5.0f, Speed: %3.0f" % [gear, rpm, speed]
