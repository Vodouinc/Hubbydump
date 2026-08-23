extends CharacterBody2D
class_name Enemy

enum EnemyType { GRETCHIN, SQUIG, ORK_BOY, STORMBOY, NOB }

@export var type: int = 0:
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
var ability_timer: float = 0.0
var base_node: Node2D = null
var is_objective_guard: bool = false
var guard_anchor: Vector2 = Vector2.ZERO
var counts_toward_wave: bool = true
var stuck_check_timer: float = 0.0
var last_stuck_pos: Vector2 = Vector2.ZERO

var aggro_scan_timer: float = 0.0
var mob_rule_scan_timer: float = 0.0
const MOB_RULE_SCAN_INTERVAL: float = 0.3
var cached_target_friendly: Node2D = null
var is_jumping_or_lunging: bool = false
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
	if not is_instance_valid(base_node):
		base_node = get_tree().get_first_node_in_group("base") as Node2D
		
	if is_instance_valid(base_node) and nav_agent:
		var surround_angle = float(get_instance_id() % 16) * (TAU / 16.0)
		var surround_offset = Vector2.RIGHT.rotated(surround_angle) * 75.0
		nav_agent.target_position = base_node.global_position + surround_offset

func apply_type_stats() -> void:
	match type:
		EnemyType.GRETCHIN:
			speed = 155.0
			max_health = 25
			damage = 5
			attack_range = 210.0
			if health_bar:
				health_bar.bar_size = Vector2(22.0, 3.5)
				health_bar.bar_offset = Vector2(0.0, -16.0)
		EnemyType.SQUIG:
			speed = 150.0
			max_health = 35
			damage = 7
			attack_range = 55.0
			if health_bar:
				health_bar.bar_size = Vector2(20.0, 3.0)
				health_bar.bar_offset = Vector2(0.0, -15.0)
		EnemyType.ORK_BOY:
			speed = 85.0
			max_health = 150
			damage = 25
			attack_range = 75.0
			if health_bar:
				health_bar.bar_size = Vector2(34.0, 4.5)
				health_bar.bar_offset = Vector2(0.0, -28.0)
		EnemyType.STORMBOY:
			speed = 165.0
			max_health = 80
			damage = 14
			attack_range = 75.0
			if health_bar:
				health_bar.bar_size = Vector2(30.0, 4.0)
				health_bar.bar_offset = Vector2(0.0, -26.0)
		EnemyType.NOB:
			speed = 68.0
			max_health = 420
			damage = 35
			attack_range = 85.0
			if health_bar:
				health_bar.bar_size = Vector2(42.0, 5.5)
				health_bar.bar_offset = Vector2(0.0, -34.0)

	if is_instance_valid(collision_shape) and collision_shape.shape is CircleShape2D:
		match type:
			EnemyType.GRETCHIN, EnemyType.SQUIG:
				collision_shape.shape.radius = 8.5
			EnemyType.ORK_BOY, EnemyType.STORMBOY:
				collision_shape.shape.radius = 13.0
			EnemyType.NOB:
				collision_shape.shape.radius = 18.0

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

	if is_jumping_or_lunging:
		return

	mob_rule_scan_timer += delta
	if mob_rule_scan_timer >= MOB_RULE_SCAN_INTERVAL:
		mob_rule_scan_timer = 0.0
		_evaluate_mob_rule_and_berserk()

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
		var nearby_barricade = _find_nearest_building_in_range(80.0)
		if is_instance_valid(nearby_barricade):
			var to_base = (base_node.global_position - global_position).normalized()
			_execute_stormboy_jump(to_base)
			return

	var move_dir = Vector2.ZERO
	
	if type == EnemyType.GRETCHIN and _process_gretchin_thievery() and is_instance_valid(targeted_scrap_item):
		move_dir = global_position.direction_to(targeted_scrap_item.global_position)
	else:
		var is_path_usable = nav_agent and not nav_agent.is_navigation_finished() and nav_agent.is_target_reachable()

		if is_path_usable:
			var next_path = nav_agent.get_next_path_position()
			move_dir = global_position.direction_to(next_path)
		else:
			var blocking_wall = _find_nearest_building_in_range(110.0)
			if is_instance_valid(blocking_wall):
				move_dir = global_position.direction_to(blocking_wall.global_position)
				if global_position.distance_to(blocking_wall.global_position) <= attack_range:
					velocity = Vector2.ZERO
					perform_attack(blocking_wall)
					return
			else:
				move_dir = global_position.direction_to(base_node.global_position)

		var lateral_offset = move_dir.orthogonal() * sin(Time.get_ticks_msec() * 0.003 + lateral_fanning_seed) * 0.25
		move_dir = (move_dir + lateral_offset).normalized()

	if type == EnemyType.GRETCHIN and not has_stolen_scrap:
		var close_threat = _find_nearest_friendly_in_range(90.0)
		if is_instance_valid(close_threat):
			move_dir = -global_position.direction_to(close_threat.global_position)

	velocity = move_dir * current_speed

	if move_and_slide():
		for i in range(get_slide_collision_count()):
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			if is_instance_valid(collider):
				if collider.has_method("take_damage") and not collider.is_in_group("enemies"):
					velocity = Vector2.ZERO
					perform_attack(collider)
					return
				elif collider.is_in_group("enemies") or collider.is_in_group("ork_citadel") or collider.is_in_group("ork_structures"):
					var slide_dir = move_dir.slide(collision.get_normal()).normalized()
					velocity = slide_dir * current_speed

	stuck_check_timer += delta
	if stuck_check_timer >= 2.5:
		stuck_check_timer = 0.0
		if is_instance_valid(base_node) and not is_objective_guard:
			if global_position.distance_to(last_stuck_pos) < 12.0 and not is_jumping_or_lunging and attack_cooldown_timer <= 0.0:
				var push_dir = (base_node.global_position - global_position).normalized()
				var side_nudge = push_dir.orthogonal() * (24.0 if (get_instance_id() % 2 == 0) else -24.0)
				global_position += (push_dir * 18.0) + side_nudge
		last_stuck_pos = global_position

