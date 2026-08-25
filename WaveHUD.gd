# res://WaveHUD.gd
extends Control
class_name WaveHUD

# Compact Top Ribbon
var top_ribbon: PanelContainer
var wave_tag_lbl: Label
var wave_detail_lbl: Label
var wave_sub_pbar: ProgressBar

# Vertical WAAAGH! Bar & Clean Tooltip
var waaagh_gauge: WaaaghVerticalGauge
var waaagh_tooltip: PanelContainer
var waaagh_tooltip_title: Label
var waaagh_tooltip_stats: Label
var waaagh_tooltip_desc: Label

func _ready() -> void:
	add_to_group("wave_hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_update_layout_positions()

func _process(_delta: float) -> void:
	_update_layout_positions()

func _update_layout_positions() -> void:
	var vp_size = get_viewport_rect().size

	# 1. SLEEK TOP RIBBON (Width: 360, Height: 28) -> Perfectly Centered at Top
	if is_instance_valid(top_ribbon):
		var w = 360.0
		var h = 28.0
		top_ribbon.position = Vector2((vp_size.x - w) * 0.5, 8.0)
		top_ribbon.size = Vector2(w, h)
		top_ribbon.custom_minimum_size = Vector2(w, h)

	# 2. VERTICAL WAAAGH! GAUGE -> Snug beside Minimap (24px margin + 210px minimap + 8px gap)
	if is_instance_valid(waaagh_gauge):
		var bar_w = 16.0
		var bar_h = 210.0
		var gauge_x = vp_size.x - 24.0 - 210.0 - 8.0 - bar_w
		var gauge_y = vp_size.y - 24.0 - bar_h

		waaagh_gauge.position = Vector2(gauge_x, gauge_y)
		waaagh_gauge.size = Vector2(bar_w, bar_h)
		waaagh_gauge.custom_minimum_size = Vector2(bar_w, bar_h)

		# Position Tooltip cleanly 8px to the left of the vertical bar
		if is_instance_valid(waaagh_tooltip) and waaagh_tooltip.visible:
			var tip_w = 210.0
			waaagh_tooltip.position = Vector2(gauge_x - tip_w - 8.0, gauge_y + 30.0)

func _build_ui() -> void:
	for c in get_children(): c.queue_free()

	# =========================================================================
	# 1. MINIMALIST TOP-CENTER TACTICAL RIBBON (28px height)
	# =========================================================================
	top_ribbon = PanelContainer.new()
	top_ribbon.name = "TopWaveRibbon"
	top_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.92)
	sb.border_color = Color(0.24, 0.28, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	top_ribbon.add_theme_stylebox_override("panel", sb)
	add_child(top_ribbon)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 2)
	top_ribbon.add_child(root_vbox)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	root_vbox.add_child(hbox)

	wave_tag_lbl = Label.new()
	wave_tag_lbl.text = "⚔️ WAVE 01/15"
	wave_tag_lbl.add_theme_font_size_override("font_size", 9)
	wave_tag_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	hbox.add_child(wave_tag_lbl)

	var sep_line = ColorRect.new()
	sep_line.custom_minimum_size = Vector2(1, 12)
	sep_line.color = Color(0.3, 0.35, 0.42, 0.5)
	hbox.add_child(sep_line)

	wave_detail_lbl = Label.new()
	wave_detail_lbl.text = "14 HOSTILES"
	wave_detail_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave_detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_detail_lbl.add_theme_font_size_override("font_size", 9)
	wave_detail_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	hbox.add_child(wave_detail_lbl)

	# Ultra-Slim 3px Progress Underline
	wave_sub_pbar = ProgressBar.new()
	wave_sub_pbar.custom_minimum_size = Vector2(0, 3)
	wave_sub_pbar.show_percentage = false
	var sb_pfill = StyleBoxFlat.new()
	sb_pfill.bg_color = Color(0.92, 0.22, 0.18)
	sb_pfill.set_corner_radius_all(1)
	wave_sub_pbar.add_theme_stylebox_override("fill", sb_pfill)
	root_vbox.add_child(wave_sub_pbar)

	# =========================================================================
	# 2. VERTICAL WAAAGH! GAUGE
	# =========================================================================
	waaagh_gauge = WaaaghVerticalGauge.new()
	waaagh_gauge.name = "WaaaghVerticalGauge"
	waaagh_gauge.mouse_filter = Control.MOUSE_FILTER_STOP
	waaagh_gauge.mouse_entered.connect(_on_waaagh_hovered)
	waaagh_gauge.mouse_exited.connect(_on_waaagh_unhovered)
	add_child(waaagh_gauge)
	waaagh_gauge.hide()

	# =========================================================================
	# 3. COMPACT WAAAGH! TOOLTIP (Fixed Width & Sizing)
	# =========================================================================
	waaagh_tooltip = PanelContainer.new()
	waaagh_tooltip.name = "WaaaghTooltipCard"
	waaagh_tooltip.custom_minimum_size = Vector2(210, 0)
	waaagh_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb_tip = StyleBoxFlat.new()
	sb_tip.bg_color = Color(0.04, 0.05, 0.08, 0.96)
	sb_tip.border_color = Color(0.35, 0.95, 0.25)
	sb_tip.set_border_width_all(1)
	sb_tip.set_corner_radius_all(3)
	sb_tip.content_margin_left = 8
	sb_tip.content_margin_right = 8
	sb_tip.content_margin_top = 6
	sb_tip.content_margin_bottom = 6
	sb_tip.shadow_color = Color(0, 0, 0, 0.7)
	sb_tip.shadow_size = 4
	waaagh_tooltip.add_theme_stylebox_override("panel", sb_tip)
	add_child(waaagh_tooltip)

	var t_vbox = VBoxContainer.new()
	t_vbox.add_theme_constant_override("separation", 2)
	waaagh_tooltip.add_child(t_vbox)

	waaagh_tooltip_title = Label.new()
	waaagh_tooltip_title.text = "🔥 WAAAGH! PSYCHIC FIELD"
	waaagh_tooltip_title.add_theme_font_size_override("font_size", 10)
	waaagh_tooltip_title.add_theme_color_override("font_color", Color(0.35, 0.95, 0.25))
	t_vbox.add_child(waaagh_tooltip_title)

	waaagh_tooltip_stats = Label.new()
	waaagh_tooltip_stats.text = "INTENSITY: 0%\n• Move Speed: +0%\n• Damage: +0%"
	waaagh_tooltip_stats.add_theme_font_size_override("font_size", 8)
	waaagh_tooltip_stats.add_theme_color_override("font_color", Color(0.92, 0.88, 0.75))
	t_vbox.add_child(waaagh_tooltip_stats)

	var t_sep = ColorRect.new()
	t_sep.custom_minimum_size = Vector2(0, 1)
	t_sep.color = Color(0.25, 0.35, 0.28, 0.5)
	t_vbox.add_child(t_sep)

	waaagh_tooltip_desc = Label.new()
	waaagh_tooltip_desc.text = "Greenskins draw strength from active Totems.\nDestroy Idols in the field to suppress frenzy."
	waaagh_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	waaagh_tooltip_desc.add_theme_font_size_override("font_size", 7)
	waaagh_tooltip_desc.add_theme_color_override("font_color", Color(0.65, 0.72, 0.65))
	t_vbox.add_child(waaagh_tooltip_desc)

	waaagh_tooltip.hide()

