extends CharacterBody2D
class_name SkitariiInfantry

@export var unit_type: GameData.CohortUnitType = GameData.CohortUnitType.VANGUARD

var max_health: int = 90
var current_health: int = 90
var movement_speed: float = 210.0
var damage: int = 18
var attack_range: float = 280.0
var attack_cooldown: float = 0.35
var can_attack: bool = true

# RTS State
var rts_target_pos: Vector2 = Vector2.ZERO
var is_rts_moving: bool = false
var is_attack_moving: bool = false
var current_attack_target: Node2D = null
var is_rts_selected: bool = false
var is_facing_left: bool = false

var rad_aura_pulse: float = 0.0

@onready var health_bar: Node2D = get_node_or_null("HealthBar")

func _ready() -> void:
	add_to_group("bodyguards")
	add_to_group("friendlies")
	add_to_group("controllable_units")
	
	_apply_unit_stats()
	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)

	var col = get_node_or_null("CollisionShape2D")
	if not col:
		col = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 10.0
		col.shape = shape
		add_child(col)

func _apply_unit_stats():
	var data = GameData.COHORT_UNITS.get(unit_type, {})
	max_health = data.get("hp", 90)
	damage = data.get("damage", 18)
	movement_speed = data.get("speed", 210.0)
	attack_range = data.get("range", 280.0)
	attack_cooldown = 0.30 if unit_type == GameData.CohortUnitType.VANGUARD else (0.90 if unit_type == GameData.CohortUnitType.RANGER else 0.40)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return

	if unit_type == GameData.CohortUnitType.VANGUARD:
		rad_aura_pulse += delta
		if rad_aura_pulse >= 0.5:
			rad_aura_pulse = 0.0
			_pulse_radiation_field()

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
		var dist = global_position.distance_to(rts_target_pos)
		if dist > 8.0:
			velocity = global_position.direction_to(rts_target_pos) * movement_speed
			is_facing_left = (velocity.x < -0.1)
		else:
			is_rts_moving = false
			velocity = Vector2.ZERO

		if is_attack_moving:
			var enemy = _find_nearest_enemy(attack_range)
			if is_instance_valid(enemy):
				current_attack_target = enemy
	else:
		velocity = velocity.move_toward(Vector2.ZERO, movement_speed * 6.0 * delta)
		var enemy = _find_nearest_enemy(attack_range)
		if is_instance_valid(enemy):
			is_facing_left = (enemy.global_position.x < global_position.x)
			if can_attack: _execute_attack(enemy)

	move_and_slide()
	rpc("sync_unit_state", global_position, is_facing_left)

func _pulse_radiation_field():
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= 80.0:
			if e.has_method("take_damage"):
				e.take_damage(4)
				e.set("speed", e.get("speed") * 0.82)

func _execute_attack(target: Node2D):
	can_attack = false
	AudioManager.play_sfx("radium_shot" if unit_type != GameData.CohortUnitType.RUSTSTALKER else "axe_swing", global_position, -4.0, 1.3)

	var main_node = get_tree().get_first_node_in_group("main")
	var crit_mult = 1.35 if target.get("has_telemetry_mark") else 1.0
	var final_dmg = int(damage * crit_mult)

	if unit_type == GameData.CohortUnitType.RUSTSTALKER:
		if target.has_method("take_damage"):
			target.take_damage(final_dmg, (target.global_position - global_position).normalized() * 150.0)
	elif main_node and "spawner" in main_node and main_node.spawner:
		var dir = (target.global_position - global_position).normalized()
		main_node.spawner.spawn({
			"type": "bullet",
			"name": "InfantryBullet_" + str(randi()),
			"position": global_position + (dir * 12.0),
			"direction": dir,
			"damage": final_dmg
		})

	get_tree().create_timer(attack_cooldown).timeout.connect(func(): if is_instance_valid(self): can_attack = true)

func rts_move_to(pos: Vector2, is_attack_move: bool = false):
	rts_target_pos = pos
	is_rts_moving = true
	is_attack_moving = is_attack_move
	current_attack_target = null

func rts_attack_target(target: Node2D):
	current_attack_target = target
	is_rts_moving = false

func rts_stop():
	is_rts_moving = false
	current_attack_target = null

func rts_hold():
	is_rts_moving = false

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
func sync_unit_state(pos: Vector2, facing_left: bool):
	if not multiplayer.is_server():
		global_position = global_position.lerp(pos, 0.45)
		is_facing_left = facing_left
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
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, Color(0.20, 0.88, 1.0, 0.85), 1.4)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	draw_circle(Vector2(0, 0), 7.0, Color(0.68, 0.16, 0.14))
	draw_circle(Vector2(0, -4), 4.5, Color(0.85, 0.88, 0.92))
	draw_circle(Vector2(2, -4), 1.5, Color(0.20, 0.88, 1.0))

	match unit_type:
		GameData.CohortUnitType.VANGUARD:
			draw_arc(Vector2(0, -4), 8.0, 0.0, TAU, 16, Color(0.35, 0.95, 0.45, 0.65), 1.2)
			draw_line(Vector2(2, 0), Vector2(10, 0), Color(0.35, 0.40, 0.48), 2.5)
			draw_circle(Vector2(10, 0), 1.8, Color(0.35, 0.95, 0.45))

		GameData.CohortUnitType.RANGER:
			draw_line(Vector2(0, 2), Vector2(18, -2), Color(0.24, 0.28, 0.35), 2.0)
			draw_circle(Vector2(18, -2), 1.5, Color(0.82, 0.62, 0.24))

		GameData.CohortUnitType.RUSTSTALKER:
			draw_line(Vector2(3, -2), Vector2(12, -8), Color(0.20, 0.88, 1.0), 2.2)
			draw_line(Vector2(3, 2), Vector2(12, 8), Color(0.20, 0.88, 1.0), 2.2)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