func _evaluate_mob_rule_and_berserk():
	var nearby_allies = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e != self and global_position.distance_to(e.global_position) <= 120.0:
			nearby_allies += 1
			if nearby_allies >= 4:
				break

	is_mob_rule_active = (nearby_allies >= 4)

	if type == EnemyType.NOB:
		var was_berserk = is_berserk
		is_berserk = (float(current_health) / float(max_health)) <= 0.28
		if is_berserk and not was_berserk:
			rpc("trigger_nob_berserk_fx")

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
	if visual_sprite:
		visual_sprite.modulate = Color(2.8, 0.3, 0.3)

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
				var target = _find_nearest_attackable_target(220.0)
				if is_instance_valid(target):
					_shoot_gretchin_slug(target.global_position)

		EnemyType.SQUIG:
			if attack_cooldown_timer <= 0.0 and ability_timer <= 0.0:
				var target = _find_nearest_attackable_target(110.0)
				if is_instance_valid(target):
					_execute_squig_pounce(target)

		EnemyType.ORK_BOY:
			if ability_timer <= 0.0:
				var target = _find_nearest_attackable_target(150.0)
				if is_instance_valid(target):
					_lob_stikkbomb(target.global_position)

		EnemyType.NOB:
			if ability_timer <= 0.0:
				_execute_nob_warcry()

func _shoot_gretchin_slug(target_pos: Vector2):
	attack_cooldown_timer = 2.4
	rpc("trigger_attack_charge")
	
	var main_node = get_parent()
	if main_node and "spawner" in main_node and main_node.spawner:
		var dir = (target_pos - global_position).normalized()
		main_node.spawner.spawn({
			"type": "bullet",
			"name": "ScrapSlug_" + str(randi()),
			"position": global_position + (dir * 18.0),
			"direction": dir,
			"damage": 6,
			"is_enemy_bullet": true
		})

