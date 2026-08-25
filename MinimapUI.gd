# res://MinimapUI.gd
extends Control

@export var corner_map_size: Vector2 = Vector2(210, 210)
@export var fullscreen_map_size: Vector2 = Vector2(760, 760)
@export var world_radius: float = 3600.0 # Covers full 7200x7200 map

var is_fullscreen: bool = false
var base_position: Vector2 = Vector2(500, 500)
var citadel_cached_pos: Vector2 = Vector2.ZERO
var has_citadel_pos: bool = false
var is_dragging_minimap: bool = false

# Palette Constants
const COL_BG = Color(0.04, 0.05, 0.08, 0.92)
const COL_GRID = Color(0.20, 0.88, 1.0, 0.12)
const COL_BORDER = Color(0.82, 0.62, 0.24, 0.85)
const COL_BASE = Color(0.20, 0.88, 1.0, 1.0)
const COL_PLAYER = Color(0.35, 0.95, 0.45, 1.0)
const COL_SCRAP = Color(1.00, 0.82, 0.20, 0.85)
const COL_ENEMY = Color(0.92, 0.22, 0.18, 0.90)
const COL_CITADEL = Color(1.0, 0.15, 0.15, 1.0)
const COL_TOTEM = Color(0.25, 0.95, 0.55, 1.0)
const COL_CAM_BOX = Color(1.0, 1.0, 1.0, 0.65)
const COL_OFFLINE = Color(0.92, 0.22, 0.18, 0.85)

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

# Convert world coordinates into Minimap pixel coordinates
func _world_to_map(world_pos: Vector2, map_center: Vector2, map_radius_px: float) -> Vector2:
	var delta_pos = world_pos - base_position
	var norm_x = clampf(delta_pos.x / world_radius, -1.0, 1.0)
	var norm_y = clampf(delta_pos.y / world_radius, -1.0, 1.0)
	return map_center + Vector2(norm_x, norm_y) * map_radius_px

# Convert Minimap pixel coordinates back into World coordinates
func _map_to_world(map_pos: Vector2, map_center: Vector2, map_radius_px: float) -> Vector2:
	var offset = map_pos - map_center
	var norm_x = clampf(offset.x / map_radius_px, -1.0, 1.0)
	var norm_y = clampf(offset.y / map_radius_px, -1.0, 1.0)
	return base_position + Vector2(norm_x * world_radius, norm_y * world_radius)

# ==============================================================================
# RELIABLE GLOBAL INPUT HANDLING (Bypasses Control Sizing Limits)
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
		var margin = 24.0 # Match the 24px margin
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
				cam.top_level = true # Detach so camera can freely peek anywhere
				cam.global_position = target_world_pos
				break

# ==============================================================================
# VISUAL RENDERING
# ==============================================================================
func _draw() -> void:
	var vp_size = get_viewport_rect().size
	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		base_position = base_node.global_position

	var main_node = get_tree().get_first_node_in_group("main")
	var radar_lvl: int = main_node.base_radar_level if is_instance_valid(main_node) and "base_radar_level" in main_node else 0

	if is_fullscreen:
		_draw_fullscreen_tactical_map(vp_size, radar_lvl)
	else:
		_draw_corner_radar_minimap(vp_size, radar_lvl)

