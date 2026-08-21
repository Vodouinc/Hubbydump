@tool
extends Node2D

enum EnemyType { GRETCHIN, SQUIG, ORK_BOY, STORMBOY, NOB }
enum BodyFacing { FRONT, BACK, SIDE }

var type: EnemyType = EnemyType.GRETCHIN
var current_facing: BodyFacing = BodyFacing.FRONT
var is_facing_left: bool = false
var anim_time: float = 0.0
var attack_flash: float = 0.0
var attack_swing_progress: float = 0.0

var glow_layer: Node2D = null

# --- GRIMDARK ORK PALETTE ---
const C_OUTLINE     := Color(0.04, 0.05, 0.07) # Hard 1.4px cel-outline
const C_ORK_GREEN   := Color(0.24, 0.48, 0.14) # Heavy Ork skin
const C_ORK_DARK    := Color(0.14, 0.30, 0.08) # Shaded skin
const C_GOBLIN_SKIN := Color(0.50, 0.68, 0.18) # Gretchin yellowish-green
const C_SQUIG_RED   := Color(0.72, 0.12, 0.12) # Squig fleshy red
const C_SQUIG_DARK  := Color(0.42, 0.06, 0.06) # Squig hide shadow
const C_RUST_IRON   := Color(0.26, 0.22, 0.20) # Heavy rusted iron
const C_STEEL_DARK  := Color(0.12, 0.14, 0.18) # Heavy cast iron & machinery
const C_STEEL_MID   := Color(0.24, 0.28, 0.35) # Standard steel
const C_STEEL_LIGHT := Color(0.44, 0.50, 0.58) # Bevel highlight steel
const C_STEEL_CHIP  := Color(0.55, 0.60, 0.66) # Chipped blade steel
const C_BRASS       := Color(0.82, 0.62, 0.24) # Goggles & ammo brass
const C_LEATHER     := Color(0.28, 0.18, 0.10) # Cracked leather harness
const C_WARPAINT    := Color(0.75, 0.14, 0.12) # Blood red warpaint
const C_TEETH_BONE  := Color(0.90, 0.86, 0.74) # Ivory tusks and skulls
const C_EYE_YELLOW  := Color(1.00, 0.85, 0.15) # Beady Gretchin/Squig eyes
const C_EYE_RED     := Color(1.00, 0.15, 0.15) # Bloodshot Ork eyes
const C_FLAME       := Color(1.00, 0.55, 0.15) # Rocket thruster exhaust

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

func update_facing(move_vector: Vector2) -> void:
	if move_vector.length_squared() > 10.0:
		if move_vector.x < -0.15:
			is_facing_left = true
		elif move_vector.x > 0.15:
			is_facing_left = false

		var deg = rad_to_deg(move_vector.angle())
		if deg < 0: deg += 360.0

		if deg >= 40.0 and deg <= 140.0:
			current_facing = BodyFacing.FRONT
		elif deg >= 220.0 and deg <= 320.0:
			current_facing = BodyFacing.BACK
		else:
			current_facing = BodyFacing.SIDE

		queue_redraw()
		if is_instance_valid(glow_layer):
			glow_layer.queue_redraw()

func _process(delta: float) -> void:
	anim_time += delta
	var movement: float = 0.0
	var parent_node = get_parent()
	
	if parent_node and "velocity" in parent_node:
		var vel: Vector2 = parent_node.velocity
		movement = vel.length()
		if vel.length_squared() > 100.0:
			update_facing(vel)
	
	# Running bobbing
	var bob_scale = 0.55 + minf(movement / 250.0, 1.0) * 1.3
	position.y = sin(anim_time * (5.0 + movement * 0.015)) * bob_scale
	
	if attack_flash > 0.0:
		attack_flash = maxf(0.0, attack_flash - delta * 4.5)

	if attack_swing_progress > 0.0:
		attack_swing_progress = maxf(0.0, attack_swing_progress - delta * 4.0)
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
	# Horizontal Flip based on movement direction
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match type:
		EnemyType.GRETCHIN: _draw_gretchin()
		EnemyType.SQUIG:    _draw_squig()
		EnemyType.ORK_BOY:  _draw_ork_boy()
		EnemyType.STORMBOY: _draw_stormboy()
		EnemyType.NOB:      _draw_nob()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 1. GRETCHIN