func _execute_squig_pounce(target: Node2D):
	is_jumping_or_lunging = true
	attack_cooldown_timer = 1.4
	ability_timer = 2.8
	rpc("trigger_attack_charge")

	var leap_dir = (target.global_position - global_position).normalized()
	var leap_target = global_position + (leap_dir * 45.0)

	var tween = create_tween()
	tween.tween_property(self, "global_position", leap_target, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func():
		is_jumping_or_lunging = false
		if is_instance_valid(target) and global_position.distance_to(target.global_position) <= 35.0:
			if target.has_method("take_damage"):
				target.take_damage(damage)
	)

# In Enemy.gd

func _lob_stikkbomb(target_pos: Vector2):
	ability_timer = 9.0
	rpc("trigger_stikkbomb_fx", global_position, target_pos)

@rpc("call_local", "unreliable")
func trigger_stikkbomb_fx(start_pos: Vector2, target_pos: Vector2):
	var bomb_fx = StikkbombTelegraphFX.new()
	bomb_fx.start_pos = start_pos
	bomb_fx.target_pos = target_pos
	bomb_fx.duration = 1.2
	get_parent().add_child(bomb_fx)

class StikkbombTelegraphFX extends Node2D:
	var start_pos: Vector2 = Vector2.ZERO
	var target_pos: Vector2 = Vector2.ZERO
	var duration: float = 1.2
	var elapsed: float = 0.0
	var arc_height: float = 85.0
	var blast_radius: float = 65.0
	var has_detonated: bool = false

	func _ready() -> void:
		z_index = 85
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat

	func _process(delta: float) -> void:
		elapsed += delta

		# Independent detonation logic (fires even if the thrower died)
		if elapsed >= duration and not has_detonated:
			has_detonated = true
			_detonate_blast()

		queue_redraw()
		if elapsed >= duration + 0.35:
			queue_free()

	func _detonate_blast() -> void:
		AudioManager.play_sfx("orbital_strike", target_pos, -2.0, 1.6)
		get_tree().call_group("players", "add_camera_trauma", 0.45)

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
			if is_instance_valid(body) and not body.is_in_group("enemies"):
				if body.has_method("take_damage"):
					var dir = (body.global_position - target_pos).normalized()
					body.take_damage(28, dir * 200.0)

	func _draw() -> void:
		var t = clampf(elapsed / duration, 0.0, 1.0)
		var pulse = 0.6 + sin(elapsed * 12.0) * 0.4
		var warning_color = Color(1.0, 0.20, 0.15, 0.75 * pulse)
		var fill_color = Color(1.0, 0.15, 0.10, 0.18 * (1.0 - t))

		if elapsed <= duration:
			draw_circle(target_pos, blast_radius, fill_color)
			draw_arc(target_pos, blast_radius, 0.0, TAU, 32, warning_color, 2.0)
			var fuse_radius = blast_radius * (1.0 - t)
			draw_arc(target_pos, fuse_radius, 0.0, TAU, 24, Color(1.0, 0.85, 0.20, 0.8), 1.5)

			var ground_pos = start_pos.lerp(target_pos, t)
			var height = sin(t * PI) * arc_height
			var bomb_pos = ground_pos + Vector2(0.0, -height)

			var shadow_scale = clampf(1.0 - (height / arc_height) * 0.5, 0.4, 1.0)
			draw_set_transform(ground_pos, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, 6.0 * shadow_scale, Color(0.02, 0.02, 0.05, 0.45 * shadow_scale))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

			var spin_angle = elapsed * 10.0
			draw_set_transform(bomb_pos, spin_angle, Vector2.ONE)
			draw_line(Vector2(0, 0), Vector2(0, 10), Color("#4a3219"), 3.0)
			draw_rect(Rect2(-4, -8, 8, 8), Color("#32373b"))
			draw_rect(Rect2(-4, -8, 8, 8), Color("#7a1f1d"), false, 1.0)
			draw_circle(Vector2(0, -9), 2.5, Color(1.0, 0.85, 0.2))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		if elapsed > duration:
			var exp_t = (elapsed - duration) / 0.35
			var exp_r = blast_radius * (0.8 + exp_t * 0.4)
			var exp_alpha = 1.0 - exp_t
			draw_circle(target_pos, exp_r, Color(1.0, 0.45, 0.1, 0.6 * exp_alpha))
			draw_circle(target_pos, exp_r * 0.6, Color(1.0, 0.90, 0.3, 0.8 * exp_alpha))
			draw_circle(target_pos, exp_r * 0.25, Color.WHITE)

