extends CharacterBody2D

enum PlayerClass { MELEE, RANGED }

@export var current_class: PlayerClass = PlayerClass.MELEE

# --- CLASS STAT RESOURCES ---
# Drag your tech_priest_stats.tres and skitarii_marshal_stats.tres here in the Inspector!
@export var tech_priest_data: PlayerClassData
@export var skitarii_marshal_data: PlayerClassData

# Active stat variables used by gameplay logic
var speed: float = 300.0
var max_health: int = 100
var current_health: int = 100

var bullet_scene = preload("res://Bullet.tscn")

var attack_cooldown: float = 0.4
var bullet_damage: int = 20
var can_attack: bool = true

# --- SERVO-SKULL CONFIGURATION ---
var active_servo_skulls: Array = []
const MAX_SERVO_SKULLS: int = 2          # Maximum active skulls at once
const SERVO_SKULL_SCRAP_COST: int = 20   # Must match AbilityHUD.gd
const SERVO_SKULL_REQ_COST: int = 10     # Must match AbilityHUD.gd

# --- MELEE ATTACK ANIMATION & HITBOX STATE ---
var is_attacking_anim: bool = false
var attack_progress: float = 0.0
var attack_angle: float = 0.0
var attack_anim_duration: float = 0.2  # Speed of the arc swing in seconds

# Tracks enemies hit during the CURRENT swing so they aren't damaged twice
var already_hit_enemies: Array = []

# --- BUILDING SYSTEM STATE ---
var selected_building_type: int = 0 # 0: Barricade, 1: Generator, 2: Turret
const BUILDING_COSTS = [15, 25, 35] # Costs for Barricade, Generator, Turret
const MIN_BUILDING_SPACING: float = 60.0 # Proximity clearance radius
const BUILD_RANGE: float = 220.0
const BUILD_SNAP_DISTANCE: float = 18.0
const CONDUIT_RANGE: float = 360.0
const TURRET_INTERACTION_RANGE: float = 85.0
var building_scene = preload("res://Building.tscn")
var is_building_mode: bool = false
var preview_instance: Node2D = null
var preview_is_valid: bool = false
var preview_connection_target: Node2D = null

# --- BODYGUARD SYSTEM STATE ---
var bodyguard_scene = preload("res://SkitariiBodyguard.tscn")
var bodyguard_level: int = 0 # 0 = No bodyguards, 1 = One bodyguard, 2 = Two bodyguards
var bodyguard_instance_count: int = 0
var active_bodyguards: Array = []
@export var bodyguard_cost: int = 5 # Cost per upgrade level

# --- SKITARII MARSHAL UPGRADE SYSTEM ---
var damage_upgrade_level: int = 0
const MAX_DAMAGE_UPGRADES: int = 3
@export var damage_upgrade_cost: int = 10

var speed_upgrade_level: int = 0
const MAX_SPEED_UPGRADES: int = 3
@export var speed_upgrade_cost: int = 10

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
	apply_class_stats()
	
	set_process_unhandled_input(_is_local_authority())
	
	if _is_local_authority():
		if label:
			label.text += " [YOU]"
		if camera:
			camera.enabled = true
			camera.make_current()
			
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
	
	if visual_sprite:
		var active_data = tech_priest_data if current_class == PlayerClass.MELEE else skitarii_marshal_data
		if active_data:
			visual_sprite.unit_type = active_data.unit_type_id
		else:
			visual_sprite.unit_type = 1 if (new_class == 1 or new_class == PlayerClass.RANGED) else 0

