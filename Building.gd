extends StaticBody2D

enum Type { BARRICADE, GENERATOR, TURRET, MANUFACTORUM }

@export var building_type: Type = Type.BARRICADE:
	set(val):
		building_type = val
		if is_node_ready():
			_apply_type_setup()

@export var max_health: int = 150
var current_health: int = 150
var current_turret_rotation: float = 0.0
var is_preview: bool = false

const TURRET_UPGRADE_COSTS := [10, 20, 35]
const TURRET_DAMAGE_BY_LEVEL := [15, 21, 29, 40]
const TURRET_FIRE_INTERVALS := [1.0, 0.78, 0.62, 0.48]
const TURRET_RANGE_BY_LEVEL := [250.0, 275.0, 305.0, 340.0]
var turret_upgrade_level: int = 0

@onready var visual_spriteNode = get_node_or_null("VisualBuildingSprite")
@onready var turret_timer: Timer = get_node_or_null("TurretTimer")
@onready var gen_timer: Timer = get_node_or_null("GeneratorTimer")
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var health_bar: Node2D = get_node_or_null("HealthBar")

# Dynamic Conal Floodlight for Turrets
var turret_light: PointLight2D = null

func _ready():
	add_to_group("buildings")
	add_to_group("navmesh_source")
	
	_setup_turret_light()
	
	match building_type:
		Type.BARRICADE, Type.MANUFACTORUM:
			max_health = 150
		Type.GENERATOR:
			max_health = 100
		Type.TURRET:
			max_health = 80
			
	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)
	update_ui()
	
	if turret_timer and not turret_timer.timeout.is_connected(_on_turret_timer_timeout):
		turret_timer.timeout.connect(_on_turret_timer_timeout)
	if gen_timer and not gen_timer.timeout.is_connected(_on_gen_timer_timeout):
		gen_timer.timeout.connect(_on_gen_timer_timeout)
		
	_apply_type_setup()
	get_tree().call_group("sandy_floor", "refresh_foundations")

func _setup_turret_light():
	if has_node("TurretLight"):
		turret_light = $TurretLight
	else:
		turret_light = PointLight2D.new()
		turret_light.name = "TurretLight"
		turret_light.enabled = false
		turret_light.shadow_enabled = true 
		turret_light.energy = 0.9 # Lower energy prevents intense stacking glare
		
		# Procedurally generate a clean cone/wedge light mask image
		var size = 256
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		
		var center = Vector2(float(size) / 2.0, float(size) / 2.0)
		var radius = float(size) * 0.45
		var cone_spread_angle = deg_to_rad(35.0) 
		
		for x in range(size):
			for y in range(size):
				var pos = Vector2(x, y)
				var dist = center.distance_to(pos)
				if dist <= radius:
					var angle_to_pixel = (pos - center).angle()
					var angle_diff = abs(wrapf(angle_to_pixel, -PI, PI))
					if angle_diff <= cone_spread_angle:
						var edge_factor = 1.0 - (angle_diff / cone_spread_angle)
						var dist_factor = 1.0 - (dist / radius)
						var alpha = clamp(edge_factor * dist_factor * 1.3, 0.0, 1.0)
						img.set_pixel(x, y, Color(0.25, 0.75, 0.95, alpha))
						
		turret_light.texture = ImageTexture.create_from_image(img)
		turret_light.texture_scale = 3.5
		turret_light.offset = Vector2(size * 0.22, 0)
		
		# Add to tree first so properties don't hit a null base object
		add_child(turret_light)

func setup_as_preview():
	is_preview = true
	remove_from_group("buildings")
	remove_from_group("navmesh_source")
	
	if is_instance_valid(turret_light):
		turret_light.enabled = false

	var shadow_node = get_node_or_null("Shadow")
	if is_instance_valid(shadow_node):
		shadow_node.visible = false

	var occluder_node = get_node_or_null("LightOccluder2D")
	if is_instance_valid(occluder_node):
		occluder_node.visible = false

	var hbar = get_node_or_null("HealthBar")
	if is_instance_valid(hbar):
		hbar.visible = false
	
	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", true)
	if has_node("Area2D"):
		$Area2D.queue_free()

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO):
	if is_preview or not multiplayer.is_server():
		return
		
	var new_hp = max(0, current_health - amount)
	rpc("sync_building_health", new_hp)