func _on_waaagh_hovered() -> void:
	if is_instance_valid(waaagh_gauge) and waaagh_gauge.visible:
		waaagh_tooltip.show()
		_update_layout_positions()

func _on_waaagh_unhovered() -> void:
	if is_instance_valid(waaagh_tooltip):
		waaagh_tooltip.hide()

func update_telemetry(wave: int, max_w: int, title: String, preparing: bool, prep_left: float, on_break: bool, break_left: float, contacts_active: int, contacts_total: int) -> void:
	if not is_instance_valid(wave_tag_lbl): return

	wave_tag_lbl.text = "⚔️ WAVE %02d/%02d" % [wave, max_w]

	if preparing:
		wave_sub_pbar.max_value = 8.0
		wave_sub_pbar.value = prep_left
		wave_detail_lbl.text = "⚠️ INVASION IN: %.1fs" % maxf(0.0, prep_left)
		wave_detail_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	elif on_break:
		wave_sub_pbar.max_value = 20.0
		wave_sub_pbar.value = break_left
		wave_detail_lbl.text = "⏳ BREAK: %.1fs" % maxf(0.0, break_left)
		wave_detail_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
	else:
		wave_sub_pbar.max_value = max(1, contacts_total)
		wave_sub_pbar.value = clampi(contacts_active, 0, max(1, contacts_total))
		wave_detail_lbl.text = "%d HOSTILES LEFT" % contacts_active
		wave_detail_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))

	_refresh_waaagh_display()

