# res://AbilityHUD.gd
extends Control
class_name AbilityHUD

var local_player: Node2D = null
var update_accumulator: float = 0.0
var context_banner: PanelContainer = null
var context_label: Label = null
const UPDATE_INTERVAL: float = 0.06

var reboot_panel: PanelContainer = null
var reboot_timer_lbl: Label = null

# Tech-Priest Active Tab (0: Defenses, 1: Industry)
var tp_active_tab: int = 0

# Theme Colors
const C_BG_DARK     := Color(0.04, 0.05, 0.08, 0.96)
const C_PANEL_EDGE  := Color(0.18, 0.22, 0.28, 0.95)
const C_BRASS       := Color(0.82, 0.62, 0.24)
const C_BRASS_DIM   := Color(0.40, 0.28, 0.10)
const C_CYAN        := Color(0.20, 0.88, 1.00)
const C_AMBER       := Color(1.00, 0.72, 0.15)
const C_RED_ALERT   := Color(0.92, 0.22, 0.18)
const C_GREEN_READY := Color(0.35, 0.95, 0.45)
const C_PARCHMENT   := Color(0.88, 0.84, 0.72)
const C_MUTED       := Color(0.50, 0.54, 0.60)

var weapon_buttons: Array[Button] = []
var action_buttons: Array[Button] = []
var augment_buttons: Array[Button] = []

# Tech-Priest Tab Buttons
var tp_tab_container: HBoxContainer = null
var tp_defenses_tab_btn: Button = null
var tp_industry_tab_btn: Button = null

var action_panel: PanelContainer = null
var action_title_lbl: Label = null
var tooltip_card: PanelContainer = null
var hovered_slot_data: Dictionary = {}
var global_res_label: Label = null

# Sister Progression Header
var sister_prog_panel: PanelContainer = null
var sister_lvl_lbl: Label = null
var sister_exp_bar: ProgressBar = null
var sister_pts_lbl: Label = null

func _ready():
	add_to_group("ability_hud")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hud_layout()
	hide()

func _process(delta: float):
	if not is_instance_valid(local_player):
		_find_local_player()
		if not is_instance_valid(local_player):
			hide()
			return

	update_accumulator += delta
	if update_accumulator >= UPDATE_INTERVAL:
		update_accumulator = 0.0
		refresh_hud_display()

func _find_local_player():
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p):
			if (not multiplayer.has_multiplayer_peer()) or p.is_multiplayer_authority():
				setup_hud_for_player(p)
				return

func setup_hud_for_player(player_node: Node2D):
	local_player = player_node
	tp_active_tab = 0
	show()
	refresh_hud_display()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(local_player): return
	var p_class = int(local_player.get("current_class")) if "current_class" in local_player else 0

	# =========================================================================
	# A. TECH-PRIEST RTS TAB & BUILD HOTKEYS (1/2 Tabs + Q/E/R/F Building Keys)
	# =========================================================================
	if p_class == 0:
		if event is InputEventKey and event.pressed and not event.echo:
			var code = event.keycode if event.keycode != 0 else event.physical_keycode
			
			# ESC / Backspace: Cancel Building Mode
			if code == KEY_ESCAPE:
				if local_player.get("is_building_mode"):
					if local_player.has_method("toggle_build_mode"):
						local_player.toggle_build_mode(-1)
					refresh_hud_display()
					get_viewport().set_input_as_handled()
					return

			# Keys 1 & 2: Switch Tabs
			match code:
				KEY_1, KEY_KP_1:
					tp_active_tab = 0 # Switch to DEFENSES Tab
					refresh_hud_display()
					get_viewport().set_input_as_handled()
					return
				KEY_2, KEY_KP_2:
					tp_active_tab = 1 # Switch to INDUSTRY Tab
					refresh_hud_display()
					get_viewport().set_input_as_handled()
					return

			# Keys Q, E, R, F: Select Building in Active Tab (No WASD Conflict!)
			if tp_active_tab == 0: # --- DEFENSES TAB ---
				match code:
					KEY_Q:
						_select_tp_structure(0) # Aegis Rampart (Wall)
						get_viewport().set_input_as_handled()
					KEY_E:
						_select_tp_structure(2) # Cognis Turret
						get_viewport().set_input_as_handled()
					KEY_R:
						_select_tp_structure(4) # Electro-Relay
						get_viewport().set_input_as_handled()

			elif tp_active_tab == 1: # --- INDUSTRY TAB ---
				match code:
					KEY_Q:
						_select_tp_structure(1) # Plasma Dynamo
						get_viewport().set_input_as_handled()
					KEY_E:
						_select_tp_structure(3) # Scrap Smelter
						get_viewport().set_input_as_handled()
					KEY_R:
						_select_tp_structure(6) # Tech Shrine
						get_viewport().set_input_as_handled()
					KEY_F:
						_select_tp_structure(7) # Cybernetica Forge
						get_viewport().set_input_as_handled()

		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if local_player.get("is_building_mode"):
				if local_player.has_method("toggle_build_mode"):
					local_player.toggle_build_mode(-1)
				refresh_hud_display()

	# =========================================================================
	# B. SISTER OF BATTLE QUICK-UNLOCK HOTKEYS (CTRL + 1-4 / SPACE)
	# =========================================================================
	elif p_class == 2:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.ctrl_pressed or Input.is_key_pressed(KEY_CTRL):
				var code = event.keycode if event.keycode != 0 else event.physical_keycode
				var target_id: int = -1

				match code:
					KEY_1, KEY_KP_1: target_id = 0
					KEY_2, KEY_KP_2: target_id = 1
					KEY_3, KEY_KP_3: target_id = 2
					KEY_4, KEY_KP_4: target_id = 3
					KEY_SPACE:       target_id = 4

				if target_id != -1:
					_try_quick_upgrade_sister(target_id)
					get_viewport().set_input_as_handled()

func set_tp_tab(tab_idx: int) -> void:
	tp_active_tab = tab_idx
	refresh_hud_display()

func get_tp_tab() -> int:
	return tp_active_tab

func _select_tp_structure(type_id: int):
	if local_player and local_player.has_method("toggle_build_mode"):
		local_player.toggle_build_mode(type_id)
	refresh_hud_display()

func _try_quick_upgrade_sister(target_upgrade_id: int) -> void:
	var pts = local_player.get("miracle_points") if "miracle_points" in local_player else 0
	if pts <= 0: return

	var s_lvl = local_player.get("current_level") if "current_level" in local_player else 1
	var can_upgrade: bool = false

	match target_upgrade_id:
		0: can_upgrade = (local_player.get("rank_intervention") < 3)
		1: can_upgrade = (local_player.get("rank_grenade") < 3)
		2: can_upgrade = (local_player.get("rank_shield") < 3)
		3:
			var r_ult = local_player.get("rank_ultimate") if "rank_ultimate" in local_player else 0
			var req_lvl = 6 if r_ult == 0 else 12
			can_upgrade = (s_lvl >= req_lvl and r_ult < 2)
		4: can_upgrade = (local_player.get("rank_dash") < 3)

	if can_upgrade:
		if multiplayer.has_multiplayer_peer():
			local_player.rpc_id(1, "request_upgrade_sister_ability", target_upgrade_id)
		else:
			if local_player.has_method("request_upgrade_sister_ability"):
				local_player.request_upgrade_sister_ability(target_upgrade_id)

