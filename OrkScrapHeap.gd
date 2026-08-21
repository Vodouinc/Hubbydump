@tool
extends StaticBody2D

@export var max_health: int = 400
var current_health: int = 400

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("objectives")
	add_to_group("ork_structures")
	add_to_group("navmesh_source")
	
	max_health = GameData.ORK_SCRAP_HEAP_MAX_HEALTH
	current_health = max_health
	
	var col = get_node_or_null("CollisionShape2D")
	if not col:
		col = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(44, 44)
		col.shape = rect
		add_child(col)
		
	queue_redraw()

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		var new_hp = max(0, current_health - amount)
		rpc("sync_scrapheap_health", new_hp)

@rpc("call_local", "reliable")
func sync_scrapheap_health(new_hp: int) -> void:
	current_health = new_hp
	if current_health <= 0 and (multiplayer.is_server() or not multiplayer.has_multiplayer_peer()):
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node and main_node.has_method("add_scrap"):
			main_node.add_scrap(30)
		AudioManager.play_sfx("orbital_strike", global_position, -2.0, 1.5)
		queue_free()

func _draw() -> void:
	var rust_dark = Color(0.18, 0.14, 0.10)
	var rust_mid = Color(0.42, 0.28, 0.18)
	var blood_red = Color(0.68, 0.12, 0.10)
	var iron_spike = Color(0.65, 0.70, 0.75)

	# Jagged irregular scrap pile polygon
	var poly = PackedVector2Array([
		Vector2(-20, -14), Vector2(0, -22), Vector2(22, -12),
		Vector2(18, 16), Vector2(-4, 22), Vector2(-22, 10)
	])
	draw_colored_polygon(poly, rust_dark)
	draw_polyline(poly, rust_mid, 2.5)

	# Red armored scrap panels
	draw_rect(Rect2(-12, -8, 24, 16), blood_red)
	draw_rect(Rect2(-12, -8, 24, 16), Color.BLACK, false, 1.5)

	# Jutting spikes
	draw_line(Vector2(-10, -10), Vector2(-16, -20), iron_spike, 2.5)
	draw_line(Vector2(12, -8), Vector2(20, -18), iron_spike, 2.5)
