@tool
extends CharacterBody2D

@export var movement_speed: float = 220.0
@export var detection_radius: float = 400.0
@export var scrap_pickup_range: float = 30.0
@export var zap_range: float = 100.0
@export var zap_damage: int = 13
@export var zap_cooldown: float = 1.0

# Follow behavior matching bodyguards
@export var follow_distance: float = 80.0
@export var max_follow_distance: float = 300.0

var owner_player: Node2D = null
var current_target_scrap: Node2D = null
var current_target_enemy: Node2D = null
var zap_timer: float = 0.0
var zap_visual_timer: float = 0.0
var anim_time: float = 0.0
var hover_time: float = 0.0
@export var base_elevation: float = 12.0

# Core Palette Constants
const COLOR_WHITE_TRIM = Color(0.92, 0.92, 0.88)
const COLOR_BRONZE = Color(0.7, 0.48, 0.22)
const COLOR_BRASS = Color(0.85, 0.65, 0.25)
const COLOR_STEEL = Color(0.55, 0.58, 0.62)
const COLOR_DARK_STEEL = Color(0.25, 0.28, 0.32)
const COLOR_CYAN_GLOW = Color(0.15, 0.9, 1.0)
const COLOR_PURITY_PAPER = Color(0.88, 0.85, 0.75)
const COLOR_PURITY_WAX = Color(0.7, 0.1, 0.1)

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var visual_sprite: Node2D = get_node_or_null("VisualSprite")
@onready var shadow_node: Node2D = get_node_or_null("Shadow")

func _ready():
	add_to_group("ServoSkull")
	set_process(true)
	
	if not has_node("SkullSearchLight"):
		var light = LightUtils.create_point_light(Color(0.20, 0.88, 1.0), 1.0, 1.8)
		light.name = "SkullSearchLight"
		add_child(light)
	
	if not Engine.is_editor_hint():
		set_physics_process(multiplayer.is_server())
	else:
		set_physics_process(false)

func _process(delta):
	# 1. Floating Hover & Bobbing Animation
	hover_time += delta * 3.2
	var current_elevation = base_elevation + sin(hover_time) * 3.0
	if visual_sprite:
		visual_sprite.position.y = -current_elevation
	if shadow_node and shadow_node.has_method("set_elevation"):
		shadow_node.set_elevation(current_elevation)

	# 2. Server/Authority logic for timers
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if zap_timer > 0:
		zap_timer -= delta
		
	if zap_visual_timer > 0:
		zap_visual_timer -= delta
		anim_time += delta
		if anim_time > 0.05:
			anim_time = 0.0
			queue_redraw()
	elif zap_visual_timer <= 0 and anim_time != 0.0:
		anim_time = 0.0
		queue_redraw() # Clear the canvas once when the zap finishes

func _physics_process(delta):
	if not owner_player or not is_instance_valid(owner_player):
		find_owner_player()
		return

	# 1. Prioritize looking for scrap if none is currently targeted
	if not current_target_scrap or not is_instance_valid(current_target_scrap):
		current_target_scrap = find_nearest_scrap()

	var target_position: Vector2

	if current_target_scrap:
		target_position = current_target_scrap.global_position
		float_toward(target_position, delta)
		
		if global_position.distance_to(current_target_scrap.global_position) <= scrap_pickup_range:
			# Extract scrap value safely before freeing or collecting
			var scrap_value = 5 # Default fallback value
			if "scrap_value" in current_target_scrap:
				scrap_value = current_target_scrap.scrap_value
			elif current_target_scrap.has_method("get_scrap_value"):
				scrap_value = current_target_scrap.get_scrap_value()

			# Deposit directly to the main game node pool
			var main_node = get_tree().get_first_node_in_group("main")
			if main_node and main_node.has_method("add_scrap"):
				main_node.add_scrap(scrap_value)

			if current_target_scrap.has_method("collect"):
				current_target_scrap.collect(owner_player)
			else:
				current_target_scrap.queue_free()
				
			current_target_scrap = null
	else:
		handle_bodyguard_idle_behavior(delta)

func float_toward(target_pos: Vector2, delta: float):
	var direction = global_position.direction_to(target_pos)
	velocity = velocity.move_toward(direction * movement_speed, movement_speed * 5.0 * delta)
	move_and_slide()

