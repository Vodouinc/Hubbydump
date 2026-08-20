extends Node2D

enum BuildingType { BARRICADE, GENERATOR, TURRET, MANUFACTORUM, DISTRIBUTOR, NOOSPHERE_ANTENNA, RESEARCH_SHRINE }

@export var type: BuildingType = BuildingType.BARRICADE:
	set(val):
		type = val
		queue_redraw()

var pulse_scale: float = 0.0
var idle_timer: float = 0.0
var turret_rotation: float = 0.0
var turret_upgrade_level: int = 0
var wall_connections: Array[Vector2] = []
var is_noosphere_connected: bool = false
var laser_target_node: Node2D = null

func _process(delta: float):
	idle_timer += delta
	if pulse_scale > 0.0:
		pulse_scale = max(0.0, pulse_scale - delta * 1.8)
	queue_redraw()

func pulse_generator():
	pulse_scale = 1.0
	queue_redraw()

func _draw():
	# Draw Noosphere status aura if connected
	if is_noosphere_connected and type != BuildingType.BARRICADE:
		var aura_pulse = 0.25 + sin(idle_timer * 3.0) * 0.1
		draw_arc(Vector2.ZERO, 28.0, 0, TAU, 16, Color(0.20, 0.88, 1.0, aura_pulse), 1.2)

	match type:
		BuildingType.BARRICADE: _draw_barricade()
		BuildingType.GENERATOR: _draw_generator()
		BuildingType.TURRET: _draw_turret()
		BuildingType.MANUFACTORUM: _draw_manufactorum()
		BuildingType.DISTRIBUTOR: _draw_distributor()
		BuildingType.NOOSPHERE_ANTENNA: _draw_antenna()
		BuildingType.RESEARCH_SHRINE: _draw_research_shrine()

	# Draw Solid Continuous Laser Beam
	if is_instance_valid(laser_target_node):
		var local_target = to_local(laser_target_node.global_position)
		draw_line(Vector2.ZERO, local_target, Color(0.15, 0.90, 1.0, 0.4), 4.5)
		draw_line(Vector2.ZERO, local_target, Color(0.85, 0.98, 1.0, 0.95), 1.8)
		draw_circle(local_target, 4.0, Color(0.20, 0.88, 1.0, 0.8))

func _draw_distributor():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.25, 0.28, 0.32)
	var brass_gold = Color(0.78, 0.58, 0.22)

	# Heavy Triangular Plinth
	var tri = PackedVector2Array([Vector2(0, -18), Vector2(16, 12), Vector2(-16, 12)])
	draw_colored_polygon(tri, iron_dark)
	var closed = tri.duplicate(); closed.append(tri[0])
	draw_polyline(closed, brass_gold, 2.0)

	# Central Ground-Anchor Core
	draw_circle(Vector2.ZERO, 9.0, iron_mid)
	draw_circle(Vector2.ZERO, 4.0, brass_gold)

func _draw_antenna():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.25, 0.28, 0.32)
	var brass_gold = Color(0.85, 0.65, 0.25)
	var cyan_glow = Color(0.20, 0.88, 1.0)

	# Hexagonal Base
	var hex = PackedVector2Array()
	for i in range(6):
		var a = i * TAU / 6.0
		hex.append(Vector2(cos(a), sin(a)) * 18.0)
	draw_colored_polygon(hex, iron_dark)
	var closed = hex.duplicate(); closed.append(hex[0])
	draw_polyline(closed, brass_gold, 2.0)

	# Broadcast Satellite Dish & Antennas
	for i in range(3):
		var a = (i * TAU / 3.0) + (idle_timer * 1.5)
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * 22.0, iron_mid, 3.0)
		draw_circle(Vector2(cos(a), sin(a)) * 22.0, 2.5, cyan_glow)

	# Central Pulsing Ocular Node
	var pulse = 0.5 + sin(idle_timer * 4.0) * 0.5
	draw_circle(Vector2.ZERO, 7.0, iron_dark)
	draw_circle(Vector2.ZERO, 4.0 + pulse * 2.0, Color(cyan_glow.r, cyan_glow.g, cyan_glow.b, 0.8))

