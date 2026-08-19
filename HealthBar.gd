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
@export var color_healthy: Color = Color(0.15, 0.90, 0.45) # Emerald Green / Cyan Glow
@export var color_medium: Color = Color(0.95, 0.72, 0.15)  # Forge Amber
@export var color_critical: Color = Color(0.92, 0.18, 0.18)# Mars Red
@export var color_ghost: Color = Color(0.95, 0.92, 0.85, 0.75) # Trailing damage flash
@export var bg_color: Color = Color(0.06, 0.07, 0.10, 0.85)     # Deep dark iron
@export var border_color: Color = Color(0.35, 0.38, 0.42, 0.9)  # Steel frame

var current_hp: float = 100.0
var max_hp: float = 100.0

var target_ratio: float = 1.0
var primary_ratio: float = 1.0
var ghost_ratio: float = 1.0

var ghost_lag_timer: float = 0.0
var visibility_timer: float = 0.0
var current_alpha: float = 1.0

func _ready() -> void:
	z_index = 10 # Draw above floor and units
	if not Engine.is_editor_hint() and auto_hide_when_full and not always_visible:
		current_alpha = 0.0
		modulate.a = 0.0

func _process(delta: float) -> void:
	var parent_node = get_parent() as Node2D
	if parent_node:
		# Lock rotation to 0 so healthbar never spins when unit turns
		global_rotation = 0.0
		global_position = parent_node.global_position + bar_offset

	# 1. Smooth Primary Bar Lerp
	var need_redraw = false
	if abs(primary_ratio - target_ratio) > 0.001:
		primary_ratio = lerpf(primary_ratio, target_ratio, clampf(delta * 14.0, 0.0, 1.0))
		need_redraw = true
	else:
		primary_ratio = target_ratio

	# 2. Smooth Ghost Damage Lag Bar Lerp
	if ghost_lag_timer > 0.0:
		ghost_lag_timer -= delta
	else:
		if ghost_ratio > primary_ratio:
			ghost_ratio = lerpf(ghost_ratio, primary_ratio, clampf(delta * 5.0, 0.0, 1.0))
			need_redraw = true
		else:
			ghost_ratio = primary_ratio

	# 3. Smart Visibility / Auto-hide handling
	if not Engine.is_editor_hint() and not always_visible:
		if auto_hide_when_full:
			var target_alpha = 1.0
			if target_ratio >= 0.999 and visibility_timer <= 0.0:
				target_alpha = 0.0
			elif visibility_timer > 0.0:
				visibility_timer -= delta
				target_alpha = 1.0

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
	queue_redraw()

func update_health(current_val: int, max_val: int = -1) -> void:
	if max_val > 0:
		max_hp = float(max_val)
	current_hp = clampf(float(current_val), 0.0, max_hp)

	var new_ratio = current_hp / max_hp
	if new_ratio < target_ratio:
		# Taking damage: hold ghost bar for 0.28s before draining
		ghost_lag_timer = 0.28
		visibility_timer = 3.5 # Stay visible for 3.5 seconds after damage

	target_ratio = new_ratio
	queue_redraw()

func _draw() -> void:
	var half_w = bar_size.x * 0.5
	var half_h = bar_size.y * 0.5
	var bar_rect = Rect2(-half_w, -half_h, bar_size.x, bar_size.y)

	# 1. Dark Background Plate
	draw_rect(bar_rect, bg_color)

	# 2. Ghost Bar (Trailing Damage Flash)
	if ghost_ratio > 0.001:
		var ghost_w = bar_size.x * clampf(ghost_ratio, 0.0, 1.0)
		draw_rect(Rect2(-half_w, -half_h, ghost_w, bar_size.y), color_ghost)

	# 3. Dynamic Primary Health Fill
	if primary_ratio > 0.001:
		var fill_w = bar_size.x * clampf(primary_ratio, 0.0, 1.0)
		var fill_color = _get_fill_color(primary_ratio)
		draw_rect(Rect2(-half_w, -half_h, fill_w, bar_size.y), fill_color)

		# Top highlight line for a crisp 3D beveled sci-fi edge
		if bar_size.y >= 3.0:
			var highlight_color = Color(fill_color.r + 0.25, fill_color.g + 0.25, fill_color.b + 0.25, 0.6)
			draw_line(Vector2(-half_w, -half_h + 1), Vector2(-half_w + fill_w, -half_h + 1), highlight_color, 1.0)

	# 4. Metallic Steel Border Frame
	var border_rect = Rect2(-half_w - 1, -half_h - 1, bar_size.x + 2, bar_size.y + 2)
	draw_rect(border_rect, border_color, false, 1.0)

func _get_fill_color(ratio: float) -> Color:
	if ratio > 0.5:
		var t = (ratio - 0.5) / 0.5
		return color_medium.lerp(color_healthy, t)
	else:
		var t = ratio / 0.5
		return color_critical.lerp(color_medium, t)
