@tool
extends Node2D

enum EnemyType { GRETCHIN, SQUIG, ORK_BOY, STORMBOY, NOB }
var type: EnemyType = EnemyType.GRETCHIN
var anim_time: float = 0.0
var attack_flash: float = 0.0
var attack_swing_progress: float = 0.0

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
	
	# Running bob
	position.y = sin(anim_time * (5.0 + movement * 0.015)) * (0.6 + minf(movement / 250.0, 1.2))
	
	if attack_flash > 0.0:
		attack_flash = maxf(0.0, attack_flash - delta * 4.0)

	if attack_swing_progress > 0.0:
		attack_swing_progress = maxf(0.0, attack_swing_progress - delta * 4.5)
		queue_redraw()

	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func play_attack_fx() -> void:
	attack_flash = 1.0
	attack_swing_progress = 1.0
	queue_redraw()
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func set_enemy_type(new_type: int) -> void:
	type = new_type as EnemyType
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

	# --- MELEE ATTACK SWIPE ANIMATIONS ---
	if attack_swing_progress > 0.0:
		_draw_attack_swing()

func _draw_attack_swing() -> void:
	var swing_t = 1.0 - attack_swing_progress # 0.0 -> 1.0
	var alpha = attack_swing_progress

	match type:
		EnemyType.SQUIG:
			# Chomping bite snap
			var bite_lunge = sin(swing_t * PI) * 10.0
			draw_arc(Vector2(bite_lunge + 6.0, 0.0), 12.0, -PI * 0.4, PI * 0.4, 8, Color(1.0, 0.2, 0.2, alpha * 0.8), 2.5)

		EnemyType.ORK_BOY:
			# Cleaving Choppa Slash Arc
			var start_angle = -PI * 0.6 + (swing_t * PI * 0.3)
			var end_angle = start_angle + PI * 0.85
			draw_arc(Vector2(6, 0), 28.0, start_angle, end_angle, 12, Color(1.0, 0.25, 0.15, alpha * 0.9), 4.0)
			draw_arc(Vector2(6, 0), 28.0, start_angle + 0.1, end_angle - 0.1, 12, Color.WHITE, 1.5)

		EnemyType.STORMBOY:
			# Dual Cross-Slash
			var slash_len = 22.0
			draw_line(Vector2(0, -12), Vector2(18, 10), Color(1.0, 0.4, 0.1, alpha * 0.9), 3.0)
			draw_line(Vector2(0, 12), Vector2(18, -10), Color(1.0, 0.4, 0.1, alpha * 0.9), 3.0)

		EnemyType.NOB:
			# Massive Hydraulic Power Klaw Shear Crush
			var reach = 36.0
			var start_a = -PI * 0.5 + (swing_t * PI * 0.2)
			draw_arc(Vector2(10, 0), reach, start_a, start_a + PI * 1.0, 14, Color(1.0, 0.15, 0.15, alpha * 0.95), 6.0)
			draw_arc(Vector2(10, 0), reach, start_a + 0.15, start_a + PI * 0.85, 14, Color(1.0, 0.9, 0.3, alpha), 2.5)

# --- 1. GRETCHIN (SCAVENGER / CHOPPER CHAFF) ---
func _draw_gretchin() -> void:
	var skin = Color("#7fa62b")
	var skin_dark = Color("#55701d")
	var leather = Color("#3d2817")
	var scrap_iron = Color("#4a5056")

	# Scrap Sack on back
	draw_circle(Vector2(-6, 2), 6.0, leather)
	draw_rect(Rect2(-8, 0, 5, 4), Color("#5a3d22"))

	# Green Goblin Body & Tattered Rags
	draw_circle(Vector2.ZERO, 8.5, skin)
	draw_rect(Rect2(-5, 2, 10, 7), leather)

	# Long Pointy Bat Ears
	var ear_l = PackedVector2Array([Vector2(-4, -3), Vector2(-16, -10), Vector2(-2, 2)])
	var ear_r = PackedVector2Array([Vector2(4, -3), Vector2(16, -10), Vector2(2, 2)])
	draw_colored_polygon(ear_l, skin_dark)
	draw_colored_polygon(ear_r, skin_dark)

	# Pointy Goblin Nose
	var nose = PackedVector2Array([Vector2(-2, -1), Vector2(0, 7), Vector2(2, -1)])
	draw_colored_polygon(nose, skin_dark)

	# Scrap Pistol in hand
	draw_rect(Rect2(5, 1, 8, 4), scrap_iron)
	draw_rect(Rect2(9, -1, 3, 2), Color("#2a2d30"))

