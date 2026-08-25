# res://MinimapUI.gd
extends Control

@export var corner_map_size: Vector2 = Vector2(210, 210)
@export var fullscreen_map_size: Vector2 = Vector2(740, 740)
@export var world_radius: float = 3600.0 # Covers full 7200x7200 map

var is_fullscreen: bool = false
var base_position: Vector2 = Vector2(500, 500)
var citadel_cached_pos: Vector2 = Vector2.ZERO
var has_citadel_pos: bool = false
var is_dragging_minimap: bool = false

# --- CLEAN MINIMALIST PALETTE ---
const COL_VOID_BG       := Color(0.04, 0.05, 0.07, 0.96)
const COL_FOG_EXPLORED  := Color(0.08, 0.10, 0.14, 0.85)
const COL_FOG_ACTIVE    := Color(0.09, 0.18, 0.23, 0.65)
const COL_BORDER_BRASS  := Color(0.75, 0.58, 0.24, 0.85)
const COL_CYAN_ACCENT   := Color(0.20, 0.88, 1.00)
const COL_AMBER_OFF     := Color(0.85, 0.22, 0.18, 0.85)

# Entities
const COL_PLAYER        := Color(0.35, 0.95, 0.45)
const COL_SCRAP_DEPOSIT := Color(1.00, 0.82, 0.20)
const COL_ENEMY_SIGHT   := Color(0.95, 0.20, 0.18)
const COL_CAM_BOX       := Color(1.00, 1.00, 1.00, 0.50)

# Minimalist Obstacles (Active Sight vs Memory Cache)
const COL_CRAG          := Color(0.55, 0.60, 0.68)
const COL_TREE          := Color(0.32, 0.55, 0.35)
const COL_RUIN          := Color(0.65, 0.48, 0.32)

func _ready() -> void:
	add_to_group("minimap_ui")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var mat = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func _process(_delta: float) -> void:
	queue_redraw()

func toggle_fullscreen_map() -> void:
	is_fullscreen = not is_fullscreen
	is_dragging_minimap = false
	queue_redraw()

func register_citadel_position(pos: Vector2) -> void:
	citadel_cached_pos = pos
	has_citadel_pos = true
	queue_redraw()

func _world_to_map(world_pos: Vector2, map_center: Vector2, map_radius_px: float) -> Vector2:
	var delta_pos = world_pos - base_position
	var norm_x = clampf(delta_pos.x / world_radius, -1.0, 1.0)
	var norm_y = clampf(delta_pos.y / world_radius, -1.0, 1.0)
	return map_center + Vector2(norm_x, norm_y) * map_radius_px

func _map_to_world(map_pos: Vector2, map_center: Vector2, map_radius_px: float) -> Vector2:
	var offset = map_pos - map_center
	var norm_x = clampf(offset.x / map_radius_px, -1.0, 1.0)
	var norm_y = clampf(offset.y / map_radius_px, -1.0, 1.0)
	return base_position + Vector2(norm_x * world_radius, norm_y * world_radius)

# ==============================================================================
# 1. INPUT & INTERACTION
# ==============================================================================
func _input(event: InputEvent) -> void:
	var vp_size = get_viewport_rect().size
	var map_rect: Rect2
	var map_center: Vector2
	var map_rad_px: float

	if is_fullscreen:
		map_rect = Rect2((vp_size - fullscreen_map_size) * 0.5, fullscreen_map_size)
		map_center = map_rect.position + (fullscreen_map_size * 0.5)
		map_rad_px = fullscreen_map_size.x * 0.48
	else:
		var margin = 24.0
		map_rect = Rect2(vp_size.x - corner_map_size.x - margin, vp_size.y - corner_map_size.y - margin, corner_map_size.x, corner_map_size.y)
		map_center = map_rect.position + (corner_map_size * 0.5)
		map_rad_px = corner_map_size.x * 0.48

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if map_rect.has_point(event.position):
				is_dragging_minimap = true
				_pan_camera_to_map_pos(event.position, map_center, map_rad_px)
				get_viewport().set_input_as_handled()
		else:
			if is_dragging_minimap:
				is_dragging_minimap = false
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and is_dragging_minimap:
		_pan_camera_to_map_pos(event.position, map_center, map_rad_px)
		get_viewport().set_input_as_handled()

