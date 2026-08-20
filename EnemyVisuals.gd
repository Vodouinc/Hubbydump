@tool
extends Node2D

enum EnemyType { GRETCHIN, SQUIG, ORK_BOY, STORMBOY, NOB }
var type: EnemyType = EnemyType.GRETCHIN
var anim_time: float = 0.0
var attack_flash: float = 0.0

var glow_layer: Node2D = null

func _ready() -> void:
	_setup_glow_layer()
	queue_redraw()

func _setup_glow_layer():
	if not has_node("EnemyGlowOverlay"):
		glow_layer = Node2D.new()
		glow_layer.name = "EnemyGlowOverlay"
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		glow_layer.material = mat
		add_child(glow_layer)
		glow_layer.set_script(load("res://EnemyVisuals.gd").EnemyGlowRenderer)
	else:
		glow_layer = get_node("EnemyGlowOverlay")

func _process(delta: float) -> void:
	anim_time += delta
	var parent_node = get_parent()
	var movement: float = parent_node.get("velocity").length() if parent_node and "velocity" in parent_node else 0.0
	
	position.y = sin(anim_time * (4.0 + movement * 0.015)) * (0.5 + minf(movement / 300.0, 1.0))
	
	if attack_flash > 0.0:
		attack_flash = maxf(0.0, attack_flash - delta * 5.0)

	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func play_attack_fx() -> void:
	attack_flash = 1.0
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func set_enemy_type(new_type: EnemyType) -> void:
	type = new_type
	queue_redraw()
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func _draw() -> void:
	match type:
		EnemyType.GRETCHIN: _draw_gretchin()
		EnemyType.SQUIG: _draw_squig()
		EnemyType.ORK_BOY: _draw_ork_boy()
		EnemyType.STORMBOY: _draw_stormboy()
		EnemyType.NOB: _draw_nob()

func _draw_gretchin() -> void:
	draw_circle(Vector2.ZERO, 10.0, Color("#8fb935"))
	draw_circle(Vector2(0, 10), 8.0, Color("#5c4033"))
	var left_ear = PackedVector2Array([Vector2(-6, -4), Vector2(-22, -12), Vector2(-4, 2)])
	var right_ear = PackedVector2Array([Vector2(6, -4), Vector2(22, -12), Vector2(4, 2)])
	draw_polygon(left_ear, [Color("#8fb935")])
	draw_polygon(right_ear, [Color("#8fb935")])
	var nose = PackedVector2Array([Vector2(-3, 0), Vector2(0, 8), Vector2(3, 0)])
	draw_polygon(nose, [Color("#769c28")])

func _draw_squig() -> void:
	draw_circle(Vector2.ZERO, 20.0, Color("#a61212"))
	var horn_l = PackedVector2Array([Vector2(-10, -15), Vector2(-18, -32), Vector2(-4, -18)])
	var horn_r = PackedVector2Array([Vector2(10, -15), Vector2(18, -32), Vector2(4, -18)])
	draw_polygon(horn_l, [Color("#e8e4c9")])
	draw_polygon(horn_r, [Color("#e8e4c9")])
	var mouth = PackedVector2Array([Vector2(-14, 2), Vector2(0, 16), Vector2(14, 2), Vector2(0, -2)])
	draw_polygon(mouth, [Color("#3a0000")])
	draw_line(Vector2(-10, -1), Vector2(-8, 8), Color("#e8e4c9"), 3.0)
	draw_line(Vector2(-2, -2), Vector2(0, 12), Color("#e8e4c9"), 3.5)
	draw_line(Vector2(8, -1), Vector2(6, 8), Color("#e8e4c9"), 3.0)

func _draw_ork_boy() -> void:
	draw_circle(Vector2(0, 6), 24.0, Color("#b81d13"))
	draw_circle(Vector2(0, -4), 16.0, Color("#2e6918"))
	var metal_jaw = PackedVector2Array([Vector2(-14, 2), Vector2(-8, 16), Vector2(8, 16), Vector2(14, 2)])
	draw_polygon(metal_jaw, [Color("#4a4e51")])
	draw_polyline(metal_jaw, Color("#1a1a1a"), 2.0)
	draw_line(Vector2(-6, 4), Vector2(-8, -4), Color("#e8e4c9"), 3.5)
	draw_line(Vector2(6, 4), Vector2(8, -4), Color("#e8e4c9"), 3.5)
	draw_line(Vector2(18, 10), Vector2(28, -20), Color("#2a2a2a"), 5.0)
	var blade = PackedVector2Array([Vector2(26, -20), Vector2(38, -16), Vector2(32, -40), Vector2(24, -28)])
	draw_polygon(blade, [Color("#d1d5db")])

