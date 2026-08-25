extends StaticBody2D
class_name Building

enum Type { 
	BARRICADE = 0, 
	GENERATOR = 1, 
	TURRET = 2, 
	MANUFACTORUM = 3, 
	DISTRIBUTOR = 4, 
	NOOSPHERE_ANTENNA = 5, 
	RESEARCH_SHRINE = 6,
	CYBERNETICA_FORGE = 7
}

@export var building_type: Type = Type.BARRICADE:
	set(val):
		building_type = val
		if is_node_ready():
			_apply_type_setup()

@export var max_health: int = 150
var current_health: int = 150
var health_float: float = 150.0

var max_shield: float = 0.0
var current_shield: float = 0.0
var shield_recharge_timer: float = 0.0
const SHIELD_RECHARGE_DELAY: float = 6.0
const SHIELD_REGEN_RATE: float = 18.0
const NANOBOT_REPAIR_RATE: float = 3.5

var is_noosphere_connected: bool = false
const NOOSPHERE_BROADCAST_RADIUS: float = 240.0

var foundry_timer: float = 0.0
const FOUNDRY_INTERVAL: float = 4.0
const FOUNDRY_SCRAP_YIELD: int = 5

var production_queue: Array[int] = []
var production_timer: float = 0.0
var rally_point_world: Vector2 = Vector2.ZERO

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
	if is_preview:
		setup_as_preview()
		_apply_type_setup()
		return

	add_to_group("buildings")
	add_to_group("navmesh_source")
	health_float = float(current_health)

	_apply_type_setup()
	
	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)
	update_ui()

	if building_type == Type.CYBERNETICA_FORGE and rally_point_world == Vector2.ZERO:
		var base_node = get_tree().get_first_node_in_group("base")
		if is_instance_valid(base_node):
			rally_point_world = base_node.global_position + Vector2(0, 60)

	if turret_timer and not turret_timer.timeout.is_connected(_on_turret_timer_timeout):
		turret_timer.timeout.connect(_on_turret_timer_timeout)
	if gen_timer and not gen_timer.timeout.is_connected(_on_gen_timer_timeout):
		gen_timer.timeout.connect(_on_gen_timer_timeout)

	_setup_building_light()
	if building_type == Type.BARRICADE:
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
		if building_type == Type.MANUFACTORUM:
			foundry_timer += delta
			if foundry_timer >= FOUNDRY_INTERVAL:
				foundry_timer = 0.0
				_produce_foundry_scrap()
		elif building_type == Type.CYBERNETICA_FORGE:
			_process_cybernetica_manufacturing(delta)

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



func _setup_building_light() -> void:
	if is_preview: return

	var existing = get_node_or_null("BuildingPointLight")
	if existing: existing.queue_free()

	var light: PointLight2D = null

	match building_type:
		Type.GENERATOR:
			light = LightUtils.create_point_light(Color(0.20, 0.88, 1.0), 1.3, 2.6)
		Type.MANUFACTORUM:
			light = LightUtils.create_point_light(Color(1.0, 0.55, 0.15), 1.4, 2.8)
		Type.TURRET:
			# Adapt light color based on weapon specialization
			match turret_spec:
				GameData.TurretSpec.VOLKITE_CULVERIN:
					light = LightUtils.create_point_light(Color(1.0, 0.25, 0.15), 1.2, 2.4)
				GameData.TurretSpec.ARC_BLASTER:
					light = LightUtils.create_point_light(Color(0.20, 0.88, 1.0), 1.3, 2.6)
				GameData.TurretSpec.COGNIS_FLAK:
					light = LightUtils.create_point_light(Color(1.0, 0.75, 0.25), 1.0, 2.2)
				_:
					var glow_col = Color(0.20, 0.88, 1.0) if is_noosphere_connected else Color(1.0, 0.75, 0.25)
					light = LightUtils.create_point_light(glow_col, 0.8, 1.8)
		Type.DISTRIBUTOR:
			light = LightUtils.create_point_light(Color(1.0, 0.72, 0.15), 0.8, 1.8)
		Type.NOOSPHERE_ANTENNA:
			light = LightUtils.create_point_light(Color(0.20, 0.88, 1.0), 1.1, 2.4)
		Type.RESEARCH_SHRINE:
			light = LightUtils.create_point_light(Color(0.25, 0.95, 0.40), 0.9, 2.2)
		Type.CYBERNETICA_FORGE:
			light = LightUtils.create_point_light(Color(0.20, 0.88, 1.0), 1.4, 3.0)
		Type.BARRICADE:
			if is_gate:
				light = LightUtils.create_point_light(Color(0.20, 0.88, 1.0), 0.6, 1.4)

	if light:
		light.name = "BuildingPointLight"
		light.position = Vector2.ZERO
		add_child(light)

