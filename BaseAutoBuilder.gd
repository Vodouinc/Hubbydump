# res://BaseAutoBuilder.gd
extends Node2D
class_name BaseAutoBuilder

var main_node: Node2D = null
var base_node: Node2D = null
var base_pos: Vector2 = Vector2(500, 500)

var blueprints: Array[Dictionary] = []
var fabricator_skulls: Array[FabricatorSkull] = []

var is_active: bool = false
var pulse_time: float = 0.0

func _ready() -> void:
	z_index = 80
	main_node = get_tree().get_first_node_in_group("main")
	base_node = get_tree().get_first_node_in_group("base")
	
	if is_instance_valid(base_node):
		base_pos = base_node.global_position
		global_position = base_pos

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_init_blueprints()
	_spawn_fabricator_skulls()
	is_active = true

func _init_blueprints() -> void:
	blueprints.clear()

	# 1. ECONOMY BLUEPRINTS
	# A. Plasma Dynamo (North)
	blueprints.append({
		"id": 0,
		"type": 1, # GENERATOR
		"pos": base_pos + Vector2(0, -95),
		"name": "Auto_PlasmaDynamo",
		"building_node": null,
		"is_built": false,
		"rebuild_timer": 0.0,
		"priority": 100
	})

	# B. Scrap Smelter (Find closest starter deposit)
	var deposit_pos = base_pos + Vector2(-180, -90)
	for dep in get_tree().get_nodes_in_group("scrap_deposits"):
		if is_instance_valid(dep):
			var d = base_pos.distance_to(dep.global_position)
			if d < 320.0:
				deposit_pos = dep.global_position
				break

	blueprints.append({
		"id": 1,
		"type": 3, # MANUFACTORUM / SMELTER
		"pos": deposit_pos,
		"name": "Auto_ScrapSmelter",
		"building_node": null,
		"is_built": false,
		"rebuild_timer": 0.0,
		"priority": 95
	})

	# 2. FACILITIES
	# A. Tech Shrine (West)
	blueprints.append({
		"id": 2,
		"type": 6, # RESEARCH_SHRINE
		"pos": base_pos + Vector2(-95, -35),
		"name": "Auto_TechShrine",
		"building_node": null,
		"is_built": false,
		"rebuild_timer": 0.0,
		"priority": 90
	})

	# B. Cybernetica Forge (East)
	blueprints.append({
		"id": 3,
		"type": 7, # CYBERNETICA_FORGE
		"pos": base_pos + Vector2(95, -35),
		"name": "Auto_CyberneticaForge",
		"building_node": null,
		"is_built": false,
		"rebuild_timer": 0.0,
		"priority": 85
	})

	# 3. DEFENSES (3 Perimeter Cognis Turrets)
	blueprints.append({
		"id": 4,
		"type": 2, # TURRET (West Flank)
		"pos": base_pos + Vector2(-155, 45),
		"name": "Auto_WestTurret",
		"building_node": null,
		"is_built": false,
		"rebuild_timer": 0.0,
		"priority": 80
	})

	blueprints.append({
		"id": 5,
		"type": 2, # TURRET (East Flank)
		"pos": base_pos + Vector2(155, 45),
		"name": "Auto_EastTurret",
		"building_node": null,
		"is_built": false,
		"rebuild_timer": 0.0,
		"priority": 80
	})

	blueprints.append({
		"id": 6,
		"type": 2, # TURRET (South Choke)
		"pos": base_pos + Vector2(0, 150),
		"name": "Auto_SouthTurret",
		"building_node": null,
		"is_built": false,
		"rebuild_timer": 0.0,
		"priority": 75
	})

	# 4. AEGIS BARRICADES (Perimeter Wall Links)
	var wall_offsets = [
		Vector2(-80, 145), Vector2(80, 145),
		Vector2(-140, 95), Vector2(140, 95)
	]
	for i in range(wall_offsets.size()):
		blueprints.append({
			"id": 7 + i,
			"type": 0, # BARRICADE
			"pos": base_pos + wall_offsets[i],
			"name": "Auto_Barricade_" + str(i + 1),
			"building_node": null,
			"is_built": false,
			"rebuild_timer": 0.0,
			"priority": 60 - i
		})

func _spawn_fabricator_skulls() -> void:
	for c in fabricator_skulls:
		if is_instance_valid(c): c.queue_free()
	fabricator_skulls.clear()

	for i in range(3):
		var skull = FabricatorSkull.new()
		skull.name = "FabricatorSkull_" + str(i + 1)
		skull.home_anchor = base_pos
		skull.position = base_pos + Vector2.RIGHT.rotated(float(i) * (TAU / 3.0)) * 25.0
		add_child(skull)
		fabricator_skulls.append(skull)

func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not is_active: return
	pulse_time += delta

	_evaluate_building_states(delta)
	_dispatch_skull_orders()

func _evaluate_building_states(delta: float) -> void:
	for bp in blueprints:
		if not bp is Dictionary: continue

		var is_b = bp.get("is_built", false)
		if is_b:
			var node = bp.get("building_node", null)
			if not is_instance_valid(node):
				# Structure was destroyed! Log for reconstruction
				bp["is_built"] = false
				bp["building_node"] = null
				bp["rebuild_timer"] = 10.0 # 10s cooldown before sending skull to rebuild
		else:
			var timer = float(bp.get("rebuild_timer", 0.0))
			if timer > 0.0:
				bp["rebuild_timer"] = timer - delta

func _dispatch_skull_orders() -> void:
	for bp in blueprints:
		if not bp is Dictionary: continue

		var is_b = bp.get("is_built", false)
		var timer = float(bp.get("rebuild_timer", 0.0))
		
		if not is_b and timer <= 0.0:
			if not _is_blueprint_assigned(bp):
				var available_skull = _get_idle_skull()
				if available_skull:
					available_skull.assign_construction_task(bp, self)

