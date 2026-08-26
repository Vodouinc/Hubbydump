# res://EnemyVisuals.gd
@tool
extends Node2D

enum EnemyType { GRETCHIN, SQUIG, ORK_BOY, STORMBOY, NOB, WARBOSS }
enum BodyFacing { FRONT, BACK, SIDE }

var type: EnemyType = EnemyType.GRETCHIN
var current_facing: BodyFacing = BodyFacing.FRONT
var is_facing_left: bool = false
var anim_time: float = 0.0
var attack_flash: float = 0.0
var attack_swing_progress: float = 0.0

var glow_layer: Node2D = null

# --- GRIMDARK ORK PALETTE ---
const C_OUTLINE     := Color(0.04, 0.05, 0.07)
const C_ORK_GREEN   := Color(0.24, 0.48, 0.14)
const C_ORK_DARK    := Color(0.14, 0.30, 0.08)
const C_GOBLIN_SKIN := Color(0.50, 0.68, 0.18)
const C_SQUIG_RED   := Color(0.72, 0.12, 0.12)
const C_SQUIG_DARK  := Color(0.42, 0.06, 0.06)
const C_RUST_IRON   := Color(0.26, 0.22, 0.20)
const C_STEEL_DARK  := Color(0.12, 0.14, 0.18)
const C_STEEL_MID   := Color(0.24, 0.28, 0.35)
const C_STEEL_LIGHT := Color(0.44, 0.50, 0.58)
const C_STEEL_CHIP  := Color(0.55, 0.60, 0.66)
const C_BRASS       := Color(0.82, 0.62, 0.24)
const C_LEATHER     := Color(0.28, 0.18, 0.10)
const C_WARPAINT    := Color(0.75, 0.14, 0.12)
const C_TEETH_BONE  := Color(0.90, 0.86, 0.74)
const C_EYE_YELLOW  := Color(1.00, 0.85, 0.15)
const C_EYE_RED     := Color(1.00, 0.15, 0.15)
const C_FLAME       := Color(1.00, 0.55, 0.15)

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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match type:
		EnemyType.GRETCHIN: _draw_gretchin()
		EnemyType.SQUIG:    _draw_squig()
		EnemyType.ORK_BOY:  _draw_ork_boy()
		EnemyType.STORMBOY: _draw_stormboy()
		EnemyType.NOB:      _draw_nob()
		EnemyType.WARBOSS:  _draw_warboss()

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
			draw_circle(Vector2(-2.5, -7), 1.6, C_EYE_YELLOW)
			draw_circle(Vector2(2.5, -7), 1.6, C_EYE_YELLOW)
			var gun_recoil = attack_swing_progress * -4.0
			draw_rect(Rect2(4 + gun_recoil, -2, 8, 4), C_RUST_IRON)

		BodyFacing.SIDE:
			draw_circle(Vector2(-5, 0), 6.0, C_LEATHER)
			draw_circle(Vector2(0, -5), 5.5, C_GOBLIN_SKIN)
			draw_colored_polygon(PackedVector2Array([Vector2(-2, -5), Vector2(-14, -12), Vector2(0, -1)]), C_ORK_DARK)
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
				Vector2(-7 + bite_lunge, -1), Vector2(0 + bite_lunge, jaw_open),
				Vector2(7 + bite_lunge, -1), Vector2(0 + bite_lunge, -3)
			])
			draw_colored_polygon(mouth, Color(0.18, 0.02, 0.02))
			draw_line(Vector2(-5 + bite_lunge, -2), Vector2(-4 + bite_lunge, 2), C_TEETH_BONE, 1.8)
			draw_line(Vector2(0 + bite_lunge, -3), Vector2(0 + bite_lunge, 3), C_TEETH_BONE, 2.0)
			draw_line(Vector2(5 + bite_lunge, -2), Vector2(4 + bite_lunge, 2), C_TEETH_BONE, 1.8)

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
			draw_circle(Vector2(0, -6), 9.0, C_ORK_GREEN)

		BodyFacing.FRONT:
			var chest_poly = PackedVector2Array([Vector2(-10, -4), Vector2(10, -4), Vector2(12, 12), Vector2(-12, 12)])
			draw_colored_polygon(chest_poly, C_WARPAINT)
			draw_circle(Vector2(0, -7), 9.5, C_ORK_GREEN)

			var gobb = PackedVector2Array([Vector2(-7, -2), Vector2(-4, 6), Vector2(4, 6), Vector2(7, -2)])
			draw_colored_polygon(gobb, C_RUST_IRON)
			draw_line(Vector2(-4, 0), Vector2(-5, -5), C_TEETH_BONE, 3.0)
			draw_line(Vector2(4, 0), Vector2(5, -5), C_TEETH_BONE, 3.0)
			draw_circle(Vector2(-3.5, -8), 2.0, C_EYE_RED)
			draw_circle(Vector2(3.5, -8), 2.0, C_EYE_RED)
			_draw_ork_choppa()

		BodyFacing.SIDE:
			var side_poly = PackedVector2Array([Vector2(2, -4), Vector2(-10, -4), Vector2(-10, 12), Vector2(6, 12)])
			draw_colored_polygon(side_poly, C_WARPAINT)
			draw_circle(Vector2(0, -7), 8.5, C_ORK_GREEN)
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
		tip - dir * 10.0, tip + perp * 8.0,
		tip + dir * 4.0 + perp * 6.0, tip + dir * 2.0
	])
	draw_colored_polygon(blade, C_STEEL_CHIP)

