extends StaticBody2D

enum Type { BARRICADE = 0, GENERATOR = 1, TURRET = 2, MANUFACTORUM = 3, DISTRIBUTOR = 4, NOOSPHERE_ANTENNA = 5, RESEARCH_SHRINE = 6 }

@export var building_type: Type = Type.BARRICADE:
	set(val):
		building_type = val
		if is_node_ready():
			_apply_type_setup()

@export var max_health: int = 150
var current_health: int = 150
var health_float: float = 150.0

# --- SHIELD & NOOSPHERE STATE ---
var max_shield: float = 0.0
var current_shield: float = 0.0
var shield_recharge_timer: float = 0.0
const SHIELD_RECHARGE_DELAY: float = 6.0
const SHIELD_REGEN_RATE: float = 18.0
const NANOBOT_REPAIR_RATE: float = 3.5

var is_noosphere_connected: bool = false
const NOOSPHERE_BROADCAST_RADIUS: float = 240.0

# --- TURRET & LASER STATE ---
var current_turret_rotation: float = 0.0
var is_preview: bool = false
var turret_upgrade_level: int = 0

var turret_spec: int = 0
var flak_barrel_toggle: bool = false
var volkite_beam_timer: float = 0.0
var volkite_target_pos: Vector2 = Vector2.ZERO
var arc_chain_targets: Array[Vector2] = []
var arc_beam_timer: float = 0.0

var turret_rot_sync_timer: float = 0.0
var last_synced_turret_rot: float = 0.0

var laser_target: Node2D = null
var laser_damage_timer: float = 0.0

# --- BARRICADE WALL LINK CONSTANTS ---
const WALL_LINK_RANGE: float = 95.0
const WALL_THICKNESS: float = 14.0
var connected_neighbor_ids: Array[int] = []
var active_wall_colliders: Dictionary = {}
var is_gate: bool = false
var is_gate_open: bool = false
var gate_check_timer: float = 0.0
const GATE_SENSOR_RADIUS: float = 55.0

var noosphere_check_timer: float = 0.0
var turret_target_scan_timer: float = 0.0
var cached_target_enemy: Node2D = null

@onready var visual_spriteNode = get_node_or_null("VisualBuildingSprite")
@onready var turret_timer: Timer = get_node_or_null("TurretTimer")
@onready var gen_timer: Timer = get_node_or_null("GeneratorTimer")
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var health_bar: Node2D = get_node_or_null("HealthBar")

