extends CharacterBody2D

enum PlayerClass { MELEE, RANGED }
enum Doctrina { CONQUEROR, PROTECTOR }

@export var current_class: PlayerClass = PlayerClass.MELEE

@export var tech_priest_data: PlayerClassData
@export var skitarii_marshal_data: PlayerClassData

var speed: float = 300.0
var max_health: int = 100
var current_health: int = 100

var bullet_scene = preload("res://Bullet.tscn")
var attack_cooldown: float = 0.4
var bullet_damage: int = 20
var can_attack: bool = true

var can_plasma_attack: bool = true
var plasma_cooldown: float = 0.65
var plasma_damage: int = 30

var tooltip_overlay: Node2D = null

var is_attacking_anim: bool = false
var attack_progress: float = 0.0
var attack_angle: float = 0.0
var attack_anim_duration: float = 0.22
var already_hit_enemies: Array = []

var selected_building_type: int = 0
const BUILD_RANGE: float = 260.0
const CONDUIT_RANGE: float = 360.0
const INTERACTION_RANGE: float = 85.0
var building_scene = preload("res://Building.tscn")
var is_building_mode: bool = false
var preview_instance: Node2D = null
var preview_is_valid: bool = false
var preview_connection_target: Node2D = null
var hovered_interact_building: Node2D = null

const GRID_SIZE: float = 32.0
const WALL_LINK_RANGE: float = 95.0
var preview_barricade_links: Array[Node2D] = []

var rts_selected_units: Array[Node2D] = []
var is_box_selecting: bool = false
var box_select_start_screen: Vector2 = Vector2.ZERO
var box_select_current_screen: Vector2 = Vector2.ZERO
var is_attack_move_queued: bool = false
var control_groups: Dictionary = {}

var is_mmb_dragging: bool = false
var mmb_drag_start_mouse: Vector2 = Vector2.ZERO
var mmb_drag_start_cam: Vector2 = Vector2.ZERO
const EDGE_SCROLL_MARGIN: float = 20.0
const RTS_CAM_PAN_SPEED: float = 950.0

var rts_target_move_pos: Vector2 = Vector2.ZERO
var rts_is_moving: bool = false
var rts_attack_target_node: Node2D = null
var rts_is_attack_moving: bool = false
var is_rts_selected: bool = false

var active_doctrina: Doctrina = Doctrina.CONQUEROR
var orbital_strike_cooldown: float = 0.0
var active_bodyguards: Array = []
var active_servo_skulls: Array = []
var active_kastelan_robot: Node2D = null
var bodyguard_level: int = 0
var damage_upgrade_level: int = 0
var speed_upgrade_level: int = 0

@onready var label: Label = $Label
@onready var camera: Camera2D = $Camera2D
@onready var visual_sprite: Node2D = $VisualSprite
@onready var shadow_node: Node2D = get_node_or_null("Shadow")
@onready var health_bar: Node2D = get_node_or_null("HealthBar")

func _enter_tree():
	var id = name.to_int()
	if id != 0:
		set_multiplayer_authority(id)

func _is_local_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()

func _ready():
	add_to_group("players")
	add_to_group("friendlies")
	add_to_group("controllable_units")
	apply_class_stats()
	
	set_process_unhandled_input(_is_local_authority())
	
	if _is_local_authority():
		_setup_tooltip_overlay()
		if label:
			label.text += " [YOU]"
		if camera:
			camera.enabled = true
			camera.make_current()
			if current_class == PlayerClass.RANGED:
				camera.top_level = true
				camera.global_position = global_position
			
		var hud = get_tree().get_first_node_in_group("ability_hud")
		if hud and hud.has_method("setup_hud_for_player"):
			hud.setup_hud_for_player(self)
	else:
		if camera:
			camera.enabled = false

func set_player_class(new_class):
	current_class = new_class
	if not is_node_ready():
		await ready

	apply_class_stats()
	if camera and _is_local_authority():
		if current_class == PlayerClass.RANGED:
			camera.top_level = true
			camera.global_position = global_position
		else:
			camera.top_level = false
			camera.position = Vector2.ZERO

func apply_class_stats():
	var active_data = tech_priest_data if current_class == PlayerClass.MELEE else skitarii_marshal_data
	if active_data:
		speed = active_data.movement_speed
		max_health = active_data.max_health
		attack_cooldown = active_data.attack_cooldown
		bullet_damage = active_data.base_damage
		attack_anim_duration = active_data.attack_anim_duration
		if visual_sprite:
			visual_sprite.unit_type = active_data.unit_type_id
	else:
		speed = 250.0 if current_class == PlayerClass.MELEE else 340.0
		max_health = 150 if current_class == PlayerClass.MELEE else 90
		bullet_damage = 25

	if shadow_node and shadow_node.has_method("update_shadow_size"):
		shadow_node.update_shadow_size()

	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)

func _physics_process(delta: float) -> void:
	if current_class == PlayerClass.MELEE:
		_process_techpriest_movement(delta)
	else:
		_process_marshal_rts_movement(delta)

func _process_techpriest_movement(delta: float) -> void:
	if not _is_local_authority(): return

	var direction = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): direction.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): direction.y += 1

	if direction != Vector2.ZERO:
		direction = direction.normalized()
		var corner_nudge = _calculate_corner_nudge(direction)
		direction = (direction + corner_nudge).normalized()
		velocity = direction * speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed * 12.0 * delta)

	move_and_slide()