# ==============================================================================
func _draw_gretchin():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 8), 7.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match current_facing:
		BodyFacing.BACK:
			draw_circle(Vector2(0, -2), 7.0, C_LEATHER)
			draw_circle(Vector2(0, -2), 7.0, C_OUTLINE, false, 1.2)
			draw_line(Vector2(-5, -2), Vector2(5, -2), Color(0.4, 0.3, 0.2), 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(-4, -6), Vector2(-15, -12), Vector2(-2, -2)]), C_ORK_DARK)
			draw_colored_polygon(PackedVector2Array([Vector2(4, -6), Vector2(15, -12), Vector2(2, -2)]), C_ORK_DARK)

		BodyFacing.FRONT:
			draw_circle(Vector2(0, 0), 7.0, C_LEATHER)
			draw_circle(Vector2(0, 0), 7.0, C_OUTLINE, false, 1.2)
			draw_circle(Vector2(0, -6), 6.0, C_GOBLIN_SKIN)
			draw_colored_polygon(PackedVector2Array([Vector2(-4, -6), Vector2(-16, -13), Vector2(-2, -2)]), C_ORK_DARK)
			draw_colored_polygon(PackedVector2Array([Vector2(4, -6), Vector2(16, -13), Vector2(2, -2)]), C_ORK_DARK)
			draw_colored_polygon(PackedVector2Array([Vector2(-2, -6), Vector2(0, 0), Vector2(2, -6)]), C_ORK_DARK)
			draw_circle(Vector2(-2.5, -7), 1.6, C_EYE_YELLOW)
			draw_circle(Vector2(2.5, -7), 1.6, C_EYE_YELLOW)

			var gun_recoil = attack_swing_progress * -4.0
			draw_rect(Rect2(4 + gun_recoil, -2, 8, 4), C_RUST_IRON)
			draw_rect(Rect2(10 + gun_recoil, -3, 3, 6), C_STEEL_CHIP)

		BodyFacing.SIDE:
			draw_circle(Vector2(-5, 0), 6.0, C_LEATHER)
			draw_circle(Vector2(0, -5), 5.5, C_GOBLIN_SKIN)
			draw_colored_polygon(PackedVector2Array([Vector2(-2, -5), Vector2(-14, -12), Vector2(0, -1)]), C_ORK_DARK)
			draw_colored_polygon(PackedVector2Array([Vector2(2, -6), Vector2(8, -4), Vector2(2, -2)]), C_ORK_DARK)
			draw_circle(Vector2(2.5, -6), 1.8, C_EYE_YELLOW)
			var recoil = attack_swing_progress * -5.0
			draw_rect(Rect2(2 + recoil, 0, 10, 4), C_RUST_IRON)

# ==============================================================================
# 2. SQUIG
# ==============================================================================
func _draw_squig():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 8), 9.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	var bite_lunge = sin(attack_swing_progress * PI) * 8.0

	match current_facing:
		BodyFacing.BACK:
			draw_circle(Vector2(0, 0), 10.5, C_SQUIG_RED)
			draw_circle(Vector2(0, 0), 10.5, C_OUTLINE, false, 1.4)
			draw_circle(Vector2(-4, -3), 2.5, C_SQUIG_DARK)
			draw_circle(Vector2(3, 4), 2.0, C_SQUIG_DARK)
			draw_colored_polygon(PackedVector2Array([Vector2(-5, -6), Vector2(-9, -15), Vector2(-1, -8)]), C_TEETH_BONE)
			draw_colored_polygon(PackedVector2Array([Vector2(5, -6), Vector2(9, -15), Vector2(1, -8)]), C_TEETH_BONE)

		BodyFacing.FRONT, BodyFacing.SIDE:
			draw_line(Vector2(-5, 6), Vector2(-8, 12), C_SQUIG_DARK, 2.5)
			draw_line(Vector2(5, 6), Vector2(8, 12), C_SQUIG_DARK, 2.5)
			draw_circle(Vector2(bite_lunge * 0.5, 0), 10.5, C_SQUIG_RED)
			draw_circle(Vector2(bite_lunge * 0.5, 0), 10.5, C_OUTLINE, false, 1.4)

			draw_colored_polygon(PackedVector2Array([Vector2(-5, -6), Vector2(-9, -15), Vector2(-1, -8)]), C_TEETH_BONE)
			draw_colored_polygon(PackedVector2Array([Vector2(5, -6), Vector2(9, -15), Vector2(1, -8)]), C_TEETH_BONE)

			draw_circle(Vector2(-3.5 + bite_lunge * 0.5, -4), 2.2, C_EYE_YELLOW)
			draw_circle(Vector2(3.5 + bite_lunge * 0.5, -4), 2.2, C_EYE_YELLOW)

			var jaw_open = 4.0 + (attack_swing_progress * 8.0)
			var mouth = PackedVector2Array([
				Vector2(-7 + bite_lunge, -1),
				Vector2(0 + bite_lunge, jaw_open),
				Vector2(7 + bite_lunge, -1),
				Vector2(0 + bite_lunge, -3)
			])
			draw_colored_polygon(mouth, Color(0.18, 0.02, 0.02))
			draw_polyline(mouth, C_OUTLINE, 1.2)

			draw_line(Vector2(-5 + bite_lunge, -2), Vector2(-4 + bite_lunge, 2), C_TEETH_BONE, 1.8)
			draw_line(Vector2(0 + bite_lunge, -3), Vector2(0 + bite_lunge, 3), C_TEETH_BONE, 2.0)
			draw_line(Vector2(5 + bite_lunge, -2), Vector2(4 + bite_lunge, 2), C_TEETH_BONE, 1.8)
			draw_line(Vector2(-2 + bite_lunge, jaw_open - 1), Vector2(-2 + bite_lunge, jaw_open - 4), C_TEETH_BONE, 1.8)
			draw_line(Vector2(2 + bite_lunge, jaw_open - 1), Vector2(2 + bite_lunge, jaw_open - 4), C_TEETH_BONE, 1.8)

