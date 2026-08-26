# res://Enemy.gd
extends CharacterBody2D
class_name Enemy

enum EnemyType { GRETCHIN, SQUIG, ORK_BOY, STORMBOY, NOB, WARBOSS }

var march_waypoints: Array[Vector2] = []
var is_warboss: bool = false

@export var type: int = 0:
	set(value):
		type = value
		if is_node_ready():
			apply_type_stats()
			update_visuals()

@export var speed: float = 130.0
@export var max_health: int = 50
@export var damage: int = 10
@export var attack_range: float = 75.0

var current_health: int = 50
var attack_cooldown_timer: float = 0.0
var ability_timer: float = 0.0
var hook_cooldown_timer: float = 0.0
var base_node: Node2D = null
var is_objective_guard: bool = false
var guard_anchor: Vector2 = Vector2.ZERO
var counts_toward_wave: bool = true
var stuck_check_timer: float = 0.0
var last_stuck_pos: Vector2 = Vector2.ZERO

var repath_timer: float = 0.0
var gretchin_panic_timer: float = 0.0
var gretchin_threat_scan_timer: float = 0.0

var current_aggro_target: Node2D = null
var aggro_scan_timer: float = 0.0
var aggro_detection_range: float = 320.0
var deaggro_range: float = 520.0

var mob_rule_scan_timer: float = 0.0
const MOB_RULE_SCAN_INTERVAL: float = 0.3
var is_jumping_or_lunging: bool = false
var is_hook_winding_up: bool = false
var rage_buff_timer: float = 0.0
var is_mob_rule_active: bool = false
var is_berserk: bool = false
var lateral_fanning_seed: float = 0.0

var targeted_scrap_item: Node2D = null
var has_stolen_scrap: bool = false

var has_telemetry_mark: bool = false
var telemetry_mark_timer: float = 0.0

var knockback_velocity: Vector2 = Vector2.ZERO
var flash_timer: float = 0.0

@onready var health_bar: Node2D = get_node_or_null("HealthBar")
@onready var visual_sprite: Node2D = get_node_or_null("VisualSprite")
@onready var nav_agent: NavigationAgent2D = get_node_or_null("NavigationAgent2D")
@onready var shadow_node: Node2D = get_node_or_null("Shadow")
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")

func _ready() -> void:
	add_to_group("enemies")
	lateral_fanning_seed = float(get_instance_id() % 13) * 0.48
	
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
	if not is_inside_tree(): return
	var tween = create_tween()
	tween.tween_interval(randf_range(0.05, 0.25))
	tween.tween_callback(_update_nav_target)

func _update_nav_target() -> void:
	if not nav_agent: return

	if is_instance_valid(current_aggro_target):
		nav_agent.target_position = current_aggro_target.global_position
		return

	while not march_waypoints.is_empty():
		var target_pt = march_waypoints[0]
		if global_position.distance_to(target_pt) <= 220.0 or (nav_agent.is_navigation_finished() and global_position.distance_to(target_pt) <= 400.0):
			march_waypoints.pop_front()
		else:
			nav_agent.target_position = target_pt
			return

	if not is_instance_valid(base_node):
		base_node = get_tree().get_first_node_in_group("base") as Node2D
		
	if is_instance_valid(base_node):
		var surround_angle = float(get_instance_id() % 16) * (TAU / 16.0)
		var surround_offset = Vector2.RIGHT.rotated(surround_angle) * 75.0
		nav_agent.target_position = base_node.global_position + surround_offset

func apply_type_stats() -> void:
	match type:
		EnemyType.GRETCHIN:
			speed = 145.0
			max_health = 45
			damage = 5
			attack_range = 190.0
			aggro_detection_range = 240.0
			if health_bar:
				health_bar.bar_size = Vector2(22.0, 3.5)
				health_bar.bar_offset = Vector2(0.0, -16.0)
		EnemyType.SQUIG:
			speed = 210.0
			max_health = 45
			damage = 12
			attack_range = 55.0
			aggro_detection_range = 360.0
			if health_bar:
				health_bar.bar_size = Vector2(20.0, 3.0)
				health_bar.bar_offset = Vector2(0.0, -15.0)
		EnemyType.ORK_BOY:
			speed = 130.0
			max_health = 160
			damage = 22
			attack_range = 70.0
			aggro_detection_range = 280.0
			if health_bar:
				health_bar.bar_size = Vector2(34.0, 4.5)
				health_bar.bar_offset = Vector2(0.0, -28.0)
		EnemyType.STORMBOY:
			speed = 185.0
			max_health = 95
			damage = 18
			attack_range = 75.0
			aggro_detection_range = 360.0
			if health_bar:
				health_bar.bar_size = Vector2(30.0, 4.0)
				health_bar.bar_offset = Vector2(0.0, -26.0)
		EnemyType.NOB:
			speed = 110.0
			max_health = 450
			damage = 42
			attack_range = 85.0
			aggro_detection_range = 380.0
			if health_bar:
				health_bar.bar_size = Vector2(44.0, 5.5)
				health_bar.bar_offset = Vector2(0.0, -34.0)
		EnemyType.WARBOSS:
			speed = 125.0
			max_health = 1800
			damage = 75
			attack_range = 100.0
			aggro_detection_range = 440.0
			if health_bar:
				health_bar.bar_size = Vector2(60.0, 7.0)
				health_bar.bar_offset = Vector2(0.0, -44.0)
				health_bar.always_visible = true

	if is_instance_valid(collision_shape) and collision_shape.shape is CircleShape2D:
		match type:
			EnemyType.GRETCHIN, EnemyType.SQUIG:
				collision_shape.shape.radius = 8.5
			EnemyType.ORK_BOY, EnemyType.STORMBOY:
				collision_shape.shape.radius = 13.0
			EnemyType.NOB:
				collision_shape.shape.radius = 19.0
			EnemyType.WARBOSS:
				collision_shape.shape.radius = 28.0

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
	var fow = get_tree().get_first_node_in_group("fog_of_war")
	if fow and fow.has_method("is_world_pos_visible"):
		var in_sight = fow.is_world_pos_visible(global_position)
		if visual_sprite: visual_sprite.visible = in_sight
		if shadow_node: shadow_node.visible = in_sight
		if health_bar: health_bar.visible = in_sight

	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0 and visual_sprite:
			visual_sprite.modulate = Color.WHITE

	if telemetry_mark_timer > 0.0:
		telemetry_mark_timer -= delta
		if telemetry_mark_timer <= 0.0:
			has_telemetry_mark = false
		queue_redraw()

	if visual_sprite and visual_sprite.has_method("update_facing"):
		visual_sprite.update_facing(velocity)

