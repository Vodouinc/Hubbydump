@tool
extends Node2D

@export var custom_size_override: Vector2 = Vector2(-1.0, -1.0):
	set(val):
		custom_size_override = val
		_update_shadow_size()
		queue_redraw()

@export var ground_offset: Vector2 = Vector2(0.0, 3.0):
	set(val):
		ground_offset = val
		queue_redraw()

@export var shadow_color: Color = Color(0.02, 0.02, 0.05, 0.52):
	set(val):
		shadow_color = val
		queue_redraw()

@export var elevation: float = 0.0:
	set(val):
		elevation = val
		queue_redraw()

var calculated_size: Vector2 = Vector2(22.0, 12.0)
var sun_direction: Vector2 = Vector2(1.0, 0.28)
var shadow_length: float = 10.0
var daylight: float = 1.0

func _ready() -> void:
	show_behind_parent = true
	add_to_group("dynamic_shadows")
	_update_shadow_size()

func _process(_delta: float) -> void:
	if not is_inside_tree(): return
	var parent_node := get_parent() as Node2D
	if parent_node == null: return

	global_rotation = 0.0
	var planted := ground_offset if typeof(ground_offset) == TYPE_VECTOR2 else Vector2(0.0, 3.0)
	global_position = parent_node.global_position + planted

	if Engine.is_editor_hint():
		_update_shadow_size()

func set_elevation(height: float) -> void:
	elevation = height

func update_shadow_size() -> void:
	_update_shadow_size()
	queue_redraw()

func set_sun_state(direction: Vector2, length: float, new_daylight: float) -> void:
	if direction.length_squared() > 0.0001:
		sun_direction = direction.normalized()
	shadow_length = maxf(0.0, length)
	daylight = clampf(new_daylight, 0.0, 1.0)
	queue_redraw()

func _update_shadow_size() -> void:
	if typeof(custom_size_override) == TYPE_VECTOR2 and custom_size_override.x > 0.0 and custom_size_override.y > 0.0:
		calculated_size = custom_size_override
		return

	var parent = get_parent()
	if not parent: return

	# 1. Broader Player & Friendly Unit Dimensions
	if "unit_type" in parent:
		var type_val = int(parent.get("unit_type"))
		match type_val:
			0: calculated_size = Vector2(32.0, 18.0) # Tech-Priest (Heavy Robe)
			1: calculated_size = Vector2(26.0, 14.0) # Skitarii Marshal
			2: calculated_size = Vector2(22.0, 12.0) # Vanguard / Bodyguard
			3: calculated_size = Vector2(16.0, 9.0)  # Servo-Skull
			_: calculated_size = Vector2(22.0, 12.0)
		return

	var visual = parent.get_node_or_null("VisualSprite")
	if visual and "unit_type" in visual:
		var type_val = int(visual.get("unit_type"))
		match type_val:
			0: calculated_size = Vector2(32.0, 18.0)
			1: calculated_size = Vector2(26.0, 14.0)
			2: calculated_size = Vector2(22.0, 12.0)
			3: calculated_size = Vector2(16.0, 9.0)
		return

	# 2. Broader Enemy Dimensions
	if "type" in parent and parent.is_in_group("enemies"):
		var type_val = int(parent.get("type"))
		match type_val:
			0: calculated_size = Vector2(18.0, 10.0) # Gretchin
			1: calculated_size = Vector2(16.0, 9.0)  # Compact Squig
			2: calculated_size = Vector2(36.0, 20.0) # Ork Boy
			_: calculated_size = Vector2(24.0, 14.0)
		return

	# 3. Scrap Pickups
	if parent.is_in_group("scrap") or parent.name.begins_with("Scrap"):
		calculated_size = Vector2(14.0, 8.0)
		return

	# 4. Structures
	if parent.is_in_group("buildings") or parent.is_in_group("base"):
		if "building_type" in parent:
			var b_type = int(parent.get("building_type"))
			match b_type:
				0: calculated_size = Vector2(46.0, 24.0); ground_offset = Vector2(0.0, 6.0) # Barricade
				1: calculated_size = Vector2(62.0, 32.0); ground_offset = Vector2(0.0, 6.0) # Generator
				2: calculated_size = Vector2(52.0, 26.0); ground_offset = Vector2(0.0, 6.0) # Turret
				3: calculated_size = Vector2(80.0, 42.0); ground_offset = Vector2(0.0, 8.0) # Manufactorum
				4, 5: calculated_size = Vector2(18.0, 10.0); ground_offset = Vector2(0.0, 3.0) # Small Relay Pylon
				6: calculated_size = Vector2(72.0, 36.0); ground_offset = Vector2(0.0, 8.0) # Tech Shrine
				_: calculated_size = Vector2(46.0, 24.0)
		elif parent.name.begins_with("Base") or parent.is_in_group("base"):
			calculated_size = Vector2(120.0, 60.0)
			ground_offset = Vector2(0.0, 10.0)
		return

	calculated_size = Vector2(22.0, 12.0)

