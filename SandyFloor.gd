@tool
extends Node2D

const GRID_SIZE: float = 32.0

@export var floor_size: Vector2 = Vector2(7500, 7500):
	set(value):
		floor_size = value
		queue_redraw()

# --- GRIMDARK DESERT PALETTE ---
@export var sand_base_color: Color = Color(0.55, 0.42, 0.28)
@export var sand_shadow_color: Color = Color(0.38, 0.26, 0.16, 0.55)
@export var sand_crest_color: Color = Color(0.68, 0.52, 0.36, 0.45)
@export var sand_pebble_color: Color = Color(0.24, 0.16, 0.10, 0.60)

# --- FORGE-DECK MODULAR GRID PALETTE ---
@export var plate_base_color: Color = Color(0.12, 0.14, 0.18, 1.0)
@export var plate_inset_color: Color = Color(0.16, 0.18, 0.23, 1.0)
@export var tile_seam_color: Color = Color(0.06, 0.07, 0.09, 0.95)
@export var plate_highlight: Color = Color(0.26, 0.30, 0.38, 0.90)
@export var plate_shadow: Color = Color(0.04, 0.05, 0.07, 0.90)
@export var brass_rim_color: Color = Color(0.78, 0.58, 0.22, 1.0)

# Floor Conduit Channels
@export var cable_dark: Color = Color(0.06, 0.07, 0.09, 0.95)
@export var cable_rubber: Color = Color(0.18, 0.20, 0.24, 0.85)
@export var conduit_glow_color: Color = Color(0.20, 0.88, 1.0, 0.75)

# Cached Grid State
var cached_active_cells: Dictionary = {}
var cached_perimeter_edges: Array[Dictionary] = []
var cached_active_structures: Array[Dictionary] = []
var cached_conduit_links: Array[Dictionary] = []

var conduit_pulse_renderer: Node2D = null
var _refresh_scheduled: bool = false

func _ready() -> void:
	z_index = -10
	add_to_group("sandy_floor")
	_setup_pulse_renderer()
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

## Debounced single-pass refresh (Runs only once per frame at most)
func refresh_foundations() -> void:
	if _refresh_scheduled: return
	_refresh_scheduled = true
	call_deferred("_execute_refresh_foundations")

func _execute_refresh_foundations() -> void:
	_refresh_scheduled = false
	cached_active_structures = _gather_active_structures()
	cached_conduit_links = _build_conduit_network(cached_active_structures)
	_rasterize_radial_grid_cells()
	_calculate_perimeter_borders()
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
				"radius": 240.0,
				"visual_radius": 36.0,
				"type": -1
			})

	var building_nodes = get_tree().get_nodes_in_group("buildings") if not Engine.is_editor_hint() else []
	for b in building_nodes:
		if is_instance_valid(b):
			if "is_preview" in b and b.is_preview: continue
			var b_type = int(b.get("building_type")) if "building_type" in b else 0
			
			var rad = 0.0
			var visual_r = 16.0
			match b_type:
				0: rad = 0.0;    visual_r = 14.0 # Barricade
				1: rad = 96.0;   visual_r = 18.0 # Generator
				2: rad = 0.0;    visual_r = 15.0 # Turret
				3: rad = 128.0;  visual_r = 22.0 # Manufactorum
				4: rad = 160.0; visual_r = 10.0 # Distributor
				5: rad = 192.0; visual_r = 12.0 # Antenna
				6: rad = 112.0;  visual_r = 20.0 # Tech Shrine

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

	if not Engine.is_editor_hint():
		for b in get_tree().get_nodes_in_group("buildings"):
			if is_instance_valid(b) and int(b.get("building_type")) == 0:
				var visual_sprite = b.get_node_or_null("VisualBuildingSprite")
				if visual_sprite and "wall_connections" in visual_sprite:
					for conn_offset in visual_sprite.wall_connections:
						var p1 = to_local(b.global_position)
						var p2 = p1 + conn_offset
						_rasterize_line_cells(p1, p2, 12.0)