func apply_telemetry_mark(duration: float = 6.0):
	has_telemetry_mark = true
	telemetry_mark_timer = duration
	rpc("sync_telemetry_mark", true, duration)

@rpc("call_local", "unreliable")
func sync_telemetry_mark(marked: bool, duration: float):
	has_telemetry_mark = marked
	telemetry_mark_timer = duration
	queue_redraw()

func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if ability_timer > 0.0:
		ability_timer -= delta
	if hook_cooldown_timer > 0.0:
		hook_cooldown_timer -= delta
	if rage_buff_timer > 0.0:
		rage_buff_timer -= delta

	if not is_instance_valid(base_node):
		base_node = get_tree().get_first_node_in_group("base") as Node2D
		if not base_node:
			velocity = Vector2.ZERO
			return

	if knockback_velocity.length() > 10.0:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1500.0 * delta)
		velocity = knockback_velocity
		move_and_slide()
		return

	# Plant feet during hook windup or jump
	if is_jumping_or_lunging or is_hook_winding_up:
		velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
		move_and_slide()
		return

	mob_rule_scan_timer += delta
	if mob_rule_scan_timer >= MOB_RULE_SCAN_INTERVAL:
		mob_rule_scan_timer = 0.0
		_evaluate_mob_rule_and_berserk()

	aggro_scan_timer += delta
	if aggro_scan_timer >= 0.20:
		aggro_scan_timer = randf_range(-0.05, 0.05)
		_evaluate_dynamic_aggro()

	var main_node = get_tree().get_first_node_in_group("main")
	var waaagh_speed_mult = 1.0
	if main_node and main_node.has_method("get_waaagh_speed_multiplier"):
		waaagh_speed_mult = main_node.get_waaagh_speed_multiplier()
	
	var speed_multiplier = 1.0
	if is_berserk:
		speed_multiplier = 1.45
	elif rage_buff_timer > 0.0:
		speed_multiplier = 1.35
	elif is_mob_rule_active:
		speed_multiplier = 1.15

	var current_speed = speed * speed_multiplier * waaagh_speed_mult

	if is_objective_guard:
		_process_guard_behavior(delta, current_speed)
		return

	_process_enemy_special_abilities(delta)

	var immediate_target = _find_nearest_attackable_target(attack_range)
	if is_instance_valid(immediate_target) and type != EnemyType.GRETCHIN:
		velocity = Vector2.ZERO
		perform_attack(immediate_target)
		return

	if type == EnemyType.STORMBOY and ability_timer <= 0.0:
		if is_instance_valid(current_aggro_target):
			var dist_to_aggro = global_position.distance_to(current_aggro_target.global_position)
			if dist_to_aggro >= 90.0 and dist_to_aggro <= 240.0:
				var jump_dir = (current_aggro_target.global_position - global_position).normalized()
				_execute_stormboy_jump(jump_dir)
				return
		else:
			var nearby_barricade = _find_nearest_building_in_range(80.0)
			if is_instance_valid(nearby_barricade):
				var to_base = (base_node.global_position - global_position).normalized()
				_execute_stormboy_jump(to_base)
				return

	if type == EnemyType.WARBOSS and ability_timer <= 0.0:
		var nearby_players = _find_nearest_friendly_in_range(160.0)
		if is_instance_valid(nearby_players):
			_execute_warboss_ground_slam()
			return

	repath_timer += delta
	if repath_timer >= 0.4:
		repath_timer = randf_range(-0.05, 0.05)
		if not is_objective_guard:
			_update_nav_target()

	if type == EnemyType.GRETCHIN:
		var target_vel = _process_organic_gretchin_steering(delta, current_speed)
		velocity = velocity.lerp(target_vel, 7.5 * delta)
	else:
		var move_dir = Vector2.ZERO
		if is_instance_valid(current_aggro_target):
			var dist = global_position.distance_to(current_aggro_target.global_position)
			if dist <= attack_range:
				velocity = Vector2.ZERO
				perform_attack(current_aggro_target)
				return
			else:
				if nav_agent and not nav_agent.is_navigation_finished():
					var next_path = nav_agent.get_next_path_position()
					move_dir = global_position.direction_to(next_path)
				else:
					move_dir = global_position.direction_to(current_aggro_target.global_position)
		elif nav_agent and not nav_agent.is_navigation_finished():
			var next_path = nav_agent.get_next_path_position()
			move_dir = global_position.direction_to(next_path)
			if global_position.distance_to(next_path) < 12.0:
				move_dir = global_position.direction_to(base_node.global_position if is_instance_valid(base_node) else global_position)
		else:
			var blocking_wall = _find_nearest_building_in_range(110.0)
			if is_instance_valid(blocking_wall):
				move_dir = global_position.direction_to(blocking_wall.global_position)
				if global_position.distance_to(blocking_wall.global_position) <= attack_range:
					velocity = Vector2.ZERO
					perform_attack(blocking_wall)
					return
			else:
				move_dir = global_position.direction_to(base_node.global_position if is_instance_valid(base_node) else global_position)

		var lateral_offset = move_dir.orthogonal() * sin(Time.get_ticks_msec() * 0.003 + lateral_fanning_seed) * 0.18
		move_dir = (move_dir + lateral_offset).normalized()
		velocity = velocity.lerp(move_dir * current_speed, 9.0 * delta)

	if move_and_slide():
		for i in range(get_slide_collision_count()):
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			if is_instance_valid(collider):
				if collider.has_method("take_damage") and not collider.is_in_group("enemies") and not collider.is_in_group("world_obstacles"):
					velocity = Vector2.ZERO
					perform_attack(collider)
					return
				else:
					var slide_dir = velocity.slide(collision.get_normal()).normalized()
					velocity = slide_dir * current_speed

	stuck_check_timer += delta
	if stuck_check_timer >= 1.0:
		stuck_check_timer = 0.0
		if is_instance_valid(base_node) and not is_objective_guard:
			if global_position.distance_to(last_stuck_pos) < 16.0 and not is_jumping_or_lunging and attack_cooldown_timer <= 0.0:
				_update_nav_target()
				var to_base = (base_node.global_position - global_position).normalized()
				var side = to_base.orthogonal() * (36.0 if (get_instance_id() % 2 == 0) else -36.0)
				global_position += (to_base * 8.0) + side
		last_stuck_pos = global_position

