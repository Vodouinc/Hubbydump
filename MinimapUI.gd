extends Control
class_name MinimapUI

const GameData = preload("res://GameData.gd")

var is_fullscreen_map: bool = false
var sweep_angle: float = 0.0
var world_size: Vector2 = Vector2(3000, 3000)

var detected_blips: Dictionary = {}
var is_waaagh_gauge_hovered: bool = false

# Custom WAAAGH! Telemetry Hover Tooltip
var waaagh_tooltip: PanelContainer = null
var waaagh_title_lbl: Label = null
var waaagh_sub_lbl: Label = null
var waaagh_stats_lbl: Label = null
var waaagh_lore_lbl: Label = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("minimap_ui")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_setup_waaagh_tooltip()

func _setup_waaagh_tooltip():
	waaagh_tooltip = PanelContainer.new()
	waaagh_tooltip.name = "WaaaghTooltip"
	waaagh_tooltip.custom_minimum_size = Vector2(310, 0)
	waaagh_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.96)
	sb.border_color = Color(0.35, 0.95, 0.15)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.65)
	sb.shadow_size = 6
	waaagh_tooltip.add_theme_stylebox_override("panel", sb)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	waaagh_tooltip.add_child(vbox)

	waaagh_title_lbl = Label.new()
	waaagh_title_lbl.name = "Title"
	waaagh_title_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.15))
	waaagh_title_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(waaagh_title_lbl)

	waaagh_sub_lbl = Label.new()
	waaagh_sub_lbl.name = "Sub"
	waaagh_sub_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	waaagh_sub_lbl.add_theme_font_size_override("font_size", 9)
	vbox.add_child(waaagh_sub_lbl)

	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.25, 0.28, 0.35, 0.6)
	vbox.add_child(sep)

	waaagh_stats_lbl = Label.new()
	waaagh_stats_lbl.name = "Stats"
	waaagh_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	waaagh_stats_lbl.add_theme_color_override("font_color", Color(0.90, 0.92, 0.96))
	waaagh_stats_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(waaagh_stats_lbl)

	waaagh_lore_lbl = Label.new()
	waaagh_lore_lbl.name = "Lore"
	waaagh_lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	waaagh_lore_lbl.add_theme_color_override("font_color", Color(0.68, 0.72, 0.65))
	waaagh_lore_lbl.add_theme_font_size_override("font_size", 9)
	vbox.add_child(waaagh_lore_lbl)

	add_child(waaagh_tooltip)
	waaagh_tooltip.hide()

func _process(delta: float):
	sweep_angle = fmod(sweep_angle + delta * 2.5, TAU)
	
	for k in detected_blips.keys():
		detected_blips[k] -= delta
		if detected_blips[k] <= 0.0:
			detected_blips.erase(k)

	_check_waaagh_mouse_hover()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var screen_size = get_viewport_rect().size
		var radar_size = Vector2(165, 165)
		var radar_rect = Rect2(screen_size.x - radar_size.x - 16, 12, radar_size.x, radar_size.y)

		if radar_rect.has_point(event.position):
			var center = radar_rect.get_center()
			var radius = radar_size.x * 0.46
			var click_offset = event.position - center

			if click_offset.length() <= radius:
				var max_radar_world_range = 1900.0
				var scale_factor = radius / max_radar_world_range
				
				var base_node = get_tree().get_first_node_in_group("base")
				var world_origin = base_node.global_position if is_instance_valid(base_node) else Vector2(500, 500)
				var target_world_pos = world_origin + (click_offset / scale_factor)

				var player = _get_local_player()
				if player:
					if event.button_index == MOUSE_BUTTON_LEFT:
						# Jump RTS Camera
						if is_instance_valid(player.get_node_or_null("Camera2D")):
							player.get_node("Camera2D").global_position = target_world_pos
					elif event.button_index == MOUSE_BUTTON_RIGHT and player.current_class == 1:
						# Send Move Order to Selected Units
						player._issue_order_to_selection(target_world_pos, false)

				accept_event()

func _get_local_player() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and ((not multiplayer.has_multiplayer_peer()) or p.is_multiplayer_authority()):
			return p
	return null

