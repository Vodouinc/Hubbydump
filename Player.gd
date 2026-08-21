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

var tooltip_overlay: Node2D = null

# --- SERVO-SKULL CONFIGURATION ---
var active_servo_skulls: Array = []

# --- MELEE ATTACK ANIMATION & HITBOX STATE ---
var is_attacking_anim: bool = false
var attack_progress: float = 0.0
var attack_angle: float = 0.0
var attack_anim_duration: float = 0.2
var already_hit_enemies: Array = []

# --- BUILDING SYSTEM & GRID STATE ---
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
const BARRICADE_WALL_LENGTH: float = 75.0
const BARRICADE_SNAP_DETECTION_RANGE: float = 110.0

const GRID_SIZE: float = 32.0
const WALL_LINK_RANGE: float = 95.0
var preview_barricade_links: Array[Node2D] = []

# --- BODYGUARD SYSTEM STATE ---
var bodyguard_scene = preload("res://SkitariiBodyguard.tscn")
var bodyguard_level: int = 0
var bodyguard_instance_count: int = 0
var active_bodyguards: Array = []

var active_doctrina: Doctrina = Doctrina.CONQUEROR
var orbital_strike_cooldown: float = 0.0

# --- SKITARII MARSHAL UPGRADE SYSTEM ---
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
	apply_class_stats()
	
	set_process_unhandled_input(_is_local_authority())
	
	if _is_local_authority():
		_setup_tooltip_overlay()
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

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO):
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		var final_damage = float(amount)
		
		# Skitarii Stance Multipliers
		if current_class == PlayerClass.RANGED:
			if active_doctrina == Doctrina.PROTECTOR:
				final_damage *= 0.65
			elif active_doctrina == Doctrina.CONQUEROR:
				final_damage *= 1.20

		# Trench Cover Defense (-35% damage reduction near Barricades)
		var main_node = get_parent()
		if main_node and main_node.get("tech_spikes_cover_unlocked"):
			if _is_near_friendly_barricade(45.0):
				final_damage *= 0.65 # -35% cover reduction!
				
		var new_hp = max(0, current_health - int(final_damage))
		rpc("sync_player_health", new_hp)
		rpc("trigger_player_hit_feedback", int(final_damage))

func _is_near_friendly_barricade(range_limit: float) -> bool:
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and int(b.get("building_type")) == 0:
			if global_position.distance_to(b.global_position) <= range_limit:
				return true
	return false

@rpc("any_peer", "call_local", "unreliable")
func trigger_player_hit_feedback(amount: int):
	AudioManager.play_sfx("hit", global_position, -2.0)
	
	if visual_sprite:
		visual_sprite.modulate = Color(2.5, 0.4, 0.4)
		var tween = create_tween()
		tween.tween_property(visual_sprite, "modulate", Color.WHITE, 0.15)

	var dmg_label = Label.new()
	dmg_label.script = load("res://DamageNumber.gd")
	dmg_label.global_position = global_position + Vector2(randf_range(-8, 8), -30)
	get_tree().current_scene.add_child(dmg_label)
	dmg_label.setup(amount, false)

@rpc("any_peer", "call_local", "reliable")
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

func _get_building_size(type: int) -> Vector2:
	if type == -1:
		return Vector2(144, 144) # Main base
	var info = GameData.STRUCTURE_INFO.get(type, null)
	return info["size"] if info else Vector2(32, 32)

func _requires_industrial_ground(type: int) -> bool:
	var info = GameData.STRUCTURE_INFO.get(type, null)
	return info["requires_industrial"] if info else false

func _is_position_on_industrial_ground(pos: Vector2) -> bool:
	var floor_node = get_tree().get_first_node_in_group("sandy_floor")
	if floor_node and floor_node.has_method("is_world_pos_on_grid"):
		return floor_node.is_world_pos_on_grid(pos)

	# Fallback distance check if floor is not ready
	var base_nodes = get_tree().get_nodes_in_group("base")
	for b in base_nodes:
		if is_instance_valid(b) and pos.distance_to(b.global_position) <= 192.0:
			return true
	return false