func apply_class_stats():
	var active_data: PlayerClassData = null
	
	match current_class:
		PlayerClass.MELEE:
			active_data = tech_priest_data
			if label:
				label.text = "Tech-Priest"
		PlayerClass.RANGED:
			active_data = skitarii_marshal_data
			if label:
				label.text = "Skitarii Marshal"
				
	if active_data:
		speed = active_data.movement_speed
		max_health = active_data.max_health
		attack_cooldown = active_data.attack_cooldown
		bullet_damage = active_data.base_damage
		attack_anim_duration = active_data.attack_anim_duration
		
		if visual_sprite:
			visual_sprite.unit_type = active_data.unit_type_id
	else:
		# Fallback defaults if .tres hasn't been assigned yet in the editor
		if current_class == PlayerClass.MELEE:
			speed = 250.0
			max_health = 150
		else:
			speed = 350.0
			max_health = 80
			bullet_damage = 25

	if shadow_node and shadow_node.has_method("update_shadow_size"):
		shadow_node.update_shadow_size()

	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)

	if is_multiplayer_authority():
		var hud = get_tree().get_first_node_in_group("ability_hud")
		if hud and hud.has_method("update_hud_layout"):
			hud.update_hud_layout()

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO):
	if multiplayer.is_server():
		var new_hp = max(0, current_health - amount)
		rpc("sync_player_health", new_hp)

@rpc("call_local", "reliable")
func sync_player_health(new_hp: int):
	current_health = new_hp
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

func _physics_process(_delta):
	if is_multiplayer_authority():
		var direction = Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): direction.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): direction.y += 1

		velocity = direction.normalized() * speed
		move_and_slide()

# --- BUILDING SYSTEM CONTROLS ---

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
	if is_instance_valid(preview_instance):
		preview_instance.queue_free()
		preview_instance = null
	queue_redraw()
		
func update_preview_type():
	if is_instance_valid(preview_instance):
		if "building_type" in preview_instance:
			preview_instance.building_type = selected_building_type
		# If your preview instance has a method to refresh its visual sprite/mesh:
		if preview_instance.has_method("setup_as_preview"):
			preview_instance.setup_as_preview()

func _is_build_location_valid(build_pos: Vector2) -> bool:
	var preview_radius = _get_structure_foundation_radius(preview_instance)
	var structures: Array = get_tree().get_nodes_in_group("buildings")
	structures.append_array(get_tree().get_nodes_in_group("base"))
	for structure in structures:
		if is_instance_valid(structure) and structure != preview_instance:
			var required_clearance = preview_radius + _get_structure_foundation_radius(structure) + 12.0
			if structure.global_position.distance_to(build_pos) < max(MIN_BUILDING_SPACING, required_clearance):
				return false
	return true

func _get_structure_foundation_radius(node: Node2D) -> float:
	if node.is_in_group("base"):
		return 115.0
	if "building_type" in node:
		match int(node.building_type):
			0: return 32.0
			1: return 52.0
			2: return 45.0
			3: return 58.0
	return 32.0

func _get_snapped_build_position(mouse_pos: Vector2) -> Vector2:
	var snapped = mouse_pos.snapped(Vector2(8.0, 8.0))
	var preview_radius = _get_structure_foundation_radius(preview_instance)
	var candidates: Array = get_tree().get_nodes_in_group("buildings")
	candidates.append_array(get_tree().get_nodes_in_group("base"))
	for candidate in candidates:
		if not is_instance_valid(candidate) or candidate == preview_instance:
			continue
		var outward = snapped - candidate.global_position
		if outward.length_squared() < 0.01:
			continue
		var anchor = candidate.global_position + outward.normalized() * (_get_structure_foundation_radius(candidate) + preview_radius + 12.0)
		if snapped.distance_to(anchor) <= BUILD_SNAP_DISTANCE:
			return anchor.snapped(Vector2(4.0, 4.0))
	return snapped

func _find_preview_connection(build_pos: Vector2) -> Node2D:
	var closest: Node2D = null
	var closest_distance := CONDUIT_RANGE
	var candidates: Array = get_tree().get_nodes_in_group("buildings")
	candidates.append_array(get_tree().get_nodes_in_group("base"))
	for candidate in candidates:
		if not is_instance_valid(candidate) or candidate == preview_instance:
			continue
		var distance = candidate.global_position.distance_to(build_pos)
		if distance < closest_distance:
			closest_distance = distance
			closest = candidate
	return closest

