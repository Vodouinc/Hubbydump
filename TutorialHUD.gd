# res://TutorialHUD.gd
extends Control
class_name TutorialHUD

const SETTINGS_FILE = "user://tutorial_settings.cfg"

var log_panel: PanelContainer

# Section 1: Tutorial Directives
var tut_section: VBoxContainer
var tut_title_lbl: Label
var tut_task_lbl: Label
var skip_btn: Button

# Section 2: Primary Objectives
var primary_wave_lbl: Label
var primary_citadel_lbl: Label

# Section 3: Bonus / Tactical Objectives
var bonus_stc_lbl: Label
var bonus_outposts_lbl: Label

var current_step_index: int = 0
var current_quests: Array[Dictionary] = []
var permanently_skipped: bool = false
var session_tutorial_completed: bool = false
var active_class_id: int = 0
var local_player: Node2D = null

var active_beacon_node: Node2D = null
var is_step_completed: bool = false
var auto_advance_timer: float = 0.0

# Initial cached states for tracking quest triggers
var initial_building_count: int = 0
var initial_bodyguard_count: int = 0
var initial_skull_count: int = 0
var initial_doctrina_state: int = -1

# ==============================================================================
# CLASS-SPECIFIC TUTORIAL QUEST DEFINITIONS
# ==============================================================================

const QUESTS_TECHPRIEST: Array[Dictionary] = [
	{
		"id": "tp_move",
		"task": "Move into marked beacon [W][A][S][D]",
		"type": "BEACON",
		"offset": Vector2(-150, 70)
	},
	{
		"id": "tp_combat",
		"task": "Perform weapon attack [LMB / RMB]",
		"type": "ATTACK"
	},
	{
		"id": "tp_build",
		"task": "Construct a structure [B / 1-7]",
		"type": "BUILD"
	},
	{
		"id": "tp_servo",
		"task": "Deploy Servo-Skull repair drone [C]",
		"type": "SERVO_SKULL"
	},
	{
		"id": "tp_map",
		"task": "Open Map [M] or access Base [E]",
		"type": "MAP_OR_BASE"
	}
]

const QUESTS_MARSHAL: Array[Dictionary] = [
	{
		"id": "sm_move",
		"task": "Box-Select [LMB] & Move [RMB] to beacon",
		"type": "BEACON",
		"offset": Vector2(160, -70)
	},
	{
		"id": "sm_doctrina",
		"task": "Shift Doctrina Imperative aura [Q]",
		"type": "DOCTRINA"
	},
	{
		"id": "sm_recruit",
		"task": "Recruit cohort bodyguard [Z / X / C]",
		"type": "RECRUIT"
	},
	{
		"id": "sm_uplink",
		"task": "Transmit Orbital Supply Uplink [V]",
		"type": "SUPPLY_UPLINK"
	},
	{
		"id": "sm_map_jump",
		"task": "Open Map [M] or Left-Click Radar",
		"type": "MAP_JUMP"
	}
]

# ==============================================================================
# LIFECYCLE & LAYOUT
# ==============================================================================

