@tool
extends Node2D

const GRID_SIZE: float = 32.0

@export var floor_size: Vector2 = Vector2(3000, 3000):
	set(value):
		floor_size = value
		queue_redraw()

# --- DESERT WASTELAND PALETTE ---
@export var sand_base_color: Color = Color(0.76, 0.58, 0.38)
@export var sand_shadow_color: Color = Color(0.64, 0.46, 0.28, 0.45)
@export var sand_crest_color: Color = Color(0.86, 0.70, 0.46, 0.55)
@export var sand_pebble_color: Color = Color(0.40, 0.28, 0.16, 0.50)

# --- FORGEWORLD MODULAR GRID PALETTE ---
@export var plate_base_color: Color = Color(0.12, 0.13, 0.16, 1.0)
@export var plate_inset_color: Color = Color(0.16, 0.18, 0.22, 1.0)
@export var tile_seam_color: Color = Color(0.07, 0.08, 0.10, 0.90)
@export var rivet_color: Color = Color(0.45, 0.48, 0.55, 0.85)

# Perimeter Stepped Girder Border
@export var girder_dark_edge: Color = Color(0.05, 0.06, 0.08, 1.0)
@export var girder_light_edge: Color = Color(0.48, 0.54, 0.62, 1.0)
@export var brass_rim_color: Color = Color(0.78, 0.58, 0.22, 1.0)

# Cable Channels & Conduit Pulse
@export var cable_dark: Color = Color(0.08, 0.08, 0.10, 0.95)
@export var cable_rubber: Color = Color(0.20, 0.22, 0.26, 0.90)
@export var conduit_glow_color: Color = Color(0.20, 0.88, 1.0, 0.85)

# Cached Grid State
var cached_active_cells: Dictionary = {} # Vector2i -> true
var cached_perimeter_edges: Array[Dictionary] = [] # [{ "p1": Vector2, "p2": Vector2 }]
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
	_rasterize_radial_grid_cells()
	_calculate_perimeter_borders()
	queue_redraw()

func _gather_active_structures() -> Array[Dictionary]:
	var list: Array[Dictionary] = []

	# Main Base gives 6-tile radius circle of squares (~192px)
	var base_nodes = get_tree().get_nodes_in_group("base") if not Engine.is_editor_hint() else []
	for b in base_nodes:
		if is_instance_valid(b):
			list.append({
				"node": b,
				"local_pos": to_local(b.global_position),
				"is_base": true,
				"radius": 256.0, # Expanded from 192px -> 256px for a spacious starting courtyard!
				"visual_radius": 44.0,
				"type": -1
			})

	var building_nodes = get_tree().get_nodes_in_group("buildings") if not Engine.is_editor_hint() else []
	for b in building_nodes:
		if is_instance_valid(b):
			if "is_preview" in b and b.is_preview: continue
			var b_type = int(b.get("building_type")) if "building_type" in b else 0
			
			var rad = 0.0
			var visual_r = 18.0
			match b_type:
				0: rad = 0.0;    visual_r = 16.0    # Barricade (Open sand)
				1: rad = 96.0;   visual_r = 24.0    # Generator (3 tiles)
				2: rad = 0.0;    visual_r = 20.0    # Turret
				3: rad = 128.0;  visual_r = 34.0    # Manufactorum (4 tiles)
				4: rad = 160.0; visual_r = 9.0   # Distributor (9px visual radius)
				5: rad = 192.0; visual_r = 10.0  # Noosphere Antenna (10px visual radius)
				6: rad = 112.0;  visual_r = 28.0    # Research Shrine (3.5 tiles)

			list.append({
				"node": b,
				"local_pos": to_local(b.global_position),
				"is_base": false,
				"radius": rad,
				"visual_radius": visual_r,
				"type": b_type
			})

	return list

func _rasterize_radial_grid_cells() -> void:
	cached_active_cells.clear()
	
	for s in cached_active_structures:
		if s.radius <= 0.0: continue
		var center: Vector2 = s.local_pos
		var rad: float = s.radius
		var rad_sq: float = rad * rad

		var min_gx = int(floor((center.x - rad) / GRID_SIZE))
		var max_gx = int(ceil((center.x + rad) / GRID_SIZE))
		var min_gy = int(floor((center.y - rad) / GRID_SIZE))
		var max_gy = int(ceil((center.y + rad) / GRID_SIZE))

		for gx in range(min_gx, max_gx + 1):
			for gy in range(min_gy, max_gy + 1):
				var cell_center = Vector2((gx + 0.5) * GRID_SIZE, (gy + 0.5) * GRID_SIZE)
				if cell_center.distance_squared_to(center) <= rad_sq:
					cached_active_cells[Vector2i(gx, gy)] = true

