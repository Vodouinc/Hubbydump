# res://OrkCitadel.gd
@tool
extends StaticBody2D

@export var max_health: int = 2500
var current_health: int = 2500

var is_shield_active: bool = true
var outposts_remaining: int = 3
var pulse_time: float = 0.0

# 4 Bastion Guns with Target Leading & Predictive Fire
var turret_fire_timer: float = 0.0
const TURRET_RANGE: float = 480.0
var turret_aim_angle: float = 0.0

@onready var health_bar: Node2D = get_node_or_null("HealthBar")

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("objectives")
	add_to_group("ork_citadel")
	add_to_group("navmesh_source")
	
	max_health = GameData.ORK_CITADEL_MAX_HEALTH
	current_health = max_health
	is_shield_active = true
	outposts_remaining = 3
	
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)
	
	var col = get_node_or_null("CollisionShape2D")
	if not col:
		col = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(110, 110)
		col.shape = rect
		add_child(col)
		
	queue_redraw()

func _process(delta: float) -> void:
	pulse_time += delta

	# Automated Citadel Defense Artillery with Predictive Aiming
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		turret_fire_timer -= delta
		if turret_fire_timer <= 0.0:
			_process_citadel_defenses()

	queue_redraw()

func _process_citadel_defenses() -> void:
	var target = _find_closest_citadel_intruder()
	if is_instance_valid(target):
		var target_vel = target.velocity if "velocity" in target else Vector2.ZERO
		var dist = global_position.distance_to(target.global_position)
		
		# PREDICTIVE TARGET LEADING (Calculates where the player will be when bullet arrives)
		var bullet_speed = 680.0
		var lead_time = clampf(dist / bullet_speed, 0.0, 0.45)
		var predicted_target_pos = target.global_position + (target_vel * lead_time)

		turret_aim_angle = (predicted_target_pos - global_position).angle()
		turret_fire_timer = 0.85 # Rapid, punishing fire rate
		
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node and "spawner" in main_node and main_node.spawner:
			var dir = (predicted_target_pos - global_position).normalized()
			
			# High-velocity kinetic shots from all 4 fortress bastions
			for tower_corner in [Vector2(-44, -44), Vector2(44, -44), Vector2(-44, 44), Vector2(44, 44)]:
				var spawn_pos = global_position + tower_corner + (dir * 18.0)
				main_node.spawner.spawn({
					"type": "bullet",
					"name": "MekDakka_" + str(randi()),
					"position": spawn_pos,
					"direction": dir.rotated(randf_range(-0.03, 0.03)), # Tight, accurate grouping
					"damage": 18,
					"bullet_type": 5, # ORK_SLUG
					"is_enemy_bullet": true
				})
			
			AudioManager.play_sfx("radium_shot", global_position, 1.5, 0.75)

func _find_closest_citadel_intruder() -> Node2D:
	var candidates = get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("bodyguards")
	var closest: Node2D = null
	var min_d = TURRET_RANGE
	for c in candidates:
		if is_instance_valid(c) and not bool(c.get("is_dead")):
			var d = global_position.distance_to(c.global_position)
			if d < min_d:
				min_d = d
				closest = c
	return closest

func update_shield_state(remaining_satellites: int) -> void:
	outposts_remaining = remaining_satellites
	is_shield_active = (remaining_satellites > 0)
	rpc("sync_shield_state", is_shield_active, outposts_remaining)

@rpc("call_local", "reliable")
func sync_shield_state(shielded: bool, remaining: int) -> void:
	is_shield_active = shielded
	outposts_remaining = remaining
	queue_redraw()

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if is_shield_active:
		rpc("trigger_shield_deflect_fx")
		return

	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		var new_hp = max(0, current_health - amount)
		rpc("sync_citadel_health", new_hp)

@rpc("call_local", "unreliable")
func trigger_shield_deflect_fx() -> void:
	AudioManager.play_sfx("hit", global_position, 0.0, 1.8)
	var label = Label.new()
	label.script = load("res://DamageNumber.gd")
	label.global_position = global_position + Vector2(randf_range(-60, 20), -70)
	get_parent().add_child(label)
	label.text = "🛡️ SHIELDED (%d/3 OUTPOSTS REMAIN)" % outposts_remaining
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.35, 0.95, 0.25)
	label.label_settings.font_size = 12

@rpc("call_local", "reliable")
func sync_citadel_health(new_hp: int) -> void:
	current_health = new_hp
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
		
	if current_health <= 0 and (multiplayer.is_server() or not multiplayer.has_multiplayer_peer()):
		_destroy_citadel()

func _destroy_citadel() -> void:
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		if main_node.has_method("add_scrap"): main_node.add_scrap(250)
		if main_node.has_method("add_requisition"): main_node.add_requisition(150)
		if main_node.has_method("notify_citadel_destroyed"):
			main_node.notify_citadel_destroyed()
		elif main_node.has_method("game_over"):
			main_node.game_over(true)

	AudioManager.play_sfx("orbital_strike", global_position, 4.0, 0.5)
	queue_free()

