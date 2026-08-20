@tool
extends Node2D

@export var floor_size: Vector2 = Vector2(3000, 3000):
	set(value):
		floor_size = value
		queue_redraw()

# --- DESERT WASTELAND PALETTE ---
@export var sand_base_color: Color = Color(0.76, 0.60, 0.40)
@export var sand_shadow_color: Color = Color(0.66, 0.49, 0.31, 0.45)
@export var sand_crest_color: Color = Color(0.85, 0.70, 0.48, 0.55)
@export var sand_pebble_color: Color = Color(0.44, 0.31, 0.19, 0.55)

# --- FORGEWORLD ART SLAB PALETTE ---
@export var ferro_plate_base: Color = Color(0.11, 0.13, 0.16, 1.0)
@export var ferro_plate_inner: Color = Color(0.17, 0.19, 0.23, 1.0)
@export var plate_bevel_light: Color = Color(0.42, 0.48, 0.55, 1.0)
@export var plate_bevel_dark: Color = Color(0.06, 0.07, 0.09, 1.0)
@export var brass_trim_color: Color = Color(0.78, 0.58, 0.22, 1.0)
@export var conduit_trench_color: Color = Color(0.08, 0.09, 0.11, 1.0)
@export var conduit_metal_color: Color = Color(0.28, 0.32, 0.38, 1.0)
@export var conduit_glow_color: Color = Color(0.15, 0.90, 1.0, 0.9)
@export var max_conduit_length: float = 380.0
@export var territory_padding: float = 38.0

# Cached geometry
var cached_slab_polygons: Array[PackedVector2Array] = []
var cached_inner_polygons: Array[PackedVector2Array] = []
var cached_active_structures: Array[Dictionary] = []
var cached_conduit_links: Array[Dictionary] = []

var conduit_pulse_renderer: Node2D = null

func _ready() -> void:
	z_index = -10
	add_to_group("sandy_floor")
	
	_setup_pulse_renderer()
	
	if not Engine.is_editor_hint():
		get_tree().node_added.connect(_on_node_added)
		get_tree().node_removed.connect(_on_node_removed)
	refresh_foundations()

func _setup_pulse_renderer() -> void:
	if not has_node("ConduitPulseRenderer"):
		conduit_pulse_renderer = ConduitPulseRenderer.new()
		conduit_pulse_renderer.name = "ConduitPulseRenderer"
		conduit_pulse_renderer.z_index = 1
		add_child(conduit_pulse_renderer)
	else:
		conduit_pulse_renderer = get_node("ConduitPulseRenderer")

func _on_node_added(node: Node) -> void:
	# Only refresh when a relevant StaticBody2D structure changes
	if node is StaticBody2D and (node.is_in_group("buildings") or node.is_in_group("base")):
		call_deferred("refresh_foundations")

func _on_node_removed(node: Node) -> void:
	if node is StaticBody2D and (node.is_in_group("buildings") or node.is_in_group("base")):
		call_deferred("refresh_foundations")

func refresh_foundations() -> void:
	cached_active_structures = _gather_active_structures()
	cached_conduit_links = _build_conduit_network(cached_active_structures)
	
	if cached_active_structures.is_empty():
		cached_slab_polygons.clear()
		cached_inner_polygons.clear()
		queue_redraw()
		return

	var raw_polygons: Array[PackedVector2Array] = []

	for s in cached_active_structures:
		var r: float = s.radius + territory_padding
		raw_polygons.append(_get_polygon_points(s.local_pos, r, 20, 0.0))

	for i in range(cached_active_structures.size()):
		for j in range(i + 1, cached_active_structures.size()):
			var s1 = cached_active_structures[i]
			var s2 = cached_active_structures[j]
			var r1: float = s1.radius + territory_padding
			var r2: float = s2.radius + territory_padding
			if s1.local_pos.distance_to(s2.local_pos) <= (r1 + r2) * 1.05:
				raw_polygons.append(_get_bridge_polygon(s1.local_pos, s2.local_pos, r1 * 0.85, r2 * 0.85))

	cached_slab_polygons = _fuse_polygons(raw_polygons)

	cached_inner_polygons.clear()
	for slab in cached_slab_polygons:
		var insets = Geometry2D.offset_polygon(slab, -6.0, Geometry2D.JOIN_ROUND)
		for inset in insets:
			cached_inner_polygons.append(inset)

	queue_redraw()

