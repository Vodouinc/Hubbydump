@tool
extends Control
class_name WaveHUD

var current_wave: int = 1
var max_waves: int = 15
var wave_title: String = "LOST RECON SCOUTS"

var is_preparing: bool = false
var prep_time_left: float = 0.0
var max_prep_time: float = 8.0

var is_break: bool = false
var break_time_left: float = 0.0
var max_break_time: float = 14.0

var active_contacts: int = 0
var total_wave_contacts: int = 0
var anim_time: float = 0.0

func _ready() -> void:
	add_to_group("wave_hud")
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	anim_time += delta
	if is_preparing and prep_time_left > 0.0:
		prep_time_left = maxf(0.0, prep_time_left - delta)
	if is_break and break_time_left > 0.0:
		break_time_left = maxf(0.0, break_time_left - delta)
	queue_redraw()

func update_telemetry(wave: int, max_w: int, title_txt: String, preparing: bool, prep_left: float, on_break: bool, break_left: float, contacts_active: int, contacts_total: int):
	current_wave = wave
	max_waves = max_w
	wave_title = title_txt
	is_preparing = preparing
	prep_time_left = prep_left
	is_break = on_break
	break_time_left = break_left
	active_contacts = contacts_active
	total_wave_contacts = max(contacts_total, contacts_active)
	queue_redraw()

func _draw() -> void:
	var screen_w = get_viewport_rect().size.x
	var font = ThemeDB.fallback_font

	var panel_w = 460.0
	var panel_h = 44.0
	var panel_rect = Rect2((screen_w - panel_w) * 0.5, 10, panel_w, panel_h)

	var bg_dark = Color(0.04, 0.05, 0.07, 0.94)
	var brass = Color(0.78, 0.58, 0.22)
	var border_color = Color(0.20, 0.88, 1.0, 0.85) if not is_preparing else Color(1.0, 0.25, 0.20, 0.95)

	# 1. Console Housing
	draw_rect(panel_rect, bg_dark, true)
	draw_rect(panel_rect, border_color, false, 1.2)
	
	# Corner Brackets
	var c_len = 5.0
	draw_line(panel_rect.position, panel_rect.position + Vector2(c_len, 0), brass, 1.5)
	draw_line(panel_rect.position, panel_rect.position + Vector2(0, c_len), brass, 1.5)
	var tr = panel_rect.position + Vector2(panel_w, 0)
	draw_line(tr, tr - Vector2(c_len, 0), brass, 1.5)
	draw_line(tr, tr + Vector2(0, c_len), brass, 1.5)

	# 2. Status Content
	if is_preparing:
		_draw_prep_status(panel_rect, font)
	elif is_break:
		_draw_break_status(panel_rect, font)
	else:
		_draw_active_wave_status(panel_rect, font)

func _draw_prep_status(rect: Rect2, font: Font) -> void:
	var pulse = 0.65 + sin(anim_time * 8.0) * 0.35
	var warn_amber = Color(1.0, 0.75, 0.20)
	var sec = ceil(prep_time_left)
	draw_string(font, rect.position + Vector2(0, 16), "⚠️ AUSPEX INTERCEPT: INCOMING ASSAULT IN %02ds" % int(sec), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 11, warn_amber)

	var progress = clampf(prep_time_left / max_prep_time, 0.0, 1.0)
	var bar_rect = Rect2(rect.position.x + 16, rect.position.y + 24, rect.size.x - 32, 6)
	draw_rect(bar_rect, Color(0.12, 0.08, 0.08))
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * (1.0 - progress), bar_rect.size.y)), Color(1.0, 0.20, 0.15, pulse))

func _draw_break_status(rect: Rect2, font: Font) -> void:
	var sec = ceil(break_time_left)
	draw_string(font, rect.position + Vector2(0, 16), "◆ PERIMETER SECURED ◆ RE-ARM & FORTIFY [%02ds]" % int(sec), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 11, Color(0.35, 0.95, 0.45))

	var progress = clampf(break_time_left / max_break_time, 0.0, 1.0)
	var bar_rect = Rect2(rect.position.x + 16, rect.position.y + 24, rect.size.x - 32, 6)
	draw_rect(bar_rect, Color(0.08, 0.12, 0.16))
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * progress, bar_rect.size.y)), Color(0.20, 0.88, 1.0))

func _draw_active_wave_status(rect: Rect2, font: Font) -> void:
	draw_string(font, rect.position + Vector2(0, 15), "◆ WAVE %02d / %02d : %s ◆" % [current_wave, max_waves, wave_title], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 10, Color(0.92, 0.88, 0.78))

	var bar_rect = Rect2(rect.position.x + 16, rect.position.y + 22, rect.size.x - 32, 7)
	var ratio = clampf(float(active_contacts) / float(max(1, total_wave_contacts)), 0.0, 1.0)
	draw_rect(bar_rect, Color(0.08, 0.09, 0.11))
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * ratio, bar_rect.size.y)), Color(0.90, 0.25, 0.20))
	draw_rect(bar_rect, Color(0.35, 0.38, 0.42), false, 1.0)

	draw_string(font, bar_rect.position + Vector2(0, 6), "%d HOSTILES REMAINING" % active_contacts, HORIZONTAL_ALIGNMENT_CENTER, bar_rect.size.x, 8, Color(1.0, 0.95, 0.85))