func _draw_research_shrine():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.22, 0.24, 0.28)
	var mars_red = Color(0.68, 0.12, 0.08)
	var brass_gold = Color(0.85, 0.68, 0.22)
	var cyan_holo = Color(0.20, 0.88, 1.0, 0.7)

	# Octagonal Vault Foundation
	var oct_poly = PackedVector2Array([
		Vector2(-32, -18), Vector2(-18, -32), Vector2(18, -32), Vector2(32, -18),
		Vector2(32, 18), Vector2(18, 32), Vector2(-18, 32), Vector2(-32, 18)
	])
	draw_colored_polygon(oct_poly, iron_dark)
	var closed = oct_poly.duplicate(); closed.append(oct_poly[0])
	draw_polyline(closed, brass_gold, 2.0)

	# Gothic Red Sanctuary Wings
	draw_rect(Rect2(-24, -20, 48, 40), mars_red)
	draw_rect(Rect2(-20, -24, 40, 48), mars_red)
	draw_rect(Rect2(-20, -20, 40, 40), iron_mid)

	# Central Holographic Tech-Skull Projector
	var holo_pulse = 0.6 + sin(idle_timer * 3.5) * 0.3
	draw_arc(Vector2.ZERO, 12.0, 0, TAU, 16, Color(cyan_holo.r, cyan_holo.g, cyan_holo.b, holo_pulse), 2.0)
	draw_circle(Vector2.ZERO, 5.0, cyan_holo)

func _draw_barricade():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.20, 0.22, 0.26)
	var steel_edge = Color(0.60, 0.65, 0.72)
	var brass_gold = Color(0.78, 0.58, 0.22)
	var warning_yellow = Color(0.90, 0.75, 0.15)
	var alert_red = Color(0.80, 0.15, 0.15)

	# 1. Connecting Blast Walls
	var wall_half_width = 8.0
	for conn in wall_connections:
		var dir = conn.normalized()
		var perp = dir.orthogonal() * wall_half_width
		var length = conn.length()

		var wall_poly = PackedVector2Array([-perp, conn - perp, conn + perp, perp])
		draw_colored_polygon(wall_poly, iron_dark)
		draw_line(-perp, conn - perp, steel_edge, 2.0)
		draw_line(perp, conn + perp, steel_edge, 2.0)

		var inner_perp = dir.orthogonal() * (wall_half_width - 2.5)
		var inner_poly = PackedVector2Array([-inner_perp, conn - inner_perp, conn + inner_perp, inner_perp])
		draw_colored_polygon(inner_poly, iron_mid)

		var num_struts = int(length / 16.0)
		for i in range(num_struts):
			var t1 = float(i) / float(num_struts)
			var t2 = float(i + 1) / float(num_struts)
			var p1 = (-inner_perp).lerp(conn - inner_perp, t1)
			var p2 = (inner_perp).lerp(conn + inner_perp, t2)
			draw_line(p1, p2, brass_gold, 1.2)

		var mid_point = conn * 0.5
		draw_circle(mid_point, 3.5, iron_dark)
		draw_circle(mid_point, 2.0, warning_yellow)

	# 2. Bastion Post
	draw_circle(Vector2.ZERO, 19.5, iron_dark)
	draw_arc(Vector2.ZERO, 19.5, 0, TAU, 20, brass_gold, 2.0)
	draw_circle(Vector2.ZERO, 15.0, iron_mid)
	draw_arc(Vector2.ZERO, 15.0, 0, TAU, 20, steel_edge, 1.5)

	for angle_offset in [-2.1, 0.0, 2.1]:
		var start_angle = angle_offset - 0.62
		var end_angle = angle_offset + 0.62
		draw_arc(Vector2.ZERO, 12.5, start_angle, end_angle, 8, iron_dark, 5.0)
		draw_arc(Vector2.ZERO, 12.5, start_angle, end_angle, 8, steel_edge, 1.5)
		draw_circle(Vector2.RIGHT.rotated(angle_offset) * 12.5, 2.0, warning_yellow)

	draw_circle(Vector2.ZERO, 5.5, iron_dark)
	draw_circle(Vector2.ZERO, 5.5, brass_gold, false, 1.5)
	var core_glow = (sin(idle_timer * 3.5) + 1.0) * 0.5
	draw_circle(Vector2.ZERO, 2.5, Color(alert_red.r, alert_red.g, alert_red.b, 0.5 + core_glow * 0.5))