func _produce_foundry_scrap():
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.has_method("add_scrap"):
		main_node.add_scrap(FOUNDRY_SCRAP_YIELD)
		rpc("trigger_foundry_smoke_fx")

@rpc("call_local", "unreliable")
func trigger_foundry_smoke_fx():
	AudioManager.play_sfx("building_place", global_position, -6.0, 1.6)
	var label = Label.new()
	label.script = load("res://DamageNumber.gd")
	label.global_position = global_position + Vector2(-15, -34)
	get_tree().current_scene.add_child(label)
	label.text = "+%d Scrap" % FOUNDRY_SCRAP_YIELD
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.95, 0.75, 0.20)
	label.label_settings.font_size = 13

func _process_cybernetica_manufacturing(delta: float):
	if production_queue.is_empty():
		production_timer = 0.0
		return

	var current_unit_id = production_queue.front()
	var unit_data = GameData.COHORT_UNITS.get(current_unit_id, {})
	var build_time = unit_data.get("build_time", 5.0)

	production_timer += delta
	if production_timer >= build_time:
		production_timer = 0.0
		production_queue.pop_front()
		_spawn_manufactured_unit(current_unit_id)
		if multiplayer.has_multiplayer_peer():
			rpc("sync_production_state", production_queue.duplicate(), production_timer)

func _spawn_manufactured_unit(unit_type_id: int):
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return

	var spawn_pos = global_position + Vector2(0, 36)
	var spawn_type = "cohort_infantry"
	
	if unit_type_id == GameData.CohortUnitType.KATAPHRON:
		spawn_type = "kataphron_unit"
	elif unit_type_id == GameData.CohortUnitType.KASTELAN:
		spawn_type = "kastelan_robot"

	var spawn_data = {
		"type": spawn_type,
		"name": "CohortUnit_" + str(randi()),
		"position": spawn_pos,
		"unit_type": unit_type_id,
		"owner_id": 1
	}

	var unit_node: Node2D = null
	if main_node.has_method("spawn_entity"):
		unit_node = main_node.spawn_entity(spawn_data) as Node2D
	elif main_node.spawner and multiplayer.has_multiplayer_peer():
		unit_node = main_node.spawner.spawn(spawn_data) as Node2D
	else:
		unit_node = main_node._custom_spawner(spawn_data) as Node2D
		if is_instance_valid(unit_node):
			main_node.add_child(unit_node)

	if is_instance_valid(unit_node):
		var base_node = get_tree().get_first_node_in_group("base")
		var fallback_target = base_node.global_position + Vector2(0, 60) if is_instance_valid(base_node) else (global_position + Vector2(0, 60))
		var target_loc = rally_point_world if rally_point_world != Vector2.ZERO else fallback_target

		if unit_node.has_method("set_initial_rally"):
			unit_node.set_initial_rally(target_loc)
		elif unit_node.has_method("rts_move_to"):
			unit_node.rts_move_to(target_loc, true)

func try_queue_unit(unit_id: int) -> bool:
	if building_type != Type.CYBERNETICA_FORGE: return false
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return false
	if production_queue.size() >= 5: return false

	var unit_data = GameData.COHORT_UNITS.get(unit_id, {})
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return false

	var current_pop = main_node.get_cohort_population() if main_node.has_method("get_cohort_population") else 0
	if current_pop + unit_data.get("pop", 1) > GameData.BASE_COHORT_CAP: return false
	if main_node.scrap_amount < unit_data.get("scrap", 0) or main_node.requisition_amount < unit_data.get("req", 0): return false

	main_node.scrap_amount -= unit_data.get("scrap", 0)
	main_node.requisition_amount -= unit_data.get("req", 0)
	
	production_queue.append(unit_id)
	
	if multiplayer.has_multiplayer_peer():
		main_node.rpc("sync_resources", main_node.scrap_amount, main_node.requisition_amount)
		rpc("sync_production_state", production_queue.duplicate(), production_timer)
	
	return true

