extends CharacterBody2D
class_name SkitariiBodyguard

const GameData = preload("res://GameData.gd")

@export var guard_role: int = 0:
	set(val):
		guard_role = val
		if is_node_ready():
			_apply_role_stats()

var player_owner: Node2D = null
var bodyguard_slot_index: int = 0

# Health & Combat Stats
@export var max_health: int = 140
var current_health: int = 140
var speed: float = 310.0
var max_acceleration: float = 1400.0
var detection_range: float = 580.0
var can_attack: bool = true
var attack_cooldown: float = 1.15
var base_attack_cooldown: float = 1.15

# Doctrina Aura State
var is_in_marshal_aura: bool = false
var aura_is_conqueror: bool = true

# RTS & Directive State
var is_anchored_bipod: bool = false
var anchor_target_pos: Vector2 = Vector2.ZERO
var is_rts_selected: bool = false
var rts_move_target: Vector2 = Vector2.ZERO
var rts_is_commanded_move: bool = false
var rts_target_enemy_node: Node2D = null

@onready var visual_sprite: Node2D = get_node_or_null("VisualSprite")
@onready var health_bar: Node2D = get_node_or_null("HealthBar")

func _ready():
	add_to_group("bodyguards")
	add_to_group("controllable_units")
	add_to_group("friendlies")

	current_health = max_health
	if is_instance_valid(health_bar) and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)

	var col = get_node_or_null("CollisionShape2D")
	if not col:
		col = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 10.0
		col.shape = shape
		add_child(col)

	collision_layer = 1
	collision_mask = 1 | 2

	_apply_role_stats()

func _apply_role_stats():
	if not visual_sprite:
		visual_sprite = get_node_or_null("VisualSprite")

	match guard_role:
		0: # Ranger Sniper (Galvanic Arquebus)
			max_health = 110
			speed = 290.0
			detection_range = 580.0
			base_attack_cooldown = 1.15
			if visual_sprite: visual_sprite.unit_type = 4 # SKITARII_RANGER
		1: # Sicarian Melee (Cyan Transonic Blades)
			max_health = 175
			speed = 410.0
			detection_range = 280.0
			base_attack_cooldown = 0.42
			if visual_sprite: visual_sprite.unit_type = 5 # SICARIAN_RUSTSTALKER
		2: # Vanguard Rad-Trooper (Radium Carbine)
			max_health = 130
			speed = 330.0
			detection_range = 380.0
			base_attack_cooldown = 0.65
			if visual_sprite: visual_sprite.unit_type = 2 # SKITARII_VANGUARD

	attack_cooldown = base_attack_cooldown
	current_health = min(current_health, max_health)
	queue_redraw()

# ==============================================================================
# RTS & DIRECTIVE INTERFACE
# ==============================================================================
func set_rts_selected(selected: bool) -> void:
	is_rts_selected = selected
	queue_redraw()

func rts_move_to(target_pos: Vector2, is_attack_move: bool = false) -> void:
	rts_move_target = target_pos
	rts_is_commanded_move = true
	rts_target_enemy_node = null
	is_anchored_bipod = false
	if is_attack_move:
		detection_range = 700.0

func rts_attack_target(target_node: Node2D) -> void:
	rts_target_enemy_node = target_node
	rts_is_commanded_move = false
	is_anchored_bipod = false

func rts_stop() -> void:
	rts_is_commanded_move = false
	rts_target_enemy_node = null
	velocity = Vector2.ZERO

func rts_hold() -> void:
	rts_is_commanded_move = false

func set_anchor_directive(pos: Vector2) -> void:
	is_anchored_bipod = true
	var angle_offset = float(bodyguard_slot_index) * (TAU / 4.0)
	anchor_target_pos = pos + Vector2.RIGHT.rotated(angle_offset) * 32.0
	if guard_role == 0:
		detection_range = 800.0
		base_attack_cooldown = 0.60
	queue_redraw()

func clear_anchor_directive() -> void:
	is_anchored_bipod = false
	_apply_role_stats()

func set_doctrina_buff(is_conq: bool, active: bool) -> void:
	is_in_marshal_aura = active
	aura_is_conqueror = is_conq
	queue_redraw()

