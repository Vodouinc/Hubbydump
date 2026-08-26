# res://EventBannerHUD.gd
extends Control
class_name EventBannerHUD

enum BannerType {
	ADMECH_TECH = 0,       # Cyan
	SORORITAS_HOLY = 1,    # Ecclesiarch Gold / Crimson
	NECRON_ARCHEOTECH = 2, # Gauss Emerald Green
	TACTICAL_ALERT = 3,    # Orange / Red Klaxon
	QUEST_COMPLETE = 4     # Vivid Green
}

var banner_panel: PanelContainer = null
var faction_lbl: Label = null
var message_lbl: Label = null
var border_style: StyleBoxFlat = null

var message_queue: Array[Dictionary] = []
var is_displaying: bool = false
var display_timer: float = 0.0
const BANNER_DURATION: float = 4.2
const BANNER_WIDTH: float = 480.0
const TARGET_Y: float = 52.0 # Sits cleanly under the Wave HUD

func _ready() -> void:
	add_to_group("event_banner")
	z_index = 110
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_banner_ui()
	
	banner_panel.modulate.a = 0.0
	banner_panel.position.y = -60.0
	_update_banner_x_position()

func _build_banner_ui() -> void:
	banner_panel = PanelContainer.new()
	banner_panel.name = "BannerPanel"
	banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.custom_minimum_size = Vector2(BANNER_WIDTH, 48)

	# Dark High-Contrast Glassmorphic StyleBox
	border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0.03, 0.04, 0.06, 0.95)
	border_style.border_color = Color(0.20, 0.88, 1.0)
	border_style.set_border_width_all(1)
	border_style.set_corner_radius_all(3)
	border_style.content_margin_left = 14
	border_style.content_margin_right = 14
	border_style.content_margin_top = 5
	border_style.content_margin_bottom = 5
	border_style.shadow_color = Color(0.0, 0.0, 0.0, 0.75)
	border_style.shadow_size = 6
	banner_panel.add_theme_stylebox_override("panel", border_style)
	add_child(banner_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	banner_panel.add_child(vbox)

	faction_lbl = Label.new()
	faction_lbl.text = "◆ TRANSMISSION INCOMING ◆"
	faction_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	faction_lbl.add_theme_font_size_override("font_size", 9)
	faction_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	vbox.add_child(faction_lbl)

	message_lbl = Label.new()
	message_lbl.text = ""
	message_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_lbl.add_theme_font_size_override("font_size", 10)
	message_lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	vbox.add_child(message_lbl)

func _update_banner_x_position() -> void:
	var vp_size = get_viewport_rect().size
	if is_instance_valid(banner_panel):
		banner_panel.size.x = BANNER_WIDTH
		banner_panel.position.x = (vp_size.x - BANNER_WIDTH) * 0.5

func post_banner(header_text: String, body_text: String, banner_type: int = 0) -> void:
	message_queue.append({
		"header": header_text,
		"body": body_text,
		"type": banner_type
	})

func _process(delta: float) -> void:
	_update_banner_x_position()

	if is_displaying:
		display_timer -= delta
		if display_timer <= 0.0:
			_hide_banner()
	elif not message_queue.is_empty():
		var next_msg = message_queue.pop_front()
		_show_banner(next_msg)

func _show_banner(msg_data: Dictionary) -> void:
	is_displaying = true
	display_timer = BANNER_DURATION
	_update_banner_x_position()

	faction_lbl.text = msg_data.get("header", "TRANSMISSION")
	message_lbl.text = msg_data.get("body", "")

	var b_type = int(msg_data.get("type", 0))
	var theme_col = Color(0.20, 0.88, 1.0) # Default Admech Cyan

	match b_type:
		BannerType.ADMECH_TECH:
			theme_col = Color(0.20, 0.88, 1.0)
		BannerType.SORORITAS_HOLY:
			theme_col = Color(1.0, 0.85, 0.35)
		BannerType.NECRON_ARCHEOTECH:
			theme_col = Color(0.25, 1.0, 0.45)
		BannerType.TACTICAL_ALERT:
			theme_col = Color(1.0, 0.35, 0.20)
		BannerType.QUEST_COMPLETE:
			theme_col = Color(0.35, 0.95, 0.45)

	border_style.border_color = theme_col
	faction_lbl.add_theme_color_override("font_color", theme_col)

	# Clean Slide-Down & Fade-In Tween
	var tween = create_tween().set_parallel(true)
	tween.tween_property(banner_panel, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(banner_panel, "position:y", TARGET_Y, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_banner() -> void:
	var tween = create_tween().set_parallel(true)
	tween.tween_property(banner_panel, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(banner_panel, "position:y", TARGET_Y - 20.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(func():
		is_displaying = false
		banner_panel.position.y = -60.0
	)
