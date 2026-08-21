extends Control
class_name MinimapUI

const GameData = preload("res://GameData.gd")

var is_fullscreen_map: bool = false
var sweep_angle: float = 0.0
var world_size: Vector2 = Vector2(3000, 3000)

var detected_blips: Dictionary = {} # Node -> fade_timer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("minimap_ui")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float):
	sweep_angle = fmod(sweep_angle + delta * 2.5, TAU)
	
	# Fade sweep blips
	for k in detected_blips.keys():
		detected_blips[k] -= delta
		if detected_blips[k] <= 0.0:
			detected_blips.erase(k)

	queue_redraw()

func toggle_fullscreen_map():
	var main_node = get_tree().get_first_node_in_group("main")
	var radar_level = main_node.get("base_radar_level") if main_node else 0
	if radar_level < GameData.BaseRadarTier.TIER_1_CARTOGRAPH:
		return # Cannot open map without Cartograph upgrade!

	is_fullscreen_map = not is_fullscreen_map
	queue_redraw()

func _draw():
	var main_node = get_tree().get_first_node_in_group("main")
	var radar_tier = main_node.get("base_radar_level") if main_node else 0
	
	if radar_tier == GameData.BaseRadarTier.NONE:
		# Draw unlinked static prompt
		_draw_offline_hud()
		return

	if is_fullscreen_map:
		_draw_fullscreen_holo_map(radar_tier)
	else:
		_draw_corner_radar(radar_tier)

func _draw_offline_hud():
	var screen_size = get_viewport_rect().size
	var box_w = 160.0
	var box_h = 36.0
	var box_rect = Rect2(screen_size.x - box_w - 16, 12, box_w, box_h)
	
	draw_rect(box_rect, Color(0.04, 0.05, 0.08, 0.92), true)
	draw_rect(box_rect, Color(0.35, 0.40, 0.45, 0.75), false, 1.2)
	
	var font = ThemeDB.fallback_font
	draw_string(font, box_rect.position + Vector2(10, 22), "📡 AUSPEX OFFLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.70, 0.75, 0.80))

func _draw_corner_radar(radar_tier: int):
	var screen_size = get_viewport_rect().size
	var radar_size = Vector2(165, 165)
	var radar_rect = Rect2(screen_size.x - radar_size.x - 16, 12, radar_size.x, radar_size.y)
	var center = radar_rect.get_center()
	var radius = radar_size.x * 0.46

	# 1. Glass Radar Scope Background
	draw_circle(center, radius, Color(0.03, 0.06, 0.08, 0.90))
	draw_arc(center, radius, 0, TAU, 32, Color(0.20, 0.88, 1.0, 0.75), 1.5)
	draw_arc(center, radius * 0.66, 0, TAU, 24, Color(0.20, 0.88, 1.0, 0.25), 1.0)
	draw_arc(center, radius * 0.33, 0, TAU, 16, Color(0.20, 0.88, 1.0, 0.25), 1.0)
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(0.20, 0.88, 1.0, 0.2), 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color(0.20, 0.88, 1.0, 0.2), 1.0)

	# 2. Tier 2 Radar Sweep Line
	if radar_tier >= GameData.BaseRadarTier.TIER_2_AUSPEX:
		var sweep_dir = Vector2.RIGHT.rotated(sweep_angle)
		draw_line(center, center + sweep_dir * radius, Color(0.20, 0.95, 1.0, 0.85), 1.5)

	# 3. Render World Entities onto Minimap
	_render_entities_to_scope(center, radius, radar_tier, false)

func _draw_fullscreen_holo_map(radar_tier: int):
	var screen_size = get_viewport_rect().size
	var map_size = Vector2(600, 600)
	var map_rect = Rect2((screen_size - map_size) * 0.5, map_size)
	var center = map_rect.get_center()
	var radius = map_size.x * 0.46

	# Backdrop
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.02, 0.03, 0.05, 0.80), true)
	draw_rect(map_rect, Color(0.04, 0.07, 0.10, 0.95), true)
	draw_rect(map_rect, Color(0.20, 0.88, 1.0, 0.85), false, 2.0)

	var font = ThemeDB.fallback_font
	draw_string(font, map_rect.position + Vector2(16, 24), "◆ NOOSPHERIC BATTLEFIELD CARTOGRAPH [M to close] ◆", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.20, 0.88, 1.0))

	draw_circle(center, radius, Color(0.02, 0.05, 0.08, 0.5))
	draw_arc(center, radius, 0, TAU, 48, Color(0.20, 0.88, 1.0, 0.4), 1.2)
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(0.20, 0.88, 1.0, 0.15), 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color(0.20, 0.88, 1.0, 0.15), 1.0)

	_render_entities_to_scope(center, radius, radar_tier, true)