func _refresh_waaagh_display() -> void:
	if not is_instance_valid(waaagh_gauge): return

	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return

	var is_unlocked = main_node.get("tech_waaagh_reader_unlocked") if "tech_waaagh_reader_unlocked" in main_node else false
	if not is_unlocked:
		waaagh_gauge.hide()
		waaagh_tooltip.hide()
		return

	waaagh_gauge.show()
	var totems = main_node.get_active_totem_count() if main_node.has_method("get_active_totem_count") else 0
	var speed_buff = int(totems * 10)
	var dmg_buff = int(totems * 12)
	var intensity = main_node.get_waaagh_intensity_pct() if main_node.has_method("get_waaagh_intensity_pct") else 0.0

	waaagh_gauge.target_intensity = intensity
	waaagh_gauge.totem_count = totems

	if is_instance_valid(waaagh_tooltip_stats):
		waaagh_tooltip_stats.text = "INTENSITY: %d%%\n• Active Totems: %d in field\n• Move Speed Buff: +%d%%\n• Damage Multiplier: +%d%%" % [
			int(intensity * 100.0), totems, speed_buff, dmg_buff
		]

# ==============================================================================
# VERTICAL GAUGE COMPONENT (Snug, Animated, Discrete Breakpoints)
# ==============================================================================
class WaaaghVerticalGauge extends Control:
	var target_intensity: float = 0.0
	var current_intensity: float = 0.0
	var totem_count: int = 0

	func _process(delta: float) -> void:
		current_intensity = lerpf(current_intensity, target_intensity, clampf(delta * 4.0, 0.0, 1.0))
		queue_redraw()

	func _draw() -> void:
		var bar_w = size.x
		var bar_h = size.y
		var pulse = 0.75 + sin(Time.get_ticks_msec() * 0.008) * 0.25

		# 1. Dark Carbon Base Plate
		draw_rect(Rect2(0, 0, bar_w, bar_h), Color(0.05, 0.06, 0.08, 0.95))

		# 2. Bottom-Up Emerald Energy Fill
		var fill_h = bar_h * clampf(current_intensity, 0.0, 1.0)
		if fill_h > 1.0:
			var fill_rect = Rect2(0, bar_h - fill_h, bar_w, fill_h)
			draw_rect(fill_rect, Color(0.18, 0.85, 0.28, 0.85))
			draw_rect(Rect2(2, bar_h - fill_h, bar_w - 4, fill_h), Color(0.35, 0.95, 0.45, 0.9))
			draw_line(Vector2(0, bar_h - fill_h), Vector2(bar_w, bar_h - fill_h), Color.WHITE, 1.5)

		# 3. Discreet Breakpoint Notches (25%, 50%, 75% thresholds)
		for i in range(1, 4):
			var notch_y = bar_h * (1.0 - (float(i) * 0.25))
			draw_line(Vector2(1, notch_y), Vector2(bar_w - 1, notch_y), Color(0.04, 0.06, 0.07, 0.75), 1.0)
			draw_line(Vector2(-2, notch_y), Vector2(0, notch_y), Color(0.82, 0.62, 0.24), 1.2)
			draw_line(Vector2(bar_w, notch_y), Vector2(bar_w + 2, notch_y), Color(0.82, 0.62, 0.24), 1.2)

		# 4. Metallic Frame
		draw_rect(Rect2(0, 0, bar_w, bar_h), Color(0.24, 0.28, 0.35), false, 1.2)

		# 5. Small Glowing Glyph Icon at Top
		var icon_center = Vector2(bar_w * 0.5, -10.0)
		draw_circle(icon_center, 5.5, Color(0.04, 0.05, 0.08))
		draw_circle(icon_center, 5.5, Color(0.35, 0.95, 0.25, 0.35 * pulse))
		draw_arc(icon_center, 5.5, 0, TAU, 14, Color(0.35, 0.95, 0.25), 1.0)
		draw_line(icon_center - Vector2(2, 2), icon_center + Vector2(2, 2), Color.WHITE, 1.0)
		draw_line(icon_center - Vector2(-2, 2), icon_center + Vector2(-2, -2), Color.WHITE, 1.0)