func _draw_stormboy() -> void:
	# Rocket Thruster on back
	draw_rect(Rect2(-10, -26, 20, 14), Color("#2b2d30"))
	draw_rect(Rect2(-10, -26, 20, 14), Color("#b81d13"), false, 1.5)
	# Body & Pilot Goggles
	draw_circle(Vector2(0, 6), 20.0, Color("#3a3e42"))
	draw_circle(Vector2(0, -4), 14.0, Color("#2e6918"))
	# Leather Stikkbomb
	draw_circle(Vector2(-14, 6), 5.0, Color("#4a5568"))

func _draw_nob() -> void:
	# Massive Broad Iron Pauldrons & Mega-Armor
	draw_circle(Vector2(0, 8), 32.0, Color("#7b1113"))
	draw_circle(Vector2(0, -6), 20.0, Color("#1e4a10"))
	# Horned Boss Gobb
	var metal_gobb = PackedVector2Array([Vector2(-20, 4), Vector2(-12, 22), Vector2(12, 22), Vector2(20, 4)])
	draw_colored_polygon(metal_gobb, Color("#2d3748"))
	draw_polyline(metal_gobb, Color("#e2e8f0"), 2.5)
	# Big Tusk Fangs
	draw_line(Vector2(-10, 6), Vector2(-14, -6), Color("#f7fafc"), 4.5)
	draw_line(Vector2(10, 6), Vector2(14, -6), Color("#f7fafc"), 4.5)
	# Heavy Power Klaw
	draw_line(Vector2(24, 12), Vector2(38, -26), Color("#1a202c"), 7.0)
	var blade = PackedVector2Array([Vector2(32, -26), Vector2(50, -20), Vector2(42, -52), Vector2(30, -36)])
	draw_polygon(blade, [Color("#e2e8f0")])

# --- NIGHT GLOW FOR EYES & THRUSTERS ---
class EnemyGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		match p.type:
			0: # Gretchin
				var eye_glow = 0.7 + sin(p.anim_time * 7.0) * 0.25
				draw_circle(Vector2(-4, -3), 4.5, Color(1.0, 0.93, 0.0, 0.25 * eye_glow))
				draw_circle(Vector2(4, -3), 4.5, Color(1.0, 0.93, 0.0, 0.25 * eye_glow))
				draw_circle(Vector2(-4, -3), 2.5, Color(1.0, 0.93, 0.0))
				draw_circle(Vector2(4, -3), 2.5, Color(1.0, 0.93, 0.0))
			1: # Squig
				draw_circle(Vector2(-10, -10), 4.0, Color(1.0, 0.85, 0.0, 0.3))
				draw_circle(Vector2(10, -10), 4.0, Color(1.0, 0.85, 0.0, 0.3))
				draw_circle(Vector2(-10, -10), 2.3 + p.attack_flash * 2.0, Color("#ffcc00"))
				draw_circle(Vector2(10, -10), 2.3 + p.attack_flash * 2.0, Color("#ffcc00"))
			2: # Ork Boy
				var eye_pulse = 0.8 + sin(p.anim_time * 4.0) * 0.3
				draw_circle(Vector2(-6, -6), 6.0, Color(1.0, 0.1, 0.1, 0.35 * eye_pulse))
				draw_circle(Vector2(6, -6), 6.0, Color(1.0, 0.1, 0.1, 0.35 * eye_pulse))
				draw_circle(Vector2(-6, -6), 2.8 + p.attack_flash * 2.0, Color(1.0, 0.15, 0.15))
				draw_circle(Vector2(6, -6), 2.8 + p.attack_flash * 2.0, Color(1.0, 0.15, 0.15))
			3: # Stormboy (Rocket Exhaust Flame!)
				var flame_len = randf_range(12.0, 22.0)
				draw_line(Vector2(0, -26), Vector2(0, -26 - flame_len), Color(1.0, 0.5, 0.1, 0.9), 6.0)
				draw_line(Vector2(0, -26), Vector2(0, -26 - flame_len * 0.6), Color(1.0, 0.95, 0.2), 3.0)
				draw_circle(Vector2(-5, -6), 2.5, Color(1.0, 0.2, 0.2))
				draw_circle(Vector2(5, -6), 2.5, Color(1.0, 0.2, 0.2))
			4: # Ork Nob (Gigantic Menacing Red Visor Eyes)
				draw_circle(Vector2(-8, -8), 8.0, Color(1.0, 0.05, 0.05, 0.45))
				draw_circle(Vector2(8, -8), 8.0, Color(1.0, 0.05, 0.05, 0.45))
				draw_circle(Vector2(-8, -8), 3.5, Color(1.0, 0.15, 0.15))
				draw_circle(Vector2(8, -8), 3.5, Color(1.0, 0.15, 0.15))
				draw_circle(Vector2(-8, -8), 1.5, Color.WHITE)
				draw_circle(Vector2(8, -8), 1.5, Color.WHITE)
