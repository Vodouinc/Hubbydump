extends Node2D

enum BuildingType { MAIN_BASE, BARRICADE, GENERATOR, TURRET, MANUFACTORUM, DISTRIBUTOR, NOOSPHERE_ANTENNA, RESEARCH_SHRINE }

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
var is_preview: bool = false
var laser_target_node: Node2D = null
var glow_layer: Node2D = null
var turret_spec: int = 0
var volkite_target_pos: Vector2 = Vector2.ZERO
var volkite_beam_timer: float = 0.0
var arc_chain_targets: Array[Vector2] = []
var arc_beam_timer: float = 0.0
var has_spikes: bool = false
var has_electro_mesh: bool = false

func _ready() -> void:
	_setup_building_glow_layer()
	queue_redraw()

func _process(delta: float) -> void:
	var needs_redraw = false

	if pulse_scale > 0.0:
		pulse_scale = maxf(0.0, pulse_scale - delta * 1.8)
		needs_redraw = true

	if volkite_beam_timer > 0.0:
		volkite_beam_timer -= delta
		queue_redraw()
	if arc_beam_timer > 0.0:
		arc_beam_timer -= delta
		queue_redraw()

	if type == BuildingType.GENERATOR or type == BuildingType.MAIN_BASE or is_instance_valid(laser_target_node):
		idle_timer += delta
		needs_redraw = true
	elif is_gate and not is_gate_open:
		idle_timer += delta
		needs_redraw = true
		
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
	if is_noosphere_connected and type != BuildingType.BARRICADE and type != BuildingType.MAIN_BASE:
		var aura_pulse = 0.25 + sin(idle_timer * 3.0) * 0.1
		draw_arc(Vector2.ZERO, 32.0, 0, TAU, 20, Color(0.20, 0.88, 1.0, aura_pulse), 1.2)

	match type:
		BuildingType.MAIN_BASE: _draw_main_base()
		BuildingType.BARRICADE: _draw_barricade()
		BuildingType.GENERATOR: _draw_generator()
		BuildingType.TURRET: _draw_turret()
		BuildingType.MANUFACTORUM: _draw_manufactorum()
		BuildingType.DISTRIBUTOR: _draw_distributor()
		BuildingType.NOOSPHERE_ANTENNA: _draw_antenna()
		BuildingType.RESEARCH_SHRINE: _draw_research_shrine()

	# Cognis Laser Tracer
	if is_instance_valid(laser_target_node):
		var local_target = to_local(laser_target_node.global_position)
		draw_line(Vector2.ZERO, local_target, Color(0.15, 0.90, 1.0, 0.45), 4.0)
		draw_line(Vector2.ZERO, local_target, Color(0.85, 0.98, 1.0, 0.95), 1.5)
		draw_circle(local_target, 4.0, Color(0.20, 0.88, 1.0, 0.8))

