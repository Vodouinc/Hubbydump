extends CharacterBody2D
class_name KataphronUnit

var max_health: int = 520
var current_health: int = 520
var movement_speed: float = 140.0
var damage: int = 65
var attack_range: float = 260.0
var attack_cooldown: float = 0.85
var can_attack: bool = true

var rally_anchor: Vector2 = Vector2.ZERO
var has_received_player_order: bool = false

# RTS State
var rts_target_pos: Vector2 = Vector2.ZERO
var is_rts_moving: bool = false
var is_attack_moving: bool = false
var current_attack_target: Node2D = null
var is_rts_selected: bool = false
var is_facing_left: bool = false

var tread_anim: float = 0.0

@onready var health_bar: Node2D = get_node_or_null("HealthBar")

func _ready() -> void:
	add_to_group("bodyguards")
	add_to_group("friendlies")
	add_to_group("controllable_units")
	
	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)

	var col = get_node_or_null("CollisionShape2D")
	if not col:
		col = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 14.0
		col.shape = shape
		add_child(col)

	if not has_node("KataphronLight"):
		var light = LightUtils.create_point_light(Color(0.20, 0.88, 1.0), 0.8, 1.8)
		light.name = "KataphronLight"
		add_child(light)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return

	if velocity.length_squared() > 10.0:
		tread_anim += delta * 12.0

	var in_grid = false
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.get("is_noosphere_connected") and global_position.distance_to(b.global_position) <= 240.0:
			in_grid = true
			break

	if in_grid and current_health < max_health:
		current_health = min(max_health, current_health + int(ceil(2.0 * delta)))
		if health_bar and health_bar.has_method("update_health"):
			health_bar.update_health(current_health, max_health)

	if is_instance_valid(current_attack_target):
		var dist = global_position.distance_to(current_attack_target.global_position)
		is_facing_left = (current_attack_target.global_position.x < global_position.x)
		if dist <= attack_range:
			velocity = Vector2.ZERO
			if can_attack: _execute_attack(current_attack_target)
		else:
			velocity = global_position.direction_to(current_attack_target.global_position) * movement_speed

	elif is_rts_moving:
		if is_attack_moving:
			var threat = _find_best_target(attack_range + 30.0)
			if is_instance_valid(threat):
				current_attack_target = threat

		var dist = global_position.distance_to(rts_target_pos)
		if dist > 10.0:
			velocity = global_position.direction_to(rts_target_pos) * movement_speed
			is_facing_left = (velocity.x < -0.1)
		else:
			is_rts_moving = false
			is_attack_moving = false
			velocity = Vector2.ZERO

	else:
		velocity = velocity.move_toward(Vector2.ZERO, movement_speed * 6.0 * delta)
		var threat = _find_best_target(attack_range if has_received_player_order else 220.0)
		if is_instance_valid(threat):
			is_facing_left = (threat.global_position.x < global_position.x)
			if global_position.distance_to(threat.global_position) <= attack_range:
				if can_attack: _execute_attack(threat)
			elif not has_received_player_order:
				velocity = global_position.direction_to(threat.global_position) * movement_speed
		elif not has_received_player_order:
			if rally_anchor != Vector2.ZERO:
				var dist_to_anchor = global_position.distance_to(rally_anchor)
				if dist_to_anchor > 35.0:
					velocity = global_position.direction_to(rally_anchor) * (movement_speed * 0.75)
					is_facing_left = (velocity.x < -0.1)
			else:
				var p = _get_nearest_friendly_player()
				if is_instance_valid(p) and global_position.distance_to(p.global_position) > 85.0:
					velocity = global_position.direction_to(p.global_position) * movement_speed
					is_facing_left = (velocity.x < -0.1)

	move_and_slide()
	rpc("sync_unit_state", global_position, is_facing_left, tread_anim)

