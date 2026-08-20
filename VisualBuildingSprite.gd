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
var is_gate: bool = false
var is_gate_open: bool = false
var laser_target_node: Node2D = null
var glow_layer: Node2D = null

func _ready() -> void:
	_setup_building_glow_layer()
	queue_redraw()

func _process(delta: float) -> void:
	# ONLY animate and redraw if the building actually has active moving components!
	var needs_redraw = false

	if pulse_scale > 0.0:
		pulse_scale = maxf(0.0, pulse_scale - delta * 1.8)
		needs_redraw = true

	# Only generators and active lasers need continuous frame animation
	if type == BuildingType.GENERATOR or is_instance_valid(laser_target_node):
		idle_timer += delta
		needs_redraw = true
	elif is_gate and not is_gate_open:
		idle_timer += delta
		needs_redraw = true # Pulsing laser gate bars
		
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

	if needs_redraw:
		queue_redraw()
		
func _setup_building_glow_layer():
	if not has_node("BuildingGlowOverlay"):
		glow_layer = Node2D.new()
		glow_layer.name = "BuildingGlowOverlay"
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		glow_layer.material = mat
		add_child(glow_layer)
		glow_layer.set_script(load("res://VisualBuildingSprite.gd").BuildingGlowRenderer)
	else:
		glow_layer = get_node("BuildingGlowOverlay")

func pulse_generator():
	pulse_scale = 1.0
	queue_redraw()

func _draw():
	if is_noosphere_connected and type != BuildingType.BARRICADE:
		var aura_pulse = 0.25 + sin(idle_timer * 3.0) * 0.1
		draw_arc(Vector2.ZERO, 32.0, 0, TAU, 20, Color(0.20, 0.88, 1.0, aura_pulse), 1.2)

	match type:
		BuildingType.BARRICADE: _draw_barricade()
		BuildingType.GENERATOR: _draw_generator()
		BuildingType.TURRET: _draw_turret()
		BuildingType.MANUFACTORUM: _draw_manufactorum()
		BuildingType.DISTRIBUTOR: _draw_distributor()
		BuildingType.NOOSPHERE_ANTENNA: _draw_antenna()
		BuildingType.RESEARCH_SHRINE: _draw_research_shrine()

	if is_instance_valid(laser_target_node):
		var local_target = to_local(laser_target_node.global_position)
		draw_line(Vector2.ZERO, local_target, Color(0.15, 0.90, 1.0, 0.4), 5.0)
		draw_line(Vector2.ZERO, local_target, Color(0.85, 0.98, 1.0, 0.95), 1.8)
		draw_circle(local_target, 4.5, Color(0.20, 0.88, 1.0, 0.8))

