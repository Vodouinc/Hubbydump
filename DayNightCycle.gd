extends Node

@export var full_cycle_seconds: float = 240.0
@export_range(0.0, 1.0) var starting_time: float = 0.28

@onready var canvas_modulate: CanvasModulate = $CanvasModulate

var time_of_day: float = 0.0

func _ready() -> void:
	time_of_day = starting_time

func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / full_cycle_seconds, 1.0)
	_apply_lighting()

func _apply_lighting() -> void:
	# Noon is at 0.25; the sun falls below the horizon after 0.5.
	var sun_height = maxf(0.0, sin(time_of_day * TAU))
	var daylight = smoothstep(0.0, 0.18, sun_height)

	# East-west azimuth with a slight groundward Y so casts read as lying on the sand.
	var azimuth = Vector2(cos(time_of_day * TAU), sin(time_of_day * TAU) * 0.38)
	if azimuth.length_squared() < 0.0001:
		azimuth = Vector2.RIGHT
	var shadow_dir = -azimuth.normalized()

	# Long at dawn/dusk, short at noon, none at night (contact blob only).
	var low_sun = 1.0 - sun_height
	var shadow_length = lerpf(7.0, 44.0, low_sun) * daylight

	get_tree().call_group("dynamic_shadows", "set_sun_state", shadow_dir, shadow_length, daylight)

	if canvas_modulate:
		var night_color = Color(0.24, 0.31, 0.48)
		var day_color = Color(1.0, 0.92, 0.78)
		canvas_modulate.color = night_color.lerp(day_color, daylight)