# ==============================================================================
# 3. ORK BOY
# ==============================================================================
func _draw_ork_boy():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 13.0, Color(0.02, 0.02, 0.04, 0.50))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match current_facing:
		BodyFacing.BACK:
			var back_poly = PackedVector2Array([Vector2(-11, -4), Vector2(11, -4), Vector2(13, 12), Vector2(-13, 12)])
			draw_colored_polygon(back_poly, C_ORK_GREEN)
			var cl_b = back_poly.duplicate(); cl_b.append(back_poly[0])
			draw_polyline(cl_b, C_OUTLINE, 1.5)
			draw_circle(Vector2(-12, -4), 5.5, C_RUST_IRON)
			draw_line(Vector2(-15, -7), Vector2(-20, -12), C_STEEL_CHIP, 2.2)
			draw_rect(Rect2(2, 6, 4, 8), C_RUST_IRON)
			draw_circle(Vector2(4, 6), 3.0, C_STEEL_DARK)
			draw_circle(Vector2(0, -6), 9.0, C_ORK_GREEN)
			draw_circle(Vector2(0, -6), 9.0, C_OUTLINE, false, 1.2)

		BodyFacing.FRONT:
			var chest_poly = PackedVector2Array([Vector2(-10, -4), Vector2(10, -4), Vector2(12, 12), Vector2(-12, 12)])
			draw_colored_polygon(chest_poly, C_WARPAINT)
			var cl_c = chest_poly.duplicate(); cl_c.append(chest_poly[0])
			draw_polyline(cl_c, C_OUTLINE, 1.5)

			draw_circle(Vector2(-13, -2), 6.0, C_RUST_IRON)
			draw_line(Vector2(-16, -5), Vector2(-21, -10), C_STEEL_CHIP, 2.5)

			draw_circle(Vector2(0, -7), 9.5, C_ORK_GREEN)
			draw_circle(Vector2(0, -7), 9.5, C_OUTLINE, false, 1.2)

			var gobb = PackedVector2Array([Vector2(-7, -2), Vector2(-4, 6), Vector2(4, 6), Vector2(7, -2)])
			draw_colored_polygon(gobb, C_RUST_IRON)
			draw_polyline(gobb, C_OUTLINE, 1.4)

			draw_line(Vector2(-4, 0), Vector2(-5, -5), C_TEETH_BONE, 3.0)
			draw_line(Vector2(4, 0), Vector2(5, -5), C_TEETH_BONE, 3.0)
			draw_circle(Vector2(-3.5, -8), 2.0, C_EYE_RED)
			draw_circle(Vector2(3.5, -8), 2.0, C_EYE_RED)

			_draw_ork_choppa()

		BodyFacing.SIDE:
			var side_poly = PackedVector2Array([Vector2(2, -4), Vector2(-10, -4), Vector2(-10, 12), Vector2(6, 12)])
			draw_colored_polygon(side_poly, C_WARPAINT)
			var cl_s = side_poly.duplicate(); cl_s.append(side_poly[0])
			draw_polyline(cl_s, C_OUTLINE, 1.5)

			draw_circle(Vector2(0, -7), 8.5, C_ORK_GREEN)
			var side_gobb = PackedVector2Array([Vector2(2, -4), Vector2(9, -2), Vector2(6, 4), Vector2(0, 4)])
			draw_colored_polygon(side_gobb, C_RUST_IRON)
			draw_line(Vector2(4, 0), Vector2(6, -5), C_TEETH_BONE, 3.0)
			draw_circle(Vector2(3.5, -8), 2.2, C_EYE_RED)

			_draw_ork_choppa()

