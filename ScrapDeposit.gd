@tool
extends StaticBody2D

@export var is_occupied: bool = false:
	set(val):
		is_occupied = val
		queue_redraw()

var pulse_time: float = 0.0

func _ready() -> void:
	add_to_group("scrap_deposits")
	z_index = -5
	
	# Compact collision so players can walk over the deposit until built on
	var col = get_node_or_null("CollisionShape2D")
	if not col:
		col = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 16.0
		col.shape = shape
		add_child(col)
	col.disabled = true # Walkable terrain until a Foundry is constructed on it

func _process(delta: float) -> void:
	pulse_time += delta
	if not is_occupied:
		queue_redraw()

func _draw() -> void:
	if is_occupied:
		return # Hidden when a Foundry is sitting on top of it

	var rust_dark = Color(0.18, 0.14, 0.10)
	var rust_mid = Color(0.38, 0.28, 0.16)
	var scrap_brass = Color(0.78, 0.58, 0.22)
	var pulse = 0.6 + sin(pulse_time * 3.5) * 0.35
	var scrap_glow = Color(0.95, 0.75, 0.20, pulse)

	# 1. Ground Fissure / Scrap Vent Crater
	draw_circle(Vector2.ZERO, 24.0, rust_dark)
	draw_circle(Vector2.ZERO, 20.0, Color(0.10, 0.08, 0.06))
	draw_arc(Vector2.ZERO, 24.0, 0, TAU, 18, rust_mid, 2.0)

	# 2. Exposed Underground Gears & Machinery
	for i in range(4):
		var a = (float(i) * TAU / 4.0) + (pulse_time * 0.4)
		var pt = Vector2(cos(a), sin(a)) * 11.0
		draw_circle(pt, 3.5, rust_mid)
		draw_circle(pt, 1.5, scrap_brass)

	# 3. Molten / Glowing Scrap Fume Vent
	draw_circle(Vector2.ZERO, 7.0, Color(scrap_glow.r, scrap_glow.g, scrap_glow.b, 0.4 * pulse))
	draw_circle(Vector2.ZERO, 4.0, scrap_glow)
	draw_circle(Vector2.ZERO, 1.5, Color.WHITE)

	# 4. Outward Resource Bracket Markers
	for i in range(4):
		var a = (float(i) * TAU / 4.0) + (PI / 4.0)
		var corner = Vector2(cos(a), sin(a)) * 26.0
		draw_rect(Rect2(corner - Vector2(2, 2), Vector2(4, 4)), scrap_brass)