@rpc("call_local", "reliable")
func sync_health(new_hp: int) -> void:
	current_health = new_hp
	var hb = get_node_or_null("HealthBar")
	if hb and hb.has_method("update_health"):
		hb.update_health(current_health, max_health)

@rpc("call_local", "reliable")
func sync_production_state(queue_data: Array, timer_val: float):
	var incoming = queue_data.duplicate()
	production_queue.clear()
	for item in incoming:
		production_queue.append(int(item))
	production_timer = timer_val

@rpc("call_local", "reliable")
func set_rally_point(world_pos: Vector2):
	rally_point_world = world_pos
	queue_redraw()

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
	if (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()) or building_type != Type.BARRICADE or is_gate:
		return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node:
		return false

	if main_node.scrap_amount >= GameData.GATE_UPGRADE_SCRAP and main_node.requisition_amount >= GameData.GATE_UPGRADE_REQ:
		main_node.scrap_amount -= GameData.GATE_UPGRADE_SCRAP
		main_node.requisition_amount -= GameData.GATE_UPGRADE_REQ
		if multiplayer.has_multiplayer_peer():
			main_node.rpc("sync_resources", main_node.scrap_amount, main_node.requisition_amount)
			rpc("sync_gate_upgrade")
		else:
			sync_gate_upgrade()
		return true
	return false

@rpc("call_local", "reliable")
func sync_gate_upgrade():
	is_gate = true
	_setup_building_light()
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
	if not main_node: return

	# STC Master-Core: +75 Bonus Fortification HP
	if main_node.get("stc_aegis_core_unlocked"):
		var info = GameData.STRUCTURE_INFO.get(int(building_type), null)
		var base_hp = info["max_hp"] if info else 100
		max_health = base_hp + 75

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
			if int(current_shield) != prev_shield and multiplayer.has_multiplayer_peer():
				rpc("sync_shield", current_shield)

		if is_noosphere_connected and tech_nanobots and current_health < max_health:
			health_float = minf(float(max_health), health_float + NANOBOT_REPAIR_RATE * delta)
			var new_int_health = int(health_float)
			if new_int_health != current_health:
				current_health = new_int_health
				if multiplayer.has_multiplayer_peer():
					rpc("sync_building_health", current_health)

func _process_turret_laser(delta: float):
	var main_node = get_tree().get_first_node_in_group("main")
	var tech_lasers = main_node.get("tech_lasers_unlocked") if main_node else false

	if not is_noosphere_connected or not tech_lasers:
		if laser_target != null:
			laser_target = null
			if multiplayer.has_multiplayer_peer():
				rpc("sync_laser_target", "")
		return

	var target = _find_closest_enemy()
	if target != laser_target:
		laser_target = target
		if multiplayer.has_multiplayer_peer():
			rpc("sync_laser_target", target.name if target else "")

	if is_instance_valid(laser_target):
		laser_damage_timer += delta
		if laser_damage_timer >= 0.1:
			laser_damage_timer = 0.0
			if laser_target.has_method("take_damage"):
				laser_target.take_damage(4)

func _calculate_target_weight(enemy: Node2D) -> float:
	var dist = global_position.distance_to(enemy.global_position)
	var weight = 1000.0 - dist
	
	if enemy.get("has_telemetry_mark"):
		weight += 500.0 # Prioritize Auspex painted targets
		
	match turret_spec:
		GameData.TurretSpec.COGNIS_FLAK:
			if enemy.type in [Enemy.EnemyType.STORMBOY, Enemy.EnemyType.GRETCHIN]:
				weight += 400.0
		GameData.TurretSpec.VOLKITE_CULVERIN:
			if enemy.type == Enemy.EnemyType.NOB or enemy.is_in_group("objectives"):
				weight += 600.0
		GameData.TurretSpec.ARC_BLASTER:
			if enemy.type in [Enemy.EnemyType.SQUIG, Enemy.EnemyType.ORK_BOY]:
				weight += 300.0
	return weight

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
	if is_preview or (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()): return

	shield_recharge_timer = SHIELD_RECHARGE_DELAY
	var damage_remaining = float(amount)

	if current_shield > 0.0:
		var shield_dmg = minf(current_shield, damage_remaining)
		current_shield -= shield_dmg
		damage_remaining -= shield_dmg
		if multiplayer.has_multiplayer_peer():
			rpc("sync_shield", current_shield)

	if damage_remaining > 0.0:
		var new_hp = max(0, current_health - int(damage_remaining))
		health_float = float(new_hp)
		if multiplayer.has_multiplayer_peer():
			rpc("sync_building_health", new_hp)
		else:
			sync_building_health(new_hp)

	if building_type == Type.BARRICADE:
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
	if current_health <= 0:
		destroy_building()