func _draw_main_base():
	# --- GRIMDARK FORGEWORLD PALETTE ---
	var adamantium_black = Color(0.05, 0.06, 0.08)
	var weathered_iron = Color(0.14, 0.16, 0.20)
	var gunmetal_edge = Color(0.30, 0.34, 0.40)
	var martian_crimson_dark = Color(0.18, 0.03, 0.03)
	var martian_crimson = Color(0.42, 0.07, 0.06)
	var antique_brass = Color(0.62, 0.46, 0.18)
	var tarnished_bronze = Color(0.38, 0.26, 0.10)
	var reliquary_ivory = Color(0.66, 0.62, 0.52)
	var deep_plasma = Color(0.12, 0.60, 0.74, 0.85)
	var plasma_focal = Color(0.70, 0.92, 0.98)
	var furnace_amber = Color(0.85, 0.50, 0.10, 0.85)

	# --- 1. HEAVY SOOT-STAINED ADAMANTIUM FOUNDATION ---
	var base_poly = PackedVector2Array([
		Vector2(-48, -20), Vector2(-20, -48), Vector2(20, -48), Vector2(48, -20),
		Vector2(48, 20), Vector2(20, 48), Vector2(-20, 48), Vector2(-48, 20)
	])
	draw_colored_polygon(base_poly, adamantium_black)
	var closed_base = base_poly.duplicate(); closed_base.append(base_poly[0])
	draw_polyline(closed_base, tarnished_bronze, 2.5)
	draw_polyline(closed_base, gunmetal_edge, 1.0)

	# --- 2. FOUR CORNER BASTION BUTTRESSES ---
	var corner_offsets = [Vector2(-32, -32), Vector2(32, -32), Vector2(-32, 32), Vector2(32, 32)]
	for c in corner_offsets:
		draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), adamantium_black)
		draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), weathered_iron)
		draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), tarnished_bronze, false, 1.2)
		
		# Grated pressure thurible vent (smoldering amber)
		draw_circle(c, 3.2, adamantium_black)
		draw_circle(c, 1.6, furnace_amber)
		
		# Iron rivets
		draw_circle(c + Vector2(-4, -4), 0.9, gunmetal_edge)
		draw_circle(c + Vector2(4, -4), 0.9, gunmetal_edge)
		draw_circle(c + Vector2(-4, 4), 0.9, gunmetal_edge)
		draw_circle(c + Vector2(4, 4), 0.9, gunmetal_edge)

	# --- 3. OXIDIZED MARTIAN CRIMSON ENAMELED BASTION ---
	draw_rect(Rect2(-35, -25, 70, 50), martian_crimson_dark)
	draw_rect(Rect2(-25, -35, 50, 70), martian_crimson_dark)
	draw_rect(Rect2(-33, -23, 66, 46), martian_crimson)
	draw_rect(Rect2(-23, -33, 46, 66), martian_crimson)
	draw_rect(Rect2(-33, -23, 66, 46), antique_brass, false, 1.5)
	draw_rect(Rect2(-23, -33, 46, 66), antique_brass, false, 1.5)

	# Recessed maintenance grilles
	for wing in [Vector2(-27, 0), Vector2(27, 0), Vector2(0, -27), Vector2(0, 27)]:
		draw_rect(Rect2(wing - Vector2(4, 3), Vector2(8, 6)), adamantium_black)
		draw_rect(Rect2(wing - Vector2(4, 3), Vector2(8, 6)), tarnished_bronze, false, 1.0)
		draw_line(wing - Vector2(3, 0), wing + Vector2(3, 0), gunmetal_edge, 1.0)

	# --- 4. OPUS MACHINA (TARNISHED BRASS TOOTHED COG) ---
	var cog_radius = 20.0
	var tooth_count = 12
	for i in range(tooth_count):
		var angle = (float(i) / float(tooth_count)) * TAU
		var tooth_dir = Vector2.RIGHT.rotated(angle)
		var tooth_pos = tooth_dir * cog_radius
		draw_set_transform(tooth_pos, angle, Vector2.ONE)
		draw_rect(Rect2(-2.0, -2.0, 4.0, 4.0), antique_brass)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Gear body
	draw_circle(Vector2.ZERO, cog_radius, adamantium_black)
	draw_circle(Vector2.ZERO, cog_radius, antique_brass, false, 1.8)
	draw_circle(Vector2.ZERO, cog_radius - 2.5, weathered_iron)

	# Split-skull inner disc (Half Reliquary Bone / Half Black Iron)
	var left_semi = PackedVector2Array()
	var right_semi = PackedVector2Array()
	for i in range(17):
		var a = -PI/2 + (i * PI / 16.0)
		left_semi.append(Vector2(cos(a + PI), sin(a + PI)) * (cog_radius - 4.5))
		right_semi.append(Vector2(cos(a), sin(a)) * (cog_radius - 4.5))
	draw_colored_polygon(left_semi, reliquary_ivory)
	draw_colored_polygon(right_semi, adamantium_black)
	draw_arc(Vector2.ZERO, cog_radius - 4.5, 0, TAU, 20, tarnished_bronze, 1.0)

	# --- 5. FOUR HEAVY MAGNETIC CONTAINMENT INJECTORS ---
	for i in range(4):
		var dir = Vector2.RIGHT.rotated(float(i) * PI / 2.0)
		draw_line(dir * 8.0, dir * 16.0, adamantium_black, 3.5)
		draw_line(dir * 8.0, dir * 16.0, antique_brass, 1.2)
		draw_circle(dir * 9.0, 1.2, deep_plasma)

	# --- 6. SUBDUED ARCHEOTECH COIL & PLASMA FURNACE ---
	# Fine Dial Astrolabe Ring
	var ring_angle = idle_timer * 1.4
	draw_arc(Vector2.ZERO, 11.5, ring_angle, ring_angle + PI * 0.9, 14, deep_plasma, 1.2)
	draw_arc(Vector2.ZERO, 11.5, ring_angle + PI, ring_angle + PI * 1.9, 14, deep_plasma, 1.2)

	# Resonant Plasma Core (Dense & Compact)
	var pulse = 0.85 + sin(idle_timer * 3.5) * 0.15
	draw_circle(Vector2.ZERO, 6.0 * pulse, Color(deep_plasma.r, deep_plasma.g, deep_plasma.b, 0.25))
	draw_circle(Vector2.ZERO, 4.0, deep_plasma)
	draw_circle(Vector2.ZERO, 1.8, plasma_focal)