func _build_hud_layout():
	for c in get_children():
		c.queue_free()

	_build_top_left_resource_monitor()
	_build_context_interaction_banner()
	_build_reboot_overlay()
	_build_sister_progression_ribbon()

	tooltip_card = TooltipCard.new()
	tooltip_card.name = "TooltipCard"
	tooltip_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tooltip_card)
	tooltip_card.hide()

	var main_hbox = HBoxContainer.new()
	main_hbox.name = "MainHUDHBox"
	main_hbox.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	main_hbox.offset_left = -440
	main_hbox.offset_right = 440
	main_hbox.offset_top = -80
	main_hbox.offset_bottom = -10
	main_hbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_hbox.grow_vertical = Control.GROW_DIRECTION_BEGIN
	main_hbox.add_theme_constant_override("separation", 10)
	main_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(main_hbox)

	# --- POD A: ARMAMENTS & ACTIVES ---
	var weapon_panel = _create_pod_panel("ArmamentPod", main_hbox)
	var weapon_vbox = VBoxContainer.new()
	weapon_vbox.add_theme_constant_override("separation", 2)
	weapon_panel.add_child(weapon_vbox)

	var w_title = Label.new()
	w_title.text = "ARMAMENTS & ACTIVES"
	w_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w_title.add_theme_font_size_override("font_size", 8)
	w_title.add_theme_color_override("font_color", C_BRASS)
	weapon_vbox.add_child(w_title)

	var weapon_hbox = HBoxContainer.new()
	weapon_hbox.add_theme_constant_override("separation", 4)
	weapon_vbox.add_child(weapon_hbox)

	weapon_buttons.clear()
	for i in range(3):
		var slot = CompactSlot.new("weapon", i)
		slot.custom_minimum_size = Vector2(48, 48)
		slot.mouse_entered.connect(_on_slot_hovered.bind(slot))
		slot.mouse_exited.connect(_on_slot_unhovered)
		slot.pressed.connect(_on_slot_clicked.bind(slot))
		weapon_hbox.add_child(slot)
		weapon_buttons.append(slot)

	# --- POD B: TACTICAL PROTOCOLS / FORGE COGITATOR TABS ---
	action_panel = _create_pod_panel("ActionPod", main_hbox)
	var action_vbox = VBoxContainer.new()
	action_vbox.add_theme_constant_override("separation", 2)
	action_panel.add_child(action_vbox)

	# Tech-Priest Dual Category Tabs Header
	tp_tab_container = HBoxContainer.new()
	tp_tab_container.alignment = BoxContainer.ALIGNMENT_CENTER
	tp_tab_container.add_theme_constant_override("separation", 6)
	action_vbox.add_child(tp_tab_container)

	tp_defenses_tab_btn = Button.new()
	tp_defenses_tab_btn.text = "[1] 🛡️ DEFENSES"
	tp_defenses_tab_btn.custom_minimum_size = Vector2(100, 16)
	tp_defenses_tab_btn.add_theme_font_size_override("font_size", 8)
	tp_defenses_tab_btn.pressed.connect(func(): set_tp_tab(0))
	tp_tab_container.add_child(tp_defenses_tab_btn)

	tp_industry_tab_btn = Button.new()
	tp_industry_tab_btn.text = "[2] ⚙️ INDUSTRY"
	tp_industry_tab_btn.custom_minimum_size = Vector2(100, 16)
	tp_industry_tab_btn.add_theme_font_size_override("font_size", 8)
	tp_industry_tab_btn.pressed.connect(func(): set_tp_tab(1))
	tp_tab_container.add_child(tp_industry_tab_btn)

	action_title_lbl = Label.new()
	action_title_lbl.text = "TACTICAL PROTOCOLS"
	action_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_title_lbl.add_theme_font_size_override("font_size", 8)
	action_title_lbl.add_theme_color_override("font_color", C_CYAN)
	action_vbox.add_child(action_title_lbl)

	var action_hbox = HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 4)
	action_vbox.add_child(action_hbox)

	action_buttons.clear()
	for i in range(7):
		var slot = CompactSlot.new("action", i)
		slot.custom_minimum_size = Vector2(48, 48)
		slot.mouse_entered.connect(_on_slot_hovered.bind(slot))
		slot.mouse_exited.connect(_on_slot_unhovered)
		slot.pressed.connect(_on_slot_clicked.bind(slot))
		action_hbox.add_child(slot)
		action_buttons.append(slot)

	# --- POD C: CYBERNETICS & BLESSINGS ---
	var augment_panel = _create_pod_panel("AugmentPod", main_hbox)
	var augment_vbox = VBoxContainer.new()
	augment_vbox.add_theme_constant_override("separation", 2)
	augment_panel.add_child(augment_vbox)

	var aug_title = Label.new()
	aug_title.text = "BIONICS & BLESSINGS"
	aug_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aug_title.add_theme_font_size_override("font_size", 8)
	aug_title.add_theme_color_override("font_color", C_AMBER)
	augment_vbox.add_child(aug_title)

	var augment_hbox = HBoxContainer.new()
	augment_hbox.add_theme_constant_override("separation", 4)
	augment_vbox.add_child(augment_hbox)

	augment_buttons.clear()
	for i in range(3):
		var slot = CompactSlot.new("augment", i)
		slot.custom_minimum_size = Vector2(48, 48)
		slot.mouse_entered.connect(_on_slot_hovered.bind(slot))
		slot.mouse_exited.connect(_on_slot_unhovered)
		slot.pressed.connect(_on_slot_clicked.bind(slot))
		augment_hbox.add_child(slot)
		augment_buttons.append(slot)