func _draw_barricade():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.20, 0.22, 0.26)
	var steel_edge = Color(0.60, 0.65, 0.72)
	var brass_gold = Color(0.78, 0.58, 0.22)
	var warning_yellow = Color(0.90, 0.75, 0.15)
	var alert_red = Color(0.80, 0.15, 0.15)
	var gate_cyan = Color(0.20, 0.88, 1.0)
	var gate_green = Color(0.25, 0.95, 0.40)

	var wall_half_width = 8.0
	for conn in wall_connections:
		var dir = conn.normalized()
		var perp = dir.orthogonal() * wall_half_width
		var length = conn.length()

		var wall_poly = PackedVector2Array([-perp, conn - perp, conn + perp, perp])
		draw_colored_polygon(wall_poly, iron_dark)
		draw_line(-perp, conn - perp, steel_edge, 2.0)
		draw_line(perp, conn + perp, steel_edge, 2.0)

		if is_gate:
			if is_gate_open:
				draw_line(-perp * 0.4, conn - perp * 0.4, Color(gate_green.r, gate_green.g, gate_green.b, 0.3), 2.0)
				draw_line(perp * 0.4, conn + perp * 0.4, Color(gate_green.r, gate_green.g, gate_green.b, 0.3), 2.0)
				draw_circle(conn * 0.5, 4.0, gate_green)
			else:
				var num_lasers = 3
				for l in range(num_lasers):
					var offset_factor = lerpf(-0.6, 0.6, float(l) / float(num_lasers - 1))
					var l_p1 = (perp * offset_factor)
					var l_p2 = conn + (perp * offset_factor)
					var laser_pulse = 0.6 + sin(idle_timer * 6.0 + float(l)) * 0.35
					draw_line(l_p1, l_p2, Color(gate_cyan.r, gate_cyan.g, gate_cyan.b, laser_pulse), 2.0)

				var mid_point = conn * 0.5
				draw_circle(mid_point, 4.0, iron_mid)
				draw_circle(mid_point, 2.0, warning_yellow)
		else:
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

	draw_circle(Vector2.ZERO, 19.5, iron_dark)
	draw_arc(Vector2.ZERO, 19.5, 0, TAU, 20, brass_gold if not is_gate else (gate_green if is_gate_open else gate_cyan), 2.0)
	draw_circle(Vector2.ZERO, 15.0, iron_mid)
	draw_arc(Vector2.ZERO, 15.0, 0, TAU, 20, steel_edge, 1.5)

	for angle_offset in [-2.1, 0.0, 2.1]:
		var start_angle = angle_offset - 0.62
		var end_angle = angle_offset + 0.62
		draw_arc(Vector2.ZERO, 12.5, start_angle, end_angle, 8, iron_dark, 5.0)
		draw_arc(Vector2.ZERO, 12.5, start_angle, end_angle, 8, steel_edge, 1.5)
		draw_circle(Vector2.RIGHT.rotated(angle_offset) * 12.5, 2.0, warning_yellow)

	var beacon_color = gate_green if (is_gate and is_gate_open) else (gate_cyan if is_gate else alert_red)
	var core_glow = (sin(idle_timer * 3.5) + 1.0) * 0.5
	draw_circle(Vector2.ZERO, 5.5, iron_dark)
	draw_circle(Vector2.ZERO, 5.5, brass_gold, false, 1.5)
	draw_circle(Vector2.ZERO, 2.5, Color(beacon_color.r, beacon_color.g, beacon_color.b, 0.5 + core_glow * 0.5))

	for i in range(6):
		draw_circle(Vector2.RIGHT.rotated(float(i) * TAU / 6.0) * 16.5, 1.2, brass_gold)

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
		hex_poly.append(Vector2(cos(angle), sin(angle)) * 24.0)
	draw_colored_polygon(hex_poly, iron_dark)
	var closed = hex_poly.duplicate(); closed.append(hex_poly[0])
	draw_polyline(closed, brass_gold, 2.0)

	for i in range(6):
		var fin_dir = Vector2.RIGHT.rotated(i * TAU / 6.0)
		draw_line(fin_dir * 14.0, fin_dir * 28.0, iron_mid, 4.0)
		draw_line(fin_dir * 14.0, fin_dir * 28.0, brass_gold, 1.5)
		draw_circle(fin_dir * 26.0, 2.0, Color(1.0, 0.5, 0.1, 0.8))

	draw_circle(Vector2.ZERO, 16.0, iron_mid)
	draw_circle(Vector2.ZERO, 16.0, brass_gold, false, 2.0)

	var aura_radius = 13.0 + (pulse_scale * 9.0)
	draw_circle(Vector2.ZERO, aura_radius, Color(plasma_cyan.r, plasma_cyan.g, plasma_cyan.b, glow_intensity * 0.4))
	draw_circle(Vector2.ZERO, 11.0, Color(0.05, 0.2, 0.35))
	draw_arc(Vector2.ZERO, 11.0, 0, TAU, 24, plasma_cyan, 2.0)

	for i in range(3):
		var arc_start = idle_timer * 3.0 + (i * TAU / 3.0)
		draw_arc(Vector2.ZERO, 8.0, arc_start, arc_start + 1.8, 12, plasma_white, 2.0)

	var core_r = 4.5 + (pulse_scale * 4.0)
	draw_circle(Vector2.ZERO, core_r, plasma_white)

