extends CharacterBody2D

enum GuardRole { RANGER_SNIPER, SICARIAN_MELEE }
@export var guard_role: GuardRole = GuardRole.RANGER_SNIPER

var player_owner: Node2D = null
var speed: float = 340.0
var max_acceleration: float = 1400.0
var detection_range: float = 550.0
var can_attack: bool = true
var attack_cooldown: float = 1.1

var bodyguard_slot_index: int = 0
@export var rotation_speed: float = 14.0
var current_target_rotation: float = 0.0

@onready var visual_sprite: Node2D = $VisualSprite

func _ready():
	add_to_group("bodyguards")
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

	# --- 1. MOVEMENT & FORMATION ---
	var player_facing = Vector2.RIGHT
	if player_owner.get("visual_sprite") and player_owner.visual_sprite:
		player_facing = Vector2.RIGHT.rotated(player_owner.visual_sprite.global_rotation)

	var side_dir = player_facing.orthogonal()
	var side_offset = -40.0 if bodyguard_slot_index == 0 else 40.0
	var follow_target_pos = player_owner.global_position - (player_facing * 32.0) + (side_dir * side_offset)

	var nearest_enemy = get_nearest_enemy()
	var desired_velocity = Vector2.ZERO

	# Inherit active doctrine from Marshal if inside command aura
	var in_aura = (global_position.distance_to(player_owner.global_position) <= 240.0)
	var owner_doctrina = player_owner.get("active_doctrina") if "active_doctrina" in player_owner else 0
	
	if in_aura:
		if owner_doctrina == 0: # CONQUEROR
			attack_cooldown = 0.70 if guard_role == GuardRole.RANGER_SNIPER else 0.28
		else: # PROTECTOR
			attack_cooldown = 1.15 if guard_role == GuardRole.RANGER_SNIPER else 0.45

	# Sicarian Melee Guards dash in to shred nearby enemies
	if guard_role == GuardRole.SICARIAN_MELEE and is_instance_valid(nearest_enemy) and global_position.distance_to(nearest_enemy.global_position) <= 220.0:
		var dir_to_enemy = global_position.direction_to(nearest_enemy.global_position)
		desired_velocity = dir_to_enemy * speed
		if global_position.distance_to(nearest_enemy.global_position) <= 42.0:
			if can_attack:
				_perform_melee_strike(nearest_enemy)
	else:
		# Stay in formation near the Marshal
		var dist_to_slot = global_position.distance_to(follow_target_pos)
		if dist_to_slot > 12.0:
			var target_spd = speed
			if dist_to_slot < 50.0:
				target_spd = speed * (dist_to_slot / 50.0)
			desired_velocity = global_position.direction_to(follow_target_pos) * target_spd

	velocity = velocity.move_toward(desired_velocity, max_acceleration * delta)
	move_and_slide()

	# --- 2. ROTATION & RANGED COMBAT ---
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
	if main_node and "spawner" in main_node:
		var dir = (target_pos - global_position).normalized()
		var bullet_data = {
			"type": "bullet",
			"name": "SniperShot_" + str(randi()),
			"position": global_position + (dir * 22.0),
			"direction": dir,
			"damage": 50 # Heavy high-velocity round
		}
		main_node.spawner.spawn(bullet_data)

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