func _draw_ork_choppa():
	var swing = attack_swing_progress
	var arm_root = Vector2(8, 0)
	var swing_angle = -PI * 0.4 + (pow(1.0 - swing, 2.0) * PI * 0.85)

	var dir = Vector2.RIGHT.rotated(swing_angle)
	var tip = arm_root + dir * 20.0

	draw_line(arm_root, tip, Color(0.1, 0.1, 0.1), 3.5)
	var perp = dir.orthogonal()
	var blade = PackedVector2Array([
		tip - dir * 10.0,
		tip + perp * 8.0,
		tip + dir * 4.0 + perp * 6.0,
		tip + dir * 2.0
	])
	draw_colored_polygon(blade, C_STEEL_CHIP)
	var cl = blade.duplicate(); cl.append(blade[0])
	draw_polyline(cl, C_RUST_IRON, 1.4)

	if swing > 0.1 and swing < 0.9:
		draw_arc(arm_root, 22.0, swing_angle - 0.5, swing_angle, 8, Color(C_WARPAINT.r, C_WARPAINT.g, C_WARPAINT.b, 0.6), 4.0)

# ==============================================================================
# 4. STORMBOY (ROCKET JUMP RAIDER WITH REAR DOWNWARD THRUSTERS)
# ==============================================================================
func _draw_stormboy():
	# Ground Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 11.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match current_facing:
		BodyFacing.BACK:
			# Massive Twin Rocket Canister strapped directly to the back (Shoulders down to waist)
			draw_rect(Rect2(-8, -12, 7, 16), C_RUST_IRON)
			draw_rect(Rect2(1, -12, 7, 16), C_RUST_IRON)
			draw_rect(Rect2(-8, -12, 16, 4), C_WARPAINT) # Red nose band
			
			# Downward Exhaust Nozzles at Bottom (Y = 4)
			draw_circle(Vector2(-4.5, 4), 3.0, C_STEEL_DARK)
			draw_circle(Vector2(4.5, 4), 3.0, C_STEEL_DARK)

			# Body & Head
			var back_p = PackedVector2Array([Vector2(-7, -4), Vector2(7, -4), Vector2(9, 10), Vector2(-9, 10)])
			draw_colored_polygon(back_p, C_LEATHER)
			draw_circle(Vector2(0, -7), 7.5, C_ORK_GREEN)

		BodyFacing.FRONT:
			# Rocket Pack Nosecones peeking over shoulders
			draw_rect(Rect2(-8, -14, 6, 6), C_RUST_IRON)
			draw_rect(Rect2(2, -14, 6, 6), C_RUST_IRON)
			draw_circle(Vector2(-5, -14), 3.0, C_WARPAINT)
			draw_circle(Vector2(5, -14), 3.0, C_WARPAINT)

			# Torso & Harness
			var front_p = PackedVector2Array([Vector2(-8, -4), Vector2(8, -4), Vector2(10, 11), Vector2(-10, 11)])
			draw_colored_polygon(front_p, C_LEATHER)
			var cl_f = front_p.duplicate(); cl_f.append(front_p[0])
			draw_polyline(cl_f, C_OUTLINE, 1.4)

			# Head & Aviator Helmet with Goggles
			draw_circle(Vector2(0, -7), 8.0, C_ORK_GREEN)
			draw_arc(Vector2(0, -9), 8.0, PI * 0.9, PI * 2.1, 10, C_LEATHER, 3.0)
			draw_circle(Vector2(-3.5, -7), 2.8, C_BRASS)
			draw_circle(Vector2(3.5, -7), 2.8, C_BRASS)
			draw_circle(Vector2(-3.5, -7), 1.4, C_EYE_YELLOW)
			draw_circle(Vector2(3.5, -7), 1.4, C_EYE_YELLOW)

			# Dual Combat Blades
			var swing = attack_swing_progress
			var offset_l = Vector2(-9, 3 - swing * 8.0)
			var offset_r = Vector2(9, 3 - swing * 8.0)
			draw_line(offset_l, offset_l + Vector2(-6, -10), C_STEEL_CHIP, 3.0)
			draw_line(offset_r, offset_r + Vector2(6, -10), C_STEEL_CHIP, 3.0)

		BodyFacing.SIDE:
			# Angled Rocket Pack on Back (Shooting back/down)
			var pack_pts = PackedVector2Array([
				Vector2(-12, -14), Vector2(-4, -10),
				Vector2(-7, 6), Vector2(-15, 2)
			])
			draw_colored_polygon(pack_pts, C_RUST_IRON)
			draw_circle(Vector2(-11, 4), 3.0, C_STEEL_DARK) # Downward nozzle

			# Leaning Forward Torso
			var side_p = PackedVector2Array([Vector2(3, -4), Vector2(-7, -4), Vector2(-5, 11), Vector2(4, 8)])
			draw_colored_polygon(side_p, C_LEATHER)
			draw_circle(Vector2(0, -7), 7.5, C_ORK_GREEN)
			draw_circle(Vector2(3, -7), 2.8, C_BRASS)
			draw_circle(Vector2(3, -7), 1.4, C_EYE_YELLOW)

			# Forward Blade
			draw_line(Vector2(2, 3), Vector2(16, -5), C_STEEL_CHIP, 3.0)