func update_ui():
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
		if health_bar.has_method("update_shield"):
			health_bar.update_shield(int(current_shield), int(max_shield))

func try_upgrade_distributor() -> bool:
	if (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()) or building_type != Type.DISTRIBUTOR: return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not main_node.has_method("spend_requisition"): return false
	if not main_node.spend_requisition(GameData.ANTENNA_UPGRADE_REQ): return false
	if multiplayer.has_multiplayer_peer():
		rpc("sync_distributor_upgrade")
	else:
		sync_distributor_upgrade()
	return true

@rpc("call_local", "reliable")
func sync_distributor_upgrade():
	building_type = Type.NOOSPHERE_ANTENNA
	_apply_type_setup()
	_setup_building_light()
	get_tree().call_group("buildings", "_update_noosphere_connection")

func try_purchase_research(tech_index: int) -> bool:
	if (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()) or building_type != Type.RESEARCH_SHRINE: return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return false
	if tech_index < 0 or tech_index >= GameData.TECH_DATA.size(): return false

	var tech_cost = GameData.TECH_DATA[tech_index].cost
	if not main_node.spend_requisition(tech_cost): return false

	main_node.unlock_tech(tech_index)
	return true

func try_upgrade_turret() -> bool:
	if (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()) or building_type != Type.TURRET: return false
	if turret_upgrade_level >= GameData.TURRET_UPGRADE_COSTS.size(): return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not main_node.has_method("spend_requisition"): return false
	var cost: int = GameData.TURRET_UPGRADE_COSTS[turret_upgrade_level]
	if not main_node.spend_requisition(cost): return false
	if multiplayer.has_multiplayer_peer():
		rpc("sync_turret_upgrade", turret_upgrade_level + 1)
	else:
		sync_turret_upgrade(turret_upgrade_level + 1)
	return true

func try_specialize_turret(spec_id: int) -> bool:
	if (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()) or building_type != Type.TURRET: return false
	if turret_upgrade_level < 3 or turret_spec != GameData.TurretSpec.NONE: return false
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not main_node.has_method("spend_requisition"): return false
	if not main_node.spend_requisition(GameData.TURRET_SPEC_REQ_COST): return false

	if multiplayer.has_multiplayer_peer():
		rpc("sync_turret_spec", spec_id)
	else:
		sync_turret_spec(spec_id)
	return true

@rpc("call_local", "reliable")
func sync_turret_spec(new_spec: int) -> void:
	turret_spec = new_spec
	_apply_turret_upgrade()
	_setup_building_light()
	AudioManager.play_sfx("orbital_strike", global_position, -2.0, 1.4)

