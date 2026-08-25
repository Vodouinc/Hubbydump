# res://WorldObstacle.gd
extends StaticBody2D
class_name WorldObstacle

enum ObstacleType { MOUNTAIN_CRAG, IRONWOOD_TREE, INDUSTRIAL_RUIN }

@export var obstacle_type: ObstacleType = ObstacleType.MOUNTAIN_CRAG
@export var radius: float = 38.0
var seed_val: float = 0.0

func _ready() -> void:
	add_to_group("world_obstacles")
	seed_val = randf() * 1000.0
	
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = radius * 0.85
	col.shape = shape
	add_child(col)
	queue_redraw()

func _draw() -> void:
	match obstacle_type:
		ObstacleType.MOUNTAIN_CRAG:
			_draw_mountain_crag()
		ObstacleType.IRONWOOD_TREE:
			_draw_ironwood_tree()
		ObstacleType.INDUSTRIAL_RUIN:
			_draw_industrial_ruin()

func _draw_mountain_crag() -> void:
	# Jagged basalt rock crags
	var points: PackedVector2Array = []
	var num_pts = 9
	for i in range(num_pts):
		var angle = (float(i) / float(num_pts)) * TAU
		var offset = (sin(angle * 3.0 + seed_val) + cos(angle * 2.0)) * (radius * 0.22)
		var r = radius + offset
		points.append(Vector2.RIGHT.rotated(angle) * r)
	
	# Rock body + dark highlight ridges
	draw_colored_polygon(points, Color(0.14, 0.12, 0.11))
	draw_polyline(points, Color(0.38, 0.30, 0.24), 2.0, true)
	draw_line(Vector2(-radius * 0.3, -radius * 0.2), Vector2(radius * 0.4, radius * 0.3), Color(0.25, 0.20, 0.17), 2.5)

func _draw_ironwood_tree() -> void:
	# Mechanical / Rust forest canopy
	# Shadow
	draw_circle(Vector2(4, 6), radius * 0.8, Color(0.02, 0.03, 0.04, 0.5))
	# Base trunk
	draw_circle(Vector2.ZERO, radius * 0.35, Color(0.18, 0.14, 0.10))
	# Dense copper/decay foliage
	draw_circle(Vector2(-4, -4), radius * 0.7, Color(0.18, 0.32, 0.20))
	draw_circle(Vector2(5, -2), radius * 0.65, Color(0.24, 0.42, 0.25))
	draw_circle(Vector2(0, 3), radius * 0.6, Color(0.14, 0.26, 0.16))
	# Canopy highlight rim
	draw_arc(Vector2(-2, -2), radius * 0.75, 0, TAU, 16, Color(0.35, 0.55, 0.32, 0.6), 1.5)

func _draw_industrial_ruin() -> void:
	# Concrete / rusted girders
	var rect = Rect2(-radius * 0.9, -radius * 0.6, radius * 1.8, radius * 1.2)
	draw_rect(rect, Color(0.16, 0.17, 0.22))
	draw_rect(rect, Color(0.45, 0.38, 0.25), false, 2.0)
	# Rust crossbar
	draw_line(rect.position, rect.position + rect.size, Color(0.35, 0.25, 0.18), 2.0)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), Color(0.35, 0.25, 0.18), 2.0)
