@tool
extends Node2D

@export var floor_size: Vector2 = Vector2(3000, 3000):
	set(value):
		floor_size = value
		queue_redraw()

# --- DESERT TERRAIN PALETTE (Warm, clean, soft contrast) ---
@export var sand_base_color: Color = Color(0.75, 0.58, 0.38)       # Desert Dune Ochre
@export var sand_shadow_color: Color = Color(0.65, 0.48, 0.30, 0.4) # Soft Dune Troughs
@export var sand_crest_color: Color = Color(0.83, 0.67, 0.46, 0.5)  # Windblown Dune Crests
@export var sand_pebble_color: Color = Color(0.45, 0.32, 0.20, 0.5) # Weathered desert stones

# --- INDUSTRIAL FORGEWORLD FOUNDATION PALETTE (Cool dark iron, brass, glowing conduits) ---
@export var ferro_plate_base: Color = Color(0.14, 0.16, 0.20)     # Heavy Ferrocrete Base
@export var ferro_plate_inner: Color = Color(0.19, 0.22, 0.27)    # Plasteel Surface
@export var plate_bevel_light: Color = Color(0.36, 0.42, 0.48)    # Steel Bevel Highlight
@export var plate_bevel_dark: Color = Color(0.08, 0.09, 0.11)     # Recessed Seam Shadow
@export var conduit_trench_color: Color = Color(0.09, 0.10, 0.12) # Cable Conduit Trench
@export var conduit_metal_color: Color = Color(0.28, 0.32, 0.38)  # Metal Shielding Pipe
@export var conduit_glow_color: Color = Color(0.15, 0.88, 1.0, 0.85) # Glowing Cyan Tech Cable
@export var conduit_aura_color: Color = Color(0.10, 0.65, 0.85, 0.22) # Energy Field Aura
@export var hazard_yellow: Color = Color(0.86, 0.70, 0.14)        # Caution Stencil Yellow
@export var rivet_color: Color = Color(0.55, 0.60, 0.68)          # Steel Corner Bolts
@export var brass_trim_color: Color = Color(0.75, 0.58, 0.22)     # Mechanicus Brass
@export var max_conduit_length: float = 360.0
@export var foundation_merge_distance: float = 190.0
@export var territory_padding: float = 46.0

var _registered_structures: Array = []

func _ready() -> void:
	add_to_group("sandy_floor")
	if not Engine.is_editor_hint():
		get_tree().node_added.connect(_on_node_added)
		get_tree().node_removed.connect(_on_node_removed)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _on_node_added(node: Node) -> void:
	if node.is_in_group("buildings") or node.is_in_group("base") or node.name.begins_with("Building") or node.name.begins_with("Base"):
		call_deferred("refresh_foundations")

func _on_node_removed(node: Node) -> void:
	if node.is_in_group("buildings") or node.is_in_group("base") or node.name.begins_with("Building") or node.name.begins_with("Base"):
		call_deferred("refresh_foundations")

func refresh_foundations() -> void:
	queue_redraw()

## Query whether a world-space position is inside the industrialized Mechanicus foundation territory
func is_position_on_industrial_ground(global_pos: Vector2) -> bool:
	var bases = get_tree().get_nodes_in_group("base")
	for b in bases:
		if is_instance_valid(b):
			if global_pos.distance_to(b.global_position) <= 125.0:
				return true

	var buildings = get_tree().get_nodes_in_group("buildings")
	for b in buildings:
		if is_instance_valid(b):
			if "is_preview" in b and b.is_preview:
				continue
			var radius = 55.0
			if "building_type" in b:
				match int(b.building_type):
					1: radius = 68.0 # Generator
					3: radius = 75.0 # Manufactorum
					_: radius = 55.0
			if global_pos.distance_to(b.global_position) <= radius:
				return true
	return false