func _build_sister_progression_ribbon():
	sister_prog_panel = PanelContainer.new()
	sister_prog_panel.name = "SisterProgressionRibbon"
	sister_prog_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sister_prog_panel.offset_left = -210
	sister_prog_panel.offset_right = 210
	sister_prog_panel.offset_top = -108
	sister_prog_panel.offset_bottom = -84
	sister_prog_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.94)
	sb.border_color = Color(0.82, 0.62, 0.24, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sister_prog_panel.add_theme_stylebox_override("panel", sb)
	add_child(sister_prog_panel)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	sister_prog_panel.add_child(hbox)

	sister_lvl_lbl = Label.new()
	sister_lvl_lbl.text = "LVL 1"
	sister_lvl_lbl.add_theme_font_size_override("font_size", 9)
	sister_lvl_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	hbox.add_child(sister_lvl_lbl)

	sister_exp_bar = ProgressBar.new()
	sister_exp_bar.custom_minimum_size = Vector2(140, 6)
	sister_exp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sister_exp_bar.show_percentage = false
	var sb_fill = StyleBoxFlat.new()
	sb_fill.bg_color = Color(0.20, 0.88, 1.0)
	sb_fill.set_corner_radius_all(2)
	sister_exp_bar.add_theme_stylebox_override("fill", sb_fill)
	hbox.add_child(sister_exp_bar)

	sister_pts_lbl = Label.new()
	sister_pts_lbl.text = "0/60 XP"
	sister_pts_lbl.add_theme_font_size_override("font_size", 8)
	sister_pts_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	hbox.add_child(sister_pts_lbl)

	sister_prog_panel.hide()

func _build_reboot_overlay():
	reboot_panel = PanelContainer.new()
	reboot_panel.name = "RebootOverlay"
	reboot_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	reboot_panel.offset_left = -260
	reboot_panel.offset_right = 260
	reboot_panel.offset_top = 80
	reboot_panel.offset_bottom = 140
	reboot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.95)
	sb.border_color = Color(0.92, 0.22, 0.18)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	reboot_panel.add_theme_stylebox_override("panel", sb)
	add_child(reboot_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	reboot_panel.add_child(vbox)

	reboot_timer_lbl = Label.new()
	reboot_timer_lbl.text = "⚡ CEREBRAL REBOOT IN PROGRESS: 10.0s ⚡"
	reboot_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reboot_timer_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.15))
	reboot_timer_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(reboot_timer_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "Chassis destroyed. Re-materializing at Main Base Sanctum..."
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	sub_lbl.add_theme_font_size_override("font_size", 9)
	vbox.add_child(sub_lbl)

	reboot_panel.hide()

func _build_context_interaction_banner():
	context_banner = PanelContainer.new()
	context_banner.name = "ContextInteractionBanner"
	context_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	context_banner.offset_left = -230
	context_banner.offset_right = 230
	context_banner.offset_top = -106
	context_banner.offset_bottom = -82
	context_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	context_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	context_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.94)
	sb.border_color = Color(0.20, 0.88, 1.0, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	context_banner.add_theme_stylebox_override("panel", sb)
	add_child(context_banner)

	context_label = Label.new()
	context_label.name = "ContextLabel"
	context_label.text = ""
	context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	context_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	context_label.add_theme_font_size_override("font_size", 8)
	context_banner.add_child(context_label)
	context_banner.hide()

func _build_top_left_resource_monitor():
	var top_panel = PanelContainer.new()
	top_panel.name = "TopLeftResourceMonitor"
	top_panel.z_index = 100
	top_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_panel.offset_left = 12
	top_panel.offset_top = 8
	top_panel.offset_right = 265
	top_panel.offset_bottom = 36
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.92)
	sb.border_color = Color(0.24, 0.28, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	top_panel.add_theme_stylebox_override("panel", sb)
	add_child(top_panel)

	global_res_label = Label.new()
	global_res_label.name = "GlobalResLabel"
	global_res_label.text = "⚙ 75 SCRAP   ⚡ 25 REQ   🤖 0/12"
	global_res_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	global_res_label.add_theme_font_size_override("font_size", 9)
	global_res_label.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	top_panel.add_child(global_res_label)

func _create_pod_panel(pod_name: String, parent_container: Container) -> PanelContainer:
	var pc = PanelContainer.new()
	pc.name = pod_name
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_BG_DARK
	sb.border_color = C_BRASS_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 4
	pc.add_theme_stylebox_override("panel", sb)
	parent_container.add_child(pc)
	return pc

func _on_slot_hovered(slot: Button):
	if slot is CompactSlot:
		hovered_slot_data = slot.cached_data
		if not hovered_slot_data.is_empty():
			_update_tooltip_position(slot)
			tooltip_card.show()

func _on_slot_unhovered():
	hovered_slot_data.clear()
	if tooltip_card:
		tooltip_card.hide()

func _on_slot_clicked(slot: Button):
	if not is_instance_valid(local_player) or not (slot is CompactSlot): return
	var p_class = int(local_player.get("current_class")) if "current_class" in local_player else 0

	# --- 1. TECH-PRIEST ACTIONS ---
	if p_class == 0:
		if slot.category == "action":
			var t_id = slot.cached_data.get("type_id", -1)
			if t_id != -1:
				_select_tp_structure(t_id)

		elif slot.category == "augment" and slot.slot_index == 0:
			if multiplayer.has_multiplayer_peer(): local_player.rpc_id(1, "request_spawn_servo_skull")
			else: local_player.request_spawn_servo_skull()

	# --- 2. SKITARII MARSHAL ACTIONS ---
	elif p_class == 1:
		if slot.category == "action":
			match slot.slot_index:
				0: local_player.is_attack_move_queued = not local_player.is_attack_move_queued
				1: local_player._issue_stop_to_selection()
				2: local_player._issue_hold_to_selection()
				3:
					var mouse_w = local_player.get_global_mouse_position()
					var tgt = local_player._find_enemy_under_cursor(mouse_w)
					if is_instance_valid(tgt) and local_player.has_method("_designate_priority_target"):
						local_player._designate_priority_target(tgt)
				4:
					if is_instance_valid(local_player.camera):
						local_player.camera.global_position = local_player.global_position
				5:
					if multiplayer.has_multiplayer_peer():
						local_player.rpc_id(1, "request_field_requisition_uplink")
					else:
						local_player.request_field_requisition_uplink()
		elif slot.category == "weapon" and slot.slot_index == 1:
			if local_player.has_method("_toggle_doctrina_imperative"):
				local_player._toggle_doctrina_imperative()
		elif slot.category == "augment":
			if multiplayer.has_multiplayer_peer():
				local_player.rpc_id(1, "request_recruit_bodyguard", slot.slot_index)
			else:
				local_player.request_recruit_bodyguard(slot.slot_index)

	# --- 3. SISTER OF BATTLE ACTIONS ---
	elif p_class == 2:
		var pts = local_player.get("miracle_points") if "miracle_points" in local_player else 0
		var s_lvl = local_player.get("current_level") if "current_level" in local_player else 1

		if pts > 0:
			var target_upgrade_id: int = -1
			if slot.category == "action":
				var ability_id = slot.slot_index
				if ability_id in [0, 1, 2]:
					target_upgrade_id = ability_id
				elif ability_id == 3:
					var r_ult = local_player.get("rank_ultimate") if "rank_ultimate" in local_player else 0
					var req_lvl = 6 if r_ult == 0 else 12
					if s_lvl >= req_lvl and r_ult < 2:
						target_upgrade_id = 3
			elif slot.category == "weapon" and slot.slot_index == 2:
				if local_player.get("rank_dash") < 3:
					target_upgrade_id = 4

			if target_upgrade_id != -1:
				if multiplayer.has_multiplayer_peer():
					local_player.rpc_id(1, "request_upgrade_sister_ability", target_upgrade_id)
				else:
					if local_player.has_method("request_upgrade_sister_ability"):
						local_player.request_upgrade_sister_ability(target_upgrade_id)

func _get_data_for_category(category: String, idx: int) -> Dictionary:
	if not is_instance_valid(local_player): return {}
	var p_class = int(local_player.get("current_class")) if "current_class" in local_player else 0

	# ==========================================================================
	# A. TECH-PRIEST ENGINSEER (TABBED RTS BUILD COGITATOR)
	# ==========================================================================
	if p_class == 0:
		match category:
			"weapon":
				match idx:
					0: return {"key": "LMB", "name": "Omnissian Power-Axe", "sub": "Heavy Melee Cleave", "icon": "axe", "scrap": 0, "req": 0, "type_id": -1, "desc": "Heavy energized power-axe (40 DMG). Cuts through armor in a wide arc.", "flavor": "\"The blade is the voice of the Omnissiah.\""}
					1: return {"key": "RMB", "name": "Plasma Caliver", "sub": "Auspex Paint", "icon": "plasma_pistol", "scrap": 0, "req": 0, "type_id": -1, "desc": "Fires superheated plasma (30 DMG). Applies Auspex Lock-On (+35% Crit).", "flavor": "\"Paint the xeno in telemetry.\""}
					_: return {}

			"action":
				if tp_active_tab == 0: # --- 🛡️ DEFENSES TAB (Hotkeys: Q, E, R) ---
					match idx:
						0: return {"key": "Q", "name": "Aegis Blast Rampart", "sub": "Wall Post (15 Scrap)", "icon": "barricade", "scrap": 15, "req": 0, "type_id": 0, "desc": "Heavy blast wall. Links automatically into continuous ramparts. Upgrade to Gate [E].", "flavor": "\"Armor preserves the faithful.\""}
						1: return {"key": "E", "name": "Cognis Defense Battery", "sub": "Turret (35 Scrap 5 Req)", "icon": "turret", "scrap": 35, "req": 5, "type_id": 2, "desc": "Automated defense battery. Upgradable to Flak, Volkite, or Arc Blasters with [E].", "flavor": "\"Strike swift in His name.\""}
						2: return {"key": "R", "name": "Electro-Relay Substation", "sub": "Grid Conduit (20 Scrap)", "icon": "distributor", "scrap": 20, "req": 0, "type_id": 4, "desc": "Extends 240px Noosphere power grid. Magnetically siphons loose battlefield scrap.", "flavor": "\"The Motive Force flows unbroken.\""}
						_: return {}

				else: # --- ⚙️ INDUSTRY TAB (Hotkeys: Q, E, R, F) ---
					match idx:
						0: return {"key": "Q", "name": "Imperial Plasma Dynamo", "sub": "+2 Req / Cycle (25 Scrap)", "icon": "generator", "scrap": 25, "req": 0, "type_id": 1, "desc": "Generates +2 Requisition per cycle. Energizes shields and nanobots.", "flavor": "\"From caged fury we draw civilization.\""}
						1: return {"key": "E", "name": "Scrap Smelter", "sub": "+5 Scrap / Cycle (30 Scrap)", "icon": "foundry", "scrap": 30, "req": 5, "type_id": 3, "desc": "Build over Scrap Deposit. Automatically extracts +5 Scrap per cycle.", "flavor": "\"The broken iron of the foe is remade.\""}
						2: return {"key": "R", "name": "Omnissian Reliquary", "sub": "Tech Shrine (40 Scrap)", "icon": "shrine", "scrap": 40, "req": 15, "type_id": 6, "desc": "Access terminal [E] to research Shields, Lasers, Siphons, and Uplinks.", "flavor": "\"Knowledge is the true holy relic.\""}
						3: return {"key": "F", "name": "Cybernetica Manufactorum", "sub": "Cohort Assembly (50 Scrap)", "icon": "cybernetica", "scrap": 50, "req": 20, "type_id": 7, "desc": "Construct Vanguard, Rangers, Ruststalkers, Kataphrons, and Kastelans with [E].", "flavor": "\"From holy fires march undying cohorts.\""}
						_: return {}

			"augment":
				match idx:
					0:
						var skulls = local_player.active_servo_skulls.size() if "active_servo_skulls" in local_player else 0
						return {"key": "C", "name": "Fabricate Servo-Skull", "sub": "Drone (%d/%d)" % [skulls, GameData.MAX_SERVO_SKULLS], "icon": "skull", "scrap": GameData.SERVO_SKULL_SCRAP_COST, "req": GameData.SERVO_SKULL_REQ_COST, "type_id": -1, "current_rank": skulls, "max_rank": GameData.MAX_SERVO_SKULLS, "desc": "Deploys an autonomous drone to retrieve scrap.", "flavor": "\"Even in death, the servant performs the work.\""}
					_: return {}

	# ==========================================================================
	# B. SKITARII MARSHAL
	# ==========================================================================
	elif p_class == 1:
		match category:
			"weapon":
				match idx:
					0: return {"key": "LMB", "name": "Radium Serpenta Carbine", "sub": "Ranged Munition", "icon": "radium_carbine", "scrap": 0, "req": 0, "type_id": -1, "desc": "Rapid-fire irradiated rifle. Decays organic cellular structures on impact.", "flavor": "\"Cleanse in phosphor fallout.\""}
					1:
						var is_conq = (local_player.active_doctrina == 0) if "active_doctrina" in local_player else true
						return {"key": "Q", "name": "Doctrina: " + ("CONQUEROR" if is_conq else "PROTECTOR"), "sub": "Aura", "icon": "doctrina_conq" if is_conq else "doctrina_prot", "scrap": 0, "req": 0, "type_id": -1, "desc": "Aura: +30% Speed & +25% Fire Rate (-15% Armor)" if is_conq else "Aura: +35% Armor & +20% Range (-15% Speed)", "flavor": "\"Upload the sacred canticle.\""}
					2: return {"key": "R", "name": "Orbital Lance Strike", "sub": "Bombardment", "icon": "orbital", "scrap": 0, "req": GameData.ORBITAL_REQ_COST, "type_id": -1, "desc": "Calls down a searing orbital lance strike (220 DMG / 45s CD).", "flavor": "\"Let the stars descend in cleansing fire.\""}
					_: return {}
			"action":
				match idx:
					0: return {"key": "A", "name": "Attack-Move", "sub": "Directive", "icon": "attack_move", "scrap": 0, "req": 0, "type_id": -1, "desc": "Orders selected units to march and engage all enemies.", "flavor": "\"Advance with fury.\""}
					1: return {"key": "S", "name": "Halt / Stop", "sub": "Directive", "icon": "stop", "scrap": 0, "req": 0, "type_id": -1, "desc": "Cancels movement and combat orders.", "flavor": "\"Hold position.\""}
					2: return {"key": "H", "name": "Hold Ground", "sub": "Directive", "icon": "hold_ground", "scrap": 0, "req": 0, "type_id": -1, "desc": "Units hold ground and fire at maximum range.", "flavor": "\"The line does not yield.\""}
					3: return {"key": "F", "name": "Auspex Target Paint", "sub": "Telemetry", "icon": "auspex_paint", "scrap": 0, "req": 0, "type_id": -1, "desc": "Paints target (+35% Crit). Kills yield +1 to +3 REQ.", "flavor": "\"Mark the xeno for eradication.\""}
					4: return {"key": "SPACE", "name": "Focus Commander", "sub": "Camera", "icon": "cam_lock", "scrap": 0, "req": 0, "type_id": -1, "desc": "Centers tactical camera on the Marshal.", "flavor": "\"Re-center telemetry.\""}
					5: return {"key": "V", "name": "Orbital Supply Uplink", "sub": "Transmutation", "icon": "distributor", "scrap": 15, "req": 0, "type_id": -1, "desc": "Transmits 15 Scrap to orbit for +8 Requisition.", "flavor": "\"Receive consecrated munitions.\""}
					_: return {}
			"augment":
				var count = local_player.active_bodyguards.size() if "active_bodyguards" in local_player else 0
				match idx:
					0: return {"key": "Z", "name": "Skitarii Ranger", "sub": "Sniper", "icon": "recruit_ranger", "scrap": 15, "req": 5, "type_id": 0, "current_rank": count, "max_rank": GameData.MAX_BODYGUARDS, "desc": "Galvanic sniper cadre (%d/%d Active)." % [count, GameData.MAX_BODYGUARDS], "flavor": "\"Never miss the spark.\""}
					1: return {"key": "X", "name": "Sicarian Ruststalker", "sub": "Assassin", "icon": "recruit_sicarian", "scrap": 20, "req": 10, "type_id": 1, "current_rank": count, "max_rank": GameData.MAX_BODYGUARDS, "desc": "Transonic cyber-assassin (%d/%d Active)." % [count, GameData.MAX_BODYGUARDS], "flavor": "\"Cleave at a molecular level.\""}
					2: return {"key": "C", "name": "Skitarii Vanguard", "sub": "Shock Trooper", "icon": "recruit_vanguard", "scrap": 10, "req": 5, "type_id": 2, "current_rank": count, "max_rank": GameData.MAX_BODYGUARDS, "desc": "Rad-shock infantry with fallout aura (%d/%d Active)." % [count, GameData.MAX_BODYGUARDS], "flavor": "\"Their bodies burn with fallout.\""}
					_: return {}

	# ==========================================================================
	# C. SISTER SUPERIOR (ADEPTA SORORITAS)
	# ==========================================================================
	elif p_class == 2:
		var pts = local_player.get("miracle_points") if "miracle_points" in local_player else 0
		var r_dash = local_player.get("rank_dash") if "rank_dash" in local_player else 1
		var r_int = local_player.get("rank_intervention") if "rank_intervention" in local_player else 0
		var r_gren = local_player.get("rank_grenade") if "rank_grenade" in local_player else 0
		var r_shld = local_player.get("rank_shield") if "rank_shield" in local_player else 0
		var r_ult = local_player.get("rank_ultimate") if "rank_ultimate" in local_player else 0
		var s_lvl = local_player.get("current_level") if "current_level" in local_player else 1

		var b_dmg = int(local_player.get("bullet_damage") if "bullet_damage" in local_player else 25)
		var dodge_chance = float(local_player.get("faith_dodge_chance") if "faith_dodge_chance" in local_player else 0.15)
		var cur_s = int(local_player.get("faith_shield_current") if "faith_shield_current" in local_player else 40)
		var max_s = int(local_player.get("faith_shield_max") if "faith_shield_max" in local_player else 40)

		match category:
			"weapon":
				match idx:
					0: return {"key": "LMB", "name": "Holy Flamer", "sub": "Armor-Piercing Burn", "icon": "flamer", "scrap": 0, "req": 0, "type_id": -1, "desc": "Sprays continuous promethium fire (%d DPS). Scales with level." % b_dmg, "flavor": "\"Cleanse with holy fire.\""}
					1: return {"key": "RMB", "name": "Multi-Melta", "sub": "Thermal Beam", "icon": "melta", "scrap": 0, "req": 0, "type_id": -1, "desc": "Devastating thermal ray (110 DMG) melting heavy Nobz and bastions.", "flavor": "\"No armor withstands His fury.\""}
					2: return {"key": "SPACE", "name": "Seraphim Dash", "sub": "Jetpack Thrust (Rank %d/3)" % r_dash, "icon": "seraphim_dash", "scrap": 0, "req": 0, "type_id": 4, "current_rank": r_dash, "max_rank": 3, "can_upgrade": (pts > 0 and r_dash < 3), "desc": "Rocket dash leaving burning scorch trails. Upgrading reduces cooldown.", "flavor": "\"Seraphim wings bear us swift.\""}
			"action":
				match idx:
					0: return {"key": "1", "name": "Holy Intervention", "sub": "Sanctuary Relic (Rank %d/3)" % r_int, "icon": "miracle_shield", "scrap": 0, "req": 0, "type_id": 0, "current_rank": r_int, "max_rank": 3, "can_upgrade": (pts > 0 and r_int < 3), "desc": "Throws a holy relic that absorbs all incoming enemy projectiles in a 140px dome before detonating.", "flavor": "\"Stand within the sacred circle.\""}
					1: return {"key": "2", "name": "Holy Hand Grenade", "sub": "Consecrated Relic (Rank %d/3)" % r_gren, "icon": "holy_grenade", "scrap": 0, "req": 0, "type_id": 1, "current_rank": r_gren, "max_rank": 3, "can_upgrade": (pts > 0 and r_gren < 3), "desc": "Lobs a sacred grenade dealing 160-300 DMG with wide knockback.", "flavor": "\"O Lord, bless this thy hand grenade...\""}
					2: return {"key": "3", "name": "Act of Faith", "sub": "Faith Shield (Rank %d/3)" % r_shld, "icon": "miracle_shield", "scrap": 0, "req": 0, "type_id": 2, "current_rank": r_shld, "max_rank": 3, "can_upgrade": (pts > 0 and r_shld < 3), "desc": "Passive: Dodge + Faith Shield. Active: Instantly overcharges shield to max.", "flavor": "\"Faith is my shield.\""}
					3: return {
						"key": "4", 
						"name": "Righteous Pyre", 
						"sub": "Divine Ultimate (Rank %d/2)" % r_ult, 
						"icon": "righteous_pyre", 
						"scrap": 0, 
						"req": 0, 
						"type_id": 3, 
						"current_rank": r_ult, 
						"max_rank": 2, 
						"can_upgrade": (pts > 0 and s_lvl >= (6 if r_ult == 0 else 12) and r_ult < 2), 
						"desc": "Heavenly pillar of divine wrath (260-400 DMG), granting invulnerability for 6s. (Req. Lv 6 / Lv 12)", 
						"flavor": "\"By Saint Katherine's blood!\""
					}
					_: return {}
			"augment":
				match idx:
					0:
						var is_saint_ready = s_lvl >= 10
						var status_txt = "MARTYRDOM READY (LVL 10+)" if is_saint_ready else "LOCKED (Req. Level 10)"
						return {
							"key": "PASSIVE", 
							"name": "Living Saint Ascension", 
							"sub": status_txt, 
							"icon": "celestine_wings", 
							"scrap": 0, 
							"req": 0, 
							"type_id": -1, 
							"current_rank": (1 if is_saint_ready else 0), 
							"max_rank": 1, 
							"desc": "Upon taking lethal damage at Level 10+, ascend into Saint Celestine with glowing wings, full HP/Shield, and divine shockwaves.", 
							"flavor": "\"She who dies in His light shall rise unbroken.\""
						}
					1:
						return {"key": "PASSIVE", "name": "Holy Evasion", "sub": "+%d%% Dodge" % int(dodge_chance * 100), "icon": "seraphim_dash", "scrap": 0, "req": 0, "type_id": -1, "desc": "Passively dodges incoming projectile and melee attacks.", "flavor": "\"The Emperor protects her stride.\""}
					2:
						return {"key": "PASSIVE", "name": "Consecrated Aegis", "sub": "Shield (%d/%d)" % [cur_s, max_s], "icon": "miracle_shield", "scrap": 0, "req": 0, "type_id": -1, "desc": "Absorbs incoming damage before health. Regenerates passively.", "flavor": "\"Anointed in holy oils.\""}
					_:
						return {}

	return {}

func refresh_hud_display():
	if not is_instance_valid(local_player): return

	var main_node = get_tree().get_first_node_in_group("main")
	var cur_scrap = main_node.scrap_amount if main_node and "scrap_amount" in main_node else 0
	var cur_req = main_node.requisition_amount if main_node and "requisition_amount" in main_node else 0
	var cur_pop = main_node.get_cohort_population() if main_node and main_node.has_method("get_cohort_population") else 0

	var p_class = int(local_player.get("current_class")) if "current_class" in local_player else 0

	# --- 1. SHARED TOP-LEFT RESOURCE MONITOR ---
	if global_res_label:
		global_res_label.text = "⚙ %d SCRAP   ⚡ %d REQ   🤖 %d/%d" % [
			cur_scrap, cur_req, cur_pop, GameData.BASE_COHORT_CAP
		]

	# --- 2. SISTER PROGRESSION RIBBON ---
	if is_instance_valid(sister_prog_panel):
		if p_class == 2:
			sister_prog_panel.show()
			var s_pts = int(local_player.get("miracle_points") if "miracle_points" in local_player else 0)
			var s_lvl = int(local_player.get("current_level") if "current_level" in local_player else 1)
			var s_exp = int(local_player.get("current_exp") if "current_exp" in local_player else 0)
			var s_next = int(local_player.get("exp_to_next_level") if "exp_to_next_level" in local_player else 60)

			if s_lvl >= 14:
				sister_lvl_lbl.text = "LVL 14 (MAX)"
				sister_exp_bar.max_value = 1
				sister_exp_bar.value = 1
				sister_pts_lbl.text = "✨ %d PTS [CTRL+KEY]" % s_pts if s_pts > 0 else "DIVINE PERFECTION"
				sister_pts_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
			else:
				sister_lvl_lbl.text = "LVL %d" % s_lvl
				sister_exp_bar.max_value = max(1, s_next)
				sister_exp_bar.value = s_exp
				if s_pts > 0:
					sister_pts_lbl.text = "✨ %d PTS [CTRL+KEY TO UNLOCK]" % s_pts
					sister_pts_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
				else:
					sister_pts_lbl.text = "%d/%d XP" % [s_exp, s_next]
					sister_pts_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
		else:
			sister_prog_panel.hide()

	# --- 3. TECH-PRIEST TABS & HEADER UPDATE ---
	if is_instance_valid(tp_tab_container):
		if p_class == 0:
			tp_tab_container.show()
			action_title_lbl.hide()

			# Highlight Active Tab
			if tp_active_tab == 0:
				tp_defenses_tab_btn.modulate = Color(0.20, 0.88, 1.0)
				tp_industry_tab_btn.modulate = Color(0.6, 0.65, 0.7)
			else:
				tp_defenses_tab_btn.modulate = Color(0.6, 0.65, 0.7)
				tp_industry_tab_btn.modulate = Color(1.0, 0.75, 0.2)
		else:
			tp_tab_container.hide()
			action_title_lbl.show()
			if p_class == 1:
				action_title_lbl.text = "TACTICAL PROTOCOLS"; action_title_lbl.add_theme_color_override("font_color", C_CYAN)
			elif p_class == 2:
				action_title_lbl.text = "CONSECRATED RELICS"; action_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))

	var selected_type = local_player.selected_building_type if "selected_building_type" in local_player else 0
	var is_building = local_player.is_building_mode if "is_building_mode" in local_player else false

	if is_instance_valid(reboot_panel):
		var is_player_dead = local_player.is_dead if "is_dead" in local_player else false
		if is_player_dead:
			var time_left = maxf(0.0, local_player.respawn_timer if "respawn_timer" in local_player else 0.0)
			reboot_timer_lbl.text = "⚡ CEREBRAL REBOOT IN PROGRESS: %.1fs ⚡" % time_left
			reboot_panel.show()
		else:
			reboot_panel.hide()

	# 1. Weapon Pod
	for i in range(weapon_buttons.size()):
		var slot = weapon_buttons[i]
		var data = _get_data_for_category("weapon", i)
		_populate_slot(slot, data, cur_scrap, cur_req)

		if p_class == 0 and i == 1:
			var can_plasma = local_player.can_plasma_attack if "can_plasma_attack" in local_player else true
			var cd = local_player.plasma_cooldown if "plasma_cooldown" in local_player else 0.65
			slot.cooldown_left = 0.0 if can_plasma else cd
		elif p_class == 1 and i == 2:
			slot.cooldown_left = local_player.orbital_strike_cooldown if "orbital_strike_cooldown" in local_player else 0.0
		elif p_class == 2:
			if i == 1: slot.cooldown_left = local_player.melta_cooldown_timer if "melta_cooldown_timer" in local_player else 0.0
			elif i == 2: slot.cooldown_left = local_player.dash_cooldown_timer if "dash_cooldown_timer" in local_player else 0.0

	# 2. Action Pod
	for i in range(action_buttons.size()):
		var slot = action_buttons[i]
		var data = _get_data_for_category("action", i)
		_populate_slot(slot, data, cur_scrap, cur_req)

		if p_class == 0:
			var t_id = data.get("type_id", -1)
			slot.is_selected = (is_building and selected_type == t_id and t_id != -1)
		elif p_class == 1:
			if i == 0 and "is_attack_move_queued" in local_player:
				slot.is_selected = local_player.is_attack_move_queued
		elif p_class == 2:
			if i == 0: slot.cooldown_left = local_player.holy_intervention_cooldown if "holy_intervention_cooldown" in local_player else 0.0
			elif i == 1: slot.cooldown_left = local_player.holy_grenade_cooldown if "holy_grenade_cooldown" in local_player else 0.0
			elif i == 2: slot.cooldown_left = local_player.miracle_act_cooldown if "miracle_act_cooldown" in local_player else 0.0
			elif i == 3: slot.cooldown_left = local_player.sister_ultimate_cooldown if "sister_ultimate_cooldown" in local_player else 0.0

	# 3. Augment Pod
	for i in range(augment_buttons.size()):
		var slot = augment_buttons[i]
		var data = _get_data_for_category("augment", i)
		_populate_slot(slot, data, cur_scrap, cur_req)
		if not data.is_empty() and data.has("current_rank") and data.has("max_rank"):
			slot.current_rank = data.current_rank
			slot.max_rank = data.max_rank
			slot.is_maxed = (slot.current_rank >= slot.max_rank)

	if not hovered_slot_data.is_empty() and tooltip_card and tooltip_card.visible:
		tooltip_card.set_data(hovered_slot_data, cur_scrap, cur_req)

	_update_context_banner_display(p_class == 0, cur_scrap, cur_req)

