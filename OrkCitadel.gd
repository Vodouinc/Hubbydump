@tool
extends StaticBody2D

@export var max_health: int = 2500
var current_health: int = 2500

@onready var health_bar: Node2D = get_node_or_null("HealthBar")
var pulse_time: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("objectives")
	add_to_group("ork_citadel")
	add_to_group("navmesh_source")
	
	max_health = GameData.ORK_CITADEL_MAX_HEALTH
	current_health = max_health
	
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)
	
	# Solid collision
	var col = get_node_or_null("CollisionShape2D")
	if not col:
		col = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(110, 110)
		col.shape = rect
		add_child(col)
		
	queue_redraw()

func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		var new_hp = max(0, current_health - amount)
		rpc("sync_citadel_health", new_hp)

@rpc("call_local", "reliable")
func sync_citadel_health(new_hp: int) -> void:
	current_health = new_hp
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
		
	if current_health <= 0 and (multiplayer.is_server() or not multiplayer.has_multiplayer_peer()):
		_destroy_citadel()

func _destroy_citadel() -> void:
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		if main_node.has_method("add_scrap"): main_node.add_scrap(250)
		if main_node.has_method("add_requisition"): main_node.add_requisition(150)
		# Trigger Instant Crusade Victory!
		if main_node.has_method("game_over"):
			main_node.game_over(true)

	AudioManager.play_sfx("orbital_strike", global_position, 4.0, 0.5)
	queue_free()

func _draw() -> void:
	var scrap_dark = Color(0.14, 0.12, 0.10)
	var rusted_plate = Color(0.38, 0.22, 0.14)
	var blood_red = Color(0.65, 0.10, 0.08)
	var bone_ivory = Color(0.88, 0.84, 0.72)
	var iron_trim = Color(0.60, 0.65, 0.70)
	var waaagh_green = Color(0.35, 0.95, 0.15)
	var pulse = 0.6 + sin(pulse_time * 3.5) * 0.35

	# 1. Massive Cobbled Scrap Base Plinth (120x120)
	var base_rect = Rect2(-56, -56, 112, 112)
	draw_rect(base_rect, scrap_dark)
	draw_rect(base_rect, rusted_plate, false, 4.0)

	# 2. Four Spiked Bastion Towers
	for c in [Vector2(-44, -44), Vector2(44, -44), Vector2(-44, 44), Vector2(44, 44)]:
		draw_rect(Rect2(c - Vector2(14, 14), Vector2(28, 28)), Color(0.18, 0.15, 0.12))
		draw_rect(Rect2(c - Vector2(14, 14), Vector2(28, 28)), blood_red, false, 2.5)
		# Corner horn spikes
		draw_line(c, c + c.normalized() * 18.0, bone_ivory, 3.5)

	# 3. Fortress Courtyard & Rusty Chimney Stacks
	draw_rect(Rect2(-36, -36, 72, 72), rusted_plate)
	draw_rect(Rect2(-32, -32, 64, 64), blood_red)
	draw_rect(Rect2(-32, -32, 64, 64), iron_trim, false, 2.0)

	# 4. Giant Horned WAAAGH! Warboss Totem Skull in Center
	var skull_poly = PackedVector2Array([
		Vector2(-20, -22), Vector2(0, -32), Vector2(20, -22),
		Vector2(24, 12), Vector2(12, 26), Vector2(-12, 26), Vector2(-24, 12)
	])
	draw_colored_polygon(skull_poly, Color(0.10, 0.10, 0.12))
	draw_polyline(skull_poly, bone_ivory, 3.0)

	# Glowing Green WAAAGH! Eyes
	draw_circle(Vector2(-8, -4), 4.5, Color(waaagh_green.r, waaagh_green.g, waaagh_green.b, 0.4 * pulse))
	draw_circle(Vector2(8, -4), 4.5, Color(waaagh_green.r, waaagh_green.g, waaagh_green.b, 0.4 * pulse))
	draw_circle(Vector2(-8, -4), 2.5, waaagh_green)
	draw_circle(Vector2(8, -4), 2.5, waaagh_green)
	draw_circle(Vector2(-8, -4), 1.0, Color.WHITE)
	draw_circle(Vector2(8, -4), 1.0, Color.WHITE)

	# Massive Jagged Tusk Fangs
	draw_line(Vector2(-12, 14), Vector2(-18, -4), bone_ivory, 4.5)
	draw_line(Vector2(12, 14), Vector2(18, -4), bone_ivory, 4.5)

	# 5. Health Bar Plate
	var hp_ratio = float(current_health) / float(max_health)
	draw_rect(Rect2(-50, -68, 100, 7), Color(0.04, 0.05, 0.04, 0.95))
	draw_rect(Rect2(-48, -66, 96 * hp_ratio, 3.5), Color(0.95, 0.20, 0.15))
