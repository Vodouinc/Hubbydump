extends Node2D

@onready var player: CharacterBody2D = get_parent()
@onready var base_pointer: CanvasItem = get_node_or_null("BasePointer")
@onready var teammate_pointer: CanvasItem = get_node_or_null("TeammatePointer")

const EDGE_MARGIN: float = 48.0
var active_threat_angles: Array = []
var pulse_time: float = 0.0

func _ready():
	add_to_group("navigation_pointers")
	z_index = 120 # Draw above all world elements and shadows
	
	var unshaded = CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded

func set_threat_lanes(angles: Array):
	active_threat_angles = angles
	queue_redraw()

func _process(delta: float):
	if multiplayer.has_multiplayer_peer() and not player.is_multiplayer_authority():
		visible = false
		return
	
	visible = true
	pulse_time += delta
	queue_redraw()

	var camera = player.get_node_or_null("Camera2D") as Camera2D
	if not camera: return

	# 1. Base Pointer (if nodes exist in scene)
	var base_node = get_tree().get_first_node_in_group("base")
	if base_node and is_instance_valid(base_pointer):
		_update_legacy_pointer(base_pointer, base_node.global_position, camera)

	# 2. Teammate Pointer
	var teammate = _get_teammate_node()
	if teammate and is_instance_valid(teammate_pointer):
		teammate_pointer.visible = true
		_update_legacy_pointer(teammate_pointer, teammate.global_position, camera)
	elif is_instance_valid(teammate_pointer):
		teammate_pointer.visible = false

func _get_teammate_node() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if p != player and is_instance_valid(p):
			return p
	return null

func _update_legacy_pointer(pointer: CanvasItem, target_pos: Vector2, camera: Camera2D):
	var viewport_rect = get_viewport_rect()
	var screen_center = camera.get_screen_center_position()
	var half_size = viewport_rect.size / 2.0 - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var target_vector = target_pos - screen_center

	if abs(target_vector.x) < half_size.x and abs(target_vector.y) < half_size.y:
		pointer.visible = false
		return

	pointer.visible = true
	var scale_factor = min(
		abs(half_size.x / target_vector.x) if target_vector.x != 0 else 999.0,
		abs(half_size.y / target_vector.y) if target_vector.y != 0 else 999.0
	)
	pointer.global_position = screen_center + (target_vector * scale_factor)
	pointer.global_rotation = target_vector.angle()

func _draw():
	if multiplayer.has_multiplayer_peer() and not player.is_multiplayer_authority():
		return
	if active_threat_angles.is_empty():
		return

	var camera = player.get_node_or_null("Camera2D") as Camera2D
	if not camera: return

	var viewport_rect = get_viewport_rect()
	var screen_center = camera.get_screen_center_position()
	var half_size = (viewport_rect.size / 2.0) - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var base_node = get_tree().get_first_node_in_group("base")
	var origin_pos = base_node.global_position if base_node else screen_center

	var pulse = 0.65 + sin(pulse_time * 5.5) * 0.35
	var threat_color = Color(1.0, 0.20, 0.15, pulse)
	var text_color = Color(1.0, 0.85, 0.3, pulse)
	var font = ThemeDB.fallback_font

	for angle_val in active_threat_angles:
		var dir = Vector2.RIGHT.rotated(float(angle_val))
		var threat_world_target = origin_pos + (dir * 900.0)
		var to_threat = threat_world_target - screen_center

		# Clamping to screen edges
		var scale_factor = min(
			abs(half_size.x / to_threat.x) if to_threat.x != 0 else 999.0,
			abs(half_size.y / to_threat.y) if to_threat.y != 0 else 999.0
		)
		var edge_pos = (to_threat * scale_factor) # Local to screen center

		# Draw Auspex Threat Chevron & Badge
		draw_set_transform(edge_pos, dir.angle(), Vector2.ONE)

		# 1. Warning Arrow / Chevrons
		var chevron_1 = PackedVector2Array([Vector2(-14, -10), Vector2(0, 0), Vector2(-14, 10), Vector2(-8, 0)])
		var chevron_2 = PackedVector2Array([Vector2(-24, -8), Vector2(-12, 0), Vector2(-24, 8), Vector2(-18, 0)])
		draw_colored_polygon(chevron_1, threat_color)
		draw_colored_polygon(chevron_2, Color(threat_color.r, threat_color.g, threat_color.b, threat_color.a * 0.6))

		# 2. Holographic Border Box
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		var badge_rect = Rect2(edge_pos - Vector2(40, 11), Vector2(80, 22))
		draw_rect(badge_rect, Color(0.06, 0.08, 0.12, 0.85), true)
		draw_rect(badge_rect, threat_color, false, 1.5)
		
		# Text Label
		draw_string(font, edge_pos + Vector2(-34, 4), "⚠️ HOSTILE", HORIZONTAL_ALIGNMENT_CENTER, 70, 10, text_color)