func _draw_barricade():
	var iron_dark = Color(0.08, 0.09, 0.12)
	var iron_mid = Color(0.18, 0.20, 0.25)
	var steel_edge = Color(0.45, 0.50, 0.58)
	var brass_gold = Color(0.68, 0.50, 0.18)
	var gate_cyan = Color(0.20, 0.88, 1.0)
	var gate_green = Color(0.25, 0.95, 0.40)
	var electro_cyan = Color(0.25, 0.85, 1.0, 0.45)

	var wall_half_width = 6.0
	var conn_count = wall_connections.size()

	# Determine vector toward base core so spikes point OUTWARD toward the desert
	var base_center = Vector2.ZERO
	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		base_center = base_node.global_position
	var away_from_base = (global_position - base_center).normalized()

	# --- 1. CLEAN SLOPED BLAST WALL SPANS ---
	for conn in wall_connections:
		var dir = conn.normalized()
		var perp = dir.orthogonal() * wall_half_width
		var length = conn.length()

		var wall_poly = PackedVector2Array([-perp, conn - perp, conn + perp, perp])
		draw_colored_polygon(wall_poly, iron_dark)
		draw_line(-perp, conn - perp, steel_edge, 1.2)
		draw_line(perp, conn + perp, steel_edge, 1.2)

		if is_gate:
			var mid_point = conn * 0.5
			if is_gate_open:
				draw_line(-perp * 0.5, conn - perp * 0.5, Color(gate_green.r, gate_green.g, gate_green.b, 0.3), 1.5)
				draw_line(perp * 0.5, conn + perp * 0.5, Color(gate_green.r, gate_green.g, gate_green.b, 0.3), 1.5)
			else:
				var pulse = 0.5 + sin(idle_timer * 5.0) * 0.3
				draw_line(Vector2.ZERO, conn, Color(gate_cyan.r, gate_cyan.g, gate_cyan.b, pulse), 2.0)
				draw_circle(mid_point, 2.5, gate_cyan)
		else:
			var inner_perp = dir.orthogonal() * (wall_half_width - 1.8)
			var inner_poly = PackedVector2Array([-inner_perp, conn - inner_perp, conn + inner_perp, inner_perp])
			draw_colored_polygon(inner_poly, iron_mid)
			draw_line(Vector2.ZERO, conn, brass_gold, 0.8)

			# --- TECH 5: OUTWARD-ONLY DRAGON'S TEETH SPIKES ---
			if has_spikes:
				# Ensure spikes point outward toward desert, away from base
				var spike_norm = perp if (perp.dot(away_from_base) > 0) else -perp
				var num_spikes = int(length / 22.0)
				for i in range(num_spikes):
					var t = (float(i) + 0.5) / float(num_spikes)
					var spike_base = conn * t + spike_norm
					var spike_tip = spike_base + spike_norm.normalized() * 5.5
					draw_line(spike_base, spike_tip, steel_edge, 1.5)

			# --- TECH 4: SUBTLE ELECTRIFIED MESH GLOW ---
			if has_electro_mesh:
				draw_line(Vector2.ZERO, conn, electro_cyan, 1.5)

	# --- 2. CLEAN FLUSH WALL JOINTS (NO HUGE CIRCLES) ---
	if conn_count == 0:
		draw_circle(Vector2.ZERO, 6.5, iron_dark)
		draw_circle(Vector2.ZERO, 6.5, brass_gold, false, 1.0)
		draw_circle(Vector2.ZERO, 2.0, iron_mid)
	elif conn_count == 1:
		draw_circle(Vector2.ZERO, 7.0, iron_dark)
		draw_circle(Vector2.ZERO, 7.0, steel_edge, false, 1.0)
		draw_rect(Rect2(-1.5, -1.5, 3, 3), brass_gold)
	else:
		# In-line joint: flush and minimal
		draw_circle(Vector2.ZERO, 5.0, iron_dark)
		draw_circle(Vector2.ZERO, 2.0, brass_gold)

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
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.26, 0.28, 0.34)
	var mars_red = Color(0.60, 0.08, 0.08)
	var brass_gold = Color(0.85, 0.68, 0.22)

	draw_circle(Vector2.ZERO, 19.0, iron_dark)
	draw_circle(Vector2.ZERO, 19.0, brass_gold, false, 2.0)

	for level in range(turret_upgrade_level):
		var ring_radius = 22.0 + level * 3.0
		var arc_start = (idle_timer * (1.5 + level * 0.25)) + level * 1.4
		draw_arc(Vector2.ZERO, ring_radius, arc_start, arc_start + PI * 1.35, 16, Color(0.25, 0.88, 1.0, 0.75), 1.5)

	# Rotate turret head
	draw_set_transform(Vector2.ZERO, turret_rotation, Vector2.ONE)

	match turret_spec:
		0: # Standard Twin Anti-Chaff Stubber
			draw_rect(Rect2(2, -8, 18, 4), iron_dark)
			draw_rect(Rect2(2, 4, 18, 4), iron_dark)
			draw_rect(Rect2(16, -9, 4, 6), brass_gold)
			draw_rect(Rect2(16, 3, 4, 6), brass_gold)

		1: # Cognis Flak (Quad Rotary Barrels)
			for offset_y in [-9, -4, 2, 7]:
				draw_rect(Rect2(2, offset_y, 20, 3.2), iron_dark)
				draw_rect(Rect2(18, offset_y - 0.5, 3, 4.2), brass_gold)

		2: # Volkite Culverin (Heavy Thermal Coils)
			draw_rect(Rect2(2, -6, 22, 12), iron_dark)
			draw_rect(Rect2(4, -7, 14, 14), Color(0.85, 0.45, 0.15)) # Copper cooling fins
			draw_circle(Vector2(24, 0), 4.0, Color(1.0, 0.2, 0.1))   # Red thermal emitter

		3: # Heavy Arc Blaster (Tesla Prongs)
			draw_rect(Rect2(2, -7, 16, 14), iron_dark)
			draw_line(Vector2(14, -8), Vector2(24, -4), brass_gold, 2.5) # Top Prong
			draw_line(Vector2(14, 8), Vector2(24, 4), brass_gold, 2.5)   # Bottom Prong
			draw_circle(Vector2(20, 0), 3.0, Color(0.20, 0.88, 1.0))     # Arc sphere

	# Mars Red Armored Casing
	var housing_poly = PackedVector2Array([
		Vector2(-14, -14), Vector2(2, -14), Vector2(10, -7),
		Vector2(10, 7), Vector2(2, 14), Vector2(-14, 14)
	])
	draw_colored_polygon(housing_poly, mars_red)
	var closed_housing = housing_poly.duplicate(); closed_housing.append(housing_poly[0])
	draw_polyline(closed_housing, brass_gold, 2.0)

	draw_circle(Vector2(3, 0), 4.5, iron_dark)
	draw_circle(Vector2(3, 0), 4.5, brass_gold, false, 1.0)
	draw_circle(Vector2(4, 0), 2.2, Color(0.20, 0.88, 1.0) if turret_spec == 3 else Color(1.0, 0.2, 0.2))

	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# --- WEAPON FIRING FX BEAMS ---
	if volkite_beam_timer > 0.0:
		var beam_alpha = volkite_beam_timer / 0.22
		draw_line(Vector2.ZERO, volkite_target_pos, Color(1.0, 0.15, 0.10, 0.4 * beam_alpha), 7.0)
		draw_line(Vector2.ZERO, volkite_target_pos, Color(1.0, 0.85, 0.70, 0.95 * beam_alpha), 2.5)

	if arc_beam_timer > 0.0 and not arc_chain_targets.is_empty():
		var arc_alpha = arc_beam_timer / 0.20
		var prev_pt = Vector2.ZERO
		for pt in arc_chain_targets:
			draw_line(prev_pt, pt, Color(0.20, 0.88, 1.0, 0.5 * arc_alpha), 4.0)
			draw_line(prev_pt, pt, Color.WHITE, 1.5)
			draw_circle(pt, 4.0, Color(0.20, 0.88, 1.0, arc_alpha))
			prev_pt = pt