func _gather_active_structures() -> Array[Dictionary]:
	var list: Array[Dictionary] = []

	var base_nodes = get_tree().get_nodes_in_group("base") if not Engine.is_editor_hint() else []
	for b in base_nodes:
		if is_instance_valid(b):
			list.append({
				"node": b,
				"local_pos": to_local(b.global_position),
				"is_base": true,
				"radius": 130.0,
				"type": -1
			})

	var building_nodes = get_tree().get_nodes_in_group("buildings") if not Engine.is_editor_hint() else []
	for b in building_nodes:
		if is_instance_valid(b):
			if "is_preview" in b and b.is_preview: continue
			var b_type = int(b.get("building_type")) if "building_type" in b else 0
			
			# ONLY Heavy & Logistics buildings spread Industrial Ground
			# (Barricades [0] and Turrets [2] DO NOT generate ground)
			var b_radius = 0.0
			match b_type:
				1: b_radius = 58.0   # Generator
				3: b_radius = 65.0   # Manufactorum
				4: b_radius = 110.0  # Distributor (Expands Territory!)
				5: b_radius = 120.0  # Noosphere Antenna
				6: b_radius = 65.0   # Research Shrine
				_: continue

			list.append({
				"node": b,
				"local_pos": to_local(b.global_position),
				"is_base": false,
				"radius": b_radius,
				"type": b_type
			})

	return list