func _process_marshal_rts_movement(delta: float) -> void:
	if rts_is_moving:
		var dist = global_position.distance_to(rts_target_move_pos)
		if dist > 12.0:
			var dir = global_position.direction_to(rts_target_move_pos)
			var corner_nudge = _calculate_corner_nudge(dir)
			velocity = (dir + corner_nudge).normalized() * speed
		else:
			rts_is_moving = false
			velocity = Vector2.ZERO
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed * 12.0 * delta)

	move_and_slide()

	if _is_local_authority():
		_process_marshal_combat(delta)

func _process_marshal_combat(_delta: float) -> void:
	if is_instance_valid(rts_attack_target_node):
		var dist = global_position.distance_to(rts_attack_target_node.global_position)
		if dist <= 380.0 and can_attack:
			rpc("perform_attack", rts_attack_target_node.global_position)
	elif rts_is_attack_moving or not rts_is_moving:
		var nearby_enemy = _find_nearest_enemy_in_range(340.0)
		if is_instance_valid(nearby_enemy) and can_attack:
			rpc("perform_attack", nearby_enemy.global_position)

func _calculate_corner_nudge(move_dir: Vector2) -> Vector2:
	var space_state = get_world_2d().direct_space_state
	if not space_state: return Vector2.ZERO

	var probe_dist = 14.0
	var side_spread = 10.0
	var perp = move_dir.orthogonal()

	var left_origin = global_position - (perp * side_spread)
	var right_origin = global_position + (perp * side_spread)

	var left_query = PhysicsRayQueryParameters2D.create(left_origin, left_origin + (move_dir * probe_dist))
	left_query.exclude = [get_rid()]
	left_query.collision_mask = collision_mask

	var right_query = PhysicsRayQueryParameters2D.create(right_origin, right_origin + (move_dir * probe_dist))
	right_query.exclude = [get_rid()]
	right_query.collision_mask = collision_mask

	var left_hit = space_state.intersect_ray(left_query)
	var right_hit = space_state.intersect_ray(right_query)

	if not left_hit.is_empty() and right_hit.is_empty():
		return perp * 0.85
	elif left_hit.is_empty() and not right_hit.is_empty():
		return -perp * 0.85

	return Vector2.ZERO

func toggle_build_mode(building_type_idx: int = 0):
	if is_building_mode and selected_building_type == building_type_idx:
		_cancel_build_mode()
		return
		
	_cancel_build_mode()
	
	is_building_mode = true
	selected_building_type = building_type_idx
	
	preview_instance = building_scene.instantiate()
	preview_instance.modulate = Color(1, 1, 1, 0.5)
	
	if "building_type" in preview_instance:
		preview_instance.building_type = selected_building_type
	
	if preview_instance.has_method("setup_as_preview"):
		preview_instance.setup_as_preview()
	elif preview_instance.has_node("CollisionShape2D"):
		preview_instance.get_node("CollisionShape2D").disabled = true
		
	get_parent().add_child(preview_instance)

func _cancel_build_mode():
	is_building_mode = false
	preview_is_valid = false
	preview_connection_target = null
	preview_barricade_links.clear()
	if is_instance_valid(preview_instance):
		preview_instance.queue_free()
		preview_instance = null
	queue_redraw()

func _get_building_size(b_type: int) -> Vector2:
	if b_type == -1: return Vector2(144, 144)
	var info = GameData.STRUCTURE_INFO.get(b_type, null)
	return info["size"] if info else Vector2(32, 32)

func _requires_industrial_ground(b_type: int) -> bool:
	var info = GameData.STRUCTURE_INFO.get(b_type, null)
	return info["requires_industrial"] if info else false

func _is_position_on_industrial_ground(pos: Vector2) -> bool:
	var floor_node = get_tree().get_first_node_in_group("sandy_floor")
	if floor_node and floor_node.has_method("is_world_pos_on_grid"):
		return floor_node.is_world_pos_on_grid(pos)
	return false

func _get_snapped_build_position(mouse_pos: Vector2) -> Vector2:
	if selected_building_type == 0:
		var buildings = get_tree().get_nodes_in_group("buildings")
		var closest_barricade: Node2D = null
		var closest_score = 120.0

		for b in buildings:
			if not is_instance_valid(b) or b == preview_instance: continue
			if "building_type" in b and int(b.building_type) == 0:
				if "is_preview" in b and b.is_preview: continue
				var d = mouse_pos.distance_to(b.global_position)
				if d < closest_score and d > 10.0:
					var conns = b.connected_neighbor_ids.size() if "connected_neighbor_ids" in b else 0
					var score = d if conns < 2 else d + 40.0
					if score < closest_score:
						closest_score = score
						closest_barricade = b

		if is_instance_valid(closest_barricade):
			var diff = mouse_pos - closest_barricade.global_position
			var snapped_angle = snapped(diff.angle(), PI / 4.0)
			var dir_vector = Vector2.RIGHT.rotated(snapped_angle).round()
			var snapped_target = closest_barricade.global_position + (dir_vector * 64.0)
			return Vector2(
				floor(snapped_target.x / GRID_SIZE) * GRID_SIZE + (GRID_SIZE * 0.5),
				floor(snapped_target.y / GRID_SIZE) * GRID_SIZE + (GRID_SIZE * 0.5)
			)

	var size = _get_building_size(selected_building_type)
	var cells_x = int(round(size.x / GRID_SIZE))
	var cells_y = int(round(size.y / GRID_SIZE))
	var snapped_x = floor(mouse_pos.x / GRID_SIZE) * GRID_SIZE + (GRID_SIZE * 0.5) if cells_x % 2 == 1 else round(mouse_pos.x / GRID_SIZE) * GRID_SIZE
	var snapped_y = floor(mouse_pos.y / GRID_SIZE) * GRID_SIZE + (GRID_SIZE * 0.5) if cells_y % 2 == 1 else round(mouse_pos.y / GRID_SIZE) * GRID_SIZE
	return Vector2(snapped_x, snapped_y)