# --- 2. SQUIG (RABID ANKLE-BITER) ---
func _draw_squig() -> void:
	var squig_red = Color("#a61212")
	var squig_dark = Color("#610a0a")
	var tooth_bone = Color("#e8e4c9")
	var maw_dark = Color("#2a0000")

	# Claw feet
	draw_line(Vector2(-5, 6), Vector2(-8, 12), squig_dark, 2.0)
	draw_line(Vector2(5, 6), Vector2(8, 12), squig_dark, 2.0)

	# Meatball body
	draw_circle(Vector2.ZERO, 11.0, squig_red)
	draw_circle(Vector2(-3, -4), 2.5, squig_dark) # Mottled hide spots
	draw_circle(Vector2(4, 3), 2.0, squig_dark)

	# Stubby Horns
	var horn_l = PackedVector2Array([Vector2(-6, -7), Vector2(-10, -15), Vector2(-2, -9)])
	var horn_r = PackedVector2Array([Vector2(6, -7), Vector2(10, -15), Vector2(2, -9)])
	draw_colored_polygon(horn_l, tooth_bone)
	draw_colored_polygon(horn_r, tooth_bone)

	# Chomping maw
	var mouth = PackedVector2Array([Vector2(-8, 1), Vector2(0, 9), Vector2(8, 1), Vector2(0, -1)])
	draw_colored_polygon(mouth, maw_dark)
	
	# Needle teeth
	draw_line(Vector2(-6, 0), Vector2(-5, 4), tooth_bone, 1.8)
	draw_line(Vector2(-1, -1), Vector2(0, 5), tooth_bone, 2.0)
	draw_line(Vector2(4, 0), Vector2(5, 4), tooth_bone, 1.8)
	draw_line(Vector2(-3, 8), Vector2(-3, 4), tooth_bone, 1.8)
	draw_line(Vector2(3, 8), Vector2(3, 4), tooth_bone, 1.8)

# --- 3. ORK BOY (FRONTLINE BRUTE WITH CHOPPA & STIKKBOMBS) ---
func _draw_ork_boy() -> void:
	var ork_green = Color("#2a6316")
	var ork_dark_green = Color("#183d0c")
	var rusted_iron = Color("#4a453f")
	var steel_blade = Color("#c4ccd4")
	var leather = Color("#382313")
	var blood_red = Color("#8a1212")

	# Heavy Hunched Torso & Leather Bandolier
	draw_circle(Vector2(0, 5), 18.0, blood_red)
	draw_circle(Vector2(0, 4), 15.0, leather)
	
	# Stikkbomb strapped to belt
	draw_rect(Rect2(-12, 6, 4, 8), Color("#2d3338"))
	draw_circle(Vector2(-10, 6), 3.0, Color("#4a5259"))

	# Spiked Iron Left Pauldron
	draw_circle(Vector2(-14, 0), 7.0, rusted_iron)
	draw_line(Vector2(-17, -3), Vector2(-22, -8), rusted_iron, 2.5)

	# Muscular Green Ork Head
	draw_circle(Vector2(0, -4), 13.0, ork_green)

	# Heavy Iron Jaw Gobb
	var metal_gobb = PackedVector2Array([Vector2(-10, 2), Vector2(-6, 12), Vector2(6, 12), Vector2(10, 2)])
	draw_colored_polygon(metal_gobb, rusted_iron)
	draw_polyline(metal_gobb, Color("#1a1a1a"), 1.5)

	# Big Bottom Tusks
	draw_line(Vector2(-5, 4), Vector2(-6, -2), Color("#e8e4c9"), 3.0)
	draw_line(Vector2(5, 4), Vector2(6, -2), Color("#e8e4c9"), 3.0)

	# Heavy Serrated Iron Choppa (Right Hand)
	var swing_rot = attack_swing_progress * -0.8
	draw_set_transform(Vector2(12, 4), swing_rot, Vector2.ONE)
	draw_line(Vector2.ZERO, Vector2(14, -20), Color("#1a1a1a"), 4.0) # Handle
	var blade = PackedVector2Array([Vector2(10, -18), Vector2(24, -14), Vector2(18, -34), Vector2(8, -24)])
	draw_colored_polygon(blade, steel_blade)
	draw_polyline(blade, rusted_iron, 1.5)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# --- 4. STORMBOY (ROCKET JUMP RAIDER) ---