# ==============================================================================
# DYNAMIC AGGRO & TARGET SELECTION MATRIX
# ==============================================================================
func _evaluate_dynamic_aggro() -> void:
	if is_instance_valid(current_aggro_target):
		var target_dead = current_aggro_target.get("is_dead") == true
		var dist = global_position.distance_to(current_aggro_target.global_position)
		if target_dead or dist > deaggro_range:
			current_aggro_target = null
			_update_nav_target()
		else:
			return

	var candidates: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and not p.get("is_dead"):
			candidates.append({"node": p, "weight": _calculate_target_priority(p)})

	for bg in get_tree().get_nodes_in_group("bodyguards"):
		if is_instance_valid(bg):
			candidates.append({"node": bg, "weight": _calculate_target_priority(bg)})

	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.get("is_preview"):
			var b_type = int(b.get("building_type")) if "building_type" in b else 0
			if b_type in [1, 2]:
				candidates.append({"node": b, "weight": _calculate_target_priority(b)})

	var best_target: Node2D = null
	var highest_weight: float = 0.0

	for c in candidates:
		if c.weight > highest_weight:
			highest_weight = c.weight
			best_target = c.node

	if is_instance_valid(best_target) and highest_weight > 10.0:
		current_aggro_target = best_target
		if nav_agent:
			nav_agent.target_position = best_target.global_position

func _calculate_target_priority(target: Node2D) -> float:
	var dist = global_position.distance_to(target.global_position)
	if dist > aggro_detection_range:
		return 0.0

	var proximity_score = (aggro_detection_range - dist) * 1.5
	var bonus = 0.0

	if type == EnemyType.SQUIG and (target.is_in_group("players") or target.is_in_group("bodyguards")):
		bonus += 180.0
	if type == EnemyType.STORMBOY and target.is_in_group("players"):
		bonus += 160.0
	if type in [EnemyType.NOB, EnemyType.WARBOSS]:
		if target.is_in_group("players"):
			bonus += 180.0
		elif target.is_in_group("buildings") and int(target.get("building_type")) == 2:
			bonus += 120.0
	if type == EnemyType.ORK_BOY:
		if target.is_in_group("players"):
			bonus += 100.0

	return proximity_score + bonus

func _evaluate_mob_rule_and_berserk():
	var nearby_allies = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e != self and global_position.distance_to(e.global_position) <= 120.0:
			nearby_allies += 1
			if nearby_allies >= 4:
				break

	is_mob_rule_active = (nearby_allies >= 4)

	if type in [EnemyType.NOB, EnemyType.WARBOSS]:
		var was_berserk = is_berserk
		is_berserk = (float(current_health) / float(max_health)) <= 0.28
		if is_berserk and not was_berserk:
			rpc("trigger_nob_berserk_fx")

func _process_organic_gretchin_steering(delta: float, base_speed: float) -> Vector2:
	gretchin_threat_scan_timer += delta
	var close_threat = current_aggro_target

	if gretchin_threat_scan_timer >= 0.15:
		gretchin_threat_scan_timer = 0.0
		close_threat = _find_nearest_friendly_in_range(90.0)

	if gretchin_panic_timer > 0.0:
		gretchin_panic_timer -= delta

	if is_instance_valid(close_threat):
		var dist = global_position.distance_to(close_threat.global_position)
		if dist <= 75.0:
			gretchin_panic_timer = 0.35

		if gretchin_panic_timer > 0.0:
			var dir_away = (global_position - close_threat.global_position).normalized()
			var wobble = sin(Time.get_ticks_msec() * 0.015 + lateral_fanning_seed) * 0.4
			var panic_dir = (dir_away + dir_away.orthogonal() * wobble).normalized()
			if visual_sprite: visual_sprite.rotation = sin(Time.get_ticks_msec() * 0.025) * 0.2
			return panic_dir * (base_speed * 1.15)

	if _process_gretchin_thievery() and is_instance_valid(targeted_scrap_item):
		return global_position.direction_to(targeted_scrap_item.global_position) * base_speed

	if is_instance_valid(current_aggro_target):
		var d = global_position.distance_to(current_aggro_target.global_position)
		if d > attack_range:
			return global_position.direction_to(current_aggro_target.global_position) * base_speed
		elif d < 100.0:
			return -global_position.direction_to(current_aggro_target.global_position) * (base_speed * 0.8)
		else:
			return Vector2.ZERO

	var dist_to_base = global_position.distance_to(base_node.global_position)
	if dist_to_base > 160.0:
		if nav_agent and not nav_agent.is_navigation_finished():
			var next_path = nav_agent.get_next_path_position()
			return global_position.direction_to(next_path) * base_speed
		else:
			return global_position.direction_to(base_node.global_position) * base_speed

	var blocking_target = _find_nearest_attackable_target(attack_range)
	if is_instance_valid(blocking_target):
		velocity = Vector2.ZERO
		perform_attack(blocking_target)
		return Vector2.ZERO

	return global_position.direction_to(base_node.global_position) * (base_speed * 0.5)