func _is_build_location_valid(build_pos: Vector2) -> bool:
	if selected_building_type == 3:
		var nearest_deposit = _find_nearest_unoccupied_deposit(build_pos, 32.0)
		if not is_instance_valid(nearest_deposit): return false

	if _requires_industrial_ground(selected_building_type) and not _is_position_on_industrial_ground(build_pos):
		return false

	var is_placing_barricade = (selected_building_type == 0)
	var placement_margin = -1.0 if is_placing_barricade else 4.0
	var my_rect = Rect2(build_pos - (_get_building_size(selected_building_type) * 0.5), _get_building_size(selected_building_type)).grow(placement_margin)

	var structures = get_tree().get_nodes_in_group("buildings")
	structures.append_array(get_tree().get_nodes_in_group("base"))

	for s in structures:
		if not is_instance_valid(s) or s == preview_instance: continue
		if "is_preview" in s and s.is_preview: continue
		var s_type = -1 if s.is_in_group("base") else int(s.get("building_type"))
		var other_is_barricade = (s_type == 0)
		var other_margin = -1.0 if (is_placing_barricade and other_is_barricade) else 4.0
		var other_rect = Rect2(s.global_position - (_get_building_size(s_type) * 0.5), _get_building_size(s_type)).grow(other_margin)

		if my_rect.intersects(other_rect): return false

	return true

func _find_nearest_unoccupied_deposit(pos: Vector2, max_dist: float) -> Node2D:
	for dep in get_tree().get_nodes_in_group("scrap_deposits"):
		if is_instance_valid(dep) and not dep.get("is_occupied"):
			if pos.distance_to(dep.global_position) <= max_dist:
				return dep
	return null

func _find_preview_connection(build_pos: Vector2) -> Node2D:
	var closest: Node2D = null
	var closest_distance := CONDUIT_RANGE
	var candidates: Array = get_tree().get_nodes_in_group("buildings")
	candidates.append_array(get_tree().get_nodes_in_group("base"))
	for candidate in candidates:
		if not is_instance_valid(candidate) or candidate == preview_instance: continue
		var distance = candidate.global_position.distance_to(build_pos)
		if distance < closest_distance:
			closest_distance = distance
			closest = candidate
	return closest
	
func _find_preview_barricade_links(build_pos: Vector2) -> Array[Node2D]:
	var linked_neighbors: Array[Node2D] = []
	if selected_building_type != 0: return linked_neighbors

	var buildings = get_tree().get_nodes_in_group("buildings")
	var candidates: Array[Dictionary] = []
	for b in buildings:
		if not is_instance_valid(b) or b == preview_instance: continue
		if "building_type" in b and int(b.building_type) == 0:
			if "is_preview" in b and b.is_preview: continue
			var dist = b.global_position.distance_to(build_pos)
			if dist <= WALL_LINK_RANGE and dist > 5.0:
				var conns = b.connected_neighbor_ids.size() if "connected_neighbor_ids" in b else 0
				if conns < 2: candidates.append({"node": b, "dist": dist})

	candidates.sort_custom(func(a, b): return a.dist < b.dist)
	for i in range(min(candidates.size(), 2)):
		linked_neighbors.append(candidates[i].node)

	return linked_neighbors

func request_interact_nearby_structure() -> void:
	var b_ui = get_tree().get_first_node_in_group("base_upgrade_ui")
	if b_ui and b_ui.visible: b_ui.close_terminal(); return
	var r_ui = get_tree().get_first_node_in_group("research_ui")
	if r_ui and r_ui.visible: r_ui.close_terminal(); return
	var t_ui = get_tree().get_first_node_in_group("turret_upgrade_ui")
	if t_ui and t_ui.visible: t_ui.close_modal(); return
	var c_ui = get_tree().get_first_node_in_group("cybernetica_ui")
	if c_ui and c_ui.visible: c_ui.close_terminal(); return

	var closest = _get_closest_interactable_structure()
	if is_instance_valid(closest):
		if closest.is_in_group("base"):
			if b_ui: b_ui.open_terminal(closest)
			return

		var main_node = get_tree().get_first_node_in_group("main")
		if main_node:
			var b_type = int(closest.building_type)
			if b_type == 0:
				main_node.rpc_id(1, "request_upgrade_gate", closest.name)
			elif b_type == 2:
				var lvl = closest.turret_upgrade_level if "turret_upgrade_level" in closest else 0
				var spec = closest.turret_spec if "turret_spec" in closest else 0
				if lvl < 3: main_node.rpc_id(1, "request_upgrade_turret", closest.name)
				elif spec == GameData.TurretSpec.NONE and t_ui: t_ui.open_modal(closest)
			elif b_type == 4: main_node.rpc_id(1, "request_upgrade_distributor", closest.name)
			elif b_type == 6 and r_ui: r_ui.open_terminal(closest)
			elif b_type == 7 and c_ui: c_ui.open_terminal(closest)