func _render_entities_to_scope(scope_center: Vector2, scope_radius: float, radar_tier: int, is_large: bool):
	var base_node = get_tree().get_first_node_in_group("base")
	var world_origin = base_node.global_position if is_instance_valid(base_node) else Vector2(500, 500)
	
	# Scale factor: covers 1900px radius across the wasteland
	var max_radar_world_range = 1900.0
	var scale_factor = scope_radius / max_radar_world_range

	# 1. Base Core
	draw_rect(Rect2(scope_center - Vector2(4, 4), Vector2(8, 8)), Color(0.20, 0.88, 1.0))

	# 2. Friendly Buildings & Foundries
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b):
			var local_pos = (b.global_position - world_origin) * scale_factor
			if local_pos.length() <= scope_radius:
				var b_type = int(b.get("building_type")) if "building_type" in b else 0
				var col = Color(0.95, 0.75, 0.20) if b_type == 3 else Color(0.20, 0.88, 1.0, 0.8)
				draw_circle(scope_center + local_pos, 2.5 if not is_large else 4.0, col)

	# 3. Scrap Ore Deposits
	for dep in get_tree().get_nodes_in_group("scrap_deposits"):
		if is_instance_valid(dep):
			var local_pos = (dep.global_position - world_origin) * scale_factor
			if local_pos.length() <= scope_radius:
				draw_circle(scope_center + local_pos, 2.0 if not is_large else 3.5, Color(0.78, 0.58, 0.22, 0.7))

	# 4. Players
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p):
			var local_pos = (p.global_position - world_origin) * scale_factor
			if local_pos.length() <= scope_radius:
				draw_circle(scope_center + local_pos, 3.5 if not is_large else 5.0, Color(0.25, 0.95, 0.40))

	# 5. Hostile Entities & Ork Strongholds (Tier 2/3 Radar)
	if radar_tier >= GameData.BaseRadarTier.TIER_2_AUSPEX:
		# Ork Citadel (Red Fort Marker)
		for cit in get_tree().get_nodes_in_group("ork_citadel"):
			if is_instance_valid(cit):
				var local_pos = (cit.global_position - world_origin) * scale_factor
				if local_pos.length() <= scope_radius:
					draw_rect(Rect2(scope_center + local_pos - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.15, 0.15))
					draw_rect(Rect2(scope_center + local_pos - Vector2(4, 4), Vector2(8, 8)), Color.WHITE, false, 1.0)

		# WAAAGH! Totems (Purple Skull Blips)
		for tot in get_tree().get_nodes_in_group("waaagh_totems"):
			if is_instance_valid(tot):
				var local_pos = (tot.global_position - world_origin) * scale_factor
				if local_pos.length() <= scope_radius:
					draw_circle(scope_center + local_pos, 3.5 if not is_large else 5.0, Color(0.85, 0.20, 0.95))
					draw_circle(scope_center + local_pos, 1.5, Color.WHITE)

		# Enemy Units
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and not e.is_in_group("objectives"):
				var local_pos = (e.global_position - world_origin) * scale_factor
				if local_pos.length() <= scope_radius:
					if radar_tier == GameData.BaseRadarTier.TIER_3_NOOSPHERE:
						draw_circle(scope_center + local_pos, 2.0 if not is_large else 3.0, Color(1.0, 0.25, 0.20))
					else:
						var to_blip_angle = fposmod(local_pos.angle(), TAU)
						if abs(angle_difference(sweep_angle, to_blip_angle)) < 0.12:
							detected_blips[e] = 1.6
						if detected_blips.has(e):
							var blip_alpha = detected_blips[e] / 1.6
							draw_circle(scope_center + local_pos, 2.2, Color(1.0, 0.25, 0.20, blip_alpha))
