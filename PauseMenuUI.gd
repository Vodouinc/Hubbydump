# res://PauseMenuUI.gd
extends Control
class_name PauseMenuUI

enum View { MAIN, VIDEO, AUDIO, CONTROLS }
var current_view: View = View.MAIN

# Node References
var panel_container: PanelContainer = null
var main_view_box: VBoxContainer = null
var video_view_box: VBoxContainer = null
var audio_view_box: VBoxContainer = null
var controls_view_box: VBoxContainer = null
var ally_pause_banner: PanelContainer = null

# Top Navigation Bar (Shown when opened from Title Screen)
var title_nav_hbox: HBoxContainer = null

# Audio Controls
var master_slider: HSlider = null
var music_slider: HSlider = null
var sfx_slider: HSlider = null
var master_lbl: Label = null
var music_lbl: Label = null
var sfx_lbl: Label = null

# Video Controls
var window_mode_btn: Button = null
var vsync_btn: Button = null
var fps_btn: Button = null

# Keybind Controls
var keybind_buttons: Dictionary = {}
var current_rebinding_action: String = ""
var rebinding_dialog_lbl: Label = null
const KEYBINDS_FILE = "user://custom_keybinds.cfg"

const ACTION_DEFS: Array[Dictionary] = [
	{"id": "action_primary", "name": "Primary Fire / Attack", "default_key": KEY_NONE, "default_mouse": MOUSE_BUTTON_LEFT, "default_joy": JOY_AXIS_TRIGGER_RIGHT, "is_axis": true},
	{"id": "action_secondary", "name": "Secondary Fire / Special", "default_key": KEY_NONE, "default_mouse": MOUSE_BUTTON_RIGHT, "default_joy": JOY_AXIS_TRIGGER_LEFT, "is_axis": true},
	{"id": "action_dash", "name": "Seraphim Dash / Mobility", "default_key": KEY_SPACE, "default_joy": JOY_BUTTON_A},
	{"id": "action_ability_1", "name": "Ability 1 (Sanctuary / Wall)", "default_key": KEY_1, "default_joy": JOY_BUTTON_X},
	{"id": "action_ability_2", "name": "Ability 2 (Grenade / Turret)", "default_key": KEY_2, "default_joy": JOY_BUTTON_Y},
	{"id": "action_ability_3", "name": "Ability 3 (Faith / Relay)", "default_key": KEY_3, "default_joy": JOY_BUTTON_B},
	{"id": "action_ability_4", "name": "Ultimate [4] (Pyre / Dynamo)", "default_key": KEY_4, "default_joy": JOY_BUTTON_RIGHT_SHOULDER},
	{"id": "action_interact", "name": "Interact / Sanctum Terminal", "default_key": KEY_E, "default_joy": JOY_BUTTON_LEFT_SHOULDER},
	{"id": "action_drone", "name": "Deploy Drone / Supply", "default_key": KEY_C, "default_joy": JOY_BUTTON_DPAD_UP},
	{"id": "action_map", "name": "Tactical Minimap [M]", "default_key": KEY_M, "default_joy": JOY_BUTTON_BACK},
	{"id": "action_pause", "name": "Pause Menu / Escape", "default_key": KEY_ESCAPE, "default_joy": JOY_BUTTON_START}
]

const VIDEO_SETTINGS_FILE = "user://video_settings.cfg"
var current_window_mode: int = DisplayServer.WINDOW_MODE_WINDOWED
var is_vsync_enabled: bool = true
var current_max_fps: int = 0

var backdrop_rect: ColorRect = null
var center_container: CenterContainer = null
var is_opened_from_title: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	add_to_group("pause_menu")
	theme = AdmechTheme.make()
	hide()
	_init_input_map()
	_load_custom_keybinds()
	_load_video_settings()
	_build_ui_layout()

func _init_input_map() -> void:
	for def in ACTION_DEFS:
		var act = def["id"]
		if not InputMap.has_action(act):
			InputMap.add_action(act)

func _load_custom_keybinds() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(KEYBINDS_FILE) == OK:
		for def in ACTION_DEFS:
			var act = def["id"]
			if cfg.has_section_key("keybinds", act):
				var saved_event = cfg.get_value("keybinds", act)
				if saved_event is InputEvent:
					InputMap.action_erase_events(act)
					InputMap.action_add_event(act, saved_event)