func _get_closest_interactable_structure() -> Node2D:
	var closest: Node2D = null
	var closest_dist := INTERACTION_RANGE

	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		var dist_to_base = global_position.distance_to(base_node.global_position)
		if dist_to_base <= 65.0:
			closest_dist = dist_to_base
			closest = base_node

	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not ("building_type" in building): continue
		var b_type = int(building.building_type)
		if b_type == 0 and building.get("is_gate"): continue
		if not (b_type in [0, 2, 4, 6, 7]): continue
		var dist = global_position.distance_to(building.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = building
			
	return closest

func _process(delta: float):
	if orbital_strike_cooldown > 0.0:
		orbital_strike_cooldown = maxf(0.0, orbital_strike_cooldown - delta)

	if is_attacking_anim:
		attack_progress += delta / attack_anim_duration
		if visual_sprite and visual_sprite.has_method("set_attack_state"):
			visual_sprite.set_attack_state(true, attack_progress, attack_angle)
		
		if multiplayer.is_server() and attack_progress >= 0.20 and attack_progress <= 0.75:
			check_lingering_melee_hits()

		if attack_progress >= 1.0:
			is_attacking_anim = false
			attack_progress = 0.0
			already_hit_enemies.clear()
			if visual_sprite and visual_sprite.has_method("set_attack_state"):
				visual_sprite.set_attack_state(false, 0.0, 0.0)

		queue_redraw()

	if _is_local_authority():
		if current_class == PlayerClass.RANGED and is_instance_valid(camera):
			_process_rts_camera_panning(delta)

		var mouse_pos = get_global_mouse_position()
		if visual_sprite and visual_sprite.has_method("update_facing"):
			visual_sprite.update_facing(mouse_pos)

	if is_box_selecting:
		queue_redraw()

	if _is_local_authority() and is_building_mode and is_instance_valid(preview_instance):
		var build_pos = _get_snapped_build_position(get_global_mouse_position())
		preview_instance.global_position = build_pos
		preview_is_valid = global_position.distance_to(build_pos) <= BUILD_RANGE and _is_build_location_valid(build_pos)
		preview_connection_target = _find_preview_connection(build_pos)
		preview_barricade_links = _find_preview_barricade_links(build_pos)
		preview_instance.modulate = Color(0.45, 1.0, 0.78, 0.66) if preview_is_valid else Color(1.0, 0.28, 0.24, 0.66)
		queue_redraw()

func _process_rts_camera_panning(delta: float):
	if not is_instance_valid(camera): return

	var cam_move = Vector2.ZERO
	var vp_size = get_viewport_rect().size
	var m_pos = get_viewport().get_mouse_position()

	if m_pos.x <= EDGE_SCROLL_MARGIN: cam_move.x -= 1
	if m_pos.x >= vp_size.x - EDGE_SCROLL_MARGIN: cam_move.x += 1
	if m_pos.y <= EDGE_SCROLL_MARGIN: cam_move.y -= 1
	if m_pos.y >= vp_size.y - EDGE_SCROLL_MARGIN: cam_move.y += 1

	if Input.is_key_pressed(KEY_UP): cam_move.y -= 1
	if Input.is_key_pressed(KEY_DOWN): cam_move.y += 1
	if Input.is_key_pressed(KEY_LEFT): cam_move.x -= 1
	if Input.is_key_pressed(KEY_RIGHT): cam_move.x += 1

	if is_mmb_dragging:
		var mouse_delta = get_viewport().get_mouse_position() - mmb_drag_start_mouse
		camera.global_position = mmb_drag_start_cam - mouse_delta
	elif cam_move != Vector2.ZERO:
		camera.global_position += cam_move.normalized() * RTS_CAM_PAN_SPEED * delta

func _unhandled_input(event: InputEvent):
	if not _is_local_authority(): return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _handle_modal_esc_close():
			get_viewport().set_input_as_handled()
			return

	if current_class == PlayerClass.RANGED:
		_handle_rts_commander_input(event)
	else:
		_handle_techpriest_arpg_input(event)

func _handle_rts_commander_input(event: InputEvent):
	var mouse_world = get_global_mouse_position()
	var mouse_screen = get_viewport().get_mouse_position()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			is_mmb_dragging = true
			mmb_drag_start_mouse = mouse_screen
			mmb_drag_start_cam = camera.global_position
		else:
			is_mmb_dragging = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if is_instance_valid(camera): camera.global_position = global_position
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_box_selecting = true
			box_select_start_screen = mouse_screen
			box_select_current_screen = mouse_screen
		else:
			if is_box_selecting:
				is_box_selecting = false
				box_select_current_screen = mouse_screen
				if is_attack_move_queued:
					is_attack_move_queued = false
					_issue_order_to_selection(mouse_world, true)
				elif not _check_remote_building_click(mouse_world) and box_select_start_screen.distance_to(box_select_current_screen) < 8.0:
					_select_single_unit_under_cursor(mouse_world, Input.is_key_pressed(KEY_SHIFT))
				else:
					_execute_box_selection(Input.is_key_pressed(KEY_SHIFT))
				queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and is_box_selecting:
		box_select_current_screen = mouse_screen
		queue_redraw()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		is_attack_move_queued = false
		var target_enemy = _find_enemy_under_cursor(mouse_world)
		if is_instance_valid(target_enemy):
			_issue_attack_order_to_selection(target_enemy)
		else:
			_issue_order_to_selection(mouse_world, false)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_A:
			is_attack_move_queued = true
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S:
			_issue_stop_to_selection()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H:
			_issue_hold_to_selection()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			rpc_id(1, "request_orbital_strike", mouse_world)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			if bodyguard_level < GameData.MAX_BODYGUARDS:
				rpc_id(1, "request_upgrade_bodyguards")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Z:
			if damage_upgrade_level < GameData.MAX_DAMAGE_UPGRADES:
				rpc_id(1, "request_upgrade_damage")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_X:
			if speed_upgrade_level < GameData.MAX_SPEED_UPGRADES:
				rpc_id(1, "request_upgrade_speed")
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var group_num = event.keycode - KEY_0
			if Input.is_key_pressed(KEY_CTRL): _save_control_group(group_num)
			else: _load_control_group(group_num)
			get_viewport().set_input_as_handled()

func _handle_techpriest_arpg_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if is_building_mode:
			_cancel_build_mode()
		elif can_plasma_attack:
			rpc("perform_plasma_attack", get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_building_mode:
			var build_pos = preview_instance.global_position if is_instance_valid(preview_instance) else get_global_mouse_position()
			if global_position.distance_to(build_pos) <= BUILD_RANGE and _is_build_location_valid(build_pos):
				var main_node = get_parent()
				if main_node:
					main_node.rpc_id(1, "request_build_structure", build_pos, selected_building_type)
				AudioManager.play_sfx("building_place", build_pos, 0.0)
				_cancel_build_mode()
		elif can_attack:
			rpc("perform_attack", get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_E:
			request_interact_nearby_structure()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			rpc_id(1, "request_spawn_servo_skull")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_B or event.keycode == KEY_TAB:
			toggle_build_mode(selected_building_type)
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_1, KEY_KP_1]: toggle_build_mode(0); get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_2, KEY_KP_2]: toggle_build_mode(4); get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_3, KEY_KP_3]: toggle_build_mode(1); get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_4, KEY_KP_4]: toggle_build_mode(2); get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_5, KEY_KP_5]: toggle_build_mode(3); get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_6, KEY_KP_6]: toggle_build_mode(6); get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_7, KEY_KP_7]: toggle_build_mode(7); get_viewport().set_input_as_handled()

