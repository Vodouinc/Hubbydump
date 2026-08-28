# res://SettingsUI.gd
extends Control
class_name SettingsUI

const KEYBINDS_FILE = "user://custom_keybinds.cfg"

var tab_container: TabContainer = null
var keybind_buttons: Dictionary = {}
var current_rebinding_action: String = ""
var rebinding_dialog_lbl: Label = null

# Default action mapping definitions
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("settings_ui")
	theme = AdmechTheme.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_init_input_map()
	_load_custom_keybinds()
	_build_ui()
	hide()

func toggle_settings() -> void:
	if visible:
		hide()
	else:
		show()
		_focus_first_element()

func _focus_first_element() -> void:
	await get_tree().process_frame
	var first_slider = find_child("VolumeSlider*", true, false)
	if first_slider and first_slider is Control:
		first_slider.grab_focus()

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

func _build_ui() -> void:
	for c in get_children(): c.queue_free()

	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.88)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(740, 500)
	center.add_child(main_panel)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	main_panel.add_child(root_vbox)

	var title = Label.new()
	title.text = "◆ COGITATOR OCULAR & CONTROL PROTOCOLS ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	title.add_theme_font_size_override("font_size", 14)
	root_vbox.add_child(title)

	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(tab_container)

	_build_audio_tab()
	_build_interactive_keybinds_tab()

	rebinding_dialog_lbl = Label.new()
	rebinding_dialog_lbl.text = ""
	rebinding_dialog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rebinding_dialog_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	rebinding_dialog_lbl.add_theme_font_size_override("font_size", 11)
	root_vbox.add_child(rebinding_dialog_lbl)

	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", 20)
	root_vbox.add_child(bottom_hbox)

	var reset_btn = Button.new()
	reset_btn.text = "↺ RESET TO DEFAULTS"
	reset_btn.custom_minimum_size = Vector2(180, 32)
	reset_btn.focus_mode = Control.FOCUS_ALL
	reset_btn.pressed.connect(_reset_all_to_defaults)
	bottom_hbox.add_child(reset_btn)

	var close_btn = Button.new()
	close_btn.text = "SAVE & CLOSE [ESC]"
	close_btn.custom_minimum_size = Vector2(220, 32)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.pressed.connect(toggle_settings)
	bottom_hbox.add_child(close_btn)

func _build_audio_tab() -> void:
	var tab = VBoxContainer.new()
	tab.name = "AUDIO / OCULAR"
	tab.add_theme_constant_override("separation", 14)
	tab_container.add_child(tab)

	var sliders = [
		{"name": "Master Output Volume", "bus": "Master", "val": AudioManager.master_volume, "setter": "set_master_volume"},
		{"name": "Symphonic Battle Soundtrack", "bus": "Music", "val": AudioManager.music_volume, "setter": "set_music_volume"},
		{"name": "Weapon & Battle SFX Volume", "bus": "SFX", "val": AudioManager.sfx_volume, "setter": "set_sfx_volume"}
	]

	for s in sliders:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		tab.add_child(row)

		var lbl = Label.new()
		lbl.text = s.name
		lbl.custom_minimum_size = Vector2(240, 0)
		lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(lbl)

		var slider = HSlider.new()
		slider.name = "VolumeSlider_" + s.bus
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = s.val
		slider.custom_minimum_size = Vector2(280, 20)
		slider.focus_mode = Control.FOCUS_ALL
		slider.value_changed.connect(func(v): AudioManager.call(s.setter, v))
		row.add_child(slider)

func _build_interactive_keybinds_tab() -> void:
	var scroll = ScrollContainer.new()
	scroll.name = "KEYBINDS & CONTROLS"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(scroll)

	var tab = VBoxContainer.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 6)
	scroll.add_child(tab)

	keybind_buttons.clear()

	for def in ACTION_DEFS:
		var act_id = def["id"]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		tab.add_child(row)

		var act_lbl = Label.new()
		act_lbl.text = "• " + def["name"]
		act_lbl.custom_minimum_size = Vector2(240, 0)
		act_lbl.add_theme_font_size_override("font_size", 10)
		act_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
		row.add_child(act_lbl)

		var btn = Button.new()
		btn.name = "Btn_" + act_id
		btn.custom_minimum_size = Vector2(220, 26)
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_font_size_override("font_size", 9)
		btn.text = _get_action_display_string(act_id)
		btn.pressed.connect(_start_rebinding.bind(act_id, btn))
		row.add_child(btn)

		keybind_buttons[act_id] = btn

	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.25, 0.28, 0.35, 0.4)
	tab.add_child(sep)

	var guide_lbl = Label.new()
	guide_lbl.text = "🎮 GAMEPAD GUIDE: Left Stick = Move | Right Stick = 360° Aim | R2 = Fire | L2 = Secondary | L1 = Interact\n⚜️ QUICK UPGRADE: Tap D-PAD (Left/Up/Right/Down) or HOLD L1 + (A/X/Y/B/R1)"
	guide_lbl.add_theme_font_size_override("font_size", 8)
	guide_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	tab.add_child(guide_lbl)

func _get_action_display_string(act_id: String) -> String:
	var events = InputMap.action_get_events(act_id)
	if events.is_empty():
		return "[UNBOUND]"
	
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
	btn.text = "⚡ Press Key / Button..."
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	rebinding_dialog_lbl.text = "Listening: Press any Keyboard Key, Mouse Button, or Controller Button for '%s' (ESC to cancel)" % act_id

func _input(event: InputEvent) -> void:
	if current_rebinding_action.is_empty():
		# Controller D-Pad Navigation fallback if focus is lost
		if visible and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			if get_viewport().gui_get_focus_owner() == null:
				_focus_first_element()
		return

	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event.is_pressed():
			# Cancel with ESC
			if event is InputEventKey and event.keycode == KEY_ESCAPE:
				_cancel_rebinding()
				get_viewport().set_input_as_handled()
				return

			_apply_rebind(current_rebinding_action, event)
			get_viewport().set_input_as_handled()

func _apply_rebind(act_id: String, new_event: InputEvent) -> void:
	InputMap.action_erase_events(act_id)
	InputMap.action_add_event(act_id, new_event)
	_save_custom_keybinds()

	if keybind_buttons.has(act_id):
		var btn: Button = keybind_buttons[act_id]
		btn.text = _get_action_display_string(act_id)
		btn.remove_theme_color_override("font_color")

	rebinding_dialog_lbl.text = "✓ Remapped '%s' successfully!" % act_id
	current_rebinding_action = ""

func _cancel_rebinding() -> void:
	if keybind_buttons.has(current_rebinding_action):
		var btn: Button = keybind_buttons[current_rebinding_action]
		btn.text = _get_action_display_string(current_rebinding_action)
		btn.remove_theme_color_override("font_color")
	rebinding_dialog_lbl.text = "Rebinding cancelled."
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
	rebinding_dialog_lbl.text = "↺ All controls reset to holy factory standards."