func _save_custom_keybinds() -> void:
	var cfg = ConfigFile.new()
	for def in ACTION_DEFS:
		var act = def["id"]
		var events = InputMap.action_get_events(act)
		if not events.is_empty():
			cfg.set_value("keybinds", act, events[0])
	cfg.save(KEYBINDS_FILE)

func open_settings_from_title():
	is_opened_from_title = true
	_update_layout_size()
	panel_container.show()
	ally_pause_banner.hide()
	show()
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
	_switch_view(View.VIDEO)

func _on_settings_back_pressed():
	if is_opened_from_title:
		is_opened_from_title = false
		panel_container.hide()
		hide()
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node and main_node.has_method("_show_title_screen"):
			main_node._show_title_screen()
	else:
		_switch_view(View.MAIN)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if not visible and not get_tree().paused:
				_restore_gameplay_cursor_mode()

func _unhandled_input(event: InputEvent) -> void:
	if current_rebinding_action.is_empty():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			toggle_my_pause_menu()
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if current_rebinding_action.is_empty(): return

	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event.is_pressed():
			if event is InputEventKey and event.keycode == KEY_ESCAPE:
				_cancel_rebinding()
				get_viewport().set_input_as_handled()
				return

			_apply_rebind(current_rebinding_action, event)
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if visible:
		_update_layout_size()

func _update_layout_size() -> void:
	var vp = get_viewport_rect().size
	size = vp
	if is_instance_valid(backdrop_rect): backdrop_rect.size = vp
	if is_instance_valid(center_container): center_container.size = vp
	if is_instance_valid(ally_pause_banner):
		ally_pause_banner.position = Vector2((vp.x - 400.0) * 0.5, 32.0)
		ally_pause_banner.size = Vector2(400.0, 56.0)

