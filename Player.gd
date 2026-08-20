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

# --- BUILDING SYSTEM & GRID STATE ---
# Building Types: 
# 0: Barricade (15 Scrap - Open terrain)
# 1: Generator (25 Scrap - Requires Industrial Ground)
# 2: Turret (35 Scrap, 5 Req - Open terrain)
# 3: Manufactorum (60 Scrap, 25 Req - Requires Industrial Ground)
# 4: Distributor (20 Scrap - Spreads Industrial Ground)
# 5: Noosphere Antenna (Upgraded from Distributor via [E])
# 6: Research Shrine (40 Scrap, 15 Req - Requires Industrial Ground)
var selected_building_type: int = 0
const BUILDING_COSTS = [15, 25, 35, 60, 20, 0, 40]
const BUILD_RANGE: float = 260.0
const CONDUIT_RANGE: float = 360.0
const INTERACTION_RANGE: float = 85.0
var building_scene = preload("res://Building.tscn")
var is_building_mode: bool = false
var preview_instance: Node2D = null
var preview_is_valid: bool = false
var preview_connection_target: Node2D = null
var hovered_interact_building: Node2D = null

# ==============================================================================
# MODULAR GRID & WALL BALANCING CONSTANTS
# ==============================================================================
const GRID_SIZE: float = 32.0          # Base cell dimension in pixels
const WALL_LINK_RANGE: float = 95.0    # Connects up to 2 cells cardinally (64px) & 1-2 cells diagonally (~45-90px)
var preview_barricade_links: Array[Node2D] = []

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

# --- BUILDING & GRID PLACEMENT SYSTEM ---

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
		
func update_preview_type():
	if is_instance_valid(preview_instance):
		if "building_type" in preview_instance:
			preview_instance.building_type = selected_building_type
		if preview_instance.has_method("setup_as_preview"):
			preview_instance.setup_as_preview()

# --- GRID FOOTPRINT & DIMENSION HELPERS ---

func _get_building_size(type: int) -> Vector2:
	match type:
		-1: return Vector2(144, 144) # Main Base Core (4.5 tiles with natural clearance)
		0:  return Vector2(32, 32)   # Barricade Post (1x1 tile)
		1:  return Vector2(64, 64)   # Generator (2x2 tiles)
		2:  return Vector2(48, 48)   # Turret (1.5 tiles - provides clearance for rotating barrels)
		3:  return Vector2(96, 96)   # Manufactorum (3x3 tiles)
		4:  return Vector2(48, 48)   # Distributor (1.5 tiles - prevents merging into generators)
		5:  return Vector2(48, 48)   # Noosphere Antenna (1.5 tiles)
		6:  return Vector2(72, 72)   # Research Shrine (2.25 tiles)
		_:  return Vector2(32, 32)

func _get_building_rect(type: int, pos: Vector2) -> Rect2:
	var size = _get_building_size(type)
	return Rect2(pos - (size * 0.5), size)

func _requires_industrial_ground(type: int) -> bool:
	# Generator (1), Manufactorum (3), and Research Shrine (6) MUST be placed on industrial ground!
	return type in [1, 3, 6]

func _is_position_on_industrial_ground(pos: Vector2) -> bool:
	var base_nodes = get_tree().get_nodes_in_group("base")
	for b in base_nodes:
		if is_instance_valid(b) and pos.distance_to(b.global_position) <= 145.0:
			return true

	var buildings = get_tree().get_nodes_in_group("buildings")
	for b in buildings:
		if not is_instance_valid(b) or b == preview_instance:
			continue
		var b_type = int(b.get("building_type")) if "building_type" in b else 0
		var coverage_radius = 0.0
		match b_type:
			1: coverage_radius = 70.0   # Generator
			3: coverage_radius = 80.0   # Manufactorum
			4: coverage_radius = 125.0  # Distributor (Territory Expansion)
			5: coverage_radius = 135.0  # Noosphere Antenna
			6: coverage_radius = 80.0   # Research Shrine
			_: continue

		if pos.distance_to(b.global_position) <= coverage_radius:
			return true

	return false