func _draw_corner_radar_minimap(vp_size: Vector2, radar_lvl: int) -> void:
	var margin = 24.0 # Increased from 16.0 for clean screen padding
	var map_rect = Rect2(vp_size.x - corner_map_size.x - margin, vp_size.y - corner_map_size.y - margin, corner_map_size.x, corner_map_size.y)
	var map_center = map_rect.position + (corner_map_size * 0.5)
	var map_rad_px = corner_map_size.x * 0.48
	var font = ThemeDB.fallback_font

	# Background & Frame
	draw_rect(map_rect, COL_BG, true)
	draw_rect(map_rect, COL_BORDER if radar_lvl > 0 else COL_OFFLINE, false, 1.5)

	# --- LEVEL 0: OFFLINE STATIC ---
	if radar_lvl == 0:
		var pulse = 0.6 + sin(Time.get_ticks_msec() * 0.008) * 0.4
		draw_rect(map_rect, Color(0.92, 0.22, 0.18, 0.08 * pulse), true)
		
		draw_line(Vector2(map_rect.position.x, map_center.y), Vector2(map_rect.end.x, map_center.y), Color(0.92, 0.22, 0.18, 0.25), 1.0)
		draw_line(Vector2(map_center.x, map_rect.position.y), Vector2(map_center.x, map_rect.end.y), Color(0.92, 0.22, 0.18, 0.25), 1.0)
		
		var base_p = _world_to_map(base_position, map_center, map_rad_px)
		draw_circle(base_p, 3.5, COL_BASE)
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p):
				draw_circle(_world_to_map(p.global_position, map_center, map_rad_px), 2.5, COL_PLAYER)

		draw_string(font, map_rect.position + Vector2(10, map_rect.size.y * 0.45), "⚠️ AUSPEX OFFLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.22, 0.18, 0.9 * pulse))
		draw_string(font, map_rect.position + Vector2(10, map_rect.size.y * 0.58), "Upgrade Base [E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 0.75, 0.65, 0.8))
		return

	# --- LEVEL 1+: ACTIVE RADAR RINGS ---
	draw_arc(map_center, map_rad_px * 0.33, 0, TAU, 24, COL_GRID, 1.0)
	draw_arc(map_center, map_rad_px * 0.66, 0, TAU, 32, COL_GRID, 1.0)
	draw_arc(map_center, map_rad_px, 0, TAU, 40, COL_GRID, 1.2)
	draw_line(Vector2(map_rect.position.x, map_center.y), Vector2(map_rect.end.x, map_center.y), COL_GRID, 1.0)
	draw_line(Vector2(map_center.x, map_rect.position.y), Vector2(map_center.x, map_rect.end.y), COL_GRID, 1.0)

	_draw_map_entities(map_center, map_rad_px, 1.0, radar_lvl)

	var status_str = "LVL %d AUSPEX [M]" % radar_lvl
	draw_string(font, map_rect.position + Vector2(6, 14), status_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.82, 0.62, 0.24, 0.85))

func _draw_fullscreen_tactical_map(vp_size: Vector2, radar_lvl: int) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.02, 0.03, 0.05, 0.90), true)

	var map_rect = Rect2((vp_size - fullscreen_map_size) * 0.5, fullscreen_map_size)
	var map_center = map_rect.position + (fullscreen_map_size * 0.5)
	var map_rad_px = fullscreen_map_size.x * 0.48
	var font = ThemeDB.fallback_font

	draw_rect(map_rect, Color(0.04, 0.05, 0.08, 0.96), true)
	draw_rect(map_rect, Color(0.20, 0.88, 1.0, 0.85) if radar_lvl > 0 else COL_OFFLINE, false, 2.0)

	# --- LEVEL 0: OFFLINE HOLO WARNING ---
	if radar_lvl == 0:
		var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.006) * 0.3
		draw_rect(map_rect, Color(0.92, 0.22, 0.18, 0.06 * pulse), true)

		var title = "◆ TACTICAL HOLOMAP OFFLINE ◆"
		draw_string(font, map_center + Vector2(-160, -30), title, HORIZONTAL_ALIGNMENT_CENTER, 320, 16, Color(0.92, 0.22, 0.18, pulse))
		
		var desc = "Sanctum Auspex array requires power restoration.\nInteract with the Main Base [E] and research Auspex Radar Level 1."
		draw_string(font, map_center + Vector2(-220, 10), desc, HORIZONTAL_ALIGNMENT_CENTER, 440, 11, Color(0.85, 0.88, 0.94, 0.85))
		
		draw_string(font, map_rect.position + Vector2(16, map_rect.size.y - 14), "[M / ESC TO CLOSE]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.60, 0.50))
		return

	# --- LEVEL 1+: HOLOGRAPHIC GRID ---
	for i in range(1, 5):
		draw_arc(map_center, map_rad_px * (float(i) / 4.0), 0, TAU, 48, Color(0.20, 0.88, 1.0, 0.15), 1.0)
	draw_line(Vector2(map_rect.position.x, map_center.y), Vector2(map_rect.end.x, map_center.y), Color(0.20, 0.88, 1.0, 0.25), 1.0)
	draw_line(Vector2(map_center.x, map_rect.position.y), Vector2(map_center.x, map_rect.end.y), Color(0.20, 0.88, 1.0, 0.25), 1.0)

	_draw_map_entities(map_center, map_rad_px, 2.4, radar_lvl)

	var header_txt = "◆ OMNISSIAN TACTICAL HOLO-AUSPEX (RADAR LVL %d) ◆ [M / ESC TO CLOSE]" % radar_lvl
	draw_string(font, map_rect.position + Vector2(16, 24), header_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.20, 0.88, 1.0))

	var legend_txt = "🔵 SANCTUM  |  🟢 CADRE  |  🟡 SCRAP"
	if radar_lvl >= 2: legend_txt += "  |  🔴 ENEMY BLIPS"
	if radar_lvl >= 3: legend_txt += "  |  💀 ORK CITADEL  |  💎 WAAAGH! IDOLS"
	draw_string(font, map_rect.position + Vector2(16, map_rect.size.y - 12), legend_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.82, 0.75, 0.60))