func _draw_turret():
	var iron_dark = Color(0.12, 0.12, 0.15)
	var iron_mid = Color(0.30, 0.32, 0.36)
	var mars_red = Color(0.70, 0.10, 0.10)
	var brass_gold = Color(0.85, 0.68, 0.22)

	draw_circle(Vector2.ZERO, 19.0, iron_dark)
	draw_circle(Vector2.ZERO, 19.0, brass_gold, false, 2.0)

	for level in range(turret_upgrade_level):
		var ring_radius = 22.0 + level * 3.0
		var arc_start = (idle_timer * (1.5 + level * 0.25)) + level * 1.4
		draw_arc(Vector2.ZERO, ring_radius, arc_start, arc_start + PI * 1.35, 16, Color(0.25, 0.88, 1.0, 0.82), 1.5)

	for i in range(8):
		var a = i * TAU / 8.0
		var bolt_pos = Vector2(cos(a), sin(a)) * 16.5
		draw_circle(bolt_pos, 1.5, brass_gold)

	draw_set_transform(Vector2.ZERO, turret_rotation, Vector2.ONE)

	draw_rect(Rect2(2, -9, 18, 5), iron_dark)
	draw_rect(Rect2(2, 4, 18, 5), iron_dark)
	draw_rect(Rect2(16, -10, 5, 7), iron_mid)
	draw_rect(Rect2(16, 3, 5, 7), iron_mid)
	draw_rect(Rect2(18, -9.5, 2, 6), brass_gold)
	draw_rect(Rect2(18, 3.5, 2, 6), brass_gold)

	var housing_poly = PackedVector2Array([
		Vector2(-14, -14), Vector2(2, -14), Vector2(10, -7),
		Vector2(10, 7), Vector2(2, 14), Vector2(-14, 14)
	])
	draw_colored_polygon(housing_poly, mars_red)
	var closed_housing = housing_poly.duplicate(); closed_housing.append(housing_poly[0])
	draw_polyline(closed_housing, brass_gold, 2.0)

	draw_rect(Rect2(-10, -17, 10, 3), iron_mid)
	draw_rect(Rect2(-10, 14, 10, 3), iron_mid)
	draw_rect(Rect2(-10, -17, 10, 3), brass_gold, false, 1.0)
	draw_rect(Rect2(-10, 14, 10, 3), brass_gold, false, 1.0)
	draw_rect(Rect2(-12, -8, 4, 16), iron_dark)
	draw_line(Vector2(-10, -6), Vector2(-10, 6), brass_gold, 1.5)

	draw_circle(Vector2(3, 0), 4.5, iron_dark)
	draw_circle(Vector2(3, 0), 4.5, brass_gold, false, 1.0)
	draw_circle(Vector2(4, 0), 2.5, Color(1.0, 0.2, 0.2))
	draw_circle(Vector2(4.8, -0.8), 0.8, Color.WHITE)

	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_distributor():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.25, 0.28, 0.32)
	var brass_gold = Color(0.78, 0.58, 0.22)
	var amber_glow = Color(0.95, 0.72, 0.15)

	var tri = PackedVector2Array([Vector2(0, -20), Vector2(18, 14), Vector2(-18, 14)])
	draw_colored_polygon(tri, iron_dark)
	var closed = tri.duplicate(); closed.append(tri[0])
	draw_polyline(closed, brass_gold, 2.0)

	for p in tri:
		draw_circle(p, 4.0, iron_mid)
		draw_circle(p, 4.0, brass_gold, false, 1.0)
		draw_circle(p, 2.0, amber_glow)

	draw_circle(Vector2.ZERO, 10.0, iron_mid)
	draw_circle(Vector2.ZERO, 6.0, iron_dark)
	draw_circle(Vector2.ZERO, 6.0, brass_gold, false, 1.5)
	draw_circle(Vector2.ZERO, 3.0, amber_glow)