func _get_snapped_build_position(mouse_pos: Vector2) -> Vector2:
	var size = _get_building_size(selected_building_type)
	var cells_x = int(round(size.x / GRID_SIZE))
	var cells_y = int(round(size.y / GRID_SIZE))
	
	var snapped_x: float
	var snapped_y: float
	
	# Odd cell footprints center on cell midpoints (+16px); even footprints center on grid line intersections (+0px)
	if cells_x % 2 == 1:
		snapped_x = floor(mouse_pos.x / GRID_SIZE) * GRID_SIZE + (GRID_SIZE * 0.5)
	else:
		snapped_x = round(mouse_pos.x / GRID_SIZE) * GRID_SIZE
		
	if cells_y % 2 == 1:
		snapped_y = floor(mouse_pos.y / GRID_SIZE) * GRID_SIZE + (GRID_SIZE * 0.5)
	else:
		snapped_y = round(mouse_pos.y / GRID_SIZE) * GRID_SIZE
		
	return Vector2(snapped_x, snapped_y)

func _is_build_location_valid(build_pos: Vector2) -> bool:
	# 1. Industrial Ground Requirement Check
	if _requires_industrial_ground(selected_building_type) and not _is_position_on_industrial_ground(build_pos):
		return false

	var is_placing_barricade = (selected_building_type == 0)
	
	# Barricades touch with tight tolerance; Heavy buildings get a 6px breathing margin
	var placement_margin = -1.0 if is_placing_barricade else 6.0
	var my_rect = Rect2(build_pos - (_get_building_size(selected_building_type) * 0.5), _get_building_size(selected_building_type)).grow(placement_margin)

	var structures = get_tree().get_nodes_in_group("buildings")
	structures.append_array(get_tree().get_nodes_in_group("base"))

	for s in structures:
		if not is_instance_valid(s) or s == preview_instance:
			continue
		if "is_preview" in s and s.is_preview:
			continue

		var s_type = -1 if s.is_in_group("base") else int(s.get("building_type"))
		var other_is_barricade = (s_type == 0)

		# Allow Barricade-to-Barricade touching for continuous curtain walls
		var other_margin = -1.0 if (is_placing_barricade and other_is_barricade) else 6.0
		var other_rect = Rect2(s.global_position - (_get_building_size(s_type) * 0.5), _get_building_size(s_type)).grow(other_margin)

		# Block placement if the footprints crowd or overlap
		if my_rect.intersects(other_rect):
			return false

	return true

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
	
func _find_preview_barricade_links(build_pos: Vector2) -> Array[Node2D]:
	var linked_neighbors: Array[Node2D] = []
	if selected_building_type != 0: # Only for Barricades
		return linked_neighbors

	var buildings = get_tree().get_nodes_in_group("buildings")
	for b in buildings:
		if not is_instance_valid(b) or b == preview_instance:
			continue
		if "building_type" in b and int(b.building_type) == 0:
			if "is_preview" in b and b.is_preview:
				continue
			var dist = b.global_position.distance_to(build_pos)
			if dist <= WALL_LINK_RANGE and dist > 1.0:
				if not _is_wall_line_blocked_by_structure(build_pos, b.global_position):
					linked_neighbors.append(b)
	return linked_neighbors

func _is_wall_line_blocked_by_structure(pos_a: Vector2, pos_b: Vector2) -> bool:
	var structures = get_tree().get_nodes_in_group("buildings")
	structures.append_array(get_tree().get_nodes_in_group("base"))
	
	for s in structures:
		if not is_instance_valid(s) or s == preview_instance:
			continue
		if "building_type" in s and int(s.building_type) == 0:
			continue # Ignore other barricades
			
		var s_type = -1 if s.is_in_group("base") else int(s.get("building_type"))
		var s_pos = s.global_position
		var s_radius = _get_building_size(s_type).x * 0.45

		var seg = pos_b - pos_a
		var l2 = seg.length_squared()
		if l2 > 0.0:
			var t = clampf((s_pos - pos_a).dot(seg) / l2, 0.0, 1.0)
			var proj = pos_a + t * seg
			if proj.distance_to(s_pos) < s_radius:
				return true
	return false