func _ready():
	add_to_group("buildings")
	add_to_group("navmesh_source")
	health_float = float(current_health)

	if has_node("TurretLight"):
		get_node("TurretLight").queue_free()

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

	noosphere_check_timer += delta
	if noosphere_check_timer >= 0.25:
		noosphere_check_timer = 0.0
		_update_noosphere_connection()

	if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
		_process_server_buffs(delta)
		if building_type == Type.TURRET:
			_process_turret_logic(delta)
			_process_turret_laser(delta)

	if is_gate and ((not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()):
		gate_check_timer += delta
		if gate_check_timer >= 0.08:
			gate_check_timer = 0.0
			_process_gate_sensor()

func _process_gate_sensor():
	var should_open = false
	var friendlies: Array = get_tree().get_nodes_in_group("players")
	friendlies.append_array(get_tree().get_nodes_in_group("bodyguards"))
	friendlies.append_array(get_tree().get_nodes_in_group("ServoSkull"))

	for f in friendlies:
		if is_instance_valid(f) and global_position.distance_to(f.global_position) <= GATE_SENSOR_RADIUS:
			should_open = true
			break

	if should_open != is_gate_open:
		is_gate_open = should_open
		rpc("sync_gate_state", is_gate_open)

@rpc("call_local", "reliable")
func sync_gate_state(open_state: bool):
	is_gate_open = open_state

	for col in active_wall_colliders.values():
		if is_instance_valid(col):
			col.set_deferred("disabled", is_gate_open)

	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and building != self and "active_wall_colliders" in building:
			if building.active_wall_colliders.has(get_instance_id()):
				var neighbor_col = building.active_wall_colliders[get_instance_id()]
				if is_instance_valid(neighbor_col):
					neighbor_col.set_deferred("disabled", is_gate_open)

	AudioManager.play_sfx("gate_toggle", global_position, -3.0, 1.25 if open_state else 0.8)

	if visual_spriteNode and "is_gate_open" in visual_spriteNode:
		visual_spriteNode.is_gate_open = is_gate_open
		visual_spriteNode.queue_redraw()

func try_upgrade_to_gate() -> bool:
	if not multiplayer.is_server() or building_type != Type.BARRICADE or is_gate:
		return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node:
		return false

	if main_node.scrap_amount >= GameData.GATE_UPGRADE_SCRAP and main_node.requisition_amount >= GameData.GATE_UPGRADE_REQ:
		main_node.scrap_amount -= GameData.GATE_UPGRADE_SCRAP
		main_node.requisition_amount -= GameData.GATE_UPGRADE_REQ
		main_node.rpc("sync_resources", main_node.scrap_amount, main_node.requisition_amount)
		rpc("sync_gate_upgrade")
		return true
	return false

@rpc("call_local", "reliable")
func sync_gate_upgrade():
	is_gate = true
	if visual_spriteNode and "is_gate" in visual_spriteNode:
		visual_spriteNode.is_gate = true
		visual_spriteNode.queue_redraw()

func _update_noosphere_connection():
	var was_connected = is_noosphere_connected
	is_noosphere_connected = false

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

	if is_noosphere_connected and main_node.get("tech_shields_unlocked"):
		max_shield = max_health * 0.4
		if current_shield <= 0.0:
			current_shield = max_shield
	else:
		max_shield = 0.0
		current_shield = 0.0

	if is_instance_valid(visual_spriteNode):
		if "has_spikes" in visual_spriteNode:
			visual_spriteNode.has_spikes = main_node.get("tech_spikes_cover_unlocked") if main_node else false
		if "has_electro_mesh" in visual_spriteNode:
			visual_spriteNode.has_electro_mesh = is_noosphere_connected and (main_node.get("tech_electro_barricades_unlocked") if main_node else false)
		visual_spriteNode.queue_redraw()

	update_ui()

func _process_server_buffs(delta: float):
	var main_node = get_tree().get_first_node_in_group("main")
	var tech_shields = main_node.get("tech_shields_unlocked") if main_node else false
	var tech_nanobots = main_node.get("tech_nanobots_unlocked") if main_node else false

	if shield_recharge_timer > 0.0:
		shield_recharge_timer -= delta
	else:
		if is_noosphere_connected and tech_shields and current_shield < max_shield:
			var prev_shield = int(current_shield)
			current_shield = minf(max_shield, current_shield + SHIELD_REGEN_RATE * delta)
			if int(current_shield) != prev_shield:
				rpc("sync_shield", current_shield)

		if is_noosphere_connected and tech_nanobots and current_health < max_health:
			health_float = minf(float(max_health), health_float + NANOBOT_REPAIR_RATE * delta)
			var new_int_health = int(health_float)
			if new_int_health != current_health:
				current_health = new_int_health
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
				laser_target.take_damage(4)

@rpc("call_local", "unreliable")
func sync_laser_target(target_name: String):
	if target_name.is_empty():
		laser_target = null
	else:
		laser_target = get_parent().get_node_or_null(target_name)
	if visual_spriteNode and "laser_target_node" in visual_spriteNode:
		visual_spriteNode.laser_target_node = laser_target
		visual_spriteNode.queue_redraw()

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO):
	if is_preview or not multiplayer.is_server():
		return

	shield_recharge_timer = SHIELD_RECHARGE_DELAY
	var damage_remaining = float(amount)

	if current_shield > 0.0:
		var shield_dmg = minf(current_shield, damage_remaining)
		current_shield -= shield_dmg
		damage_remaining -= shield_dmg
		rpc("sync_shield", current_shield)

	if damage_remaining > 0.0:
		var new_hp = max(0, current_health - int(damage_remaining))
		health_float = float(new_hp)
		rpc("sync_building_health", new_hp)

	# --- BARRICADE TECH RETALIATION ---
	if building_type == Type.BARRICADE and multiplayer.is_server():
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node:
			var has_spikes = main_node.get("tech_spikes_cover_unlocked")
			var has_electro = is_noosphere_connected and main_node.get("tech_electro_barricades_unlocked")
			
			if has_spikes or has_electro:
				var attackers = get_tree().get_nodes_in_group("enemies")
				for enemy in attackers:
					if is_instance_valid(enemy) and global_position.distance_to(enemy.global_position) <= 75.0:
						if has_spikes and enemy.has_method("take_damage"):
							enemy.take_damage(18, (enemy.global_position - global_position).normalized() * 120.0)
						if has_electro and enemy.has_method("take_damage"):
							enemy.take_damage(12)
							enemy.set("knockback_velocity", (enemy.global_position - global_position).normalized() * 80.0)

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

func try_upgrade_distributor() -> bool:
	if not multiplayer.is_server() or building_type != Type.DISTRIBUTOR:
		return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not main_node.has_method("spend_requisition"):
		return false
	if not main_node.spend_requisition(GameData.ANTENNA_UPGRADE_REQ):
		return false
	rpc("sync_distributor_upgrade")
	return true

