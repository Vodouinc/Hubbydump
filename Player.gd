extends CharacterBody2D

enum PlayerClass { MELEE, RANGED }
enum Doctrina { CONQUEROR, PROTECTOR }

@export var current_class: PlayerClass = PlayerClass.MELEE

@export var tech_priest_data: PlayerClassData
@export var skitarii_marshal_data: PlayerClassData

var speed: float = 300.0
var max_health: int = 100
var current_health: int = 100

var camera_trauma: float = 0.0
const TRAUMA_DECAY: float = 1.6
const MAX_SHAKE_OFFSET: float = 18.0
const MAX_SHAKE_ROLL: float = 0.04

var bullet_scene = preload("res://Bullet.tscn")
var attack_cooldown: float = 0.4
var bullet_damage: int = 20
var can_attack: bool = true

var can_plasma_attack: bool = true
var plasma_cooldown: float = 0.65
var plasma_damage: int = 30

var is_dead: bool = false
var respawn_timer: float = 0.0
const RESPAWN_DURATION: float = 10.0

var preview_validation_info: Dictionary = {"valid": false, "reason": "INITIALIZING"}
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
var hovered_interact_building: Node2D = null

const GRID_SIZE: float = 32.0
const WALL_LINK_RANGE: float = 95.0

# RTS Controller Engine
var rts_selected_units: Array[Node2D] = []
var is_box_selecting: bool = false
var box_select_start_world: Vector2 = Vector2.ZERO
var box_select_current_world: Vector2 = Vector2.ZERO
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
		z_index = 88 # Render hero and selection box above shadows and atmospheric dust
		
		# Prevent Godot from culling the selection box when Marshal is off-screen
		RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, Rect2(-2000, -2000, 4000, 4000))

		DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_CONFINED)

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

func set_player_class(new_class: int):
	current_class = new_class as PlayerClass
	apply_class_stats()
	
	if camera and _is_local_authority():
		if current_class == PlayerClass.RANGED:
			camera.top_level = true
			camera.global_position = global_position
		else:
			camera.top_level = false
			camera.position = Vector2.ZERO

func apply_class_stats():
	var is_techpriest = (current_class == PlayerClass.MELEE)
	var active_data = tech_priest_data if is_techpriest else skitarii_marshal_data
	
	if active_data:
		speed = active_data.movement_speed
		max_health = active_data.max_health
		attack_cooldown = active_data.attack_cooldown
		bullet_damage = active_data.base_damage
		attack_anim_duration = active_data.attack_anim_duration
	else:
		speed = 250.0 if is_techpriest else 340.0
		max_health = 150 if is_techpriest else 90
		bullet_damage = 25

	# Explicitly assign unit_type so VisualSprite draws the correct model
	if visual_sprite:
		visual_sprite.unit_type = 0 if is_techpriest else 1
		if visual_sprite.has_method("queue_redraw"):
			visual_sprite.queue_redraw()

	if shadow_node and shadow_node.has_method("update_shadow_size"):
		shadow_node.update_shadow_size()

	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)

# ------------------------------------------------------------------------------
# DAMAGE & HEALTH HANDLING
# ------------------------------------------------------------------------------

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO):
	if is_dead: return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return

	var actual_damage = float(amount)
	
	if current_class == PlayerClass.RANGED:
		if active_doctrina == Doctrina.PROTECTOR:
			actual_damage *= 0.65
		elif active_doctrina == Doctrina.CONQUEROR:
			actual_damage *= 1.20

	var new_health = max(0, current_health - int(actual_damage))
	if multiplayer.has_multiplayer_peer():
		rpc("sync_health", new_health)
	else:
		sync_health(new_health)

@rpc("call_local", "reliable")
func sync_health(new_hp: int):
	current_health = new_hp
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	if _is_local_authority():
		add_camera_trauma(0.30)
		AudioManager.play_sfx("hit", global_position, 1.0, 0.9)
		
		if current_class == PlayerClass.RANGED and is_instance_valid(camera):
			var cam_dist = camera.global_position.distance_to(global_position)
			if cam_dist > 450.0:
				AudioManager.play_sfx("klaxon_alert", camera.global_position, 2.0, 1.5)

	# Enter Cybernetic Reboot Stasis
	if current_health <= 0 and not is_dead:
		_handle_player_death_stasis()

func _handle_player_death_stasis():
	is_dead = true
	respawn_timer = RESPAWN_DURATION
	velocity = Vector2.ZERO
	is_building_mode = false
	is_box_selecting = false
	is_attack_move_queued = false

	# Disable collisions and hide sprite during reboot
	collision_layer = 0
	collision_mask = 0
	if visual_sprite: visual_sprite.visible = false
	if health_bar: health_bar.visible = false
	if shadow_node: shadow_node.visible = false

	if _is_local_authority():
		add_camera_trauma(0.60)
		AudioManager.play_sfx("orbital_strike", global_position, -2.0, 1.6)

		# Pan camera back to the Main Sanctum so player watches the base
		var base_node = get_tree().get_first_node_in_group("base")
		if is_instance_valid(base_node) and is_instance_valid(camera):
			var tween = create_tween()
			tween.tween_property(camera, "global_position", base_node.global_position, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _execute_sanctum_respawn():
	var base_node = get_tree().get_first_node_in_group("base")
	var spawn_pos = base_node.global_position + Vector2(0, 60) if is_instance_valid(base_node) else Vector2(500, 500)

	if multiplayer.has_multiplayer_peer():
		rpc("sync_respawn", spawn_pos)
	else:
		sync_respawn(spawn_pos)

@rpc("call_local", "reliable")
func sync_respawn(respawn_pos: Vector2):
	is_dead = false
	respawn_timer = 0.0
	current_health = max_health
	global_position = respawn_pos

	# Re-enable collision & visuals
	collision_layer = 1
	collision_mask = 1
	if visual_sprite: visual_sprite.visible = true
	if health_bar: 
		health_bar.visible = true
		health_bar.update_health(current_health, max_health)
	if shadow_node: shadow_node.visible = true

	# Resurrect sound & camera focus
	AudioManager.play_sfx("volkite_beam", global_position, 2.0, 1.4)
	
	if _is_local_authority():
		if camera:
			camera.global_position = global_position
		if current_class == PlayerClass.RANGED:
			_add_unit_to_selection(self)

# ------------------------------------------------------------------------------
# MOVEMENT & PHYSICS
# ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_dead: return # Halt all physics movement while dead

	if current_class == PlayerClass.MELEE:
		_process_techpriest_movement(delta)
	else:
		_process_marshal_rts_movement(delta)
		if _is_local_authority():
			_broadcast_marshal_doctrina_aura()

func _process_techpriest_movement(delta: float) -> void:
	if not _is_local_authority(): return

	var direction = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): direction.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): direction.y += 1

	if direction != Vector2.ZERO:
		# If camera was detached to peek at the map, re-attach it when you move
		if camera and camera.top_level:
			camera.top_level = false
			camera.position = Vector2.ZERO

		direction = direction.normalized()
		var corner_nudge = _calculate_corner_nudge(direction)
		velocity = (direction + corner_nudge).normalized() * speed

	if direction != Vector2.ZERO:
		direction = direction.normalized()
		var corner_nudge = _calculate_corner_nudge(direction)
		velocity = (direction + corner_nudge).normalized() * speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed * 12.0 * delta)

	velocity += _calculate_friendly_separation() * 60.0
	move_and_slide()

