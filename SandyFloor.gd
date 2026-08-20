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

# --- FORGEWORLD MODULAR SQUARE SLAB PALETTE ---
@export var ferro_plate_base: Color = Color(0.10, 0.12, 0.15, 1.0)
@export var ferro_plate_inner: Color = Color(0.16, 0.18, 0.22, 1.0)
@export var plate_bevel_light: Color = Color(0.40, 0.46, 0.54, 1.0)
@export var plate_bevel_dark: Color = Color(0.05, 0.06, 0.08, 1.0)
@export var brass_trim_color: Color = Color(0.78, 0.58, 0.22, 1.0)

# Living Metal Conduit Seams
@export var conduit_trench_color: Color = Color(0.06, 0.07, 0.09, 0.95)
@export var conduit_metal_color: Color = Color(0.24, 0.28, 0.34, 0.85)
@export var conduit_glow_color: Color = Color(0.15, 0.85, 1.0, 0.85)
@export var max_conduit_length: float = 320.0

# Cached geometry
var cached_slab_polygons: Array[PackedVector2Array] = []
var cached_inner_polygons: Array[PackedVector2Array] = []
var cached_stepped_edge_plates: Array[PackedVector2Array] = []
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
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		conduit_pulse_renderer.material = mat
		add_child(conduit_pulse_renderer)
	else:
		conduit_pulse_renderer = get_node("ConduitPulseRenderer")

func _on_node_added(node: Node) -> void:
	if node is StaticBody2D and (node.is_in_group("buildings") or node.is_in_group("base") or node.name.begins_with("Base") or node.name.begins_with("Building")):
		call_deferred("refresh_foundations")

func _on_node_removed(node: Node) -> void:
	if node is StaticBody2D and (node.is_in_group("buildings") or node.is_in_group("base") or node.name.begins_with("Base") or node.name.begins_with("Building")):
		call_deferred("refresh_foundations")

func refresh_foundations() -> void:
	cached_active_structures = _gather_active_structures()
	cached_conduit_links = _build_conduit_network(cached_active_structures)
	
	if cached_active_structures.is_empty():
		cached_slab_polygons.clear()
		cached_inner_polygons.clear()
		cached_stepped_edge_plates.clear()
		queue_redraw()
		return

	var raw_polygons: Array[PackedVector2Array] = []

	# 1. Generate SQUARE Modular Industrial Plating with Chamfered Corners
	for s in cached_active_structures:
		if s.slab_size.x > 0.0:
			raw_polygons.append(_get_square_plate_polygon(s.local_pos, s.slab_size * 0.5, 12.0))

	# 2. Bridge neighboring square slabs with corridors
	var ground_structs = cached_active_structures.filter(func(st): return st.slab_size.x > 0.0)
	for i in range(ground_structs.size()):
		for j in range(i + 1, ground_structs.size()):
			var s1 = ground_structs[i]
			var s2 = ground_structs[j]
			var dist = s1.local_pos.distance_to(s2.local_pos)
			var max_bridge_dist = (s1.slab_size.x * 0.5) + (s2.slab_size.x * 0.5) + 45.0
			if dist <= max_bridge_dist:
				raw_polygons.append(_get_bridge_polygon(s1.local_pos, s2.local_pos, 28.0, 28.0))

	# 3. Boolean Union: Merge all square slabs into a continuous industrial deck!
	cached_slab_polygons = _fuse_polygons(raw_polygons)

	# 4. Generate Inset Plasteel Plates
	cached_inner_polygons.clear()
	for slab in cached_slab_polygons:
		var insets = Geometry2D.offset_polygon(slab, -7.0, Geometry2D.JOIN_SQUARE)
		for inset in insets:
			cached_inner_polygons.append(inset)

	# 5. Generate Stepped Outer Edge Plates that fade into sand
	cached_stepped_edge_plates.clear()
	for slab in cached_slab_polygons:
		var stepped = Geometry2D.offset_polygon(slab, 8.0, Geometry2D.JOIN_SQUARE)
		for st in stepped:
			cached_stepped_edge_plates.append(st)

	queue_redraw()