func _pan_camera_to_map_pos(map_pos: Vector2, map_center: Vector2, map_rad_px: float) -> void:
	var target_world_pos = _map_to_world(map_pos, map_center, map_rad_px)
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and ((not multiplayer.has_multiplayer_peer()) or p.is_multiplayer_authority()):
			var cam = p.get_node_or_null("Camera2D") as Camera2D
			if is_instance_valid(cam):
				cam.top_level = true
				cam.global_position = target_world_pos
				break

# ==============================================================================
# 2. RENDER PIPELINE
# ==============================================================================
func _draw() -> void:
	var vp_size = get_viewport_rect().size
	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		base_position = base_node.global_position

	var main_node = get_tree().get_first_node_in_group("main")
	var radar_lvl: int = main_node.base_radar_level if is_instance_valid(main_node) and "base_radar_level" in main_node else 0
	var fow = get_tree().get_first_node_in_group("fog_of_war") as FogOfWar

	if is_fullscreen:
		_draw_fullscreen_tactical_map(vp_size, radar_lvl, fow)
	else:
		_draw_corner_radar_minimap(vp_size, radar_lvl, fow)

func _draw_corner_radar_minimap(vp_size: Vector2, radar_lvl: int, fow: FogOfWar) -> void:
	var margin = 24.0
	var map_rect = Rect2(vp_size.x - corner_map_size.x - margin, vp_size.y - corner_map_size.y - margin, corner_map_size.x, corner_map_size.y)
	var map_center = map_rect.position + (corner_map_size * 0.5)
	var map_rad_px = corner_map_size.x * 0.48
	var font = ThemeDB.fallback_font

	# 1. Seamless Clean 3-State Fog Base
	draw_rect(map_rect, COL_VOID_BG, true)
	if radar_lvl >= 1 and is_instance_valid(fow):
		_draw_clean_fog_base(map_rect, fow, 18)

	# 2. Minimalist Frame & Reticle
	draw_rect(map_rect, COL_BORDER_BRASS if radar_lvl > 0 else COL_AMBER_OFF, false, 1.2)
	_draw_minimal_reticle(map_rect, map_center, map_rad_px)

	# --- LEVEL 0: OFFLINE PROMPT ---
	if radar_lvl == 0:
		var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.006) * 0.3
		draw_rect(map_rect, Color(0.85, 0.18, 0.15, 0.06 * pulse), true)
		draw_string(font, map_rect.position + Vector2(12, map_rect.size.y * 0.46), "⚠️ AUSPEX OFFLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.22, 0.18, pulse))
		draw_string(font, map_rect.position + Vector2(12, map_rect.size.y * 0.58), "Sanctify Base [E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.75, 0.78, 0.82))
		return

	# --- LEVEL 1+: CLEAN ENTITIES & SWEEP ---
	_draw_clean_obstacles(map_center, map_rad_px, 1.0, fow, radar_lvl)
	_draw_clean_entities(map_center, map_rad_px, 1.0, radar_lvl, fow)
	_draw_subtle_radar_sweep(map_center, map_rad_px)

	var status_str = "AUSPEX T%d [M]" % radar_lvl
	draw_string(font, map_rect.position + Vector2(8, 14), status_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(COL_BORDER_BRASS.r, COL_BORDER_BRASS.g, COL_BORDER_BRASS.b, 0.8))

func _draw_fullscreen_tactical_map(vp_size: Vector2, radar_lvl: int, fow: FogOfWar) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.02, 0.03, 0.04, 0.88), true)

	var map_rect = Rect2((vp_size - fullscreen_map_size) * 0.5, fullscreen_map_size)
	var map_center = map_rect.position + (fullscreen_map_size * 0.5)
	var map_rad_px = fullscreen_map_size.x * 0.48
	var font = ThemeDB.fallback_font

	# 1. Seamless Clean 3-State Fog Base
	draw_rect(map_rect, COL_VOID_BG, true)
	if radar_lvl >= 1 and is_instance_valid(fow):
		_draw_clean_fog_base(map_rect, fow, 36)

	# 2. Minimalist Frame & Reticle
	draw_rect(map_rect, COL_CYAN_ACCENT if radar_lvl > 0 else COL_AMBER_OFF, false, 1.5)
	_draw_minimal_reticle(map_rect, map_center, map_rad_px)

	if radar_lvl == 0:
		var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.006) * 0.3
		draw_rect(map_rect, Color(0.85, 0.18, 0.15, 0.06 * pulse), true)
		draw_string(font, map_center + Vector2(-150, -10), "◆ AUSPEX OFFLINE — UPGRADE BASE CORE ◆", HORIZONTAL_ALIGNMENT_CENTER, 300, 12, Color(0.92, 0.22, 0.18, pulse))
		return

	# --- LEVEL 1+: FULL CLEAN TACTICAL MAP ---
	_draw_clean_obstacles(map_center, map_rad_px, 2.2, fow, radar_lvl)
	_draw_clean_entities(map_center, map_rad_px, 2.2, radar_lvl, fow)
	_draw_subtle_radar_sweep(map_center, map_rad_px)

	draw_string(font, map_rect.position + Vector2(16, 22), "◆ OMNISSIAN TACTICAL MAP (TIER %d) ◆ [M / ESC TO CLOSE]" % radar_lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_CYAN_ACCENT)
	draw_string(font, map_rect.position + Vector2(16, map_rect.size.y - 12), "🔵 BASE   🟢 SQUAD   🟡 SCRAP   ⛰️ CRAGS   🌲 GROVES   🔴 HOSTILES (DIRECT / FOG GHOST)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.70, 0.75, 0.80))

# ==============================================================================
# 3. CLEAN 3-STATE FOG OF WAR BACKDROP
# ==============================================================================
func _draw_clean_fog_base(map_rect: Rect2, fow: FogOfWar, resolution: int) -> void:
	var step_x = map_rect.size.x / float(resolution)
	var step_y = map_rect.size.y / float(resolution)

	for gy in range(resolution):
		var norm_y = ((float(gy) + 0.5) / float(resolution)) * 2.0 - 1.0
		var world_y = base_position.y + (norm_y * world_radius)
		var py = map_rect.position.y + (float(gy) * step_y)

		for gx in range(resolution):
			var norm_x = ((float(gx) + 0.5) / float(resolution)) * 2.0 - 1.0
			var world_x = base_position.x + (norm_x * world_radius)
			var px = map_rect.position.x + (float(gx) * step_x)
			var cell_world = Vector2(world_x, world_y)

			var is_visible = fow.is_world_pos_visible(cell_world)
			var is_explored = fow.is_world_pos_explored(cell_world)

			if is_visible:
				# Active Line of Sight (Smooth Phosphor Glow)
				draw_rect(Rect2(px, py, step_x + 0.5, step_y + 0.5), COL_FOG_ACTIVE)
			elif is_explored:
				# Shrouded Memory Cache (Dark Slate)
				draw_rect(Rect2(px, py, step_x + 0.5, step_y + 0.5), COL_FOG_EXPLORED)
			# Unexplored areas remain the clean deep void color (COL_VOID_BG)

# ==============================================================================
# 4. MINIMALIST OBSTACLES (CLEAN TOPOGRAPHICAL GLYPHS)
# ==============================================================================
func _draw_clean_obstacles(map_center: Vector2, map_rad_px: float, scale_mult: float, fow: FogOfWar, radar_lvl: int) -> void:
	for obs in get_tree().get_nodes_in_group("world_obstacles"):
		if not is_instance_valid(obs): continue

		var obs_pos: Vector2 = obs.global_position
		var is_explored = (fow and fow.is_world_pos_explored(obs_pos)) or (radar_lvl >= 3)
		if not is_explored: continue

		var in_sight = fow and fow.is_world_pos_visible(obs_pos)
		var mp = _world_to_map(obs_pos, map_center, map_rad_px)
		var obs_type = obs.get("obstacle_type") if "obstacle_type" in obs else 0
		var r = (obs.get("radius") / 20.0 if "radius" in obs else 2.0) * scale_mult

		match obs_type:
			0: # Mountain Crag (Minimalist Elevation Triangle ▲)
				var alpha = 0.85 if in_sight else 0.35
				var col = Color(COL_CRAG.r, COL_CRAG.g, COL_CRAG.b, alpha)
				var tri = [mp + Vector2(0, -r * 1.2), mp + Vector2(r, r * 0.8), mp + Vector2(-r, r * 0.8)]
				draw_colored_polygon(tri, col)

			1: # Ironwood Grove (Soft Stipple Dot •)
				var alpha = 0.80 if in_sight else 0.30
				draw_circle(mp, r * 0.85, Color(COL_TREE.r, COL_TREE.g, COL_TREE.b, alpha))

			2: # Industrial Ruin (Clean Minimalist Sector Box ■)
				var alpha = 0.85 if in_sight else 0.35
				var half = r * 0.85
				draw_rect(Rect2(mp - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), Color(COL_RUIN.r, COL_RUIN.g, COL_RUIN.b, alpha))

# ==============================================================================
# 5. CLEAN ENTITIES, SQUAD & HOSTILE FLIR CLOUDS
# ==============================================================================
func _draw_clean_entities(map_center: Vector2, map_rad_px: float, scale_mult: float, radar_lvl: int, fow: FogOfWar) -> void:
	# Scrap Deposits
	if radar_lvl >= 1:
		for dep in get_tree().get_nodes_in_group("scrap_deposits"):
			if is_instance_valid(dep):
				var is_seen = (fow and fow.is_world_pos_explored(dep.global_position)) or (radar_lvl >= 3)
				if is_seen:
					var p = _world_to_map(dep.global_position, map_center, map_rad_px)
					var in_sight = fow and fow.is_world_pos_visible(dep.global_position)
					draw_circle(p, 1.6 * scale_mult, COL_SCRAP_DEPOSIT if in_sight else Color(COL_SCRAP_DEPOSIT.r, COL_SCRAP_DEPOSIT.g, COL_SCRAP_DEPOSIT.b, 0.4))

		# Buildings & Barricades
		for b in get_tree().get_nodes_in_group("buildings"):
			if is_instance_valid(b) and not b.get("is_preview"):
				var p = _world_to_map(b.global_position, map_center, map_rad_px)
				var b_type = int(b.get("building_type")) if "building_type" in b else 0
				var col = COL_CYAN_ACCENT if b_type != 0 else Color(0.4, 0.6, 0.8, 0.7)
				draw_rect(Rect2(p - Vector2.ONE * (1.2 * scale_mult), Vector2.ONE * (2.4 * scale_mult)), col)

	# Main Base Core
	var base_p = _world_to_map(base_position, map_center, map_rad_px)
	draw_circle(base_p, 3.5 * scale_mult, COL_CYAN_ACCENT)
	draw_arc(base_p, 5.5 * scale_mult, 0, TAU, 16, COL_CYAN_ACCENT, 1.0)

	# Players & Camera Frustum
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p):
			var pp = _world_to_map(p.global_position, map_center, map_rad_px)
			draw_circle(pp, 2.8 * scale_mult, COL_PLAYER)
			draw_circle(pp, 1.0 * scale_mult, Color.WHITE)

			var cam = p.get_node_or_null("Camera2D") as Camera2D
			if is_instance_valid(cam) and radar_lvl >= 1:
				var vp_half = (get_viewport_rect().size * (1.0 / cam.zoom.x)) * 0.5
				var c1 = _world_to_map(cam.global_position - vp_half, map_center, map_rad_px)
				var c2 = _world_to_map(cam.global_position + vp_half, map_center, map_rad_px)
				draw_rect(Rect2(c1, c2 - c1), COL_CAM_BOX, false, 1.0)

	# Hostile Tracking (Direct Sight vs Heat Cloud Guesstimation)
	_draw_clean_hostiles(map_center, map_rad_px, scale_mult, radar_lvl, fow)

	# Objectives (Totems & Citadel)
	if radar_lvl >= 1:
		for idol in get_tree().get_nodes_in_group("waaagh_totems"):
			if is_instance_valid(idol) and ((fow and fow.is_world_pos_explored(idol.global_position)) or radar_lvl >= 3):
				var p = _world_to_map(idol.global_position, map_center, map_rad_px)
				draw_circle(p, 2.5 * scale_mult, Color(0.25, 0.95, 0.55))

		var cit = get_tree().get_first_node_in_group("ork_citadel")
		var cit_pos = cit.global_position if is_instance_valid(cit) else citadel_cached_pos
		if (is_instance_valid(cit) or has_citadel_pos) and ((fow and fow.is_world_pos_explored(cit_pos)) or radar_lvl >= 3):
			var cp = _world_to_map(cit_pos, map_center, map_rad_px)
			var pulse = 0.75 + sin(Time.get_ticks_msec() * 0.006) * 0.25
			draw_circle(cp, 4.5 * scale_mult, Color(1.0, 0.15, 0.15, 0.4 * pulse))
			draw_arc(cp, 7.0 * scale_mult, 0, TAU, 16, Color(1.0, 0.2, 0.2), 1.2)