func _draw_antenna():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.25, 0.28, 0.32)
	var brass_gold = Color(0.85, 0.65, 0.25)
	var cyan_glow = Color(0.20, 0.88, 1.0)

	var hex = PackedVector2Array()
	for i in range(6):
		var a = i * TAU / 6.0
		hex.append(Vector2(cos(a), sin(a)) * 20.0)
	draw_colored_polygon(hex, iron_dark)
	var closed = hex.duplicate(); closed.append(hex[0])
	draw_polyline(closed, brass_gold, 2.0)

	for i in range(3):
		var a = (i * TAU / 3.0) + 0.4
		var tip = Vector2(cos(a), sin(a)) * 24.0
		draw_line(Vector2.ZERO, tip, iron_mid, 3.5)
		draw_line(Vector2.ZERO, tip, brass_gold, 1.5)
		draw_circle(tip, 3.0, cyan_glow)

	draw_circle(Vector2.ZERO, 9.0, iron_dark)
	draw_circle(Vector2.ZERO, 9.0, brass_gold, false, 1.5)
	draw_circle(Vector2.ZERO, 4.0, cyan_glow)

func _draw_research_shrine():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.22, 0.24, 0.28)
	var mars_red = Color(0.68, 0.12, 0.08)
	var mars_red_dark = Color(0.42, 0.06, 0.05)
	var brass_gold = Color(0.85, 0.68, 0.22)
	var cyan_holo = Color(0.20, 0.88, 1.0, 0.8)

	var oct_poly = PackedVector2Array([
		Vector2(-32, -18), Vector2(-18, -32), Vector2(18, -32), Vector2(32, -18),
		Vector2(32, 18), Vector2(18, 32), Vector2(-18, 32), Vector2(-32, 18)
	])
	draw_colored_polygon(oct_poly, iron_dark)
	var closed = oct_poly.duplicate(); closed.append(oct_poly[0])
	draw_polyline(closed, brass_gold, 2.0)

	draw_rect(Rect2(-26, -22, 52, 44), mars_red_dark)
	draw_rect(Rect2(-22, -26, 44, 52), mars_red_dark)
	draw_rect(Rect2(-24, -20, 48, 40), mars_red)
	draw_rect(Rect2(-20, -24, 40, 48), mars_red)
	draw_rect(Rect2(-24, -20, 48, 40), brass_gold, false, 1.5)
	draw_rect(Rect2(-20, -24, 40, 48), brass_gold, false, 1.5)

	for corner in [Vector2(-20, -20), Vector2(20, -20), Vector2(-20, 20), Vector2(20, 20)]:
		draw_circle(corner, 5.0, iron_mid)
		draw_circle(corner, 5.0, brass_gold, false, 1.0)
		draw_circle(corner, 2.5, cyan_holo)

	draw_circle(Vector2.ZERO, 13.0, iron_dark)
	draw_circle(Vector2.ZERO, 13.0, brass_gold, false, 2.0)
	draw_arc(Vector2.ZERO, 10.0, 0, TAU, 16, cyan_holo, 2.0)
	draw_circle(Vector2.ZERO, 5.0, cyan_holo)
	draw_circle(Vector2.ZERO, 2.0, Color.WHITE)

