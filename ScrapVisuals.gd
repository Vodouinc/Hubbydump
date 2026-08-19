@tool
extends Node2D

@export var cog_radius: float = 7.0
@export var tooth_count: int = 6
@export var float_speed: float = 3.0

# AdMech Palette
var iron_color: Color = Color(0.2, 0.22, 0.25)       # Dark Metal
var brass_color: Color = Color(0.85, 0.6, 0.2)      # Mechanicus Brass
var energy_glow: Color = Color(0.1, 0.9, 0.9, 0.9)   # Cog-Machinery Cyan

var time_passed: float = 0.0

func _process(delta: float) -> void:
	time_passed += delta
	queue_redraw() # Request redraw to animate rotation/glow

func _draw() -> void:
	var rotation_angle = time_passed * 1.5
	
	# 1. Outer Brass Gear Teeth
	for i in range(tooth_count):
		var angle = rotation_angle + (i * (TAU / tooth_count))
		var tooth_dir = Vector2.RIGHT.rotated(angle)
		
		# Draw small tooth rectangles along the circumference
		var tooth_pos = tooth_dir * (cog_radius + 1.0)
		var points = PackedVector2Array([
			tooth_pos + tooth_dir.rotated(PI/2) * 2.0,
			tooth_pos - tooth_dir.rotated(PI/2) * 2.0,
			tooth_pos + tooth_dir * 3.0 - tooth_dir.rotated(PI/2) * 1.5,
			tooth_pos + tooth_dir * 3.0 + tooth_dir.rotated(PI/2) * 1.5,
		])
		draw_primitive(points, [brass_color, brass_color, brass_color, brass_color], PackedVector2Array())

	# 2. Outer Dark Metallic Ring
	draw_circle(Vector2.ZERO, cog_radius, iron_color)
	draw_arc(Vector2.ZERO, cog_radius, 0, TAU, 16, brass_color, 1.2)

	# 3. Inner Mechanism (Recessed Dark Core)
	draw_circle(Vector2.ZERO, cog_radius * 0.55, Color(0.08, 0.08, 0.1))

	# 4. Pulsing Archeotech Energy Core (Pulsing Cyan Plasma)
	var pulse = (sin(time_passed * 4.0) + 1.0) * 0.5
	var core_radius = lerp(1.5, 2.5, pulse)
	
	# Subtle outer aura glow
	draw_circle(Vector2.ZERO, core_radius + 1.5, Color(energy_glow.r, energy_glow.g, energy_glow.b, 0.3 * pulse))
	# Solid center node
	draw_circle(Vector2.ZERO, core_radius, energy_glow)