func _broadcast_marshal_doctrina_aura() -> void:
	var aura_radius = 230.0
	var is_conqueror = (active_doctrina == Doctrina.CONQUEROR)
	
	for unit in get_tree().get_nodes_in_group("controllable_units"):
		if is_instance_valid(unit) and unit != self:
			var in_range = global_position.distance_to(unit.global_position) <= aura_radius
			if unit.has_method("set_doctrina_buff"):
				unit.set_doctrina_buff(is_conqueror, in_range)

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

	velocity += _calculate_friendly_separation() * 60.0
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

func _calculate_friendly_separation() -> Vector2:
	var push = Vector2.ZERO
	for u in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(u) and u != self:
			var d = global_position.distance_to(u.global_position)
			if d < 32.0 and d > 0.1:
				push += (global_position - u.global_position).normalized() * (1.0 - (d / 32.0))
	return push

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

# ------------------------------------------------------------------------------
# BUILDING & INTERACTION
# ------------------------------------------------------------------------------

func toggle_build_mode(building_type_idx: int = 0):
	if is_building_mode and selected_building_type == building_type_idx:
		_cancel_build_mode()
		return
		
	_cancel_build_mode()
	
	is_building_mode = true
	selected_building_type = building_type_idx
	
	preview_instance = building_scene.instantiate()
	preview_instance.is_preview = true
	get_parent().add_child(preview_instance)
	preview_instance.setup_as_preview()
	preview_instance.building_type = selected_building_type
	_update_building_preview_position()

func _cancel_build_mode():
	is_building_mode = false
	preview_is_valid = false
	if is_instance_valid(preview_instance):
		preview_instance.queue_free()
		preview_instance = null
	queue_redraw()

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
		# --- STC ARCHEOTECH VAULT INTERACTION ---
		if closest.is_in_group("stc_vaults") and closest.has_method("interact_relic"):
			closest.interact_relic(self)
			return

		if closest.is_in_group("base"):
			if b_ui: b_ui.open_terminal(closest)
			return

		var main_node = get_tree().get_first_node_in_group("main")
		var b_type = int(closest.building_type) if "building_type" in closest else -1

		match b_type:
			0:
				if multiplayer.has_multiplayer_peer():
					if main_node: main_node.rpc_id(1, "request_upgrade_gate", closest.name)
				elif closest.has_method("try_upgrade_to_gate"):
					closest.try_upgrade_to_gate()
			2:
				var lvl = closest.turret_upgrade_level if "turret_upgrade_level" in closest else 0
				var spec = closest.turret_spec if "turret_spec" in closest else 0
				if lvl < 3:
					if multiplayer.has_multiplayer_peer():
						if main_node: main_node.rpc_id(1, "request_upgrade_turret", closest.name)
					elif closest.has_method("try_upgrade_turret"):
						closest.try_upgrade_turret()
				elif spec == GameData.TurretSpec.NONE and t_ui:
					t_ui.open_modal(closest)
			4:
				if multiplayer.has_multiplayer_peer():
					if main_node: main_node.rpc_id(1, "request_upgrade_distributor", closest.name)
				elif closest.has_method("try_upgrade_distributor"):
					closest.try_upgrade_distributor()
			6:
				if r_ui: r_ui.open_terminal(closest)
			7:
				if c_ui: c_ui.open_terminal(closest)

func _get_closest_interactable_structure() -> Node2D:
	var candidates: Array[Node2D] = []
	var mouse_world = get_global_mouse_position()

	# 1. Check Base Core (Within 80px reach)
	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		if global_position.distance_to(base_node.global_position) <= 80.0:
			candidates.append(base_node)

	# 2. Check STC Vaults (Within 75px reach)
	for vault in get_tree().get_nodes_in_group("stc_vaults"):
		if is_instance_valid(vault) and not vault.get("is_cleansed"):
			if global_position.distance_to(vault.global_position) <= 75.0:
				candidates.append(vault)

	# 3. Check Player Buildings (Within 75px reach)
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and not building.get("is_preview") and ("building_type" in building):
			if global_position.distance_to(building.global_position) <= 75.0:
				candidates.append(building)

	if candidates.is_empty():
		return null

	# If only one structure is in range, select it directly
	if candidates.size() == 1:
		return candidates[0]

	# --- MOUSE-FOCUS REDUNDANCY ---
	# If multiple structures are in range, pick the one the player is aiming at with the cursor
	var best_candidate: Node2D = null
	var best_score: float = 999999.0

	for c in candidates:
		var dist_to_mouse = mouse_world.distance_to(c.global_position)
		var dist_to_player = global_position.distance_to(c.global_position)

		# 75% priority to mouse aim direction, 25% to player proximity
		var score = (dist_to_mouse * 0.75) + (dist_to_player * 0.25)

		if score < best_score:
			best_score = score
			best_candidate = c

	return best_candidate

# ------------------------------------------------------------------------------
# PROCESS & REAL-TIME PREVIEW
# ------------------------------------------------------------------------------

func _process(delta: float):
# Handle Cybernetic Reboot Countdown
	if is_dead:
		if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
			respawn_timer -= delta
			if respawn_timer <= 0.0:
				_execute_sanctum_respawn()
		return

	if _is_local_authority():
		hovered_interact_building = _get_closest_interactable_structure()
		_process_camera_shake(delta)

		if is_box_selecting:
			box_select_current_world = get_global_mouse_position()
			queue_redraw()


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

		if is_building_mode:
			_update_building_preview_position()
			queue_redraw()

		var mouse_pos = get_global_mouse_position()
		if visual_sprite and visual_sprite.has_method("update_facing"):
			visual_sprite.update_facing(mouse_pos)

	if is_box_selecting:
		queue_redraw()