func _draw_map_entities(map_center: Vector2, map_rad_px: float, scale_mult: float, radar_lvl: int) -> void:
	# -------------------------------------------------------------------------
	# RADAR LEVEL 1+: Resource Deposits, Friendly Buildings, Base, Players
	# -------------------------------------------------------------------------
	if radar_lvl >= 1:
		for dep in get_tree().get_nodes_in_group("scrap_deposits"):
			if is_instance_valid(dep):
				var p = _world_to_map(dep.global_position, map_center, map_rad_px)
				draw_circle(p, 2.2 * scale_mult, COL_SCRAP)

		for b in get_tree().get_nodes_in_group("buildings"):
			if is_instance_valid(b) and not b.get("is_preview"):
				var p = _world_to_map(b.global_position, map_center, map_rad_px)
				var b_type = int(b.get("building_type")) if "building_type" in b else 0
				var b_col = COL_BASE if b_type != 0 else Color(0.35, 0.55, 0.75, 0.8)
				draw_rect(Rect2(p - Vector2.ONE * scale_mult, Vector2.ONE * 2.0 * scale_mult), b_col)

	# Base Core Sanctum
	var base_p = _world_to_map(base_position, map_center, map_rad_px)
	draw_circle(base_p, 4.0 * scale_mult, COL_BASE)
	draw_arc(base_p, 6.0 * scale_mult, 0, TAU, 16, COL_BASE, 1.2)

	# Players & Camera Viewport Box
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p):
			var pp = _world_to_map(p.global_position, map_center, map_rad_px)
			draw_circle(pp, 3.2 * scale_mult, COL_PLAYER)
			
			var cam = p.get_node_or_null("Camera2D") as Camera2D
			if is_instance_valid(cam) and radar_lvl >= 1:
				var vp_half = (get_viewport_rect().size * (1.0 / cam.zoom.x)) * 0.5
				var cam_p1 = _world_to_map(cam.global_position - vp_half, map_center, map_rad_px)
				var cam_p2 = _world_to_map(cam.global_position + vp_half, map_center, map_rad_px)
				draw_rect(Rect2(cam_p1, cam_p2 - cam_p1), COL_CAM_BOX, false, 1.2 * scale_mult)

	# -------------------------------------------------------------------------
	# RADAR LEVEL 2+: Real-Time Enemy Horde Blips
	# -------------------------------------------------------------------------
	if radar_lvl >= 2:
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e):
				var ep = _world_to_map(e.global_position, map_center, map_rad_px)
				draw_circle(ep, 1.5 * scale_mult, COL_ENEMY)

	# -------------------------------------------------------------------------
	# RADAR LEVEL 3+: Global Threat Telemetry (Ork Citadel & WAAAGH! Totems)
	# -------------------------------------------------------------------------
	if radar_lvl >= 3:
		for idol in get_tree().get_nodes_in_group("waaagh_totems"):
			if is_instance_valid(idol):
				var p = _world_to_map(idol.global_position, map_center, map_rad_px)
				var diamond = [
					p + Vector2(0, -4.5 * scale_mult),
					p + Vector2(4.5 * scale_mult, 0),
					p + Vector2(0, 4.5 * scale_mult),
					p + Vector2(-4.5 * scale_mult, 0)
				]
				draw_colored_polygon(diamond, COL_TOTEM)

		var cit = get_tree().get_first_node_in_group("ork_citadel")
		var cit_pos = cit.global_position if is_instance_valid(cit) else citadel_cached_pos

		if is_instance_valid(cit) or has_citadel_pos:
			var cp = _world_to_map(cit_pos, map_center, map_rad_px)
			var pulse = 0.75 + sin(Time.get_ticks_msec() * 0.008) * 0.25
			
			draw_circle(cp, 5.0 * scale_mult, Color(1.0, 0.15, 0.15, 0.35))
			draw_arc(cp, 8.0 * scale_mult * pulse, 0, TAU, 24, COL_CITADEL, 1.5)
			draw_arc(cp, 13.0 * scale_mult * (1.2 - pulse * 0.2), 0, TAU, 24, Color(1.0, 0.2, 0.2, 0.5), 1.0)
			
			draw_line(cp - Vector2(3, 3) * scale_mult, cp + Vector2(3, 3) * scale_mult, Color.WHITE, 1.5)
			draw_line(cp - Vector2(-3, 3) * scale_mult, cp + Vector2(-3, 3) * scale_mult, Color.WHITE, 1.5)

			if is_fullscreen:
				var font = ThemeDB.fallback_font
				draw_string(font, cp + Vector2(-32, -16 * scale_mult), "💀 ORK CITADEL", HORIZONTAL_ALIGNMENT_CENTER, 64, 8, COL_CITADEL)
