extends StaticBody2D

@export var max_health: int = 500
var current_health: int = 500

@onready var health_bar: Node2D = get_node_or_null("HealthBar")
@onready var visual_sprite = get_node_or_null("VisualBuildingSprite") if has_node("VisualBuildingSprite") else get_node_or_null("VisualSprite")

func _ready():
	add_to_group("base")
	add_to_group("navmesh_source")
	
	# Add Sanctum Forge-Hearth PointLight
	if not has_node("SanctumLight"):
		var light = LightUtils.create_point_light(Color(1.0, 0.60, 0.18), 1.6, 4.0)
		light.name = "SanctumLight"
		add_child(light)

	current_health = max_health
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)
	update_ui()
	setup_building_type(true)
	get_tree().call_group("sandy_floor", "refresh_foundations")

func setup_building_type(is_main_base: bool):
	if not visual_sprite:
		visual_sprite = get_node_or_null("VisualBuildingSprite") if has_node("VisualBuildingSprite") else get_node_or_null("VisualSprite")
	if visual_sprite and "type" in visual_sprite:
		visual_sprite.type = 0 # 0 is MAIN_BASE in VisualBuildingSprite
		if visual_sprite.has_method("queue_redraw"):
			visual_sprite.queue_redraw()

func set_preview_mode(enabled: bool):
	if visual_sprite:
		visual_sprite.is_preview = enabled
		
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.set_deferred("disabled", enabled)
		
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
	var hb = get_node_or_null("HealthBar")
	if hb and hb.has_method("update_health"):
		hb.update_health(current_health, max_health)
	update_ui()
	
	if current_health <= 0 and (multiplayer.is_server() or not multiplayer.has_multiplayer_peer()):
		remove_from_group("navmesh_source")
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node:
			if main_node.has_method("request_navmesh_rebake"):
				main_node.request_navmesh_rebake()
			if main_node.has_method("game_over"):
				main_node.game_over(false)

func update_ui():
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