func _execute_attack(target: Node2D):
	can_attack = false
	AudioManager.play_sfx("arc_lightning", global_position, 0.0, 1.2)

	var is_structure = target.is_in_group("ork_citadel") or target.is_in_group("ork_structures") or target.is_in_group("objectives")
	var final_damage = damage * 2 if is_structure else damage
	
	if target.get("has_telemetry_mark"):
		final_damage = int(final_damage * 1.35)

	if target.has_method("take_damage"):
		target.take_damage(final_damage, (target.global_position - global_position).normalized() * 180.0)

	get_tree().create_timer(attack_cooldown).timeout.connect(func(): if is_instance_valid(self): can_attack = true)

func set_initial_rally(target_pos: Vector2) -> void:
	rally_anchor = target_pos
	has_received_player_order = false
	rts_target_pos = target_pos
	is_rts_moving = true
	is_attack_moving = true
	current_attack_target = null

func rts_move_to(pos: Vector2, is_attack_move: bool = false) -> void:
	has_received_player_order = true
	rts_target_pos = pos
	is_rts_moving = true
	is_attack_moving = is_attack_move
	current_attack_target = null

func rts_attack_target(target: Node2D) -> void:
	has_received_player_order = true
	current_attack_target = target
	is_rts_moving = false

func rts_stop() -> void:
	has_received_player_order = true
	is_rts_moving = false
	current_attack_target = null

func rts_hold() -> void:
	has_received_player_order = true
	is_rts_moving = false

func _find_best_target(max_d: float) -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var best_target: Node2D = null
	var min_d = max_d

	for e in enemies:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			if e.get("has_telemetry_mark"):
				var d = global_position.distance_to(e.global_position)
				if d <= max_d * 1.35:
					return e

	for e in enemies:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			var d = global_position.distance_to(e.global_position)
			if d < min_d:
				min_d = d
				best_target = e
	return best_target

func _get_nearest_friendly_player() -> Node2D:
	var players = get_tree().get_nodes_in_group("players")
	var closest: Node2D = null
	var min_d = 99999.0
	for p in players:
		if is_instance_valid(p):
			var d = global_position.distance_to(p.global_position)
			if d < min_d:
				min_d = d
				closest = p
	return closest

func set_rts_selected(selected: bool):
	is_rts_selected = selected
	queue_redraw()

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO):
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer(): return
	current_health = max(0, current_health - amount)
	rpc("sync_health", current_health)
	if current_health <= 0:
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node and main_node.has_method("notify_cohort_unit_lost"):
			main_node.notify_cohort_unit_lost()
		queue_free()

@rpc("call_local", "reliable")
func sync_health(hp: int):
	current_health = hp
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

@rpc("unreliable")
func sync_unit_state(pos: Vector2, facing_left: bool, anim_val: float):
	if not multiplayer.is_server():
		global_position = global_position.lerp(pos, 0.45)
		is_facing_left = facing_left
		tread_anim = anim_val
		queue_redraw()

func _find_nearest_enemy(max_d: float) -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var closest: Node2D = null
	var min_d = max_d
	for e in enemies:
		if is_instance_valid(e):
			var d = global_position.distance_to(e.global_position)
			if d < min_d: min_d = d; closest = e
	return closest

func _draw() -> void:
	if is_rts_selected:
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 28, Color(0.20, 0.88, 1.0, 0.85), 1.6)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	draw_rect(Rect2(-12, -8, 24, 16), Color(0.12, 0.14, 0.18))
	draw_rect(Rect2(-12, -8, 24, 16), Color(0.35, 0.40, 0.48), false, 1.5)

	for i in range(4):
		var offset_x = -9.0 + fposmod((i * 6.0) + tread_anim, 20.0)
		draw_line(Vector2(offset_x, -7), Vector2(offset_x, 7), Color(0.24, 0.28, 0.35), 1.2)

	draw_circle(Vector2(0, -2), 8.0, Color(0.68, 0.16, 0.14))
	draw_rect(Rect2(2, -6, 12, 5), Color(0.20, 0.88, 1.0))
	draw_circle(Vector2(-1, -6), 4.0, Color(0.85, 0.88, 0.92))
	draw_circle(Vector2(1, -6), 1.5, Color(0.20, 0.88, 1.0))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