# ==============================================================================
# 5. ORK NOB (MEGA-ARMORED WARBOSS)
# ==============================================================================
func _draw_nob():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 12), 16.0, Color(0.02, 0.02, 0.04, 0.55))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	# Horned Trophy Spikes (Impaled Human/Space Marine Skulls)
	draw_line(Vector2(-14, -8), Vector2(-20, -24), C_RUST_IRON, 3.5)
	draw_line(Vector2(14, -8), Vector2(20, -24), C_RUST_IRON, 3.5)
	draw_circle(Vector2(-20, -24), 3.0, C_TEETH_BONE)
	draw_circle(Vector2(20, -24), 3.0, C_TEETH_BONE)

	match current_facing:
		BodyFacing.BACK:
			draw_rect(Rect2(-16, -10, 32, 22), C_RUST_IRON)
			draw_rect(Rect2(-16, -10, 32, 22), C_WARPAINT, false, 2.5)
			draw_circle(Vector2(0, -8), 12.0, C_ORK_DARK)

		BodyFacing.FRONT:
			draw_rect(Rect2(-15, -8, 30, 22), C_RUST_IRON)
			draw_rect(Rect2(-15, -8, 30, 22), C_WARPAINT, false, 2.5)
			for i in range(4):
				var tx = -12.0 + (i * 7.0)
				draw_line(Vector2(tx, 4), Vector2(tx + 3.5, 9), C_TEETH_BONE, 2.0)

			draw_circle(Vector2(0, -9), 12.0, C_ORK_GREEN)
			draw_circle(Vector2(0, -9), 12.0, C_OUTLINE, false, 1.4)

			var gobb = PackedVector2Array([Vector2(-9, -3), Vector2(-6, 8), Vector2(6, 8), Vector2(9, -3)])
			draw_colored_polygon(gobb, C_RUST_IRON)
			draw_polyline(gobb, C_OUTLINE, 1.5)

			draw_line(Vector2(-5, 0), Vector2(-7, -7), C_TEETH_BONE, 4.0)
			draw_line(Vector2(5, 0), Vector2(7, -7), C_TEETH_BONE, 4.0)

			draw_circle(Vector2(-4.5, -10), 3.5, Color(1.0, 0.1, 0.1))
			draw_circle(Vector2(-4.5, -10), 1.5, Color.WHITE)
			draw_circle(Vector2(4.5, -10), 2.2, C_EYE_RED)

			_draw_nob_power_klaw()

		BodyFacing.SIDE:
			draw_rect(Rect2(-12, -8, 24, 22), C_RUST_IRON)
			draw_circle(Vector2(0, -9), 11.0, C_ORK_GREEN)
			var side_gobb = PackedVector2Array([Vector2(3, -4), Vector2(11, -2), Vector2(8, 7), Vector2(2, 7)])
			draw_colored_polygon(side_gobb, C_RUST_IRON)
			draw_line(Vector2(6, 0), Vector2(8, -7), C_TEETH_BONE, 4.0)
			draw_circle(Vector2(4.5, -10), 3.0, Color(1.0, 0.1, 0.1))

			_draw_nob_power_klaw()

