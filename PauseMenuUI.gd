extends Control
class_name PauseMenuUI

enum View { MAIN, VIDEO, AUDIO }
var current_view: View = View.MAIN

# Node References
var panel_container: PanelContainer = null
var main_view_box: VBoxContainer = null
var video_view_box: VBoxContainer = null
var audio_view_box: VBoxContainer = null
var ally_pause_banner: PanelContainer = null

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

const VIDEO_SETTINGS_FILE = "user://video_settings.cfg"
var current_window_mode: int = DisplayServer.WINDOW_MODE_WINDOWED
var is_vsync_enabled: bool = true
var current_max_fps: int = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	theme = AdmechTheme.make()
	hide()
	_load_video_settings()
	_build_ui_layout()

# ==============================================================================
# 1. INPUT HANDLING (SINGLE SOURCE OF TRUTH FOR PAUSE TOGGLE)
# ==============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggle_my_pause_menu()
		get_viewport().set_input_as_handled()

# ==============================================================================
# 2. UI LAYOUT & VIEWS
# ==============================================================================
func _build_ui_layout():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 1. Dark Backdrop
	var backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.75)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(backdrop)

	# 2. Ally Pause Banner
	_build_ally_pause_banner()

	# 3. Main Center Menu Container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(460, 380)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(pc)
	panel_container = pc

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	panel_container.add_child(root_vbox)

	# --- VIEW 1: MAIN PAUSE VIEW ---
	main_view_box = VBoxContainer.new()
	main_view_box.add_theme_constant_override("separation", 10)
	root_vbox.add_child(main_view_box)

	var title = Label.new()
	title.text = "◆ TACTICAL COGITATION HOLD ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	main_view_box.add_child(title)

	var resume_btn = _create_btn("RESUME OPERATIONS [ESC]", func(): toggle_my_pause_menu())
	var video_btn = _create_btn("VIDEO PROTOCOLS", func(): _switch_view(View.VIDEO))
	var audio_btn = _create_btn("AUDIO PROTOCOLS", func(): _switch_view(View.AUDIO))
	var exit_menu_btn = _create_btn("DISENGAGE TO LOBBY", func(): _on_exit_to_lobby())
	var exit_game_btn = _create_btn("SHUT DOWN INTERFACE", func(): get_tree().quit())
	
	main_view_box.add_child(resume_btn)
	main_view_box.add_child(video_btn)
	main_view_box.add_child(audio_btn)
	main_view_box.add_child(exit_menu_btn)
	main_view_box.add_child(exit_game_btn)

	var status_lbl = Label.new()
	status_lbl.text = "◆ STATUS: SYSTEM PAUSED ◆"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.20))
	status_lbl.add_theme_font_size_override("font_size", 11)
	main_view_box.add_child(status_lbl)

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
	var vid_back_btn = _create_btn("BACK [ESC]", func(): _switch_view(View.MAIN))

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

	var aud_back_btn = _create_btn("BACK [ESC]", func(): _switch_view(View.MAIN))
	audio_view_box.add_child(aud_back_btn)

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
	p_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(p_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "Press [ESC] to access Pause Options"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.80))
	sub_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(sub_lbl)

func _switch_view(view: View):
	current_view = view
	main_view_box.visible = (view == View.MAIN)
	video_view_box.visible = (view == View.VIDEO)
	audio_view_box.visible = (view == View.AUDIO)
	
	if view == View.VIDEO:
		_refresh_video_buttons()
	elif view == View.AUDIO:
		_refresh_audio_sliders()

# ==============================================================================
# 3. PAUSE & UNPAUSE LOGIC (OFFLINE & NETWORK RESILIENT)
# ==============================================================================
func toggle_my_pause_menu():
	if visible and panel_container.visible:
		if current_view != View.MAIN:
			_switch_view(View.MAIN)
			return
		hide_my_pause_menu()
	else:
		show_my_pause_menu()

func show_my_pause_menu():
	_switch_view(View.MAIN)
	panel_container.show()
	ally_pause_banner.hide()
	show()
	_sync_pause_state_with_main(true)

func hide_my_pause_menu():
	panel_container.hide()
	hide()
	_sync_pause_state_with_main(false)

func _sync_pause_state_with_main(is_paused: bool):
	var main_node = get_tree().get_first_node_in_group("main")
	if not multiplayer.has_multiplayer_peer():
		# Offline / Singleplayer mode: directly pause/unpause scene tree
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
	# 1. Unpause locally and hide pause menu
	get_tree().paused = false
	panel_container.hide()
	hide()
	
	# 2. Trigger rematch / return to lobby on Main
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		if not multiplayer.has_multiplayer_peer():
			main_node.execute_rematch()
		elif multiplayer.is_server():
			main_node.rpc("execute_rematch")
		else:
			main_node.rpc_id(1, "request_rematch")

# ==============================================================================
# 4. VIDEO SETTINGS LOGIC
# ==============================================================================
func _cycle_window_mode():
	match current_window_mode:
		DisplayServer.WINDOW_MODE_WINDOWED:
			current_window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			current_window_mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			current_window_mode = DisplayServer.WINDOW_MODE_WINDOWED
		_:
			current_window_mode = DisplayServer.WINDOW_MODE_WINDOWED

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
	if window_mode_btn:
		window_mode_btn.text = "WINDOW MODE: " + _get_window_mode_name()
	if vsync_btn:
		vsync_btn.text = "V-SYNC: " + ("ENABLED" if is_vsync_enabled else "DISABLED")
	if fps_btn:
		fps_btn.text = "MAX FPS: " + _get_fps_name()

func _get_window_mode_name() -> String:
	match current_window_mode:
		DisplayServer.WINDOW_MODE_WINDOWED: return "WINDOWED"
		DisplayServer.WINDOW_MODE_FULLSCREEN: return "BORDERLESS"
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: return "FULLSCREEN"
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

	DisplayServer.window_set_mode(current_window_mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if is_vsync_enabled else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = current_max_fps

# ==============================================================================
# 5. HELPERS
# ==============================================================================
func _create_btn(text: String, callable: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 34)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(callable)
	return btn

func _create_slider_row(label_text: String, initial_val: float) -> Dictionary:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	var n_lbl = Label.new()
	n_lbl.text = label_text
	n_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n_lbl.add_theme_color_override("font_color", Color(0.90, 0.86, 0.74))
	hbox.add_child(n_lbl)

	var v_lbl = Label.new()
	v_lbl.text = str(int(initial_val * 100)) + "%"
	v_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	hbox.add_child(v_lbl)

	var slider = HSlider.new()
	slider.min_value = 0.0; slider.max_value = 1.0; slider.step = 0.05
	slider.value = initial_val
	slider.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(slider)

	return {"container": vbox, "slider": slider, "val_lbl": v_lbl}

func _refresh_audio_sliders():
	if master_slider: master_slider.value = AudioManager.master_volume
	if music_slider: music_slider.value = AudioManager.music_volume
	if sfx_slider: sfx_slider.value = AudioManager.sfx_volume
	if master_lbl: master_lbl.text = str(int(AudioManager.master_volume * 100)) + "%"
	if music_lbl: music_lbl.text = str(int(AudioManager.music_volume * 100)) + "%"
	if sfx_lbl: sfx_lbl.text = str(int(AudioManager.sfx_volume * 100)) + "%"
