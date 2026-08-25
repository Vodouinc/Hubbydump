# res://FogOfWar.gd
extends Node2D
class_name FogOfWar

const GRID_SIZE: int = 192 # 192x192 texture for smooth 60 FPS performance
const WORLD_EXTENT: float = 3750.0 # Covers full 7500x7500 map

var base_pos: Vector2 = Vector2(500, 500)
var fog_texture: ImageTexture
var fog_mesh: MeshInstance2D

var raw_bytes: PackedByteArray
var tick_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.05 # Updates vision 20 times per second

# Vision Radii Table
const VISION_RANGES := {
	"base": 650.0,
	"player": 520.0, # Generous player line of sight
	"antenna": 560.0, # High-vision watchtower
	"distributor": 380.0,
	"building": 340.0,
	"barricade": 200.0,
	"scout": 400.0, # Servo-Skulls & Bodyguards
}

func _ready() -> void:
	add_to_group("fog_of_war")
	z_index = 75 # Sits above terrain, obstacles, and enemies, but below UI

	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		base_pos = base_node.global_position

	_init_buffers()
	_setup_mesh_and_shader()
	update_fog()

func _init_buffers() -> void:
	# RGBA8 Buffer: Red = Active Vision, Green = Explored Memory, Alpha = 255
	raw_bytes = PackedByteArray()
	raw_bytes.resize(GRID_SIZE * GRID_SIZE * 4)
	raw_bytes.fill(0)
	
	for i in range(GRID_SIZE * GRID_SIZE):
		raw_bytes[i * 4 + 3] = 255

	var img = Image.create_from_data(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGBA8, raw_bytes)
	fog_texture = ImageTexture.create_from_image(img)

func _setup_mesh_and_shader() -> void:
	fog_mesh = MeshInstance2D.new()
	fog_mesh.name = "FogMesh"
	
	var quad = QuadMesh.new()
	quad.size = Vector2(WORLD_EXTENT * 2.0, WORLD_EXTENT * 2.0)
	fog_mesh.mesh = quad
	fog_mesh.position = base_pos

	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;

	uniform sampler2D fog_texture : filter_linear, repeat_disable;
	uniform vec4 color_unexplored : source_color = vec4(0.02, 0.03, 0.05, 1.0);
	uniform vec4 color_shrouded : source_color = vec4(0.04, 0.05, 0.08, 0.72);

	void fragment() {
		vec4 f = texture(fog_texture, UV);
		float active_vis = f.r; // Red channel = Live sight
		float explored = f.g;   // Green channel = Explored memory

		// Unexplored -> Pitch Black (1.0 alpha)
		// Explored -> Shrouded Fog (0.72 alpha)
		// Active Sight -> Fully Transparent (0.0 alpha)
		vec4 fog_col = mix(color_unexplored, color_shrouded, clamp(explored * 2.0, 0.0, 1.0));
		float final_alpha = mix(fog_col.a, 0.0, clamp(active_vis * 2.0, 0.0, 1.0));

		COLOR = vec4(fog_col.rgb, final_alpha);
	}
	"""
	mat.shader = shader
	mat.set_shader_parameter("fog_texture", fog_texture)
	fog_mesh.material = mat
	add_child(fog_mesh)

func _process(delta: float) -> void:
	tick_timer += delta
	if tick_timer >= UPDATE_INTERVAL:
		tick_timer = 0.0
		update_fog()

func reset_fog() -> void:
	_init_buffers()
	update_fog()

func update_fog() -> void:
	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node):
		base_pos = base_node.global_position
		if is_instance_valid(fog_mesh):
			fog_mesh.position = base_pos

	# 1. Clear Active Vision (Red Channel), preserve Explored Memory (Green Channel)
	for i in range(GRID_SIZE * GRID_SIZE):
		raw_bytes[i * 4] = 0

	# 2. Stamp vision for Base
	if is_instance_valid(base_node):
		_stamp_vision(base_node.global_position, VISION_RANGES["base"])

	# 3. Stamp vision for Players (Follows player movement in real-time)
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and not p.get("is_dead"):
			_stamp_vision(p.global_position, VISION_RANGES["player"])

	# 4. Stamp vision for Buildings & Antennas
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.get("is_preview"):
			var b_type = int(b.get("building_type")) if "building_type" in b else 0
			var r = VISION_RANGES["building"]
			if b_type == 5: r = VISION_RANGES["antenna"]
			elif b_type == 4: r = VISION_RANGES["distributor"]
			elif b_type == 0: r = VISION_RANGES["barricade"]
			_stamp_vision(b.global_position, r)

	# 5. Stamp vision for Servo-Skulls & Bodyguards
	for unit in get_tree().get_nodes_in_group("controllable_units"):
		if is_instance_valid(unit) and not unit.is_in_group("players"):
			_stamp_vision(unit.global_position, VISION_RANGES["scout"])

	# 6. Re-create image from data and push update to GPU texture
	var img = Image.create_from_data(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGBA8, raw_bytes)
	fog_texture.update(img)

func _stamp_vision(world_pos: Vector2, radius_world: float) -> void:
	var gc = _world_to_grid(world_pos)
	var gr = int(round((radius_world / (WORLD_EXTENT * 2.0)) * float(GRID_SIZE)))
	var gr_sq = gr * gr

	var min_x = clampi(gc.x - gr, 0, GRID_SIZE - 1)
	var max_x = clampi(gc.x + gr, 0, GRID_SIZE - 1)
	var min_y = clampi(gc.y - gr, 0, GRID_SIZE - 1)
	var max_y = clampi(gc.y + gr, 0, GRID_SIZE - 1)

	for y in range(min_y, max_y + 1):
		var dy_sq = (y - gc.y) * (y - gc.y)
		var row_offset = y * GRID_SIZE
		for x in range(min_x, max_x + 1):
			var dx = x - gc.x
			if (dx * dx + dy_sq) <= gr_sq:
				var idx = (row_offset + x) * 4
				raw_bytes[idx] = 255     # Red: Active Vision
				raw_bytes[idx + 1] = 255 # Green: Explored Memory

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	var delta = world_pos - base_pos
	var gx = int(clampf(((delta.x + WORLD_EXTENT) / (WORLD_EXTENT * 2.0)) * float(GRID_SIZE), 0, GRID_SIZE - 1))
	var gy = int(clampf(((delta.y + WORLD_EXTENT) / (WORLD_EXTENT * 2.0)) * float(GRID_SIZE), 0, GRID_SIZE - 1))
	return Vector2i(gx, gy)

func is_world_pos_visible(world_pos: Vector2) -> bool:
	if raw_bytes.is_empty(): return true
	var g = _world_to_grid(world_pos)
	var idx = (g.y * GRID_SIZE + g.x) * 4
	return raw_bytes[idx] > 30

func is_world_pos_explored(world_pos: Vector2) -> bool:
	if raw_bytes.is_empty(): return true
	var g = _world_to_grid(world_pos)
	var idx = (g.y * GRID_SIZE + g.x) * 4
	return raw_bytes[idx + 1] > 30