func _get_snapped_build_position(mouse_pos: Vector2) -> Vector2:
	if selected_building_type == 0:
		var buildings = get_tree().get_nodes_in_group("buildings")
		var closest_barricade: Node2D = null
		var closest_d = BARRICADE_SNAP_DETECTION_RANGE

		for b in buildings:
			if not is_instance_valid(b) or b == preview_instance: continue
			if "building_type" in b and int(b.building_type) == 0:
				if "is_preview" in b and b.is_preview: continue
				var d = mouse_pos.distance_to(b.global_position)
				if d < closest_d and d > 20.0:
					closest_d = d
					closest_barricade = b

		if is_instance_valid(closest_barricade):
			var to_mouse = mouse_pos - closest_barricade.global_position
			var angle = snapped(to_mouse.angle(), PI / 4.0)
			return (closest_barricade.global_position + Vector2.RIGHT.rotated(angle) * BARRICADE_WALL_LENGTH).snapped(Vector2(2, 2))

	var size = _get_building_size(selected_building_type)
	var cells_x = int(round(size.x / GRID_SIZE))
	var cells_y = int(round(size.y / GRID_SIZE))
	var snapped_x = floor(mouse_pos.x / GRID_SIZE) * GRID_SIZE + (GRID_SIZE * 0.5) if cells_x % 2 == 1 else round(mouse_pos.x / GRID_SIZE) * GRID_SIZE
	var snapped_y = floor(mouse_pos.y / GRID_SIZE) * GRID_SIZE + (GRID_SIZE * 0.5) if cells_y % 2 == 1 else round(mouse_pos.y / GRID_SIZE) * GRID_SIZE
	return Vector2(snapped_x, snapped_y)

func _is_build_location_valid(build_pos: Vector2) -> bool:
	if _requires_industrial_ground(selected_building_type) and not _is_position_on_industrial_ground(build_pos):
		return false

	var is_placing_barricade = (selected_building_type == 0)
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
		var other_margin = -1.0 if (is_placing_barricade and other_is_barricade) else 6.0
		var other_rect = Rect2(s.global_position - (_get_building_size(s_type) * 0.5), _get_building_size(s_type)).grow(other_margin)

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
	if selected_building_type != 0:
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
			continue
			
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

func request_interact_nearby_structure() -> void:
	var r_ui = get_tree().get_first_node_in_group("research_ui")
	if r_ui and r_ui.visible:
		r_ui.close_terminal()
		return

	var t_ui = get_tree().get_first_node_in_group("turret_upgrade_ui")
	if t_ui and t_ui.visible:
		t_ui.close_modal()
		return

	var closest: Node2D = _get_closest_interactable_structure()
	if is_instance_valid(closest):
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node:
			var b_type = int(closest.building_type)
			if b_type == 0:
				main_node.rpc_id(1, "request_upgrade_gate", closest.name)
			elif b_type == 2:
				var lvl = closest.get("turret_upgrade_level") if "turret_upgrade_level" in closest else 0
				var spec = closest.get("turret_spec") if "turret_spec" in closest else 0
				
				if lvl < 3:
					# Upgrade to next numerical tier (Lv. 2 -> Lv. 4)
					main_node.rpc_id(1, "request_upgrade_turret", closest.name)
				elif spec == GameData.TurretSpec.NONE:
					# Turret is Level 4! Open Specialization Modal (Option A)
					if t_ui and t_ui.has_method("open_modal"):
						t_ui.open_modal(closest)
			elif b_type == 4:
				main_node.rpc_id(1, "request_upgrade_distributor", closest.name)
			elif b_type == 6:
				if r_ui and r_ui.has_method("open_terminal"):
					r_ui.open_terminal(closest)
	
