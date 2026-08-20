extends CharacterBody2D

enum EnemyType { GRETCHIN, SQUIG, ORK_BOY }

@export var type: EnemyType = EnemyType.GRETCHIN:
	set(value):
		type = value
		if is_node_ready():
			apply_type_stats()
			update_visuals()

@export var speed: float = 120.0
@export var max_health: int = 50
@export var damage: int = 10
@export var attack_range: float = 75.0

var current_health: int = 50
var attack_cooldown_timer: float = 0.0
var base_node: Node2D = null
var is_objective_guard: bool = false
var guard_anchor: Vector2 = Vector2.ZERO
var counts_toward_wave: bool = true
var aggro_scan_timer: float = 0.0
var cached_target_friendly: Node2D = null

# Hit Feedback Variables
var knockback_velocity: Vector2 = Vector2.ZERO
var flash_timer: float = 0.0

@onready var health_bar: Node2D = get_node_or_null("HealthBar")
@onready var visual_sprite: Node2D = get_node_or_null("VisualSprite")
@onready var nav_agent: NavigationAgent2D = get_node_or_null("NavigationAgent2D")
@onready var shadow_node: Node2D = get_node_or_null("Shadow")

func _ready() -> void:
	add_to_group("enemies")
	if is_objective_guard:
		add_to_group("objective_guards")
	
	apply_type_stats()
	update_visuals()
	
	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)
	update_ui()
	
	base_node = get_tree().get_first_node_in_group("base") as Node2D

	var is_host = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
	if nav_agent and is_host:
		NavigationServer2D.map_changed.connect(_on_nav_map_changed)
		call_deferred("setup_navigation")

func setup_navigation() -> void:
	await get_tree().physics_frame
	_update_nav_target()

func _on_nav_map_changed(_map_rid: RID) -> void:
	# Stagger target re-checks over 0.05 - 0.25s so the CPU doesn't spike all at once
	var delay = randf_range(0.05, 0.25)
	get_tree().create_timer(delay).timeout.connect(func():
		if is_instance_valid(self):
			_update_nav_target()
	)

func _update_nav_target() -> void:
	if not is_instance_valid(base_node):
		base_node = get_tree().get_first_node_in_group("base") as Node2D
		
	if is_instance_valid(base_node) and nav_agent:
		nav_agent.target_position = base_node.global_position

func apply_type_stats() -> void:
	match type:
		EnemyType.GRETCHIN:
			speed = 160.0
			max_health = 25
			damage = 5
			if health_bar:
				health_bar.bar_size = Vector2(22.0, 3.5)
				health_bar.bar_offset = Vector2(0.0, -18.0)
		EnemyType.SQUIG:
			speed = 130.0
			max_health = 60
			damage = 15
			if health_bar:
				health_bar.bar_size = Vector2(28.0, 4.0)
				health_bar.bar_offset = Vector2(0.0, -24.0)
		EnemyType.ORK_BOY:
			speed = 80.0
			max_health = 140
			damage = 25
			if health_bar:
				health_bar.bar_size = Vector2(34.0, 4.5)
				health_bar.bar_offset = Vector2(0.0, -28.0)

func update_visuals() -> void:
	if not visual_sprite:
		visual_sprite = get_node_or_null("VisualSprite")
		
	if visual_sprite and visual_sprite.has_method("set_enemy_type"):
		visual_sprite.set_enemy_type(type)

	if not shadow_node:
		shadow_node = get_node_or_null("Shadow")
	if shadow_node and shadow_node.has_method("update_shadow_size"):
		shadow_node.update_shadow_size()

func _process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0 and visual_sprite:
			visual_sprite.modulate = Color.WHITE

func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
		
	if is_objective_guard:
		aggro_scan_timer += delta
		if aggro_scan_timer >= 0.15:
			aggro_scan_timer = 0.0
			cached_target_friendly = _find_nearest_friendly_in_range(260.0)

		if is_instance_valid(cached_target_friendly):
			var dist = global_position.distance_to(cached_target_friendly.global_position)
			if dist <= attack_range:
				velocity = Vector2.ZERO
				perform_attack(cached_target_friendly)
			else:
				velocity = global_position.direction_to(cached_target_friendly.global_position) * speed
			move_and_slide()
			return

		# Patrol Orbit
		var wander_radius = 90.0 + (float(get_instance_id() % 6) * 16.0)
		var patrol_angle = (Time.get_ticks_msec() * 0.0007) + (float(get_instance_id()) * 1.2)
		var patrol_target = guard_anchor + Vector2.RIGHT.rotated(patrol_angle) * wander_radius

		var dist_to_patrol = global_position.distance_to(patrol_target)
		velocity = global_position.direction_to(patrol_target) * (speed * 0.55) if dist_to_patrol > 15.0 else Vector2.ZERO
		move_and_slide()
		return

	# Handle Attack Cooldown
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta

	# Re-locate base if missing
	if not is_instance_valid(base_node):
		base_node = get_tree().get_first_node_in_group("base") as Node2D
		if not base_node:
			velocity = Vector2.ZERO
			return

	# Handle Knockback Stagger
	if knockback_velocity.length() > 10.0:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1500.0 * delta)
		velocity = knockback_velocity
		move_and_slide()
		return

	# Idol guards actively protect their camp and chase players who trespass
	if is_objective_guard:
		# 1. Check for nearby players or friendly bodyguards to attack
		var target_friendly = _find_nearest_friendly_in_range(260.0)
		if is_instance_valid(target_friendly):
			var dist = global_position.distance_to(target_friendly.global_position)
			if dist <= attack_range:
				velocity = Vector2.ZERO
				perform_attack(target_friendly)
			else:
				velocity = global_position.direction_to(target_friendly.global_position) * speed
			move_and_slide()
			return

		# 2. If no players nearby, patrol in a wide orbit around the camp anchor
		var wander_radius = 90.0 + (float(get_instance_id() % 6) * 16.0)
		var patrol_angle = (Time.get_ticks_msec() * 0.0007) + (float(get_instance_id()) * 1.2)
		var patrol_target = guard_anchor + Vector2.RIGHT.rotated(patrol_angle) * wander_radius

		var dist_to_patrol = global_position.distance_to(patrol_target)
		if dist_to_patrol > 15.0:
			velocity = global_position.direction_to(patrol_target) * (speed * 0.55)
		else:
			velocity = Vector2.ZERO

		move_and_slide()
		return

	# 1. Check distance to base
	var dist_to_base = global_position.distance_to(base_node.global_position)
	if dist_to_base <= attack_range:
		velocity = Vector2.ZERO
		perform_attack(base_node)
		return

	# 2. Compute Movement via NavigationAgent2D
	var move_direction = Vector2.ZERO

	if nav_agent:
		if not nav_agent.is_navigation_finished():
			var next_path_pos = nav_agent.get_next_path_position()
			move_direction = global_position.direction_to(next_path_pos)
		else:
			_update_nav_target()
	else:
		move_direction = global_position.direction_to(base_node.global_position)

	velocity = move_direction * speed

	# 3. Move and check for breakable obstacles blocking the direct path
	if move_and_slide():
		for i in range(get_slide_collision_count()):
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			
			if is_instance_valid(collider):
				if collider.has_method("take_damage") and not collider.is_in_group("enemies"):
					velocity = Vector2.ZERO
					perform_attack(collider)
					return