# ==============================================================================
# PHYSICS PROCESS & FACING
# ==============================================================================
func _physics_process(delta: float):
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return

	if not is_instance_valid(player_owner):
		_resolve_player_owner()
		if not is_instance_valid(player_owner):
			return

	if "active_bodyguards" in player_owner:
		var idx = player_owner.active_bodyguards.find(self)
		if idx >= 0: bodyguard_slot_index = idx

	# Check Marshal command aura proximity (260px)
	var dist_to_owner = global_position.distance_to(player_owner.global_position)
	is_in_marshal_aura = (dist_to_owner <= 260.0)
	if is_in_marshal_aura:
		aura_is_conqueror = (player_owner.get("active_doctrina") == 0) if "active_doctrina" in player_owner else true
		attack_cooldown = base_attack_cooldown * (0.70 if aura_is_conqueror else 1.0)
	else:
		attack_cooldown = base_attack_cooldown

	# Vanguard Passive Rad-Fallout Pulse
	if guard_role == 2:
		_process_vanguard_rad_aura(delta)

	# 1. Target Selection
	var nearest_enemy: Node2D = null
	if is_instance_valid(rts_target_enemy_node):
		nearest_enemy = rts_target_enemy_node
	else:
		var painted = player_owner.get("painted_target_enemy") if "painted_target_enemy" in player_owner else null
		if is_instance_valid(painted):
			nearest_enemy = painted
		else:
			nearest_enemy = get_nearest_enemy()

	# 2. Movement & Formations
	var desired_velocity = Vector2.ZERO

	if rts_is_commanded_move:
		var dist = global_position.distance_to(rts_move_target)
		if dist > 14.0:
			desired_velocity = global_position.direction_to(rts_move_target) * speed
		else:
			rts_is_commanded_move = false
			desired_velocity = Vector2.ZERO

	elif is_anchored_bipod:
		var dist_to_anchor = global_position.distance_to(anchor_target_pos)
		if dist_to_anchor > 10.0:
			desired_velocity = global_position.direction_to(anchor_target_pos) * speed
		else:
			desired_velocity = Vector2.ZERO

	elif guard_role == 1 and is_instance_valid(nearest_enemy) and global_position.distance_to(nearest_enemy.global_position) <= 240.0:
		var dir_to_enemy = global_position.direction_to(nearest_enemy.global_position)
		desired_velocity = _process_sicarian_combat(nearest_enemy, delta)
		if global_position.distance_to(nearest_enemy.global_position) <= 44.0 and can_attack:
			_perform_melee_strike(nearest_enemy)

	else:
		# Escort formation flanking the Marshal
		var player_facing = Vector2.RIGHT
		if player_owner.get("visual_sprite") and player_owner.visual_sprite:
			player_facing = Vector2.RIGHT.rotated(player_owner.visual_sprite.aim_angle if "aim_angle" in player_owner.visual_sprite else 0.0)

		var side_dir = player_facing.orthogonal()
		var lateral_offset = 0.0
		var back_offset = 28.0

		match bodyguard_slot_index:
			0: lateral_offset = -38.0
			1: lateral_offset = 38.0
			2: lateral_offset = -70.0; back_offset = 42.0
			3: lateral_offset = 70.0; back_offset = 42.0
			4: lateral_offset = 0.0; back_offset = 54.0
			_: lateral_offset = (bodyguard_slot_index % 2 * 2 - 1) * 60.0

		var follow_target_pos = player_owner.global_position - (player_facing * back_offset) + (side_dir * lateral_offset)
		var dist_to_slot = global_position.distance_to(follow_target_pos)
		if dist_to_slot > 14.0:
			var target_spd = speed
			if dist_to_slot < 60.0:
				target_spd = speed * (dist_to_slot / 60.0)
			desired_velocity = global_position.direction_to(follow_target_pos) * target_spd

	desired_velocity += _calculate_friendly_separation() * 40.0
	velocity = velocity.move_toward(desired_velocity, max_acceleration * delta)
	move_and_slide()

	# 3. Update 4-Directional Facing & Weapons on VisualSprite
	if visual_sprite and visual_sprite.has_method("update_facing"):
		if is_instance_valid(nearest_enemy) and global_position.distance_to(nearest_enemy.global_position) <= detection_range:
			visual_sprite.update_facing(nearest_enemy.global_position)
			if guard_role == 0 and can_attack:
				_shoot_sniper_round(nearest_enemy.global_position)
			elif guard_role == 2 and can_attack:
				_shoot_rad_carbine(nearest_enemy.global_position)
		elif velocity.length_squared() > 100.0:
			visual_sprite.update_facing(global_position + velocity)

	var target_look = nearest_enemy.global_position if is_instance_valid(nearest_enemy) else (global_position + velocity)
	rpc("sync_transform", global_position, target_look)

func _calculate_friendly_separation() -> Vector2:
	var push = Vector2.ZERO
	for u in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(u) and u != self:
			var d = global_position.distance_to(u.global_position)
			if d < 28.0 and d > 0.1:
				push += (global_position - u.global_position).normalized() * (1.0 - (d / 28.0))
	return push

func _process_vanguard_rad_aura(_delta: float):
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= 90.0:
			if e.has_method("take_damage") and (Time.get_ticks_msec() % 500 < 20):
				e.take_damage(2)

func _resolve_player_owner():
	var name_parts = name.split("_")
	if name_parts.size() >= 2:
		player_owner = get_parent().get_node_or_null(name_parts[1])
	if not is_instance_valid(player_owner):
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p.get("current_class") == 1:
				player_owner = p
				break

@rpc("unreliable")
func sync_transform(server_pos: Vector2, look_pos: Vector2):
	if not multiplayer.is_server():
		global_position = global_position.lerp(server_pos, 0.45)
		if visual_sprite and visual_sprite.has_method("update_facing"):
			visual_sprite.update_facing(look_pos)

