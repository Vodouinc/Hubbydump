@tool
extends Node2D

@export var cog_radius: float = 7.0
@export var tooth_count: int = 6

var iron_color: Color = Color(0.2, 0.22, 0.25)
var brass_color: Color = Color(0.85, 0.6, 0.2)
var energy_glow: Color = Color(0.1, 0.9, 0.9, 0.9)

func _ready() -> void:
	queue_redraw()

func _process(delta: float) -> void:
	# Hardware transform rotation avoids recalculating 6 teeth polygons every frame on CPU
	rotation += delta * 1.5

func _draw() -> void:
	for i in range(tooth_count):
		var angle = i * (TAU / float(tooth_count))
		var tooth_dir = Vector2.RIGHT.rotated(angle)
		var tooth_pos = tooth_dir * (cog_radius + 1.0)
		var points = PackedVector2Array([
			tooth_pos + tooth_dir.rotated(PI/2) * 2.0,
			tooth_pos - tooth_dir.rotated(PI/2) * 2.0,
			tooth_pos + tooth_dir * 3.0 - tooth_dir.rotated(PI/2) * 1.5,
			tooth_pos + tooth_dir * 3.0 + tooth_dir.rotated(PI/2) * 1.5,
		])
		draw_primitive(points, [brass_color, brass_color, brass_color, brass_color], PackedVector2Array())

	draw_circle(Vector2.ZERO, cog_radius, iron_color)
	draw_arc(Vector2.ZERO, cog_radius, 0, TAU, 16, brass_color, 1.2)
	draw_circle(Vector2.ZERO, cog_radius * 0.55, Color(0.08, 0.08, 0.1))
	draw_circle(Vector2.ZERO, 3.5, Color(energy_glow.r, energy_glow.g, energy_glow.b, 0.3))
	draw_circle(Vector2.ZERO, 2.0, energy_glow)