func _update_building_preview_position():
	if not is_instance_valid(preview_instance):
		preview_instance = building_scene.instantiate()
		preview_instance.is_preview = true
		get_parent().add_child(preview_instance)
		preview_instance.setup_as_preview()
		preview_instance.building_type = selected_building_type

	var mouse_world = get_global_mouse_position()
	var snapped_pos = mouse_world.snapped(Vector2(GRID_SIZE, GRID_SIZE))

	var info = GameData.STRUCTURE_INFO.get(selected_building_type, {})
	var requires_deposit = info.get("requires_deposit", false)
	if requires_deposit:
		var nearest_dep = _find_nearest_deposit(mouse_world, 80.0)
		if is_instance_valid(nearest_dep):
			snapped_pos = nearest_dep.global_position

	preview_instance.global_position = snapped_pos

	preview_validation_info = _validate_structure_placement(snapped_pos, selected_building_type)
	preview_is_valid = preview_validation_info.valid

	if preview_is_valid:
		preview_instance.modulate = Color(0.20, 0.88, 1.00, 0.80)
	else:
		preview_instance.modulate = Color(0.92, 0.22, 0.18, 0.55)

func _validate_structure_placement(target_pos: Vector2, b_type: int) -> Dictionary:
	var info = GameData.STRUCTURE_INFO.get(b_type, {})
	if info.is_empty():
		return {"valid": false, "reason": "UNKNOWN BLUEPRINT"}

	if global_position.distance_to(target_pos) > BUILD_RANGE:
		return {"valid": false, "reason": "OUT OF AUSPEX RANGE"}

	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		var cur_scrap = main_node.scrap_amount if "scrap_amount" in main_node else 0
		var cur_req = main_node.requisition_amount if "requisition_amount" in main_node else 0
		if cur_scrap < info.get("scrap", 0) or cur_req < info.get("req", 0):
			return {"valid": false, "reason": "INSUFFICIENT RESERVES"}

	var my_size: Vector2 = info.get("size", Vector2(32, 32))
	var my_radius = maxf(my_size.x, my_size.y) * 0.45

	var requires_deposit = info.get("requires_deposit", false)
	var deposits = get_tree().get_nodes_in_group("scrap_deposits")

	if requires_deposit:
		var target_deposit = _find_nearest_deposit(target_pos, 32.0)
		if not is_instance_valid(target_deposit):
			return {"valid": false, "reason": "MUST BE PLACED ON DEPOSIT"}

		for b in get_tree().get_nodes_in_group("buildings"):
			if is_instance_valid(b) and not b.get("is_preview") and b != preview_instance:
				if b.global_position.distance_to(target_deposit.global_position) < 28.0:
					return {"valid": false, "reason": "DEPOSIT ALREADY OCCUPIED"}
	else:
		for dep in deposits:
			if is_instance_valid(dep):
				var min_clearance = 28.0 + (my_radius * 0.85)
				if dep.global_position.distance_to(target_pos) < min_clearance:
					return {"valid": false, "reason": "RESERVED FOR EXTRACTOR"}

	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		if base_node.global_position.distance_to(target_pos) < 54.0:
			return {"valid": false, "reason": "SANCTUM ZONE OBSTRUCTED"}

	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.get("is_preview") and b != preview_instance:
			var other_type = int(b.get("building_type")) if "building_type" in b else 0
			var other_info = GameData.STRUCTURE_INFO.get(other_type, {})
			var other_size: Vector2 = other_info.get("size", Vector2(32, 32))
			var other_radius = maxf(other_size.x, other_size.y) * 0.45

			var min_dist = (my_radius + other_radius) * 0.85
			if b_type == 0 and other_type == 0:
				min_dist = 20.0

			if b.global_position.distance_to(target_pos) < min_dist:
				return {"valid": false, "reason": "TERRAIN OBSTRUCTED"}

	return {"valid": true, "reason": "READY FOR SANCTIFICATION"}

func _find_nearest_deposit(world_pos: Vector2, max_dist: float) -> Node2D:
	var closest: Node2D = null
	var min_d = max_dist
	for dep in get_tree().get_nodes_in_group("scrap_deposits"):
		if is_instance_valid(dep):
			var d = world_pos.distance_to(dep.global_position)
			if d < min_d:
				min_d = d
				closest = dep
	return closest

# ------------------------------------------------------------------------------
# HOLOGRAPHIC GRID & EXCLUSION ZONE DRAWING
# ------------------------------------------------------------------------------

func _draw():
	if not _is_local_authority(): return

	if is_building_mode and current_class == PlayerClass.MELEE:
		_draw_holographic_build_grid()

	elif current_class == PlayerClass.RANGED:
		if is_box_selecting:
			_draw_rts_selection_box()
		if is_attack_move_queued:
			_draw_attack_move_cursor_reticle()

func _draw_rts_selection_box():
	var p1 = to_local(box_select_start_world)
	var p2 = to_local(box_select_current_world)

	var rect_min = Vector2(minf(p1.x, p2.x), minf(p1.y, p2.y))
	var rect_max = Vector2(maxf(p1.x, p2.x), maxf(p1.y, p2.y))
	var select_rect = Rect2(rect_min, rect_max - rect_min)

	var col_fill = Color(0.20, 0.88, 1.0, 0.15) if not is_attack_move_queued else Color(1.0, 0.25, 0.20, 0.15)
	var col_edge = Color(0.20, 0.88, 1.0, 0.90) if not is_attack_move_queued else Color(1.0, 0.25, 0.20, 0.90)

	draw_rect(select_rect, col_fill, true)
	draw_rect(select_rect, col_edge, false, 1.5)

	# Corner bracket crosshairs on the selection box
	var c = 6.0
	draw_line(select_rect.position, select_rect.position + Vector2(c, 0), col_edge, 2.0)
	draw_line(select_rect.position, select_rect.position + Vector2(0, c), col_edge, 2.0)
	var tr = select_rect.position + Vector2(select_rect.size.x, 0)
	draw_line(tr, tr - Vector2(c, 0), col_edge, 2.0)
	draw_line(tr, tr + Vector2(0, c), col_edge, 2.0)
	var bl = select_rect.position + Vector2(0, select_rect.size.y)
	draw_line(bl, bl + Vector2(c, 0), col_edge, 2.0)
	draw_line(bl, bl - Vector2(0, c), col_edge, 2.0)
	var br = select_rect.position + select_rect.size
	draw_line(br, br - Vector2(c, 0), col_edge, 2.0)
	draw_line(br, br - Vector2(0, c), col_edge, 2.0)