func _draw() -> void:
	var half_size = floor_size / 2.0
	var full_rect = Rect2(-half_size, floor_size)

	# =========================================================================
	# 1. DESERT PLANET WASTELAND BASE LAYER (Warm, Organic Dunes)
	# =========================================================================
	draw_rect(full_rect, sand_base_color)

	var rng = RandomNumberGenerator.new()
	rng.seed = 44219

	# Soft sweeping desert dune ridges
	var dune_count = 14
	for d in range(dune_count):
		var center_y = -half_size.y + (d * (floor_size.y / float(dune_count))) + rng.randf_range(-40.0, 40.0)
		var points_trough = PackedVector2Array()
		var points_crest = PackedVector2Array()
		
		var step_x = 120.0
		var x = -half_size.x
		while x <= half_size.x + step_x:
			var wave = sin((x * 0.0025) + float(d) * 1.7) * 45.0 + cos((x * 0.001) + float(d)) * 20.0
			var pt = Vector2(x, center_y + wave)
			points_trough.append(pt)
			points_crest.append(pt - Vector2(10.0, 6.0))
			x += step_x

		if points_trough.size() > 1:
			# Soft dune shadow edge
			draw_polyline(points_trough, sand_shadow_color, 12.0)
			# Sunlit dune crest highlight
			draw_polyline(points_crest, sand_crest_color, 4.0)

	# Sparse desert rock pebbles (minimal noise for maximum unit readability)
	var pebble_count = int((floor_size.x * floor_size.y) / 45000.0)
	for i in range(pebble_count):
		var p_pos = Vector2(
			rng.randf_range(-half_size.x + 80.0, half_size.x - 80.0),
			rng.randf_range(-half_size.y + 80.0, half_size.y - 80.0)
		)
		var p_radius = rng.randf_range(2.0, 5.0)
		# Small drop shadow & rock pebble
		draw_circle(p_pos + Vector2(1.5, 2.0), p_radius, Color(0.20, 0.14, 0.08, 0.35))
		draw_circle(p_pos, p_radius, sand_pebble_color)

	# =========================================================================
	# 2. DYNAMIC INDUSTRIALIZED MECHANICUS TERRITORY
	# =========================================================================
	var active_structures: Array[Dictionary] = []

	# Gather Base Core
	var base_nodes = get_tree().get_nodes_in_group("base") if not Engine.is_editor_hint() else []
	for b in base_nodes:
		if is_instance_valid(b):
			active_structures.append({
				"node": b,
				"local_pos": to_local(b.global_position),
				"is_base": true,
				"radius": 115.0,
				"type": -1
			})

	# If in editor hint, add a mock base at center so the editor preview looks great
	if Engine.is_editor_hint() and active_structures.is_empty():
		active_structures.append({
			"node": null,
			"local_pos": Vector2.ZERO,
			"is_base": true,
			"radius": 115.0,
			"type": -1
		})

	# Gather Placed Buildings
	var building_nodes = get_tree().get_nodes_in_group("buildings") if not Engine.is_editor_hint() else []
	for b in building_nodes:
		if is_instance_valid(b):
			if "is_preview" in b and b.is_preview:
				continue
			var b_type = int(b.get("building_type")) if "building_type" in b else 0
			var b_radius = 44.0
			match b_type:
				0: b_radius = 34.0 # Barricade
				1: b_radius = 52.0 # Generator
				2: b_radius = 45.0 # Turret
				3: b_radius = 58.0 # Manufactorum

			active_structures.append({
				"node": b,
				"local_pos": to_local(b.global_position),
				"is_base": false,
				"radius": b_radius,
				"type": b_type
			})

	# Lay down a soft, connected industrial territory before the hard pads.
	# Overlapping influence discs and joins form a continuous forge-world floor
	# without requiring expensive polygon boolean operations.
	_draw_industrial_territory(active_structures)

	# --- 2A. DRAW A ROOTED POWER & DATA NETWORK ---
	# Each structure receives one low-resistance link to the existing network.
	# This is a Prim-style tree rather than a complete graph, so a dense base
	# remains readable and naturally grows into tidy branches.
	var network_links = _build_conduit_network(active_structures)
	for link in network_links:
		var source = active_structures[link.from]
		var target = active_structures[link.to]
		if source.local_pos.distance_to(target.local_pos) <= foundation_merge_distance:
			_draw_foundation_bridge(source, target)
		_draw_conduit_cable(source.local_pos, target.local_pos, source.radius, target.radius)

	# --- 2B. DRAW INDUSTRIAL FOUNDATION PADS ---
	for s in active_structures:
		if s.is_base:
			_draw_base_command_plaza(s.local_pos, s.radius)
		else:
			_draw_building_foundation_pad(s.local_pos, s.radius, s.type)

# -----------------------------------------------------------------------------
# DRAWING HELPERS: POWER CONDUITS
# -----------------------------------------------------------------------------
func _build_conduit_network(structures: Array[Dictionary]) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	var powered: Array[int] = []
	var unpowered: Array[int] = []

	for i in range(structures.size()):
		if structures[i].is_base:
			powered.append(i)
		else:
			unpowered.append(i)

	while not unpowered.is_empty() and not powered.is_empty():
		var best_parent := -1
		var best_child := -1
		var best_distance := INF
		for parent_idx in powered:
			for child_idx in unpowered:
				var distance = structures[parent_idx].local_pos.distance_to(structures[child_idx].local_pos)
				if distance <= max_conduit_length and distance < best_distance:
					best_distance = distance
					best_parent = parent_idx
					best_child = child_idx

		if best_child == -1:
			break # Structures beyond reach stay visually disconnected.
		links.append({"from": best_parent, "to": best_child})
		powered.append(best_child)
		unpowered.erase(best_child)

	return links