func _check_waaagh_mouse_hover():
	var main_node = get_tree().get_first_node_in_group("main")
	var is_waaagh_unlocked = main_node.tech_waaagh_reader_unlocked if (main_node and "tech_waaagh_reader_unlocked" in main_node) else false
	if not is_waaagh_unlocked:
		if waaagh_tooltip: waaagh_tooltip.hide()
		return

	var screen_size = get_viewport_rect().size
	var gauge_rect = Rect2(screen_size.x - 290, 12, 110, 42)
	var mouse_pos = get_local_mouse_position()

	var was_hovered = is_waaagh_gauge_hovered
	is_waaagh_gauge_hovered = gauge_rect.has_point(mouse_pos)

	if is_waaagh_gauge_hovered:
		_update_waaagh_tooltip_content(gauge_rect)
		waaagh_tooltip.show()
	elif was_hovered:
		waaagh_tooltip.hide()

func _update_waaagh_tooltip_content(gauge_rect: Rect2):
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not is_instance_valid(waaagh_title_lbl): return

	var totems = main_node.get_active_totem_count() if main_node.has_method("get_active_totem_count") else 0
	var spd_buff = int(totems * 12)
	var dmg_buff = int(totems * 10)

	waaagh_title_lbl.text = "◆ WAAAGH! PSYCHIC FIELD TELEMETRY ◆"
	waaagh_sub_lbl.text = "THREAT LEVEL: %s (%d ACTIVE TOTEMS)" % [("DORMANT" if totems == 0 else "CRITICAL PHASE %d" % totems), totems]
	
	if totems > 0:
		waaagh_stats_lbl.text = "• +%d%% Hostile Movement & Charge Speed\n• +%d%% Hostile Melee & Weapon Damage\n• +25%% Horde Spawn Frequency\n\nTACTICAL ADVICE: Dispatch sorties across the desert to destroy WAAAGH! Idols and suppress enemy buffs." % [spd_buff, dmg_buff]
	else:
		waaagh_stats_lbl.text = "No active WAAAGH! Totems detected. Hostile psychic gestalt is currently dormant.\n\nKeep radar sweeps active to detect newly manifested shrines."

	waaagh_lore_lbl.text = "\"The psychic wavelength of the greenskin burns across the ether like a toxic flare. Silence their crude shrines.\" — Magos Biologis"

	waaagh_tooltip.global_position = Vector2(gauge_rect.position.x - waaagh_tooltip.size.x - 8, gauge_rect.position.y)

func toggle_fullscreen_map():
	var main_node = get_tree().get_first_node_in_group("main")
	var radar_level = main_node.base_radar_level if (main_node and "base_radar_level" in main_node) else 0
	if radar_level < 1: return
	is_fullscreen_map = not is_fullscreen_map
	queue_redraw()

func _draw():
	var main_node = get_tree().get_first_node_in_group("main")
	var radar_tier = main_node.base_radar_level if (main_node and "base_radar_level" in main_node) else 0
	var waaagh_unlocked = main_node.tech_waaagh_reader_unlocked if (main_node and "tech_waaagh_reader_unlocked" in main_node) else false
	
	# 1. Draw WAAAGH! Companion Widget (By Minimap) if researched
	if waaagh_unlocked:
		_draw_waaagh_minimap_widget()

	# 2. Draw Radar / Cartograph
	if radar_tier == 0:
		_draw_offline_hud()
		return

	if is_fullscreen_map:
		_draw_fullscreen_holo_map(radar_tier)
	else:
		_draw_corner_radar(radar_tier)