func _ready() -> void:
	add_to_group("tutorial_hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_settings()
	_build_ui()
	_update_layout_position()

func _load_settings():
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK:
		# Reset to false if not explicitly permanently skipped
		permanently_skipped = cfg.get_value("tutorial", "permanently_skipped", false)

func _save_settings():
	var cfg = ConfigFile.new()
	cfg.set_value("tutorial", "permanently_skipped", permanently_skipped)
	cfg.save(SETTINGS_FILE)

func start_tutorial_for_class(class_id: int):
	active_class_id = class_id
	current_quests = QUESTS_TECHPRIEST if class_id == 0 else QUESTS_MARSHAL
	current_step_index = 0
	session_tutorial_completed = false
	is_step_completed = false
	
	_find_local_player()
	_cache_initial_states()

	if not permanently_skipped:
		if is_instance_valid(tut_section):
			tut_section.show()
		_setup_current_quest()
	else:
		if is_instance_valid(tut_section):
			tut_section.hide()

	show()

func _find_local_player():
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and ((not multiplayer.has_multiplayer_peer()) or p.is_multiplayer_authority()):
			local_player = p
			break

func _cache_initial_states():
	initial_building_count = get_tree().get_nodes_in_group("buildings").size()
	initial_bodyguard_count = get_tree().get_nodes_in_group("bodyguards").size()
	initial_skull_count = get_tree().get_nodes_in_group("ServoSkull").size()
	if is_instance_valid(local_player) and "active_doctrina" in local_player:
		initial_doctrina_state = local_player.active_doctrina

func _process(delta: float) -> void:
	_update_layout_position()
	_refresh_campaign_objectives()

	if not visible or session_tutorial_completed or permanently_skipped or current_quests.is_empty():
		return

	if not is_instance_valid(local_player):
		_find_local_player()
		return

	if is_step_completed:
		auto_advance_timer -= delta
		if auto_advance_timer <= 0.0:
			_advance_to_next_quest()
		return

	_evaluate_tutorial_quest()

func _update_layout_position():
	# DOCKED DIRECTLY UNDER TOP-LEFT RESOURCE RIBBON
	if is_instance_valid(log_panel):
		log_panel.position = Vector2(12.0, 42.0)

# ==============================================================================
# UI CONSTRUCTION (CLEAN & COMPACT DIRECTIVE LOG)
# ==============================================================================

func _build_ui():
	for c in get_children(): c.queue_free()

	log_panel = PanelContainer.new()
	log_panel.name = "DirectivesLogPanel"
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.custom_minimum_size = Vector2(230, 0)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.90)
	sb.border_color = Color(0.24, 0.28, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	log_panel.add_theme_stylebox_override("panel", sb)
	add_child(log_panel)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 5)
	log_panel.add_child(root_vbox)

	# --- 1. TUTORIAL SECTION ---
	tut_section = VBoxContainer.new()
	tut_section.name = "TutorialSection"
	tut_section.add_theme_constant_override("separation", 2)
	root_vbox.add_child(tut_section)

	var tut_header_hbox = HBoxContainer.new()
	tut_section.add_child(tut_header_hbox)

	tut_title_lbl = Label.new()
	tut_title_lbl.text = "🎓 TUTORIAL (1/5)"
	tut_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut_title_lbl.add_theme_font_size_override("font_size", 8)
	tut_title_lbl.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
	tut_header_hbox.add_child(tut_title_lbl)

	skip_btn = Button.new()
	skip_btn.text = "✕ SKIP"
	skip_btn.custom_minimum_size = Vector2(42, 16)
	skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	skip_btn.add_theme_font_size_override("font_size", 7)
	skip_btn.pressed.connect(_on_skip_all_pressed)
	tut_header_hbox.add_child(skip_btn)

	tut_task_lbl = Label.new()
	tut_task_lbl.text = "● Move into marked beacon"
	tut_task_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_task_lbl.add_theme_font_size_override("font_size", 8)
	tut_task_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	tut_section.add_child(tut_task_lbl)

	var sep1 = ColorRect.new()
	sep1.name = "TutSep"
	sep1.custom_minimum_size = Vector2(0, 1)
	sep1.color = Color(0.25, 0.30, 0.38, 0.4)
	tut_section.add_child(sep1)

	# --- 2. PRIMARY WIN-CONDITION OBJECTIVES ---
	var prim_title = Label.new()
	prim_title.text = "◆ PRIMARY DIRECTIVES ◆"
	prim_title.add_theme_font_size_override("font_size", 8)
	prim_title.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	root_vbox.add_child(prim_title)

	primary_wave_lbl = Label.new()
	primary_wave_lbl.text = "[ ] Defend Forge: Wave 01/15"
	primary_wave_lbl.add_theme_font_size_override("font_size", 8)
	primary_wave_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	root_vbox.add_child(primary_wave_lbl)

	primary_citadel_lbl = Label.new()
	primary_citadel_lbl.text = "[ ] Slay Warboss / Destroy Citadel"
	primary_citadel_lbl.add_theme_font_size_override("font_size", 8)
	primary_citadel_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	root_vbox.add_child(primary_citadel_lbl)

	var sep2 = ColorRect.new()
	sep2.custom_minimum_size = Vector2(0, 1)
	sep2.color = Color(0.25, 0.30, 0.38, 0.4)
	root_vbox.add_child(sep2)

	# --- 3. BONUS & EXPLORATION OBJECTIVES ---
	var bonus_title = Label.new()
	bonus_title.text = "◆ TACTICAL EXPEDITION ◆"
	bonus_title.add_theme_font_size_override("font_size", 8)
	bonus_title.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
	root_vbox.add_child(bonus_title)

	bonus_stc_lbl = Label.new()
	bonus_stc_lbl.text = "[ ] Recover STC Relics (0/2)"
	bonus_stc_lbl.add_theme_font_size_override("font_size", 8)
	bonus_stc_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.85))
	root_vbox.add_child(bonus_stc_lbl)

	bonus_outposts_lbl = Label.new()
	bonus_outposts_lbl.text = "[ ] Cripple Outposts (0/3)"
	bonus_outposts_lbl.add_theme_font_size_override("font_size", 8)
	bonus_outposts_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.85))
	root_vbox.add_child(bonus_outposts_lbl)