func _update_context_banner_display(is_techpriest: bool, cur_scrap: int, cur_req: int):
	if not is_instance_valid(context_banner) or not is_techpriest:
		if is_instance_valid(context_banner): context_banner.hide()
		return

	var b = local_player.hovered_interact_building if "hovered_interact_building" in local_player else null
	if not is_instance_valid(b) or local_player.get("is_building_mode"):
		context_banner.hide()
		return

	var prompt_text = ""
	var can_afford = true
	var is_maxed = false

	if b.is_in_group("stc_vaults"):
		prompt_text = "◆ STC VAULT: PRESS [E] TO CLAIM ARCHEOTECH ◆"
	elif b.is_in_group("base"):
		prompt_text = "◆ SANCTUM: PRESS [E] TO ACCESS AUSPEX PROTOCOLS ◆"
	else:
		var b_type = int(b.building_type) if "building_type" in b else -1
		match b_type:
			0:
				if b.get("is_gate"):
					is_maxed = true
					prompt_text = "◆ MOTORIZED GATE: OPERATIONAL ◆"
				else:
					can_afford = (cur_scrap >= 10 and cur_req >= 5)
					prompt_text = "◆ BARRICADE: [E] UPGRADE GATE (⚙ 10  ⚡ 5) ◆"
			1:
				is_maxed = true
				prompt_text = "◆ PLASMA DYNAMO: +2 REQ / CYCLE ◆"
			2:
				var lvl = b.turret_upgrade_level if "turret_upgrade_level" in b else 0
				var spec = b.turret_spec if "turret_spec" in b else 0
				if lvl < 3:
					var cost = GameData.TURRET_UPGRADE_COSTS[lvl]
					can_afford = (cur_req >= cost)
					prompt_text = "◆ COGNIS (T%d): [E] UPGRADE (⚡ %d REQ) ◆" % [lvl + 1, cost]
				elif spec == 0:
					can_afford = (cur_req >= GameData.TURRET_SPEC_REQ_COST)
					prompt_text = "◆ COGNIS (MAX): [E] SPECIALIZE (⚡ 35 REQ) ◆"
				else:
					is_maxed = true
					var spec_info = GameData.TURRET_SPEC_INFO.get(spec, {})
					prompt_text = "◆ %s: OPTIMAL ◆" % spec_info.get("name", "COGNIS").to_upper()
			3:
				is_maxed = true
				prompt_text = "◆ SCRAP SMELTER: +5 SCRAP / CYCLE ◆"
			4:
				can_afford = (cur_req >= 15)
				prompt_text = "◆ ELECTRO-RELAY: [E] UPGRADE ANTENNA (⚡ 15) ◆"
			5:
				is_maxed = true
				prompt_text = "◆ NOOSPHERE ANTENNA: 240px GRID ACTIVE ◆"
			6:
				prompt_text = "◆ TECH SHRINE: [E] RESEARCH ARCHIVES ◆"
			7:
				prompt_text = "◆ CYBERNETICA: [E] FABRICATE COHORTS ◆"

	if prompt_text.is_empty():
		context_banner.hide()
		return

	context_label.text = prompt_text
	var text_col = Color(0.55, 0.60, 0.68) if is_maxed else (Color(0.20, 0.88, 1.0) if can_afford else Color(0.92, 0.22, 0.18))
	context_label.add_theme_color_override("font_color", text_col)
	context_banner.show()

