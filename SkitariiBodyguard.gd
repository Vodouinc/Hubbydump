extends CharacterBody2D

enum GuardRole { RANGER_SNIPER, SICARIAN_MELEE }
@export var guard_role: GuardRole = GuardRole.RANGER_SNIPER

var player_owner: Node2D = null
var speed: float = 340.0
var max_acceleration: float = 1400.0
var detection_range: float = 550.0
var can_attack: bool = true
var attack_cooldown: float = 1.1

# RTS & Directive State
var is_anchored_bipod: bool = false
var anchor_target_pos: Vector2 = Vector2.ZERO
var is_rts_selected: bool = false
var rts_move_target: Vector2 = Vector2.ZERO
var rts_is_commanded_move: bool = false
var rts_target_enemy_node: Node2D = null

var bodyguard_slot_index: int = 0
@export var rotation_speed: float = 14.0
var current_target_rotation: float = 0.0

@onready var visual_sprite: Node2D = $VisualSprite

func _ready():
	add_to_group("bodyguards")
	add_to_group("controllable_units")
	add_to_group("friendlies")
	_apply_role_stats()

func _apply_role_stats():
	if guard_role == GuardRole.RANGER_SNIPER:
		speed = 310.0
		detection_range = 580.0
		attack_cooldown = 1.15
	else:
		speed = 420.0
		detection_range = 280.0
		attack_cooldown = 0.45

	if visual_sprite:
		visual_sprite.unit_type = 2 # Vanguard visual base

# ==============================================================================
# RTS COMMAND INTERFACE
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
	var slot_offset = Vector2(24, 0) if bodyguard_slot_index == 0 else Vector2(-24, 0)
	anchor_target_pos = pos + slot_offset
	detection_range = 800.0
	attack_cooldown = 0.65

func clear_anchor_directive() -> void:
	is_anchored_bipod = false
	_apply_role_stats()