func _execute_box_selection(add_to_selection: bool):
	if not add_to_selection: _clear_rts_selection()

	var p1 = box_select_start_screen
	var p2 = box_select_current_screen
	var rect_min = Vector2(minf(p1.x, p2.x), minf(p1.y, p2.y))
	var rect_max = Vector2(maxf(p1.x, p2.x), maxf(p1.y, p2.y))
	var screen_rect = Rect2(rect_min, rect_max - rect_min)

	for unit in get_tree().get_nodes_in_group("controllable_units"):
		if is_instance_valid(unit):
			var u_screen = unit.get_global_transform_with_canvas().origin
			if screen_rect.has_point(u_screen):
				_add_unit_to_selection(unit)

	if rts_selected_units.is_empty() and screen_rect.has_point(get_global_transform_with_canvas().origin):
		_add_unit_to_selection(self)

func _select_single_unit_under_cursor(world_pos: Vector2, add_to_selection: bool):
	if not add_to_selection: _clear_rts_selection()
	for unit in get_tree().get_nodes_in_group("controllable_units"):
		if is_instance_valid(unit) and unit.global_position.distance_to(world_pos) <= 28.0:
			_add_unit_to_selection(unit)
			return

func _add_unit_to_selection(unit: Node2D):
	if not (unit in rts_selected_units):
		rts_selected_units.append(unit)
		if unit.has_method("set_rts_selected"): unit.set_rts_selected(true)
		elif "is_rts_selected" in unit: unit.is_rts_selected = true

func _clear_rts_selection():
	for unit in rts_selected_units:
		if is_instance_valid(unit):
			if unit.has_method("set_rts_selected"): unit.set_rts_selected(false)
			elif "is_rts_selected" in unit: unit.is_rts_selected = false
	rts_selected_units.clear()

func _issue_order_to_selection(target_pos: Vector2, is_attack_move: bool):
	if rts_selected_units.is_empty(): _add_unit_to_selection(self)

	var count = rts_selected_units.size()
	for i in range(count):
		var unit = rts_selected_units[i]
		if not is_instance_valid(unit): continue
		
		var offset = Vector2.ZERO
		if count > 1:
			var angle = (float(i) / float(count)) * TAU
			offset = Vector2(cos(angle), sin(angle)) * 32.0

		var slot_pos = target_pos + offset
		if unit.has_method("rts_move_to"):
			unit.rts_move_to(slot_pos, is_attack_move)
		elif unit == self:
			rts_target_move_pos = slot_pos
			rts_is_moving = true
			rts_is_attack_moving = is_attack_move
			rts_attack_target_node = null

	AudioManager.play_sfx("building_place", target_pos, -4.0, 1.6)

func _issue_attack_order_to_selection(target_enemy: Node2D):
	for unit in rts_selected_units:
		if is_instance_valid(unit):
			if unit.has_method("rts_attack_target"):
				unit.rts_attack_target(target_enemy)
			elif unit == self:
				rts_attack_target_node = target_enemy
				rts_is_moving = false

	AudioManager.play_sfx("volkite_beam", target_enemy.global_position, -2.0, 1.5)