func request_upgrade_nearby_turret() -> void:
	var closest_turret: Node2D = null
	var closest_distance := TURRET_INTERACTION_RANGE
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not ("building_type" in building):
			continue
		if int(building.building_type) != 2:
			continue
		var distance = global_position.distance_to(building.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_turret = building
	if is_instance_valid(closest_turret):
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node:
			main_node.rpc_id(1, "request_upgrade_turret", closest_turret.name)

# --- PROCESS LOOP ---

func _process(delta):
	if is_attacking_anim:
		attack_progress += delta / attack_anim_duration
		
		if multiplayer.is_server():
			check_lingering_melee_hits()

		if attack_progress >= 1.0:
			is_attacking_anim = false
			attack_progress = 0.0
			already_hit_enemies.clear()

		queue_redraw()

	if _is_local_authority():
		var mouse_pos = get_global_mouse_position()
		if visual_sprite:
			visual_sprite.look_at(mouse_pos)

	if _is_local_authority() and is_building_mode and is_instance_valid(preview_instance):
		var build_pos = _get_snapped_build_position(get_global_mouse_position())
		preview_instance.global_position = build_pos
		preview_is_valid = global_position.distance_to(build_pos) <= BUILD_RANGE and _is_build_location_valid(build_pos)
		preview_connection_target = _find_preview_connection(build_pos)
		preview_instance.modulate = Color(0.45, 1.0, 0.78, 0.66) if preview_is_valid else Color(1.0, 0.28, 0.24, 0.66)
		queue_redraw()

func _draw():
	if is_attacking_anim:
		draw_omnissian_axe_sweep()
	if is_building_mode and is_instance_valid(preview_instance):
		var local_build_pos = preview_instance.global_position - global_position
		var placement_color = Color(0.35, 1.0, 0.72, 0.9) if preview_is_valid else Color(1.0, 0.25, 0.20, 0.95)
		draw_arc(Vector2.ZERO, BUILD_RANGE, 0.0, TAU, 48, Color(0.20, 0.75, 0.95, 0.24), 1.5)
		draw_arc(local_build_pos, _get_structure_foundation_radius(preview_instance) + 7.0, 0.0, TAU, 24, placement_color, 2.0)
		draw_circle(local_build_pos, 3.0, placement_color)
		if is_instance_valid(preview_connection_target):
			var local_target = preview_connection_target.global_position - global_position
			draw_line(local_target, local_build_pos, Color(0.25, 0.85, 1.0, 0.45), 2.0)

func draw_omnissian_axe_sweep():
	var eased_progress = pow(attack_progress, 2.5) 
	var total_cone = deg_to_rad(120.0)
	var current_angle = attack_angle - (total_cone / 2.0) + (eased_progress * total_cone)
	
	var reach_length: float = 70.0
	var shaft_dir = Vector2.RIGHT.rotated(current_angle)
	var axe_head_pos = shaft_dir * reach_length
	
	var brass_color = Color("#b8860b")     
	var dark_iron_color = Color("#1a202c") 
	var steel_edge_color = Color("#e2e8f0")
	var trail_red = Color("#8b0000", 0.3)    

	if attack_progress > 0.05 and attack_progress < 0.95:
		var trail_start = current_angle - deg_to_rad(20.0)
		draw_arc(Vector2.ZERO, reach_length, trail_start, current_angle, 8, trail_red, 5.0)

	draw_line(Vector2.ZERO, axe_head_pos, dark_iron_color, 6.0)
	draw_line(Vector2.ZERO, axe_head_pos, brass_color, 3.0)

	var head_perp = shaft_dir.orthogonal()
	var cog_center = axe_head_pos - (shaft_dir * 14.0)
	var num_teeth = 5
	var cog_radius = 12.0
	for i in range(num_teeth):
		var tooth_angle = current_angle + PI + lerp(-PI / 2.2, PI / 2.2, float(i) / (num_teeth - 1))
		var tooth_dir = Vector2.RIGHT.rotated(tooth_angle)
		var tooth_base = cog_center + (tooth_dir * (cog_radius - 3.0))
		var tooth_tip = cog_center + (tooth_dir * (cog_radius + 4.0))
		draw_line(tooth_base, tooth_tip, brass_color, 4.0)

	var blade_top = axe_head_pos + (head_perp * 22.0) - (shaft_dir * 12.0)
	var blade_bottom_socket = axe_head_pos - (head_perp * 6.0) - (shaft_dir * 18.0)
	
	var blade_polygon = PackedVector2Array([
		cog_center,
		blade_top,
		axe_head_pos,
		blade_bottom_socket
	])
	draw_polygon(blade_polygon, [dark_iron_color, dark_iron_color, dark_iron_color, dark_iron_color])
	
	draw_line(blade_top, axe_head_pos, steel_edge_color, 3.5)
	draw_line(blade_bottom_socket, axe_head_pos, steel_edge_color, 2.5)

func check_lingering_melee_hits():
	var eased_progress = pow(attack_progress, 2.5) 
	var total_cone = deg_to_rad(120.0)
	var current_axe_angle = attack_angle - (total_cone / 2.0) + (eased_progress * total_cone)
	var axe_dir = Vector2.RIGHT.rotated(current_axe_angle)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy in already_hit_enemies:
			continue
			
		var to_enemy = enemy.global_position - global_position
		var dist = to_enemy.length()
		
		if dist <= 85.0:
			var angle_diff = abs(axe_dir.angle_to(to_enemy))
			if angle_diff <= deg_to_rad(35.0):
				already_hit_enemies.append(enemy)
				if enemy.has_method("take_damage"):
					var knockback_dir = to_enemy.normalized()
					var knockback_strength: float = 250.0
					enemy.take_damage(40, knockback_dir * knockback_strength)

# --- UNHANDLED INPUT (KEYBOARD & MOUSE) ---

func _unhandled_input(event):
	if not is_multiplayer_authority():
		return

	# Tech-Priest Building & Support Inputs
	if current_class == PlayerClass.MELEE:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_E:
				request_upgrade_nearby_turret()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_K: # Press K to deploy a Servo-skull
				rpc("request_spawn_servo_skull")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_B or event.keycode == KEY_TAB:
				toggle_build_mode(selected_building_type)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_1 or event.keycode == KEY_KP_1:
				if not is_building_mode:
					toggle_build_mode(0)
				else:
					selected_building_type = 0
					update_preview_type()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_2 or event.keycode == KEY_KP_2:
				if not is_building_mode:
					toggle_build_mode(1)
				else:
					selected_building_type = 1
					update_preview_type()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_3 or event.keycode == KEY_KP_3:
				if not is_building_mode:
					toggle_build_mode(2)
				else:
					selected_building_type = 2
					update_preview_type()
				get_viewport().set_input_as_handled()
				return

		if is_building_mode:
			if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or \
			   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
				_cancel_build_mode()
				get_viewport().set_input_as_handled()
				return

			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				var build_pos = preview_instance.global_position if is_instance_valid(preview_instance) else get_global_mouse_position()
				if global_position.distance_to(build_pos) <= BUILD_RANGE:
					if _is_build_location_valid(build_pos):
						var main_node = get_parent()
						if main_node:
							main_node.rpc_id(1, "request_build_structure", build_pos, selected_building_type)
						_cancel_build_mode()
					else:
						print("[Build System] Placement blocked: Too close to another building!")
				else:
					print("[Build System] Placement blocked: Target out of range!")
				
				get_viewport().set_input_as_handled()
				return
				

	# Skitarii Marshal Bodyguard & Upgrade Controls
	if current_class == PlayerClass.RANGED and event is InputEventKey and event.pressed:
		if event.keycode == KEY_N:
			if bodyguard_level < 2:
				rpc("request_upgrade_bodyguards")
				get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_M: # Upgrade Weapon Damage
			if damage_upgrade_level < MAX_DAMAGE_UPGRADES:
				rpc("request_upgrade_damage")
				get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_V: # Upgrade Movement Speed
			if speed_upgrade_level < MAX_SPEED_UPGRADES:
				rpc("request_upgrade_speed")
				get_viewport().set_input_as_handled()
			return

	# Primary Attack Execution
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if can_attack:
			var target_pos = get_global_mouse_position()
			rpc("perform_attack", target_pos)

# --- BODYGUARD UPGRADE RPC SYSTEM ---

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_bodyguards():
	if multiplayer.is_server():
		if bodyguard_level >= 2:
			return
			
		var main_node = get_parent()
		if main_node:
			var current_requisition: int = 0
			if "requisition_amount" in main_node:
				current_requisition = main_node.requisition_amount
			elif "requisition" in main_node:
				current_requisition = main_node.requisition
			elif main_node.has_method("get_requisition"):
				current_requisition = main_node.get_requisition()
			else:
				current_requisition = 999

			if current_requisition >= bodyguard_cost:
				if main_node.has_method("spend_requisition"):
					if not main_node.spend_requisition(bodyguard_cost):
						return
				elif "requisition_amount" in main_node:
					main_node.requisition_amount -= bodyguard_cost

				bodyguard_level += 1
				rpc("sync_bodyguard_level", bodyguard_level)
				spawn_bodyguard_instance()
				
@rpc("any_peer", "call_local", "reliable")
func request_spawn_servo_skull():
	if current_class != PlayerClass.MELEE or not multiplayer.is_server():
		return

	# Clean up any destroyed / freed skulls from the array
	active_servo_skulls = active_servo_skulls.filter(func(s): return is_instance_valid(s))
	
	# 1. Enforce Max Limit
	if active_servo_skulls.size() >= MAX_SERVO_SKULLS:
		print("[Servo-Skull] Max active skulls reached (%d/%d)!" % [active_servo_skulls.size(), MAX_SERVO_SKULLS])
		return

	var main_node = get_parent()
	if not main_node or not ("scrap_amount" in main_node and "requisition_amount" in main_node):
		return

	# 2. Enforce Resource Cost Check
	if main_node.scrap_amount >= SERVO_SKULL_SCRAP_COST and main_node.requisition_amount >= SERVO_SKULL_REQ_COST:
		# Deduct resources
		main_node.scrap_amount -= SERVO_SKULL_SCRAP_COST
		main_node.requisition_amount -= SERVO_SKULL_REQ_COST
		main_node.rpc("sync_resources", main_node.scrap_amount, main_node.requisition_amount)

		# 3. Spawn the Servo-Skull
		if "spawner" in main_node and main_node.spawner:
			var skull_data = {
				"type": "servo_skull",
				"name": "ServoSkull_" + str(name) + "_" + str(randi()),
				"position": global_position + Vector2(30, -30),
				"owner_id": name.to_int()
			}
			var new_skull = main_node.spawner.spawn(skull_data)
			if new_skull:
				active_servo_skulls.append(new_skull)

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_damage():
	if multiplayer.is_server():
		if damage_upgrade_level >= MAX_DAMAGE_UPGRADES:
			return
			
		var main_node = get_parent()
		if main_node:
			var current_requisition: int = 0
			if "requisition_amount" in main_node:
				current_requisition = main_node.requisition_amount
			elif "requisition" in main_node:
				current_requisition = main_node.requisition
			elif main_node.has_method("get_requisition"):
				current_requisition = main_node.get_requisition()
			else:
				current_requisition = 999

			if current_requisition >= damage_upgrade_cost:
				if main_node.has_method("spend_requisition"):
					if not main_node.spend_requisition(damage_upgrade_cost):
						return
				elif "requisition_amount" in main_node:
					main_node.requisition_amount -= damage_upgrade_cost

				damage_upgrade_level += 1
				bullet_damage += 10
				rpc("sync_damage_upgrade", damage_upgrade_level, bullet_damage)

@rpc("any_peer", "call_local", "reliable")
func sync_damage_upgrade(new_level: int, new_damage: int):
	damage_upgrade_level = new_level
	bullet_damage = new_damage
	if is_multiplayer_authority():
		var hud = get_tree().get_first_node_in_group("ability_hud")
		if hud and hud.has_method("update_hud_layout"):
			hud.update_hud_layout()

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_speed():
	if multiplayer.is_server():
		if speed_upgrade_level >= MAX_SPEED_UPGRADES:
			return
			
		var main_node = get_parent()
		if main_node:
			var current_requisition: int = 0
			if "requisition_amount" in main_node:
				current_requisition = main_node.requisition_amount
			elif "requisition" in main_node:
				current_requisition = main_node.requisition
			elif main_node.has_method("get_requisition"):
				current_requisition = main_node.get_requisition()
			else:
				current_requisition = 999

			if current_requisition >= speed_upgrade_cost:
				if main_node.has_method("spend_requisition"):
					if not main_node.spend_requisition(speed_upgrade_cost):
						return
				elif "requisition_amount" in main_node:
					main_node.requisition_amount -= speed_upgrade_cost

				speed_upgrade_level += 1
				speed += 35.0
				rpc("sync_speed_upgrade", speed_upgrade_level, speed)

@rpc("any_peer", "call_local", "reliable")
func sync_speed_upgrade(new_level: int, new_speed: float):
	speed_upgrade_level = new_level
	speed = new_speed
	if is_multiplayer_authority():
		var hud = get_tree().get_first_node_in_group("ability_hud")
		if hud and hud.has_method("update_hud_layout"):
			hud.update_hud_layout()

@rpc("any_peer", "call_local", "reliable")
func sync_bodyguard_level(new_level: int):
	bodyguard_level = new_level
	if is_multiplayer_authority():
		var hud = get_tree().get_first_node_in_group("ability_hud")
		if hud and hud.has_method("update_hud_layout"):
			hud.update_hud_layout()

func spawn_bodyguard_instance():
	if multiplayer.is_server():
		var main_node = get_parent()
		if main_node and "spawner" in main_node:
			bodyguard_instance_count += 1
			var offset = Vector2(40, 40) if active_bodyguards.size() > 0 else Vector2(-40, 0)
			var bodyguard_data = {
				"type": "bodyguard",
				"name": "Bodyguard_" + str(name) + "_" + str(bodyguard_instance_count),
				"position": global_position + offset,
				"owner_id": name.to_int()
			}
			var bg = main_node.spawner.spawn(bodyguard_data)
			if bg:
				active_bodyguards.append(bg)

# --- ATTACK RPC SYSTEM ---

@rpc("any_peer", "call_local", "reliable")
func perform_attack(target_pos: Vector2):
	can_attack = false
	if visual_sprite and visual_sprite.has_method("trigger_attack_fx"):
		visual_sprite.trigger_attack_fx()
	
	if current_class == PlayerClass.RANGED:
		if multiplayer.is_server():
			var main_node = get_parent()
			if main_node and "bullet_count" in main_node:
				main_node.bullet_count += 1
				var bullet_data = {
					"type": "bullet",
					"name": "Bullet_" + str(main_node.bullet_count),
					"position": global_position,
					"direction": (target_pos - global_position).normalized(),
					"damage": bullet_damage
				}
				if "spawner" in main_node:
					main_node.spawner.spawn(bullet_data)
	else:
		execute_melee_attack(target_pos)

	var timer = get_tree().create_timer(attack_cooldown)
	timer.timeout.connect(func():
		if is_instance_valid(self):
			can_attack = true
	)

func execute_melee_attack(target_pos: Vector2):
	var attack_dir = (target_pos - global_position).normalized()
	is_attacking_anim = true
	attack_progress = 0.0
	attack_angle = attack_dir.angle()
	already_hit_enemies.clear()
	queue_redraw()
