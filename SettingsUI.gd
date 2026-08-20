extends Control
class_name SettingsUI

var master_slider: HSlider = null
var music_slider: HSlider = null
var sfx_slider: HSlider = null

var master_lbl: Label = null
var music_lbl: Label = null
var sfx_lbl: Label = null

func _ready():
	add_to_group("settings_ui")
	theme = AdmechTheme.make()
	hide()
	_build_ui_layout()

func _build_ui_layout():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dark Tactical Backdrop
	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.75)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(520, 360)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(pc)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	pc.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "◆ AUDIO COGITATION PROTOCOLS ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# Sliders Container
	var sliders_box = VBoxContainer.new()
	sliders_box.add_theme_constant_override("separation", 12)
	vbox.add_child(sliders_box)

	# 1. Master Volume
	var m_row = _create_slider_row("Master Output", AudioManager.master_volume)
	master_slider = m_row.slider
	master_lbl = m_row.val_lbl
	master_slider.value_changed.connect(_on_master_changed)
	sliders_box.add_child(m_row.container)

	# 2. Music / Soundtrack Volume
	var mus_row = _create_slider_row("Machine Hymn (Music)", AudioManager.music_volume)
	music_slider = mus_row.slider
	music_lbl = mus_row.val_lbl
	music_slider.value_changed.connect(_on_music_changed)
	sliders_box.add_child(mus_row.container)

	# 3. SFX / Weapons Volume
	var sfx_row = _create_slider_row("Combat Audio (SFX)", AudioManager.sfx_volume)
	sfx_slider = sfx_row.slider
	sfx_lbl = sfx_row.val_lbl
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sliders_box.add_child(sfx_row.container)

	# Close Button
	var close_btn = Button.new()
	close_btn.text = "CONFIRM & CLOSE [ESC / O]"
	close_btn.custom_minimum_size = Vector2(220, 34)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(toggle_settings)
	vbox.add_child(close_btn)

func _create_slider_row(label_text: String, initial_val: float) -> Dictionary:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var hbox_header = HBoxContainer.new()
	vbox.add_child(hbox_header)

	var name_lbl = Label.new()
	name_lbl.text = label_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.86, 0.74))
	hbox_header.add_child(name_lbl)

	var val_lbl = Label.new()
	val_lbl.text = str(int(initial_val * 100)) + "%"
	val_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	hbox_header.add_child(val_lbl)

	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial_val
	slider.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(slider)

	return {"container": vbox, "slider": slider, "val_lbl": val_lbl}

func toggle_settings():
	if visible:
		hide()
	else:
		_refresh_slider_values()
		show()

func _refresh_slider_values():
	if master_slider: master_slider.value = AudioManager.master_volume
	if music_slider: music_slider.value = AudioManager.music_volume
	if sfx_slider: sfx_slider.value = AudioManager.sfx_volume
	if master_lbl: master_lbl.text = str(int(AudioManager.master_volume * 100)) + "%"
	if music_lbl: music_lbl.text = str(int(AudioManager.music_volume * 100)) + "%"
	if sfx_lbl: sfx_lbl.text = str(int(AudioManager.sfx_volume * 100)) + "%"

func _on_master_changed(val: float):
	AudioManager.set_master_volume(val)
	master_lbl.text = str(int(val * 100)) + "%"

func _on_music_changed(val: float):
	AudioManager.set_music_volume(val)
	music_lbl.text = str(int(val * 100)) + "%"

func _on_sfx_changed(val: float):
	AudioManager.set_sfx_volume(val)
	sfx_lbl.text = str(int(val * 100)) + "%"
	# Play a test beep when adjusting SFX
	AudioManager.play_sfx("scrap_pickup", Vector2.ZERO, -4.0)

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_O:
			toggle_settings()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			hide()
			get_viewport().set_input_as_handled()