func _draw() -> void:
	var scrap_dark = Color(0.14, 0.12, 0.10)
	var rusted_plate = Color(0.38, 0.22, 0.14)
	var blood_red = Color(0.65, 0.10, 0.08)
	var bone_ivory = Color(0.88, 0.84, 0.72)
	var iron_trim = Color(0.60, 0.65, 0.70)
	var waaagh_green = Color(0.35, 0.95, 0.15)
	var pulse = 0.6 + sin(pulse_time * 3.5) * 0.35

	# 1. Base Plinth
	var base_rect = Rect2(-56, -56, 112, 112)
	draw_rect(base_rect, scrap_dark)
	draw_rect(base_rect, rusted_plate, false, 4.0)

	# 2. Four Spiked Bastion Towers with Rotating Dakka Guns
	var turret_dir = Vector2.RIGHT.rotated(turret_aim_angle)
	for c in [Vector2(-44, -44), Vector2(44, -44), Vector2(-44, 44), Vector2(44, 44)]:
		draw_rect(Rect2(c - Vector2(14, 14), Vector2(28, 28)), Color(0.18, 0.15, 0.12))
		draw_rect(Rect2(c - Vector2(14, 14), Vector2(28, 28)), blood_red, false, 2.5)
		draw_line(c, c + c.normalized() * 18.0, bone_ivory, 3.5)
		
		# Rotating Twin-Linked Mek Guns
		draw_circle(c, 6.0, Color(0.1, 0.12, 0.14))
		draw_line(c - turret_dir.orthogonal() * 2.8, c + (turret_dir * 18.0) - turret_dir.orthogonal() * 2.8, iron_trim, 3.0)
		draw_line(c + turret_dir.orthogonal() * 2.8, c + (turret_dir * 18.0) + turret_dir.orthogonal() * 2.8, iron_trim, 3.0)
		draw_circle(c + (turret_dir * 18.0), 2.2, Color(1.0, 0.6, 0.2))

	# 3. Fortress Courtyard & Main Hall
	draw_rect(Rect2(-36, -36, 72, 72), rusted_plate)
	draw_rect(Rect2(-32, -32, 64, 64), blood_red)
	draw_rect(Rect2(-32, -32, 64, 64), iron_trim, false, 2.0)

	# 4. Giant Horned WAAAGH! Warboss Totem Skull in Center
	var skull_poly = PackedVector2Array([
		Vector2(-20, -22), Vector2(0, -32), Vector2(20, -22),
		Vector2(24, 12), Vector2(12, 26), Vector2(-12, 26), Vector2(-24, 12)
	])
	draw_colored_polygon(skull_poly, Color(0.10, 0.10, 0.12))
	draw_polyline(skull_poly, bone_ivory, 3.0)

	draw_circle(Vector2(-8, -4), 4.5, Color(waaagh_green.r, waaagh_green.g, waaagh_green.b, 0.4 * pulse))
	draw_circle(Vector2(8, -4), 4.5, Color(waaagh_green.r, waaagh_green.g, waaagh_green.b, 0.4 * pulse))
	draw_circle(Vector2(-8, -4), 2.5, waaagh_green)
	draw_circle(Vector2(8, -4), 2.5, waaagh_green)
	draw_circle(Vector2(-8, -4), 1.0, Color.WHITE)
	draw_circle(Vector2(8, -4), 1.0, Color.WHITE)

	draw_line(Vector2(-12, 14), Vector2(-18, -4), bone_ivory, 4.5)
	draw_line(Vector2(12, 14), Vector2(18, -4), bone_ivory, 4.5)

	# 5. Kustom Force Field Bubble Dome
	if is_shield_active:
		var shield_r = 78.0 + sin(pulse_time * 4.0) * 4.0
		var shield_col = Color(0.35, 0.95, 0.25, 0.22 * pulse)
		var rim_col = Color(0.35, 0.95, 0.25, 0.85 * pulse)

		draw_circle(Vector2.ZERO, shield_r, shield_col)
		draw_arc(Vector2.ZERO, shield_r, 0, TAU, 32, rim_col, 2.5)

		var a1 = pulse_time * 2.5
		draw_arc(Vector2.ZERO, shield_r + 6.0, a1, a1 + PI * 0.8, 16, Color(1.0, 0.85, 0.20, 0.8), 1.6)
		draw_arc(Vector2.ZERO, shield_r + 6.0, a1 + PI, a1 + PI * 1.8, 16, Color(1.0, 0.85, 0.20, 0.8), 1.6)

		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(-60, -88), "🛡️ KUSTOM FORCE FIELD (%d/3)" % outposts_remaining, HORIZONTAL_ALIGNMENT_CENTER, 120, 9, Color(0.35, 0.95, 0.25))

	# 6. Health Bar Plate
	var hp_ratio = float(current_health) / float(max_health)
	draw_rect(Rect2(-50, -68, 100, 7), Color(0.04, 0.05, 0.04, 0.95))
	draw_rect(Rect2(-48, -66, 96 * hp_ratio, 3.5), Color(0.95, 0.20, 0.15))
