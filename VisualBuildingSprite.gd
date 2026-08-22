@tool
extends Node2D

enum BuildingType { 
	MAIN_BASE = 0, 
	BARRICADE = 1, 
	GENERATOR = 2, 
	TURRET = 3, 
	MANUFACTORUM = 4, 
	DISTRIBUTOR = 5, 
	NOOSPHERE_ANTENNA = 6, 
	RESEARCH_SHRINE = 7,
	CYBERNETICA_FORGE = 8
}

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

# --- GRIMDARK 40K PALETTE ---
const C_OUTLINE     := Color(0.04, 0.05, 0.07)
const C_STEEL_DARK  := Color(0.12, 0.14, 0.18) # Soot cast-iron
const C_STEEL_MID   := Color(0.24, 0.28, 0.35) # Armor plating
const C_STEEL_LIGHT := Color(0.42, 0.48, 0.56) # Bevel steel
const C_MARS_DARK   := Color(0.28, 0.05, 0.05) # Shaded red
const C_MARS_RED    := Color(0.68, 0.16, 0.14) # Martian crimson
const C_MARS_LIGHT  := Color(0.85, 0.25, 0.20) # Highlight red
const C_BRASS_DARK  := Color(0.40, 0.28, 0.10) # Antique bronze
const C_BRASS       := Color(0.82, 0.62, 0.24) # Sanctified brass
const C_BRASS_LIGHT := Color(0.96, 0.82, 0.45) # Polished trim
const C_COPPER      := Color(0.82, 0.44, 0.18) # Thermal copper
const C_CYAN        := Color(0.20, 0.88, 1.00) # Omnissian plasma
const C_AMBER       := Color(1.00, 0.70, 0.15) # Molten crucible fire
const C_RUNE_GREEN  := Color(0.25, 0.95, 0.40) # Cogitator machine code

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
		needs_redraw = true
	if arc_beam_timer > 0.0:
		arc_beam_timer -= delta
		needs_redraw = true

	idle_timer += delta
	if type in [BuildingType.GENERATOR, BuildingType.MAIN_BASE, BuildingType.MANUFACTORUM, BuildingType.TURRET, BuildingType.CYBERNETICA_FORGE] or is_instance_valid(laser_target_node) or (is_gate and not is_gate_open):
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
	match type:
		BuildingType.MAIN_BASE:         _draw_main_base()
		BuildingType.BARRICADE:         _draw_barricade()
		BuildingType.GENERATOR:         _draw_generator()
		BuildingType.TURRET:            _draw_turret()
		BuildingType.MANUFACTORUM:      _draw_manufactorum()
		BuildingType.DISTRIBUTOR:       _draw_distributor()
		BuildingType.NOOSPHERE_ANTENNA: _draw_antenna()
		BuildingType.RESEARCH_SHRINE:   _draw_research_shrine()
		BuildingType.CYBERNETICA_FORGE: _draw_cybernetica_forge()

	# Laser Tracer
	if is_instance_valid(laser_target_node):
		var local_target = to_local(laser_target_node.global_position)
		draw_line(Vector2(0, -10), local_target, Color(0.15, 0.90, 1.0, 0.45), 4.0)
		draw_line(Vector2(0, -10), local_target, Color(0.85, 0.98, 1.0, 0.95), 1.5)
		draw_circle(local_target, 4.0, Color(0.20, 0.88, 1.0, 0.8))

