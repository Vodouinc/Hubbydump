extends Node

@export var full_cycle_seconds: float = 240.0
@export_range(0.0, 1.0) var starting_time: float = 0.32

@onready var canvas_modulate: CanvasModulate = $CanvasModulate

var time_of_day: float = 0.0
var shadow_update_accumulator: float = 0.0
const SHADOW_UPDATE_INTERVAL: float = 0.10

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
	# Sun altitude & Daylight factor (0.0 = Deep Night, 1.0 = High Noon)
	var sun_height = maxf(0.0, sin(time_of_day * TAU))
	var daylight = smoothstep(0.0, 0.22, sun_height)

	# Sun Azimuth & Dynamic Cast Shadows
	var azimuth = Vector2(cos(time_of_day * TAU), sin(time_of_day * TAU) * 0.45)
	if azimuth.length_squared() < 0.0001:
		azimuth = Vector2.RIGHT
	var shadow_dir = -azimuth.normalized()
	var shadow_length = lerpf(6.0, 42.0, 1.0 - sun_height) * daylight

	get_tree().call_group("dynamic_shadows", "set_sun_state", shadow_dir, shadow_length, daylight)

	# --- 4-PHASE ATMOSPHERIC COLOR GRADING ---
	if canvas_modulate:
		var target_ambient: Color
		var t = time_of_day # 0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset

		if t < 0.20 or t >= 0.85:
			# Deep Rad-Indigo Night (High contrast for plasma & fires)
			target_ambient = Color(0.18, 0.20, 0.28)
		elif t >= 0.20 and t < 0.35:
			# Dawn: Golden Martian Dust Haze
			var blend = (t - 0.20) / 0.15
			target_ambient = Color(0.18, 0.20, 0.28).lerp(Color(0.88, 0.62, 0.45), blend)
		elif t >= 0.35 and t < 0.70:
			# Day: Harsh Sunlit Desert
			var blend = (t - 0.35) / 0.35
			target_ambient = Color(0.88, 0.62, 0.45).lerp(Color(1.0, 0.95, 0.88), blend)
		else:
			# Dusk: Crimson-Purple Martian Twilight
			var blend = (t - 0.70) / 0.15
			target_ambient = Color(1.0, 0.95, 0.88).lerp(Color(0.72, 0.32, 0.40), blend)

		canvas_modulate.color = target_ambient

	# Notify lights of daylight factor (dim in bright sun, blaze at night)
	get_tree().call_group("dynamic_lights", "set_daylight_factor", daylight)
