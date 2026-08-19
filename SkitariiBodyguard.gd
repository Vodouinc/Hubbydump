extends CharacterBody2D

var player_owner: Node2D = null
var speed: float = 340.0
var max_acceleration: float = 1200.0
var follow_distance: float = 120.0
var detection_range: float = 350.0
var can_shoot: bool = true
var shoot_cooldown: float = 0.6

var bodyguard_slot_index: int = 0
@export var rotation_speed: float = 12.0 

var current_target_rotation: float = 0.0 

@onready var visual_sprite: Node2D = $VisualSprite

func _ready():
	add_to_group("bodyguards")
	if visual_sprite:
		visual_sprite.unit_type = 2 # SKITARII_VANGUARD

func _physics_process(delta):
	# Only host executes movement and shooting logic
	if not multiplayer.is_server():
		return
		
	# Resolve owner dynamically if missing
	if not is_instance_valid(player_owner):
		var name_parts = name.split("_")
		if name_parts.size() >= 2:
			var owner_id_str = name_parts[1]
			player_owner = get_parent().get_node_or_null(owner_id_str)
			
		if not is_instance_valid(player_owner):
			return

	# Update slot index
	if player_owner and "active_bodyguards" in player_owner:
		var idx = player_owner.active_bodyguards.find(self)
		if idx >= 0:
			bodyguard_slot_index = idx

	# -------------------------------------------------------------
	# 1. SMOOTH FORMATION & MOVEMENT STEERING
	# -------------------------------------------------------------
	# Calculate offset behind and to the side of player facing direction
	var player_facing = Vector2.RIGHT
	if player_owner.get("visual_sprite") and player_owner.visual_sprite:
		player_facing = Vector2.RIGHT.rotated(player_owner.visual_sprite.global_rotation)

	var side_dir = player_facing.orthogonal()
	var side_offset = -35.0 if bodyguard_slot_index == 0 else 35.0
	var target_pos = player_owner.global_position - (player_facing * 30.0) + (side_dir * side_offset)
	
	var dist_to_target = global_position.distance_to(target_pos)
	var desired_velocity = Vector2.ZERO

	if dist_to_target > 12.0:
		var target_speed = speed
		# Arrival damping: slow down as guard gets close to target slot
		if dist_to_target < 50.0:
			target_speed = speed * (dist_to_target / 50.0)

		var dir = (target_pos - global_position).normalized()
		desired_velocity = dir * target_speed

	# Accelerate smoothly to avoid snappy jitter
	velocity = velocity.move_toward(desired_velocity, max_acceleration * delta)
	move_and_slide()

	# -------------------------------------------------------------
	# 2. SMOOTH AIMING & ROTATION
	# -------------------------------------------------------------
	var nearest_enemy = get_nearest_enemy()

	if nearest_enemy and global_position.distance_to(nearest_enemy.global_position) <= detection_range:
		current_target_rotation = (nearest_enemy.global_position - global_position).angle()
		if can_shoot:
			shoot(nearest_enemy.global_position)
	elif velocity.length_squared() > 400.0:
		current_target_rotation = velocity.angle()

	var active_rotation = visual_sprite.global_rotation if visual_sprite else global_rotation
	var smooth_rot = lerp_angle(active_rotation, current_target_rotation, rotation_speed * delta)

	apply_sprite_rotation(smooth_rot)
	rpc("sync_transform", global_position, smooth_rot)

func apply_sprite_rotation(rot_angle: float):
	if visual_sprite:
		visual_sprite.global_rotation = rot_angle
	else:
		global_rotation = rot_angle

@rpc("unreliable")
func sync_transform(server_pos: Vector2, rot_angle: float):
	if not multiplayer.is_server():
		# Interpolate non-server positions smoothly
		global_position = global_position.lerp(server_pos, 0.4)
		apply_sprite_rotation(rot_angle)

func get_nearest_enemy() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var min_dist = detection_range
	
	for enemy in enemies:
		if is_instance_valid(enemy):
			var d = global_position.distance_to(enemy.global_position)
			if d < min_dist:
				min_dist = d
				nearest = enemy
	return nearest

func shoot(target_pos: Vector2):
	can_shoot = false
	if visual_sprite and visual_sprite.has_method("trigger_attack_fx"):
		visual_sprite.trigger_attack_fx()
	
	var main_node = get_parent()
	if main_node and "bullet_count" in main_node:
		main_node.bullet_count += 1
		var bullet_data = {
			"type": "bullet",
			"name": "BodyguardBullet_" + str(main_node.bullet_count),
			"position": global_position,
			"direction": (target_pos - global_position).normalized()
		}
		if "spawner" in main_node:
			main_node.spawner.spawn(bullet_data)
			
	var timer = get_tree().create_timer(shoot_cooldown)
	timer.timeout.connect(func(): 
		if is_instance_valid(self):
			can_shoot = true
	)