@rpc("call_local", "reliable")
func sync_turret_upgrade(new_level: int) -> void:
	turret_upgrade_level = clampi(new_level, 0, GameData.TURRET_DAMAGE_BY_LEVEL.size() - 1)
	_apply_turret_upgrade()
	_setup_building_light()

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
	max_health = info["max_hp"] if info else 100
	health_float = float(max_health)

	# ALWAYS update the visual sprite type, even in preview mode!
	if not visual_spriteNode:
		visual_spriteNode = get_node_or_null("VisualBuildingSprite")
	
	if is_instance_valid(visual_spriteNode):
		if "type" in visual_spriteNode:
			visual_spriteNode.type = int(building_type) + 1
		if "is_preview" in visual_spriteNode:
			visual_spriteNode.is_preview = is_preview
		visual_spriteNode.queue_redraw()

	# If this is a preview, stop here (do not set up real collisions or timers)
	if is_preview:
		return

	if is_instance_valid(collision_shape) and collision_shape.shape:
		match building_type:
			Type.DISTRIBUTOR, Type.NOOSPHERE_ANTENNA:
				if not (collision_shape.shape is CircleShape2D): collision_shape.shape = CircleShape2D.new()
				collision_shape.shape.radius = 7.0
			Type.BARRICADE:
				if not (collision_shape.shape is CircleShape2D): collision_shape.shape = CircleShape2D.new()
				collision_shape.shape.radius = 8.0
			Type.TURRET:
				if not (collision_shape.shape is CircleShape2D): collision_shape.shape = CircleShape2D.new()
				collision_shape.shape.radius = 12.0
			Type.GENERATOR:
				if not (collision_shape.shape is RectangleShape2D): collision_shape.shape = RectangleShape2D.new()
				collision_shape.shape.size = Vector2(32, 32)
			Type.MANUFACTORUM, Type.RESEARCH_SHRINE:
				if not (collision_shape.shape is RectangleShape2D): collision_shape.shape = RectangleShape2D.new()
				collision_shape.shape.size = Vector2(40, 40)
			Type.CYBERNETICA_FORGE:
				if not (collision_shape.shape is RectangleShape2D): collision_shape.shape = RectangleShape2D.new()
				collision_shape.shape.size = Vector2(48, 48)

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return

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
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.has_method("add_requisition"):
		main_node.add_requisition(2)
		if multiplayer.has_multiplayer_peer():
			rpc("trigger_generator_pulse")
		else:
			trigger_generator_pulse()

@rpc("call_local", "reliable")
func trigger_generator_pulse():
	if is_instance_valid(visual_spriteNode) and visual_spriteNode.has_method("pulse_generator"):
		visual_spriteNode.pulse_generator()

func _process_turret_logic(delta: float):
	turret_target_scan_timer += delta
	if turret_target_scan_timer >= 0.12:
		turret_target_scan_timer = 0.0
		var max_range = GameData.TURRET_SPEC_INFO[turret_spec].range if turret_spec != GameData.TurretSpec.NONE else GameData.TURRET_RANGE_BY_LEVEL[turret_upgrade_level]
		if not is_instance_valid(cached_target_enemy) or global_position.distance_to(cached_target_enemy.global_position) > max_range:
			cached_target_enemy = _acquire_turret_target(max_range)

	if is_instance_valid(cached_target_enemy):
		var enemy_vel = cached_target_enemy.velocity if "velocity" in cached_target_enemy else Vector2.ZERO
		var dist = global_position.distance_to(cached_target_enemy.global_position)
		var bullet_speed = 550.0
		var lead_time = clampf(dist / bullet_speed, 0.0, 0.6)
		var predicted_pos = cached_target_enemy.global_position + (enemy_vel * lead_time)
		var target_angle = (predicted_pos - global_position).angle()
		var track_speed = 6.5 if is_noosphere_connected else 5.0
		current_turret_rotation = lerp_angle(current_turret_rotation, target_angle, track_speed * delta)
	else:
		var base_center = Vector2.ZERO
		var core_node = get_tree().get_first_node_in_group("base")
		if core_node: base_center = core_node.global_position
		var outward_dir = (global_position - base_center)
		if outward_dir.length_squared() < 1.0: outward_dir = Vector2.RIGHT
		var sweep = sin(Time.get_ticks_msec() * 0.0015) * 0.8
		current_turret_rotation = lerp_angle(current_turret_rotation, outward_dir.angle() + sweep, 2.0 * delta)

	turret_rot_sync_timer += delta
	if turret_rot_sync_timer >= 0.06:
		turret_rot_sync_timer = 0.0
		if abs(angle_difference(last_synced_turret_rot, current_turret_rotation)) > 0.025:
			last_synced_turret_rot = current_turret_rotation
			if multiplayer.has_multiplayer_peer():
				rpc("sync_turret_rotation", current_turret_rotation)

