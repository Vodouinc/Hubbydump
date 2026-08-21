@tool
extends Node2D

@export var bar_size: Vector2 = Vector2(32.0, 4.0):
	set(val):
		bar_size = val
		queue_redraw()

@export var bar_offset: Vector2 = Vector2(0.0, -22.0):
	set(val):
		bar_offset = val
		queue_redraw()

@export var auto_hide_when_full: bool = true
@export var always_visible: bool = false

# Palette Constants
@export var color_healthy: Color = Color(0.15, 0.90, 0.45)
@export var color_medium: Color = Color(0.95, 0.72, 0.15)
@export var color_critical: Color = Color(0.92, 0.18, 0.18)
@export var color_shield: Color = Color(0.20, 0.88, 1.0, 0.95)
@export var color_ghost: Color = Color(0.95, 0.92, 0.85, 0.75)
@export var bg_color: Color = Color(0.06, 0.07, 0.10, 0.85)
@export var border_color: Color = Color(0.35, 0.38, 0.42, 0.9)

var current_hp: float = 100.0
var max_hp: float = 100.0
var current_shield: float = 0.0
var max_shield: float = 0.0

var target_ratio: float = 1.0
var primary_ratio: float = 1.0
var ghost_ratio: float = 1.0
var shield_ratio: float = 0.0

var ghost_lag_timer: float = 0.0
var visibility_timer: float = 0.0
var current_alpha: float = 0.0

func _ready() -> void:
	z_index = 10
	if not Engine.is_editor_hint() and auto_hide_when_full and not always_visible:
		current_alpha = 0.0
		modulate.a = 0.0

func _process(delta: float) -> void:
	var parent_node = get_parent() as Node2D
	if parent_node:
		global_rotation = 0.0
		global_position = parent_node.global_position + bar_offset

	var need_redraw = false
	if abs(primary_ratio - target_ratio) > 0.001:
		primary_ratio = lerpf(primary_ratio, target_ratio, clampf(delta * 14.0, 0.0, 1.0))
		need_redraw = true
	else:
		primary_ratio = target_ratio

	if ghost_lag_timer > 0.0:
		ghost_lag_timer -= delta
	else:
		if ghost_ratio > primary_ratio:
			ghost_ratio = lerpf(ghost_ratio, primary_ratio, clampf(delta * 5.0, 0.0, 1.0))
			need_redraw = true
		else:
			ghost_ratio = primary_ratio

	# --- AUTO-HIDE SMOOTH FADE SYSTEM ---
	if not Engine.is_editor_hint() and not always_visible:
		if auto_hide_when_full:
			var is_hp_full = (target_ratio >= 0.999)
			# If max_shield is 0, consider shield full. If max_shield > 0, check shield_ratio >= 0.999
			var is_shield_full = (max_shield <= 0.0 or shield_ratio >= 0.999)

			var target_alpha = 0.0

			if visibility_timer > 0.0:
				visibility_timer -= delta
				target_alpha = 1.0
			elif not is_hp_full or not is_shield_full:
				target_alpha = 1.0
			else:
				target_alpha = 0.0

			if abs(current_alpha - target_alpha) > 0.01:
				current_alpha = lerpf(current_alpha, target_alpha, clampf(delta * 8.0, 0.0, 1.0))
				modulate.a = current_alpha
			else:
				current_alpha = target_alpha
				modulate.a = current_alpha
	else:
		modulate.a = 1.0

	if need_redraw or Engine.is_editor_hint():
		queue_redraw()

func setup(current_val: int, max_val: int) -> void:
	max_hp = maxf(1.0, float(max_val))
	current_hp = clampf(float(current_val), 0.0, max_hp)
	target_ratio = current_hp / max_hp
	primary_ratio = target_ratio
	ghost_ratio = target_ratio
	visibility_timer = 0.0
	
	if auto_hide_when_full and not always_visible and not Engine.is_editor_hint():
		current_alpha = 0.0
		modulate.a = 0.0
		
	queue_redraw()

func update_health(current_val: int, max_val: int = -1) -> void:
	if max_val > 0: max_hp = float(max_val)
	current_hp = clampf(float(current_val), 0.0, max_hp)
	var new_ratio = current_hp / max_hp
	
	# Only wake up visibility timer if damage was taken (health decreased)
	if new_ratio < target_ratio:
		ghost_lag_timer = 0.28
		visibility_timer = 4.0
		
	target_ratio = new_ratio
	queue_redraw()

func update_shield(current_val: int, max_val: int) -> void:
	max_shield = float(max_val)
	current_shield = float(current_val)
	shield_ratio = (current_shield / max_shield) if max_shield > 0.0 else 0.0
	
	if max_shield > 0.0 and shield_ratio < 0.999:
		visibility_timer = 4.0
		
	queue_redraw()

func _draw() -> void:
	var half_w = bar_size.x * 0.5
	var half_h = bar_size.y * 0.5
	var bar_rect = Rect2(-half_w, -half_h, bar_size.x, bar_size.y)

	# 1. Background Plate
	draw_rect(bar_rect, bg_color)

	# 2. Ghost Bar (White damage trail)
	if ghost_ratio > 0.001:
		draw_rect(Rect2(-half_w, -half_h, bar_size.x * clampf(ghost_ratio, 0.0, 1.0), bar_size.y), color_ghost)

	# 3. Dynamic Primary Health Fill
	if primary_ratio > 0.001:
		var fill_w = bar_size.x * clampf(primary_ratio, 0.0, 1.0)
		var fill_color = _get_fill_color(primary_ratio)
		draw_rect(Rect2(-half_w, -half_h, fill_w, bar_size.y), fill_color)

	# 4. Metallic Border
	draw_rect(Rect2(-half_w - 1, -half_h - 1, bar_size.x + 2, bar_size.y + 2), border_color, false, 1.0)

	# 5. Aegis Refractor Shield Bar (Stacked above health bar if shields exist)
	if max_shield > 0.0 and shield_ratio > 0.001:
		var shield_y = -half_h - 4.5
		var shield_w = bar_size.x * clampf(shield_ratio, 0.0, 1.0)
		draw_rect(Rect2(-half_w, shield_y, bar_size.x, 2.5), bg_color)
		draw_rect(Rect2(-half_w, shield_y, shield_w, 2.5), color_shield)
		draw_rect(Rect2(-half_w - 1, shield_y - 1, bar_size.x + 2, 4.5), border_color, false, 1.0)

func _get_fill_color(ratio: float) -> Color:
	if ratio > 0.5:
		return color_medium.lerp(color_healthy, (ratio - 0.5) / 0.5)
	return color_critical.lerp(color_medium, ratio / 0.5)