func _issue_stop_to_selection():
	for unit in rts_selected_units:
		if is_instance_valid(unit):
			if unit.has_method("rts_stop"): unit.rts_stop()
			elif unit == self:
				rts_is_moving = false
				rts_attack_target_node = null

func _issue_hold_to_selection():
	for unit in rts_selected_units:
		if is_instance_valid(unit):
			if unit.has_method("rts_hold"): unit.rts_hold()
			elif unit == self:
				rts_is_moving = false

func _save_control_group(group_num: int):
	control_groups[group_num] = rts_selected_units.duplicate()

func _load_control_group(group_num: int):
	if control_groups.has(group_num):
		_clear_rts_selection()
		for unit in control_groups[group_num]:
			if is_instance_valid(unit): _add_unit_to_selection(unit)

func _check_remote_building_click(world_pos: Vector2) -> bool:
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.global_position.distance_to(world_pos) <= 32.0:
			var b_type = int(b.building_type) if "building_type" in b else -1
			if b_type == 6:
				var r_ui = get_tree().get_first_node_in_group("research_ui")
				if r_ui: r_ui.open_terminal(b); return true
			elif b_type == 2:
				var t_ui = get_tree().get_first_node_in_group("turret_upgrade_ui")
				if t_ui: t_ui.open_modal(b); return true
			elif b_type == 7:
				var c_ui = get_tree().get_first_node_in_group("cybernetica_ui")
				if c_ui: c_ui.open_terminal(b); return true

	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node) and base_node.global_position.distance_to(world_pos) <= 48.0:
		var b_ui = get_tree().get_first_node_in_group("base_upgrade_ui")
		if b_ui: b_ui.open_terminal(base_node); return true

	return false

func _handle_modal_esc_close() -> bool:
	var b_ui = get_tree().get_first_node_in_group("base_upgrade_ui")
	if b_ui and b_ui.visible: b_ui.close_terminal(); return true
	var r_ui = get_tree().get_first_node_in_group("research_ui")
	if r_ui and r_ui.visible: r_ui.close_terminal(); return true
	var t_ui = get_tree().get_first_node_in_group("turret_upgrade_ui")
	if t_ui and t_ui.visible: t_ui.close_modal(); return true
	var c_ui = get_tree().get_first_node_in_group("cybernetica_ui")
	if c_ui and c_ui.visible: c_ui.close_terminal(); return true
	var s_ui = get_tree().get_first_node_in_group("settings_ui")
	if s_ui and s_ui.visible: s_ui.toggle_settings(); return true
	var m_ui = get_tree().get_first_node_in_group("minimap_ui")
	if m_ui and m_ui.get("is_fullscreen_map"): m_ui.toggle_fullscreen_map(); return true
	if is_building_mode: _cancel_build_mode(); return true
	return false

func _draw():
	if current_class == PlayerClass.RANGED and _is_local_authority():
		_draw_rts_selection_box()
		_draw_marshal_command_aura()

	if is_building_mode and is_instance_valid(preview_instance):
		var local_build_pos = preview_instance.global_position - global_position
		var placement_color = Color(0.35, 1.0, 0.72, 0.9) if preview_is_valid else Color(1.0, 0.25, 0.20, 0.95)
		draw_arc(Vector2.ZERO, BUILD_RANGE, 0.0, TAU, 48, Color(0.20, 0.75, 0.95, 0.24), 1.5)

		if selected_building_type == 0 and not preview_barricade_links.is_empty():
			var wall_half_width = 5.0
			var pulse = 0.55 + sin(Time.get_ticks_msec() * 0.008) * 0.25
			var holo_fill = Color(0.20, 0.88, 1.0, 0.22 * pulse) if preview_is_valid else Color(1.0, 0.25, 0.20, 0.22 * pulse)
			var holo_edge = Color(0.25, 0.92, 1.0, 0.75 * pulse) if preview_is_valid else Color(1.0, 0.28, 0.22, 0.75 * pulse)

			for neighbor in preview_barricade_links:
				if not is_instance_valid(neighbor): continue
				var local_neighbor_pos = neighbor.global_position - global_position
				var dir = (local_neighbor_pos - local_build_pos).normalized()
				var perp = dir.orthogonal() * wall_half_width

				var holo_poly = PackedVector2Array([
					local_build_pos - perp, local_neighbor_pos - perp,
					local_neighbor_pos + perp, local_build_pos + perp
				])
				draw_colored_polygon(holo_poly, holo_fill)
				draw_line(local_build_pos - perp, local_neighbor_pos - perp, holo_edge, 1.5)
				draw_line(local_build_pos + perp, local_neighbor_pos + perp, holo_edge, 1.5)

		var b_size = _get_building_size(selected_building_type)
		var b_rect = Rect2(local_build_pos - (b_size * 0.5), b_size)
		draw_rect(b_rect, Color(placement_color.r, placement_color.g, placement_color.b, 0.15), true)
		draw_rect(b_rect, placement_color, false, 1.5)