# --- [E] INTERACTION: UPGRADE TURRET / DISTRIBUTOR / TECH SHRINE ---

func request_interact_nearby_structure() -> void:
	var r_ui = get_tree().get_first_node_in_group("research_ui")
	if r_ui and r_ui.visible:
		r_ui.close_terminal()
		return

	var closest: Node2D = _get_closest_interactable_structure()
	if is_instance_valid(closest):
		var b_type = int(closest.building_type)
		if b_type == 2: # Turret Upgrade
			var main_node = get_tree().get_first_node_in_group("main")
			if main_node: main_node.rpc_id(1, "request_upgrade_turret", closest.name)
		elif b_type == 4: # Distributor -> Antenna Upgrade
			var main_node = get_tree().get_first_node_in_group("main")
			if main_node: main_node.rpc_id(1, "request_upgrade_distributor", closest.name)
		elif b_type == 6: # Research Shrine -> Open Tech-Vault Terminal!
			if r_ui and r_ui.has_method("open_terminal"):
				r_ui.open_terminal(closest)
	
func _get_closest_interactable_structure() -> Node2D:
	var closest: Node2D = null
	var closest_dist := INTERACTION_RANGE
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not ("building_type" in building): continue
		var b_type = int(building.building_type)
		# Only Turrets (2), Distributors (4), and Research Shrines (6) have [E] interactions
		if not (b_type in [2, 4, 6]): continue
		var dist = global_position.distance_to(building.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = building
	return closest

# --- PROCESS & DRAW LOOP ---

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
		hovered_interact_building = _get_closest_interactable_structure()
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
		
		# Find which barricades will connect to this position
		if selected_building_type == 0:
			preview_barricade_links = _find_preview_barricade_links(build_pos)
		else:
			preview_barricade_links.clear()

		preview_instance.modulate = Color(0.45, 1.0, 0.78, 0.66) if preview_is_valid else Color(1.0, 0.28, 0.24, 0.66)
		queue_redraw()

func _draw():
	if is_attacking_anim:
		draw_omnissian_axe_sweep()
		
	# 1. Floating In-World Contextual Interaction Tooltip
	if is_instance_valid(hovered_interact_building):
		var local_b_pos = hovered_interact_building.global_position - global_position
		_draw_inworld_interaction_tooltip(local_b_pos, int(hovered_interact_building.building_type))

	# 2. Build Preview Holograms & Blueprint Footprints
	if is_building_mode and is_instance_valid(preview_instance):
		var local_build_pos = preview_instance.global_position - global_position
		var placement_color = Color(0.35, 1.0, 0.72, 0.9) if preview_is_valid else Color(1.0, 0.25, 0.20, 0.95)
		
		# Build Range Boundary Arc
		draw_arc(Vector2.ZERO, BUILD_RANGE, 0.0, TAU, 48, Color(0.20, 0.75, 0.95, 0.24), 1.5)
		
		# Holographic Barricade Wall Link Previews
		if selected_building_type == 0 and not preview_barricade_links.is_empty():
			var wall_half_width = 8.0
			var pulse = 0.55 + sin(Time.get_ticks_msec() * 0.008) * 0.25
			var holo_fill = Color(0.20, 0.88, 1.0, 0.22 * pulse) if preview_is_valid else Color(1.0, 0.25, 0.20, 0.22 * pulse)
			var holo_edge = Color(0.25, 0.92, 1.0, 0.75 * pulse) if preview_is_valid else Color(1.0, 0.28, 0.22, 0.75 * pulse)
			var holo_truss = Color(0.35, 0.95, 1.0, 0.45 * pulse) if preview_is_valid else Color(1.0, 0.35, 0.25, 0.45 * pulse)

			for neighbor in preview_barricade_links:
				if not is_instance_valid(neighbor): continue
				var local_neighbor_pos = neighbor.global_position - global_position
				var dir = (local_neighbor_pos - local_build_pos).normalized()
				var perp = dir.orthogonal() * wall_half_width
				var span_length = local_build_pos.distance_to(local_neighbor_pos)

				# Hologram Wall Plinth
				var holo_poly = PackedVector2Array([
					local_build_pos - perp,
					local_neighbor_pos - perp,
					local_neighbor_pos + perp,
					local_build_pos + perp
				])
				draw_colored_polygon(holo_poly, holo_fill)

				# Hologram Edge Rails
				draw_line(local_build_pos - perp, local_neighbor_pos - perp, holo_edge, 1.5)
				draw_line(local_build_pos + perp, local_neighbor_pos + perp, holo_edge, 1.5)

				# Animated Cross-Bracing Trusses
				var num_struts = int(span_length / 16.0)
				for i in range(num_struts):
					var t1 = float(i) / float(num_struts)
					var t2 = float(i + 1) / float(num_struts)
					var p1 = (local_build_pos - perp).lerp(local_neighbor_pos - perp, t1)
					var p2 = (local_build_pos + perp).lerp(local_neighbor_pos + perp, t2)
					draw_line(p1, p2, holo_truss, 1.0)

				draw_arc(local_neighbor_pos, 18.0, 0.0, TAU, 16, holo_edge, 1.5)

		# Square Tactical Blueprint Footprint
		var b_size = _get_building_size(selected_building_type)
		var b_rect = Rect2(local_build_pos - (b_size * 0.5), b_size)
		
		# Blueprint cell fill & border
		draw_rect(b_rect, Color(placement_color.r, placement_color.g, placement_color.b, 0.15), true)
		draw_rect(b_rect, placement_color, false, 1.5)
		
		# Tactical corner brackets
		var b_len = 6.0
		# Top-Left
		draw_line(b_rect.position, b_rect.position + Vector2(b_len, 0), placement_color, 2.5)
		draw_line(b_rect.position, b_rect.position + Vector2(0, b_len), placement_color, 2.5)
		# Top-Right
		var tr = b_rect.position + Vector2(b_size.x, 0)
		draw_line(tr, tr - Vector2(b_len, 0), placement_color, 2.5)
		draw_line(tr, tr + Vector2(0, b_len), placement_color, 2.5)
		# Bottom-Left
		var bl = b_rect.position + Vector2(0, b_size.y)
		draw_line(bl, bl + Vector2(b_len, 0), placement_color, 2.5)
		draw_line(bl, bl - Vector2(0, b_len), placement_color, 2.5)
		# Bottom-Right
		var br = b_rect.position + b_size
		draw_line(br, br - Vector2(b_len, 0), placement_color, 2.5)
		draw_line(br, br - Vector2(0, b_len), placement_color, 2.5)
		
		# Standard Conduit Target Line (for non-barricades)
		if selected_building_type != 0 and is_instance_valid(preview_connection_target):
			var local_target = preview_connection_target.global_position - global_position
			draw_line(local_target, local_build_pos, Color(0.25, 0.85, 1.0, 0.45), 2.0)

func _draw_inworld_interaction_tooltip(local_pos: Vector2, b_type: int):
	var prompt_text = ""
	var cost_text = ""
	var main_node = get_tree().get_first_node_in_group("main")
	var current_req = main_node.requisition_amount if main_node else 0

	match b_type:
		2: # Turret
			var lvl = hovered_interact_building.get("turret_upgrade_level") if "turret_upgrade_level" in hovered_interact_building else 0
			var costs = [10, 20, 35]
			if lvl < costs.size():
				prompt_text = "[E] Upgrade (Lv." + str(lvl + 2) + ")"
				cost_text = "⚡ " + str(costs[lvl])
			else:
				prompt_text = "Turret Maxed"
		4: # Distributor
			prompt_text = "[E] Upgrade Antenna"
			cost_text = "⚡ 15"
		6: # Research Shrine
			prompt_text = "[E] Tech-Vault"
			cost_text = "OPEN"

	if prompt_text.is_empty(): return

	# Floating Holographic Badge Position
	var badge_pos = local_pos + Vector2(0, -44)
	var badge_rect = Rect2(badge_pos - Vector2(80, 13), Vector2(160, 26))
	
	# Box Backdrop & Edge Framing
	draw_rect(badge_rect, Color(0.05, 0.07, 0.10, 0.90), true)
	draw_rect(badge_rect, Color(0.20, 0.88, 1.0, 0.85), false, 1.2)
	draw_line(badge_pos + Vector2(0, 13), local_pos + Vector2(0, -18), Color(0.20, 0.88, 1.0, 0.35), 1.5)

	# Draw Holographic Text Inside Badge
	var font = ThemeDB.fallback_font
	var font_size = 11
	
	# Left Action Label
	draw_string(font, badge_pos + Vector2(-74, 4), prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.90, 0.86, 0.74))
	
	# Right Cost Badge (Live Affordability Coloring)
	if not cost_text.is_empty():
		var cost_color = Color(0.35, 0.90, 1.0)
		if cost_text.begins_with("⚡"):
			var cost_val = cost_text.replace("⚡ ", "").to_int()
			cost_color = Color(0.35, 0.90, 1.0) if current_req >= cost_val else Color(0.90, 0.25, 0.20)
		draw_string(font, badge_pos + Vector2(25, 4), cost_text, HORIZONTAL_ALIGNMENT_RIGHT, 48, font_size, cost_color)

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
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return

	# Query the physics engine in an 85px radius around the player
	var shape = CircleShape2D.new()
	shape.radius = 85.0

	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var results = space_state.intersect_shape(query, 32)
	
	var eased_progress = pow(attack_progress, 2.5) 
	var total_cone = deg_to_rad(120.0)
	var current_axe_angle = attack_angle - (total_cone / 2.0) + (eased_progress * total_cone)
	var axe_dir = Vector2.RIGHT.rotated(current_axe_angle)

	for hit in results:
		var target_body = hit.collider
		if not is_instance_valid(target_body) or target_body in already_hit_enemies:
			continue
		if not (target_body.is_in_group("enemies") or target_body.is_in_group("objectives")):
			continue
			
		var to_target = target_body.global_position - global_position
		var angle_diff = abs(axe_dir.angle_to(to_target))
		
		# 35-degree hit tolerance along the active axe head position
		if angle_diff <= deg_to_rad(35.0):
			already_hit_enemies.append(target_body)
			if target_body.has_method("take_damage"):
				var knockback_dir = to_target.normalized()
				var knockback_strength: float = 250.0
				target_body.take_damage(40, knockback_dir * knockback_strength)

# --- UNHANDLED INPUT (KEYBOARD & MOUSE) ---

func _unhandled_input(event):
	if not is_multiplayer_authority():
		return
		
	# Allow ESC to close Tech Vault terminal if open
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var r_ui = get_tree().get_first_node_in_group("research_ui")
		if r_ui and r_ui.visible:
			r_ui.close_terminal()
			get_viewport().set_input_as_handled()
			return

	# Tech-Priest Building & Support Inputs
	if current_class == PlayerClass.MELEE:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_E:
				request_interact_nearby_structure()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_K:
				rpc("request_spawn_servo_skull")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_B or event.keycode == KEY_TAB:
				toggle_build_mode(selected_building_type)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_1, KEY_KP_1]:
				toggle_build_mode(0) # Barricade
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_2, KEY_KP_2]:
				toggle_build_mode(4) # Distributor (Spreads Ground)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_3, KEY_KP_3]:
				toggle_build_mode(1) # Generator
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_4, KEY_KP_4]:
				toggle_build_mode(2) # Turret
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_5, KEY_KP_5]:
				toggle_build_mode(6) # Research Shrine
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
						print("[Build System] Placement blocked: Space occupied or lacks industrial ground!")
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