func _gather_active_structures() -> Array[Dictionary]:
	var list: Array[Dictionary] = []

	# Huge Starting Industrial Plaza for the Main Base (360x360px square!)
	var base_nodes = get_tree().get_nodes_in_group("base") if not Engine.is_editor_hint() else []
	for b in base_nodes:
		if is_instance_valid(b):
			list.append({
				"node": b,
				"local_pos": to_local(b.global_position),
				"is_base": true,
				"slab_size": Vector2(360, 360), # Massive square starting area!
				"visual_radius": 44.0,
				"type": -1
			})

	var building_nodes = get_tree().get_nodes_in_group("buildings") if not Engine.is_editor_hint() else []
	for b in building_nodes:
		if is_instance_valid(b):
			if "is_preview" in b and b.is_preview: continue
			var b_type = int(b.get("building_type")) if "building_type" in b else 0
			
			var slab_s = Vector2.ZERO
			var visual_r = 18.0
			match b_type:
				0: slab_s = Vector2.ZERO; visual_r = 16.0       # Barricade (Open sand)
				1: slab_s = Vector2(160, 160); visual_r = 24.0   # Generator
				2: slab_s = Vector2.ZERO; visual_r = 20.0       # Turret
				3: slab_s = Vector2(190, 190); visual_r = 34.0   # Manufactorum
				4: slab_s = Vector2(240, 240); visual_r = 16.0   # Distributor (Expands territory by 240px square!)
				5: slab_s = Vector2(260, 260); visual_r = 18.0   # Antenna
				6: slab_s = Vector2(180, 180); visual_r = 28.0   # Research Shrine

			list.append({
				"node": b,
				"local_pos": to_local(b.global_position),
				"is_base": false,
				"slab_size": slab_s,
				"visual_radius": visual_r,
				"type": b_type
			})

	return list