func _draw_generator():
	var iron_dark = Color(0.12, 0.12, 0.16)
	var iron_mid = Color(0.28, 0.30, 0.35)
	var brass_gold = Color(0.85, 0.65, 0.2)
	var plasma_cyan = Color(0.15, 0.8, 1.0)
	var plasma_white = Color(0.85, 0.98, 1.0)
	var glow_intensity = 0.4 + (pulse_scale * 0.6) + (sin(idle_timer * 4.0) * 0.1)

	var hex_poly = PackedVector2Array()
	for i in range(6):
		var angle = i * TAU / 6.0
		hex_poly.append(Vector2(cos(angle), sin(angle)) * 22.0)
	draw_colored_polygon(hex_poly, iron_dark)
	var closed = hex_poly.duplicate(); closed.append(hex_poly[0])
	draw_polyline(closed, brass_gold, 2.0)

	for i in range(6):
		var fin_dir = Vector2.RIGHT.rotated(i * TAU / 6.0)
		draw_line(fin_dir * 14.0, fin_dir * 25.0, iron_mid, 4.0)
		draw_line(fin_dir * 14.0, fin_dir * 25.0, brass_gold, 1.5)

	draw_circle(Vector2.ZERO, 15.0, iron_mid)
	draw_circle(Vector2.ZERO, 15.0, brass_gold, false, 2.0)

	var aura_radius = 12.0 + (pulse_scale * 8.0)
	draw_circle(Vector2.ZERO, aura_radius, Color(plasma_cyan.r, plasma_cyan.g, plasma_cyan.b, glow_intensity * 0.4))
	draw_circle(Vector2.ZERO, 10.0, Color(0.05, 0.2, 0.35))
	draw_arc(Vector2.ZERO, 10.0, 0, TAU, 24, plasma_cyan, 2.0)

	var core_r = 4.0 + (pulse_scale * 4.0)
	draw_circle(Vector2.ZERO, core_r, plasma_white)

func _draw_turret():
	var iron_dark = Color(0.12, 0.12, 0.15)
	var iron_mid = Color(0.3, 0.32, 0.36)
	var mars_red = Color(0.7, 0.1, 0.1)
	var brass_gold = Color(0.85, 0.68, 0.22)

	draw_circle(Vector2.ZERO, 19.0, iron_dark)
	draw_circle(Vector2.ZERO, 19.0, brass_gold, false, 2.0)

	draw_set_transform(Vector2.ZERO, turret_rotation, Vector2.ONE)
	draw_rect(Rect2(2, -9, 18, 5), iron_dark)
	draw_rect(Rect2(2, 4, 18, 5), iron_dark)

	var housing_poly = PackedVector2Array([
		Vector2(-14, -14), Vector2(2, -14), Vector2(10, -7),
		Vector2(10, 7), Vector2(2, 14), Vector2(-14, 14)
	])
	draw_colored_polygon(housing_poly, mars_red)
	var closed = housing_poly.duplicate(); closed.append(housing_poly[0])
	draw_polyline(closed, brass_gold, 2.0)
	draw_circle(Vector2(4, 0), 2.5, Color(1.0, 0.2, 0.2))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_manufactorum():
	var iron_dark = Color(0.12, 0.12, 0.15)
	var mars_red = Color(0.65, 0.1, 0.1)
	var brass_gold = Color(0.85, 0.68, 0.22)
	draw_rect(Rect2(-32, -32, 64, 64), iron_dark)
	draw_rect(Rect2(-28, -28, 56, 56), mars_red)
	draw_rect(Rect2(-28, -28, 56, 56), brass_gold, false, 2.0)
	draw_circle(Vector2.ZERO, 12.0, iron_dark)
	draw_circle(Vector2.ZERO, 12.0, brass_gold, false, 2.0)