func _get_closest_interactable_structure() -> Node2D:
	var closest: Node2D = null
	var closest_dist := INTERACTION_RANGE
	
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not ("building_type" in building): 
			continue
		var b_type = int(building.building_type)
		# Barricade (0 - if not gate), Turret (2), Distributor (4), Research Shrine (6)
		if b_type == 0 and building.get("is_gate"): 
			continue
		if not (b_type in [0, 2, 4, 6]): 
			continue
			
		var dist = global_position.distance_to(building.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = building
			
	return closest

func _process(delta):
	if orbital_strike_cooldown > 0.0:
		orbital_strike_cooldown = maxf(0.0, orbital_strike_cooldown - delta)

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
		var prev_hovered = hovered_interact_building
		hovered_interact_building = _get_closest_interactable_structure()
		
		if is_instance_valid(tooltip_overlay):
			if hovered_interact_building != prev_hovered or is_instance_valid(hovered_interact_building):
				tooltip_overlay.queue_redraw()

		var mouse_pos = get_global_mouse_position()
		if visual_sprite:
			visual_sprite.look_at(mouse_pos)

	if _is_local_authority() and is_building_mode and is_instance_valid(preview_instance):
		var build_pos = _get_snapped_build_position(get_global_mouse_position())
		preview_instance.global_position = build_pos
		preview_is_valid = global_position.distance_to(build_pos) <= BUILD_RANGE and _is_build_location_valid(build_pos)
		preview_connection_target = _find_preview_connection(build_pos)
		
		if selected_building_type == 0:
			preview_barricade_links = _find_preview_barricade_links(build_pos)
		else:
			preview_barricade_links.clear()

		preview_instance.modulate = Color(0.45, 1.0, 0.78, 0.66) if preview_is_valid else Color(1.0, 0.28, 0.24, 0.66)
		queue_redraw()

func _draw():
	if current_class == PlayerClass.RANGED and _is_local_authority():
		_draw_marshal_command_aura()
	if is_attacking_anim:
		draw_omnissian_axe_sweep()
		
	# Blueprint placement holograms
	if is_building_mode and is_instance_valid(preview_instance):
		var local_build_pos = preview_instance.global_position - global_position
		var placement_color = Color(0.35, 1.0, 0.72, 0.9) if preview_is_valid else Color(1.0, 0.25, 0.20, 0.95)
		
		draw_arc(Vector2.ZERO, BUILD_RANGE, 0.0, TAU, 48, Color(0.20, 0.75, 0.95, 0.24), 1.5)
		
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

				var holo_poly = PackedVector2Array([
					local_build_pos - perp,
					local_neighbor_pos - perp,
					local_neighbor_pos + perp,
					local_build_pos + perp
				])
				draw_colored_polygon(holo_poly, holo_fill)
				draw_line(local_build_pos - perp, local_neighbor_pos - perp, holo_edge, 1.5)
				draw_line(local_build_pos + perp, local_neighbor_pos + perp, holo_edge, 1.5)

				var num_struts = int(span_length / 16.0)
				for i in range(num_struts):
					var t1 = float(i) / float(num_struts)
					var t2 = float(i + 1) / float(num_struts)
					var p1 = (local_build_pos - perp).lerp(local_neighbor_pos - perp, t1)
					var p2 = (local_build_pos + perp).lerp(local_neighbor_pos + perp, t2)
					draw_line(p1, p2, holo_truss, 1.0)

				draw_arc(local_neighbor_pos, 18.0, 0.0, TAU, 16, holo_edge, 1.5)

		var b_size = _get_building_size(selected_building_type)
		var b_rect = Rect2(local_build_pos - (b_size * 0.5), b_size)
		
		draw_rect(b_rect, Color(placement_color.r, placement_color.g, placement_color.b, 0.15), true)
		draw_rect(b_rect, placement_color, false, 1.5)
		
		var b_len = 6.0
		draw_line(b_rect.position, b_rect.position + Vector2(b_len, 0), placement_color, 2.5)
		draw_line(b_rect.position, b_rect.position + Vector2(0, b_len), placement_color, 2.5)
		var tr = b_rect.position + Vector2(b_size.x, 0)
		draw_line(tr, tr - Vector2(b_len, 0), placement_color, 2.5)
		draw_line(tr, tr + Vector2(0, b_len), placement_color, 2.5)
		var bl = b_rect.position + Vector2(0, b_size.y)
		draw_line(bl, bl + Vector2(b_len, 0), placement_color, 2.5)
		draw_line(bl, bl - Vector2(0, b_len), placement_color, 2.5)
		var br = b_rect.position + b_size
		draw_line(br, br - Vector2(b_len, 0), placement_color, 2.5)
		draw_line(br, br - Vector2(0, b_len), placement_color, 2.5)
		
		if selected_building_type != 0 and is_instance_valid(preview_connection_target):
			var local_target = preview_connection_target.global_position - global_position
			draw_line(local_target, local_build_pos, Color(0.25, 0.85, 1.0, 0.45), 2.0)

func _draw_marshal_command_aura():
	var aura_radius = 230.0
	var is_conq = (active_doctrina == Doctrina.CONQUEROR)
	var pulse = 0.55 + sin(Time.get_ticks_msec() * 0.005) * 0.2
	
	var aura_color = Color(1.0, 0.75, 0.15, 0.35 * pulse) if is_conq else Color(0.20, 0.88, 1.0, 0.35 * pulse)
	var edge_color = Color(1.0, 0.80, 0.20, 0.75 * pulse) if is_conq else Color(0.30, 0.92, 1.0, 0.75 * pulse)

	draw_arc(Vector2.ZERO, aura_radius, 0.0, TAU, 36, aura_color, 1.5)
	draw_arc(Vector2.ZERO, aura_radius + 4.0, 0.0, TAU, 36, Color(edge_color.r, edge_color.g, edge_color.b, 0.2 * pulse), 1.0)

	var rot_time = Time.get_ticks_msec() * 0.0008
	var num_glyphs = 6
	for i in range(num_glyphs):
		var a = rot_time + (float(i) * TAU / float(num_glyphs))
		var pt = Vector2(cos(a), sin(a)) * aura_radius
		if is_conq:
			var forward_tip = pt + Vector2(cos(a), sin(a)) * 8.0
			var side1 = pt + Vector2(cos(a + 2.2), sin(a + 2.2)) * 6.0
			var side2 = pt + Vector2(cos(a - 2.2), sin(a - 2.2)) * 6.0
			draw_line(side1, forward_tip, edge_color, 1.8)
			draw_line(side2, forward_tip, edge_color, 1.8)
		else:
			draw_circle(pt, 3.0, edge_color)
			draw_circle(pt, 1.5, Color.WHITE)

func _setup_tooltip_overlay() -> void:
	if not has_node("TooltipOverlay"):
		tooltip_overlay = TooltipOverlayRenderer.new()
		tooltip_overlay.name = "TooltipOverlay"
		tooltip_overlay.z_index = 150
		tooltip_overlay.z_as_relative = false
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		tooltip_overlay.material = mat
		add_child(tooltip_overlay)
	else:
		tooltip_overlay = get_node("TooltipOverlay")

func render_interaction_tooltip(canvas: CanvasItem, local_pos: Vector2, b_type: int):
	var main_node = get_tree().get_first_node_in_group("main")
	var cur_scrap = main_node.scrap_amount if main_node else 0
	var cur_req = main_node.requisition_amount if main_node else 0

	var action_text = ""
	var cost_parts: Array[Dictionary] = []
	var is_maxed = false

	match b_type:
		0: # Gate
			if not hovered_interact_building.get("is_gate"):
				action_text = "Upgrade Gate"
				cost_parts.append({"text": "⚙ %d" % GameData.GATE_UPGRADE_SCRAP, "can_afford": cur_scrap >= GameData.GATE_UPGRADE_SCRAP})
				cost_parts.append({"text": "⚡ %d" % GameData.GATE_UPGRADE_REQ, "can_afford": cur_req >= GameData.GATE_UPGRADE_REQ})
		2: # Turret
			var lvl = hovered_interact_building.get("turret_upgrade_level") if "turret_upgrade_level" in hovered_interact_building else 0
			var spec = hovered_interact_building.get("turret_spec") if "turret_spec" in hovered_interact_building else 0
			
			if lvl < 3:
				var req_cost = GameData.TURRET_UPGRADE_COSTS[lvl]
				action_text = "Upgrade (Lv.%d)" % (lvl + 2)
				cost_parts.append({"text": "⚡ %d" % req_cost, "can_afford": cur_req >= req_cost})
			elif spec == GameData.TurretSpec.NONE:
				action_text = "Sanctify Protocol"
				cost_parts.append({"text": "⚡ 35", "can_afford": cur_req >= 35})
			else:
				var spec_info = GameData.TURRET_SPEC_INFO.get(spec, null)
				action_text = spec_info.name if spec_info else "Sanctified"
				is_maxed = true
		4: # Antenna
			action_text = "Upgrade Antenna"
			cost_parts.append({"text": "⚡ %d" % GameData.ANTENNA_UPGRADE_REQ, "can_afford": cur_req >= GameData.ANTENNA_UPGRADE_REQ})
		6: # Tech Vault
			action_text = "Tech Vault"
			cost_parts.append({"text": "OPEN", "can_afford": true})

	if action_text.is_empty():
		return

	var font = ThemeDB.fallback_font
	var font_size = 11
	var key_badge_text = "[E]"
	var key_w = font.get_string_size(key_badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 10.0
	var action_w = font.get_string_size(action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

	var cost_w = 0.0
	if is_maxed:
		cost_w = font.get_string_size("◆ MAX ◆", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	else:
		for cp in cost_parts:
			cost_w += font.get_string_size(cp.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0

	var total_content_w = key_w + action_w + cost_w + 24.0
	var badge_w = maxf(170.0, total_content_w)
	var badge_h = 24.0

	var badge_pos = local_pos + Vector2(0, -38.0)
	var badge_rect = Rect2(badge_pos - Vector2(badge_w * 0.5, badge_h * 0.5), Vector2(badge_w, badge_h))

	# 1. Background Panel & Border
	var border_color = Color(0.20, 0.88, 1.0, 0.90) if not is_maxed else Color(0.50, 0.55, 0.60, 0.70)
	canvas.draw_rect(badge_rect, Color(0.04, 0.05, 0.08, 0.96), true)
	canvas.draw_rect(badge_rect, border_color, false, 1.2)

	# 2. Pointer Anchor Line
	var anchor_top = badge_pos + Vector2(0, badge_h * 0.5)
	var anchor_bottom = local_pos + Vector2(0, -14.0)
	canvas.draw_line(anchor_top, anchor_bottom, Color(border_color.r, border_color.g, border_color.b, 0.40), 1.2)
	canvas.draw_circle(anchor_bottom, 2.0, border_color)

	# 3. [E] Keycap Badge
	var draw_cursor_x = badge_rect.position.x + 8.0
	var text_y = badge_pos.y + 4.0

	if not is_maxed:
		var key_rect = Rect2(Vector2(draw_cursor_x, badge_pos.y - 8.0), Vector2(key_w - 4.0, 16.0))
		canvas.draw_rect(key_rect, Color(0.12, 0.16, 0.22, 0.95), true)
		canvas.draw_rect(key_rect, Color(0.78, 0.58, 0.22), false, 1.0)
		canvas.draw_string(font, Vector2(draw_cursor_x + 3.0, text_y), key_badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.20, 0.88, 1.0))
		draw_cursor_x += key_w + 4.0
	else:
		draw_cursor_x += 4.0

	# 4. Action Title
	var title_color = Color(0.92, 0.90, 0.82) if not is_maxed else Color(0.55, 0.60, 0.65)
	canvas.draw_string(font, Vector2(draw_cursor_x, text_y), action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, title_color)

	# 5. Resource Costs
	var right_edge_x = badge_rect.position.x + badge_w - 8.0
	if is_maxed:
		canvas.draw_string(font, Vector2(right_edge_x - cost_w, text_y), "◆ MAX ◆", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.55, 0.60, 0.65))
	else:
		var current_cost_x = right_edge_x
		for i in range(cost_parts.size() - 1, -1, -1):
			var cp = cost_parts[i]
			var str_w = font.get_string_size(cp.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			current_cost_x -= str_w
			
			var c_color = Color(0.35, 0.95, 1.0) if cp.can_afford else Color(0.95, 0.25, 0.25)
			if cp.text == "OPEN":
				c_color = Color(0.40, 0.95, 0.50)
				
			canvas.draw_string(font, Vector2(current_cost_x, text_y), cp.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c_color)
			current_cost_x -= 8.0

# --- HIGH-Z OVERLAY RENDERER ---
class TooltipOverlayRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p or not is_instance_valid(p.hovered_interact_building):
			return
		var local_pos = to_local(p.hovered_interact_building.global_position)
		p.render_interaction_tooltip(self, local_pos, int(p.hovered_interact_building.building_type))

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
		
		if angle_diff <= deg_to_rad(35.0):
			already_hit_enemies.append(target_body)
			if target_body.has_method("take_damage"):
				var knockback_dir = to_target.normalized()
				var knockback_strength: float = 250.0
				target_body.take_damage(40, knockback_dir * knockback_strength)

func _unhandled_input(event):
	if not is_multiplayer_authority():
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var r_ui = get_tree().get_first_node_in_group("research_ui")
		if r_ui and r_ui.visible:
			r_ui.close_terminal()
			get_viewport().set_input_as_handled()
			return

		if is_building_mode:
			_cancel_build_mode()
			get_viewport().set_input_as_handled()
			return

		var p_ui = get_tree().get_first_node_in_group("pause_menu")
		if p_ui and p_ui.has_method("toggle_my_pause_menu"):
			p_ui.toggle_my_pause_menu()
			get_viewport().set_input_as_handled()
			return

	if current_class == PlayerClass.RANGED and event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_F:
			rpc_id(1, "request_toggle_doctrina")
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_X:
			rpc_id(1, "request_orbital_strike", get_global_mouse_position())
			get_viewport().set_input_as_handled()
			return

	if current_class == PlayerClass.MELEE:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_E:
				request_interact_nearby_structure()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_K:
				rpc_id(1, "request_spawn_servo_skull")
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_B or event.keycode == KEY_TAB:
				toggle_build_mode(selected_building_type)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_1, KEY_KP_1]:
				toggle_build_mode(0)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_2, KEY_KP_2]:
				toggle_build_mode(4)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_3, KEY_KP_3]:
				toggle_build_mode(1)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_4, KEY_KP_4]:
				toggle_build_mode(2)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode in [KEY_5, KEY_KP_5]:
				toggle_build_mode(6)
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
						AudioManager.play_sfx("building_place", build_pos, 0.0)
						_cancel_build_mode()
				get_viewport().set_input_as_handled()
				return

	if current_class == PlayerClass.RANGED and event is InputEventKey and event.pressed:
		if event.keycode == KEY_N:
			if bodyguard_level < GameData.MAX_BODYGUARDS:
				rpc_id(1, "request_upgrade_bodyguards")
				get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_M:
			if damage_upgrade_level < GameData.MAX_DAMAGE_UPGRADES:
				rpc_id(1, "request_upgrade_damage")
				get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_V:
			if speed_upgrade_level < GameData.MAX_SPEED_UPGRADES:
				rpc_id(1, "request_upgrade_speed")
				get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if can_attack:
			var target_pos = get_global_mouse_position()
			rpc("perform_attack", target_pos)