func _draw() -> void:
	if calculated_size.x <= 0.0 or calculated_size.y <= 0.0: return

	var elev := elevation
	var elev_scale := clampf(1.0 - elev * 0.015, 0.42, 1.0)
	var elev_alpha := clampf(1.0 - elev * 0.018, 0.32, 1.0)
	var radius := calculated_size.x * elev_scale * 0.5
	var squash := clampf((calculated_size.y / maxf(calculated_size.x, 1.0)) * 0.9, 0.45, 0.75)

	var dir := sun_direction.normalized() if sun_direction.length_squared() > 0.0001 else Vector2(1.0, 0.28).normalized()
	var day := clampf(daylight, 0.0, 1.0)
	var extra_len := maxf(0.0, shadow_length) * day + elev * 0.55 * day

	var base_alpha := shadow_color.a * elev_alpha
	var contact_alpha := base_alpha * lerpf(1.05, 0.72, day)
	var cast_alpha := base_alpha * 0.65 * day

	if extra_len > 3.0 and cast_alpha > 0.02:
		_draw_directional_cast(dir, radius, extra_len, squash, cast_alpha)

	_draw_contact_blob(radius, squash, contact_alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_contact_blob(radius: float, squash: float, alpha: float) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, squash))
	var c_outer := Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha * 0.35)
	var c_mid := Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha * 0.60)
	var c_core := Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha * 0.95)
	draw_circle(Vector2.ZERO, radius * 1.15, c_outer)
	draw_circle(Vector2.ZERO, radius * 0.80, c_mid)
	draw_circle(Vector2.ZERO, radius * 0.45, c_core)

func _draw_directional_cast(dir: Vector2, radius: float, extra_len: float, squash: float, alpha: float) -> void:
	var angle := dir.angle()
	draw_set_transform(Vector2.ZERO, angle, Vector2(1.0, squash))

	var tip_x := extra_len + radius * 0.4
	var root_w := radius * 1.35 # Thicker base connection
	var tip_w := radius * 0.75  # Substantially wider cast tip
	var c_soft := Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha * 0.40)
	var c_solid := Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha * 0.75)

	var outer := PackedVector2Array([
		Vector2(-radius * 0.2, -root_w * 1.1),
		Vector2(tip_x * 0.4, -root_w * 0.9),
		Vector2(tip_x, -tip_w * 1.2),
		Vector2(tip_x, tip_w * 1.2),
		Vector2(tip_x * 0.4, root_w * 0.9),
		Vector2(-radius * 0.2, root_w * 1.1),
	])
	draw_colored_polygon(outer, c_soft)

	var inner := PackedVector2Array([
		Vector2(0.0, -root_w * 0.75),
		Vector2(tip_x * 0.55, -root_w * 0.5),
		Vector2(tip_x * 0.92, -tip_w * 0.85),
		Vector2(tip_x * 0.92, tip_w * 0.85),
		Vector2(tip_x * 0.55, root_w * 0.5),
		Vector2(0.0, root_w * 0.75),
	])
	draw_colored_polygon(inner, c_solid)
	draw_circle(Vector2(tip_x, 0.0), tip_w * 1.1, c_soft)
	draw_circle(Vector2(tip_x * 0.92, 0.0), tip_w * 0.8, c_solid)