func _draw_waaagh_minimap_widget():
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return

	var screen_size = get_viewport_rect().size
	var totems = main_node.get_active_totem_count() if main_node.has_method("get_active_totem_count") else 0
	var spd_buff = int(totems * 12)

	var widget_rect = Rect2(screen_size.x - 290, 12, 110, 42)
	var bg_color = Color(0.04, 0.05, 0.08, 0.94)
	var border_color = Color(0.35, 0.95, 0.15, 0.8) if totems > 0 else Color(0.30, 0.35, 0.40, 0.8)

	if is_waaagh_gauge_hovered:
		border_color = Color(1.0, 0.85, 0.20)

	# Widget Frame
	draw_rect(widget_rect, bg_color, true)
	draw_rect(widget_rect, border_color, false, 1.2)

	var font = ThemeDB.fallback_font
	var header_color = Color(0.35, 0.95, 0.15) if totems > 0 else Color(0.60, 0.65, 0.70)
	draw_string(font, widget_rect.position + Vector2(6, 14), "🔥 WAAAGH!", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, header_color)

	# Buff / Status
	var status_str = "+%d%% SPD" % spd_buff if totems > 0 else "DORMANT"
	var status_col = Color(1.0, 0.85, 0.20) if totems > 0 else Color(0.50, 0.55, 0.60)
	draw_string(font, widget_rect.position + Vector2(widget_rect.size.x - 62, 14), status_str, HORIZONTAL_ALIGNMENT_RIGHT, 56, 8, status_col)

	# Active Totem Pips
	var pips_origin = widget_rect.position + Vector2(10, 28)
	var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.006) * 0.3
	for i in range(5):
		var p_pos = pips_origin + Vector2(i * 18.0, 0)
		if i < totems:
			draw_circle(p_pos, 3.2, Color(0.35, 0.95, 0.15, 0.9 * pulse))
			draw_circle(p_pos, 1.2, Color.WHITE)
		else:
			draw_circle(p_pos, 2.0, Color(0.20, 0.22, 0.25))

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

	draw_circle(center, radius, Color(0.03, 0.06, 0.08, 0.90))
	draw_arc(center, radius, 0, TAU, 32, Color(0.20, 0.88, 1.0, 0.75), 1.5)
	draw_arc(center, radius * 0.66, 0, TAU, 24, Color(0.20, 0.88, 1.0, 0.25), 1.0)
	draw_arc(center, radius * 0.33, 0, TAU, 16, Color(0.20, 0.88, 1.0, 0.25), 1.0)
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(0.20, 0.88, 1.0, 0.2), 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color(0.20, 0.88, 1.0, 0.2), 1.0)

	if radar_tier >= 2:
		var sweep_dir = Vector2.RIGHT.rotated(sweep_angle)
		draw_line(center, center + sweep_dir * radius, Color(0.20, 0.95, 1.0, 0.85), 1.5)

	_render_entities_to_scope(center, radius, radar_tier, false)

func _draw_fullscreen_holo_map(radar_tier: int):
	var screen_size = get_viewport_rect().size
	var map_size = Vector2(600, 600)
	var map_rect = Rect2((screen_size - map_size) * 0.5, map_size)
	var center = map_rect.get_center()
	var radius = map_size.x * 0.46

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
	var max_radar_world_range = 1900.0
	var scale_factor = scope_radius / max_radar_world_range

	draw_rect(Rect2(scope_center - Vector2(4, 4), Vector2(8, 8)), Color(0.20, 0.88, 1.0))

	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b):
			var local_pos = (b.global_position - world_origin) * scale_factor
			if local_pos.length() <= scope_radius:
				var b_type = int(b.get("building_type")) if "building_type" in b else 0
				var col = Color(0.95, 0.75, 0.20) if b_type == 3 else Color(0.20, 0.88, 1.0, 0.8)
				draw_circle(scope_center + local_pos, 2.5 if not is_large else 4.0, col)

	for dep in get_tree().get_nodes_in_group("scrap_deposits"):
		if is_instance_valid(dep):
			var local_pos = (dep.global_position - world_origin) * scale_factor
			if local_pos.length() <= scope_radius:
				draw_circle(scope_center + local_pos, 2.0 if not is_large else 3.5, Color(0.78, 0.58, 0.22, 0.7))

	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p):
			var local_pos = (p.global_position - world_origin) * scale_factor
			if local_pos.length() <= scope_radius:
				draw_circle(scope_center + local_pos, 3.5 if not is_large else 5.0, Color(0.25, 0.95, 0.40))

	if radar_tier >= 2:
		for cit in get_tree().get_nodes_in_group("ork_citadel"):
			if is_instance_valid(cit):
				var local_pos = (cit.global_position - world_origin) * scale_factor
				if local_pos.length() <= scope_radius:
					draw_rect(Rect2(scope_center + local_pos - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.15, 0.15))

		for tot in get_tree().get_nodes_in_group("waaagh_totems"):
			if is_instance_valid(tot):
				var local_pos = (tot.global_position - world_origin) * scale_factor
				if local_pos.length() <= scope_radius:
					draw_circle(scope_center + local_pos, 3.5 if not is_large else 5.0, Color(0.85, 0.20, 0.95))

		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and not e.is_in_group("objectives"):
				var local_pos = (e.global_position - world_origin) * scale_factor
				if local_pos.length() <= scope_radius:
					if radar_tier >= 3:
						draw_circle(scope_center + local_pos, 2.0 if not is_large else 3.0, Color(1.0, 0.25, 0.20))
					else:
						var to_blip_angle = fposmod(local_pos.angle(), TAU)
						if abs(angle_difference(sweep_angle, to_blip_angle)) < 0.12:
							detected_blips[e] = 1.6
						if detected_blips.has(e):
							draw_circle(scope_center + local_pos, 2.2, Color(1.0, 0.25, 0.20, detected_blips[e] / 1.6))