@rpc("call_local", "reliable")
func sync_building_health(new_hp: int):
	current_health = new_hp
	update_ui()
	
	if current_health <= 0 and multiplayer.is_server():
		destroy_building()

func destroy_building():
	if multiplayer.is_server():
		remove_from_group("navmesh_source")
		
		var main_node = get_parent()
		if not (main_node and main_node.has_method("request_navmesh_rebake")):
			main_node = get_tree().get_first_node_in_group("main")
		if main_node and main_node.has_method("request_navmesh_rebake"):
			main_node.request_navmesh_rebake()
			
		rpc("client_destroy")

@rpc("call_local", "reliable")
func client_destroy():
	get_tree().call_group("sandy_floor", "refresh_foundations")
	queue_free()

func update_ui():
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

func try_upgrade_turret() -> bool:
	if not multiplayer.is_server() or building_type != Type.TURRET:
		return false
	if turret_upgrade_level >= TURRET_UPGRADE_COSTS.size():
		return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not main_node.has_method("spend_requisition"):
		return false
	var cost: int = TURRET_UPGRADE_COSTS[turret_upgrade_level]
	if not main_node.spend_requisition(cost):
		return false
	rpc("sync_turret_upgrade", turret_upgrade_level + 1)
	return true

@rpc("call_local", "reliable")
func sync_turret_upgrade(new_level: int) -> void:
	turret_upgrade_level = clampi(new_level, 0, TURRET_DAMAGE_BY_LEVEL.size() - 1)
	_apply_turret_upgrade()

func _apply_turret_upgrade() -> void:
	if is_instance_valid(turret_timer):
		turret_timer.wait_time = TURRET_FIRE_INTERVALS[turret_upgrade_level]
	if is_instance_valid(turret_light):
		turret_light.energy = 0.9 + turret_upgrade_level * 0.18
		if turret_upgrade_level > 0:
			turret_light.color = Color(0.35, 0.88, 1.0)
	if is_instance_valid(visual_spriteNode):
		if "turret_upgrade_level" in visual_spriteNode:
			visual_spriteNode.turret_upgrade_level = turret_upgrade_level
		visual_spriteNode.queue_redraw()

# --- PROCESS & TARGETING LOGIC ---
	
func _process(delta):
	if building_type == Type.TURRET and not is_preview:
		if is_instance_valid(turret_light):
			turret_light.rotation = current_turret_rotation
			
		var is_host = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
		if is_host:
			var target = _find_closest_enemy()
			if target:
				var target_dir = (target.global_position - global_position)
				var target_angle = target_dir.angle()
				
				var rotation_speed = 3.0 
				current_turret_rotation = lerp_angle(current_turret_rotation, target_angle, rotation_speed * delta)
				
				rpc("sync_turret_rotation", current_turret_rotation)
			else:
				# --- PERIMETER SWEEP: LOOK AWAY FROM BASE ---
				# Find the center of the base (or default to Vector2.ZERO if base core isn't grouped)
				var base_center = Vector2.ZERO
				var core_node = get_tree().get_first_node_in_group("base_core") # adjust group name if needed, or use main node
				if core_node:
					base_center = core_node.global_position
				
				# Calculate vector pointing outward away from the base
				var outward_dir = (global_position - base_center)
				if outward_dir.length_squared() < 1.0:
					outward_dir = Vector2.RIGHT # Fallback if right on top of center
				
				var base_outward_angle = outward_dir.angle()
				
				# Slowly oscillate/sweep back and forth around that outward-facing angle to scan the dark
				var sweep_offset = sin(Time.get_ticks_msec() * 0.001 * 1.5) * 0.8 # sweeps about ~45 degrees left and right
				var target_idle_angle = base_outward_angle + sweep_offset
				
				current_turret_rotation = lerp_angle(current_turret_rotation, target_idle_angle, 2.0 * delta)
				rpc("sync_turret_rotation", current_turret_rotation)