func _acquire_turret_target(max_range: float) -> Node2D:
	var main_node = get_tree().get_first_node_in_group("main")
	var has_smart_uplink = is_noosphere_connected and (main_node.get("tech_targeting_uplink_unlocked") if main_node else false)

	# Fallback: Primitive optical proximity tracking (Offline Servitor)
	if not has_smart_uplink:
		return _find_closest_enemy_fallback(max_range)

	# Smart Noospheric Telemetry Target Selection
	var enemies = get_tree().get_nodes_in_group("enemies")
	var best_target: Node2D = null
	var highest_score: float = -999999.0

	for enemy in enemies:
		if is_instance_valid(enemy):
			var dist = global_position.distance_to(enemy.global_position)
			if dist <= max_range:
				var score = _calculate_noospheric_threat_score(enemy, dist, max_range)
				if score > highest_score:
					highest_score = score
					best_target = enemy

	return best_target

func _calculate_noospheric_threat_score(enemy: Node2D, dist: float, max_range: float) -> float:
	# Base score: closer targets have higher base priority
	var score = (max_range - dist) * 1.5

	# 1. AUSPEX LOCK-ON PRIORITY (Tech-Priest / Marshal painted target)
	if enemy.get("has_telemetry_mark"):
		score += 700.0

	var enemy_type = enemy.get("type") if "type" in enemy else -1

	# 2. WEAPON SPECIALIZATION PRIORITIES
	match turret_spec:
		GameData.TurretSpec.NONE:
			# Base Battery: Moderate boost to swift raiders
			if enemy_type == 3: # Stormboy
				score += 250.0
			elif enemy_type == 0: # Gretchin
				score += 150.0

		GameData.TurretSpec.COGNIS_FLAK:
			# Anti-Air & Rapid Horde Shredder
			if enemy_type == 3: # Stormboy (Airborne jump raiders)
				score += 500.0
			elif enemy_type == 0: # Gretchin (Scrap scavengers)
				score += 350.0
			elif enemy_type == 1: # Squig
				score += 200.0

		GameData.TurretSpec.VOLKITE_CULVERIN:
			# Heavy Thermal Piercing Beam: Melts armored & high-HP units
			if enemy_type == 4: # Nob (Mega-armored Warboss)
				score += 650.0
			elif enemy.is_in_group("objectives") or enemy.is_in_group("ork_citadel"):
				score += 600.0
			# Prioritize healthier enemies to maximize penetration damage
			if "current_health" in enemy and "max_health" in enemy:
				score += (float(enemy.current_health) / float(enemy.max_health)) * 200.0

		GameData.TurretSpec.ARC_BLASTER:
			# Chain Lightning: Prioritizes dense clusters of Squigs/Boyz for 3-target arcs
			if enemy_type in [1, 2]: # Squig, Ork Boy
				score += 300.0
			# Cluster bonus: count nearby greenskins within arc chain radius (130px)
			var cluster_count = 0
			for other in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(other) and other != enemy:
					if enemy.global_position.distance_to(other.global_position) <= 130.0:
						cluster_count += 1
						if cluster_count >= 2: break
			score += cluster_count * 200.0

	return score

func _find_closest_enemy_fallback(max_range: float) -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var closest_target: Node2D = null
	var closest_dist = max_range
	for enemy in enemies:
		if is_instance_valid(enemy):
			var dist = global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_target = enemy
	return closest_target

@rpc("call_local", "unreliable")
func sync_turret_rotation(rot: float):
	current_turret_rotation = rot
	if is_instance_valid(visual_spriteNode):
		visual_spriteNode.turret_rotation = current_turret_rotation
		visual_spriteNode.queue_redraw()

func _find_closest_enemy() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var closest_target: Node2D = null
	var closest_dist: float = GameData.TURRET_RANGE_BY_LEVEL[turret_upgrade_level]
	for enemy in enemies:
		if is_instance_valid(enemy):
			var dist = global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_target = enemy
	return closest_target