func _draw_attack_move_cursor_reticle():
	var mouse_local = to_local(get_global_mouse_position())
	var pulse = 0.75 + sin(Time.get_ticks_msec() * 0.01) * 0.25
	var red_col = Color(1.0, 0.25, 0.20, 0.85 * pulse)

	draw_arc(mouse_local, 14.0, 0.0, TAU, 16, red_col, 1.4)
	draw_line(mouse_local + Vector2(-18, 0), mouse_local + Vector2(-6, 0), red_col, 1.5)
	draw_line(mouse_local + Vector2(6, 0), mouse_local + Vector2(18, 0), red_col, 1.5)
	draw_line(mouse_local + Vector2(0, -18), mouse_local + Vector2(0, -6), red_col, 1.5)
	draw_line(mouse_local + Vector2(0, 6), mouse_local + Vector2(0, 18), red_col, 1.5)

	var font = ThemeDB.fallback_font
	draw_string(font, mouse_local + Vector2(-30, 26), "ATTACK-MOVE", HORIZONTAL_ALIGNMENT_CENTER, 60, 8, red_col)

func _draw_holographic_build_grid() -> void:
	var pulse = 0.70 + sin(Time.get_ticks_msec() * 0.007) * 0.30
	var c_cyan_grid   := Color(0.20, 0.88, 1.00, 0.16 * pulse)
	var c_cyan_bright := Color(0.20, 0.88, 1.00, 0.80 * pulse)
	var c_amber       := Color(1.00, 0.72, 0.15, 0.85 * pulse)
	var c_red_alert   := Color(0.92, 0.22, 0.18, 0.85 * pulse)
	var c_red_dim     := Color(0.92, 0.22, 0.18, 0.15 * pulse)

	var mouse_world = get_global_mouse_position()
	var in_range = global_position.distance_to(mouse_world) <= BUILD_RANGE
	var info = GameData.STRUCTURE_INFO.get(selected_building_type, {})
	var requires_deposit = info.get("requires_deposit", false)

	draw_circle(Vector2.ZERO, BUILD_RANGE, Color(0.20, 0.88, 1.00, 0.04 * pulse))
	draw_arc(Vector2.ZERO, BUILD_RANGE, 0.0, TAU, 64, c_cyan_bright, 1.5)

	for i in range(12):
		var a = i * (TAU / 12.0)
		var p_outer = Vector2(cos(a), sin(a)) * BUILD_RANGE
		var p_inner = Vector2(cos(a), sin(a)) * (BUILD_RANGE - (8.0 if i % 3 == 0 else 4.0))
		draw_line(p_inner, p_outer, c_cyan_bright, 1.2 if i % 3 != 0 else 2.0)

	var half_grid_steps = int(ceil(BUILD_RANGE / GRID_SIZE))
	var player_snapped = global_position.snapped(Vector2(GRID_SIZE, GRID_SIZE))

	for gx in range(-half_grid_steps, half_grid_steps + 1):
		for gy in range(-half_grid_steps, half_grid_steps + 1):
			var world_cell = player_snapped + Vector2(gx * GRID_SIZE, gy * GRID_SIZE)
			var local_cell = to_local(world_cell)
			if local_cell.length() <= BUILD_RANGE:
				draw_circle(local_cell, 1.2, c_cyan_grid)

	_draw_obstacle_exclusion_zones(c_red_alert, c_red_dim, pulse, requires_deposit)

	var snap_target_world = preview_instance.global_position if is_instance_valid(preview_instance) else mouse_world.snapped(Vector2(GRID_SIZE, GRID_SIZE))
	var snap_local = to_local(snap_target_world)
	var tile_color = c_cyan_bright if preview_is_valid else (c_amber if not in_range else c_red_alert)

	var half_s = GRID_SIZE * 0.5
	var tile_rect = Rect2(snap_local - Vector2(half_s, half_s), Vector2(GRID_SIZE, GRID_SIZE))

	var c_len = 6.0
	draw_line(tile_rect.position, tile_rect.position + Vector2(c_len, 0), tile_color, 2.0)
	draw_line(tile_rect.position, tile_rect.position + Vector2(0, c_len), tile_color, 2.0)
	var tr = tile_rect.position + Vector2(tile_rect.size.x, 0)
	draw_line(tr, tr - Vector2(c_len, 0), tile_color, 2.0)
	draw_line(tr, tr + Vector2(0, c_len), tile_color, 2.0)
	var bl = tile_rect.position + Vector2(0, tile_rect.size.y)
	draw_line(bl, bl + Vector2(c_len, 0), tile_color, 2.0)
	draw_line(bl, bl - Vector2(0, c_len), tile_color, 2.0)
	var br = tile_rect.position + tile_rect.size
	draw_line(br, br - Vector2(c_len, 0), tile_color, 2.0)
	draw_line(br, br - Vector2(0, c_len), tile_color, 2.0)

	if not preview_is_valid:
		draw_rect(tile_rect, Color(0.92, 0.22, 0.18, 0.15), true)
		draw_line(tile_rect.position + Vector2(4, 4), br - Vector2(4, 4), c_red_alert, 1.4)
		draw_line(tr + Vector2(-4, 4), bl + Vector2(4, -4), c_red_alert, 1.4)
	else:
		draw_rect(tile_rect, Color(0.20, 0.88, 1.00, 0.10), true)

	draw_line(Vector2.ZERO, snap_local, Color(tile_color.r, tile_color.g, tile_color.b, 0.35), 1.2)
	_draw_cursor_status_badge(snap_local, tile_color)