func _build_ui_layout():
	z_index = 200
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vp = get_viewport_rect().size
	size = vp

	backdrop_rect = ColorRect.new()
	backdrop_rect.name = "Backdrop"
	backdrop_rect.size = vp
	backdrop_rect.color = Color(0.02, 0.03, 0.05, 0.85)
	backdrop_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(backdrop_rect)

	_build_ally_pause_banner()

	center_container = CenterContainer.new()
	center_container.size = vp
	center_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center_container)

	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(560, 440)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	center_container.add_child(pc)
	panel_container = pc

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	panel_container.add_child(root_vbox)

	# --- TITLE SCREEN VIEW SELECTOR HEADER ---
	title_nav_hbox = HBoxContainer.new()
	title_nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_nav_hbox.add_theme_constant_override("separation", 8)
	root_vbox.add_child(title_nav_hbox)

	var nav_vid_btn = _create_btn("VIDEO", func(): _switch_view(View.VIDEO))
	var nav_aud_btn = _create_btn("AUDIO", func(): _switch_view(View.AUDIO))
	var nav_ctrl_btn = _create_btn("KEYBINDS & CONTROLS", func(): _switch_view(View.CONTROLS))
	title_nav_hbox.add_child(nav_vid_btn)
	title_nav_hbox.add_child(nav_aud_btn)
	title_nav_hbox.add_child(nav_ctrl_btn)

	# --- VIEW 1: MAIN PAUSE VIEW ---
	main_view_box = VBoxContainer.new()
	main_view_box.add_theme_constant_override("separation", 10)
	root_vbox.add_child(main_view_box)

	var title = Label.new()
	title.text = "◆ TACTICAL COGITATION HOLD ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	title.add_theme_font_size_override("font_size", 15)
	main_view_box.add_child(title)

	var resume_btn = _create_btn("RESUME OPERATIONS [ESC]", func(): toggle_my_pause_menu())
	var video_btn = _create_btn("VIDEO PROTOCOLS", func(): _switch_view(View.VIDEO))
	var audio_btn = _create_btn("AUDIO PROTOCOLS", func(): _switch_view(View.AUDIO))
	var ctrl_btn = _create_btn("KEYBINDS & CONTROLLER MAP", func(): _switch_view(View.CONTROLS))
	var exit_menu_btn = _create_btn("DISENGAGE TO LOBBY", func(): _on_exit_to_lobby())
	var exit_game_btn = _create_btn("SHUT DOWN INTERFACE", func(): get_tree().quit())
	
	main_view_box.add_child(resume_btn)
	main_view_box.add_child(video_btn)
	main_view_box.add_child(audio_btn)
	main_view_box.add_child(ctrl_btn)
	main_view_box.add_child(exit_menu_btn)
	main_view_box.add_child(exit_game_btn)

	# --- VIEW 2: VIDEO SETTINGS VIEW ---
	video_view_box = VBoxContainer.new()
	video_view_box.add_theme_constant_override("separation", 12)
	video_view_box.hide()
	root_vbox.add_child(video_view_box)

	var vid_title = Label.new()
	vid_title.text = "◆ VISUAL OCULAR SETTINGS ◆"
	vid_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vid_title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	video_view_box.add_child(vid_title)

	window_mode_btn = _create_btn("WINDOW MODE: " + _get_window_mode_name(), func(): _cycle_window_mode())
	vsync_btn = _create_btn("V-SYNC: " + ("ENABLED" if is_vsync_enabled else "DISABLED"), func(): _toggle_vsync())
	fps_btn = _create_btn("MAX FPS: " + _get_fps_name(), func(): _cycle_max_fps())
	var vid_back_btn = _create_btn("BACK [ESC]", func(): _on_settings_back_pressed())

	video_view_box.add_child(window_mode_btn)
	video_view_box.add_child(vsync_btn)
	video_view_box.add_child(fps_btn)
	video_view_box.add_child(vid_back_btn)

	# --- VIEW 3: AUDIO SETTINGS VIEW ---
	audio_view_box = VBoxContainer.new()
	audio_view_box.add_theme_constant_override("separation", 12)
	audio_view_box.hide()
	root_vbox.add_child(audio_view_box)

	var aud_title = Label.new()
	aud_title.text = "◆ AUDIO COGITATION PROTOCOLS ◆"
	aud_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aud_title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	audio_view_box.add_child(aud_title)

	var m_row = _create_slider_row("Master Output", AudioManager.master_volume)
	master_slider = m_row.slider; master_lbl = m_row.val_lbl
	master_slider.value_changed.connect(func(v): AudioManager.set_master_volume(v); master_lbl.text = str(int(v*100)) + "%")
	audio_view_box.add_child(m_row.container)

	var mus_row = _create_slider_row("Machine Hymn (Music)", AudioManager.music_volume)
	music_slider = mus_row.slider; music_lbl = mus_row.val_lbl
	music_slider.value_changed.connect(func(v): AudioManager.set_music_volume(v); music_lbl.text = str(int(v*100)) + "%")
	audio_view_box.add_child(mus_row.container)

	var sfx_row = _create_slider_row("Combat SFX", AudioManager.sfx_volume)
	sfx_slider = sfx_row.slider; sfx_lbl = sfx_row.val_lbl
	sfx_slider.value_changed.connect(func(v): AudioManager.set_sfx_volume(v); sfx_lbl.text = str(int(v*100)) + "%")
	audio_view_box.add_child(sfx_row.container)

	var aud_back_btn = _create_btn("BACK [ESC]", func(): _on_settings_back_pressed())
	audio_view_box.add_child(aud_back_btn)

	# --- VIEW 4: KEYBINDS & CONTROLLER VIEW ---
	controls_view_box = VBoxContainer.new()
	controls_view_box.add_theme_constant_override("separation", 8)
	controls_view_box.hide()
	root_vbox.add_child(controls_view_box)

	var ctrl_title = Label.new()
	ctrl_title.text = "◆ KEYBINDS & CONTROLLER REBINDING ◆"
	ctrl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctrl_title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	controls_view_box.add_child(ctrl_title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_view_box.add_child(scroll)

	var key_tab = VBoxContainer.new()
	key_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_tab.add_theme_constant_override("separation", 5)
	scroll.add_child(key_tab)

	keybind_buttons.clear()
	for def in ACTION_DEFS:
		var act_id = def["id"]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		key_tab.add_child(row)

		var act_lbl = Label.new()
		act_lbl.text = "• " + def["name"]
		act_lbl.custom_minimum_size = Vector2(220, 0)
		act_lbl.add_theme_font_size_override("font_size", 9)
		act_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
		row.add_child(act_lbl)

		var btn = _create_btn(_get_action_display_string(act_id), func(): _start_rebinding(act_id, keybind_buttons[act_id]))
		btn.custom_minimum_size = Vector2(200, 24)
		btn.add_theme_font_size_override("font_size", 8)
		row.add_child(btn)
		keybind_buttons[act_id] = btn

	rebinding_dialog_lbl = Label.new()
	rebinding_dialog_lbl.text = ""
	rebinding_dialog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rebinding_dialog_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	rebinding_dialog_lbl.add_theme_font_size_override("font_size", 9)
	controls_view_box.add_child(rebinding_dialog_lbl)

	var ctrl_btn_row = HBoxContainer.new()
	ctrl_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_btn_row.add_theme_constant_override("separation", 10)
	controls_view_box.add_child(ctrl_btn_row)

	var reset_btn = _create_btn("↺ DEFAULTS", func(): _reset_all_to_defaults())
	reset_btn.custom_minimum_size = Vector2(130, 28)
	ctrl_btn_row.add_child(reset_btn)

	var ctrl_back_btn = _create_btn("BACK [ESC]", func(): _on_settings_back_pressed())
	ctrl_back_btn.custom_minimum_size = Vector2(130, 28)
	ctrl_btn_row.add_child(ctrl_back_btn)

func _get_action_display_string(act_id: String) -> String:
	var events = InputMap.action_get_events(act_id)
	if events.is_empty(): return "[UNBOUND]"
	var parts: Array[String] = []
	for ev in events:
		if ev is InputEventKey:
			parts.append(OS.get_keycode_string(ev.keycode if ev.keycode != 0 else ev.physical_keycode))
		elif ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: parts.append("LMB")
				MOUSE_BUTTON_RIGHT: parts.append("RMB")
				MOUSE_BUTTON_MIDDLE: parts.append("MMB")
				_: parts.append("Mouse %d" % ev.button_index)
		elif ev is InputEventJoypadButton:
			match ev.button_index:
				JOY_BUTTON_A: parts.append("A / ✕")
				JOY_BUTTON_B: parts.append("B / ○")
				JOY_BUTTON_X: parts.append("X / □")
				JOY_BUTTON_Y: parts.append("Y / △")
				JOY_BUTTON_LEFT_SHOULDER: parts.append("L1 / LB")
				JOY_BUTTON_RIGHT_SHOULDER: parts.append("R1 / RB")
				JOY_BUTTON_START: parts.append("Start")
				JOY_BUTTON_BACK: parts.append("Back")
				_: parts.append("Joy %d" % ev.button_index)
		elif ev is InputEventJoypadMotion:
			match ev.axis:
				JOY_AXIS_TRIGGER_LEFT: parts.append("L2 / LT")
				JOY_AXIS_TRIGGER_RIGHT: parts.append("R2 / RT")
				_: parts.append("Axis %d" % ev.axis)

	return " / ".join(parts) if not parts.is_empty() else "[UNBOUND]"

func _start_rebinding(act_id: String, btn: Button) -> void:
	current_rebinding_action = act_id
	btn.text = "⚡ Press Key/Btn..."
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	rebinding_dialog_lbl.text = "Listening for '%s' (ESC to cancel)" % act_id

func _apply_rebind(act_id: String, new_event: InputEvent) -> void:
	InputMap.action_erase_events(act_id)
	InputMap.action_add_event(act_id, new_event)
	_save_custom_keybinds()

	if keybind_buttons.has(act_id):
		var btn: Button = keybind_buttons[act_id]
		btn.text = _get_action_display_string(act_id)
		btn.remove_theme_color_override("font_color")

	rebinding_dialog_lbl.text = "✓ Remapped '%s'!" % act_id
	current_rebinding_action = ""

func _cancel_rebinding() -> void:
	if keybind_buttons.has(current_rebinding_action):
		var btn: Button = keybind_buttons[current_rebinding_action]
		btn.text = _get_action_display_string(current_rebinding_action)
		btn.remove_theme_color_override("font_color")
	rebinding_dialog_lbl.text = "Cancelled."
	current_rebinding_action = ""

func _reset_all_to_defaults() -> void:
	for def in ACTION_DEFS:
		var act = def["id"]
		InputMap.action_erase_events(act)
		if def.get("default_key", KEY_NONE) != KEY_NONE:
			var k = InputEventKey.new()
			k.keycode = def["default_key"]
			InputMap.action_add_event(act, k)
		if def.has("default_mouse"):
			var m = InputEventMouseButton.new()
			m.button_index = def["default_mouse"]
			InputMap.action_add_event(act, m)
		if def.has("default_joy"):
			if def.get("is_axis", false):
				var jm = InputEventJoypadMotion.new()
				jm.axis = def["default_joy"]
				jm.axis_value = 1.0
				InputMap.action_add_event(act, jm)
			else:
				var jb = InputEventJoypadButton.new()
				jb.button_index = def["default_joy"]
				InputMap.action_add_event(act, jb)

	_save_custom_keybinds()
	for act_id in keybind_buttons.keys():
		keybind_buttons[act_id].text = _get_action_display_string(act_id)
	rebinding_dialog_lbl.text = "↺ Controls reset to defaults."

func _switch_view(view: View):
	current_view = view
	main_view_box.visible = (view == View.MAIN and not is_opened_from_title)
	video_view_box.visible = (view == View.VIDEO)
	audio_view_box.visible = (view == View.AUDIO)
	controls_view_box.visible = (view == View.CONTROLS)
	title_nav_hbox.visible = is_opened_from_title

	# Auto-focus the first button of the new view for controller/arrow keys
	await get_tree().process_frame
	var active_box = video_view_box if view == View.VIDEO else (audio_view_box if view == View.AUDIO else (controls_view_box if view == View.CONTROLS else main_view_box))
	var first_btn = active_box.find_children("*", "Button", true, false)
	if not first_btn.is_empty():
		(first_btn[0] as Control).grab_focus()

	if view == View.VIDEO: _refresh_video_buttons()
	elif view == View.AUDIO: _refresh_audio_sliders()

func _create_btn(text: String, callable: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 32)
	btn.focus_mode = Control.FOCUS_ALL # Allows controller D-pad/Arrow navigation!
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(callable)
	return btn

func _create_slider_row(label_text: String, initial_val: float) -> Dictionary:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	var n_lbl = Label.new()
	n_lbl.text = label_text
	n_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n_lbl.add_theme_font_size_override("font_size", 10)
	n_lbl.add_theme_color_override("font_color", Color(0.90, 0.86, 0.74))
	hbox.add_child(n_lbl)

	var v_lbl = Label.new()
	v_lbl.text = str(int(initial_val * 100)) + "%"
	v_lbl.add_theme_font_size_override("font_size", 10)
	v_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	hbox.add_child(v_lbl)

	var slider = HSlider.new()
	slider.min_value = 0.0; slider.max_value = 1.0; slider.step = 0.05
	slider.value = initial_val
	slider.custom_minimum_size = Vector2(0, 18)
	slider.focus_mode = Control.FOCUS_ALL
	vbox.add_child(slider)

	return {"container": vbox, "slider": slider, "val_lbl": v_lbl}

func _build_ally_pause_banner():
	var banner = PanelContainer.new()
	banner.name = "AllyPauseBanner"
	banner.custom_minimum_size = Vector2(400, 56)
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.position = Vector2(0, 32)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	ally_pause_banner = banner
	ally_pause_banner.hide()

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ally_pause_banner.add_child(vbox)

	var p_lbl = Label.new()
	p_lbl.text = "◆ CADRE PAUSE: GAME SUSPENDED ◆"
	p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.20))
	p_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(p_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "Press [ESC] to access Pause Options"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.80))
	sub_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(sub_lbl)