func _on_turret_timer_timeout():
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	
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

		var angle_diff = abs(angle_difference(current_turret_rotation, target_angle))
		if angle_diff <= deg_to_rad(14.0):
			var dir = Vector2.RIGHT.rotated(current_turret_rotation)
			var main_node = get_tree().get_first_node_in_group("main")
			if not main_node: return

			match turret_spec:
				GameData.TurretSpec.NONE:
					if main_node.spawner:
						main_node.spawner.spawn({
							"type": "bullet",
							"name": "TurretBullet_" + str(randi()),
							"position": global_position + (dir * 24.0),
							"direction": dir,
							"damage": GameData.TURRET_DAMAGE_BY_LEVEL[turret_upgrade_level]
						})
					AudioManager.play_sfx("laser", global_position, -4.0)

				GameData.TurretSpec.COGNIS_FLAK:
					flak_barrel_toggle = not flak_barrel_toggle
					var offset = dir.orthogonal() * (4.5 if flak_barrel_toggle else -4.5)
					var spread_dir = dir.rotated(randf_range(-0.06, 0.06))
					if main_node.spawner:
						main_node.spawner.spawn({
							"type": "bullet",
							"name": "FlakBullet_" + str(randi()),
							"position": global_position + (dir * 24.0) + offset,
							"direction": spread_dir,
							"damage": GameData.TURRET_SPEC_INFO[turret_spec].damage
						})
					AudioManager.play_sfx("radium_shot", global_position, -2.0, 1.4)

				GameData.TurretSpec.VOLKITE_CULVERIN:
					var ray_end = global_position + (dir * 380.0)
					if multiplayer.has_multiplayer_peer():
						rpc("trigger_volkite_ray_fx", ray_end)
					else:
						trigger_volkite_ray_fx(ray_end)
					_execute_volkite_piercing_ray(global_position, ray_end)

				GameData.TurretSpec.ARC_BLASTER:
					_execute_arc_chain_lightning(cached_target_enemy)

func _execute_volkite_piercing_ray(start_pos: Vector2, end_pos: Vector2):
	AudioManager.play_sfx("volkite_beam", global_position, 2.0, 1.0)
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
	AudioManager.play_sfx("arc_lightning", global_position, 2.0, 1.0)
	var chain_points: Array[Vector2] = [primary_target.global_position]
	
	if primary_target.has_method("take_damage"):
		primary_target.take_damage(GameData.TURRET_SPEC_INFO[GameData.TurretSpec.ARC_BLASTER].damage)

	var enemies = get_tree().get_nodes_in_group("enemies")
	var chained_count = 0
	for e in enemies:
		if is_instance_valid(e) and e != primary_target and chained_count < 2:
			if primary_target.global_position.distance_to(e.global_position) <= 130.0:
				chain_points.append(e.global_position)
				if e.has_method("take_damage"):
					e.take_damage(30, (e.global_position - primary_target.global_position).normalized() * 140.0)
				chained_count += 1

	if multiplayer.has_multiplayer_peer():
		rpc("trigger_arc_lightning_fx", chain_points)
	else:
		trigger_arc_lightning_fx(chain_points)

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
	rebuild_all_barricade_connections(get_tree())

static func rebuild_all_barricade_connections(tree: SceneTree) -> void:
	if not tree: return

	var all_barricades: Array[Node2D] = []
	for b in tree.get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.get("is_preview") and int(b.get("building_type")) == int(Type.BARRICADE):
			all_barricades.append(b)

	for b in all_barricades:
		b.connected_neighbor_ids.clear()

	var candidates: Array[Dictionary] = []
	for i in range(all_barricades.size()):
		for j in range(i + 1, all_barricades.size()):
			var b1 = all_barricades[i]
			var b2 = all_barricades[j]
			var dist = b1.global_position.distance_to(b2.global_position)
			if dist <= WALL_LINK_RANGE and dist > 5.0:
				candidates.append({"b1": b1, "b2": b2, "dist": dist})

	candidates.sort_custom(func(a, b): return a.dist < b.dist)

	var degree: Dictionary = {}
	for b in all_barricades:
		degree[b.get_instance_id()] = 0

	var valid_edges: Array[Dictionary] = []

	for edge in candidates:
		var id1 = edge.b1.get_instance_id()
		var id2 = edge.b2.get_instance_id()

		if degree[id1] < 2 and degree[id2] < 2:
			var p1 = edge.b1.global_position
			var p2 = edge.b2.global_position
			var crosses = false

			for existing in valid_edges:
				var eid1 = existing.b1.get_instance_id()
				var eid2 = existing.b2.get_instance_id()
				if id1 == eid1 or id1 == eid2 or id2 == eid1 or id2 == eid2:
					continue
				if Geometry2D.segment_intersects_segment(p1, p2, existing.b1.global_position, existing.b2.global_position) != null:
					crosses = true
					break

			if not crosses:
				degree[id1] += 1
				degree[id2] += 1
				valid_edges.append(edge)
				edge.b1.connected_neighbor_ids.append(id2)
				edge.b2.connected_neighbor_ids.append(id1)

	for b in all_barricades:
		var offsets: Array[Vector2] = []
		var neighbor_nodes: Array[Node2D] = []
		for n_id in b.connected_neighbor_ids:
			var neighbor = instance_from_id(n_id) as Node2D
			if is_instance_valid(neighbor):
				neighbor_nodes.append(neighbor)
				if b.get_instance_id() < n_id:
					offsets.append(b.to_local(neighbor.global_position))

		if b.visual_spriteNode and "wall_connections" in b.visual_spriteNode:
			b.visual_spriteNode.wall_connections = offsets
			b.visual_spriteNode.queue_redraw()

		b._update_wall_colliders(neighbor_nodes)

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
	remove_from_group("navmesh_source")
	var main_node = get_parent()
	if not (main_node and main_node.has_method("request_navmesh_rebake")):
		main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.has_method("request_navmesh_rebake"):
		main_node.request_navmesh_rebake()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc("client_destroy")
	else:
		client_destroy()