func _draw_distributor():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.26, 0.28, 0.34)
	var brass_gold = Color(0.85, 0.65, 0.22)
	var amber_glow = Color(1.0, 0.75, 0.15)

	# 1. Compact 3-point anchor plinth
	var tri = PackedVector2Array([Vector2(0, -10), Vector2(9, 7), Vector2(-9, 7)])
	draw_colored_polygon(tri, iron_dark)
	var closed = tri.duplicate(); closed.append(tri[0])
	draw_polyline(closed, brass_gold, 1.5)

	# 2. Mini corner mounting bolts
	for p in tri:
		draw_circle(p, 1.8, brass_gold)

	# 3. Central Substation Diode Core
	draw_circle(Vector2.ZERO, 5.5, iron_mid)
	draw_circle(Vector2.ZERO, 5.5, brass_gold, false, 1.0)
	draw_circle(Vector2.ZERO, 3.2, Color(amber_glow.r, amber_glow.g, amber_glow.b, 0.35))
	draw_circle(Vector2.ZERO, 2.0, amber_glow)
	draw_circle(Vector2.ZERO, 0.8, Color.WHITE)

func _draw_antenna():
	var iron_dark = Color(0.10, 0.11, 0.14)
	var iron_mid = Color(0.26, 0.28, 0.34)
	var brass_gold = Color(0.85, 0.68, 0.22)
	var cyan_glow = Color(0.20, 0.88, 1.0)

	# 1. Compact Hexagonal Relay Plinth
	var hex = PackedVector2Array()
	for i in range(6):
		var a = i * TAU / 6.0
		hex.append(Vector2(cos(a), sin(a)) * 9.0)
	draw_colored_polygon(hex, iron_dark)
	var closed = hex.duplicate(); closed.append(hex[0])
	draw_polyline(closed, brass_gold, 1.5)

	# 2. Slender Emitter Needles
	for i in range(3):
		var a = (i * TAU / 3.0) + (PI / 2.0)
		var tip = Vector2(cos(a), sin(a)) * 13.0
		draw_line(Vector2.ZERO, tip, iron_mid, 2.0)
		draw_line(Vector2.ZERO, tip, brass_gold, 1.0)
		draw_circle(tip, 1.5, cyan_glow)

	# 3. Central Noosphere Broadcast Core
	draw_circle(Vector2.ZERO, 5.0, iron_dark)
	draw_circle(Vector2.ZERO, 5.0, brass_gold, false, 1.0)
	draw_circle(Vector2.ZERO, 2.5, cyan_glow)
	draw_circle(Vector2.ZERO, 1.0, Color.WHITE)

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

		if is_instance_valid(p.laser_target_node):
			var local_target = to_local(p.laser_target_node.global_position)
			draw_line(Vector2.ZERO, local_target, Color(0.15, 0.85, 1.0, 0.35), 6.0)
			draw_line(Vector2.ZERO, local_target, Color(0.85, 0.98, 1.0, 0.95), 2.2)
			draw_circle(local_target, 5.0, Color(0.20, 0.88, 1.0, 0.85))

		match p.type:
			0: # Main Sanctum (Atmospheric Grimdark Night Lighting)
				var pulse = 0.85 + sin(p.idle_timer * 3.5) * 0.15
				
				# 1. Subdued Plasma Core Glow
				draw_circle(Vector2.ZERO, 9.0 * pulse, Color(0.12, 0.60, 0.74, 0.18))
				draw_circle(Vector2.ZERO, 4.0, Color(0.12, 0.60, 0.74, 0.75))
				draw_circle(Vector2.ZERO, 1.8, Color(0.85, 0.95, 1.0, 0.9))

				# 2. Delicate Astrolabe Focus Traces
				var ring_angle = p.idle_timer * 1.4
				draw_arc(Vector2.ZERO, 11.5, ring_angle, ring_angle + PI * 0.9, 14, Color(0.12, 0.60, 0.74, 0.6), 1.2)
				draw_arc(Vector2.ZERO, 11.5, ring_angle + PI, ring_angle + PI * 1.9, 14, Color(0.12, 0.60, 0.74, 0.6), 1.2)

				# 3. Four Injector Pilot Lights
				for i in range(4):
					var dir = Vector2.RIGHT.rotated(float(i) * PI / 2.0)
					draw_circle(dir * 9.0, 1.2, Color(0.12, 0.60, 0.74, 0.8))

				# 4. Corner Bastion Votive Embers
				var corner_offsets = [Vector2(-32, -32), Vector2(32, -32), Vector2(-32, 32), Vector2(32, 32)]
				for c in corner_offsets:
					var ember_pulse = 0.7 + sin(p.idle_timer * 2.5 + c.x) * 0.3
					draw_circle(c, 1.8, Color(0.85, 0.50, 0.10, 0.7 * ember_pulse))