func _draw_obstacle_exclusion_zones(c_red_alert: Color, c_red_dim: Color, pulse: float, placing_smelter: bool):
	var info = GameData.STRUCTURE_INFO.get(selected_building_type, {})
	var my_size: Vector2 = info.get("size", Vector2(32, 32))
	var my_radius = maxf(my_size.x, my_size.y) * 0.45

	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		var base_local = to_local(base_node.global_position)
		if base_local.length() <= BUILD_RANGE + 64.0:
			draw_arc(base_local, 46.0, 0, TAU, 32, Color(c_red_alert.r, c_red_alert.g, c_red_alert.b, 0.45 * pulse), 1.2)
			draw_circle(base_local, 46.0, c_red_dim)

	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.get("is_preview") and b != preview_instance:
			var b_local = to_local(b.global_position)
			if b_local.length() <= BUILD_RANGE + 48.0:
				var b_type = int(b.get("building_type")) if "building_type" in b else 0
				var b_info = GameData.STRUCTURE_INFO.get(b_type, {})
				var sz: Vector2 = b_info.get("size", Vector2(32, 32))
				var b_rect = Rect2(b_local - (sz * 0.5), sz)

				draw_rect(b_rect, Color(0.92, 0.22, 0.18, 0.12), true)
				draw_rect(b_rect, Color(c_red_alert.r, c_red_alert.g, c_red_alert.b, 0.40 * pulse), false, 1.0)
				draw_line(b_rect.position, b_rect.position + b_rect.size, Color(0.92, 0.22, 0.18, 0.25), 1.0)
				draw_line(b_rect.position + Vector2(b_rect.size.x, 0), b_rect.position + Vector2(0, b_rect.size.y), Color(0.92, 0.22, 0.18, 0.25), 1.0)

	for dep in get_tree().get_nodes_in_group("scrap_deposits"):
		if is_instance_valid(dep):
			var dep_local = to_local(dep.global_position)
			if dep_local.length() <= BUILD_RANGE + 64.0:
				if placing_smelter:
					var occupied = false
					for b in get_tree().get_nodes_in_group("buildings"):
						if is_instance_valid(b) and not b.get("is_preview") and b != preview_instance:
							if b.global_position.distance_to(dep.global_position) < 28.0:
								occupied = true
								break

					if occupied:
						draw_arc(dep_local, 28.0, 0, TAU, 24, Color(c_red_alert.r, c_red_alert.g, c_red_alert.b, 0.5 * pulse), 1.4)
						draw_circle(dep_local, 28.0, c_red_dim)
					else:
						var col = Color(1.0, 0.85, 0.20, 0.90 * pulse)
						draw_arc(dep_local, 28.0, 0, TAU, 24, col, 1.8)
						draw_circle(dep_local, 5.0, col)
						for i in range(4):
							var a = (float(i) * TAU / 4.0) + (Time.get_ticks_msec() * 0.002)
							var p = dep_local + Vector2(cos(a), sin(a)) * 28.0
							draw_circle(p, 2.0, col)
				else:
					var reserved_radius = 28.0 + (my_radius * 0.85)
					draw_arc(dep_local, reserved_radius, 0, TAU, 24, Color(c_red_alert.r, c_red_alert.g, c_red_alert.b, 0.50 * pulse), 1.2)
					draw_circle(dep_local, reserved_radius, Color(0.92, 0.22, 0.18, 0.10 * pulse))
					draw_line(dep_local - Vector2(8, 8), dep_local + Vector2(8, 8), Color(0.92, 0.22, 0.18, 0.4), 1.2)
					draw_line(dep_local + Vector2(-8, 8), dep_local + Vector2(8, -8), Color(0.92, 0.22, 0.18, 0.4), 1.2)

func _draw_cursor_status_badge(snap_local: Vector2, badge_color: Color):
	var text_str = "◆ %s ◆" % preview_validation_info.reason.to_upper()
	if not preview_is_valid:
		text_str = "⚠️ %s" % preview_validation_info.reason.to_upper()

	var font = ThemeDB.fallback_font
	var font_size = 9
	var text_w = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var badge_pos = snap_local + Vector2(- (text_w + 16) * 0.5, (GRID_SIZE * 0.5) + 6.0)
	var badge_rect = Rect2(badge_pos, Vector2(text_w + 16, 18))

	draw_rect(badge_rect, Color(0.04, 0.05, 0.08, 0.94), true)
	draw_rect(badge_rect, badge_color, false, 1.2)
	draw_string(font, badge_pos + Vector2(8, 12), text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, badge_color)

# ------------------------------------------------------------------------------
# CAMERA, RTS INPUT & SELECTION
# ------------------------------------------------------------------------------

func _process_rts_camera_panning(delta: float):
	if not is_instance_valid(camera): return

	var is_window_focused = get_window().has_focus() if get_window() else true
	if not is_window_focused:
		is_mmb_dragging = false
		return

	var cam_move = Vector2.ZERO
	var vp_size = get_viewport_rect().size
	var m_pos = get_viewport().get_mouse_position()

	if Rect2(Vector2.ZERO, vp_size).has_point(m_pos):
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

	if event is InputEventKey and event.pressed and not event.echo:
		# 1. Close open UI / Map with ESC
		if event.keycode == KEY_ESCAPE:
			if _handle_modal_esc_close():
				get_viewport().set_input_as_handled()
				return

		# 2. Toggle Fullscreen Tactical Map with 'M'
		if event.keycode == KEY_M and not is_dead:
			var m_ui = get_tree().get_first_node_in_group("minimap_ui")
			if m_ui and m_ui.has_method("toggle_fullscreen_map"):
				m_ui.toggle_fullscreen_map()
			elif m_ui and "is_fullscreen" in m_ui:
				m_ui.is_fullscreen = not m_ui.is_fullscreen
				m_ui.queue_redraw()
			get_viewport().set_input_as_handled()
			return

	if current_class == PlayerClass.RANGED:
		_handle_rts_commander_input(event)
	else:
		_handle_techpriest_arpg_input(event)