func _draw_manufactorum():
	var iron_dark = Color(0.12, 0.12, 0.15)
	var iron_mid = Color(0.25, 0.26, 0.30)
	var mars_red = Color(0.65, 0.1, 0.1)
	var mars_red_dark = Color(0.4, 0.05, 0.05)
	var brass_gold = Color(0.85, 0.68, 0.22)
	var brass_dark = Color(0.5, 0.38, 0.1)
	var cyan_plasma = Color(0.2, 0.85, 1.0, 0.8)

	var base_poly = PackedVector2Array([
		Vector2(-36, -20), Vector2(-20, -36), Vector2(20, -36), Vector2(36, -20),
		Vector2(36, 20), Vector2(20, 36), Vector2(-20, 36), Vector2(-36, 20)
	])
	draw_colored_polygon(base_poly, iron_dark)
	var closed_base = base_poly.duplicate(); closed_base.append(base_poly[0])
	draw_polyline(closed_base, brass_dark, 2.5)

	for corner in [Vector2(-30, -30), Vector2(30, -30), Vector2(-30, 30), Vector2(30, 30)]:
		draw_rect(Rect2(corner - Vector2(4, 4), Vector2(8, 8)), iron_mid)
		draw_rect(Rect2(corner - Vector2(4, 4), Vector2(8, 8)), brass_gold, false, 1.0)

	draw_rect(Rect2(-28, -24, 56, 48), mars_red_dark)
	draw_rect(Rect2(-24, -28, 48, 56), mars_red_dark)
	draw_rect(Rect2(-26, -22, 52, 44), mars_red)
	draw_rect(Rect2(-22, -26, 44, 52), mars_red)
	draw_rect(Rect2(-26, -22, 52, 44), brass_gold, false, 1.5)
	draw_rect(Rect2(-22, -26, 44, 52), brass_gold, false, 1.5)

	var chimney_positions = [Vector2(-20, -20), Vector2(20, -20), Vector2(-20, 20), Vector2(20, 20)]
	for pos in chimney_positions:
		draw_circle(pos, 6.0, iron_dark)
		draw_circle(pos, 6.0, brass_gold, false, 1.5)
		draw_circle(pos, 3.0, Color(1.0, 0.4, 0.1, 0.7))

	var cog_center = Vector2.ZERO
	var cog_radius = 14.0
	for i in range(8):
		var angle = (i * TAU / 8.0)
		var tooth_dir = Vector2.RIGHT.rotated(angle)
		draw_set_transform(cog_center + tooth_dir * cog_radius, angle, Vector2.ONE)
		draw_rect(Rect2(-2.5, -2.5, 5.0, 5.0), brass_gold)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	draw_circle(cog_center, cog_radius, iron_dark)
	draw_circle(cog_center, cog_radius, brass_gold, false, 2.0)

	var left_semi = PackedVector2Array()
	var right_semi = PackedVector2Array()
	for i in range(17):
		var a = -PI/2 + (i * PI / 16.0)
		left_semi.append(cog_center + Vector2(cos(a + PI), sin(a + PI)) * (cog_radius - 2))
		right_semi.append(cog_center + Vector2(cos(a), sin(a)) * (cog_radius - 2))

	draw_colored_polygon(left_semi, Color(0.9, 0.9, 0.9))
	draw_colored_polygon(right_semi, iron_mid)
	draw_circle(Vector2(0, -6), 4.0, cyan_plasma)
	draw_circle(Vector2(0, -6), 5.0, brass_gold, false, 1.0)

class BuildingGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		# 1. Solid-State Cognis Laser Beam (Always 100% luminous across night!)
		if is_instance_valid(p.laser_target_node):
			var local_target = to_local(p.laser_target_node.global_position)
			draw_line(Vector2.ZERO, local_target, Color(0.15, 0.85, 1.0, 0.35), 6.0)
			draw_line(Vector2.ZERO, local_target, Color(0.85, 0.98, 1.0, 0.95), 2.2)
			draw_circle(local_target, 5.0, Color(0.20, 0.88, 1.0, 0.85))

		# 2. Structure Night Glows
		match p.type:
			1: # Generator Plasma Core
				var core_r = 4.5 + (p.pulse_scale * 4.0)
				draw_circle(Vector2.ZERO, core_r + 4.0, Color(0.15, 0.85, 1.0, 0.35))
				draw_circle(Vector2.ZERO, core_r, Color.WHITE)
			2: # Turret Targeter Eye
				var dir = Vector2.RIGHT.rotated(p.turret_rotation)
				draw_circle(dir * 4.0, 3.0, Color(1.0, 0.2, 0.2, 0.9))
				draw_circle(dir * 4.0, 1.0, Color.WHITE)
			5: # Antenna Spikes
				for i in range(3):
					var a = (i * TAU / 3.0) + 0.4
					draw_circle(Vector2(cos(a), sin(a)) * 24.0, 3.5, Color(0.20, 0.88, 1.0))
				draw_circle(Vector2.ZERO, 5.0, Color(0.20, 0.88, 1.0))
			6: # Tech Shrine Hologram
				var holo_pulse = 0.6 + sin(p.idle_timer * 3.5) * 0.3
				draw_arc(Vector2.ZERO, 10.0, 0, TAU, 16, Color(0.20, 0.88, 1.0, holo_pulse), 2.0)
				draw_circle(Vector2.ZERO, 5.0, Color(0.20, 0.88, 1.0))
				draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