# --- DOCTRINA & ORBITAL RPCS ---

@rpc("any_peer", "call_local", "reliable")
func request_toggle_doctrina():
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	if sender_id != name.to_int(): return

	active_doctrina = Doctrina.PROTECTOR if active_doctrina == Doctrina.CONQUEROR else Doctrina.CONQUEROR
	
	if active_doctrina == Doctrina.CONQUEROR:
		speed = 390.0
		attack_cooldown = 0.18
	else:
		speed = 280.0
		attack_cooldown = 0.38

	rpc("sync_doctrina", int(active_doctrina), speed, attack_cooldown)

@rpc("call_local", "reliable")
func sync_doctrina(new_doctrina: int, new_speed: float, new_cooldown: float):
	active_doctrina = new_doctrina as Doctrina
	speed = new_speed
	attack_cooldown = new_cooldown
	if is_multiplayer_authority():
		var hud = get_tree().get_first_node_in_group("ability_hud")
		if hud and hud.has_method("refresh_hud_display"):
			hud.refresh_hud_display()

@rpc("any_peer", "call_local", "reliable")
func request_orbital_strike(target_pos: Vector2):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	if sender_id != name.to_int(): return
	
	var main_node = get_parent()
	if not main_node or not main_node.has_method("spend_requisition"): return
	if orbital_strike_cooldown > 0.0: return
	
	if main_node.spend_requisition(GameData.ORBITAL_REQ_COST):
		orbital_strike_cooldown = GameData.ORBITAL_COOLDOWN_MAX
		rpc("sync_orbital_cooldown", GameData.ORBITAL_COOLDOWN_MAX)
		rpc("execute_orbital_strike_fx", target_pos)

		var space_state = get_world_2d().direct_space_state
		var shape = CircleShape2D.new()
		shape.radius = 160.0
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, target_pos)
		query.collide_with_bodies = true
		var results = space_state.intersect_shape(query, 64)

		for hit in results:
			var body = hit.collider
			if is_instance_valid(body) and (body.is_in_group("enemies") or body.is_in_group("objectives")):
				var dir = (body.global_position - target_pos).normalized()
				if body.has_method("take_damage"):
					body.take_damage(220, dir * 450.0)