func toggle_my_pause_menu():
	if visible and panel_container.visible:
		if current_view != View.MAIN:
			_switch_view(View.MAIN)
			return
		hide_my_pause_menu()
	else:
		show_my_pause_menu()

func show_my_pause_menu():
	is_opened_from_title = false
	_switch_view(View.MAIN)
	_update_layout_size()
	panel_container.show()
	ally_pause_banner.hide()
	show()
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
	_sync_pause_state_with_main(true)

func hide_my_pause_menu():
	panel_container.hide()
	hide()
	_restore_gameplay_cursor_mode()
	_sync_pause_state_with_main(false)

func _restore_gameplay_cursor_mode():
	var local_player = null
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and ((not multiplayer.has_multiplayer_peer()) or p.is_multiplayer_authority()):
			local_player = p
			break

	if is_instance_valid(local_player) and local_player.get("current_class") == 1:
		DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_CONFINED)
	else:
		DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)

func _sync_pause_state_with_main(is_paused: bool):
	var main_node = get_tree().get_first_node_in_group("main")
	if not multiplayer.has_multiplayer_peer():
		get_tree().paused = is_paused
		update_global_pause_state(is_paused)
	elif multiplayer.is_server():
		if main_node and main_node.has_method("request_set_player_paused"):
			main_node.request_set_player_paused(is_paused)
	else:
		if main_node:
			main_node.rpc_id(1, "request_set_player_paused", is_paused)