func _draw_rts_selection_box():
	if not is_box_selecting: return
	var p1 = to_local(get_canvas_transform().affine_inverse() * box_select_start_screen)
	var p2 = to_local(get_canvas_transform().affine_inverse() * box_select_current_screen)
	var rect_min = Vector2(minf(p1.x, p2.x), minf(p1.y, p2.y))
	var rect_max = Vector2(maxf(p1.x, p2.x), maxf(p1.y, p2.y))
	var select_rect = Rect2(rect_min, rect_max - rect_min)
	var col_fill = Color(0.20, 0.88, 1.0, 0.15) if not is_attack_move_queued else Color(1.0, 0.25, 0.20, 0.15)
	var col_edge = Color(0.20, 0.88, 1.0, 0.85) if not is_attack_move_queued else Color(1.0, 0.25, 0.20, 0.85)
	draw_rect(select_rect, col_fill, true)
	draw_rect(select_rect, col_edge, false, 1.2)

func _draw_marshal_command_aura():
	var aura_radius = 230.0
	var is_conq = (active_doctrina == Doctrina.CONQUEROR)
	var pulse = 0.55 + sin(Time.get_ticks_msec() * 0.005) * 0.2
	var aura_color = Color(1.0, 0.75, 0.15, 0.35 * pulse) if is_conq else Color(0.20, 0.88, 1.0, 0.35 * pulse)
	var edge_color = Color(1.0, 0.80, 0.20, 0.75 * pulse) if is_conq else Color(0.30, 0.92, 1.0, 0.75 * pulse)
	draw_arc(Vector2.ZERO, aura_radius, 0.0, TAU, 36, aura_color, 1.5)
	draw_arc(Vector2.ZERO, aura_radius + 4.0, 0.0, TAU, 36, Color(edge_color.r, edge_color.g, edge_color.b, 0.2 * pulse), 1.0)

func _find_enemy_under_cursor(world_pos: Vector2) -> Node2D:
	var space = get_world_2d().direct_space_state
	if not space: return null
	var shape = CircleShape2D.new()
	shape.radius = 24.0
	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, world_pos)
	q.collide_with_bodies = true
	var hits = space.intersect_shape(q, 16)
	for hit in hits:
		var b = hit.collider
		if is_instance_valid(b) and (b.is_in_group("enemies") or b.is_in_group("objectives")):
			return b
	return null

func _find_nearest_enemy_in_range(range_limit: float) -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var closest: Node2D = null
	var min_d = range_limit
	for e in enemies:
		if is_instance_valid(e):
			var d = global_position.distance_to(e.global_position)
			if d < min_d: min_d = d; closest = e
	return closest

@rpc("any_peer", "call_local", "reliable")
func perform_attack(target_pos: Vector2):
	can_attack = false
	if visual_sprite and visual_sprite.has_method("trigger_attack_fx"):
		visual_sprite.trigger_attack_fx()
	
	if current_class == PlayerClass.RANGED:
		AudioManager.play_sfx("radium_shot", global_position, -3.0)
		if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
			var main_node = get_parent()
			if not (main_node and "spawner" in main_node):
				main_node = get_tree().get_first_node_in_group("main")

			if main_node and "spawner" in main_node and main_node.spawner:
				if "bullet_count" in main_node: main_node.bullet_count += 1
				var spawn_id = main_node.bullet_count if "bullet_count" in main_node else randi()
				var spawn_origin = global_position + Vector2(0, -12)
				var dir = (target_pos - spawn_origin).normalized()
				main_node.spawner.spawn({
					"type": "bullet", "name": "Bullet_" + str(spawn_id),
					"position": spawn_origin + (dir * 16.0), "direction": dir, "damage": bullet_damage
				})
	else:
		execute_melee_attack(target_pos)

	var timer = get_tree().create_timer(attack_cooldown)
	timer.timeout.connect(func(): if is_instance_valid(self): can_attack = true)

func execute_melee_attack(target_pos: Vector2):
	var attack_dir = (target_pos - global_position).normalized()
	is_attacking_anim = true
	attack_progress = 0.0
	attack_angle = attack_dir.angle()
	already_hit_enemies.clear()
	AudioManager.play_sfx("axe_swing", global_position, 0.0, 1.1)

@rpc("any_peer", "call_local", "reliable")
func perform_plasma_attack(target_pos: Vector2):
	can_plasma_attack = false
	if visual_sprite and visual_sprite.has_method("trigger_attack_fx"):
		visual_sprite.trigger_attack_fx()

	AudioManager.play_sfx("volkite_beam", global_position, -2.0, 1.4)
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		var main_node = get_parent()
		if not (main_node and "spawner" in main_node):
			main_node = get_tree().get_first_node_in_group("main")
		if main_node and "spawner" in main_node and main_node.spawner:
			if "bullet_count" in main_node: main_node.bullet_count += 1
			var spawn_origin = global_position + Vector2(0, -12)
			var dir = (target_pos - spawn_origin).normalized()
			main_node.spawner.spawn({
				"type": "bullet", "name": "PlasmaShot_" + str(randi()),
				"position": spawn_origin + (dir * 16.0), "direction": dir, "damage": plasma_damage,
				"is_plasma_caliver": true
			})

	var timer = get_tree().create_timer(plasma_cooldown)
	timer.timeout.connect(func(): if is_instance_valid(self): can_plasma_attack = true)

func check_lingering_melee_hits():
	var space_state = get_world_2d().direct_space_state
	if not space_state: return

	var shape = CircleShape2D.new()
	shape.radius = 65.0
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_bodies = true
	var results = space_state.intersect_shape(query, 32)
	var axe_dir = Vector2.RIGHT.rotated(attack_angle)

	for hit in results:
		var b = hit.collider
		if is_instance_valid(b) and (b.is_in_group("enemies") or b.is_in_group("objectives")) and not (b in already_hit_enemies):
			var to_target = b.global_position - global_position
			if abs(axe_dir.angle_to(to_target)) <= deg_to_rad(65.0):
				already_hit_enemies.append(b)
				if b.has_method("take_damage"):
					b.take_damage(40, to_target.normalized() * 260.0)
					AudioManager.play_sfx("hit", b.global_position, 1.0, 0.95)