# ==============================================================================
# 4. STORMBOY
# ==============================================================================
func _draw_stormboy():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 11.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match current_facing:
		BodyFacing.BACK:
			draw_rect(Rect2(-8, -12, 7, 16), C_RUST_IRON)
			draw_rect(Rect2(1, -12, 7, 16), C_RUST_IRON)
			draw_circle(Vector2(-4.5, 4), 3.0, C_STEEL_DARK)
			draw_circle(Vector2(4.5, 4), 3.0, C_STEEL_DARK)
			draw_circle(Vector2(0, -7), 7.5, C_ORK_GREEN)

		BodyFacing.FRONT:
			draw_circle(Vector2(-5, -14), 3.0, C_WARPAINT)
			draw_circle(Vector2(5, -14), 3.0, C_WARPAINT)
			draw_circle(Vector2(0, -7), 8.0, C_ORK_GREEN)
			draw_circle(Vector2(-3.5, -7), 2.8, C_BRASS)
			draw_circle(Vector2(3.5, -7), 2.8, C_BRASS)
			draw_circle(Vector2(-3.5, -7), 1.4, C_EYE_YELLOW)
			draw_circle(Vector2(3.5, -7), 1.4, C_EYE_YELLOW)
			var offset_l = Vector2(-9, 3 - attack_swing_progress * 8.0)
			var offset_r = Vector2(9, 3 - attack_swing_progress * 8.0)
			draw_line(offset_l, offset_l + Vector2(-6, -10), C_STEEL_CHIP, 3.0)
			draw_line(offset_r, offset_r + Vector2(6, -10), C_STEEL_CHIP, 3.0)

		BodyFacing.SIDE:
			draw_circle(Vector2(0, -7), 7.5, C_ORK_GREEN)
			draw_circle(Vector2(3, -7), 2.8, C_BRASS)
			draw_circle(Vector2(3, -7), 1.4, C_EYE_YELLOW)
			draw_line(Vector2(2, 3), Vector2(16, -5), C_STEEL_CHIP, 3.0)