func _is_blueprint_assigned(bp: Dictionary) -> bool:
	for skull in fabricator_skulls:
		if is_instance_valid(skull) and skull.current_task_bp == bp:
			return true
	return false

func _get_idle_skull() -> FabricatorSkull:
	for skull in fabricator_skulls:
		if is_instance_valid(skull) and skull.is_idle():
			return skull
	return null

func complete_construction(bp: Dictionary) -> void:
	if not is_instance_valid(main_node):
		main_node = get_tree().get_first_node_in_group("main")

	if is_instance_valid(main_node):
		var building_type_id = int(bp.get("type", 0))
		var build_pos = bp.get("pos", base_pos)
		var build_name = str(bp.get("name", "AutoBuilding")) + "_" + str(randi() % 10000)

		var spawned = main_node.spawn_entity({
			"type": "building",
			"name": build_name,
			"position": build_pos,
			"building_type": building_type_id
		})
		
		bp["building_node"] = spawned
		bp["is_built"] = true

		AudioManager.play_sfx("building_place", build_pos, 0.0, 1.3)

		if building_type_id == 0:
			Building.rebuild_all_barricade_connections(get_tree())
		
		if main_node.has_method("request_navmesh_rebake"):
			main_node.request_navmesh_rebake()

# ==============================================================================
# INNER CLASS: FABRICATOR SERVO-SKULL
# ==============================================================================
class FabricatorSkull extends Node2D:
	enum State { IDLE, TRAVELING, WELDING }
	var current_state: State = State.IDLE

	var home_anchor: Vector2 = Vector2.ZERO
	var current_task_bp: Dictionary = {}
	var auto_builder_ref: BaseAutoBuilder = null

	var weld_timer: float = 0.0
	const WELD_DURATION: float = 2.4

	var move_speed: float = 230.0
	var hover_angle: float = 0.0

	func _ready() -> void:
		z_index = 86
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat

	func is_idle() -> bool:
		return current_state == State.IDLE

	func assign_construction_task(bp: Dictionary, builder: BaseAutoBuilder) -> void:
		current_task_bp = bp
		auto_builder_ref = builder
		current_state = State.TRAVELING

	func _process(delta: float) -> void:
		hover_angle += delta * 2.0

		match current_state:
			State.IDLE:
				var idle_offset = Vector2.RIGHT.rotated(hover_angle + float(get_instance_id())) * 35.0
				idle_offset.y += sin(Time.get_ticks_msec() * 0.005) * 6.0
				var target = home_anchor + idle_offset
				global_position = global_position.move_toward(target, move_speed * 0.6 * delta)

			State.TRAVELING:
				if current_task_bp.is_empty():
					current_state = State.IDLE
					return

				var target_pos = current_task_bp.get("pos", global_position) + Vector2(0, -18)
				global_position = global_position.move_toward(target_pos, move_speed * delta)

				if global_position.distance_to(target_pos) <= 8.0:
					current_state = State.WELDING
					weld_timer = WELD_DURATION
					AudioManager.play_sfx("volkite_beam", global_position, -2.0, 1.8)

			State.WELDING:
				weld_timer -= delta
				if weld_timer <= 0.0:
					if is_instance_valid(auto_builder_ref) and not current_task_bp.is_empty():
						auto_builder_ref.complete_construction(current_task_bp)
					current_task_bp.clear()
					current_state = State.IDLE

		queue_redraw()

	func _draw() -> void:
		# 1. Welding Beam & Plasma Sparks
		if current_state == State.WELDING and not current_task_bp.is_empty():
			var target_pos = current_task_bp.get("pos", global_position)
			var local_weld_target = to_local(target_pos)
			var pulse = 0.8 + sin(Time.get_ticks_msec() * 0.03) * 0.2

			draw_line(Vector2(0, 2), local_weld_target, Color(0.20, 0.88, 1.0, 0.35), 4.5)
			draw_line(Vector2(0, 2), local_weld_target, Color(0.20, 0.88, 1.0, 0.95 * pulse), 1.6)
			draw_circle(local_weld_target, 5.0 * pulse, Color(0.55, 0.95, 1.0))
			draw_circle(local_weld_target, 2.0, Color.WHITE)

			# Hot metal particles
			for i in range(3):
				var spark = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(5.0, 18.0)
				draw_circle(local_weld_target + spark, 1.2, Color(1.0, 0.85, 0.20))

		# 2. Fabricator Skull Chassis
		draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 5.5, Color(0.02, 0.03, 0.05, 0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Golden Cranium Chassis
		draw_circle(Vector2(0, -2), 6.5, Color(0.82, 0.62, 0.24)) # Gold
		draw_circle(Vector2(0, -2), 4.5, Color(0.92, 0.78, 0.35))

		# Dual Cyan Lenses
		draw_circle(Vector2(-2.5, -2), 1.8, Color(0.1, 0.12, 0.15))
		draw_circle(Vector2(2.5, -2), 2.2, Color(0.20, 0.88, 1.0))
		draw_circle(Vector2(2.5, -2), 1.0, Color.WHITE)

		# Trailing Mechatendril Welding Cables
		var t = Time.get_ticks_msec() * 0.008 + float(get_instance_id())
		draw_line(Vector2(-3, 3), Vector2(-4 + sin(t) * 3.0, 10), Color(0.20, 0.22, 0.25), 1.4)
		draw_line(Vector2(0, 4), Vector2(0 + sin(t + 1.5) * 3.0, 12), Color(0.82, 0.62, 0.24), 1.4)
		draw_line(Vector2(3, 3), Vector2(4 + sin(t + 3.0) * 3.0, 10), Color(0.20, 0.22, 0.25), 1.4)
