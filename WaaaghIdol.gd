extends StaticBody2D

enum Tier { FERAL_OUTPOST = 1, WARBAND_CAMP = 2, MEGA_EFFIGY = 3 }
var tier: Tier = Tier.FERAL_OUTPOST

var time_alive: float = 0.0
@export var max_health: int = 350
var current_health: int = 350
var pulse_time: float = 0.0
var raid_dispatch_timer: float = 16.0
var glow_layer: Node2D = null

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("objectives")
	add_to_group("waaagh_totems") # <-- Add this line
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
	if is_instance_valid(glow_layer): glow_layer.queue_redraw()

	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		time_alive += delta
		
		# --- TIER EVOLUTION OVER TIME ---
		if time_alive >= 90.0 and tier < Tier.MEGA_EFFIGY:
			_evolve_to_tier(Tier.MEGA_EFFIGY, 1000, 350)
		elif time_alive >= 45.0 and tier < Tier.WARBAND_CAMP:
			_evolve_to_tier(Tier.WARBAND_CAMP, 650, 250)

		# --- RAID DISPATCH INTERVALS BY TIER ---
		raid_dispatch_timer -= delta
		if raid_dispatch_timer <= 0.0:
			match tier:
				Tier.FERAL_OUTPOST: raid_dispatch_timer = randf_range(16.0, 20.0)
				Tier.WARBAND_CAMP:  raid_dispatch_timer = randf_range(12.0, 15.0)
				Tier.MEGA_EFFIGY:   raid_dispatch_timer = randf_range(8.0, 11.0)
			_spawn_active_base_raiders()

func _evolve_to_tier(new_tier: Tier, new_max_hp: int, hp_heal_bonus: int):
	tier = new_tier
	max_health = new_max_hp
	current_health = min(max_health, current_health + hp_heal_bonus)
	rpc("sync_tier_evolution", int(tier), current_health, max_health)
	AudioManager.play_sfx("orbital_strike", global_position, 1.0, 0.7 if tier == Tier.MEGA_EFFIGY else 0.9)

@rpc("call_local", "reliable")
func sync_tier_evolution(new_tier: int, new_hp: int, new_max_hp: int):
	tier = new_tier as Tier
	current_health = new_hp
	max_health = new_max_hp
	queue_redraw()

func _spawn_active_base_raiders() -> void:
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node or not ("spawner" in main_node) or not main_node.spawner: return

	# Raiding party composition scales with Totem Tier!
	var raid_units = []
	match tier:
		Tier.FERAL_OUTPOST:
			raid_units = [0, 1] # Gretchin + Squig
		Tier.WARBAND_CAMP:
			raid_units = [2, 3, 1] # Ork Boy + Stormboy + Squig
		Tier.MEGA_EFFIGY:
			raid_units = [4, 3, 2, 1] # Ork Nob + Stormboy + Boy + Squig!

	for unit_type in raid_units:
		var spawn_pos = global_position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30, 70)
		main_node.spawner.spawn({
			"type": "enemy",
			"name": "CampRaider_" + str(randi()),
			"enemy_type": unit_type,
			"position": spawn_pos,
			"is_objective_guard": false, # Marches on the main base!
			"counts_toward_wave": false
		})

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer(): return
	rpc("sync_health", max(0, current_health - amount))

@rpc("call_local", "reliable")
func sync_health(new_health: int) -> void:
	current_health = new_health
	if current_health <= 0 and (multiplayer.is_server() or not multiplayer.has_multiplayer_peer()):
		_destroy_idol()
	queue_redraw()

func _destroy_idol() -> void:
	get_tree().call_group("objective_guards", "release_objective_guard")
	
	var scrap_reward = 35
	var req_reward = 20
	match tier:
		Tier.WARBAND_CAMP:  scrap_reward = 70;  req_reward = 40
		Tier.MEGA_EFFIGY:   scrap_reward = 140; req_reward = 75

	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		if main_node.has_method("add_scrap"): main_node.add_scrap(scrap_reward)
		if main_node.has_method("add_requisition"): main_node.add_requisition(req_reward)
		# Immediately notify Main to recalculate threat & broadcast HUD!
		if main_node.has_method("notify_totem_destroyed"):
			main_node.notify_totem_destroyed()
		
	rpc("play_destroyed_feedback", scrap_reward, req_reward)
	queue_free()