func get_nearest_enemy() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var min_d = detection_range
	for e in enemies:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			var d = global_position.distance_to(e.global_position)
			if d < min_d:
				min_d = d
				nearest = e
	return nearest

func _shoot_sniper_round(target_pos: Vector2):
	can_attack = false
	if visual_sprite and visual_sprite.has_method("trigger_attack_fx"):
		visual_sprite.trigger_attack_fx()

	AudioManager.play_sfx("radium_shot", global_position, 2.0, 0.7)

	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and "spawner" in main_node and main_node.spawner:
		var dir = (target_pos - global_position).normalized()
		main_node.spawner.spawn({
			"type": "bullet",
			"name": "SniperShot_" + str(randi()),
			"position": global_position + (dir * 24.0),
			"direction": dir,
			"damage": 55,
			"bullet_type": 0 # Bullet.BulletType.GALVANIC_SNIPER
		})

	get_tree().create_timer(attack_cooldown).timeout.connect(func(): if is_instance_valid(self): can_attack = true)
	
func _shoot_rad_carbine(target_pos: Vector2):
	can_attack = false
	if visual_sprite and visual_sprite.has_method("trigger_attack_fx"):
		visual_sprite.trigger_attack_fx()

	AudioManager.play_sfx("radium_shot", global_position, 0.0, 1.2)

	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and "spawner" in main_node and main_node.spawner:
		var dir = (target_pos - global_position).normalized()
		main_node.spawner.spawn({
			"type": "bullet",
			"name": "RadShot_" + str(randi()),
			"position": global_position + (dir * 18.0),
			"direction": dir,
			"damage": 22,
			"bullet_type": 1 # Bullet.BulletType.RADIUM_FLECHETTE
		})

	get_tree().create_timer(attack_cooldown).timeout.connect(func(): if is_instance_valid(self): can_attack = true)
	
func _process_sicarian_combat(nearest_enemy: Node2D, delta: float) -> Vector2:
	var dist = global_position.distance_to(nearest_enemy.global_position)
	var dir_to_enemy = global_position.direction_to(nearest_enemy.global_position)
	
	if dist > 46.0:
		# Sprint toward target
		return dir_to_enemy * (speed * 1.15)
	else:
		# Plant feet in melee range - DO NOT overshoot!
		if can_attack:
			_perform_melee_strike(nearest_enemy)
		# Smoothly brake to a halt
		return velocity.move_toward(Vector2.ZERO, speed * 8.0 * delta)

func _perform_melee_strike(target: Node2D):
	can_attack = false
	if visual_sprite and visual_sprite.has_method("set_attack_state"):
		visual_sprite.set_attack_state(true, 1.0, (target.global_position - global_position).angle())
	if visual_sprite and visual_sprite.has_method("trigger_attack_fx"):
		visual_sprite.trigger_attack_fx()

	AudioManager.play_sfx("axe_swing", global_position, 1.0, 1.4)

	# Micro-lunge forward into the slash
	var strike_dir = global_position.direction_to(target.global_position)
	velocity = strike_dir * 160.0

	if target.has_method("take_damage"):
		var dmg = 48 if (is_in_marshal_aura and aura_is_conqueror) else 38
		target.take_damage(dmg, strike_dir * 140.0)

	get_tree().create_timer(attack_cooldown).timeout.connect(func():
		if is_instance_valid(self):
			can_attack = true
			if visual_sprite and visual_sprite.has_method("set_attack_state"):
				visual_sprite.set_attack_state(false, 0.0, 0.0)
	)
	
func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var final_dmg = amount
	if is_in_marshal_aura and not aura_is_conqueror:
		final_dmg = int(amount * 0.65)

	current_health = max(0, current_health - final_dmg)
	if multiplayer.has_multiplayer_peer():
		rpc("sync_health", current_health)
	else:
		sync_health(current_health)

@rpc("call_local", "reliable")
func sync_health(hp: int):
	current_health = hp
	if is_instance_valid(health_bar) and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
	if current_health <= 0:
		if is_instance_valid(player_owner) and "active_bodyguards" in player_owner:
			player_owner.active_bodyguards.erase(self)
		var hud = get_tree().get_first_node_in_group("ability_hud")
		if hud and hud.has_method("refresh_hud_display"):
			hud.refresh_hud_display()
		queue_free()

# ==============================================================================
# ONLY DRAWS DECAL & STATUS RINGS (Character is drawn by VisualSprite)
# ==============================================================================
func _draw() -> void:
	if is_rts_selected:
		draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
		draw_arc(Vector2(0, 12), 16.0, 0, TAU, 24, Color(0.20, 0.88, 1.0, 0.85), 1.5)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	if is_in_marshal_aura:
		var aura_col = Color(1.0, 0.75, 0.20, 0.65) if aura_is_conqueror else Color(0.20, 0.88, 1.0, 0.65)
		draw_arc(Vector2(0, 4), 13.0, 0, TAU, 16, aura_col, 1.2)
