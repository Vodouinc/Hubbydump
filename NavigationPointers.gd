extends Node2D

@onready var player: CharacterBody2D = get_parent()
@onready var base_pointer: CanvasItem = $BasePointer
@onready var teammate_pointer: CanvasItem = $TeammatePointer

const EDGE_MARGIN: float = 40.0 # Margin from window edge

func _process(_delta):
	# Only compute pointers for the local machine's active player screen
	if multiplayer.has_multiplayer_peer() and not player.is_multiplayer_authority():
		visible = false
		return
	
	visible = true
	var camera = player.get_node_or_null("Camera2D")
	if not camera:
		return

	# 1. Update Base Pointer
	var base_node = get_tree().get_first_node_in_group("base")
	if base_node:
		update_pointer(base_pointer, base_node.global_position, camera)

	# 2. Update Teammate Pointer
	var teammate = get_teammate_node()
	if teammate:
		teammate_pointer.visible = true
		update_pointer(teammate_pointer, teammate.global_position, camera)
	else:
		teammate_pointer.visible = false

func get_teammate_node() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if p != player:
			return p
	return null

func update_pointer(pointer: CanvasItem, target_pos: Vector2, camera: Camera2D):
	var viewport_rect = get_viewport_rect()
	var screen_center = camera.get_screen_center_position()
	var half_size = viewport_rect.size / 2.0 - Vector2(EDGE_MARGIN, EDGE_MARGIN)

	var target_vector = target_pos - screen_center

	# Check if target is inside screen view bounds
	if abs(target_vector.x) < half_size.x and abs(target_vector.y) < half_size.y:
		pointer.visible = false # Hide pointer when target is on screen
		return

	# Show pointer when target is off-screen
	pointer.visible = true
	pointer.z_index = 100 # Draw ON TOP of all map elements

	# Compute scale factor to push pointer directly onto screen edge
	var scale_factor = min(
		abs(half_size.x / target_vector.x) if target_vector.x != 0 else 999.0,
		abs(half_size.y / target_vector.y) if target_vector.y != 0 else 999.0
	)
	
	var clamped_screen_pos = screen_center + (target_vector * scale_factor)

	# Apply world position and rotate arrow toward target direction
	pointer.global_position = clamped_screen_pos
	pointer.global_rotation = target_vector.angle()