func _fuse_polygons(poly_list: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var merged: Array[PackedVector2Array] = poly_list.duplicate()
	var changed = true
	var max_iterations = 12
	var iter = 0

	while changed and iter < max_iterations:
		iter += 1
		changed = false
		var next_pass: Array[PackedVector2Array] = []
		
		while not merged.is_empty():
			var current = merged.pop_back()
			var did_merge = false
			
			for idx in range(merged.size() - 1, -1, -1):
				var candidate = merged[idx]
				var union = Geometry2D.merge_polygons(current, candidate)
				if union.size() == 1:
					merged[idx] = union[0]
					did_merge = true
					changed = true
					break
			
			if not did_merge:
				next_pass.append(current)
				
		merged = next_pass

	return merged

func _draw() -> void:
	var half_size = floor_size / 2.0
	var full_rect = Rect2(-half_size, floor_size)

	# 1. Static Sand Floor & Dunes
	draw_rect(full_rect, sand_base_color)

	var rng = RandomNumberGenerator.new()
	rng.seed = 44219

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
			draw_polyline(points_trough, sand_shadow_color, 12.0)
			draw_polyline(points_crest, sand_crest_color, 4.0)

	var pebble_count = int((floor_size.x * floor_size.y) / 45000.0)
	for i in range(pebble_count):
		var p_pos = Vector2(
			rng.randf_range(-half_size.x + 80.0, half_size.x - 80.0),
			rng.randf_range(-half_size.y + 80.0, half_size.y - 80.0)
		)
		var p_radius = rng.randf_range(2.0, 5.0)
		draw_circle(p_pos + Vector2(1.5, 2.0), p_radius, Color(0.20, 0.14, 0.08, 0.35))
		draw_circle(p_pos, p_radius, sand_pebble_color)

		# 2. Static Industrial Slabs (Drop shadow loop removed!)
	for slab in cached_slab_polygons:
		draw_colored_polygon(slab, ferro_plate_base)

	for inner in cached_inner_polygons:
		draw_colored_polygon(inner, ferro_plate_inner)
		var closed_inner = inner.duplicate()
		closed_inner.append(inner[0])
		draw_polyline(closed_inner, plate_bevel_dark, 1.5)

	for slab in cached_slab_polygons:
		var closed_slab = slab.duplicate()
		closed_slab.append(slab[0])
		draw_polyline(closed_slab, plate_bevel_light, 2.5)
		draw_polyline(closed_slab, brass_trim_color, 1.0)

	# 3. Static Conduit Trench Cables
	for link in cached_conduit_links:
		var source = cached_active_structures[link.from]
		var target = cached_active_structures[link.to]
		_draw_static_conduit(source.local_pos, target.local_pos, source.radius, target.radius)

	# 4. Base Command Plaza
	for s in cached_active_structures:
		if s.is_base:
			_draw_base_command_plaza(s.local_pos, s.radius)

func _draw_static_conduit(p1: Vector2, p2: Vector2, radius_1: float, radius_2: float) -> void:
	var direction = p2 - p1
	var total_len = direction.length()
	if total_len < 1.0: return
	var dir_norm = direction.normalized()
	
	var start = p1 + dir_norm * (radius_1 * 0.6)
	var finish = p2 - dir_norm * (radius_2 * 0.6)
	if start.distance_to(finish) < 2.0: return

	draw_line(start, finish, conduit_trench_color, 7.0)
	draw_line(start, finish, conduit_metal_color, 3.5)
	draw_line(start, finish, Color(conduit_glow_color.r, conduit_glow_color.g, conduit_glow_color.b, 0.3), 1.5)

func _build_conduit_network(structures: Array[Dictionary]) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	var powered: Array[int] = []
	var unpowered: Array[int] = []

	for i in range(structures.size()):
		if structures[i].is_base: powered.append(i)
		else: unpowered.append(i)

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

		if best_child == -1: break
		links.append({"from": best_parent, "to": best_child})
		powered.append(best_child)
		unpowered.erase(best_child)

	return links

func _draw_base_command_plaza(pos: Vector2, radius: float) -> void:
	var cog_radius = radius * 0.72
	draw_arc(pos, cog_radius, 0, TAU, 24, brass_trim_color, 2.0)
	for i in range(12):
		var angle = (float(i) / 12.0) * TAU
		var t_pos = pos + Vector2(cos(angle), sin(angle)) * cog_radius
		draw_rect(Rect2(t_pos - Vector2(3, 3), Vector2(6, 6)), brass_trim_color)

	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(pos + (dir * 20.0), pos + (dir * (radius - 8.0)), conduit_trench_color, 5.0)
		draw_line(pos + (dir * 20.0), pos + (dir * (radius - 8.0)), conduit_glow_color, 2.0)

func _get_bridge_polygon(p1: Vector2, p2: Vector2, radius_1: float, radius_2: float) -> PackedVector2Array:
	var delta = p2 - p1
	if delta.length_squared() < 0.01: return PackedVector2Array()
	var direction = delta.normalized()
	var perpendicular = direction.orthogonal()
	return PackedVector2Array([
		p1 + perpendicular * radius_1,
		p2 + perpendicular * radius_2,
		p2 - perpendicular * radius_2,
		p1 - perpendicular * radius_1
	])

func _get_polygon_points(center: Vector2, radius: float, sides: int, angle_offset: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(sides):
		var angle = angle_offset + (float(i) / float(sides)) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points

# --- NESTED CLASS: LIGHTWEIGHT CONDUIT PULSE ANIMATOR ---
class ConduitPulseRenderer extends Node2D:
	var anim_timer: float = 0.0

	func _process(delta: float) -> void:
		anim_timer += delta
		queue_redraw()

	func _draw() -> void:
		var parent = get_parent()
		if not parent or not ("cached_conduit_links" in parent):
			return

		var links: Array[Dictionary] = parent.cached_conduit_links
		var structures: Array[Dictionary] = parent.cached_active_structures
		var glow_color: Color = parent.conduit_glow_color

		var pulse_speed = 90.0
		var pulse_spacing = 60.0
		var pulse_offset = fmod(anim_timer * pulse_speed, pulse_spacing)

		for link in links:
			var s1 = structures[link.from]
			var s2 = structures[link.to]
			var p1: Vector2 = s1.local_pos
			var p2: Vector2 = s2.local_pos
			
			var dir_vec = p2 - p1
			var dist = dir_vec.length()
			if dist < 1.0: continue
			var dir_norm = dir_vec.normalized()

			var start = p1 + dir_norm * (s1.radius * 0.6)
			var finish = p2 - dir_norm * (s2.radius * 0.6)
			var seg_len = start.distance_to(finish)
			if seg_len < 2.0: continue

			var cur_dist = pulse_offset
			while cur_dist < seg_len:
				var pulse_pos = start + dir_norm * cur_dist
				draw_circle(pulse_pos, 2.5, glow_color)
				draw_circle(pulse_pos, 1.2, Color.WHITE)
				cur_dist += pulse_spacing
