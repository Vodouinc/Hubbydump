extends Node

@export var full_cycle_seconds: float = 240.0
@export_range(0.0, 1.0) var starting_time: float = 0.28

@onready var canvas_modulate: CanvasModulate = $CanvasModulate

var time_of_day: float = 0.0
var shadow_update_accumulator: float = 0.0
const SHADOW_UPDATE_INTERVAL: float = 0.15 # 6-7 updates/sec is plenty for shadows

func _ready() -> void:
	time_of_day = starting_time
	_apply_lighting(true)

func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / full_cycle_seconds, 1.0)
	shadow_update_accumulator += delta
	if shadow_update_accumulator >= SHADOW_UPDATE_INTERVAL:
		shadow_update_accumulator = 0.0
		_apply_lighting(false)

func _apply_lighting(force: bool = false) -> void:
	var sun_height = maxf(0.0, sin(time_of_day * TAU))
	var daylight = smoothstep(0.0, 0.18, sun_height)

	var azimuth = Vector2(cos(time_of_day * TAU), sin(time_of_day * TAU) * 0.38)
	if azimuth.length_squared() < 0.0001:
		azimuth = Vector2.RIGHT
	var shadow_dir = -azimuth.normalized()

	var low_sun = 1.0 - sun_height
	var shadow_length = lerpf(7.0, 44.0, low_sun) * daylight

	get_tree().call_group("dynamic_shadows", "set_sun_state", shadow_dir, shadow_length, daylight)

	if canvas_modulate:
		var night_color = Color(0.24, 0.31, 0.48)
		var day_color = Color(1.0, 0.92, 0.78)
		canvas_modulate.color = night_color.lerp(day_color, daylight)
