extends StaticBody2D

enum Type { BARRICADE, GENERATOR, TURRET, MANUFACTORUM, DISTRIBUTOR, NOOSPHERE_ANTENNA, RESEARCH_SHRINE }

@export var building_type: Type = Type.BARRICADE:
	set(val):
		building_type = val
		if is_node_ready():
			_apply_type_setup()

@export var max_health: int = 150
var current_health: int = 150

# --- SHIELD & NOOSPHERE STATE ---
var max_shield: float = 0.0
var current_shield: float = 0.0
var shield_recharge_timer: float = 0.0
const SHIELD_RECHARGE_DELAY: float = 6.0
const SHIELD_REGEN_RATE: float = 18.0
const NANOBOT_REPAIR_RATE: float = 3.5

var is_noosphere_connected: bool = false
const NOOSPHERE_BROADCAST_RADIUS: float = 240.0

# --- TURRET & LASER CONSTANTS ---
var current_turret_rotation: float = 0.0
var is_preview: bool = false
const TURRET_UPGRADE_COSTS := [10, 20, 35]
const TURRET_DAMAGE_BY_LEVEL := [15, 21, 29, 40]
const TURRET_FIRE_INTERVALS := [1.0, 0.78, 0.62, 0.48]
const TURRET_RANGE_BY_LEVEL := [250.0, 275.0, 305.0, 340.0]
var turret_upgrade_level: int = 0

var laser_target: Node2D = null
var laser_damage_timer: float = 0.0

# --- BARRICADE WALL LINK CONSTANTS ---
const WALL_LINK_RANGE: float = 95.0
const WALL_THICKNESS: float = 14.0
var connected_neighbor_ids: Array[int] = []
var active_wall_colliders: Dictionary = {}

@onready var visual_spriteNode = get_node_or_null("VisualBuildingSprite")
@onready var turret_timer: Timer = get_node_or_null("TurretTimer")
@onready var gen_timer: Timer = get_node_or_null("GeneratorTimer")
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var health_bar: Node2D = get_node_or_null("HealthBar")
var turret_light: PointLight2D = null

func _ready():
	add_to_group("buildings")
	add_to_group("navmesh_source")
	
	_setup_turret_light()
	_apply_type_setup()
	
	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)
	update_ui()

	if turret_timer and not turret_timer.timeout.is_connected(_on_turret_timer_timeout):
		turret_timer.timeout.connect(_on_turret_timer_timeout)
	if gen_timer and not gen_timer.timeout.is_connected(_on_gen_timer_timeout):
		gen_timer.timeout.connect(_on_gen_timer_timeout)

	if not is_preview:
		call_deferred("refresh_barricade_connections")
		get_tree().call_group("sandy_floor", "refresh_foundations")

func _process(delta: float):
	if is_preview:
		return

	# 1. Update Noosphere Connection Status
	_update_noosphere_connection()

	# 2. Host Logic: Shield Regeneration, Nanobot Repair, Turret Laser
	if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
		_process_server_buffs(delta)
		if building_type == Type.TURRET:
			_process_turret_logic(delta)
			_process_turret_laser(delta)

	if building_type == Type.TURRET and is_instance_valid(turret_light):
		turret_light.rotation = current_turret_rotation

func _update_noosphere_connection():
	var was_connected = is_noosphere_connected
	is_noosphere_connected = false

	# Base and Antennas project the Noosphere
	var sources: Array = get_tree().get_nodes_in_group("base")
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and int(b.get("building_type")) == int(Type.NOOSPHERE_ANTENNA):
			sources.append(b)

	for src in sources:
		if is_instance_valid(src) and global_position.distance_to(src.global_position) <= NOOSPHERE_BROADCAST_RADIUS:
			is_noosphere_connected = true
			break

	if is_noosphere_connected != was_connected:
		_apply_tech_stats()
		if visual_spriteNode and "is_noosphere_connected" in visual_spriteNode:
			visual_spriteNode.is_noosphere_connected = is_noosphere_connected
			visual_spriteNode.queue_redraw()