func _rasterize_line_cells(p1: Vector2, p2: Vector2, half_width: float = 12.0) -> void:
	var seg_dir = p2 - p1
	var seg_len_sq = seg_dir.length_squared()
	if seg_len_sq < 0.001: return

	var min_x = minf(p1.x, p2.x) - half_width
	var max_x = maxf(p1.x, p2.x) + half_width
	var min_y = minf(p1.y, p2.y) - half_width
	var max_y = maxf(p1.y, p2.y) + half_width

	var min_gx = int(floor(min_x / GRID_SIZE))
	var max_gx = int(ceil(max_x / GRID_SIZE))
	var min_gy = int(floor(min_y / GRID_SIZE))
	var max_gy = int(ceil(max_y / GRID_SIZE))

	var rad_sq = half_width * half_width

	for gx in range(min_gx, max_gx + 1):
		for gy in range(min_gy, max_gy + 1):
			var cell_center = Vector2((gx + 0.5) * GRID_SIZE, (gy + 0.5) * GRID_SIZE)
			var t = clampf((cell_center - p1).dot(seg_dir) / seg_len_sq, 0.0, 1.0)
			var proj_pt = p1 + (seg_dir * t)
			if cell_center.distance_squared_to(proj_pt) <= rad_sq:
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

		if not cached_active_cells.has(Vector2i(gx, gy - 1)):
			cached_perimeter_edges.append({"p1": top_left, "p2": top_right})
		if not cached_active_cells.has(Vector2i(gx, gy + 1)):
			cached_perimeter_edges.append({"p1": bottom_left, "p2": bottom_right})
		if not cached_active_cells.has(Vector2i(gx - 1, gy)):
			cached_perimeter_edges.append({"p1": top_left, "p2": bottom_left})
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

	# 1. Desert Sand Base
	draw_rect(full_rect, sand_base_color)

	var rng = RandomNumberGenerator.new()
	rng.seed = 44219
	for d in range(14):
		var cy = -half_size.y + (d * (floor_size.y / 14.0)) + rng.randf_range(-40.0, 40.0)
		var pts = PackedVector2Array()
		var x = -half_size.x
		while x <= half_size.x + 120.0:
			var w = sin((x * 0.0025) + float(d) * 1.7) * 45.0 + cos((x * 0.001) + float(d)) * 20.0
			pts.append(Vector2(x, cy + w))
			x += 120.0
		if pts.size() > 1:
			draw_polyline(pts, sand_shadow_color, 12.0)

	# 2. Flush Modular Industrial Ferrocrete Plates (32x32)
	for cell in cached_active_cells.keys():
		var origin = Vector2(cell.x * GRID_SIZE, cell.y * GRID_SIZE)
		var full_cell = Rect2(origin, Vector2(GRID_SIZE, GRID_SIZE))
		var inset_cell = Rect2(origin + Vector2(1, 1), Vector2(GRID_SIZE - 2, GRID_SIZE - 2))

		draw_rect(full_cell, plate_base_color)
		draw_rect(inset_cell, plate_inset_color)

		draw_line(origin, origin + Vector2(GRID_SIZE, 0), plate_highlight, 1.0)
		draw_line(origin, origin + Vector2(0, GRID_SIZE), plate_highlight, 1.0)
		draw_line(origin + Vector2(GRID_SIZE, 0), origin + Vector2(GRID_SIZE, GRID_SIZE), plate_shadow, 1.0)
		draw_line(origin + Vector2(0, GRID_SIZE), origin + Vector2(GRID_SIZE, GRID_SIZE), plate_shadow, 1.0)

		draw_circle(origin + Vector2(3, 3), 0.9, plate_highlight)
		draw_circle(origin + Vector2(GRID_SIZE - 3, 3), 0.9, plate_highlight)
		draw_circle(origin + Vector2(3, GRID_SIZE - 3), 0.9, plate_highlight)
		draw_circle(origin + Vector2(GRID_SIZE - 3, GRID_SIZE - 3), 0.9, plate_highlight)

	# 3. Ground Anchor Rim Brackets on Sand Perimeter
	for edge in cached_perimeter_edges:
		draw_line(edge.p1, edge.p2, Color(0.05, 0.06, 0.08), 3.0)
		draw_line(edge.p1, edge.p2, brass_rim_color, 1.2)
		draw_circle(edge.p1, 2.0, brass_rim_color)
		draw_circle(edge.p2, 2.0, brass_rim_color)

	# 4. Floor Cable Conduit Channels
	for link in cached_conduit_links:
		var source = cached_active_structures[link.from]
		var target = cached_active_structures[link.to]
		_draw_static_conduit(source.local_pos, target.local_pos, source.visual_radius, target.visual_radius)

func _draw_static_conduit(p1: Vector2, p2: Vector2, v_radius_1: float, v_radius_2: float) -> void:
	var direction = p2 - p1
	var total_len = direction.length()
	if total_len < 1.0: return
	var dir_norm = direction.normalized()
	
	var start = p1 + dir_norm * (v_radius_1 - 1.0)
	var finish = p2 - dir_norm * (v_radius_2 - 1.0)
	if start.distance_to(finish) < 4.0: return

	draw_line(start, finish, cable_dark, 3.5)
	draw_line(start, finish, cable_rubber, 1.5)
	draw_circle(start, 2.0, brass_rim_color)
	draw_circle(finish, 2.0, brass_rim_color)

func _build_conduit_network(structures: Array[Dictionary]) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	if structures.size() < 2: return links

	var base_idx = -1
	var relays: Array[int] = []
	var consumers: Array[int] = []

	for i in range(structures.size()):
		var s = structures[i]
		if s.is_base:
			base_idx = i
			relays.append(i)
		elif s.type in [4, 5]:
			relays.append(i)
		elif s.type in [1, 2, 3, 6]:
			consumers.append(i)

	for i in relays:
		if i == base_idx: continue
		var closest = -1
		var min_d = 420.0
		for j in relays:
			if i == j: continue
			var d = structures[i].local_pos.distance_to(structures[j].local_pos)
			if d < min_d: min_d = d; closest = j
		if closest != -1:
			links.append({"from": closest, "to": i})

	for c in consumers:
		var closest = -1
		var min_d = 280.0
		for r in relays:
			var d = structures[c].local_pos.distance_to(structures[r].local_pos)
			if d < min_d: min_d = d; closest = r
		if closest != -1:
			links.append({"from": closest, "to": c})

	return links

# --- UNSHADED PULSING ENERGY RENDERER ---
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
		var pulse_spacing = 40.0
		var pulse_offset = fmod(anim_timer * 60.0, pulse_spacing)

		for link in links:
			var s1 = structures[link.from]
			var s2 = structures[link.to]
			var dir = (s2.local_pos - s1.local_pos).normalized()
			var start = s1.local_pos + dir * (s1.visual_radius - 1.0)
			var finish = s2.local_pos - dir * (s2.visual_radius - 1.0)
			var seg_len = start.distance_to(finish)
			if seg_len < 4.0: continue

			draw_line(start, finish, Color(glow_color.r, glow_color.g, glow_color.b, 0.30), 1.0)

			var cur_d = pulse_offset
			while cur_d < seg_len:
				var p = start + dir * cur_d
				draw_circle(p, 1.8, Color(glow_color.r, glow_color.g, glow_color.b, 0.6))
				draw_circle(p, 0.8, Color.WHITE)
				cur_d += pulse_spacing