func _draw_nob_power_klaw():
	var swing = attack_swing_progress
	var arm_root = Vector2(14, 2)
	var arm_extend = arm_root + Vector2(8 + swing * 8.0, -8 - swing * 4.0)

	draw_line(arm_root, arm_extend, C_RUST_IRON, 7.0)
	draw_circle(arm_extend, 5.0, C_WARPAINT)

	var chomp_anim = sin(anim_time * 5.0) * 3.0
	var pincer_gap = 6.0 + chomp_anim - (swing * 8.0)

	# Top Pincer
	var pincer_top = PackedVector2Array([
		arm_extend + Vector2(2, -4),
		arm_extend + Vector2(18, -14 - pincer_gap),
		arm_extend + Vector2(12, 0)
	])
	draw_colored_polygon(pincer_top, C_STEEL_CHIP)
	var cl_t = pincer_top.duplicate(); cl_t.append(pincer_top[0])
	draw_polyline(cl_t, C_OUTLINE, 1.4)

	# Bottom Pincer
	var pincer_bot = PackedVector2Array([
		arm_extend + Vector2(2, 4),
		arm_extend + Vector2(18, 6 + pincer_gap),
		arm_extend + Vector2(12, 0)
	])
	draw_colored_polygon(pincer_bot, C_STEEL_CHIP)
	var cl_b = pincer_bot.duplicate(); cl_b.append(pincer_bot[0])
	draw_polyline(cl_b, C_OUTLINE, 1.4)

# ==============================================================================
# UNSHADED NIGHT GLOW & DOWNWARD JET EXHAUST FLAMES
# ==============================================================================
class EnemyGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		var flip = -1.0 if p.is_facing_left else 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(flip, 1.0))

		match p.type:
			0: # Gretchin Beady Eyes
				if p.current_facing != BodyFacing.BACK:
					var pos = Vector2(2.5, -6) if p.current_facing == BodyFacing.SIDE else Vector2(0, -7)
					draw_circle(pos, 2.0, Color(1.0, 0.85, 0.15, 0.9))
			1: # Squig Eyes
				if p.current_facing != BodyFacing.BACK:
					draw_circle(Vector2(0, -4), 2.5, Color(1.0, 0.85, 0.15, 0.9))
			2: # Ork Boy Bloodshot Eyes
				if p.current_facing != BodyFacing.BACK:
					draw_circle(Vector2(0, -8), 3.0, Color(1.0, 0.15, 0.15, 0.85))
			3: # Stormboy Downward/Rear Rocket Jet Exhaust Flames
				var flame_l = randf_range(8.0, 18.0)
				if p.current_facing == BodyFacing.SIDE:
					# Diagonal rear thrust
					var nozzle = Vector2(-11, 4)
					var flame_end = nozzle + Vector2(-flame_l * 0.7, flame_l * 0.7)
					draw_line(nozzle, flame_end, Color(1.0, 0.45, 0.1, 0.9), 4.5)
					draw_line(nozzle, nozzle + (flame_end - nozzle) * 0.6, Color(1.0, 0.95, 0.2), 2.0)
				else:
					# Downward rear thrust
					var noz_l = Vector2(-4.5, 4)
					var noz_r = Vector2(4.5, 4)
					draw_line(noz_l, noz_l + Vector2(0, flame_l), Color(1.0, 0.45, 0.1, 0.9), 4.0)
					draw_line(noz_l, noz_l + Vector2(0, flame_l * 0.6), Color(1.0, 0.95, 0.2), 2.0)
					draw_line(noz_r, noz_r + Vector2(0, flame_l), Color(1.0, 0.45, 0.1, 0.9), 4.0)
					draw_line(noz_r, noz_r + Vector2(0, flame_l * 0.6), Color(1.0, 0.95, 0.2), 2.0)
			4: # Ork Nob Bionic Eye
				if p.current_facing != BodyFacing.BACK:
					draw_circle(Vector2(-4.5, -10), 4.0, Color(1.0, 0.1, 0.1, 0.9))
					draw_circle(Vector2(-4.5, -10), 1.8, Color.WHITE)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