func _apply_tech_stats():
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node:
		return

	# If Shield Tech is researched and building is connected to Noosphere
	if is_noosphere_connected and main_node.get("tech_shields_unlocked"):
		max_shield = max_health * 0.4
	else:
		max_shield = 0.0
		current_shield = 0.0

	update_ui()

func _process_server_buffs(delta: float):
	var main_node = get_tree().get_first_node_in_group("main")
	var tech_shields = main_node.get("tech_shields_unlocked") if main_node else false
	var tech_nanobots = main_node.get("tech_nanobots_unlocked") if main_node else false

	# Shield Recharge Delay
	if shield_recharge_timer > 0.0:
		shield_recharge_timer -= delta
	else:
		# Recharge Shield
		if is_noosphere_connected and tech_shields and current_shield < max_shield:
			current_shield = minf(max_shield, current_shield + SHIELD_REGEN_RATE * delta)
			rpc("sync_shield", current_shield)

		# Passive Nanobot Health Repair
		if is_noosphere_connected and tech_nanobots and current_health < max_health:
			current_health = int(minf(max_health, current_health + NANOBOT_REPAIR_RATE * delta))
			rpc("sync_building_health", current_health)

func _process_turret_laser(delta: float):
	var main_node = get_tree().get_first_node_in_group("main")
	var tech_lasers = main_node.get("tech_lasers_unlocked") if main_node else false

	if not is_noosphere_connected or not tech_lasers:
		if laser_target != null:
			laser_target = null
			rpc("sync_laser_target", "")
		return

	var target = _find_closest_enemy()
	if target != laser_target:
		laser_target = target
		rpc("sync_laser_target", target.name if target else "")

	if is_instance_valid(laser_target):
		laser_damage_timer += delta
		if laser_damage_timer >= 0.1:
			laser_damage_timer = 0.0
			if laser_target.has_method("take_damage"):
				laser_target.take_damage(4) # 40 DPS Continuous Laser

@rpc("call_local", "unreliable")
func sync_laser_target(target_name: String):
	if target_name.is_empty():
		laser_target = null
	else:
		laser_target = get_parent().get_node_or_null(target_name)
	if visual_spriteNode and "laser_target_node" in visual_spriteNode:
		visual_spriteNode.laser_target_node = laser_target
		visual_spriteNode.queue_redraw()

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO):
	if is_preview or not multiplayer.is_server():
		return

	shield_recharge_timer = SHIELD_RECHARGE_DELAY
	var damage_remaining = float(amount)

	# Shield Absorbs Damage First
	if current_shield > 0.0:
		var shield_dmg = minf(current_shield, damage_remaining)
		current_shield -= shield_dmg
		damage_remaining -= shield_dmg
		rpc("sync_shield", current_shield)

	# Remaining damage passes through to structural HP
	if damage_remaining > 0.0:
		var new_hp = max(0, current_health - int(damage_remaining))
		rpc("sync_building_health", new_hp)

@rpc("call_local", "reliable")
func sync_shield(new_shield: float):
	current_shield = new_shield
	update_ui()

@rpc("call_local", "reliable")
func sync_building_health(new_hp: int):
	current_health = new_hp
	update_ui()
	if current_health <= 0 and multiplayer.is_server():
		destroy_building()

func update_ui():
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
		if health_bar.has_method("update_shield"):
			health_bar.update_shield(int(current_shield), int(max_shield))

# --- UPGRADE: DISTRIBUTOR -> NOOSPHERE ANTENNA ---

func try_upgrade_distributor() -> bool:
	if not multiplayer.is_server() or building_type != Type.DISTRIBUTOR:
		return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not main_node.has_method("spend_requisition"):
		return false
	if not main_node.spend_requisition(15):
		return false
	rpc("sync_distributor_upgrade")
	return true

@rpc("call_local", "reliable")
func sync_distributor_upgrade():
	building_type = Type.NOOSPHERE_ANTENNA
	_apply_type_setup()
	get_tree().call_group("buildings", "_update_noosphere_connection")