# ==============================================================================
# 1. FORGE-TEMPLE SANCTUM (CENTRAL CATHEDRAL SMELTER BASTION)
# ==============================================================================
func _draw_main_base():
	# Ground Contact Drop Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
	draw_circle(Vector2(0, 4), 48.0, Color(0.02, 0.02, 0.04, 0.55))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Tier 1: Octagonal Fortified Foundry Plinth
	IsoDraw.box(self, Vector3(-28, -28, 0), Vector3(56, 56, 8), C_STEEL_DARK)

	# 4 Corner Incense Thurible Bastion Towers
	for c in [Vector3(-24, -24, 8), Vector3(16, -24, 8), Vector3(-24, 16, 8), Vector3(16, 16, 8)]:
		IsoDraw.box(self, c, Vector3(8, 8, 10), C_STEEL_MID)
		var th_top = IsoDraw.project(c.x + 4, c.y + 4, c.z + 10)
		draw_circle(th_top, 2.8, C_BRASS)
		var ember = 0.6 + sin(idle_timer * 4.0 + c.x) * 0.4
		draw_circle(th_top, 1.6, Color(C_AMBER.r, C_AMBER.g, C_AMBER.b, ember))

	# Tier 2: Martian Crimson Citadel Forge Hull
	IsoDraw.box(self, Vector3(-20, -20, 8), Vector3(40, 40, 16), C_MARS_RED)

	# Central Molten Blast Crucible Gate (Glowing Orange Hearth)
	var door_p = IsoDraw.project(0, 20, 0)
	draw_rect(Rect2(door_p - Vector2(10, 12), Vector2(20, 12)), C_STEEL_DARK)
	var fire = 0.75 + sin(idle_timer * 6.0) * 0.25
	draw_rect(Rect2(door_p - Vector2(8, 10), Vector2(16, 10)), Color(C_AMBER.r, C_AMBER.g, C_AMBER.b, fire))
	draw_rect(Rect2(door_p - Vector2(10, 12), Vector2(20, 12)), C_BRASS, false, 1.2)

	# Opus Machina Sacred Cog Emblem
	var cog_center = IsoDraw.project(0, 0, 24)
	IsoDraw.opus_machina_cog(self, cog_center, 13.0, 8)

	# Twin Smokestacks Puffing Furnace Embers
	for sx in [-12.0, 12.0]:
		var stack_top = IsoDraw.project(sx, -14, 28)
		draw_circle(stack_top, 3.0, C_STEEL_DARK)
		draw_circle(stack_top, 3.0, C_BRASS, false, 1.0)
		draw_circle(stack_top, 1.5, Color(C_AMBER.r, C_AMBER.g, C_AMBER.b, 0.8))

	# Central Plasma Core Flame
	draw_circle(cog_center, 3.0, C_CYAN)
	draw_circle(cog_center, 1.2, Color.WHITE)

	# Purity Seals
	IsoDraw.purity_seal(self, door_p + Vector2(-12, -4), 8.0)
	IsoDraw.purity_seal(self, door_p + Vector2(12, -4), 8.0)

# ==============================================================================
# 2. BARRICADE (AEGIS BLAST DEFENSE LINE)
# ==============================================================================
func _draw_barricade():
	for conn in wall_connections:
		var dir = conn.normalized()
		var perp = dir.orthogonal() * 5.0
		
		var p1 = -perp; var p2 = conn - perp
		var p3 = conn + perp; var p4 = perp
		var poly = PackedVector2Array([p1, p2, p3, p4])

		if is_gate:
			if is_gate_open:
				draw_line(Vector2.ZERO, conn, Color(0.25, 0.95, 0.40, 0.4), 2.5)
			else:
				var pulse = 0.5 + sin(idle_timer * 5.0) * 0.3
				draw_colored_polygon(poly, C_STEEL_DARK)
				draw_line(Vector2.ZERO, conn, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, pulse), 2.5)
				draw_circle(conn * 0.5, 2.5, C_CYAN)
		else:
			draw_colored_polygon(poly, C_MARS_RED)
			var cl = poly.duplicate(); cl.append(poly[0])
			draw_polyline(cl, C_OUTLINE, 1.4)
			draw_line(Vector2.ZERO, conn, C_BRASS, 1.2)

			# Hazard Braces
			var num_braces = int(conn.length() / 18.0)
			for i in range(num_braces):
				var t = (float(i) + 0.5) / float(num_braces)
				var pt = conn * t
				draw_line(pt - perp * 0.8, pt + perp * 0.8, C_AMBER, 1.8)

			if has_spikes:
				for i in range(num_braces):
					var t = (float(i) + 0.5) / float(num_braces)
					var sp = conn * t + perp
					draw_line(sp, sp + perp.normalized() * 5.0, C_STEEL_LIGHT, 2.0)

	# Standing Anchor Posts
	IsoDraw.box(self, Vector3(-5, -5, 0), Vector3(10, 10, 12), C_STEEL_DARK)
	draw_circle(IsoDraw.project(0, 0, 12), 2.5, C_BRASS)
	IsoDraw.purity_seal(self, IsoDraw.project(0, 5, 6), 6.0)