# ==============================================================================
# PHYSICS PROCESS & COMBAT
# ==============================================================================
func _physics_process(delta: float):
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return

	if not is_instance_valid(player_owner):
		var name_parts = name.split("_")
		if name_parts.size() >= 2:
			player_owner = get_parent().get_node_or_null(name_parts[1])
		if not is_instance_valid(player_owner):
			return

	if "active_bodyguards" in player_owner:
		var idx = player_owner.active_bodyguards.find(self)
		if idx >= 0:
			bodyguard_slot_index = idx
			guard_role = GuardRole.RANGER_SNIPER if idx == 0 else GuardRole.SICARIAN_MELEE

	# --- 1. TARGET SELECTION ---
	var nearest_enemy: Node2D = null
	if is_instance_valid(rts_target_enemy_node):
		nearest_enemy = rts_target_enemy_node
	else:
		var painted = player_owner.get("painted_target_enemy") if "painted_target_enemy" in player_owner else null
		if is_instance_valid(painted):
			nearest_enemy = painted
		else:
			nearest_enemy = get_nearest_enemy()

	# --- 2. MOVEMENT & FORMATIONS ---
	var desired_velocity = Vector2.ZERO

	# Inherit active Doctrina if inside command aura
	var in_aura = (global_position.distance_to(player_owner.global_position) <= 240.0)
	var owner_doctrina = player_owner.get("active_doctrina") if "active_doctrina" in player_owner else 0
	
	if in_aura:
		if owner_doctrina == 0:
			attack_cooldown = 0.70 if guard_role == GuardRole.RANGER_SNIPER else 0.28
		else:
			attack_cooldown = 1.15 if guard_role == GuardRole.RANGER_SNIPER else 0.45

	if rts_is_commanded_move:
		# Direct RTS Move Order
		var dist = global_position.distance_to(rts_move_target)
		if dist > 14.0:
			desired_velocity = global_position.direction_to(rts_move_target) * speed
		else:
			rts_is_commanded_move = false
			desired_velocity = Vector2.ZERO
	elif is_anchored_bipod:
		# Hold Deployed Anchor Bipod
		var dist_to_anchor = global_position.distance_to(anchor_target_pos)
		if dist_to_anchor > 10.0:
			desired_velocity = global_position.direction_to(anchor_target_pos) * speed
		else:
			desired_velocity = Vector2.ZERO
	elif guard_role == GuardRole.SICARIAN_MELEE and is_instance_valid(nearest_enemy) and global_position.distance_to(nearest_enemy.global_position) <= 220.0:
		# Sicarian Melee Charge
		var dir_to_enemy = global_position.direction_to(nearest_enemy.global_position)
		desired_velocity = dir_to_enemy * speed
		if global_position.distance_to(nearest_enemy.global_position) <= 42.0:
			if can_attack:
				_perform_melee_strike(nearest_enemy)
	else:
		# Escort formation near Marshal
		var player_facing = Vector2.RIGHT
		if player_owner.get("visual_sprite") and player_owner.visual_sprite:
			player_facing = Vector2.RIGHT.rotated(player_owner.visual_sprite.global_rotation)

		var side_dir = player_facing.orthogonal()
		var side_offset = -40.0 if bodyguard_slot_index == 0 else 40.0
		var follow_target_pos = player_owner.global_position - (player_facing * 32.0) + (side_dir * side_offset)

		var dist_to_slot = global_position.distance_to(follow_target_pos)
		if dist_to_slot > 12.0:
			var target_spd = speed
			if dist_to_slot < 50.0:
				target_spd = speed * (dist_to_slot / 50.0)
			desired_velocity = global_position.direction_to(follow_target_pos) * target_spd

	velocity = velocity.move_toward(desired_velocity, max_acceleration * delta)
	move_and_slide()

	# --- 3. ROTATION & RANGED COMBAT ---
	if is_instance_valid(nearest_enemy) and global_position.distance_to(nearest_enemy.global_position) <= detection_range:
		current_target_rotation = (nearest_enemy.global_position - global_position).angle()
		if guard_role == GuardRole.RANGER_SNIPER and can_attack:
			_shoot_sniper_round(nearest_enemy.global_position)
	elif velocity.length_squared() > 400.0:
		current_target_rotation = velocity.angle()

	var active_rot = visual_sprite.global_rotation if visual_sprite else global_rotation
	var smooth_rot = lerp_angle(active_rot, current_target_rotation, rotation_speed * delta)
	apply_sprite_rotation(smooth_rot)
	rpc("sync_transform", global_position, smooth_rot)

func apply_sprite_rotation(rot_angle: float):
	if visual_sprite: visual_sprite.global_rotation = rot_angle
	else: global_rotation = rot_angle

@rpc("unreliable")
func sync_transform(server_pos: Vector2, rot_angle: float):
	if not multiplayer.is_server():
		global_position = global_position.lerp(server_pos, 0.45)
		apply_sprite_rotation(rot_angle)

func get_nearest_enemy() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var min_d = detection_range
	for e in enemies:
		if is_instance_valid(e):
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

	var main_node = get_parent()
	if main_node and "spawner" in main_node and main_node.spawner:
		var dir = (target_pos - global_position).normalized()
		main_node.spawner.spawn({
			"type": "bullet",
			"name": "SniperShot_" + str(randi()),
			"position": global_position + (dir * 22.0),
			"direction": dir,
			"damage": 50
		})

	var timer = get_tree().create_timer(attack_cooldown)
	timer.timeout.connect(func(): if is_instance_valid(self): can_attack = true)

func _perform_melee_strike(target: Node2D):
	can_attack = false
	if visual_sprite and visual_sprite.has_method("trigger_attack_fx"):
		visual_sprite.trigger_attack_fx()

	AudioManager.play_sfx("axe_swing", global_position, -2.0, 1.35)

	if target.has_method("take_damage"):
		var knockback_dir = global_position.direction_to(target.global_position)
		target.take_damage(35, knockback_dir * 180.0)

	var timer = get_tree().create_timer(attack_cooldown)
	timer.timeout.connect(func(): if is_instance_valid(self): can_attack = true)

func _draw() -> void:
	# Tactical RTS Selection Decal
	if is_rts_selected:
		draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
		draw_arc(Vector2(0, 14), 16.0, 0, TAU, 20, Color(0.20, 0.88, 1.0, 0.85), 1.5)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