@rpc("call_local", "reliable")
func play_destroyed_feedback(scrap_amt: int, req_amt: int) -> void:
	AudioManager.play_sfx("orbital_strike", global_position, 2.5, 1.2)
	var label = Label.new()
	label.global_position = global_position + Vector2(-80, -60)
	var tier_name = "FERAL OUTPOST" if tier == Tier.FERAL_OUTPOST else ("WARBAND STRONGHOLD" if tier == Tier.WARBAND_CAMP else "MEGA-WAAAGH! EFFIGY")
	label.text = "◆ " + tier_name + " DESTROYED ◆\n+" + str(scrap_amt) + " SCRAP   +" + str(req_amt) + " REQ"
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.35, 0.95, 1.0)
	label.label_settings.font_size = 14
	get_tree().current_scene.add_child(label) # Use current_scene to avoid premature free
	get_tree().create_timer(3.5).timeout.connect(label.queue_free)

func _draw() -> void:
	var health_ratio = float(current_health) / float(max_health)
	var scale_mult = 1.0 if tier == Tier.FERAL_OUTPOST else (1.25 if tier == Tier.WARBAND_CAMP else 1.55)

	# 1. Base Scrap Pile
	var r_base = 30.0 * scale_mult
	draw_circle(Vector2(3, 6), r_base + 6.0, Color(0.03, 0.05, 0.02, 0.45))
	draw_circle(Vector2.ZERO, r_base, Color(0.18, 0.19, 0.14))
	draw_arc(Vector2.ZERO, r_base, 0.0, TAU, 16, Color(0.48, 0.45, 0.28), 3.0)

	# 2. Tier 2 & 3 Iron Horn Tusks
	if tier >= Tier.WARBAND_CAMP:
		var tusk_l = PackedVector2Array([Vector2(-24 * scale_mult, 0), Vector2(-36 * scale_mult, -28 * scale_mult), Vector2(-16 * scale_mult, -12 * scale_mult)])
		var tusk_r = PackedVector2Array([Vector2(24 * scale_mult, 0), Vector2(36 * scale_mult, -28 * scale_mult), Vector2(16 * scale_mult, -12 * scale_mult)])
		draw_colored_polygon(tusk_l, Color("#2d3748"))
		draw_polyline(tusk_l, Color("#e2e8f0"), 2.0)
		draw_colored_polygon(tusk_r, Color("#2d3748"))
		draw_polyline(tusk_r, Color("#e2e8f0"), 2.0)

	# 3. Jagged Red Ork Glyph
	var glyph = PackedVector2Array([
		Vector2(-14, -24) * scale_mult, Vector2(5, -12) * scale_mult, Vector2(19, -25) * scale_mult,
		Vector2(12, 18) * scale_mult, Vector2(-18, 18) * scale_mult
	])
	draw_colored_polygon(glyph, Color(0.68, 0.09, 0.07))
	var closed = glyph.duplicate(); closed.append(glyph[0])
	draw_polyline(closed, Color(0.95, 0.55, 0.12), 2.5)

	# 4. Health Bar Plate
	var bar_w = 60.0 * scale_mult
	var bar_y = -44.0 * scale_mult
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 6.0), Color(0.04, 0.05, 0.04, 0.9))
	draw_rect(Rect2(-bar_w * 0.5 + 2.0, bar_y + 1.5, (bar_w - 4.0) * health_ratio, 3.0), Color(0.35, 0.95, 0.15))

class WaaaghGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return
		var glow = 0.5 + sin(p.pulse_time * 3.5) * 0.25
		var scale_mult = 1.0 if p.tier == Tier.FERAL_OUTPOST else (1.25 if p.tier == Tier.WARBAND_CAMP else 1.55)

		# Expanding Unshaded Green Warp Storm Aura
		var aura_r = (38.0 + glow * 8.0) * scale_mult
		draw_arc(Vector2.ZERO, aura_r, 0.0, TAU, 24, Color(0.35, 0.95, 0.15, glow * (0.35 if p.tier == Tier.FERAL_OUTPOST else 0.65)), 2.5)
		
		if p.tier == Tier.MEGA_EFFIGY:
			# Extra rotating warp lightning arcs for Tier 3
			draw_arc(Vector2.ZERO, aura_r + 14.0, p.pulse_time * 2.0, p.pulse_time * 2.0 + PI, 16, Color(0.40, 1.0, 0.20, 0.8), 2.0)

		draw_circle(Vector2(0, -3 * scale_mult), (7.0 + glow * 3.0) * scale_mult, Color(0.35, 0.95, 0.12, glow))
		draw_circle(Vector2(0, -3 * scale_mult), 3.0 * scale_mult, Color.WHITE)