# ==============================================================================
# 3. INCREMENTAL COGNIS TURRET (LEVELS 1 TO 4 + 4 SPECIALIZATIONS)
# ==============================================================================
func _draw_turret():
	# Ground Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
	draw_circle(Vector2(0, 2), 18.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# --- NOOSPHERIC TARGETING UPLINK AUSPEX RETICLE ---
	var main_node = get_tree().get_first_node_in_group("main")
	var has_smart_uplink = is_noosphere_connected and not is_preview and (main_node.get("tech_targeting_uplink_unlocked") if main_node else false)

	if has_smart_uplink:
		var pulse = 0.65 + sin(idle_timer * 4.5) * 0.35
		var reticle_r = 16.0 + (turret_upgrade_level * 1.5)
		
		# Flat ground projection
		draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
		draw_arc(Vector2(0, 4), reticle_r, 0.0, TAU, 24, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.45 * pulse), 1.2)
		draw_arc(Vector2(0, 4), reticle_r * 0.6, 0.0, TAU, 16, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.20 * pulse), 1.0)
		
		# Auspex rotating cardinal telemetry ticks
		for i in range(4):
			var a = (float(i) * (TAU / 4.0)) + (idle_timer * 0.8)
			var p_outer = Vector2(cos(a), sin(a)) * reticle_r + Vector2(0, 4)
			var p_inner = Vector2(cos(a), sin(a)) * (reticle_r - 3.5) + Vector2(0, 4)
			draw_line(p_inner, p_outer, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.75 * pulse), 1.4)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# --------------------------------------------------

	# Bunker Pedestal Base
	var base_w = 20.0 + (turret_upgrade_level * 2.0)
	var base_h = 6.0 + (turret_upgrade_level * 2.0)
	IsoDraw.box(self, Vector3(-base_w*0.5, -base_w*0.5, 0), Vector3(base_w, base_w, base_h), C_STEEL_DARK)

	for c in [Vector3(-base_w*0.4, -base_w*0.4, base_h), Vector3(base_w*0.4, -base_w*0.4, base_h),
			  Vector3(-base_w*0.4, base_w*0.4, base_h), Vector3(base_w*0.4, base_w*0.4, base_h)]:
		draw_circle(IsoDraw.project(c.x, c.y, c.z), 1.2, C_BRASS)

	# Rotating Turret Cupola
	var head_z = base_h
	var head_pos = IsoDraw.project(0, 0, head_z)
	var aim_dir = Vector2.RIGHT.rotated(turret_rotation)
	var perp = aim_dir.orthogonal()

	draw_circle(head_pos, 7.5 + turret_upgrade_level * 0.8, C_MARS_RED)
	draw_arc(head_pos, 7.5 + turret_upgrade_level * 0.8, 0, TAU, 16, C_OUTLINE, 1.4)
	draw_circle(head_pos, 4.0, C_STEEL_DARK)

	# Weapon Barrels
	var b_root = head_pos + (aim_dir * 3.0)
	var b_len = 14.0 + (turret_upgrade_level * 2.5)
	var b_tip = head_pos + (aim_dir * b_len)

	match turret_upgrade_level:
		0: # LVL 1: Twin Light Stubbers
			draw_line(b_root + perp * 3.0, b_tip + perp * 3.0, C_STEEL_DARK, 3.0)
			draw_line(b_root - perp * 3.0, b_tip - perp * 3.0, C_STEEL_DARK, 3.0)
			draw_circle(b_tip + perp * 3.0, 1.2, C_STEEL_LIGHT)
			draw_circle(b_tip - perp * 3.0, 1.2, C_STEEL_LIGHT)

		1: # LVL 2: Heavy Autocannons (Muzzle Brakes + Side Ammo Drum)
			draw_line(b_root + perp * 3.5, b_tip + perp * 3.5, C_STEEL_DARK, 4.0)
			draw_line(b_root - perp * 3.5, b_tip - perp * 3.5, C_STEEL_DARK, 4.0)
			draw_line(b_root + perp * 3.5, b_tip + perp * 3.5, C_BRASS, 1.2)
			draw_line(b_root - perp * 3.5, b_tip - perp * 3.5, C_BRASS, 1.2)
			draw_rect(Rect2(b_tip + perp * 2.0 - Vector2(1, 1), Vector2(3, 3)), C_BRASS)
			draw_rect(Rect2(b_tip - perp * 5.0 - Vector2(1, 1), Vector2(3, 3)), C_BRASS)
			draw_circle(head_pos - perp * 6.5, 2.5, C_STEEL_DARK)

		2: # LVL 3: Cognis Heavy Siege Guns (Recoil Pistons + Targeting Radar)
			draw_line(b_root + perp * 4.0, b_tip + perp * 4.0, C_STEEL_DARK, 5.0)
			draw_line(b_root - perp * 4.0, b_tip - perp * 4.0, C_STEEL_DARK, 5.0)
			draw_line(b_root + perp * 4.0, b_tip + perp * 4.0, C_BRASS, 1.5)
			draw_line(b_root - perp * 4.0, b_tip - perp * 4.0, C_BRASS, 1.5)
			draw_rect(Rect2(b_root + perp * 2.5 - Vector2(1, 1), Vector2(4, 3)), C_COPPER)
			draw_rect(Rect2(b_root - perp * 5.5 - Vector2(1, 1), Vector2(4, 3)), C_COPPER)
			var dish_pos = head_pos + Vector2(0, -6)
			var sweep = (idle_timer * 3.0)
			draw_arc(dish_pos, 3.5, sweep, sweep + PI, 8, C_CYAN, 1.2)
			IsoDraw.purity_seal(self, head_pos + perp * 6.0, 5.0)

		3: # LVL 4 / SANCTIFIED SPECIALIZATIONS
			match turret_spec:
				0: # Standard Superheavy Siege Battery
					draw_line(b_root + perp * 4.5, b_tip + perp * 4.5, C_STEEL_DARK, 6.0)
					draw_line(b_root - perp * 4.5, b_tip - perp * 4.5, C_STEEL_DARK, 6.0)
					draw_line(b_root + perp * 4.5, b_tip + perp * 4.5, C_BRASS_LIGHT, 2.0)
					draw_line(b_root - perp * 4.5, b_tip - perp * 4.5, C_BRASS_LIGHT, 2.0)
					draw_rect(Rect2(head_pos - Vector2(5, 5), Vector2(10, 10)), C_MARS_RED, false, 1.5)
				1: # Cognis Flak (Quad Gatling Arrays)
					for o in [-5.0, -1.8, 1.8, 5.0]:
						draw_line(b_root + perp * o, b_tip + perp * o, C_STEEL_DARK, 2.5)
						draw_line(b_root + perp * o, b_tip + perp * o, C_BRASS, 1.0)
				2: # Volkite Thermal Culverin (Ribbed Copper Coils)
					draw_line(b_root, b_tip, C_STEEL_DARK, 7.0)
					draw_line(b_root, b_tip, C_COPPER, 4.0)
					for i in range(4):
						var cp = b_root.lerp(b_tip, i / 3.0)
						draw_circle(cp, 2.5, C_BRASS)
					draw_circle(b_tip, 3.2, Color(1.0, 0.2, 0.1))
				3: # Heavy Arc Blaster (Tesla Prongs)
					draw_line(b_root + perp * 4.5, b_tip + perp * 2.0, C_BRASS, 2.5)
					draw_line(b_root - perp * 4.5, b_tip - perp * 2.0, C_BRASS, 2.5)
					draw_circle(head_pos, 4.5, C_CYAN)

	draw_circle(head_pos, 2.0, C_CYAN)

	# Firing Beams
	if volkite_beam_timer > 0.0:
		var beam_a = volkite_beam_timer / 0.22
		draw_line(head_pos, volkite_target_pos, Color(1.0, 0.15, 0.10, 0.4 * beam_a), 7.0)
		draw_line(head_pos, volkite_target_pos, Color(1.0, 0.85, 0.70, 0.95 * beam_a), 2.5)

	if arc_beam_timer > 0.0 and not arc_chain_targets.is_empty():
		var arc_a = arc_beam_timer / 0.20
		var prev_pt = head_pos
		for pt in arc_chain_targets:
			draw_line(prev_pt, pt, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.5 * arc_a), 4.0)
			draw_line(prev_pt, pt, Color.WHITE, 1.5)
			draw_circle(pt, 4.0, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, arc_a))
			prev_pt = pt