func set_building_type(type_id: int):
	selected_building_type = type_id
	if is_instance_valid(preview_instance):
		preview_instance.building_type = type_id

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

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_box_selecting = true
			box_select_start_world = mouse_world
			box_select_current_world = mouse_world
		else:
			if is_box_selecting:
				is_box_selecting = false
				box_select_current_world = mouse_world
				if is_attack_move_queued:
					is_attack_move_queued = false
					_issue_order_to_selection(mouse_world, true)
				elif not _check_remote_building_click(mouse_world) and box_select_start_world.distance_to(box_select_current_world) < 12.0:
					_select_single_unit_under_cursor(mouse_world, Input.is_key_pressed(KEY_SHIFT))
				else:
					_execute_box_selection(Input.is_key_pressed(KEY_SHIFT))
				queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and is_box_selecting:
		box_select_current_world = mouse_world
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
		if event.keycode == KEY_SPACE:
			if is_instance_valid(camera): 
				camera.global_position = global_position
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Q:
			_toggle_doctrina_imperative()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			var target_enemy = _find_enemy_under_cursor(mouse_world)
			if is_instance_valid(target_enemy):
				_designate_priority_target(target_enemy)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_A:
			is_attack_move_queued = true
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S:
			_issue_stop_to_selection()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H:
			_issue_hold_to_selection()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Z:
			if multiplayer.has_multiplayer_peer():
				rpc_id(1, "request_recruit_bodyguard", 0)
			else:
				request_recruit_bodyguard(0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_X:
			if multiplayer.has_multiplayer_peer():
				rpc_id(1, "request_recruit_bodyguard", 1)
			else:
				request_recruit_bodyguard(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			if multiplayer.has_multiplayer_peer():
				rpc_id(1, "request_recruit_bodyguard", 2)
			else:
				request_recruit_bodyguard(2)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_V:
			if multiplayer.has_multiplayer_peer():
				rpc_id(1, "request_field_requisition_uplink")
			else:
				request_field_requisition_uplink()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			if multiplayer.has_multiplayer_peer():
				rpc_id(1, "request_orbital_strike", mouse_world)
			else:
				request_orbital_strike(mouse_world)
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var group_num = event.keycode - KEY_0
			if Input.is_key_pressed(KEY_CTRL): _save_control_group(group_num)
			else: _load_control_group(group_num)
			get_viewport().set_input_as_handled()

func _toggle_doctrina_imperative() -> void:
	active_doctrina = Doctrina.PROTECTOR if active_doctrina == Doctrina.CONQUEROR else Doctrina.CONQUEROR
	
	if AudioManager.sfx_library.has("binary_canticle"):
		AudioManager.play_sfx("binary_canticle", global_position, 1.0, 1.2 if active_doctrina == Doctrina.CONQUEROR else 0.85)
	else:
		AudioManager.play_sfx("building_place", global_position, -2.0, 1.8 if active_doctrina == Doctrina.CONQUEROR else 1.2)
	
	_broadcast_marshal_doctrina_aura()
	var hud = get_tree().get_first_node_in_group("ability_hud")
	if hud and hud.has_method("refresh_hud_display"):
		hud.refresh_hud_display()
	queue_redraw()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Instantly release cursor confinement to prevent AMD driver lockup
			DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
			is_box_selecting = false
			is_mmb_dragging = false
			
		NOTIFICATION_APPLICATION_FOCUS_IN:
			# Re-confine only if in an active match as Commander
			if not is_dead and _is_local_authority():
				var main_node = get_tree().get_first_node_in_group("main")
				if main_node and main_node.get("match_started"):
					DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_CONFINED)

func _designate_priority_target(enemy: Node2D):
	if enemy.has_method("apply_telemetry_mark"):
		enemy.apply_telemetry_mark(8.0)
	
	_issue_attack_order_to_selection(enemy)
	AudioManager.play_sfx("volkite_beam", enemy.global_position, 1.0, 1.6)
	add_camera_trauma(0.20)

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
			if preview_is_valid and is_instance_valid(preview_instance):
				var build_pos = preview_instance.global_position
				var main_node = get_parent()
				if not (main_node and main_node.has_method("request_build_structure")):
					main_node = get_tree().get_first_node_in_group("main")
				if main_node:
					main_node.rpc_id(1, "request_build_structure", build_pos, selected_building_type)
				AudioManager.play_sfx("building_place", build_pos, 0.0)
				_cancel_build_mode()
			else:
				AudioManager.play_sfx("hit", global_position, -3.0, 1.8)
		elif can_attack:
			rpc("perform_attack", get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_E:
			request_interact_nearby_structure()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			if multiplayer.has_multiplayer_peer():
				rpc_id(1, "request_spawn_servo_skull")
			else:
				request_spawn_servo_skull()
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

# ------------------------------------------------------------------------------
# WORLD-SPACE BOX SELECTION
# ------------------------------------------------------------------------------

func _execute_box_selection(add_to_selection: bool):
	if not add_to_selection: _clear_rts_selection()

	var p1 = box_select_start_world
	var p2 = box_select_current_world
	var rect_min = Vector2(minf(p1.x, p2.x), minf(p1.y, p2.y))
	var rect_max = Vector2(maxf(p1.x, p2.x), maxf(p1.y, p2.y))
	var world_rect = Rect2(rect_min, rect_max - rect_min)

	for unit in get_tree().get_nodes_in_group("controllable_units"):
		if is_instance_valid(unit) and world_rect.has_point(unit.global_position):
			_add_unit_to_selection(unit)

	if rts_selected_units.is_empty() and world_rect.has_point(global_position):
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

# ------------------------------------------------------------------------------
# NETWORKED RTS COMMAND ROUTING (CLIENT -> SERVER)
# ------------------------------------------------------------------------------

func _issue_order_to_selection(target_pos: Vector2, is_attack_move: bool):
	if rts_selected_units.is_empty(): 
		_add_unit_to_selection(self)

	_spawn_rts_waypoint_marker(target_pos, is_attack_move)
	AudioManager.play_sfx("building_place", target_pos, -4.0, 1.6)

	var count = rts_selected_units.size()
	var unit_names: Array[String] = []

	for i in range(count):
		var unit = rts_selected_units[i]
		if not is_instance_valid(unit): continue
		unit_names.append(unit.name)

		var offset = Vector2.ZERO
		if count > 1:
			var angle = (float(i) / float(count)) * TAU
			offset = Vector2(cos(angle), sin(angle)) * 32.0
		var slot_pos = target_pos + offset

		if unit == self:
			rts_target_move_pos = slot_pos
			rts_is_moving = true
			rts_is_attack_moving = is_attack_move
			rts_attack_target_node = null
		elif not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
			if unit.has_method("rts_move_to"):
				unit.rts_move_to(slot_pos, is_attack_move)

	if multiplayer.has_multiplayer_peer():
		rpc_id(1, "request_rts_move_order", unit_names, target_pos, is_attack_move)

func _calculate_tactical_slot_offset(unit: Node2D, index: int, total_units: int, move_dir: Vector2) -> Vector2:
	if total_units <= 1: return Vector2.ZERO

	var perp = move_dir.orthogonal()
	var col_spacing = 26.0
	
	var depth_offset = 0.0
	if unit is KataphronUnit or unit is KastelanRobot:
		depth_offset = 20.0
	elif unit.get("unit_type") == GameData.CohortUnitType.RANGER:
		depth_offset = -35.0

	var lateral_slot = (index - (total_units * 0.5)) * col_spacing
	return (perp * lateral_slot) + (move_dir * depth_offset)

@rpc("any_peer", "call_local", "reliable")
func request_rts_move_order(unit_names: Array, target_pos: Vector2, is_attack_move: bool):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return

	var count = unit_names.size()
	for i in range(count):
		var u_name = str(unit_names[i])
		var unit: Node2D = null
		for candidate in get_tree().get_nodes_in_group("controllable_units"):
			if is_instance_valid(candidate) and candidate.name == u_name:
				unit = candidate
				break

		if not is_instance_valid(unit): continue

		var offset = Vector2.ZERO
		if count > 1:
			var angle = (float(i) / float(count)) * TAU
			offset = Vector2(cos(angle), sin(angle)) * 32.0

		var slot_pos = target_pos + offset
		if unit.has_method("rts_move_to"):
			unit.rts_move_to(slot_pos, is_attack_move)
		elif unit is CharacterBody2D and "rts_target_move_pos" in unit:
			unit.rts_target_move_pos = slot_pos
			unit.rts_is_moving = true
			unit.rts_is_attack_moving = is_attack_move
			unit.rts_attack_target_node = null

func _issue_attack_order_to_selection(target_enemy: Node2D):
	var unit_names: Array[String] = []
	for u in rts_selected_units:
		if is_instance_valid(u): unit_names.append(u.name)

	if multiplayer.has_multiplayer_peer():
		rpc_id(1, "request_rts_attack_order", unit_names, target_enemy.name)
	else:
		request_rts_attack_order(unit_names, target_enemy.name)

	AudioManager.play_sfx("volkite_beam", target_enemy.global_position, -2.0, 1.5)

@rpc("any_peer", "call_local", "reliable")
func request_rts_attack_order(unit_names: Array, target_name: String):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return

	var target_node: Node2D = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.name == target_name:
			target_node = e
			break

	if not is_instance_valid(target_node): return

	for u_name in unit_names:
		for candidate in get_tree().get_nodes_in_group("controllable_units"):
			if is_instance_valid(candidate) and candidate.name == str(u_name):
				if candidate.has_method("rts_attack_target"):
					candidate.rts_attack_target(target_node)
				elif "rts_attack_target_node" in candidate:
					candidate.rts_attack_target_node = target_node
					candidate.rts_is_moving = false
				break

func _issue_stop_to_selection():
	var unit_names: Array[String] = []
	for u in rts_selected_units:
		if is_instance_valid(u): unit_names.append(u.name)

	if multiplayer.has_multiplayer_peer():
		rpc_id(1, "request_rts_stop_order", unit_names)
	else:
		request_rts_stop_order(unit_names)

@rpc("any_peer", "call_local", "reliable")
func request_rts_stop_order(unit_names: Array):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	for u_name in unit_names:
		for candidate in get_tree().get_nodes_in_group("controllable_units"):
			if is_instance_valid(candidate) and candidate.name == str(u_name):
				if candidate.has_method("rts_stop"): candidate.rts_stop()
				elif "rts_is_moving" in candidate:
					candidate.rts_is_moving = false
					candidate.rts_attack_target_node = null
				break

func _issue_hold_to_selection():
	var unit_names: Array[String] = []
	for u in rts_selected_units:
		if is_instance_valid(u): unit_names.append(u.name)

	if multiplayer.has_multiplayer_peer():
		rpc_id(1, "request_rts_hold_order", unit_names)
	else:
		request_rts_hold_order(unit_names)

@rpc("any_peer", "call_local", "reliable")
func request_rts_hold_order(unit_names: Array):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	for u_name in unit_names:
		for candidate in get_tree().get_nodes_in_group("controllable_units"):
			if is_instance_valid(candidate) and candidate.name == str(u_name):
				if candidate.has_method("rts_hold"): candidate.rts_hold()
				elif "rts_is_moving" in candidate:
					candidate.rts_is_moving = false
				break
# ==============================================================================
# 1. RECRUIT BODYGUARD (MARSHAL: Z, X, C)
# ==============================================================================
@rpc("any_peer", "call_local", "reliable")
func request_recruit_bodyguard(role_id: int):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Clean up any destroyed bodyguards from the list
	active_bodyguards = active_bodyguards.filter(func(b): return is_instance_valid(b))

	if active_bodyguards.size() >= GameData.MAX_BODYGUARDS:
		return

	var role_info = GameData.BODYGUARD_ROSTER.get(role_id, {})
	if role_info.is_empty(): return

	var scrap_cost = role_info.get("scrap", 0)
	var req_cost = role_info.get("req", 0)

	var main_node = get_parent()
	if not (main_node and "scrap_amount" in main_node and "requisition_amount" in main_node):
		main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return

	# Verify resources
	if main_node.scrap_amount < scrap_cost or main_node.requisition_amount < req_cost:
		return

	main_node.scrap_amount -= scrap_cost
	main_node.requisition_amount -= req_cost

	if multiplayer.has_multiplayer_peer():
		main_node.rpc("sync_resources", main_node.scrap_amount, main_node.requisition_amount)

	var spawn_pos = global_position + Vector2.RIGHT.rotated(randf() * TAU) * 35.0
	var bg_data = {
		"type": "bodyguard",
		"name": "Bodyguard_" + str(name) + "_" + str(randi()),
		"position": spawn_pos,
		"guard_role": role_id,
		"owner_id": int(name) if name.is_valid_int() else 1
	}

	# ONLY use MultiplayerSpawner if online; otherwise spawn locally via _custom_spawner
	if main_node.spawner and multiplayer.has_multiplayer_peer():
		main_node.spawner.spawn(bg_data)
	else:
		var bg_node = main_node._custom_spawner(bg_data)
		if is_instance_valid(bg_node):
			main_node.add_child(bg_node)

	var hud = get_tree().get_first_node_in_group("ability_hud")
	if hud and hud.has_method("refresh_hud_display"):
		hud.refresh_hud_display()

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
	var closest_target: Node2D = null
	var min_d: float = range_limit
	for e in enemies:
		if is_instance_valid(e):
			var d = global_position.distance_to(e.global_position)
			if d < min_d:
				min_d = d
				closest_target = e
	return closest_target

# ------------------------------------------------------------------------------
# ATTACKS & UPGRADES
# ------------------------------------------------------------------------------

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
func request_field_requisition_uplink():
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var main_node = get_parent()
	if not (main_node and "scrap_amount" in main_node and "requisition_amount" in main_node):
		main_node = get_tree().get_first_node_in_group("main")

	var scrap_cost = 15
	var req_yield = 8

	if main_node and main_node.scrap_amount >= scrap_cost:
		main_node.scrap_amount -= scrap_cost
		main_node.requisition_amount += req_yield
		if multiplayer.has_multiplayer_peer():
			main_node.rpc("sync_resources", main_node.scrap_amount, main_node.requisition_amount)
		
		rpc("execute_supply_drop_fx", global_position)
		AudioManager.play_sfx("building_place", global_position, 1.0, 1.5)

@rpc("call_local", "unreliable")
func execute_supply_drop_fx(pos: Vector2):
	var label = Label.new()
	label.script = load("res://DamageNumber.gd")
	label.global_position = pos + Vector2(0, -35)
	get_parent().add_child(label)
	label.text = "⚡ +8 REQUISITION (TRANSMITTED) ⚡"
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.35, 0.95, 0.45)
	label.label_settings.font_size = 14

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
	if _is_local_authority():
		var dist = global_position.distance_to(target_pos)
		var intensity = clampf(1.0 - (dist / 900.0), 0.35, 1.0)
		add_camera_trauma(0.85 * intensity)

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

# ==============================================================================
# 2. FABRICATE SERVO-SKULL (TECH-PRIEST: C)
# ==============================================================================
@rpc("any_peer", "call_local", "reliable")
func request_spawn_servo_skull():
	if current_class != PlayerClass.MELEE: return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return

	active_servo_skulls = active_servo_skulls.filter(func(s): return is_instance_valid(s))
	if active_servo_skulls.size() >= GameData.MAX_SERVO_SKULLS: return

	var main_node = get_parent()
	if not (main_node and "scrap_amount" in main_node and "requisition_amount" in main_node):
		main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return

	if main_node.scrap_amount >= GameData.SERVO_SKULL_SCRAP_COST and main_node.requisition_amount >= GameData.SERVO_SKULL_REQ_COST:
		main_node.scrap_amount -= GameData.SERVO_SKULL_SCRAP_COST
		main_node.requisition_amount -= GameData.SERVO_SKULL_REQ_COST
		if multiplayer.has_multiplayer_peer():
			main_node.rpc("sync_resources", main_node.scrap_amount, main_node.requisition_amount)

		var skull_data = {
			"type": "servo_skull",
			"name": "ServoSkull_" + str(name) + "_" + str(randi()),
			"position": global_position + Vector2(30, -30),
			"owner_id": int(name) if name.is_valid_int() else 1
		}

		# ONLY use MultiplayerSpawner if online; otherwise spawn locally via _custom_spawner
		if main_node.spawner and multiplayer.has_multiplayer_peer():
			main_node.spawner.spawn(skull_data)
		else:
			var skull_node = main_node._custom_spawner(skull_data)
			if is_instance_valid(skull_node):
				main_node.add_child(skull_node)

		var hud = get_tree().get_first_node_in_group("ability_hud")
		if hud and hud.has_method("refresh_hud_display"):
			hud.refresh_hud_display()


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

# ------------------------------------------------------------------------------
# TOOLTIP & OVERLAY RENDERER
# ------------------------------------------------------------------------------

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
	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var p = get_parent()
		if not is_instance_valid(p) or p.current_class != 0: return
		if p.is_building_mode: return
		if not is_instance_valid(p.hovered_interact_building): return

		var b = p.hovered_interact_building
		var local_b_pos = b.global_position - p.global_position
		var font = ThemeDB.fallback_font

		# Determine if building has available upgrades or is at MAX tier
		var is_interactive = true
		var is_maxed = false

		if b.is_in_group("stc_vaults"):
			is_interactive = not b.get("is_cleansed")
		elif b.is_in_group("base") or ("building_type" in b and int(b.building_type) in [6, 7]):
			is_interactive = true # Terminals always accessible
		elif "building_type" in b:
			match int(b.building_type):
				0: is_maxed = b.get("is_gate") # Gate is maxed
				1, 3, 5: is_maxed = true       # Dynamos, Smelters, Antennas have no further upgrades
				2: # Turret
					var lvl = b.get("turret_upgrade_level") if b.get("turret_upgrade_level") != null else 0
					var spec = b.get("turret_spec") if b.get("turret_spec") != null else 0
					is_maxed = (lvl >= 3 and spec != 0)
				4: is_maxed = false

		var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.007) * 0.3
		var ring_r = 26.0
		if b.is_in_group("base"): ring_r = 52.0
		elif "building_type" in b and int(b.building_type) in [1, 3, 6, 7]: ring_r = 34.0

		if is_maxed:
			# --- GREYED-OUT "MAX" BADGE ---
			var grey_col = Color(0.42, 0.45, 0.50, 0.55)
			draw_arc(local_b_pos, ring_r, 0.0, TAU, 24, grey_col, 1.0)
			
			var badge_pos = local_b_pos + Vector2(0, -ring_r - 8.0)
			var badge_rect = Rect2(badge_pos - Vector2(12, 6), Vector2(24, 12))
			draw_rect(badge_rect, Color(0.04, 0.05, 0.08, 0.90), true)
			draw_rect(badge_rect, grey_col, false, 1.0)
			draw_string(font, badge_pos + Vector2(-10, 3), "MAX", HORIZONTAL_ALIGNMENT_CENTER, 20, 7, grey_col)
		else:
			# --- ACTIVE CYAN RETICLE & [E] PROMPT ---
			var ring_col = Color(0.20, 0.88, 1.0, 0.75 * pulse)
			draw_arc(local_b_pos, ring_r, 0.0, TAU, 32, ring_col, 1.2)
			draw_circle(local_b_pos, ring_r, Color(0.20, 0.88, 1.0, 0.05 * pulse))

			for i in range(4):
				var a = (float(i) * TAU / 4.0) + (Time.get_ticks_msec() * 0.001)
				var pt = local_b_pos + Vector2(cos(a), sin(a)) * ring_r
				draw_circle(pt, 1.8, ring_col)

			var icon_pos = local_b_pos + Vector2(0, -ring_r - 10.0)
			var key_rect = Rect2(icon_pos - Vector2(8, 8), Vector2(16, 16))
			draw_rect(key_rect, Color(0.04, 0.05, 0.08, 0.92), true)
			draw_rect(key_rect, ring_col, false, 1.0)
			draw_string(font, key_rect.position + Vector2(0, 11), "E", HORIZONTAL_ALIGNMENT_CENTER, 16, 8, ring_col)