@rpc("call_local", "reliable")
func sync_distributor_upgrade():
	building_type = Type.NOOSPHERE_ANTENNA
	_apply_type_setup()
	get_tree().call_group("buildings", "_update_noosphere_connection")

func try_purchase_research(tech_index: int) -> bool:
	if not multiplayer.is_server() or building_type != Type.RESEARCH_SHRINE:
		return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node:
		return false

	if tech_index < 0 or tech_index >= GameData.TECH_DATA.size():
		return false

	var tech_cost = GameData.TECH_DATA[tech_index].cost
	if not main_node.spend_requisition(tech_cost):
		return false

	main_node.unlock_tech(tech_index)
	return true

func try_upgrade_turret() -> bool:
	if not multiplayer.is_server() or building_type != Type.TURRET:
		return false
	if turret_upgrade_level >= GameData.TURRET_UPGRADE_COSTS.size():
		return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not main_node.has_method("spend_requisition"):
		return false
	var cost: int = GameData.TURRET_UPGRADE_COSTS[turret_upgrade_level]
	if not main_node.spend_requisition(cost):
		return false
	rpc("sync_turret_upgrade", turret_upgrade_level + 1)
	return true

func try_specialize_turret(spec_id: int) -> bool:
	if not multiplayer.is_server() or building_type != Type.TURRET:
		return false
	if turret_upgrade_level < 3 or turret_spec != GameData.TurretSpec.NONE:
		return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not main_node.has_method("spend_requisition"):
		return false
	if not main_node.spend_requisition(GameData.TURRET_SPEC_REQ_COST):
		return false

	rpc("sync_turret_spec", spec_id)
	return true

@rpc("call_local", "reliable")
func sync_turret_spec(new_spec: int) -> void:
	turret_spec = new_spec
	_apply_turret_upgrade()
	AudioManager.play_sfx("orbital_strike", global_position, -2.0, 1.4)

@rpc("call_local", "reliable")
func sync_turret_upgrade(new_level: int) -> void:
	turret_upgrade_level = clampi(new_level, 0, GameData.TURRET_DAMAGE_BY_LEVEL.size() - 1)
	_apply_turret_upgrade()

func _apply_turret_upgrade() -> void:
	if is_instance_valid(turret_timer):
		if turret_spec != GameData.TurretSpec.NONE:
			var spec_info = GameData.TURRET_SPEC_INFO[turret_spec]
			turret_timer.wait_time = spec_info.fire_interval
		else:
			turret_timer.wait_time = GameData.TURRET_FIRE_INTERVALS[turret_upgrade_level]

	if is_instance_valid(visual_spriteNode):
		if "turret_upgrade_level" in visual_spriteNode:
			visual_spriteNode.turret_upgrade_level = turret_upgrade_level
		if "turret_spec" in visual_spriteNode:
			visual_spriteNode.turret_spec = turret_spec
		visual_spriteNode.queue_redraw()

func _apply_type_setup():
	var info = GameData.STRUCTURE_INFO.get(int(building_type), null)
	if info:
		max_health = info["max_hp"]
	else:
		max_health = 100

	health_float = float(max_health)

	if is_instance_valid(visual_spriteNode):
		if "type" in visual_spriteNode:
			# Shift building_type index by +1 since VisualBuildingSprite includes MAIN_BASE at 0
			visual_spriteNode.type = int(building_type) + 1
		visual_spriteNode.queue_redraw()

	if is_instance_valid(collision_shape) and collision_shape.shape:
		match building_type:
			Type.DISTRIBUTOR, Type.NOOSPHERE_ANTENNA:
				if not (collision_shape.shape is CircleShape2D): collision_shape.shape = CircleShape2D.new()
				collision_shape.shape.radius = 7.0 # Compact solid bollard post
			Type.BARRICADE:
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
	turret_target_scan_timer += delta
	if turret_target_scan_timer >= 0.1:
		turret_target_scan_timer = 0.0
		var max_range = GameData.TURRET_RANGE_BY_LEVEL[turret_upgrade_level]
		if not is_instance_valid(cached_target_enemy) or global_position.distance_to(cached_target_enemy.global_position) > max_range:
			cached_target_enemy = _find_closest_enemy()

	if is_instance_valid(cached_target_enemy):
		# 1. Predictive Ballistic Lead (aims where the enemy is heading)
		var enemy_vel = cached_target_enemy.velocity if "velocity" in cached_target_enemy else Vector2.ZERO
		var dist = global_position.distance_to(cached_target_enemy.global_position)
		var bullet_speed = 550.0
		var lead_time = clampf(dist / bullet_speed, 0.0, 0.6)
		var predicted_pos = cached_target_enemy.global_position + (enemy_vel * lead_time)

		var target_angle = (predicted_pos - global_position).angle()
		var track_speed = 6.5 if is_noosphere_connected else 5.0 # Noosphere tracking buff
		current_turret_rotation = lerp_angle(current_turret_rotation, target_angle, track_speed * delta)
	else:
		# Idle radar sweep
		var base_center = Vector2.ZERO
		var core_node = get_tree().get_first_node_in_group("base")
		if core_node: base_center = core_node.global_position
		var outward_dir = (global_position - base_center)
		if outward_dir.length_squared() < 1.0: outward_dir = Vector2.RIGHT
		var sweep = sin(Time.get_ticks_msec() * 0.0015) * 0.8
		current_turret_rotation = lerp_angle(current_turret_rotation, outward_dir.angle() + sweep, 2.0 * delta)

	# 2. Throttled Network Sync (saves bandwidth)
	turret_rot_sync_timer += delta
	if turret_rot_sync_timer >= 0.06:
		turret_rot_sync_timer = 0.0
		if abs(angle_difference(last_synced_turret_rot, current_turret_rotation)) > 0.025:
			last_synced_turret_rot = current_turret_rotation
			rpc("sync_turret_rotation", current_turret_rotation)

