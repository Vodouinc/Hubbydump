extends StaticBody2D

@export var max_health: int = 400
var current_health: int = 400
var pulse_time: float = 0.0
var raid_dispatch_timer: float = 20.0 # Sends a raiding party toward base every 20s
var glow_layer: Node2D = null

func _ready() -> void:
	add_to_group("objectives")
	current_health = max_health
	_setup_glow_layer()
	queue_redraw()

func _setup_glow_layer():
	if not has_node("WaaaghGlowOverlay"):
		glow_layer = Node2D.new()
		glow_layer.name = "WaaaghGlowOverlay"
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		glow_layer.material = mat
		add_child(glow_layer)
		glow_layer.set_script(load("res://WaaaghIdol.gd").WaaaghGlowRenderer)
	else:
		glow_layer = get_node("WaaaghGlowOverlay")

func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()

	if multiplayer.is_server():
		raid_dispatch_timer -= delta
		if raid_dispatch_timer <= 0.0:
			raid_dispatch_timer = 22.0
			_dispatch_camp_raiders()
	
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func _dispatch_camp_raiders() -> void:
	# Pick 1-2 guards and release them to charge the base
	var guards = get_tree().get_nodes_in_group("objective_guards")
	var count = 0
	for g in guards:
		if is_instance_valid(g) and g.get("guard_anchor") == global_position:
			if g.has_method("release_objective_guard"):
				g.release_objective_guard()
				count += 1
				if count >= 2: break

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
	# Release all remaining defenders into an all-out enraged assault
	get_tree().call_group("objective_guards", "release_objective_guard")
	
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		if main_node.has_method("add_scrap"):
			main_node.add_scrap(45)
		if main_node.has_method("add_requisition"):
			main_node.add_requisition(25)
			
	rpc("play_destroyed_feedback")
	queue_free()

@rpc("call_local", "reliable")
func play_destroyed_feedback() -> void:
	
	AudioManager.play_sfx("orbital_strike", global_position, 2.0, 1.3)
	
	var label = Label.new()
	label.global_position = global_position + Vector2(-60, -56)
	label.text = "◆ WAAAGH! IDOL DESTROYED ◆\n+45 SCRAP   +25 REQ"
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.35, 0.95, 1.0)
	label.label_settings.font_size = 14
	get_parent().add_child(label)
	get_tree().create_timer(3.0).timeout.connect(label.queue_free)

func _draw() -> void:
	var health_ratio = float(current_health) / float(max_health)
	var glow = 0.5 + sin(pulse_time * 3.5) * 0.25

	# 1. Pulsing Green WAAAGH! War-Totem Aura
	draw_arc(Vector2.ZERO, 38.0 + glow * 6.0, 0.0, TAU, 24, Color(0.35, 0.95, 0.15, glow * 0.35), 2.0)
	draw_circle(Vector2(3, 6), 36.0, Color(0.03, 0.05, 0.02, 0.45))

	# 2. Scrap Pile Base
	draw_circle(Vector2.ZERO, 30.0, Color(0.18, 0.19, 0.14))
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 16, Color(0.48, 0.45, 0.28), 3.0)

	# 3. Jagged Ork Glyph
	var glyph = PackedVector2Array([
		Vector2(-14, -24), Vector2(5, -12), Vector2(19, -25),
		Vector2(12, 18), Vector2(-18, 18)
	])
	draw_colored_polygon(glyph, Color(0.68, 0.09, 0.07))
	var closed = glyph.duplicate(); closed.append(glyph[0])
	draw_polyline(closed, Color(0.95, 0.55, 0.12), 2.5)

	# 4. Central Glowing Warp-Eye
	draw_circle(Vector2(0, -3), 7.0 + glow * 3.0, Color(0.35, 0.95, 0.12, glow))
	draw_circle(Vector2(0, -3), 3.0, Color.WHITE)

	# 5. Health Bar Plate
	draw_rect(Rect2(-30, -44, 60, 6), Color(0.04, 0.05, 0.04, 0.9))
	draw_rect(Rect2(-28, -42, 56.0 * health_ratio, 2.5), Color(0.35, 0.95, 0.15))
	
class WaaaghGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return
		var glow = 0.5 + sin(p.pulse_time * 3.5) * 0.25
		draw_arc(Vector2.ZERO, 38.0 + glow * 6.0, 0.0, TAU, 24, Color(0.35, 0.95, 0.15, glow * 0.45), 2.5)
		draw_circle(Vector2(0, -3), 7.0 + glow * 3.0, Color(0.35, 0.95, 0.12, glow))
		draw_circle(Vector2(0, -3), 3.0, Color.WHITE)