# ==============================================================================
# LIVE TRACKING FOR CAMPAIGN & TUTORIALS
# ==============================================================================

func _refresh_campaign_objectives():
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return

	# 1. Primary: Wave Defense Status
	var cur_w = main_node.get("current_wave") if "current_wave" in main_node else 1
	var max_w = main_node.get("max_waves") if "max_waves" in main_node else 15
	if is_instance_valid(primary_wave_lbl):
		if cur_w > max_w:
			primary_wave_lbl.text = "[✓] Forge Defended (15/15)"
			primary_wave_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
		else:
			primary_wave_lbl.text = "[ ] Defend Forge: Wave %02d/%02d" % [cur_w, max_w]

	# 2. Primary: Citadel / Warboss Status
	var citadel = get_tree().get_first_node_in_group("ork_citadel")
	if is_instance_valid(primary_citadel_lbl):
		if not is_instance_valid(citadel) and main_node.get("is_warboss_spawned"):
			primary_citadel_lbl.text = "[!] Slay Mega-Warboss"
			primary_citadel_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.20))
		elif not is_instance_valid(citadel):
			primary_citadel_lbl.text = "[✓] Citadel Destroyed"
			primary_citadel_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
		else:
			primary_citadel_lbl.text = "[ ] Strike: Destroy Citadel"

	# 3. Bonus: STC Relic Cleansing Count
	var stc_vaults = get_tree().get_nodes_in_group("stc_vaults")
	var cleansed_count = 0
	for v in stc_vaults:
		if is_instance_valid(v) and v.get("is_cleansed"):
			cleansed_count += 1

	if is_instance_valid(bonus_stc_lbl):
		if cleansed_count >= 2:
			bonus_stc_lbl.text = "[✓] STC Relics Recovered (2/2)"
			bonus_stc_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
		else:
			bonus_stc_lbl.text = "[ ] Recover STC Relics (%d/2)" % cleansed_count

	# 4. Bonus: Satellite Outpost Destruction
	var destroyed_sats = 0
	if not main_node.get("has_squig_pit"): destroyed_sats += 1
	if not main_node.get("has_stormboy_pad"): destroyed_sats += 1
	if not main_node.get("has_mek_foundry"): destroyed_sats += 1

	if is_instance_valid(bonus_outposts_lbl):
		if destroyed_sats >= 3:
			bonus_outposts_lbl.text = "[✓] Outposts Crippled (3/3)"
			bonus_outposts_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
		else:
			bonus_outposts_lbl.text = "[ ] Cripple Outposts (%d/3)" % destroyed_sats

func _evaluate_tutorial_quest():
	if current_step_index >= current_quests.size():
		_finish_all_tutorials()
		return

	var q = current_quests[current_step_index]
	match q["type"]:
		"BEACON":
			if is_instance_valid(active_beacon_node):
				var dist = local_player.global_position.distance_to(active_beacon_node.global_position)
				if dist <= 48.0:
					_complete_current_quest()

		"ATTACK":
			if local_player.get("is_attacking_anim") or not local_player.get("can_plasma_attack") or not local_player.get("can_attack"):
				_complete_current_quest()

		"BUILD":
			var cur_buildings = get_tree().get_nodes_in_group("buildings").size()
			if cur_buildings > initial_building_count:
				_complete_current_quest()

		"SERVO_SKULL":
			var cur_skulls = get_tree().get_nodes_in_group("ServoSkull").size()
			if cur_skulls > initial_skull_count:
				_complete_current_quest()

		"DOCTRINA":
			if "active_doctrina" in local_player and local_player.active_doctrina != initial_doctrina_state:
				_complete_current_quest()

		"RECRUIT":
			var cur_bgs = get_tree().get_nodes_in_group("bodyguards").size()
			if cur_bgs > initial_bodyguard_count:
				_complete_current_quest()

		"SUPPLY_UPLINK":
			if Input.is_key_pressed(KEY_V):
				_complete_current_quest()

		"MAP_OR_BASE":
			var m_ui = get_tree().get_first_node_in_group("minimap_ui")
			var b_ui = get_tree().get_first_node_in_group("base_upgrade_ui")
			if (m_ui and m_ui.get("is_fullscreen")) or (b_ui and b_ui.visible):
				_complete_current_quest()

		"MAP_JUMP":
			var m_ui = get_tree().get_first_node_in_group("minimap_ui")
			if (m_ui and m_ui.get("is_fullscreen")) or (m_ui and m_ui.get("is_dragging_minimap")):
				_complete_current_quest()