# ==============================================================================
# 6. MINIMALIST HOSTILE HEAT-MAP CLOUDS
# ==============================================================================
func _draw_clean_hostiles(map_center: Vector2, map_rad_px: float, scale_mult: float, radar_lvl: int, fow: FogOfWar) -> void:
	var time_now = Time.get_ticks_msec()

	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e): continue
		if e.is_in_group("ork_citadel") or e.is_in_group("ork_structures") or e.is_in_group("objectives"): continue

		var is_direct_sight = fow and fow.is_world_pos_visible(e.global_position)
		var is_painted = e.get("has_telemetry_mark") == true

		if is_direct_sight or is_painted:
			# Direct Sight: Crisp Point Blip
			var ep = _world_to_map(e.global_position, map_center, map_rad_px)
			var r = (2.0 if e.get("type") in [4, 5] else 1.4) * scale_mult
			draw_circle(ep, r, COL_ENEMY_SIGHT)
			draw_circle(ep, r * 0.4, Color.WHITE)

			if is_painted:
				draw_arc(ep, r + 2.0, 0, TAU, 8, COL_CYAN_ACCENT, 1.0)

		elif radar_lvl >= 2:
			# Fog of War: Clean Soft Red Threat Glow (Naturally blends into horde clouds)
			var e_id = float(e.get_instance_id())
			var drift_angle = (time_now * 0.001) + (e_id * 1.37)
			var drift_dist = 45.0 + sin((time_now * 0.0015) + e_id) * 20.0
			var est_world = e.global_position + Vector2(cos(drift_angle), sin(drift_angle)) * drift_dist
			var est_map = _world_to_map(est_world, map_center, map_rad_px)

			var pulse = 0.7 + sin((time_now * 0.004) + e_id) * 0.3
			var cloud_r = (6.0 if e.get("type") in [4, 5] else 4.2) * scale_mult
			# Single soft, clean translucent alpha circle
			draw_circle(est_map, cloud_r, Color(0.92, 0.18, 0.15, 0.14 * pulse))
			draw_circle(est_map, cloud_r * 0.45, Color(1.0, 0.35, 0.25, 0.22 * pulse))

# ==============================================================================
# 7. MINIMALIST RADAR ACCENTS
# ==============================================================================
func _draw_minimal_reticle(map_rect: Rect2, map_center: Vector2, map_rad_px: float) -> void:
	# Subtle Crosshairs
	var col_faint = Color(0.20, 0.88, 1.0, 0.08)
	draw_line(Vector2(map_rect.position.x, map_center.y), Vector2(map_rect.end.x, map_center.y), col_faint, 1.0)
	draw_line(Vector2(map_center.x, map_rect.position.y), Vector2(map_center.x, map_rect.end.y), col_faint, 1.0)
	
	# Range Rings (50% & 100%)
	draw_arc(map_center, map_rad_px * 0.5, 0, TAU, 32, col_faint, 1.0)
	draw_arc(map_center, map_rad_px, 0, TAU, 40, col_faint, 1.0)

func _draw_subtle_radar_sweep(map_center: Vector2, map_rad_px: float) -> void:
	var sweep_angle = fposmod(Time.get_ticks_msec() * 0.0014, TAU)
	var sweep_end = map_center + Vector2(cos(sweep_angle), sin(sweep_angle)) * map_rad_px
	draw_line(map_center, sweep_end, Color(0.20, 0.88, 1.0, 0.25), 1.0)