# ------------------------------------------------------------------------------
# RTS WAYPOINT MARKER & CAMERA SHAKE
# ------------------------------------------------------------------------------

func _spawn_rts_waypoint_marker(target_pos: Vector2, is_attack_move: bool):
	var marker = RTSWaypointMarker.new()
	marker.global_position = target_pos
	marker.is_attack = is_attack_move
	get_parent().add_child(marker)

class RTSWaypointMarker extends Node2D:
	var is_attack: bool = false
	var lifetime: float = 0.45
	var elapsed: float = 0.0

	func _ready() -> void:
		z_index = 88 # Render hero and selection box above shadows and atmospheric dust
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat

	func _process(delta: float) -> void:
		elapsed += delta
		queue_redraw()
		if elapsed >= lifetime:
			queue_free()

	func _draw() -> void:
		var t = elapsed / lifetime
		var alpha = 1.0 - t
		var base_color = Color(1.0, 0.25, 0.20, alpha) if is_attack else Color(0.20, 0.88, 1.0, alpha)
		var r = lerpf(8.0, 22.0, sqrt(t))

		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.50))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, base_color, 1.5)
		draw_arc(Vector2.ZERO, r * 0.5, 0.0, TAU, 16, Color(base_color.r, base_color.g, base_color.b, alpha * 0.4), 1.0)

		for i in range(4):
			var a = (float(i) * TAU / 4.0) + (t * 2.0)
			var p_out = Vector2(cos(a), sin(a)) * r
			var p_in = Vector2(cos(a), sin(a)) * (r - 4.0)
			draw_line(p_in, p_out, base_color, 1.6)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func add_camera_trauma(amount: float) -> void:
	camera_trauma = clampf(camera_trauma + amount, 0.0, 1.0)

func _process_camera_shake(delta: float):
	if not is_instance_valid(camera): return

	if camera_trauma > 0.0:
		camera_trauma = maxf(0.0, camera_trauma - (TRAUMA_DECAY * delta))
		var shake = camera_trauma * camera_trauma
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * MAX_SHAKE_OFFSET * shake
		camera.rotation = randf_range(-1.0, 1.0) * MAX_SHAKE_ROLL * shake
	else:
		camera.offset = Vector2.ZERO
		camera.rotation = 0.0