func _draw_industrial_territory(structures: Array[Dictionary]) -> void:
	var territory_color = Color(ferro_plate_base, 0.88)
	var territory_edge = Color(plate_bevel_dark, 0.34)

	# Each structure expands the ground plane beyond its individual hard pad.
	for structure in structures:
		var influence_radius: float = structure.radius + territory_padding
		draw_circle(structure.local_pos, influence_radius, territory_color)

	# Only terrain joins use proximity pairs. They create one unified silhouette,
	# while the conduit network above remains the clean, non-cluttered tree.
	for i in range(structures.size()):
		for j in range(i + 1, structures.size()):
			var first = structures[i]
			var second = structures[j]
			var first_radius: float = first.radius + territory_padding
			var second_radius: float = second.radius + territory_padding
			if first.local_pos.distance_to(second.local_pos) <= first_radius + second_radius:
				_draw_territory_join(first.local_pos, second.local_pos, first_radius, second_radius, territory_color, territory_edge)

func _draw_territory_join(p1: Vector2, p2: Vector2, radius_1: float, radius_2: float, fill_color: Color, edge_color: Color) -> void:
	var delta = p2 - p1
	if delta.length_squared() < 0.01:
		return
	var direction = delta.normalized()
	var perpendicular = direction.orthogonal()
	var bridge = PackedVector2Array([
		p1 + perpendicular * radius_1,
		p2 + perpendicular * radius_2,
		p2 - perpendicular * radius_2,
		p1 - perpendicular * radius_1
	])
	draw_colored_polygon(bridge, fill_color)
	# A very faint seam preserves the industrial material without breaking up the mass.
	draw_line(p1 + perpendicular * radius_1, p2 + perpendicular * radius_2, edge_color, 1.0)
	draw_line(p1 - perpendicular * radius_1, p2 - perpendicular * radius_2, edge_color, 1.0)

func _draw_conduit_cable(p1: Vector2, p2: Vector2, radius_1: float, radius_2: float) -> void:
	var direction = p2 - p1
	if direction.length_squared() < 0.01:
		return
	direction = direction.normalized()
	# Stop at the edge of each foundation, letting the pads visually absorb the link.
	var start = p1 + direction * (radius_1 * 0.62)
	var finish = p2 - direction * (radius_2 * 0.62)
	var subtle_aura = Color(conduit_aura_color, conduit_aura_color.a * 0.45)
	var subtle_glow = Color(conduit_glow_color, conduit_glow_color.a * 0.58)
	draw_line(start, finish, conduit_trench_color, 6.0)
	draw_line(start, finish, subtle_aura, 8.0)
	draw_line(start, finish, conduit_metal_color, 3.0)
	draw_line(start, finish, subtle_glow, 1.0)

func _draw_foundation_bridge(s1: Dictionary, s2: Dictionary) -> void:
	var p1: Vector2 = s1.local_pos
	var p2: Vector2 = s2.local_pos
	var delta = p2 - p1
	if delta.length_squared() < 0.01:
		return
	var direction = delta.normalized()
	var perpendicular = direction.orthogonal()
	var half_width = min(s1.radius, s2.radius) * 0.48
	var start = p1 + direction * (s1.radius * 0.45)
	var finish = p2 - direction * (s2.radius * 0.45)
	var bridge = PackedVector2Array([
		start + perpendicular * half_width,
		finish + perpendicular * half_width,
		finish - perpendicular * half_width,
		start - perpendicular * half_width
	])
	draw_colored_polygon(bridge, ferro_plate_base)
	draw_polyline(PackedVector2Array([bridge[0], bridge[1], bridge[2], bridge[3], bridge[0]]), plate_bevel_dark, 1.5)