func _fuse_polygons(poly_list: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var merged: Array[PackedVector2Array] = poly_list.duplicate()
	var changed = true
	var max_iterations = 14
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

	# 1. Desert Sand Floor
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

	# 2. Stepped Outer Ferrocrete Rim (Tapers into sand)
	for st in cached_stepped_edge_plates:
		draw_colored_polygon(st, Color(0.08, 0.09, 0.12, 0.60))

	# 3. Main Square Ferrocrete Deck
	for slab in cached_slab_polygons:
		draw_colored_polygon(slab, ferro_plate_base)

	# 4. Inset Plasteel Grid Plates
	for inner in cached_inner_polygons:
		draw_colored_polygon(inner, ferro_plate_inner)
		var closed_inner = inner.duplicate()
		closed_inner.append(inner[0])
		draw_polyline(closed_inner, plate_bevel_dark, 1.5)

	# 5. Crisp Outer Brass & Steel Perimeter Edging
	for slab in cached_slab_polygons:
		var closed_slab = slab.duplicate()
		closed_slab.append(slab[0])
		draw_polyline(closed_slab, plate_bevel_light, 2.5)
		draw_polyline(closed_slab, brass_trim_color, 1.0)

	# 6. Recessed Conduit Seams
	for link in cached_conduit_links:
		var source = cached_active_structures[link.from]
		var target = cached_active_structures[link.to]
		_draw_static_conduit(source.local_pos, target.local_pos, source.visual_radius, target.visual_radius)

	# 7. Base Command Plaza
	for s in cached_active_structures:
		if s.is_base:
			_draw_base_command_plaza(s.local_pos, 100.0)

func _draw_static_conduit(p1: Vector2, p2: Vector2, v_radius_1: float, v_radius_2: float) -> void:
	var direction = p2 - p1
	var total_len = direction.length()
	if total_len < 1.0: return
	var dir_norm = direction.normalized()
	
	var start = p1 + dir_norm * (v_radius_1 - 1.0)
	var finish = p2 - dir_norm * (v_radius_2 - 1.0)
	if start.distance_to(finish) < 4.0: return

	draw_line(start, finish, conduit_trench_color, 3.2)
	draw_line(start, finish, conduit_metal_color, 1.6)
	draw_circle(start, 2.0, conduit_metal_color)
	draw_circle(finish, 2.0, conduit_metal_color)

func _build_conduit_network(structures: Array[Dictionary]) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	if structures.size() < 2: return links

	var max_conns = 3
	var candidates: Array[Dictionary] = []

	for i in range(structures.size()):
		for j in range(i + 1, structures.size()):
			var s1 = structures[i]
			var s2 = structures[j]
			if s1.type == 0 or s2.type == 0: continue
			var dist = s1.local_pos.distance_to(s2.local_pos)
			if dist <= max_conduit_length and dist > 1.0:
				candidates.append({"from": i, "to": j, "dist": dist})

	candidates.sort_custom(func(a, b): return a.dist < b.dist)

	var conn_counts: Dictionary = {}
	for i in range(structures.size()): conn_counts[i] = 0

	for cand in candidates:
		var u = cand.from; var v = cand.to
		if conn_counts[u] >= max_conns or conn_counts[v] >= max_conns: continue

		var p1 = structures[u].local_pos
		var p2 = structures[v].local_pos
		var crosses = false

		for edge in links:
			var e1 = edge.from; var e2 = edge.to
			if u == e1 or u == e2 or v == e1 or v == e2: continue
			var ep1 = structures[e1].local_pos
			var ep2 = structures[e2].local_pos
			if Geometry2D.segment_intersects_segment(p1, p2, ep1, ep2) != null:
				crosses = true; break

		if not crosses:
			links.append({"from": u, "to": v})
			conn_counts[u] += 1
			conn_counts[v] += 1

	return links

func _draw_base_command_plaza(pos: Vector2, radius: float) -> void:
	var cog_radius = radius * 0.72
	draw_arc(pos, cog_radius, 0, TAU, 24, brass_trim_color, 2.0)
	for i in range(12):
		var angle = (float(i) / 12.0) * TAU
		var t_pos = pos + Vector2(cos(angle), sin(angle)) * cog_radius
		draw_rect(Rect2(t_pos - Vector2(3, 3), Vector2(6, 6)), brass_trim_color)

## Generates a square plate with clean chamfered corners
func _get_square_plate_polygon(center: Vector2, half_extents: Vector2, chamfer: float) -> PackedVector2Array:
	var hx = half_extents.x
	var hy = half_extents.y
	var c = minf(chamfer, minf(hx, hy) * 0.3)
	return PackedVector2Array([
		center + Vector2(-hx + c, -hy),
		center + Vector2(hx - c, -hy),
		center + Vector2(hx, -hy + c),
		center + Vector2(hx, hy - c),
		center + Vector2(hx - c, hy),
		center + Vector2(-hx + c, hy),
		center + Vector2(-hx, hy - c),
		center + Vector2(-hx, -hy + c)
	])

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

# --- UNSHADED CONDUIT PULSE RENDERER ---
class ConduitPulseRenderer extends Node2D:
	var anim_timer: float = 0.0

	func _process(delta: float) -> void:
		anim_timer += delta
		queue_redraw()

	func _draw() -> void:
		var parent = get_parent()
		if not parent or not ("cached_conduit_links" in parent): return

		var links: Array[Dictionary] = parent.cached_conduit_links
		var structures: Array[Dictionary] = parent.cached_active_structures
		var glow_color: Color = parent.conduit_glow_color

		var pulse_speed = 85.0
		var pulse_spacing = 50.0
		var pulse_offset = fmod(anim_timer * pulse_speed, pulse_spacing)

		for link in links:
			var s1 = structures[link.from]
			var s2 = structures[link.to]
			var p1 = s1.local_pos
			var p2 = s2.local_pos
			
			var dir_vec = p2 - p1
			var dist = dir_vec.length()
			if dist < 1.0: continue
			var dir_norm = dir_vec.normalized()

			var start = p1 + dir_norm * (s1.visual_radius - 1.0)
			var finish = p2 - dir_norm * (s2.visual_radius - 1.0)
			var seg_len = start.distance_to(finish)
			if seg_len < 4.0: continue

			draw_line(start, finish, Color(glow_color.r, glow_color.g, glow_color.b, 0.40), 1.0)

			var cur_dist = pulse_offset
			while cur_dist < seg_len:
				var pulse_pos = start + dir_norm * cur_dist
				draw_circle(pulse_pos, 2.2, Color(glow_color.r, glow_color.g, glow_color.b, 0.45))
				draw_circle(pulse_pos, 1.2, Color.WHITE)
				cur_dist += pulse_spacing