@rpc("any_peer", "call_local", "reliable")
func request_orbital_strike(target_pos: Vector2):
	if not multiplayer.is_server(): return
	var main_node = get_parent()
	if not main_node or not main_node.has_method("spend_requisition"): return
	if orbital_strike_cooldown > 0.0: return
	
	if main_node.spend_requisition(GameData.ORBITAL_REQ_COST):
		orbital_strike_cooldown = GameData.ORBITAL_COOLDOWN_MAX
		rpc("sync_orbital_cooldown", GameData.ORBITAL_COOLDOWN_MAX)
		rpc("execute_orbital_strike_fx", target_pos)

		var space = get_world_2d().direct_space_state
		var shape = CircleShape2D.new()
		shape.radius = 160.0
		var q = PhysicsShapeQueryParameters2D.new()
		q.shape = shape
		q.transform = Transform2D(0.0, target_pos)
		q.collide_with_bodies = true
		var results = space.intersect_shape(q, 64)
		for hit in results:
			var body = hit.collider
			if is_instance_valid(body) and (body.is_in_group("enemies") or body.is_in_group("objectives")):
				if body.has_method("take_damage"):
					body.take_damage(220, (body.global_position - target_pos).normalized() * 450.0)

@rpc("any_peer", "call_local", "unreliable")
func execute_orbital_strike_fx(target_pos: Vector2):
	AudioManager.play_sfx("orbital_strike", target_pos, 4.0)

@rpc("any_peer", "call_local", "reliable")
func sync_orbital_cooldown(new_cd: float):
	orbital_strike_cooldown = new_cd

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_bodyguards():
	if multiplayer.is_server():
		var main_node = get_parent()
		if main_node and main_node.has_method("spend_requisition"):
			if not main_node.spend_requisition(GameData.BODYGUARD_REQ_COST): return
			bodyguard_level += 1
			rpc("sync_bodyguard_level", bodyguard_level)
			var offset = Vector2(35, 35) if active_bodyguards.size() > 0 else Vector2(-35, 0)
			main_node.spawner.spawn({
				"type": "bodyguard", "name": "Bodyguard_" + str(name) + "_" + str(randi()),
				"position": global_position + offset, "owner_id": name.to_int()
			})

@rpc("any_peer", "call_local", "reliable")
func sync_bodyguard_level(new_level: int):
	bodyguard_level = new_level

@rpc("any_peer", "call_local", "reliable")
func request_spawn_servo_skull():
	if current_class != PlayerClass.MELEE or not multiplayer.is_server(): return
	active_servo_skulls = active_servo_skulls.filter(func(s): return is_instance_valid(s))
	if active_servo_skulls.size() >= GameData.MAX_SERVO_SKULLS: return

	var main_node = get_parent()
	if not main_node or not ("scrap_amount" in main_node and "requisition_amount" in main_node): return

	if main_node.scrap_amount >= GameData.SERVO_SKULL_SCRAP_COST and main_node.requisition_amount >= GameData.SERVO_SKULL_REQ_COST:
		main_node.scrap_amount -= GameData.SERVO_SKULL_SCRAP_COST
		main_node.requisition_amount -= GameData.SERVO_SKULL_REQ_COST
		main_node.rpc("sync_resources", main_node.scrap_amount, main_node.requisition_amount)

		if "spawner" in main_node and main_node.spawner:
			main_node.spawner.spawn({
				"type": "servo_skull", "name": "ServoSkull_" + str(name) + "_" + str(randi()),
				"position": global_position + Vector2(30, -30), "owner_id": name.to_int()
			})

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_damage():
	if multiplayer.is_server():
		var main_node = get_parent()
		if main_node and main_node.has_method("spend_requisition"):
			if not main_node.spend_requisition(GameData.DAMAGE_UPGRADE_REQ_COST): return
			damage_upgrade_level += 1
			bullet_damage += 10
			rpc("sync_damage_upgrade", damage_upgrade_level, bullet_damage)

@rpc("any_peer", "call_local", "reliable")
func sync_damage_upgrade(new_lvl: int, new_dmg: int):
	damage_upgrade_level = new_lvl
	bullet_damage = new_dmg

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_speed():
	if multiplayer.is_server():
		var main_node = get_parent()
		if main_node and main_node.has_method("spend_requisition"):
			if not main_node.spend_requisition(GameData.SPEED_UPGRADE_REQ_COST): return
			speed_upgrade_level += 1
			speed += 35.0
			rpc("sync_speed_upgrade", speed_upgrade_level, speed)

@rpc("any_peer", "call_local", "reliable")
func sync_speed_upgrade(new_lvl: int, new_spd: float):
	speed_upgrade_level = new_lvl
	speed = new_spd

func _setup_tooltip_overlay() -> void:
	if not has_node("TooltipOverlay"):
		tooltip_overlay = TooltipOverlayRenderer.new()
		tooltip_overlay.name = "TooltipOverlay"
		tooltip_overlay.z_index = 150
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		tooltip_overlay.material = mat
		add_child(tooltip_overlay)

class TooltipOverlayRenderer extends Node2D:
	pass