@rpc("call_local", "reliable")
func client_destroy():
	get_tree().call_group("sandy_floor", "refresh_foundations")
	get_tree().call_group("buildings", "_update_noosphere_connection")
	if building_type == Type.BARRICADE:
		call_deferred("refresh_barricade_connections")
	queue_free()

func setup_as_preview():
	is_preview = true

	# 1. Neutralize all physics layers & masks
	collision_layer = 0
	collision_mask = 0
	set_process(false)
	set_physics_process(false)

	# 2. Disable collision shapes
	if is_instance_valid(collision_shape):
		collision_shape.disabled = true

	for child in find_children("*", "CollisionShape2D", true, false):
		(child as CollisionShape2D).disabled = true
	for child in find_children("*", "CollisionPolygon2D", true, false):
		(child as CollisionPolygon2D).disabled = true

	# 3. Disable any Area2Ds (magnets, sensors)
	for child in find_children("*", "Area2D", true, false):
		var area = child as Area2D
		area.monitoring = false
		area.monitorable = false
		area.collision_layer = 0
		area.collision_mask = 0

	# 4. Remove from all groups
	var groups_to_remove = ["buildings", "navmesh_source", "friendlies", "controllable_units", "base", "dynamic_lights"]
	for g in groups_to_remove:
		if is_in_group(g):
			remove_from_group(g)

	# 5. Halt timers
	if is_instance_valid(turret_timer): turret_timer.stop()
	if is_instance_valid(gen_timer): gen_timer.stop()

	# 6. DESTROY the shadow so DayNightCycle cannot re-enable it
	if has_node("Shadow"):
		$Shadow.queue_free()
	if has_node("HealthBar"):
		$HealthBar.queue_free()
	var light = get_node_or_null("BuildingPointLight")
	if is_instance_valid(light):
		light.queue_free()

func _draw() -> void:
	if building_type == Type.CYBERNETICA_FORGE and not is_preview:
		if rally_point_world != Vector2.ZERO:
			_draw_rally_point_beacon()

func _draw_cybernetica_forge():
	# (You can remove this from Building.gd since VisualBuildingSprite now draws it)
	pass

func _draw_rally_point_beacon():
	var local_rally = to_local(rally_point_world)
	var pulse = 0.6 + sin(Time.get_ticks_msec() * 0.007) * 0.4
	var beacon_color = Color(0.20, 0.88, 1.0, 0.75 * pulse)

	draw_line(Vector2(0, 16), local_rally, Color(0.20, 0.88, 1.0, 0.25), 1.0)
	draw_circle(local_rally, 12.0, Color(0.20, 0.88, 1.0, 0.15 * pulse))
	draw_arc(local_rally, 12.0, 0.0, TAU, 24, beacon_color, 1.4)
	draw_line(local_rally + Vector2(0, -18), local_rally, beacon_color, 2.0)
	draw_colored_polygon(PackedVector2Array([
		local_rally + Vector2(0, -18),
		local_rally + Vector2(8, -14),
		local_rally + Vector2(0, -10)
	]), Color(0.82, 0.62, 0.24, 0.9))