func _process_gretchin_thievery() -> bool:
	if has_stolen_scrap: return false
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.get("current_wave") and main_node.current_wave <= 2:
		return false
	
	if not is_instance_valid(targeted_scrap_item):
		targeted_scrap_item = null
		var min_d = 140.0
		for s in get_tree().get_nodes_in_group("scrap"):
			if is_instance_valid(s):
				var d = global_position.distance_to(s.global_position)
				if d < min_d:
					min_d = d
					targeted_scrap_item = s

	if is_instance_valid(targeted_scrap_item):
		if global_position.distance_to(targeted_scrap_item.global_position) <= 24.0:
			has_stolen_scrap = true
			targeted_scrap_item.queue_free()
			targeted_scrap_item = null
			rpc("trigger_scrap_stolen_fx")
			return false
		return true

	return false

@rpc("call_local", "unreliable")
func trigger_nob_berserk_fx():
	AudioManager.play_sfx("orbital_strike", global_position, 1.0, 1.5)
	if visual_sprite: visual_sprite.modulate = Color(2.8, 0.3, 0.3)

@rpc("call_local", "unreliable")
func trigger_scrap_stolen_fx():
	var label = Label.new()
	label.text = "🏃 ⚙ STOLEN!"
	label.global_position = global_position + Vector2(-30, -32)
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(1.0, 0.85, 0.2)
	label.label_settings.font_size = 12
	get_parent().add_child(label)
	
	var tween = label.create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(label.queue_free)

func _process_enemy_special_abilities(_delta: float):
	match type:
		EnemyType.GRETCHIN:
			if attack_cooldown_timer <= 0.0 and not has_stolen_scrap:
				var target = current_aggro_target if is_instance_valid(current_aggro_target) else _find_nearest_attackable_target(220.0)
				if is_instance_valid(target):
					_shoot_gretchin_slug(target.global_position)

		EnemyType.SQUIG:
			if attack_cooldown_timer <= 0.0 and ability_timer <= 0.0:
				var target = current_aggro_target if is_instance_valid(current_aggro_target) else _find_nearest_attackable_target(145.0)
				if is_instance_valid(target):
					_execute_squig_pounce(target)

		EnemyType.ORK_BOY:
			if ability_timer <= 0.0:
				var target = current_aggro_target if is_instance_valid(current_aggro_target) else _find_nearest_attackable_target(170.0)
				if is_instance_valid(target) and global_position.distance_to(target.global_position) >= 65.0:
					_lob_stikkbomb(target.global_position)

		EnemyType.NOB, EnemyType.WARBOSS:
			# Ability 1: Warcry Buff
			if ability_timer <= 0.0:
				_execute_nob_warcry()
			
			# Ability 2: 'Eavy Snagga Harpoon Hook (Scans for any player/bodyguard in 80px-380px range)
			if hook_cooldown_timer <= 0.0 and not is_hook_winding_up:
				var hook_target = _find_best_hook_target(380.0)
				if is_instance_valid(hook_target):
					_execute_nob_harpoon_hook(hook_target)

