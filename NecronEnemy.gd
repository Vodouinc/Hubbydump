# res://NecronEnemy.gd
extends CharacterBody2D
class_name NecronEnemy

enum NecronType { SCARAB = 0, WARRIOR = 1, CRYPTEK_BOSS = 2 }

@export var necron_type: NecronType = NecronType.SCARAB
var max_health: int = 40
var current_health: int = 40
var speed: float = 180.0
var damage: int = 12

var attack_timer: float = 0.0
var tesla_timer: float = 0.0
var is_reanimating: bool = false
var reanimate_timer: float = 0.0
var has_reanimated: bool = false

var health_bar: Node2D = null
var visual_sprite: NecronVisuals = null

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("necron_enemies")

	match necron_type:
		NecronType.SCARAB:
			max_health = 35
			speed = 220.0
			damage = 8
		NecronType.WARRIOR:
			max_health = 130
			speed = 100.0
			damage = 18
		NecronType.CRYPTEK_BOSS:
			max_health = 750
			speed = 115.0
			damage = 45

	current_health = max_health

	# 1. Collision Shape
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 10.0 if necron_type == NecronType.SCARAB else (16.0 if necron_type == NecronType.WARRIOR else 24.0)
	col.shape = shape
	add_child(col)

	# 2. Visual Model Renderer
	visual_sprite = NecronVisuals.new()
	visual_sprite.name = "VisualSprite"
	visual_sprite.type = necron_type as NecronVisuals.NecronType
	add_child(visual_sprite)

	# 3. Dynamic Health Bar Setup
	_setup_health_bar()

func _setup_health_bar() -> void:
	var hb_script = load("res://HealthBar.gd")
	if hb_script:
		health_bar = Node2D.new()
		health_bar.set_script(hb_script)
		health_bar.name = "HealthBar"
		
		match necron_type:
			NecronType.SCARAB:
				health_bar.bar_size = Vector2(22.0, 3.0)
				health_bar.bar_offset = Vector2(0.0, -14.0)
				health_bar.auto_hide_when_full = true
				health_bar.always_visible = false
			NecronType.WARRIOR:
				health_bar.bar_size = Vector2(32.0, 4.0)
				health_bar.bar_offset = Vector2(0.0, -26.0)
				health_bar.auto_hide_when_full = false
				health_bar.always_visible = false
			NecronType.CRYPTEK_BOSS:
				health_bar.bar_size = Vector2(60.0, 7.0)
				health_bar.bar_offset = Vector2(0.0, -42.0)
				health_bar.auto_hide_when_full = false
				health_bar.always_visible = true # Boss bar always visible!

		add_child(health_bar)
		if health_bar.has_method("setup"):
			health_bar.setup(current_health, max_health)

func _physics_process(delta: float) -> void:
	if is_reanimating:
		reanimate_timer -= delta
		if reanimate_timer <= 0.0:
			_complete_reanimation()
		return

	if attack_timer > 0.0: attack_timer -= delta
	if tesla_timer > 0.0: tesla_timer -= delta

	var target = _find_nearest_friendly(350.0 if necron_type != NecronType.SCARAB else 450.0)
	if is_instance_valid(target):
		var dist = global_position.distance_to(target.global_position)
		var stop_dist = 30.0 if necron_type == NecronType.SCARAB else (160.0 if necron_type == NecronType.WARRIOR else 120.0)

		if dist > stop_dist:
			velocity = global_position.direction_to(target.global_position) * speed
		else:
			velocity = Vector2.ZERO

		if attack_timer <= 0.0:
			_execute_necron_attack(target)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)

	move_and_slide()

	if is_instance_valid(visual_sprite):
		visual_sprite.is_reanimating = is_reanimating

func _execute_necron_attack(target: Node2D) -> void:
	match necron_type:
		NecronType.SCARAB:
			attack_timer = 0.8
			if global_position.distance_to(target.global_position) <= 45.0 and target.has_method("take_damage"):
				target.take_damage(damage, (target.global_position - global_position).normalized() * 50.0)
				AudioManager.play_sfx("hit", global_position, -4.0, 1.6)

		NecronType.WARRIOR:
			attack_timer = 2.0
			AudioManager.play_sfx("radium_shot", global_position, -2.0, 0.8)
			_spawn_gauss_projectile(target.global_position)

		NecronType.CRYPTEK_BOSS:
			attack_timer = 1.6
			AudioManager.play_sfx("volkite_beam", global_position, 2.0, 0.7)
			if target.has_method("take_damage"):
				target.take_damage(damage, (target.global_position - global_position).normalized() * 180.0)

			# Tesla Discharge (bounces to nearby players/friendlies)
			if tesla_timer <= 0.0:
				tesla_timer = 4.5
				_fire_tesla_arc(target)

func _spawn_gauss_projectile(target_pos: Vector2) -> void:
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return

	var dir = (target_pos - global_position).normalized()
	main_node.spawn_entity({
		"type": "bullet",
		"name": "GaussShot_" + str(randi()),
		"position": global_position + (dir * 20.0),
		"direction": dir,
		"damage": damage,
		"bullet_type": 6, # BulletType.GAUSS_FLAYER
		"is_enemy_bullet": true
	})

func _fire_tesla_arc(primary_target: Node2D) -> void:
	AudioManager.play_sfx("arc_lightning", global_position, 2.0, 0.8)
	var friendlies = get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("friendlies")
	for f in friendlies:
		if is_instance_valid(f) and f != primary_target and primary_target.global_position.distance_to(f.global_position) <= 160.0:
			if f.has_method("take_damage"):
				f.take_damage(25, (f.global_position - primary_target.global_position).normalized() * 120.0)

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if is_reanimating: return
	current_health = max(0, current_health - amount)

	if is_instance_valid(health_bar) and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	if current_health <= 0:
		if necron_type == NecronType.CRYPTEK_BOSS and not has_reanimated:
			_trigger_reanimation_protocol()
		else:
			_die()

func _trigger_reanimation_protocol() -> void:
	has_reanimated = true
	is_reanimating = true
	reanimate_timer = 5.0
	velocity = Vector2.ZERO
	AudioManager.play_sfx("orbital_strike", global_position, 1.0, 1.8)

func _complete_reanimation() -> void:
	is_reanimating = false
	current_health = int(max_health * 0.45)
	if is_instance_valid(health_bar) and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
	AudioManager.play_sfx("binary_canticle", global_position, 3.0, 0.9)

func _die() -> void:
	if necron_type == NecronType.CRYPTEK_BOSS:
		var tomb = get_tree().get_first_node_in_group("necron_tomb")
		if is_instance_valid(tomb) and tomb.has_method("notify_cryptek_slain"):
			tomb.notify_cryptek_slain()

	queue_free()

func _find_nearest_friendly(max_range: float) -> Node2D:
	var candidates = get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("friendlies") + get_tree().get_nodes_in_group("buildings")
	var nearest: Node2D = null
	var min_d = max_range
	for c in candidates:
		if is_instance_valid(c):
			var d = global_position.distance_to(c.global_position)
			if d < min_d:
				min_d = d
				nearest = c
	return nearest