# --- RESEARCH SHRINE UPGRADE PURCHASES ---

func try_purchase_research(tech_index: int) -> bool:
	if not multiplayer.is_server() or building_type != Type.RESEARCH_SHRINE:
		return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node:
		return false

	var costs = [20, 30, 40] # Shields (20 Req), Lasers (30 Req), Nanobots (40 Req)
	if tech_index < 0 or tech_index >= costs.size():
		return false

	if not main_node.spend_requisition(costs[tech_index]):
		return false

	main_node.unlock_tech(tech_index)
	return true

# --- UPGRADE: TURRET ---

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
	if is_instance_valid(visual_spriteNode):
		if "turret_upgrade_level" in visual_spriteNode:
			visual_spriteNode.turret_upgrade_level = turret_upgrade_level
		visual_spriteNode.queue_redraw()

# --- TYPE INITIALIZATION ---

func _apply_type_setup():
	match building_type:
		Type.BARRICADE: max_health = 150
		Type.GENERATOR: max_health = 100
		Type.TURRET: max_health = 90
		Type.MANUFACTORUM: max_health = 250
		Type.DISTRIBUTOR: max_health = 80
		Type.NOOSPHERE_ANTENNA: max_health = 120
		Type.RESEARCH_SHRINE: max_health = 200

	if is_instance_valid(visual_spriteNode):
		if "type" in visual_spriteNode:
			visual_spriteNode.type = building_type
		visual_spriteNode.queue_redraw()

	if is_instance_valid(turret_light):
		turret_light.enabled = (building_type == Type.TURRET and not is_preview)

	if is_instance_valid(collision_shape) and collision_shape.shape:
		match building_type:
			Type.BARRICADE, Type.DISTRIBUTOR, Type.NOOSPHERE_ANTENNA:
				if not (collision_shape.shape is CircleShape2D): collision_shape.shape = CircleShape2D.new()
				collision_shape.shape.radius = 16.0
			Type.GENERATOR, Type.TURRET:
				if not (collision_shape.shape is RectangleShape2D): collision_shape.shape = RectangleShape2D.new()
				collision_shape.shape.size = Vector2(28, 28) if building_type == Type.TURRET else Vector2(56, 56)
			Type.MANUFACTORUM, Type.RESEARCH_SHRINE:
				if not (collision_shape.shape is RectangleShape2D): collision_shape.shape = RectangleShape2D.new()
				collision_shape.shape.size = Vector2(88, 88)

	if not multiplayer.is_server(): return

	if building_type == Type.TURRET:
		_apply_turret_upgrade()
		if gen_timer: gen_timer.stop()
		if turret_timer and turret_timer.is_stopped(): turret_timer.start()
	elif building_type == Type.GENERATOR:
		if turret_timer: turret_timer.stop()
		if gen_timer and gen_timer.is_stopped(): gen_timer.start()
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

func _process_turret_logic(delta: float):
	var target = _find_closest_enemy()
	if target:
		var target_angle = (target.global_position - global_position).angle()
		current_turret_rotation = lerp_angle(current_turret_rotation, target_angle, 3.5 * delta)
		rpc("sync_turret_rotation", current_turret_rotation)
	else:
		var base_center = Vector2.ZERO
		var core_node = get_tree().get_first_node_in_group("base_core")
		if core_node: base_center = core_node.global_position
		var outward_dir = (global_position - base_center)
		if outward_dir.length_squared() < 1.0: outward_dir = Vector2.RIGHT
		var sweep = sin(Time.get_ticks_msec() * 0.0015) * 0.8
		current_turret_rotation = lerp_angle(current_turret_rotation, outward_dir.angle() + sweep, 2.0 * delta)
		rpc("sync_turret_rotation", current_turret_rotation)

@rpc("call_local", "unreliable")
func sync_turret_rotation(rot: float):
	current_turret_rotation = rot
	if is_instance_valid(visual_spriteNode):
		if "turret_rotation" in visual_spriteNode:
			visual_spriteNode.turret_rotation = current_turret_rotation
		visual_spriteNode.queue_redraw()

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

