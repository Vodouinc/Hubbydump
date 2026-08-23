extends Node

@export var full_cycle_seconds: float = 240.0
@export_range(0.0, 1.0) var starting_time: float = 0.35 # Starts in bright morning

@onready var canvas_modulate: CanvasModulate = $CanvasModulate

var time_of_day: float = 0.0
var shadow_update_accumulator: float = 0.0
const SHADOW_UPDATE_INTERVAL: float = 0.05

# 4-Phase Palette Keyframes
const C_NIGHT := Color(0.18, 0.20, 0.28) # Deep Rad-Indigo Night
const C_DAWN  := Color(0.88, 0.62, 0.45) # Golden Martian Dust Sunrise
const C_DAY   := Color(1.00, 0.96, 0.90) # Harsh Sunlit Desert Noon
const C_DUSK  := Color(0.72, 0.32, 0.40) # Crimson-Purple Martian Twilight

func _ready() -> void:
	time_of_day = starting_time
	_apply_lighting(true)

func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / full_cycle_seconds, 1.0)
	
	# Smoothly update ambient atmospheric color every frame
	if canvas_modulate:
		canvas_modulate.color = _evaluate_ambient_color(time_of_day)

	# Update dynamic cast shadows on a timed interval for performance
	shadow_update_accumulator += delta
	if shadow_update_accumulator >= SHADOW_UPDATE_INTERVAL:
		shadow_update_accumulator = 0.0
		_apply_lighting(false)

func _apply_lighting(_force: bool = false) -> void:
	# 1. Sun Elevation (-1.0 at Midnight, 0.0 at Sunrise/Sunset, +1.0 at High Noon)
	var sun_height = -cos(time_of_day * TAU)
	
	# Smooth daylight factor between horizon [-0.15] and full morning [0.35]
	var daylight = clampf(smoothstep(-0.15, 0.35, sun_height), 0.0, 1.0)

	# 2. Solar Azimuth (Sun rises in East [+X], travels overhead, sets in West [-X])
	var sun_dir = Vector2(-sin(time_of_day * TAU), -cos(time_of_day * TAU) * 0.5)
	if sun_dir.length_squared() < 0.0001:
		sun_dir = Vector2.DOWN
	var shadow_dir = -sun_dir.normalized()
	
	# Long shadows at dawn/dusk, tight short shadows at noon
	var shadow_length = lerpf(8.0, 46.0, 1.0 - maxf(0.0, sun_height)) * daylight

	get_tree().call_group("dynamic_shadows", "set_sun_state", shadow_dir, shadow_length, daylight)
	get_tree().call_group("dynamic_lights", "set_daylight_factor", daylight)

## Smooth, seamless 24-hour color interpolation across all 6 time slices
func _evaluate_ambient_color(t: float) -> Color:
	if t < 0.20:
		# Deep Night (00:00 -> 04:48)
		return C_NIGHT
	elif t < 0.30:
		# Night into Dawn Sunrise (04:48 -> 07:12)
		var blend = (t - 0.20) / 0.10
		return C_NIGHT.lerp(C_DAWN, blend)
	elif t < 0.45:
		# Dawn into Full Day (07:12 -> 10:48)
		var blend = (t - 0.30) / 0.15
		return C_DAWN.lerp(C_DAY, blend)
	elif t < 0.65:
		# High Noon & Bright Afternoon (10:48 -> 15:36)
		return C_DAY
	elif t < 0.78:
		# Afternoon into Crimson Twilight (15:36 -> 18:43)
		var blend = (t - 0.65) / 0.13
		return C_DAY.lerp(C_DUSK, blend)
	elif t < 0.90:
		# Dusk into Deep Night (18:43 -> 21:36)
		var blend = (t - 0.78) / 0.12
		return C_DUSK.lerp(C_NIGHT, blend)
	else:
		# Late Night (21:36 -> 24:00)
		return C_NIGHT