func _populate_slot(slot: Button, data: Dictionary, cur_scrap: int, cur_req: int):
	if not (slot is CompactSlot): return
	if data.is_empty():
		slot.hide()
		slot.cached_data.clear()
		return
	
	slot.show()
	slot.cached_data = data
	slot.key_txt = data.key
	slot.icon_type = data.icon
	slot.scrap_cost = data.scrap
	slot.req_cost = data.req
	slot.can_afford = (cur_scrap >= data.scrap and cur_req >= data.req)
	
	slot.current_rank = data.get("current_rank", 0)
	slot.max_rank = data.get("max_rank", 0)
	slot.can_upgrade = data.get("can_upgrade", false)
	
	slot.queue_redraw()

func _update_tooltip_position(slot: Button):
	if not (slot is CompactSlot): return
	var main_node = get_tree().get_first_node_in_group("main")
	var cur_scrap = main_node.scrap_amount if main_node and "scrap_amount" in main_node else 0
	var cur_req = main_node.requisition_amount if main_node and "requisition_amount" in main_node else 0

	var slot_center_x = slot.global_position.x + (slot.size.x * 0.5)
	if tooltip_card and tooltip_card.has_method("set_data"):
		tooltip_card.set_data(slot.cached_data, cur_scrap, cur_req, slot.cooldown_left, slot.is_maxed)
		tooltip_card.global_position = Vector2(slot_center_x - (tooltip_card.size.x * 0.5), slot.global_position.y - tooltip_card.size.y - 12)