func update_global_pause_state(is_paused_globally: bool):
	get_tree().paused = is_paused_globally
	if not is_paused_globally:
		ally_pause_banner.hide()
		hide()
	else:
		if not (visible and panel_container.visible):
			panel_container.hide()
			ally_pause_banner.show()
			show()
		else:
			ally_pause_banner.hide()

func _on_exit_to_lobby():
	get_tree().paused = false
	panel_container.hide()
	hide()
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
	
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		if not multiplayer.has_multiplayer_peer(): main_node.execute_rematch()
		elif multiplayer.is_server(): main_node.rpc("execute_rematch")
		else: main_node.rpc_id(1, "request_rematch")

func _cycle_window_mode():
	match current_window_mode:
		DisplayServer.WINDOW_MODE_WINDOWED: current_window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.WINDOW_MODE_FULLSCREEN: current_window_mode = DisplayServer.WINDOW_MODE_WINDOWED
		_: current_window_mode = DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(current_window_mode)
	_refresh_video_buttons()
	_save_video_settings()

func _toggle_vsync():
	is_vsync_enabled = not is_vsync_enabled
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if is_vsync_enabled else DisplayServer.VSYNC_DISABLED)
	_refresh_video_buttons()
	_save_video_settings()

func _cycle_max_fps():
	match current_max_fps:
		0: current_max_fps = 60
		60: current_max_fps = 120
		120: current_max_fps = 144
		144: current_max_fps = 0
		_: current_max_fps = 0
	Engine.max_fps = current_max_fps
	_refresh_video_buttons()
	_save_video_settings()