@rpc("call_local", "unreliable")
func sync_turret_rotation(rot: float):
	current_turret_rotation = rot
	if is_instance_valid(visual_spriteNode):
		visual_spriteNode.turret_rotation = current_turret_rotation
		visual_spriteNode.queue_redraw()

func _find_closest_enemy() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var closest_target = null
	var closest_dist = GameData.TURRET_RANGE_BY_LEVEL[turret_upgrade_level]
	for enemy in enemies:
		if is_instance_valid(enemy):
			var dist = global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_target = enemy
	return closest_target

func _on_turret_timer_timeout():
	if not multiplayer.is_server(): return
	
	var max_range = GameData.TURRET_SPEC_INFO[turret_spec].range if turret_spec != GameData.TurretSpec.NONE else GameData.TURRET_RANGE_BY_LEVEL[turret_upgrade_level]
	if not is_instance_valid(cached_target_enemy) or global_position.distance_to(cached_target_enemy.global_position) > max_range:
		cached_target_enemy = _find_closest_enemy()

	if is_instance_valid(cached_target_enemy):
		var enemy_vel = cached_target_enemy.velocity if "velocity" in cached_target_enemy else Vector2.ZERO
		var dist = global_position.distance_to(cached_target_enemy.global_position)
		var bullet_speed = 550.0
		var lead_time = clampf(dist / bullet_speed, 0.0, 0.6)
		var predicted_pos = cached_target_enemy.global_position + (enemy_vel * lead_time)
		var target_angle = (predicted_pos - global_position).angle()

		# Bore alignment check
		var angle_diff = abs(angle_difference(current_turret_rotation, target_angle))
		if angle_diff <= deg_to_rad(14.0):
			var dir = Vector2.RIGHT.rotated(current_turret_rotation)
			var main_node = get_tree().get_first_node_in_group("main")
			if not (main_node and "spawner" in main_node and main_node.spawner): return

			match turret_spec:
				GameData.TurretSpec.NONE:
					# Standard Rapid Anti-Chaff Dual Stubber
					main_node.spawner.spawn({
						"type": "bullet",
						"name": "TurretBullet_" + str(randi()),
						"position": global_position + (dir * 24.0),
						"direction": dir,
						"damage": GameData.TURRET_DAMAGE_BY_LEVEL[turret_upgrade_level]
					})
					AudioManager.play_sfx("laser", global_position, -4.0)

				GameData.TurretSpec.COGNIS_FLAK:
					# Hyper-RPM Gatling Alternating Tracer
					flak_barrel_toggle = not flak_barrel_toggle
					var offset = dir.orthogonal() * (4.5 if flak_barrel_toggle else -4.5)
					var spread_dir = dir.rotated(randf_range(-0.06, 0.06))
					main_node.spawner.spawn({
						"type": "bullet",
						"name": "FlakBullet_" + str(randi()),
						"position": global_position + (dir * 24.0) + offset,
						"direction": spread_dir,
						"damage": GameData.TURRET_SPEC_INFO[turret_spec].damage
					})
					AudioManager.play_sfx("radium_shot", global_position, -2.0, 1.4)

				GameData.TurretSpec.VOLKITE_CULVERIN:
					# Piercing Thermal Ray (penetrates lines of enemies)
					var ray_end = global_position + (dir * 380.0)
					rpc("trigger_volkite_ray_fx", ray_end)
					_execute_volkite_piercing_ray(global_position, ray_end)

				GameData.TurretSpec.ARC_BLASTER:
					# Chain Lightning Arc
					_execute_arc_chain_lightning(cached_target_enemy)