# -----------------------------------------------------------------------------
# DRAWING HELPERS: BASE CORE COMMAND PLAZA
# -----------------------------------------------------------------------------
func _draw_base_command_plaza(pos: Vector2, radius: float) -> void:
	# Outer Ground Contact Shadow
	draw_circle(pos + Vector2(4, 6), radius + 6.0, Color(0.04, 0.05, 0.07, 0.45))

	# 1. Fortified Octagonal Foundation Pad
	var oct_pts = _get_polygon_points(pos, radius, 8, PI / 8.0)
	draw_colored_polygon(oct_pts, ferro_plate_base)
	draw_polyline(oct_pts + PackedVector2Array([oct_pts[0]]), plate_bevel_light, 3.5)

	# 2. Inner Plasteel Deck
	var inner_oct = _get_polygon_points(pos, radius * 0.82, 8, PI / 8.0)
	draw_colored_polygon(inner_oct, ferro_plate_inner)
	draw_polyline(inner_oct + PackedVector2Array([inner_oct[0]]), plate_bevel_dark, 2.0)

	# 3. Mechanicus Brass Cog Motif Rim
	var cog_radius = radius * 0.72
	draw_arc(pos, cog_radius, 0, TAU, 24, brass_trim_color, 2.0)
	var cog_teeth = 12
	for i in range(cog_teeth):
		var angle = (float(i) / float(cog_teeth)) * TAU
		var t_pos = pos + Vector2(cos(angle), sin(angle)) * cog_radius
		draw_rect(Rect2(t_pos - Vector2(3, 3), Vector2(6, 6)), brass_trim_color)

	# 4. Four Primary Energy Conduit Channels
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var line_start = pos + (dir * 20.0)
		var line_end = pos + (dir * (radius - 8.0))
		draw_line(line_start, line_end, conduit_trench_color, 5.0)
		draw_line(line_start, line_end, conduit_glow_color, 1.8)

	# 5. Corner Hazard Warning Chevrons
	for corner_dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var c_center = pos + corner_dir.normalized() * (radius * 0.65)
		draw_circle(c_center, 6.0, hazard_yellow)
		draw_circle(c_center, 4.0, Color(0.12, 0.12, 0.14))

# -----------------------------------------------------------------------------
# DRAWING HELPERS: BUILDING FOUNDATION PADS
# -----------------------------------------------------------------------------
func _draw_building_foundation_pad(pos: Vector2, radius: float, b_type: int) -> void:
	# Outer Contact Shadow
	draw_circle(pos + Vector2(3, 4), radius + 4.0, Color(0.04, 0.05, 0.07, 0.40))

	match b_type:
		1: # GENERATOR: Hexagonal Plasteel Platform with Pulse Ring
			var pts = _get_polygon_points(pos, radius, 6, 0.0)
			draw_colored_polygon(pts, ferro_plate_base)
			draw_polyline(pts + PackedVector2Array([pts[0]]), plate_bevel_light, 2.5)

			var inner = _get_polygon_points(pos, radius * 0.78, 6, 0.0)
			draw_colored_polygon(inner, ferro_plate_inner)
			draw_arc(pos, radius * 0.55, 0, TAU, 16, conduit_glow_color, 1.5)

		2: # TURRET: Reinforced Circular Gun Emplacement
			draw_circle(pos, radius, ferro_plate_base)
			draw_arc(pos, radius, 0, TAU, 20, plate_bevel_light, 2.5)
			draw_circle(pos, radius * 0.80, ferro_plate_inner)
			draw_arc(pos, radius * 0.80, 0, TAU, 20, brass_trim_color, 1.5)

			# 4 Symmetrical Mount Bolts
			for angle_deg in [45, 135, 225, 315]:
				var rad = deg_to_rad(angle_deg)
				var b_pt = pos + Vector2(cos(rad), sin(rad)) * (radius * 0.65)
				draw_circle(b_pt, 2.0, rivet_color)

		0: # BARRICADE: Compact round hardpoint, easy to chain into a perimeter
			draw_circle(pos, radius, ferro_plate_base)
			draw_arc(pos, radius, 0, TAU, 20, plate_bevel_light, 2.0)
			draw_circle(pos, radius * 0.74, ferro_plate_inner)
			draw_arc(pos, radius * 0.74, 0, TAU, 20, brass_trim_color, 1.2)
			for angle_deg in [45, 135, 225, 315]:
				var bolt_pos = pos + Vector2.RIGHT.rotated(deg_to_rad(angle_deg)) * (radius * 0.58)
				draw_circle(bolt_pos, 1.7, rivet_color)

		_: # MANUFACTORUM & OTHERS: Sturdy beveled square pad
			var pad_rect = Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
			draw_rect(pad_rect, ferro_plate_base)
			draw_rect(pad_rect, plate_bevel_light, false, 2.0)

			var inner_rect = Rect2(pos - Vector2(radius * 0.8, radius * 0.8), Vector2(radius * 1.6, radius * 1.6))
			draw_rect(inner_rect, ferro_plate_inner)

			# Corner Rivets
			var half_r = radius * 0.75
			for offset in [Vector2(-half_r, -half_r), Vector2(half_r, -half_r), Vector2(-half_r, half_r), Vector2(half_r, half_r)]:
				draw_circle(pos + offset, 2.0, rivet_color)

func _get_polygon_points(center: Vector2, radius: float, sides: int, angle_offset: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(sides):
		var angle = angle_offset + (float(i) / float(sides)) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points