# ==============================================================================
# COMPACT HUD SLOT BUTTON (HIGH-CONTRAST VECTOR ICONS)
# ==============================================================================

class CompactSlot extends Button:
	var category: String = "action"
	var slot_index: int = 0
	var key_txt: String = "1"
	var icon_type: String = "barricade"
	var scrap_cost: int = 0
	var req_cost: int = 0
	var can_afford: bool = true
	var is_selected: bool = false
	var is_maxed: bool = false
	var cooldown_left: float = 0.0
	var current_rank: int = 0
	var max_rank: int = 0
	var can_upgrade: bool = false
	var cached_data: Dictionary = {}

	func _init(cat: String, idx: int):
		category = cat
		slot_index = idx
		flat = true

	func _draw():
		var rect = Rect2(Vector2.ZERO, size)
		var is_locked = (max_rank > 0 and current_rank == 0)
		var bg_color = Color(0.06, 0.07, 0.10, 0.95)
		var border_color = Color(0.24, 0.28, 0.35)
	
		if is_locked:
			bg_color = Color(0.02, 0.03, 0.05, 0.95)
			if can_upgrade:
				var pulse = 0.6 + sin(Time.get_ticks_msec() * 0.01) * 0.4
				border_color = Color(0.20, 0.88, 1.0, pulse)
				bg_color = Color(0.02, 0.05, 0.08, 0.95)
			else:
				border_color = Color(0.18, 0.20, 0.25, 0.6)
		elif can_upgrade:
			var pulse = 0.6 + sin(Time.get_ticks_msec() * 0.01) * 0.4
			border_color = Color(0.20, 0.88, 1.0, pulse)
			bg_color = Color(0.03, 0.08, 0.12, 0.95)
		elif cooldown_left > 0.0:
			border_color = Color(1.0, 0.65, 0.15, 0.85)
		elif is_selected:
			border_color = Color(0.20, 0.88, 1.00, 1.0)
		elif not can_afford and (scrap_cost > 0 or req_cost > 0):
			border_color = Color(0.92, 0.22, 0.18, 0.65)
			bg_color = Color(0.10, 0.04, 0.04, 0.90)
		elif is_hovered():
			border_color = Color(0.95, 0.78, 0.35)

		draw_rect(rect, bg_color, true)

		_draw_icon(rect.get_center(), is_locked)

		if cooldown_left > 0.0:
			draw_rect(rect, Color(0.02, 0.03, 0.05, 0.78), true)
			var font = ThemeDB.fallback_font
			var cd_text = "%.1f" % cooldown_left if cooldown_left < 10.0 else "%d" % int(ceil(cooldown_left))
			var text_size = 13 if cooldown_left < 10.0 else 15
			var t_pos = Vector2(0, (size.y * 0.5) + 4.0)

			draw_string(font, t_pos + Vector2(1, 1), cd_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, text_size, Color.BLACK)
			draw_string(font, t_pos, cd_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, text_size, Color(1.0, 0.88, 0.25))

		draw_rect(rect, border_color, false, 1.8 if (can_upgrade or is_selected or cooldown_left > 0.0) else 1.2)

		var font = ThemeDB.fallback_font
		if is_locked and not can_upgrade:
			draw_string(font, Vector2(3, 10), "🔒", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.40, 0.44, 0.50))
		else:
			var key_col = Color(0.20, 0.88, 1.0) if (is_selected or can_upgrade) else (Color(0.50, 0.54, 0.60) if is_locked else Color(0.85, 0.88, 0.92))
			draw_string(font, Vector2(3, 10), key_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, key_col)

		if can_upgrade:
			var plus_rect = Rect2(size.x - 14, 2, 12, 10)
			draw_rect(plus_rect, Color(0.04, 0.05, 0.08, 0.9), true)
			draw_rect(plus_rect, Color(0.20, 0.88, 1.0), false, 1.0)
			draw_string(font, Vector2(size.x - 12, 10), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.20, 0.88, 1.0))

		if max_rank > 0:
			_draw_rank_pips(rect)

	func _draw_rank_pips(rect: Rect2):
		var pips_y = rect.size.y - 4.0
		var start_x = (rect.size.x - (max_rank * 6.0)) * 0.5
		for i in range(max_rank):
			var pip_pos = Vector2(start_x + (i * 6.0) + 2.0, pips_y)
			if i < current_rank:
				draw_circle(pip_pos, 1.8, Color(0.20, 0.88, 1.0))
			else:
				draw_circle(pip_pos, 1.2, Color(0.25, 0.28, 0.35))

	func _draw_icon(center: Vector2, is_locked: bool = false):
		var p_mid := Vector2(center.x, center.y - 1.0)

		var gold  := Color(0.40, 0.42, 0.48, 0.45) if is_locked else Color(0.82, 0.62, 0.24)
		var cyan  := Color(0.35, 0.38, 0.44, 0.45) if is_locked else Color(0.20, 0.88, 1.00)
		var red   := Color(0.32, 0.34, 0.38, 0.45) if is_locked else Color(0.90, 0.22, 0.18)
		var steel := Color(0.25, 0.27, 0.30, 0.40) if is_locked else Color(0.45, 0.50, 0.58)
		var green := Color(0.35, 0.38, 0.42, 0.45) if is_locked else Color(0.35, 0.95, 0.45)
		var amber := Color(0.42, 0.44, 0.48, 0.45) if is_locked else Color(1.00, 0.72, 0.15)
		var white := Color(0.50, 0.54, 0.60, 0.50) if is_locked else Color.WHITE

		match icon_type:
			"barricade":
				var wall_poly = PackedVector2Array([
					p_mid + Vector2(-7, -8), p_mid + Vector2(7, -8),
					p_mid + Vector2(9, 4), p_mid + Vector2(0, 9), p_mid + Vector2(-9, 4)
				])
				draw_colored_polygon(wall_poly, red)
				draw_polyline(wall_poly, gold, 1.4)
				draw_line(p_mid + Vector2(-8, 0), p_mid + Vector2(8, 0), gold, 1.8)
				draw_line(p_mid + Vector2(0, -8), p_mid + Vector2(0, 9), steel, 2.0)

			"turret":
				draw_circle(p_mid + Vector2(0, 2), 7.0, red)
				draw_circle(p_mid + Vector2(0, 2), 7.0, gold, false, 1.4)
				draw_line(p_mid + Vector2(-3, 0), p_mid + Vector2(-3, -10), steel, 2.5)
				draw_line(p_mid + Vector2(3, 0), p_mid + Vector2(3, -10), steel, 2.5)
				draw_circle(p_mid + Vector2(-3, -10), 1.2, cyan)
				draw_circle(p_mid + Vector2(3, -10), 1.2, cyan)

			"distributor":
				draw_line(p_mid + Vector2(0, 9), p_mid + Vector2(0, -7), steel, 3.0)
				draw_arc(p_mid + Vector2(0, -7), 5.5, 0, TAU, 16, cyan, 1.8)
				draw_circle(p_mid + Vector2(0, -7), 2.2, amber)
				draw_circle(p_mid + Vector2(0, -7), 1.0, white)

			"generator":
				draw_rect(Rect2(p_mid - Vector2(7, 7), Vector2(14, 14)), red)
				draw_rect(Rect2(p_mid - Vector2(7, 7), Vector2(14, 14)), gold, false, 1.2)
				draw_circle(p_mid, 4.5, cyan)
				draw_arc(p_mid, 4.5, 0, TAU, 14, white, 1.0)

			"foundry":
				draw_rect(Rect2(p_mid - Vector2(8, 2), Vector2(16, 10)), steel)
				draw_line(p_mid + Vector2(-4, -2), p_mid + Vector2(-4, -9), steel, 3.0)
				draw_line(p_mid + Vector2(4, -2), p_mid + Vector2(4, -9), steel, 3.0)
				draw_circle(p_mid + Vector2(-4, -9), 1.5, amber)
				draw_circle(p_mid + Vector2(4, -9), 1.5, amber)
				draw_circle(p_mid + Vector2(0, 3), 3.0, amber)

			"shrine":
				var arch = PackedVector2Array([
					p_mid + Vector2(-7, 8), p_mid + Vector2(-7, -2),
					p_mid + Vector2(0, -9), p_mid + Vector2(7, -2), p_mid + Vector2(7, 8)
				])
				draw_colored_polygon(arch, red)
				draw_polyline(arch, gold, 1.4)
				draw_circle(p_mid + Vector2(0, 1), 2.8, green)

			"cybernetica":
				draw_rect(Rect2(p_mid - Vector2(8, 6), Vector2(16, 14)), steel)
				draw_rect(Rect2(p_mid - Vector2(8, 6), Vector2(16, 14)), gold, false, 1.2)
				draw_circle(p_mid + Vector2(0, 1), 4.5, red)
				draw_circle(p_mid + Vector2(0, 1), 2.2, cyan)

			"axe":
				draw_line(p_mid + Vector2(-6, 7), p_mid + Vector2(6, -7), steel, 3.0)
				draw_circle(p_mid + Vector2(4, -5), 3.5, gold)
				draw_colored_polygon(PackedVector2Array([p_mid + Vector2(2, -9), p_mid + Vector2(8, -9), p_mid + Vector2(7, -1)]), cyan)
				draw_circle(p_mid + Vector2(4, -5), 1.2, white)

			"plasma_pistol":
				draw_rect(Rect2(p_mid + Vector2(-7, -2), Vector2(14, 5)), steel)
				draw_rect(Rect2(p_mid + Vector2(-4, -4), Vector2(8, 3)), cyan)
				draw_circle(p_mid + Vector2(7, 0), 1.8, white)

			"flamer":
				draw_rect(Rect2(p_mid + Vector2(-8, -2), Vector2(8, 4)), steel)
				var flame_pts = PackedVector2Array([p_mid + Vector2(0, -5), p_mid + Vector2(8, -8), p_mid + Vector2(6, 0), p_mid + Vector2(8, 8), p_mid + Vector2(0, 5)])
				draw_colored_polygon(flame_pts, amber)
				draw_circle(p_mid + Vector2(2, 0), 2.5, white if is_locked else Color(1.0, 0.9, 0.3))

			"melta":
				draw_rect(Rect2(p_mid + Vector2(-8, -3), Vector2(10, 6)), steel)
				draw_circle(p_mid + Vector2(4, 0), 4.5, red if not is_locked else amber)
				draw_circle(p_mid + Vector2(4, 0), 2.0, white)

			"seraphim_dash":
				draw_colored_polygon(PackedVector2Array([p_mid + Vector2(-6, 4), p_mid + Vector2(6, -6), p_mid + Vector2(2, 6)]), gold)
				draw_line(p_mid + Vector2(-7, 5), p_mid + Vector2(-3, 8), amber, 2.0)
				draw_circle(p_mid + Vector2(2, -2), 1.5, white)

			"holy_grenade":
				draw_circle(p_mid + Vector2(0, 2), 5.5, gold)
				draw_line(p_mid + Vector2(-3, -5), p_mid + Vector2(3, -5), white, 1.6)
				draw_line(p_mid + Vector2(0, -8), p_mid + Vector2(0, -2), white, 1.6)

			"miracle_shield":
				var sh_s = PackedVector2Array([p_mid + Vector2(-6, -6), p_mid + Vector2(6, -6), p_mid + Vector2(5, 3), p_mid + Vector2(0, 8), p_mid + Vector2(-5, 3)])
				draw_colored_polygon(sh_s, red if not is_locked else steel)
				draw_polyline(sh_s, gold, 1.4)
				draw_circle(p_mid + Vector2(0, 1), 2.0, cyan)

			"righteous_pyre":
				draw_line(p_mid + Vector2(0, -9), p_mid + Vector2(0, 9), white, 3.0)
				draw_arc(p_mid, 7.0, 0, TAU, 16, gold, 1.4)
				draw_circle(p_mid, 2.5, amber)

			"celestine_wings":
				var l_w = PackedVector2Array([p_mid + Vector2(-2, 3), p_mid + Vector2(-8, -6), p_mid + Vector2(-3, 0)])
				var r_w = PackedVector2Array([p_mid + Vector2(2, 3), p_mid + Vector2(8, -6), p_mid + Vector2(3, 0)])
				draw_colored_polygon(l_w, gold)
				draw_colored_polygon(r_w, gold)
				draw_arc(p_mid + Vector2(0, -5), 3.0, 0, TAU, 12, white, 1.2)

			"radium_carbine":
				draw_line(p_mid + Vector2(-8, 2), p_mid + Vector2(8, -1), steel, 2.5)
				draw_rect(Rect2(p_mid + Vector2(0, -3), Vector2(5, 3)), green)
				draw_circle(p_mid + Vector2(8, -1), 1.5, white)

			"doctrina_conq":
				draw_line(p_mid + Vector2(-7, -7), p_mid + Vector2(7, 7), amber, 2.2)
				draw_line(p_mid + Vector2(-7, 7), p_mid + Vector2(7, -7), amber, 2.2)
				draw_circle(p_mid, 2.5, red)

			"doctrina_prot":
				draw_arc(p_mid, 7.0, 0, TAU, 20, cyan, 2.0)
				draw_circle(p_mid, 2.5, cyan)

			"orbital":
				draw_arc(p_mid, 7.0, 0, TAU, 20, cyan, 1.2)
				draw_line(p_mid + Vector2(0, -9), p_mid + Vector2(0, 9), cyan, 2.2)
				draw_line(p_mid + Vector2(-9, 0), p_mid + Vector2(9, 0), cyan, 2.2)
				draw_circle(p_mid, 2.5, white)

			"attack_move":
				draw_line(p_mid + Vector2(-6, 6), p_mid + Vector2(6, -6), white, 2.0)
				draw_line(p_mid + Vector2(-6, -6), p_mid + Vector2(6, 6), white, 2.0)
				draw_line(p_mid + Vector2(0, -8), p_mid + Vector2(0, -2), red, 2.0)

			"stop":
				var oct = PackedVector2Array([p_mid + Vector2(-6, -3), p_mid + Vector2(-3, -6), p_mid + Vector2(3, -6), p_mid + Vector2(6, -3), p_mid + Vector2(6, 3), p_mid + Vector2(3, 6), p_mid + Vector2(-3, 6), p_mid + Vector2(-6, 3)])
				draw_colored_polygon(oct, red)
				draw_polyline(oct, white, 1.2)

			"hold_ground":
				var shield = PackedVector2Array([p_mid + Vector2(-6, -6), p_mid + Vector2(6, -6), p_mid + Vector2(6, 2), p_mid + Vector2(0, 7), p_mid + Vector2(-6, 2)])
				draw_colored_polygon(shield, steel)
				draw_polyline(shield, gold, 1.4)

			"auspex_paint":
				var r = 6.5
				draw_arc(p_mid, r, 0, TAU, 16, cyan, 1.4)
				draw_circle(p_mid, 1.8, red)

			"cam_lock":
				draw_arc(p_mid, 6.5, 0, TAU, 16, gold, 1.2)
				draw_circle(p_mid, 3.5, red)

			"recruit_ranger":
				draw_line(p_mid + Vector2(-8, 3), p_mid + Vector2(8, -3), steel, 3.0)
				draw_circle(p_mid + Vector2(9, -3), 1.2, cyan)

			"recruit_sicarian":
				draw_line(p_mid + Vector2(-7, 6), p_mid + Vector2(7, -6), cyan, 2.5)
				draw_line(p_mid + Vector2(-7, -6), p_mid + Vector2(7, 6), cyan, 2.5)

			"recruit_vanguard":
				draw_circle(p_mid, 5.5, red)
				draw_circle(p_mid + Vector2(0, -1), 2.0, green)

			"skull":
				draw_circle(p_mid, 5.0, gold)
				draw_circle(p_mid + Vector2(1.5, -0.5), 1.5, cyan)