# ==============================================================================
# 4. PLASMA INDUCTION GENERATOR (TESLA / INDUCTION COIL TOWER - REFERENCE MATCH)
# ==============================================================================
func _draw_generator():
	# Ground Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
	draw_circle(Vector2(0, 3), 26.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Reactor Foundation Chassis
	IsoDraw.box(self, Vector3(-16, -14, 0), Vector3(32, 28, 6), C_STEEL_DARK)

	# 3 Vertical Plasma Induction Coil Towers (Reference Style)
	for i in range(3):
		var cx = -10.0 + (i * 10.0)
		# Tower Base
		IsoDraw.cylinder(self, Vector3(cx, 0, 6), 4.5, 14.0, C_COPPER)
		
		# Glowing Cyan Induction Rings
		for r_z in [8.0, 12.0, 16.0]:
			var ring_p = IsoDraw.project(cx, 0, r_z)
			draw_arc(ring_p, 4.2, 0, TAU, 12, C_CYAN, 1.2)

		# Top Glowing Plasma Sphere
		var top_p = IsoDraw.project(cx, 0, 20)
		var pulse = 0.7 + sin(idle_timer * 5.0 + i) * 0.3
		draw_circle(top_p, 2.8 * pulse, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.4))
		draw_circle(top_p, 1.8, C_CYAN)
		draw_circle(top_p, 0.8, Color.WHITE)

	# Electric Spark Arcs Between Towers
	if randf() < 0.35:
		var p_a = IsoDraw.project(-10, 0, 18)
		var p_b = IsoDraw.project(0, 0, 18)
		draw_line(p_a, p_b + Vector2(randf_range(-2, 2), randf_range(-2, 2)), C_CYAN, 1.2)

	IsoDraw.purity_seal(self, IsoDraw.project(16, -8, 6), 6.0)

