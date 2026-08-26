extends StaticBody2D
class_name SebastianRelic

var is_collected: bool = false

func _ready() -> void:
	add_to_group("objectives")
	add_to_group("quest_interactables")
	
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 28.0
	col.shape = shape
	add_child(col)

func interact(player_node: Node2D) -> void:
	if is_collected: return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(1, "request_collect_relic", player_node.name)
		return

	_collect_relic_internal()

@rpc("any_peer", "call_local", "reliable")
func request_collect_relic(_player_name: String) -> void:
	if is_collected: return
	_collect_relic_internal()

func _collect_relic_internal() -> void:
	is_collected = true
	if multiplayer.has_multiplayer_peer():
		rpc("sync_relic_collected")
	else:
		sync_relic_collected()

@rpc("call_local", "reliable")
func sync_relic_collected() -> void:
	is_collected = true
	AudioManager.play_sfx("binary_canticle", global_position, 2.0, 1.4)

	# Inform Outpost
	var outpost = get_tree().get_first_node_in_group("sororitas_outpost")
	if is_instance_valid(outpost) and outpost.has_method("set_relic_found"):
		outpost.set_relic_found(true)

	# Post Clean Banner Notification
	get_tree().call_group("event_banner", "post_banner", 
		"✨ ARCHEOTECH SECURED", 
		"The Relic of Sebastian Thor has been recovered! Return it to the Sisters.", 
		1 # SORORITAS_HOLY
	)

	queue_free()

func _draw() -> void:
	if is_collected: return
	var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.006) * 0.3
	var gold = Color(1.0, 0.85, 0.25, 0.9 * pulse)
	var glow = Color(1.0, 0.70, 0.15, 0.15 * pulse)

	draw_circle(Vector2.ZERO, 22.0, glow)
	draw_arc(Vector2.ZERO, 20.0, 0, TAU, 24, gold, 1.5)
	draw_rect(Rect2(-12, -8, 24, 16), Color(0.15, 0.12, 0.08), true)
	draw_rect(Rect2(-12, -8, 24, 16), gold, false, 1.4)
	
	draw_line(Vector2(0, -6), Vector2(0, 6), Color.WHITE, 2.0)
	draw_line(Vector2(-4, -2), Vector2(4, -2), Color.WHITE, 2.0)

	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(-48, -26), "[E] CLAIM RELIC", HORIZONTAL_ALIGNMENT_CENTER, 96, 8, gold)