# ==============================================================================
# TOOLTIP CARD
# ==============================================================================

class TooltipCard extends PanelContainer:
	var title_lbl: Label
	var sub_lbl: Label
	var cost_lbl: Label
	var desc_lbl: Label
	var flavor_lbl: Label

	func _init():
		custom_minimum_size = Vector2(320, 0)
		_setup_ui()

	func _setup_ui():
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.05, 0.08, 0.96)
		sb.border_color = Color(0.82, 0.62, 0.24)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		sb.shadow_color = Color(0, 0, 0, 0.65)
		sb.shadow_size = 6
		add_theme_stylebox_override("panel", sb)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		add_child(vbox)

		title_lbl = Label.new()
		title_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
		title_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(title_lbl)

		sub_lbl = Label.new()
		sub_lbl.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
		sub_lbl.add_theme_font_size_override("font_size", 9)
		vbox.add_child(sub_lbl)

		cost_lbl = Label.new()
		cost_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(cost_lbl)

		var sep = ColorRect.new()
		sep.custom_minimum_size = Vector2(0, 1)
		sep.color = Color(0.25, 0.28, 0.35, 0.6)
		vbox.add_child(sep)

		desc_lbl = Label.new()
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
		desc_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(desc_lbl)

		flavor_lbl = Label.new()
		flavor_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor_lbl.add_theme_color_override("font_color", Color(0.72, 0.65, 0.50))
		flavor_lbl.add_theme_font_size_override("font_size", 9)
		vbox.add_child(flavor_lbl)

	func set_data(data: Dictionary, cur_scrap: int, cur_req: int, cooldown_left: float = 0.0, is_maxed: bool = false):
		title_lbl.text = "◆ %s [%s] ◆" % [data.get("name", "").to_upper(), data.get("key", "")]
		sub_lbl.text = data.get("sub", "").to_upper()
		desc_lbl.text = data.get("desc", "")
		flavor_lbl.text = data.get("flavor", "")

		var scrap = data.get("scrap", 0)
		var req = data.get("req", 0)
		var max_r = data.get("max_rank", 0)
		var cur_r = data.get("current_rank", 0)
		var can_up = data.get("can_upgrade", false)

		if cooldown_left > 0.0:
			cost_lbl.text = "⏳ RECHARGING (%.1fs Remaining)" % cooldown_left
			cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.15))
		elif max_r > 0 and cur_r == 0:
			if can_up:
				cost_lbl.text = "✨ UNLOCK: CLICK SLOT OR PRESS [CTRL+KEY]"
				cost_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
			else:
				cost_lbl.text = "🔒 LOCKED: EARN MIRACLE POINTS ON LEVEL-UP"
				cost_lbl.add_theme_color_override("font_color", Color(0.75, 0.35, 0.35))
		elif is_maxed:
			cost_lbl.text = "◆ PROTOCOL MAXED ◆"
			cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
		elif scrap == 0 and req == 0:
			cost_lbl.text = "STATUS: NOOSPHERIC LINK ACTIVE"
			cost_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
		else:
			var parts: Array[String] = []
			if scrap > 0: parts.append("⚙ %d SCRAP" % scrap)
			if req > 0: parts.append("⚡ %d REQ" % req)
			var can_afford = (cur_scrap >= scrap and cur_req >= req)
			cost_lbl.text = "COST: " + "   ".join(parts)
			cost_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45) if can_afford else Color(0.92, 0.22, 0.18))