# ==============================================================================
# 5. NOB
# ==============================================================================
func _draw_nob():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 12), 16.0, Color(0.02, 0.02, 0.04, 0.55))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	draw_line(Vector2(-14, -8), Vector2(-20, -24), C_RUST_IRON, 3.5)
	draw_line(Vector2(14, -8), Vector2(20, -24), C_RUST_IRON, 3.5)
	draw_circle(Vector2(-20, -24), 3.0, C_TEETH_BONE)
	draw_circle(Vector2(20, -24), 3.0, C_TEETH_BONE)

	match current_facing:
		BodyFacing.BACK:
			draw_rect(Rect2(-16, -10, 32, 22), C_RUST_IRON)
			draw_circle(Vector2(0, -8), 12.0, C_ORK_DARK)

		BodyFacing.FRONT:
			draw_rect(Rect2(-15, -8, 30, 22), C_RUST_IRON)
			draw_circle(Vector2(0, -9), 12.0, C_ORK_GREEN)
			draw_line(Vector2(-5, 0), Vector2(-7, -7), C_TEETH_BONE, 4.0)
			draw_line(Vector2(5, 0), Vector2(7, -7), C_TEETH_BONE, 4.0)
			draw_circle(Vector2(-4.5, -10), 3.5, Color(1.0, 0.1, 0.1))
			draw_circle(Vector2(-4.5, -10), 1.5, Color.WHITE)
			draw_circle(Vector2(4.5, -10), 2.2, C_EYE_RED)
			_draw_power_klaw(1.0)

		BodyFacing.SIDE:
			draw_rect(Rect2(-12, -8, 24, 22), C_RUST_IRON)
			draw_circle(Vector2(0, -9), 11.0, C_ORK_GREEN)
			draw_circle(Vector2(4.5, -10), 3.0, Color(1.0, 0.1, 0.1))
			_draw_power_klaw(1.0)

# ==============================================================================
# 6. MEGA-ARMORED WARBOSS (CLIMACTIC CRUSADE BOSS)
# ==============================================================================
func _draw_warboss():
	# Huge Ground Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 18), 24.0, Color(0.01, 0.01, 0.03, 0.65))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	# 1. Back Trophy Pole (Iron Boss-Pole with 3 Impaled Skulls & WAAAGH! Banner)
	draw_line(Vector2(0, -10), Vector2(0, -48), C_STEEL_DARK, 5.5)
	draw_line(Vector2(-18, -40), Vector2(18, -40), C_STEEL_DARK, 4.0)
	
	# Impaled Skulls
	for sx in [-16.0, 0.0, 16.0]:
		draw_circle(Vector2(sx, -42), 4.2, C_TEETH_BONE)
		draw_circle(Vector2(sx, -42), 4.2, C_OUTLINE, false, 1.2)
		draw_line(Vector2(sx, -36), Vector2(sx, -48), C_RUST_IRON, 2.0) # Spikes through skulls

	# Hanging Red Checkered Battle Banner
	var banner = PackedVector2Array([
		Vector2(-12, -38), Vector2(12, -38),
		Vector2(10, -18), Vector2(0, -12), Vector2(-10, -18)
	])
	draw_colored_polygon(banner, C_WARPAINT)
	draw_polyline(banner, C_OUTLINE, 1.5)

	# 2. Colossal Mega-Armor Torso with Checker Plate & Hydraulics
	var torso = PackedVector2Array([
		Vector2(-22, -12), Vector2(22, -12),
		Vector2(26, 16), Vector2(-26, 16)
	])
	draw_colored_polygon(torso, C_STEEL_DARK)
	draw_rect(Rect2(-20, -10, 40, 24), C_WARPAINT, false, 3.0)

	# Heavy Riveted Iron Shoulder Pauldrons
	draw_rect(Rect2(-32, -22, 14, 18), C_RUST_IRON)
	draw_rect(Rect2(18, -22, 14, 18), C_RUST_IRON)
	draw_line(Vector2(-32, -22), Vector2(-38, -32), C_STEEL_CHIP, 4.0) # Horn spike
	draw_line(Vector2(32, -22), Vector2(38, -32), C_STEEL_CHIP, 4.0)   # Horn spike

	# 3. Monstrous Warboss Head & Heavy Iron Gob (Jawplate)
	draw_circle(Vector2(0, -14), 16.0, C_ORK_GREEN)
	draw_circle(Vector2(0, -14), 16.0, C_OUTLINE, false, 1.8)

	var iron_gob = PackedVector2Array([
		Vector2(-14, -6), Vector2(-9, 10), Vector2(9, 10), Vector2(14, -6)
	])
	draw_colored_polygon(iron_gob, C_RUST_IRON)
	draw_polyline(iron_gob, C_OUTLINE, 2.0)

	# Massive 8-inch Fangs
	draw_line(Vector2(-8, -2), Vector2(-11, -12), C_TEETH_BONE, 5.5)
	draw_line(Vector2(8, -2), Vector2(11, -12), C_TEETH_BONE, 5.5)
	draw_line(Vector2(-3, 2), Vector2(-4, -6), C_TEETH_BONE, 4.0)
	draw_line(Vector2(3, 2), Vector2(4, -6), C_TEETH_BONE, 4.0)

	# Bionic Ruby Targeter Eye (Right) & Bloodshot Sclera (Left)
	draw_circle(Vector2(-6, -16), 4.5, Color(1.0, 0.1, 0.1))
	draw_circle(Vector2(-6, -16), 2.0, Color.WHITE)
	draw_circle(Vector2(6, -16), 3.0, C_EYE_RED)

	# 4. Weapons: Twin-Linked Custom Mega-Shoota (Left Hand)
	draw_rect(Rect2(-30, 2, 10, 18), C_STEEL_DARK)
	draw_line(Vector2(-28, 20), Vector2(-28, 28), C_STEEL_CHIP, 4.0)
	draw_line(Vector2(-23, 20), Vector2(-23, 28), C_STEEL_CHIP, 4.0)
	draw_circle(Vector2(-28, 28), 2.0, C_BRASS)
	draw_circle(Vector2(-23, 28), 2.0, C_BRASS)

	# 5. Colossal Mega-Power Klaw (Right Hand - 1.45x Scale)
	_draw_power_klaw(1.45)

