extends StaticBody2D

@export var max_health: int = 500
var current_health: int = 500

@onready var health_bar: Node2D = get_node_or_null("HealthBar")
@onready var visual_sprite = $VisualSprite

func _ready():
	add_to_group("base")
	add_to_group("navmesh_source")
	
	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)
	update_ui()
	
	# Trigger SandyFloor to immediately generate the ferrocrete slab under the base!
	get_tree().call_group("sandy_floor", "refresh_foundations")

func setup_building_type(is_main_base: bool):
	if visual_sprite:
		if is_main_base:
			visual_sprite.type = visual_sprite.BuildingType.MAIN_BASE
		else:
			visual_sprite.type = visual_sprite.BuildingType.GENERATOR

func set_preview_mode(enabled: bool):
	if visual_sprite:
		visual_sprite.is_preview = enabled
		
	# Disable physics shape cleanly
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.set_deferred("disabled", enabled)
		
	# Keep navmesh clean during placement preview
	if enabled:
		remove_from_group("navmesh_source")
	else:
		if not is_in_group("navmesh_source"):
			add_to_group("navmesh_source")

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO):
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		var new_hp = max(0, current_health - amount)
		rpc("sync_base_health", new_hp)

@rpc("call_local", "reliable")
func sync_base_health(new_hp: int):
	current_health = new_hp
	update_ui()
	
	if current_health <= 0 and multiplayer.is_server():
		print("Base destroyed! Triggering game over...")
		
		# Clean up navmesh source group
		remove_from_group("navmesh_source")
		
		# Notify Main to trigger game over (and optionally request a navmesh rebake)
		var main_node = get_parent()
		if not (main_node and main_node.has_method("game_over")):
			main_node = get_tree().get_first_node_in_group("main")
			
		if main_node:
			if main_node.has_method("request_navmesh_rebake"):
				main_node.request_navmesh_rebake()
			if main_node.has_method("game_over"):
				main_node.game_over(false)

func update_ui():
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