func _execute_nob_warcry():
	ability_timer = 10.0
	rpc("trigger_warcry_fx")
	
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= 260.0:
			e.set("rage_buff_timer", 5.5)

@rpc("call_local", "unreliable")
func trigger_warcry_fx():
	AudioManager.play_sfx("axe_swing", global_position, 2.0, 0.5)
	if visual_sprite:
		var tween = create_tween()
		visual_sprite.modulate = Color(2.5, 0.4, 0.4)
		tween.tween_property(visual_sprite, "modulate", Color.WHITE, 0.8)

func _execute_stormboy_jump(dir: Vector2):
	is_jumping_or_lunging = true
	ability_timer = 8.0
	rpc("trigger_jump_fx")

	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", true)

	var jump_target = global_position + (dir * 150.0)
	var tween = create_tween()
	tween.tween_property(self, "global_position", jump_target, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func():
		is_jumping_or_lunging = false
		if is_instance_valid(collision_shape):
			collision_shape.set_deferred("disabled", false)
	)

@rpc("call_local", "unreliable")
func trigger_jump_fx():
	if visual_sprite:
		var tween = create_tween()
		tween.tween_property(visual_sprite, "position:y", -40.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(visual_sprite, "position:y", 0.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _process_guard_behavior(_delta: float, current_speed: float):
	aggro_scan_timer += _delta
	if aggro_scan_timer >= 0.15:
		aggro_scan_timer = 0.0
		cached_target_friendly = _find_nearest_friendly_in_range(260.0)

	if is_instance_valid(cached_target_friendly):
		var dist = global_position.distance_to(cached_target_friendly.global_position)
		if dist <= attack_range:
			velocity = Vector2.ZERO
			perform_attack(cached_target_friendly)
		else:
			velocity = global_position.direction_to(cached_target_friendly.global_position) * current_speed
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
		if is_instance_valid(b):
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
		target.take_damage(final_dmg)

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
				EnemyType.SQUIG: knockback_mod = 1.15
				EnemyType.ORK_BOY: knockback_mod = 0.4
				EnemyType.STORMBOY: knockback_mod = 0.8
				EnemyType.NOB: knockback_mod = 0.0 if is_berserk else 0.15
			
			if is_mob_rule_active:
				knockback_mod *= 0.35
				
			knockback_velocity = knockback_impulse * knockback_mod

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
		var scrap_value = 7 if has_stolen_scrap else 5
		main_node.spawner.spawn({
			"type": "scrap",
			"name": "Scrap_" + str(randi()),
			"position": global_position,
			"value": scrap_value
		})

		# --- MARSHAL TELEMETRY REQUISITION HARVEST ---
		# Check if killed with Auspex Paint OR near a Skitarii Marshal
		var near_marshal = false
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p.get("current_class") == 1:
				if global_position.distance_to(p.global_position) <= 300.0:
					near_marshal = true
					break

		if has_telemetry_mark or near_marshal:
			var req_reward = 3 if type == EnemyType.NOB else 1
			if main_node.has_method("add_requisition"):
				main_node.add_requisition(req_reward)
				rpc("spawn_telemetry_req_popup", req_reward, global_position + Vector2(0, -22))
		# ---------------------------------------------

		if type == EnemyType.ORK_BOY and randf() <= 0.25:
			_lob_stikkbomb(global_position + Vector2.RIGHT.rotated(randf() * TAU) * 20.0)

		if counts_toward_wave and main_node.has_method("notify_enemy_defeated"):
			main_node.notify_enemy_defeated()

	queue_free()

@rpc("call_local", "unreliable")
func spawn_telemetry_req_popup(amount: int, spawn_pos: Vector2) -> void:
	var label = Label.new()
	label.script = load("res://DamageNumber.gd")
	label.global_position = spawn_pos
	get_parent().add_child(label)
	label.text = "+%d REQ ⚡" % amount
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.20, 0.88, 1.00) # Glowing Cyan
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