func _refresh_video_buttons():
	if window_mode_btn: window_mode_btn.text = "WINDOW MODE: " + _get_window_mode_name()
	if vsync_btn: vsync_btn.text = "V-SYNC: " + ("ENABLED" if is_vsync_enabled else "DISABLED")
	if fps_btn: fps_btn.text = "MAX FPS: " + _get_fps_name()

func _get_window_mode_name() -> String:
	match current_window_mode:
		DisplayServer.WINDOW_MODE_WINDOWED: return "WINDOWED"
		DisplayServer.WINDOW_MODE_FULLSCREEN: return "BORDERLESS"
	return "WINDOWED"

func _get_fps_name() -> String:
	return "UNCAPPED" if current_max_fps == 0 else str(current_max_fps) + " FPS"

func _save_video_settings():
	var cfg = ConfigFile.new()
	cfg.set_value("video", "window_mode", current_window_mode)
	cfg.set_value("video", "vsync", is_vsync_enabled)
	cfg.set_value("video", "max_fps", current_max_fps)
	cfg.save(VIDEO_SETTINGS_FILE)

func _load_video_settings():
	var cfg = ConfigFile.new()
	if cfg.load(VIDEO_SETTINGS_FILE) == OK:
		current_window_mode = cfg.get_value("video", "window_mode", DisplayServer.WINDOW_MODE_WINDOWED)
		is_vsync_enabled = cfg.get_value("video", "vsync", true)
		current_max_fps = cfg.get_value("video", "max_fps", 0)

	if current_window_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		current_window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN

	DisplayServer.window_set_mode(current_window_mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if is_vsync_enabled else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = current_max_fps

func _refresh_audio_sliders():
	if master_slider: master_slider.value = AudioManager.master_volume
	if music_slider: music_slider.value = AudioManager.music_volume
	if sfx_slider: sfx_slider.value = AudioManager.sfx_volume
	if master_lbl: master_lbl.text = str(int(AudioManager.master_volume * 100)) + "%"
	if music_lbl: music_lbl.text = str(int(AudioManager.music_volume * 100)) + "%"
	if sfx_lbl: sfx_lbl.text = str(int(AudioManager.sfx_volume * 100)) + "%"