func _find_best_hook_target(max_range: float) -> Node2D:
	var candidates: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and not bool(p.get("is_dead")):
			var d = global_position.distance_to(p.global_position)
			if d >= 75.0 and d <= max_range:
				candidates.append(p)

	for bg in get_tree().get_nodes_in_group("bodyguards"):
		if is_instance_valid(bg):
			var d = global_position.distance_to(bg.global_position)
			if d >= 75.0 and d <= max_range:
				candidates.append(bg)

	if candidates.is_empty(): return null
	candidates.sort_custom(func(a, b): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	return candidates[0]

func _shoot_gretchin_slug(target_pos: Vector2):
	attack_cooldown_timer = 2.4
	rpc("trigger_attack_charge")
	
	var main_node = get_parent()
	if main_node and "spawner" in main_node and main_node.spawner:
		var dir = (target_pos - global_position).normalized()
		main_node.spawner.spawn({
			"type": "bullet",
			"name": "ScrapSlug_" + str(randi()),
			"position": global_position + (dir * 28.0),
			"direction": dir,
			"damage": 6,
			"bullet_type": 5,
			"is_enemy_bullet": true
		})

func _execute_squig_pounce(target: Node2D):
	is_jumping_or_lunging = true
	attack_cooldown_timer = 1.2
	ability_timer = 3.2
	rpc("trigger_attack_charge")

	var leap_dir = (target.global_position - global_position).normalized()
	var leap_target = global_position + (leap_dir * 70.0)

	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e != self and e.get("type") == EnemyType.SQUIG:
			if global_position.distance_to(e.global_position) <= 100.0:
				e.set("rage_buff_timer", 2.5)

	var tween = create_tween()
	tween.tween_property(self, "global_position", leap_target, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func():
		is_jumping_or_lunging = false
		if is_instance_valid(target) and global_position.distance_to(target.global_position) <= 50.0:
			if target.has_method("take_damage"):
				target.take_damage(damage)
				_apply_slow_to_target(target, 0.35, 2.0)
	)

# ==============================================================================
# ACCURATE NOB & WARBOSS 'EAVY SNAGGA HARPOON HOOK
# ==============================================================================
func _execute_nob_harpoon_hook(target: Node2D) -> void:
	hook_cooldown_timer = 9.0 if type == EnemyType.NOB else 7.0
	is_hook_winding_up = true
	
	velocity = Vector2.ZERO
	current_aggro_target = target

	rpc("trigger_harpoon_hook_fx", global_position, target.name)

@rpc("call_local", "unreliable")
func trigger_harpoon_hook_fx(start_pos: Vector2, target_name: String):
	var target_node = null
	for p in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("bodyguards"):
		if is_instance_valid(p) and p.name == target_name:
			target_node = p
			break

	var hook_fx = HarpoonTelegraphFX.new()
	hook_fx.source_enemy = self
	hook_fx.start_pos = start_pos
	hook_fx.target_node = target_node
	get_parent().add_child(hook_fx)

class HarpoonTelegraphFX extends Node2D:
	var source_enemy: Node2D = null
	var target_node: Node2D = null
	var start_pos: Vector2 = Vector2.ZERO
	var current_aim_pos: Vector2 = Vector2.ZERO
	var locked_aim_pos: Vector2 = Vector2.ZERO
	
	var duration: float = 0.65
	var elapsed: float = 0.0
	var is_locked: bool = false
	var has_launched: bool = false
	var chain_progress: float = 0.0
	var max_range: float = 380.0

	func _ready() -> void:
		z_index = 85
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat
		AudioManager.play_sfx("volkite_beam", start_pos, -2.0, 1.8)

	func _process(delta: float) -> void:
		elapsed += delta

		if is_instance_valid(source_enemy):
			start_pos = source_enemy.global_position

		if elapsed < (duration - 0.15):
			if is_instance_valid(target_node):
				var target_vel = target_node.velocity if "velocity" in target_node else Vector2.ZERO
				current_aim_pos = target_node.global_position + (target_vel * 0.18)
			elif current_aim_pos == Vector2.ZERO:
				current_aim_pos = start_pos + Vector2.RIGHT * 200.0
		elif not is_locked:
			is_locked = true
			locked_aim_pos = current_aim_pos

		if elapsed >= duration and not has_launched:
			has_launched = true
			if is_instance_valid(source_enemy):
				source_enemy.set("is_hook_winding_up", false)
			_execute_harpoon_strike()

		if has_launched:
			chain_progress = minf(1.0, chain_progress + delta * 6.5)

		queue_redraw()
		if elapsed >= duration + 0.40:
			if is_instance_valid(source_enemy):
				source_enemy.set("is_hook_winding_up", false)
			queue_free()

	func _execute_harpoon_strike() -> void:
		AudioManager.play_sfx("axe_swing", start_pos, 2.0, 0.75)
		
		# Only the server/host applies damage and physics displacement
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			return

		var space = get_world_2d().direct_space_state
		if not space: return

		var aim_target = locked_aim_pos if is_locked else current_aim_pos
		var dir = (aim_target - start_pos).normalized()
		var strike_end = start_pos + (dir * max_range)

		var shape = CircleShape2D.new()
		shape.radius = 18.0
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.collide_with_bodies = true
		query.collide_with_areas = false

		var best_hit_body: Node2D = null
		var min_hit_dist = 9999.0

		var sample_steps = 14
		for i in range(1, sample_steps + 1):
			var sample_pt = start_pos.lerp(strike_end, float(i) / float(sample_steps))
			query.transform = Transform2D(0.0, sample_pt)
			var results = space.intersect_shape(query, 8)
			for hit in results:
				var body = hit.collider
				if is_instance_valid(body) and (body.is_in_group("players") or body.is_in_group("bodyguards")):
					if not bool(body.get("is_dead")):
						var d = start_pos.distance_to(body.global_position)
						if d < min_hit_dist:
							min_hit_dist = d
							best_hit_body = body
			if best_hit_body != null:
				break

		if is_instance_valid(best_hit_body):
			if best_hit_body.has_method("take_damage"):
				best_hit_body.take_damage(22)

			var pull_target = start_pos + (dir * 42.0)
			var pull_tween = best_hit_body.create_tween()
			pull_tween.tween_property(best_hit_body, "global_position", pull_target, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			if best_hit_body.has_method("apply_slow"):
				best_hit_body.apply_slow(0.40, 2.0)
			elif "movement_speed" in best_hit_body:
				var orig_spd = best_hit_body.movement_speed
				best_hit_body.movement_speed *= 0.60
				get_tree().create_timer(2.0).timeout.connect(func():
					if is_instance_valid(best_hit_body) and "movement_speed" in best_hit_body:
						best_hit_body.movement_speed = orig_spd
				)

			if is_instance_valid(source_enemy):
				source_enemy.set("attack_cooldown_timer", 0.05)

			var label = Label.new()
			label.script = load("res://DamageNumber.gd")
			label.global_position = best_hit_body.global_position + Vector2(-35, -35)
			get_parent().add_child(label)
			label.text = "⛓️ HOOKED!"
			label.label_settings = LabelSettings.new()
			label.label_settings.font_color = Color(1.0, 0.25, 0.15)
			label.label_settings.font_size = 14

	func _draw() -> void:
		var aim_target = locked_aim_pos if is_locked else current_aim_pos
		var dir = (aim_target - start_pos).normalized()
		var strike_end = start_pos + (dir * max_range)

		if elapsed < duration:
			var t = elapsed / duration
			var pulse = 0.65 + sin(elapsed * 28.0) * 0.35
			var warn_col = Color(1.0, 0.2, 0.1, 0.9 * pulse)

			draw_line(start_pos, strike_end, Color(1.0, 0.2, 0.1, 0.25), 5.0)
			draw_line(start_pos, strike_end, warn_col, 1.8)

			draw_circle(aim_target, 14.0 * (1.0 - t * 0.5), Color(1.0, 0.2, 0.1, 0.25))
			draw_arc(aim_target, 12.0, 0, TAU, 16, warn_col, 1.8)
			draw_line(aim_target + Vector2(-16, 0), aim_target + Vector2(16, 0), warn_col, 1.4)
			draw_line(aim_target + Vector2(0, -16), aim_target + Vector2(0, 16), warn_col, 1.4)
		else:
			var spear_pos = start_pos.lerp(strike_end, chain_progress)
			draw_line(start_pos, spear_pos, Color(0.35, 0.30, 0.28), 4.5)
			draw_line(start_pos, spear_pos, Color(0.85, 0.80, 0.75), 1.6)

			draw_set_transform(spear_pos, dir.angle(), Vector2.ONE)
			var harpoon_head = PackedVector2Array([
				Vector2(16, 0), Vector2(-6, -9), Vector2(0, -3),
				Vector2(-8, 0), Vector2(0, 3), Vector2(-6, 9)
			])
			draw_colored_polygon(harpoon_head, Color(0.90, 0.3, 0.2))
			draw_polyline(harpoon_head, Color.WHITE, 1.4)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _apply_slow_to_target(target: Node2D, slow_pct: float, duration: float):
	if target.is_in_group("players") or target.is_in_group("bodyguards"):
		if target.has_method("apply_slow"):
			target.apply_slow(slow_pct, duration)
		elif "movement_speed" in target:
			var original = target.movement_speed
			target.movement_speed *= (1.0 - slow_pct)
			get_tree().create_timer(duration).timeout.connect(func():
				if is_instance_valid(target) and "movement_speed" in target:
					target.movement_speed = original
			)

func _lob_stikkbomb(target_pos: Vector2):
	ability_timer = 11.0
	rpc("trigger_stikkbomb_fx", global_position, target_pos)

@rpc("call_local", "unreliable")
func trigger_stikkbomb_fx(start_pos: Vector2, target_pos: Vector2):
	var bomb_fx = StikkbombTelegraphFX.new()
	bomb_fx.start_pos = start_pos
	bomb_fx.target_pos = target_pos
	bomb_fx.duration = 1.4
	get_parent().add_child(bomb_fx)

class StikkbombTelegraphFX extends Node2D:
	var start_pos: Vector2 = Vector2.ZERO
	var target_pos: Vector2 = Vector2.ZERO
	var duration: float = 1.4
	var elapsed: float = 0.0
	var arc_height: float = 85.0
	var blast_radius: float = 52.0
	var has_detonated: bool = false

	func _ready() -> void:
		z_index = 85
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat

	func _process(delta: float) -> void:
		elapsed += delta
		if elapsed >= duration and not has_detonated:
			has_detonated = true
			_detonate_blast()

		queue_redraw()
		if elapsed >= duration + 0.35:
			queue_free()

	func _detonate_blast() -> void:
		AudioManager.play_sfx("orbital_strike", target_pos, -4.0, 1.7)
		get_tree().call_group("players", "add_camera_trauma", 0.30)

		# Only the server/host applies damage and knockbacks
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			return

		var space = get_world_2d().direct_space_state
		if not space: return

		var shape = CircleShape2D.new()
		shape.radius = blast_radius
		var q = PhysicsShapeQueryParameters2D.new()
		q.shape = shape
		q.transform = Transform2D(0.0, target_pos)
		q.collide_with_bodies = true
		var results = space.intersect_shape(q, 16)
		for hit in results:
			var body = hit.collider
			if is_instance_valid(body) and not body.is_in_group("enemies") and not body.is_in_group("world_obstacles"):
				if body.has_method("take_damage"):
					var dir = (body.global_position - target_pos).normalized()
					body.take_damage(20, dir * 150.0)

	func _draw() -> void:
		var t = clampf(elapsed / duration, 0.0, 1.0)
		var pulse = 0.6 + sin(elapsed * 14.0) * 0.4
		var warning_color = Color(1.0, 0.25, 0.15, 0.85 * pulse)
		var fill_color = Color(1.0, 0.15, 0.10, 0.14 * (1.0 - t))

		if elapsed <= duration:
			draw_circle(target_pos, blast_radius, fill_color)
			draw_arc(target_pos, blast_radius, 0.0, TAU, 32, warning_color, 1.8)
			var fuse_radius = blast_radius * (1.0 - t)
			draw_arc(target_pos, fuse_radius, 0.0, TAU, 24, Color(1.0, 0.85, 0.20, 0.85), 1.4)

			var ground_pos = start_pos.lerp(target_pos, t)
			var height = sin(t * PI) * arc_height
			var bomb_pos = ground_pos + Vector2(0.0, -height)

			var shadow_scale = clampf(1.0 - (height / arc_height) * 0.5, 0.4, 1.0)
			draw_set_transform(ground_pos, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, 5.0 * shadow_scale, Color(0.02, 0.02, 0.05, 0.45 * shadow_scale))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

			var spin_angle = elapsed * 8.0
			draw_set_transform(bomb_pos, spin_angle, Vector2.ONE)
			draw_line(Vector2(0, 0), Vector2(0, 8), Color("#4a3219"), 2.5)
			draw_rect(Rect2(-3, -6, 6, 6), Color("#32373b"))
			draw_circle(Vector2(0, -7), 2.0, Color(1.0, 0.85, 0.2))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		if elapsed > duration:
			var exp_t = (elapsed - duration) / 0.35
			var exp_r = blast_radius * (0.8 + exp_t * 0.4)
			var exp_alpha = 1.0 - exp_t
			draw_circle(target_pos, exp_r, Color(1.0, 0.45, 0.1, 0.6 * exp_alpha))
			draw_circle(target_pos, exp_r * 0.6, Color(1.0, 0.90, 0.3, 0.8 * exp_alpha))
			draw_circle(target_pos, exp_r * 0.25, Color.WHITE)

func _execute_nob_warcry():
	ability_timer = 9.0
	rpc("trigger_warcry_fx")
	
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= 280.0:
			e.set("rage_buff_timer", 5.0)
			if is_instance_valid(current_aggro_target) and e.get("current_aggro_target") == null:
				e.set("current_aggro_target", current_aggro_target)

func _execute_warboss_ground_slam():
	ability_timer = 6.5
	rpc("trigger_warboss_slam_fx", global_position)
	
	AudioManager.play_sfx("orbital_strike", global_position, 3.0, 0.6)
	get_tree().call_group("players", "add_camera_trauma", 0.50)

	for target in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("bodyguards"):
		if is_instance_valid(target) and global_position.distance_to(target.global_position) <= 180.0:
			if target.has_method("take_damage"):
				var knock_dir = (target.global_position - global_position).normalized()
				target.take_damage(35, knock_dir * 280.0)
				_apply_slow_to_target(target, 0.45, 2.5)

@rpc("call_local", "unreliable")
func trigger_warboss_slam_fx(slam_pos: Vector2):
	var slam = WarbossQuakeFX.new()
	slam.global_position = slam_pos
	get_parent().add_child(slam)

class WarbossQuakeFX extends Node2D:
	var timer: float = 0.4
	func _ready():
		z_index = 84
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat
	func _process(delta):
		timer -= delta
		queue_redraw()
		if timer <= 0.0: queue_free()
	func _draw():
		var t = 1.0 - (timer / 0.4)
		var r = t * 180.0
		var alpha = (1.0 - t)
		draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(1.0, 0.25, 0.15, alpha * 0.9), 4.0)
		draw_arc(Vector2.ZERO, r * 0.6, 0, TAU, 24, Color(1.0, 0.85, 0.2, alpha * 0.8), 2.5)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

@rpc("call_local", "unreliable")
func trigger_warcry_fx():
	AudioManager.play_sfx("axe_swing", global_position, 2.0, 0.5)
	if visual_sprite:
		var tween = create_tween()
		visual_sprite.modulate = Color(2.5, 0.4, 0.4)
		tween.tween_property(visual_sprite, "modulate", Color.WHITE, 0.8)

func _execute_stormboy_jump(dir: Vector2):
	is_jumping_or_lunging = true
	ability_timer = 5.5
	rpc("trigger_jump_fx")

	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", true)

	var jump_target = global_position + (dir * 180.0)
	var tween = create_tween()
	tween.tween_property(self, "global_position", jump_target, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func():
		is_jumping_or_lunging = false
		if is_instance_valid(collision_shape):
			collision_shape.set_deferred("disabled", false)
	)

@rpc("call_local", "unreliable")
func trigger_jump_fx():
	if visual_sprite:
		var tween = create_tween()
		tween.tween_property(visual_sprite, "position:y", -40.0, 0.27).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(visual_sprite, "position:y", 0.0, 0.27).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _process_guard_behavior(_delta: float, current_speed: float):
	aggro_scan_timer += _delta
	if aggro_scan_timer >= 0.15:
		aggro_scan_timer = 0.0
		current_aggro_target = _find_nearest_friendly_in_range(280.0)

	if is_instance_valid(current_aggro_target):
		var dist = global_position.distance_to(current_aggro_target.global_position)
		if dist <= attack_range:
			velocity = Vector2.ZERO
			perform_attack(current_aggro_target)
		else:
			velocity = global_position.direction_to(current_aggro_target.global_position) * current_speed
		move_and_slide()
		return

	var wander_radius = 90.0 + (float(get_instance_id() % 6) * 16.0)
	var patrol_angle = (Time.get_ticks_msec() * 0.0007) + (float(get_instance_id()) * 1.2)
	var patrol_target = guard_anchor + Vector2.RIGHT.rotated(patrol_angle) * wander_radius
	var dist_to_patrol = global_position.distance_to(patrol_target)
	
	if dist_to_patrol > 15.0:
		velocity = global_position.direction_to(patrol_target) * (current_speed * 0.55)
	else:
		velocity = Vector2.ZERO
		
	move_and_slide()

func _find_nearest_building_in_range(range_limit: float) -> Node2D:
	var buildings = get_tree().get_nodes_in_group("buildings")
	var nearest: Node2D = null
	var min_d = range_limit
	for b in buildings:
		if is_instance_valid(b) and not b.get("is_preview"):
			var d = global_position.distance_to(b.global_position)
			if d < min_d:
				min_d = d
				nearest = b
	return nearest

func _find_nearest_attackable_target(range_limit: float) -> Node2D:
	var candidates: Array = get_tree().get_nodes_in_group("players")
	candidates.append_array(get_tree().get_nodes_in_group("buildings"))
	candidates.append_array(get_tree().get_nodes_in_group("bodyguards"))
	if is_instance_valid(base_node):
		candidates.append(base_node)

	var nearest: Node2D = null
	var min_d = range_limit
	for c in candidates:
		if is_instance_valid(c):
			if c.is_in_group("players") and c.get("is_dead"): continue
			if c.is_in_group("buildings") and c.get("is_preview"): continue
			var d = global_position.distance_to(c.global_position)
			if d < min_d:
				min_d = d
				nearest = c
	return nearest

func _find_nearest_friendly_in_range(range_limit: float) -> Node2D:
	var candidates: Array = get_tree().get_nodes_in_group("players")
	candidates.append_array(get_tree().get_nodes_in_group("bodyguards"))
	var nearest: Node2D = null
	var min_d = range_limit
	for c in candidates:
		if is_instance_valid(c):
			if c.is_in_group("players") and c.get("is_dead"): continue
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
	
	var main_node = get_tree().get_first_node_in_group("main")
	var waaagh_dmg_mult = 1.0
	if main_node and main_node.has_method("get_waaagh_damage_multiplier"):
		waaagh_dmg_mult = main_node.get_waaagh_damage_multiplier()
		
	var berserk_mult = 1.5 if is_berserk else 1.0
	var final_dmg = int(damage * berserk_mult * waaagh_dmg_mult)

	if target.has_method("take_damage"):
		var knockback = (target.global_position - global_position).normalized() * (220.0 if type == EnemyType.WARBOSS else 120.0)
		target.take_damage(final_dmg, knockback)

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
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		if knockback_impulse != Vector2.ZERO:
			var knockback_mod = 1.0
			match type:
				EnemyType.GRETCHIN: knockback_mod = 1.2
				EnemyType.SQUIG: knockback_mod = 1.0
				EnemyType.ORK_BOY: knockback_mod = 0.4
				EnemyType.STORMBOY: knockback_mod = 0.7
				EnemyType.NOB: knockback_mod = 0.0 if is_berserk else 0.12
				EnemyType.WARBOSS: knockback_mod = 0.02
			
			if is_mob_rule_active:
				knockback_mod *= 0.35
				
			knockback_velocity = knockback_impulse * knockback_mod

		if not is_instance_valid(current_aggro_target):
			var nearest_player = _find_nearest_friendly_in_range(420.0)
			if is_instance_valid(nearest_player):
				current_aggro_target = nearest_player
				if nav_agent:
					nav_agent.target_position = nearest_player.global_position

		var new_health = max(0, current_health - amount)
		rpc("sync_health", new_health)
		rpc("trigger_hit_flash")
		rpc("spawn_damage_number", amount, global_position + Vector2(randf_range(-10, 10), randf_range(-10, 5)))

@rpc("call_local", "unreliable")
func spawn_damage_number(amount: int, spawn_pos: Vector2) -> void:
	var dmg_label = Label.new()
	dmg_label.script = load("res://DamageNumber.gd")
	dmg_label.global_position = spawn_pos
	get_parent().add_child(dmg_label)
	dmg_label.setup(amount, amount >= 35)

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
	if current_health <= 0 and (multiplayer.is_server() or not multiplayer.has_multiplayer_peer()) and not is_queued_for_deletion():
		call_deferred("_handle_death")

func _handle_death() -> void:
	if NavigationServer2D.map_changed.is_connected(_on_nav_map_changed):
		NavigationServer2D.map_changed.disconnect(_on_nav_map_changed)

	var main_node = get_parent()
	if main_node and "spawner" in main_node and main_node.spawner:
		var scrap_value = 6
		match type:
			EnemyType.GRETCHIN: scrap_value = 6
			EnemyType.SQUIG: scrap_value = 8
			EnemyType.ORK_BOY: scrap_value = 14
			EnemyType.STORMBOY: scrap_value = 12
			EnemyType.NOB: scrap_value = 30
			EnemyType.WARBOSS: scrap_value = 150

		if has_stolen_scrap: scrap_value += 6

		main_node.spawner.spawn({
			"type": "scrap",
			"name": "Scrap_" + str(randi()),
			"position": global_position,
			"value": scrap_value
		})

		var near_marshal = false
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p.get("current_class") == 1:
				if global_position.distance_to(p.global_position) <= 300.0:
					near_marshal = true
					break

		if has_telemetry_mark or near_marshal:
			var req_reward = 4 if type in [EnemyType.NOB, EnemyType.WARBOSS] else 1
			if main_node.has_method("add_requisition"):
				main_node.add_requisition(req_reward)
				rpc("spawn_telemetry_req_popup", req_reward, global_position + Vector2(0, -22))

		if type == EnemyType.ORK_BOY and randf() <= 0.08:
			_lob_stikkbomb(global_position + Vector2.RIGHT.rotated(randf() * TAU) * 15.0)

		if counts_toward_wave and main_node.has_method("notify_enemy_defeated"):
			main_node.notify_enemy_defeated()

		var exp_reward = 15
		match type:
			EnemyType.GRETCHIN: exp_reward = 12
			EnemyType.SQUIG: exp_reward = 18
			EnemyType.ORK_BOY: exp_reward = 28
			EnemyType.STORMBOY: exp_reward = 35
			EnemyType.NOB: exp_reward = 85
			EnemyType.WARBOSS: exp_reward = 350

		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p.get("current_class") == 2:
				p.gain_exp(exp_reward)

	queue_free()

@rpc("call_local", "unreliable")
func spawn_telemetry_req_popup(amount: int, spawn_pos: Vector2) -> void:
	var label = Label.new()
	label.script = load("res://DamageNumber.gd")
	label.global_position = spawn_pos
	get_parent().add_child(label)
	label.text = "+%d REQ ⚡" % amount
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.20, 0.88, 1.00)
	label.label_settings.font_size = 13

func update_ui() -> void:
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

func _draw() -> void:
	if has_telemetry_mark:
		var rot = Time.get_ticks_msec() * 0.004
		var pulse = 0.75 + sin(Time.get_ticks_msec() * 0.01) * 0.25
		var reticle_color = Color(0.20, 0.88, 1.0, 0.85 * pulse)
		var r = 26.0

		draw_set_transform(Vector2(0, -14), rot, Vector2.ONE)
		for i in range(4):
			var a = i * (PI / 2.0)
			var p = Vector2(cos(a), sin(a)) * r
			draw_arc(p, 6.0, a + PI * 0.75, a + PI * 1.25, 6, reticle_color, 1.8)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(-22, -42), "TARGET LOCKED", HORIZONTAL_ALIGNMENT_CENTER, 44, 7, reticle_color)