@rpc("any_peer", "call_local", "unreliable")
func execute_orbital_strike_fx(target_pos: Vector2):
	AudioManager.play_sfx("orbital_strike", target_pos, 4.0)
	var blast_label = Label.new()
	blast_label.global_position = target_pos + Vector2(-90, -20)
	blast_label.text = "◆ ORBITAL LANCE STRIKE ◆"
	blast_label.label_settings = LabelSettings.new()
	blast_label.label_settings.font_color = Color(0.20, 0.90, 1.0)
	blast_label.label_settings.font_size = 16
	get_parent().add_child(blast_label)
	get_tree().create_timer(1.8).timeout.connect(blast_label.queue_free)

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_bodyguards():
	if multiplayer.is_server():
		if bodyguard_level >= GameData.MAX_BODYGUARDS:
			return
			
		var main_node = get_parent()
		if main_node and main_node.has_method("spend_requisition"):
			if not main_node.spend_requisition(GameData.BODYGUARD_REQ_COST):
				return

			bodyguard_level += 1
			rpc("sync_bodyguard_level", bodyguard_level)
			spawn_bodyguard_instance()
				
@rpc("any_peer", "call_local", "reliable")
func request_spawn_servo_skull():
	if current_class != PlayerClass.MELEE or not multiplayer.is_server():
		return

	active_servo_skulls = active_servo_skulls.filter(func(s): return is_instance_valid(s))
	
	if active_servo_skulls.size() >= GameData.MAX_SERVO_SKULLS:
		return

	var main_node = get_parent()
	if not main_node or not ("scrap_amount" in main_node and "requisition_amount" in main_node):
		return

	if main_node.scrap_amount >= GameData.SERVO_SKULL_SCRAP_COST and main_node.requisition_amount >= GameData.SERVO_SKULL_REQ_COST:
		main_node.scrap_amount -= GameData.SERVO_SKULL_SCRAP_COST
		main_node.requisition_amount -= GameData.SERVO_SKULL_REQ_COST
		main_node.rpc("sync_resources", main_node.scrap_amount, main_node.requisition_amount)

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
		if damage_upgrade_level >= GameData.MAX_DAMAGE_UPGRADES:
			return
			
		var main_node = get_parent()
		if main_node and main_node.has_method("spend_requisition"):
			if not main_node.spend_requisition(GameData.DAMAGE_UPGRADE_REQ_COST):
				return

			damage_upgrade_level += 1
			bullet_damage += 10
			rpc("sync_damage_upgrade", damage_upgrade_level, bullet_damage)

@rpc("any_peer", "call_local", "reliable")
func sync_orbital_cooldown(new_cd: float):
	orbital_strike_cooldown = new_cd

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
		if speed_upgrade_level >= GameData.MAX_SPEED_UPGRADES:
			return
			
		var main_node = get_parent()
		if main_node and main_node.has_method("spend_requisition"):
			if not main_node.spend_requisition(GameData.SPEED_UPGRADE_REQ_COST):
				return

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

@rpc("any_peer", "call_local", "reliable")
func perform_attack(target_pos: Vector2):
	can_attack = false
	if visual_sprite and visual_sprite.has_method("trigger_attack_fx"):
		visual_sprite.trigger_attack_fx()
	
	if current_class == PlayerClass.RANGED:
		AudioManager.play_sfx("radium_shot", global_position, -3.0)
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
	AudioManager.play_sfx("axe_swing", global_position, 0.0)
	queue_redraw()
