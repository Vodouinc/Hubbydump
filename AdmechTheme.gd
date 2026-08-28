class_name AdmechTheme
extends RefCounted

const BRASS := Color(0.78, 0.58, 0.22)
const BRASS_DIM := Color(0.42, 0.32, 0.14)
const STEEL := Color(0.10, 0.12, 0.16, 0.94)
const STEEL_HOVER := Color(0.16, 0.20, 0.26, 0.96)
const CYAN := Color(0.35, 0.90, 1.0)
const PARCHMENT := Color(0.90, 0.86, 0.74)
const MUTED := Color(0.62, 0.66, 0.70)

static func make() -> Theme:
	var theme := Theme.new()
	theme.set_default_font_size(12)

	var btn_normal := _box(STEEL, BRASS_DIM, 1, 3)
	var btn_hover := _box(STEEL_HOVER, BRASS, 1, 3)
	var btn_pressed := _box(Color(0.08, 0.22, 0.28, 0.96), CYAN, 1, 3)
	var btn_disabled := _box(Color(0.08, 0.09, 0.11, 0.8), Color(0.25, 0.25, 0.28), 1, 3)
	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("focus", "Button", btn_hover)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color", "Button", PARCHMENT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", CYAN)
	theme.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.5))

	var panel := _box(Color(0.05, 0.06, 0.09, 0.92), BRASS, 1, 4)
	panel.content_margin_left = 14
	panel.content_margin_top = 10
	panel.content_margin_right = 14
	panel.content_margin_bottom = 10
	theme.set_stylebox("panel", "PanelContainer", panel)

	var sb_focus = StyleBoxFlat.new()
	sb_focus.bg_color = Color(0.08, 0.16, 0.24, 0.95)
	sb_focus.border_color = Color(0.20, 0.88, 1.00) # Glowing Cyan Focus Border
	sb_focus.set_border_width_all(2)
	sb_focus.set_corner_radius_all(3)
	theme.set_stylebox("focus", "Button", sb_focus)

	# Ability HUD Slot Panel Styling with generous padding
	var slot := _box(Color(0.07, 0.08, 0.11, 0.90), BRASS_DIM, 1, 3)
	slot.content_margin_left = 10
	slot.content_margin_top = 8
	slot.content_margin_right = 10
	slot.content_margin_bottom = 8
	theme.set_stylebox("panel", "Panel", slot)

	theme.set_color("font_color", "Label", PARCHMENT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	theme.set_constant("separation", "VBoxContainer", 4)
	theme.set_constant("separation", "HBoxContainer", 12)
	return theme

static func _box(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	return box