func _draw_stormboy() -> void:
	var ork_green = Color("#2a6316")
	var metal_dark = Color("#232629")
	var metal_rust = Color("#6b3a2a")
	var leather = Color("#2e2218")
	var blade_steel = Color("#cbd3db")

	# Twin Rocket Thruster Pack on Back
	draw_rect(Rect2(-10, -22, 9, 16), metal_dark)
	draw_rect(Rect2(1, -22, 9, 16), metal_dark)
	draw_rect(Rect2(-10, -22, 20, 4), metal_rust)

	# Rocket Exhaust Nozzles
	draw_circle(Vector2(-5, -22), 4.0, Color("#111314"))
	draw_circle(Vector2(5, -22), 4.0, Color("#111314"))

	# Body & Aviator Harness
	draw_circle(Vector2(0, 5), 15.0, leather)
	draw_circle(Vector2(0, -3), 11.5, ork_green)

	# Pilot Helmet & Brass Goggles
	draw_arc(Vector2(0, -5), 12.0, PI * 0.9, PI * 2.1, 10, leather, 3.5)
	draw_circle(Vector2(-4, -6), 3.5, Color("#8c6f28"))
	draw_circle(Vector2(4, -6), 3.5, Color("#8c6f28"))

	# Dual Combat Blades
	draw_line(Vector2(-12, 4), Vector2(-18, -14), blade_steel, 3.0)
	draw_line(Vector2(12, 4), Vector2(18, -14), blade_steel, 3.0)

# --- 5. ORK NOB (MEGA-ARMORED WARBOSS BRUTE) ---
func _draw_nob() -> void:
	var ork_dark_green = Color("#1b450c")
	var mega_armor = Color("#32383d")
	var rusted_plate = Color("#591a1a")
	var iron_trim = Color("#7a838a")
	var claw_steel = Color("#d8e0e6")
	var teeth_bone = Color("#f0ede1")

	# Massive Mega-Armor Pauldrons & Trophy Rack
	draw_rect(Rect2(-24, -12, 48, 28), mega_armor)
	draw_rect(Rect2(-24, -12, 48, 28), rusted_plate, false, 2.5)

	# Horned Boss Trophy Spikes on Back
	draw_line(Vector2(-16, -12), Vector2(-22, -28), mega_armor, 3.5)
	draw_line(Vector2(16, -12), Vector2(22, -28), mega_armor, 3.5)
	draw_circle(Vector2(-22, -28), 2.5, Color("#e2d6b5")) # Skull trophy
	draw_circle(Vector2(22, -28), 2.5, Color("#e2d6b5"))

	# Massive Brute Head
	draw_circle(Vector2(0, -6), 16.0, ork_dark_green)

	# Heavy Iron Boss Gobb
	var gobb = PackedVector2Array([Vector2(-14, 2), Vector2(-8, 16), Vector2(8, 16), Vector2(14, 2)])
	draw_colored_polygon(gobb, mega_armor)
	draw_polyline(gobb, iron_trim, 2.0)

	# Massive Tusk Fangs
	draw_line(Vector2(-7, 6), Vector2(-10, -4), teeth_bone, 4.5)
	draw_line(Vector2(7, 6), Vector2(10, -4), teeth_bone, 4.5)

	# Giant Motorized Power Klaw (Right Arm)
	var claw_anim = sin(anim_time * 6.0) * 4.0
	var arm_base = Vector2(18, 6)
	draw_line(arm_base, arm_base + Vector2(10, -14), mega_armor, 7.0)
	draw_circle(arm_base + Vector2(10, -14), 6.0, rusted_plate) # Hydraulic hinge

	# Pincer Blade 1
	var pincer_top = PackedVector2Array([
		arm_base + Vector2(8, -14), arm_base + Vector2(24, -26 - claw_anim), arm_base + Vector2(18, -8)
	])
	draw_colored_polygon(pincer_top, claw_steel)
	
	# Pincer Blade 2
	var pincer_bot = PackedVector2Array([
		arm_base + Vector2(8, -10), arm_base + Vector2(24, -2 + claw_anim), arm_base + Vector2(18, -4)
	])
	draw_colored_polygon(pincer_bot, claw_steel)

