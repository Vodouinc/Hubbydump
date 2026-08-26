extends CharacterBody2D
class_name SororitasDefender

enum State { OUTPOST_GUARD, MARCHING_TO_BASE, BASE_DEFENSE, DOWNED }

@export var sister_name: String = "Sister Ignis"
@export var weapon_type: String = "bolter"

var current_state: State = State.OUTPOST_GUARD
var max_health: int = 240
var current_health: int = 240

var patrol_offset_angle: float = 0.0
var patrol_radius: float = 120.0
var attack_cooldown: float = 0.0
var revive_timer: float = 0.0
const REVIVE_DURATION: float = 25.0

var nav_agent: NavigationAgent2D = null
var visual_sprite: UnitSprite = null
var health_bar: Node2D = null

func _ready() -> void:
	add_to_group("friendlies")
	add_to_group("controllable_units")
	add_to_group("sororitas_defenders")
	
	visual_sprite = UnitSprite.new()
	visual_sprite.unit_type = UnitSprite.UnitType.SISTER_OF_BATTLE
	add_child(visual_sprite)

	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 12.0
	col.shape = shape
	add_child(col)

	var hb_scene = load("res://HealthBar.tscn")
	if hb_scene:
		health_bar = hb_scene.instantiate()
		add_child(health_bar)
		if health_bar.has_method("setup"):
			health_bar.setup(current_health, max_health)

	nav_agent = NavigationAgent2D.new()
	nav_agent.path_desired_distance = 15.0
	nav_agent.target_desired_distance = 25.0
	add_child(nav_agent)

func _physics_process(delta: float) -> void:
	if current_state == State.DOWNED:
		if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
			revive_timer -= delta
			if revive_timer <= 0.0:
				_revive_at_sanctum()
		return

	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	match current_state:
		State.OUTPOST_GUARD:
			_process_outpost_idle(delta)
		State.MARCHING_TO_BASE:
			_process_march_to_base(delta)
		State.BASE_DEFENSE:
			_process_base_defense(delta)

func _process_outpost_idle(delta: float) -> void:
	var enemy = _find_nearest_enemy(240.0)
	if is_instance_valid(enemy):
		_engage_enemy(enemy, delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
		move_and_slide()

func _process_march_to_base(delta: float) -> void:
	var base_node = get_tree().get_first_node_in_group("base")
	if not is_instance_valid(base_node): return

	var target_pos = base_node.global_position + Vector2.RIGHT.rotated(patrol_offset_angle) * patrol_radius
	if global_position.distance_to(target_pos) <= 40.0:
		current_state = State.BASE_DEFENSE
		return

	nav_agent.target_position = target_pos
	if not nav_agent.is_navigation_finished():
		var next_path = nav_agent.get_next_path_position()
		var dir = global_position.direction_to(next_path)
		velocity = dir * 210.0
		if visual_sprite: visual_sprite.update_facing(next_path)
	move_and_slide()

func _process_base_defense(delta: float) -> void:
	var enemy = _find_nearest_enemy(320.0)
	if is_instance_valid(enemy):
		_engage_enemy(enemy, delta)
	else:
		var base_node = get_tree().get_first_node_in_group("base")
		if is_instance_valid(base_node):
			var patrol_angle = (Time.get_ticks_msec() * 0.0006) + patrol_offset_angle
			var patrol_pos = base_node.global_position + Vector2.RIGHT.rotated(patrol_angle) * patrol_radius
			if global_position.distance_to(patrol_pos) > 25.0:
				velocity = global_position.direction_to(patrol_pos) * 110.0
				if visual_sprite: visual_sprite.update_facing(patrol_pos)
			else:
				velocity = Vector2.ZERO
		move_and_slide()

func _engage_enemy(enemy: Node2D, _delta: float) -> void:
	var dist = global_position.distance_to(enemy.global_position)
	if visual_sprite: visual_sprite.update_facing(enemy.global_position)

	if dist > 140.0:
		velocity = global_position.direction_to(enemy.global_position) * 160.0
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	if attack_cooldown <= 0.0:
		_fire_weapon(enemy)

func _fire_weapon(enemy: Node2D) -> void:
	attack_cooldown = 0.45 if weapon_type == "bolter" else 0.85
	
	if weapon_type == "bolter":
		AudioManager.play_sfx("radium_shot", global_position, -2.0, 1.2)
		if enemy.has_method("take_damage"):
			enemy.take_damage(28, (enemy.global_position - global_position).normalized() * 80.0)
	else:
		AudioManager.play_sfx("volkite_beam", global_position, -1.0, 1.5)
		if enemy.has_method("take_damage"):
			enemy.take_damage(45, (enemy.global_position - global_position).normalized() * 120.0)

func order_march_to_base(offset_angle: float) -> void:
	patrol_offset_angle = offset_angle
	current_state = State.MARCHING_TO_BASE

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if current_state == State.DOWNED: return
	current_health = max(0, current_health - amount)
	
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	if current_health <= 0:
		_enter_downed_state()

func _enter_downed_state() -> void:
	current_state = State.DOWNED
	revive_timer = REVIVE_DURATION
	velocity = Vector2.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0

	var label = Label.new()
	label.script = load("res://DamageNumber.gd")
	label.global_position = global_position + Vector2(-50, -35)
	get_parent().add_child(label)
	label.text = "⚡ %s FALLEN (REVIVING AT BASE) ⚡" % sister_name
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.92, 0.22, 0.18)
	label.label_settings.font_size = 12

func _revive_at_sanctum() -> void:
	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		global_position = base_node.global_position + Vector2.RIGHT.rotated(patrol_offset_angle) * 40.0
	
	current_health = max_health
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	current_state = State.BASE_DEFENSE
	visible = true
	collision_layer = 1
	collision_mask = 1
	AudioManager.play_sfx("binary_canticle", global_position, 2.0, 1.2)

func _find_nearest_enemy(max_range: float) -> Node2D:
	var nearest: Node2D = null
	var min_d = max_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			var d = global_position.distance_to(e.global_position)
			if d < min_d:
				min_d = d
				nearest = e
	return nearest