# ==============================================================================
# 5. SCRAP FOUNDRY / PROMETHIUM SMELTER
# ==============================================================================
func _draw_manufactorum():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
	draw_circle(Vector2(0, 4), 32.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Smelter Foundation Hull
	IsoDraw.box(self, Vector3(-18, -18, 0), Vector3(36, 36, 14), C_STEEL_DARK)
	IsoDraw.box(self, Vector3(-14, -14, 14), Vector3(28, 28, 8), C_MARS_RED)

	# Twin Brass-Banded Smokestacks
	for sc in [Vector3(-10, -10, 22), Vector3(6, -10, 22)]:
		IsoDraw.cylinder(self, Vector3(sc.x + 3, sc.y + 3, 22), 3.5, 12.0, C_STEEL_MID)
		var top_p = IsoDraw.project(sc.x + 3, sc.y + 3, 34)
		draw_circle(top_p, 2.5, C_BRASS)
		draw_circle(top_p, 1.2, Color(C_AMBER.r, C_AMBER.g, C_AMBER.b, 0.85))

	# Molten Crucible Hearth
	var grate_p = IsoDraw.project(0, 18, 4)
	draw_rect(Rect2(grate_p - Vector2(8, 4), Vector2(16, 8)), C_STEEL_DARK)
	var ember = 0.65 + sin(idle_timer * 6.0) * 0.35
	draw_rect(Rect2(grate_p - Vector2(7, 3), Vector2(14, 6)), Color(C_AMBER.r, C_AMBER.g, C_AMBER.b, ember))
	
	for i in range(3):
		draw_line(Vector2(grate_p.x - 4 + i * 4, grate_p.y - 3), Vector2(grate_p.x - 4 + i * 4, grate_p.y + 3), C_STEEL_DARK, 1.5)

	IsoDraw.purity_seal(self, IsoDraw.project(18, 0, 8), 7.0)

# ==============================================================================
# 6. DISTRIBUTOR RELAY SUBSTATION
# ==============================================================================
func _draw_distributor():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
	draw_circle(Vector2(0, 2), 14.0, Color(0.02, 0.02, 0.04, 0.35))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Heavy Steel Base & Ceramic Insulator Column
	IsoDraw.box(self, Vector3(-8, -8, 0), Vector3(16, 16, 6), C_STEEL_DARK)
	IsoDraw.cylinder(self, Vector3(0, 0, 6), 5.5, 12.0, C_COPPER)

	# Ceramic Insulator Ribs
	for oy in [8.0, 12.0, 16.0]:
		var bp = IsoDraw.project(0, 0, oy)
		draw_arc(bp, 6.0, 0, TAU, 12, C_BRASS, 1.4)

	# Top Amber Capacitor Globe
	var tip = IsoDraw.project(0, 0, 18)
	draw_circle(tip, 3.5, C_BRASS)
	draw_circle(tip, 2.0, C_AMBER)
	draw_circle(tip, 1.0, Color.WHITE)

# ==============================================================================
# 7. NOOSPHERE ANTENNA MAST
# ==============================================================================
func _draw_antenna():
	IsoDraw.box(self, Vector3(-6, -6, 0), Vector3(12, 12, 10), C_STEEL_DARK)
	IsoDraw.box(self, Vector3(-4, -4, 10), Vector3(8, 8, 12), C_STEEL_MID)

	# Communication Spire
	var mast = IsoDraw.project(0, 0, 22)
	draw_line(mast, mast + Vector2(0, -14), C_BRASS, 2.0)
	draw_arc(mast + Vector2(0, -14), 4.5, 0, TAU, 12, C_CYAN, 1.2)
	draw_circle(mast + Vector2(0, -14), 2.0, Color.WHITE)

	IsoDraw.purity_seal(self, IsoDraw.project(6, 0, 6), 6.0)

# ==============================================================================
# 8. TECH SHRINE (COGITATOR ARCHIVES & RELIQUARY)
# ==============================================================================
func _draw_research_shrine():
	IsoDraw.box(self, Vector3(-16, -16, 0), Vector3(32, 32, 12), C_STEEL_DARK)
	IsoDraw.box(self, Vector3(-12, -12, 12), Vector3(24, 24, 12), C_MARS_RED)

	# Illuminated Machine Rune Screens
	var screen_p = IsoDraw.project(0, 16, 6)
	draw_rect(Rect2(screen_p - Vector2(8, 4), Vector2(16, 8)), C_STEEL_DARK)
	draw_rect(Rect2(screen_p - Vector2(7, 3), Vector2(14, 6)), Color(0.04, 0.12, 0.16))
	var code_flicker = 0.7 + sin(idle_timer * 4.0) * 0.3
	draw_rect(Rect2(screen_p - Vector2(6, 2), Vector2(12, 4)), Color(C_RUNE_GREEN.r, C_RUNE_GREEN.g, C_RUNE_GREEN.b, code_flicker * 0.8))

	# Holo Astrolabe on Roof
	var holo = IsoDraw.project(0, 0, 24)
	draw_arc(holo, 7.0, 0, TAU, 16, C_CYAN, 1.2)
	draw_circle(holo, 2.0, C_CYAN)
	draw_circle(holo, 1.0, Color.WHITE)

	IsoDraw.purity_seal(self, screen_p + Vector2(-10, -2), 8.0)
	IsoDraw.purity_seal(self, screen_p + Vector2(10, -2), 8.0)

# =============================================================================
# CYBERNETICA FORGE
# =============================================================================

func _draw_cybernetica_forge():
	# Ground Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
	draw_circle(Vector2(0, 4), 36.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Heavy Steel Factory Chassis (48x48 base)
	IsoDraw.box(self, Vector3(-24, -24, 0), Vector3(48, 48, 12), C_STEEL_DARK)
	IsoDraw.box(self, Vector3(-18, -18, 12), Vector3(36, 36, 8), C_MARS_RED)

	# Central Automata Assembly Chamber (Pulsing Cyan Core)
	var pulse = 0.65 + sin(idle_timer * 4.5) * 0.35
	IsoDraw.cylinder(self, Vector3(0, 0, 12), 14.0, 8.0, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, pulse))

	# Heavy Cyber-Crane Servo Gantry
	draw_line(Vector2(-14, -20), Vector2(-4, -36), C_STEEL_LIGHT, 3.5)
	draw_line(Vector2(-4, -36), Vector2(8, -28), C_BRASS, 2.5)

	# Opus Machina Sacred Cog Emblem
	IsoDraw.opus_machina_cog(self, Vector2(0, -6), 8.0, 8)

	# Purity Seals
	IsoDraw.purity_seal(self, IsoDraw.project(20, 0, 8), 7.0)
	IsoDraw.purity_seal(self, IsoDraw.project(-20, 0, 8), 7.0)

# ==============================================================================
# 9. UNSHADED GLOW LAYER
# ==============================================================================
class BuildingGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		match p.type:
			0: # Main Base
				var cog = IsoDraw.project(0, 0, 24)
				draw_circle(cog, 3.5, Color(0.20, 0.88, 1.0, 0.85))
				var door_p = IsoDraw.project(0, 20, 0)
				draw_circle(door_p - Vector2(0, 6), 6.0, Color(1.0, 0.7, 0.15, 0.4))
			1: # Generator Coils
				for i in range(3):
					var cx = -10.0 + (i * 10.0)
					var top_p = IsoDraw.project(cx, 0, 20)
					draw_circle(top_p, 2.5, Color(0.20, 0.88, 1.0, 0.9))
			3: # Turret (Targeting Telemetry Node Glow)
				var main_node = get_tree().get_first_node_in_group("main")
				var has_smart_uplink = p.is_noosphere_connected and not p.is_preview and (main_node.get("tech_targeting_uplink_unlocked") if main_node else false)
				if has_smart_uplink:
					# Glowing central cupola optic
					var base_h = 6.0 + (p.turret_upgrade_level * 2.0)
					var head_pos = IsoDraw.project(0, 0, base_h)
					draw_circle(head_pos, 2.5, Color(0.20, 0.88, 1.0, 0.95))
					draw_circle(head_pos, 1.0, Color.WHITE)
			5: # Antenna
				var mast = IsoDraw.project(0, 0, 22) + Vector2(0, -14)
				draw_circle(mast, 3.0, Color(0.20, 0.88, 1.0, 0.9))
			6: # Tech Shrine
				var sp = IsoDraw.project(0, 16, 6)
				draw_rect(Rect2(sp - Vector2(6, 2), Vector2(12, 4)), Color(0.25, 0.95, 0.40, 0.7))
			8: # Cybernetica Forge
				var core_top = IsoDraw.project(0, 0, 20)
				draw_circle(core_top, 4.0, Color(0.20, 0.88, 1.0, 0.90))
				draw_circle(core_top, 1.8, Color.WHITE)