# --- NIGHT GLOW & FLAME EFFECTS ---
class EnemyGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		match p.type:
			0: # Gretchin Beady Yellow Eyes
				var eye_glow = 0.7 + sin(p.anim_time * 6.0) * 0.3
				draw_circle(Vector2(-3, -2), 2.2, Color(1.0, 0.90, 0.1, eye_glow))
				draw_circle(Vector2(3, -2), 2.2, Color(1.0, 0.90, 0.1, eye_glow))
				draw_circle(Vector2(-3, -2), 1.0, Color.WHITE)
				draw_circle(Vector2(3, -2), 1.0, Color.WHITE)

			1: # Squig Beady Yellow Eyes
				draw_circle(Vector2(-5, -4), 3.0, Color(1.0, 0.85, 0.0, 0.4))
				draw_circle(Vector2(5, -4), 3.0, Color(1.0, 0.85, 0.0, 0.4))
				draw_circle(Vector2(-5, -4), 1.6 + p.attack_flash * 1.5, Color("#ffcc00"))
				draw_circle(Vector2(5, -4), 1.6 + p.attack_flash * 1.5, Color("#ffcc00"))

			2: # Ork Boy Bloodshot Red Eyes
				var eye_pulse = 0.75 + sin(p.anim_time * 4.0) * 0.25
				draw_circle(Vector2(-5, -6), 4.5, Color(1.0, 0.1, 0.1, 0.35 * eye_pulse))
				draw_circle(Vector2(5, -6), 4.5, Color(1.0, 0.1, 0.1, 0.35 * eye_pulse))
				draw_circle(Vector2(-5, -6), 2.2 + p.attack_flash * 2.0, Color(1.0, 0.15, 0.15))
				draw_circle(Vector2(5, -6), 2.2 + p.attack_flash * 2.0, Color(1.0, 0.15, 0.15))

			3: # Stormboy Rocket Jet Exhaust Flame
				var flame_len = randf_range(12.0, 22.0)
				# Left Thruster Flame
				draw_line(Vector2(-5, -22), Vector2(-5, -22 - flame_len), Color(1.0, 0.45, 0.1, 0.9), 5.0)
				draw_line(Vector2(-5, -22), Vector2(-5, -22 - flame_len * 0.6), Color(1.0, 0.95, 0.2), 2.5)
				# Right Thruster Flame
				draw_line(Vector2(5, -22), Vector2(5, -22 - flame_len), Color(1.0, 0.45, 0.1, 0.9), 5.0)
				draw_line(Vector2(5, -22), Vector2(5, -22 - flame_len * 0.6), Color(1.0, 0.95, 0.2), 2.5)
				
				# Pilot Goggles Glow
				draw_circle(Vector2(-4, -6), 1.8, Color(1.0, 0.75, 0.2, 0.8))
				draw_circle(Vector2(4, -6), 1.8, Color(1.0, 0.75, 0.2, 0.8))

			4: # Ork Nob Menacing Red Bionic Eye & Boss Visor
				draw_circle(Vector2(-7, -8), 6.5, Color(1.0, 0.05, 0.05, 0.45))
				draw_circle(Vector2(-7, -8), 3.0, Color(1.0, 0.15, 0.15))
				draw_circle(Vector2(-7, -8), 1.2, Color.WHITE)
				
				draw_circle(Vector2(7, -8), 4.5, Color(1.0, 0.05, 0.05, 0.35))
				draw_circle(Vector2(7, -8), 2.2, Color(1.0, 0.15, 0.15))