func _calculate_perimeter_borders() -> void:
	cached_perimeter_edges.clear()

	for cell in cached_active_cells.keys():
		var gx = cell.x
		var gy = cell.y
		var top_left = Vector2(gx * GRID_SIZE, gy * GRID_SIZE)
		var top_right = Vector2((gx + 1) * GRID_SIZE, gy * GRID_SIZE)
		var bottom_left = Vector2(gx * GRID_SIZE, (gy + 1) * GRID_SIZE)
		var bottom_right = Vector2((gx + 1) * GRID_SIZE, (gy + 1) * GRID_SIZE)

		# Top edge
		if not cached_active_cells.has(Vector2i(gx, gy - 1)):
			cached_perimeter_edges.append({"p1": top_left, "p2": top_right})
		# Bottom edge
		if not cached_active_cells.has(Vector2i(gx, gy + 1)):
			cached_perimeter_edges.append({"p1": bottom_left, "p2": bottom_right})
		# Left edge
		if not cached_active_cells.has(Vector2i(gx - 1, gy)):
			cached_perimeter_edges.append({"p1": top_left, "p2": bottom_left})
		# Right edge
		if not cached_active_cells.has(Vector2i(gx + 1, gy)):
			cached_perimeter_edges.append({"p1": top_right, "p2": bottom_right})

func is_world_pos_on_grid(world_pos: Vector2) -> bool:
	var local_p = to_local(world_pos)
	var gx = int(floor(local_p.x / GRID_SIZE))
	var gy = int(floor(local_p.y / GRID_SIZE))
	return cached_active_cells.has(Vector2i(gx, gy))

func _draw() -> void:
	var half_size = floor_size / 2.0
	var full_rect = Rect2(-half_size, floor_size)

	# 1. Desert Sand Floor & Dunes
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
		var p_radius = rng.randf_range(2.0, 4.5)
		draw_circle(p_pos + Vector2(1.0, 1.5), p_radius, Color(0.20, 0.14, 0.08, 0.30))
		draw_circle(p_pos, p_radius, sand_pebble_color)

	# 2. Draw Clean Modular Industrial Ferrocrete Plates (No clutter dots)
	for cell in cached_active_cells.keys():
		var cell_origin = Vector2(cell.x * GRID_SIZE, cell.y * GRID_SIZE)
		var full_cell_rect = Rect2(cell_origin, Vector2(GRID_SIZE, GRID_SIZE))
		var inset_rect = Rect2(cell_origin + Vector2(1.0, 1.0), Vector2(GRID_SIZE - 2.0, GRID_SIZE - 2.0))

		draw_rect(full_cell_rect, plate_base_color)
		draw_rect(inset_rect, plate_inset_color)
		# Subtle, non-distracting grid line
		draw_rect(full_cell_rect, tile_seam_color, false, 0.8)

	# 3. Perimeter Girder Border
	for edge in cached_perimeter_edges:
		draw_line(edge.p1, edge.p2, girder_dark_edge, 3.0)
		draw_line(edge.p1, edge.p2, brass_rim_color, 1.0)

	# 4. Recessed Floor Conduits (Subtle, non-distracting)
	for link in cached_conduit_links:
		var source = cached_active_structures[link.from]
		var target = cached_active_structures[link.to]
		_draw_static_conduit(source.local_pos, target.local_pos, source.visual_radius, target.visual_radius)

	# 5. Base Command Plaza Cog
	for s in cached_active_structures:
		if s.is_base:
			_draw_base_command_plaza(s.local_pos, 85.0)

func _draw_static_conduit(p1: Vector2, p2: Vector2, v_radius_1: float, v_radius_2: float) -> void:
	var direction = p2 - p1
	var total_len = direction.length()
	if total_len < 1.0: return
	var dir_norm = direction.normalized()
	
	var start = p1 + dir_norm * (v_radius_1 - 1.0)
	var finish = p2 - dir_norm * (v_radius_2 - 1.0)
	if start.distance_to(finish) < 4.0: return

	draw_line(start, finish, cable_dark, 4.5)
	draw_line(start, finish, cable_rubber, 2.5)
	draw_circle(start, 2.5, brass_rim_color)
	draw_circle(finish, 2.5, brass_rim_color)

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
			if dist <= 380.0 and dist > 1.0:
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
	var cog_radius = radius * 0.8
	draw_arc(pos, cog_radius, 0, TAU, 28, brass_rim_color, 2.5)
	for i in range(12):
		var angle = (float(i) / 12.0) * TAU
		var t_pos = pos + Vector2(cos(angle), sin(angle)) * cog_radius
		draw_rect(Rect2(t_pos - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), brass_rim_color)

# --- UNSHADED PULSING POWER CONDUIT RENDERER ---
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

		var pulse_speed = 80.0
		var pulse_spacing = 45.0
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
				draw_circle(pulse_pos, 2.0, Color(glow_color.r, glow_color.g, glow_color.b, 0.5))
				draw_circle(pulse_pos, 1.0, Color.WHITE)
				cur_dist += pulse_spacing