func _complete_current_quest():
	if is_step_completed: return
	is_step_completed = true
	auto_advance_timer = 1.0

	AudioManager.play_sfx("volkite_beam", Vector2.ZERO, 0.0, 1.4)
	tut_task_lbl.text = "✓ DIRECTIVE COMPLETE!"
	tut_task_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
	
	if is_instance_valid(active_beacon_node):
		active_beacon_node.queue_free()
		active_beacon_node = null

func _advance_to_next_quest():
	current_step_index += 1
	if current_step_index >= current_quests.size():
		_finish_all_tutorials()
	else:
		_cache_initial_states()
		_setup_current_quest()

func _setup_current_quest():
	is_step_completed = false
	if is_instance_valid(active_beacon_node):
		active_beacon_node.queue_free()
		active_beacon_node = null

	var q = current_quests[current_step_index]
	tut_title_lbl.text = "🎓 TUTORIAL (%d/%d)" % [current_step_index + 1, current_quests.size()]
	tut_task_lbl.text = "● " + q["task"]
	tut_task_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))

	if q["type"] == "BEACON":
		var base_node = get_tree().get_first_node_in_group("base")
		var center = base_node.global_position if is_instance_valid(base_node) else Vector2(500, 500)
		var target_pos = center + q.get("offset", Vector2(100, 0))

		active_beacon_node = TutorialObjectiveBeacon.new()
		active_beacon_node.global_position = target_pos
		get_tree().current_scene.add_child(active_beacon_node)

func _finish_all_tutorials():
	session_tutorial_completed = true
	current_quests.clear()

	if is_instance_valid(active_beacon_node):
		active_beacon_node.queue_free()
		active_beacon_node = null

	if is_instance_valid(tut_section):
		tut_section.hide()

	AudioManager.play_sfx("binary_canticle", Vector2.ZERO, -2.0, 1.1)

func _on_skip_all_pressed():
	permanently_skipped = true
	_save_settings()
	session_tutorial_completed = true
	current_quests.clear()

	if is_instance_valid(active_beacon_node):
		active_beacon_node.queue_free()
		active_beacon_node = null

	if is_instance_valid(tut_section):
		tut_section.hide()

	AudioManager.play_sfx("hit", Vector2.ZERO, -6.0, 1.2)

# ==============================================================================
# IN-WORLD GLOWING BEACON FOR QUEST 1
# ==============================================================================
class TutorialObjectiveBeacon extends Node2D:
	var anim_time: float = 0.0

	func _ready() -> void:
		z_index = 84
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat

	func _process(delta: float) -> void:
		anim_time += delta
		queue_redraw()

	func _draw() -> void:
		var pulse = 0.75 + sin(anim_time * 5.0) * 0.25
		var cyan = Color(0.20, 0.88, 1.0, 0.85 * pulse)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, 40.0, Color(0.20, 0.88, 1.0, 0.08 * pulse))
		draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 32, cyan, 1.8)
		draw_arc(Vector2.ZERO, 26.0, anim_time * 2.0, anim_time * 2.0 + PI * 1.5, 24, Color(0.82, 0.62, 0.24, 0.8), 1.4)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		draw_line(Vector2(0, 0), Vector2(0, -32), Color(0.20, 0.88, 1.0, 0.6 * pulse), 1.8)
		draw_circle(Vector2(0, -32), 3.0, Color.WHITE)

		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(-60, -42), "◆ OBJECTIVE BEACON ◆", HORIZONTAL_ALIGNMENT_CENTER, 120, 8, Color(0.20, 0.88, 1.0, pulse))