func handle_bodyguard_idle_behavior(delta: float):
	var dist_to_owner = global_position.distance_to(owner_player.global_position)

	# Check for nearby enemies to zap defensively
	current_target_enemy = find_nearest_enemy_in_range(zap_range)
	if current_target_enemy and zap_timer <= 0:
		fire_zap(current_target_enemy)
		zap_timer = zap_cooldown
		zap_visual_timer = 0.25
		queue_redraw()

	if dist_to_owner > max_follow_distance:
		float_toward(owner_player.global_position, delta)
	elif dist_to_owner > follow_distance:
		var idle_target = owner_player.global_position + (owner_player.transform.x * follow_distance)
		float_toward(idle_target, delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, movement_speed * 3.0 * delta)
		move_and_slide()

func find_nearest_scrap() -> Node2D:
	var scrap_nodes = get_tree().get_nodes_in_group("scrap")
	var nearest_scrap: Node2D = null
	var shortest_distance: float = detection_radius

	for scrap in scrap_nodes:
		var dist = global_position.distance_to(scrap.global_position)
		if dist < shortest_distance:
			shortest_distance = dist
			nearest_scrap = scrap

	return nearest_scrap

func find_nearest_enemy_in_range(range_limit: float) -> Node2D:
	var enemy_nodes = get_tree().get_nodes_in_group("enemies")
	var nearest_enemy: Node2D = null
	var shortest_distance: float = range_limit

	for enemy in enemy_nodes:
		var dist = global_position.distance_to(enemy.global_position)
		if dist < shortest_distance:
			shortest_distance = dist
			nearest_enemy = enemy

	return nearest_enemy

func fire_zap(target: Node2D):
	if target.has_method("take_damage"):
		target.take_damage(zap_damage)

func set_owner_player(player: Node2D):
	owner_player = player

func find_owner_player():
	for player in get_tree().get_nodes_in_group("players"):
		if player.name == str(name.get_slice("_", 0)):
			owner_player = player
			break

func _draw():
	# 1. Anti-Grav Engine / Top Exhaust Vent Mount
	draw_rect(Rect2(-3, -11, 6, 4), COLOR_DARK_STEEL)
	draw_line(Vector2(0, -11), Vector2(0, -14), COLOR_BRASS, 1.5)

	# 2. Cybernetic Cranium & Mechanical Plate Framing
	draw_circle(Vector2.ZERO, 8.0, COLOR_WHITE_TRIM)
	draw_circle(Vector2.ZERO, 7.0, COLOR_STEEL)
	draw_arc(Vector2.ZERO, 7.2, -PI * 0.75, PI * 0.25, 8, COLOR_BRASS, 2.5)

	# 3. Central Ocular Augment (Glowing Cyan Main Lens)
	draw_circle(Vector2(3, -1), 3.5, COLOR_DARK_STEEL)
	draw_circle(Vector2(3, -1), 2.0, COLOR_CYAN_GLOW)
	draw_circle(Vector2(3.5, -1.5), 0.7, Color.WHITE)

	# 4. Lower Jaw Augment & Data-Spike (Pointing Forward/Right)
	draw_rect(Rect2(2, 3, 5, 3), COLOR_DARK_STEEL)
	draw_line(Vector2(7, 4), Vector2(14, 4), COLOR_BRASS, 2.0)
	draw_circle(Vector2(14, 4), 1.0, COLOR_CYAN_GLOW)

	# 5. Purity Seal
	draw_line(Vector2(-4, 3), Vector2(-6, 8), COLOR_PURITY_WAX, 2.0)
	draw_rect(Rect2(-8, 8, 5, 8), COLOR_PURITY_PAPER)
	draw_circle(Vector2(-5.5, 9.5), 1.5, COLOR_PURITY_WAX)

	# 6. Synchronized Targeted Attack Zap Animation
	if zap_visual_timer > 0 and current_target_enemy and is_instance_valid(current_target_enemy):
		var zap_start = Vector2(14, 4) # Tip of the data spike
		# Convert enemy's global position into local coordinates relative to the Servo-Skull
		var local_target_pos = to_local(current_target_enemy.global_position)
		
		var points = PackedVector2Array()
		points.append(zap_start)
		
		var segments = 4
		for i in range(1, segments):
			var t = float(i) / float(segments)
			var lerped_pos = zap_start.lerp(local_target_pos, t)
			var jitter = Vector2(randf_range(-5, 5), randf_range(-5, 5))
			points.append(lerped_pos + jitter)
			
		points.append(local_target_pos)
		
		# Draw precise electrical strike hitting the actual enemy position
		draw_polyline(points, Color(COLOR_CYAN_GLOW.r, COLOR_CYAN_GLOW.g, COLOR_CYAN_GLOW.b, 0.5), 4.0)
		draw_polyline(points, Color.WHITE, 1.5)