func _find_nearest_friendly_in_range(range_limit: float) -> Node2D:
	var candidates: Array = get_tree().get_nodes_in_group("players")
	candidates.append_array(get_tree().get_nodes_in_group("bodyguards"))
	
	var nearest: Node2D = null
	var min_d = range_limit
	for c in candidates:
		if is_instance_valid(c):
			var d = global_position.distance_to(c.global_position)
			if d < min_d:
				min_d = d
				nearest = c
	return nearest

func perform_attack(target: Node2D) -> void:
	if attack_cooldown_timer > 0.0 or not is_instance_valid(target):
		return

	attack_cooldown_timer = 1.0
	rpc("trigger_attack_charge")
	
	if target.has_method("take_damage"):
		target.take_damage(damage)
	else:
		print_debug("Target ", target.name, " reached, but lacks 'take_damage(amount)' function.")

func release_objective_guard() -> void:
	is_objective_guard = false
	remove_from_group("objective_guards")

@rpc("call_local", "reliable")
func trigger_attack_charge() -> void:
	if visual_sprite:
		if visual_sprite.has_method("play_attack_fx"):
			visual_sprite.play_attack_fx()
		var tween = create_tween().set_parallel(true)
		visual_sprite.scale = Vector2(0.8, 1.2)
		tween.tween_property(visual_sprite, "scale", Vector2(1.3, 0.7), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(visual_sprite, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_SINE)

func take_damage(amount: int, knockback_impulse: Vector2 = Vector2.ZERO) -> void:
	if multiplayer.is_server():
		if knockback_impulse != Vector2.ZERO:
			var knockback_modifier = 1.0
			if type == EnemyType.ORK_BOY:
				knockback_modifier = 0.4
			elif type == EnemyType.GRETCHIN:
				knockback_modifier = 1.2
				
			knockback_velocity = knockback_impulse * knockback_modifier

		var new_health = max(0, current_health - amount)
		rpc("sync_health", new_health)
		rpc("trigger_hit_flash")
		
		var random_offset = Vector2(randf_range(-12.0, 12.0), randf_range(-10.0, 5.0))
		rpc("spawn_damage_number", amount, global_position + random_offset)

@rpc("call_local", "unreliable")
func spawn_damage_number(amount: int, spawn_pos: Vector2) -> void:
	var dmg_label = Label.new()
	dmg_label.script = load("res://DamageNumber.gd")
	dmg_label.global_position = spawn_pos
	
	var is_crit = amount >= 35
	get_parent().add_child(dmg_label)
	dmg_label.setup(amount, is_crit)

@rpc("call_local", "unreliable")
func trigger_hit_flash() -> void:
	
	AudioManager.play_sfx("hit", global_position, -6.0)
	
	if visual_sprite:
		visual_sprite.modulate = Color(2.0, 0.3, 0.3)
		flash_timer = 0.12

@rpc("call_local", "reliable")
func sync_health(new_health: int) -> void:
	current_health = new_health
	update_ui()

	if current_health <= 0:
		if multiplayer.is_server():
			if not is_queued_for_deletion():
				call_deferred("_handle_death")

func _handle_death() -> void:
	if NavigationServer2D.map_changed.is_connected(_on_nav_map_changed):
		NavigationServer2D.map_changed.disconnect(_on_nav_map_changed)

	var main_node = get_parent()
	if main_node:
		if "spawner" in main_node and main_node.spawner:
			if "scrap_count" in main_node:
				main_node.scrap_count += 1
				
			var scrap_data = {
				"type": "scrap",
				"name": "Scrap_" + str(main_node.get("scrap_count") if "scrap_count" in main_node else randi()),
				"position": global_position
			}
			main_node.spawner.spawn(scrap_data)

		if counts_toward_wave and main_node.has_method("notify_enemy_defeated"):
			main_node.notify_enemy_defeated()

	queue_free()

func update_ui() -> void:
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