func _execute_volkite_piercing_ray(start_pos: Vector2, end_pos: Vector2):
	AudioManager.play_sfx("orbital_strike", global_position, 0.0, 1.8)
	var space = get_world_2d().direct_space_state
	var shape = SegmentShape2D.new()
	shape.a = start_pos
	shape.b = end_pos

	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collide_with_bodies = true
	var results = space.intersect_shape(q, 32)
	for hit in results:
		var body = hit.collider
		if is_instance_valid(body) and (body.is_in_group("enemies") or body.is_in_group("objectives")):
			if body.has_method("take_damage"):
				body.take_damage(GameData.TURRET_SPEC_INFO[GameData.TurretSpec.VOLKITE_CULVERIN].damage)

func _execute_arc_chain_lightning(primary_target: Node2D):
	AudioManager.play_sfx("gate_toggle", global_position, 2.0, 1.6)
	var chain_points: Array[Vector2] = [primary_target.global_position]
	
	if primary_target.has_method("take_damage"):
		primary_target.take_damage(GameData.TURRET_SPEC_INFO[GameData.TurretSpec.ARC_BLASTER].damage)

	# Find up to 2 chained secondary enemies within 130px
	var enemies = get_tree().get_nodes_in_group("enemies")
	var chained_count = 0
	for e in enemies:
		if is_instance_valid(e) and e != primary_target and chained_count < 2:
			if primary_target.global_position.distance_to(e.global_position) <= 130.0:
				chain_points.append(e.global_position)
				if e.has_method("take_damage"):
					e.take_damage(30, (e.global_position - primary_target.global_position).normalized() * 140.0)
				chained_count += 1

	rpc("trigger_arc_lightning_fx", chain_points)

@rpc("call_local", "unreliable")
func trigger_volkite_ray_fx(end_pos: Vector2):
	if is_instance_valid(visual_spriteNode):
		visual_spriteNode.volkite_target_pos = to_local(end_pos)
		visual_spriteNode.volkite_beam_timer = 0.22
		visual_spriteNode.queue_redraw()

@rpc("call_local", "unreliable")
func trigger_arc_lightning_fx(points: Array):
	if is_instance_valid(visual_spriteNode):
		var local_points: Array[Vector2] = []
		for pt in points:
			local_points.append(to_local(pt))
		visual_spriteNode.arc_chain_targets = local_points
		visual_spriteNode.arc_beam_timer = 0.20
		visual_spriteNode.queue_redraw()

func refresh_barricade_connections():
	if building_type != Type.BARRICADE or is_preview or not is_inside_tree():
		return

	var candidates: Array[Dictionary] = []
	var neighbor_offsets: Array[Vector2] = []
	connected_neighbor_ids.clear()

	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or building == self: continue
		if "building_type" in building and int(building.building_type) == int(Type.BARRICADE):
			if "is_preview" in building and building.is_preview: continue
			var dist = global_position.distance_to(building.global_position)
			if dist <= WALL_LINK_RANGE and dist > 1.0:
				candidates.append({"node": building, "dist": dist})

	# Sort by distance and only connect to the 2 closest neighboring barricades!
	candidates.sort_custom(func(a, b): return a.dist < b.dist)
	var max_conns = 2
	var selected_neighbors: Array[Node2D] = []

	for i in range(min(candidates.size(), max_conns)):
		var neighbor: Node2D = candidates[i].node
		selected_neighbors.append(neighbor)
		connected_neighbor_ids.append(neighbor.get_instance_id())
		if get_instance_id() < neighbor.get_instance_id():
			neighbor_offsets.append(to_local(neighbor.global_position))

	if visual_spriteNode and "wall_connections" in visual_spriteNode:
		visual_spriteNode.wall_connections = neighbor_offsets
		visual_spriteNode.queue_redraw()

	_update_wall_colliders(selected_neighbors)

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

func setup_as_preview():
	is_preview = true
	remove_from_group("buildings")
	remove_from_group("navmesh_source")
	if has_node("Shadow"): $Shadow.visible = false
	if has_node("HealthBar"): $HealthBar.visible = false
	if is_instance_valid(collision_shape): collision_shape.set_deferred("disabled", true)