func _find_closest_enemy() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var closest_target = null
	var closest_dist = TURRET_RANGE_BY_LEVEL[turret_upgrade_level]
	for enemy in enemies:
		if is_instance_valid(enemy):
			var dist = global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_target = enemy
	return closest_target

func _apply_type_setup():
	if is_instance_valid(visual_spriteNode):
		if "type" in visual_spriteNode:
			visual_spriteNode.type = building_type
		if visual_spriteNode.has_method("queue_redraw"):
			visual_spriteNode.queue_redraw()
			
	if is_instance_valid(turret_light):
		turret_light.enabled = (building_type == Type.TURRET and not is_preview)
		if building_type == Type.TURRET:
			turret_light.color = Color(0.25, 0.75, 0.95) # Atmospheric soft cyan

	var shadow_node = get_node_or_null("Shadow")
	if is_instance_valid(shadow_node) and shadow_node.has_method("update_shadow_size"):
		shadow_node.update_shadow_size()

	if is_instance_valid(collision_shape) and collision_shape.shape:
		match building_type:
			Type.BARRICADE:
				if not (collision_shape.shape is CircleShape2D):
					collision_shape.shape = CircleShape2D.new()
				collision_shape.shape.radius = 19.0
			Type.MANUFACTORUM:
				if collision_shape.shape is RectangleShape2D:
					collision_shape.shape.size = Vector2(44, 44) 
			Type.GENERATOR:
				if collision_shape.shape is CircleShape2D:
					collision_shape.shape.radius = 22.0 
			Type.TURRET:
				if collision_shape.shape is CircleShape2D:
					collision_shape.shape.radius = 16.0 

	if not multiplayer.is_server():
		return

	if building_type == Type.TURRET:
		_apply_turret_upgrade()
		if gen_timer: gen_timer.stop()
		if turret_timer and turret_timer.is_stopped(): 
			turret_timer.start()
	elif building_type == Type.GENERATOR:
		if turret_timer: turret_timer.stop()
		if gen_timer and gen_timer.is_stopped(): 
			gen_timer.start()
	else:
		if turret_timer: turret_timer.stop()
		if gen_timer: gen_timer.stop()

func _on_gen_timer_timeout():
	if multiplayer.is_server():
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node and main_node.has_method("add_requisition"):
			main_node.add_requisition(2)
			rpc("trigger_generator_pulse")

@rpc("call_local", "reliable")
func trigger_generator_pulse():
	if is_instance_valid(visual_spriteNode) and visual_spriteNode.has_method("pulse_generator"):
		visual_spriteNode.pulse_generator()

@rpc("call_local", "unreliable")
func sync_turret_rotation(rot: float):
	current_turret_rotation = rot
	if is_instance_valid(visual_spriteNode):
		if "turret_rotation" in visual_spriteNode:
			visual_spriteNode.turret_rotation = current_turret_rotation
		visual_spriteNode.queue_redraw()

func _on_turret_timer_timeout():
	if not multiplayer.is_server(): 
		return
		
	var target = _find_closest_enemy()
	if target:
		var dir = Vector2.RIGHT.rotated(current_turret_rotation)
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node and "spawner" in main_node and main_node.spawner:
			var spawn_pos = global_position + (dir * 36.0)
			
			var bullet_data = {
				"type": "bullet",
				"name": "TurretBullet_" + str(randi()),
				"position": spawn_pos,
				"direction": dir,
				"damage": TURRET_DAMAGE_BY_LEVEL[turret_upgrade_level]
			}
			main_node.spawner.spawn(bullet_data)