func _draw_power_klaw(scale_mult: float):
	var swing = attack_swing_progress
	var arm_root = Vector2(18 * scale_mult, 2)
	var arm_extend = arm_root + Vector2(10 + swing * 12.0, -8 - swing * 6.0) * scale_mult

	draw_line(arm_root, arm_extend, C_RUST_IRON, 8.0 * scale_mult)
	draw_circle(arm_extend, 6.0 * scale_mult, C_WARPAINT)

	var chomp_anim = sin(anim_time * 6.0) * 4.0
	var pincer_gap = (8.0 + chomp_anim - (swing * 10.0)) * scale_mult

	# Top Serrated Pincer
	var pincer_top = PackedVector2Array([
		arm_extend + Vector2(2, -4) * scale_mult,
		arm_extend + Vector2(24 * scale_mult, -18 * scale_mult - pincer_gap),
		arm_extend + Vector2(14 * scale_mult, 0)
	])
	draw_colored_polygon(pincer_top, C_STEEL_CHIP)
	var cl_t = pincer_top.duplicate(); cl_t.append(pincer_top[0])
	draw_polyline(cl_t, C_OUTLINE, 1.6)

	# Bottom Serrated Pincer
	var pincer_bot = PackedVector2Array([
		arm_extend + Vector2(2, 4) * scale_mult,
		arm_extend + Vector2(24 * scale_mult, 8 * scale_mult + pincer_gap),
		arm_extend + Vector2(14 * scale_mult, 0)
	])
	draw_colored_polygon(pincer_bot, C_STEEL_CHIP)
	var cl_b = pincer_bot.duplicate(); cl_b.append(pincer_bot[0])
	draw_polyline(cl_b, C_OUTLINE, 1.6)

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
			3: # Stormboy Rocket Jet Exhaust Flames
				var flame_l = randf_range(8.0, 18.0)
				if p.current_facing == BodyFacing.SIDE:
					var nozzle = Vector2(-11, 4)
					var flame_end = nozzle + Vector2(-flame_l * 0.7, flame_l * 0.7)
					draw_line(nozzle, flame_end, Color(1.0, 0.45, 0.1, 0.9), 4.5)
					draw_line(nozzle, nozzle + (flame_end - nozzle) * 0.6, Color(1.0, 0.95, 0.2), 2.0)
				else:
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
			5: # Warboss Giant Ruby Optical Scanner & Boss Aura
				if p.current_facing != BodyFacing.BACK:
					var pulse = 0.75 + sin(Time.get_ticks_msec() * 0.008) * 0.25
					draw_circle(Vector2(-6, -16), 5.5 * pulse, Color(1.0, 0.1, 0.1, 0.95))
					draw_circle(Vector2(-6, -16), 2.2, Color.WHITE)
					# WAAAGH! Warboss Presence Ring
					draw_arc(Vector2.ZERO, 32.0, 0, TAU, 24, Color(1.0, 0.2, 0.1, 0.4 * pulse), 2.0)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