func _on_turret_timer_timeout():
	if not multiplayer.is_server(): return
	var target = _find_closest_enemy()
	if target:
		var dir = Vector2.RIGHT.rotated(current_turret_rotation)
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node and "spawner" in main_node and main_node.spawner:
			var bullet_data = {
				"type": "bullet",
				"name": "TurretBullet_" + str(randi()),
				"position": global_position + (dir * 28.0),
				"direction": dir,
				"damage": TURRET_DAMAGE_BY_LEVEL[turret_upgrade_level]
			}
			main_node.spawner.spawn(bullet_data)

# --- BARRICADE WALLS ---

func refresh_barricade_connections():
	if building_type != Type.BARRICADE or is_preview or not is_inside_tree():
		return

	var neighbors: Array[Node2D] = []
	var neighbor_offsets: Array[Vector2] = []
	connected_neighbor_ids.clear()

	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or building == self: continue
		if "building_type" in building and int(building.building_type) == int(Type.BARRICADE):
			if "is_preview" in building and building.is_preview: continue
			var dist = global_position.distance_to(building.global_position)
			if dist <= WALL_LINK_RANGE and dist > 1.0:
				neighbors.append(building)
				connected_neighbor_ids.append(building.get_instance_id())
				if get_instance_id() < building.get_instance_id():
					neighbor_offsets.append(to_local(building.global_position))

	if visual_spriteNode and "wall_connections" in visual_spriteNode:
		visual_spriteNode.wall_connections = neighbor_offsets
		visual_spriteNode.queue_redraw()

	_update_wall_colliders(neighbors)

func _update_wall_colliders(neighbors: Array[Node2D]):
	for id in active_wall_colliders.keys():
		if not (id in connected_neighbor_ids):
			if is_instance_valid(active_wall_colliders[id]):
				active_wall_colliders[id].queue_free()
			active_wall_colliders.erase(id)

	for neighbor in neighbors:
		var n_id = neighbor.get_instance_id()
		if get_instance_id() < n_id:
			if not active_wall_colliders.has(n_id):
				var col = CollisionShape2D.new()
				col.name = "WallCollider_" + str(n_id)
				var rect_shape = RectangleShape2D.new()
				var local_target = to_local(neighbor.global_position)
				rect_shape.size = Vector2(local_target.length(), WALL_THICKNESS)
				col.shape = rect_shape
				col.position = local_target * 0.5
				col.rotation = local_target.angle()
				add_child(col)
				active_wall_colliders[n_id] = col

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
	get_tree().call_group("buildings", "_update_noosphere_connection")
	queue_free()

func _setup_turret_light():
	if has_node("TurretLight"):
		turret_light = $TurretLight
	else:
		turret_light = PointLight2D.new()
		turret_light.name = "TurretLight"
		turret_light.enabled = false
		turret_light.shadow_enabled = true
		turret_light.energy = 0.9
		var size = 256
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var center = Vector2(float(size)/2.0, float(size)/2.0)
		var radius = float(size) * 0.45
		for x in range(size):
			for y in range(size):
				var pos = Vector2(x, y)
				var dist = center.distance_to(pos)
				if dist <= radius:
					var angle_diff = abs(wrapf((pos - center).angle(), -PI, PI))
					if angle_diff <= deg_to_rad(35.0):
						img.set_pixel(x, y, Color(0.25, 0.75, 0.95, (1.0 - dist/radius) * 0.9))
		turret_light.texture = ImageTexture.create_from_image(img)
		turret_light.texture_scale = 3.5
		turret_light.offset = Vector2(size * 0.22, 0)
		add_child(turret_light)

func setup_as_preview():
	is_preview = true
	remove_from_group("buildings")
	remove_from_group("navmesh_source")
	if is_instance_valid(turret_light): turret_light.enabled = false
	if has_node("Shadow"): $Shadow.visible = false
	if has_node("HealthBar"): $HealthBar.visible = false
	if is_instance_valid(collision_shape): collision_shape.set_deferred("disabled", true)
