extends StaticBody2D

@export var max_health: int = 350
var current_health: int = 350
var pulse_time := 0.0

func _ready() -> void:
	add_to_group("objectives")
	current_health = max_health
	queue_redraw()

func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if not multiplayer.is_server():
		return
	rpc("sync_health", max(0, current_health - amount))

@rpc("call_local", "reliable")
func sync_health(new_health: int) -> void:
	current_health = new_health
	if current_health <= 0 and multiplayer.is_server():
		_destroy_idol()
	queue_redraw()

func _destroy_idol() -> void:
	# The warband loses its gathering point and surges toward the main fight.
	get_tree().call_group("objective_guards", "release_objective_guard")
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		if main_node.has_method("add_scrap"):
			main_node.add_scrap(30)
		if main_node.has_method("add_requisition"):
			main_node.add_requisition(15)
	rpc("play_destroyed_feedback")
	queue_free()

@rpc("call_local", "reliable")
func play_destroyed_feedback() -> void:
	var label = Label.new()
	label.global_position = global_position + Vector2(-55, -56)
	label.text = "WAAAGH! IDOL DESTROYED\n+30 SCRAP  +15 REQ"
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.3, 0.95, 1.0)
	label.label_settings.font_size = 14
	get_parent().add_child(label)
	get_tree().create_timer(2.5).timeout.connect(label.queue_free)

func _draw() -> void:
	var health_ratio = float(current_health) / float(max_health)
	var glow = 0.45 + sin(pulse_time * 3.0) * 0.18
	# Crude, loud Ork construction: a red glyph bolted to a pile of scrap.
	draw_circle(Vector2(3, 6), 34.0, Color(0.03, 0.05, 0.02, 0.45))
	draw_circle(Vector2.ZERO, 28.0, Color(0.16, 0.18, 0.12))
	draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 16, Color(0.42, 0.40, 0.24), 3.0)
	var glyph = PackedVector2Array([Vector2(-12, -22), Vector2(4, -10), Vector2(17, -23), Vector2(10, 16), Vector2(-16, 16)])
	draw_colored_polygon(glyph, Color(0.62, 0.08, 0.06))
	draw_polyline(PackedVector2Array([glyph[0], glyph[1], glyph[2], glyph[3], glyph[4], glyph[0]]), Color(0.95, 0.55, 0.12), 2.0)
	draw_circle(Vector2(0, -3), 7.0 + glow * 4.0, Color(0.35, 0.95, 0.12, glow))
	draw_rect(Rect2(-28, -40, 56, 6), Color(0.04, 0.05, 0.04, 0.9))
	draw_rect(Rect2(-26, -38, 52.0 * health_ratio, 2), Color(0.35, 0.95, 0.15))
