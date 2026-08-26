# res://NecronVisuals.gd
@tool
extends Node2D
class_name NecronVisuals

enum NecronType { SCARAB = 0, WARRIOR = 1, CRYPTEK_BOSS = 2 }
enum BodyFacing { FRONT, BACK, SIDE }

@export var type: NecronType = NecronType.SCARAB
var current_facing: BodyFacing = BodyFacing.FRONT
var is_facing_left: bool = false
var anim_time: float = 0.0
var attack_flash: float = 0.0
var is_reanimating: bool = false
var glow_layer: Node2D = null

# --- NECRON DYNASTY PALETTE ---
const C_OUTLINE      := Color(0.02, 0.03, 0.04)
const C_BLACKSTONE   := Color(0.07, 0.09, 0.11)
const C_LIVING_METAL := Color(0.28, 0.32, 0.36)
const C_NECRON_DARK  := Color(0.16, 0.18, 0.22)
const C_NECRON_GOLD  := Color(0.78, 0.65, 0.25)
const C_GAUSS_GREEN  := Color(0.20, 1.00, 0.45)
const C_GAUSS_DARK   := Color(0.08, 0.55, 0.22)
const C_GAUSS_CORE   := Color(0.90, 1.00, 0.92)

func _ready() -> void:
	_setup_glow_layer()
	queue_redraw()

func _setup_glow_layer():
	if not has_node("NecronGlowOverlay"):
		glow_layer = NecronGlowRenderer.new()
		glow_layer.name = "NecronGlowOverlay"
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		glow_layer.material = mat
		add_child(glow_layer)
	else:
		glow_layer = get_node("NecronGlowOverlay")

func update_facing(move_vector: Vector2) -> void:
	if move_vector.length_squared() > 10.0:
		if move_vector.x < -0.15: is_facing_left = true
		elif move_vector.x > 0.15: is_facing_left = false

		var deg = rad_to_deg(move_vector.angle())
		if deg < 0: deg += 360.0

		if deg >= 40.0 and deg <= 140.0: current_facing = BodyFacing.FRONT
		elif deg >= 220.0 and deg <= 320.0: current_facing = BodyFacing.BACK
		else: current_facing = BodyFacing.SIDE

		queue_redraw()
		if is_instance_valid(glow_layer): glow_layer.queue_redraw()

func _process(delta: float) -> void:
	anim_time += delta
	var parent_node = get_parent()
	if parent_node and "velocity" in parent_node:
		var vel: Vector2 = parent_node.velocity
		if vel.length_squared() > 100.0:
			update_facing(vel)

	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match type:
		NecronType.SCARAB:       _draw_scarab()
		NecronType.WARRIOR:      _draw_warrior()
		NecronType.CRYPTEK_BOSS: _draw_cryptek()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 1. CANOPTEK SCARAB (Swarm Unit)
# ==============================================================================
func _draw_scarab():
	# Ground Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 8), 7.0, Color(0.01, 0.01, 0.02, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	# 6 Twitching Segmented Legs
	var leg_cycle = sin(anim_time * 18.0) * 3.0
	for side in [-1.0, 1.0]:
		draw_line(Vector2(side * 4, -2), Vector2(side * 10, -5 + leg_cycle), C_LIVING_METAL, 1.5)
		draw_line(Vector2(side * 5, 1), Vector2(side * 11, 2 - leg_cycle), C_LIVING_METAL, 1.5)
		draw_line(Vector2(side * 4, 4), Vector2(side * 9, 7 + leg_cycle), C_LIVING_METAL, 1.5)

	# Chitinous Carapace Shell
	var carapace = PackedVector2Array([
		Vector2(0, -6), Vector2(6, -2), Vector2(5, 5),
		Vector2(0, 7), Vector2(-5, 5), Vector2(-6, -2)
	])
	draw_colored_polygon(carapace, C_BLACKSTONE)
	draw_polyline(carapace, C_OUTLINE, 1.4)
	draw_line(Vector2(0, -5), Vector2(0, 6), C_LIVING_METAL, 1.2)

# ==============================================================================
# 2. NECRON WARRIOR
# ==============================================================================
func _draw_warrior():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 10.0, Color(0.01, 0.01, 0.02, 0.50))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	# Torso Ribcage
	draw_rect(Rect2(-7, -8, 14, 16), C_NECRON_DARK)
	draw_rect(Rect2(-7, -8, 14, 16), C_OUTLINE, false, 1.2)
	for i in range(3):
		draw_line(Vector2(-5, -4 + i * 4), Vector2(5, -4 + i * 4), C_LIVING_METAL, 1.6)

	# Metallic Skull
	draw_circle(Vector2(0, -12), 5.5, C_LIVING_METAL)
	draw_circle(Vector2(0, -12), 5.5, C_OUTLINE, false, 1.2)

	# Gauss Flayer Rifle
	var gun_root = Vector2(4, 0)
	var gun_tip = Vector2(18, -2)
	draw_line(gun_root, gun_tip, C_BLACKSTONE, 3.5)
	draw_line(gun_root + Vector2(2, 0), gun_tip - Vector2(4, 0), C_GAUSS_GREEN, 1.5)
	draw_circle(gun_tip, 2.0, C_LIVING_METAL)

# ==============================================================================
# 3. NECRON CRYPTEK WARDEN (BOSS)
# ==============================================================================
func _draw_cryptek():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 16), 22.0, Color(0.01, 0.01, 0.03, 0.65))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	# Floating Canoptek Mantle & Spine Ribs
	var hover = sin(anim_time * 4.0) * 3.5
	var center = Vector2(0, hover)

	# Golden Dynastic Crest & Headdress
	var crest = PackedVector2Array([
		center + Vector2(0, -28), center + Vector2(14, -14),
		center + Vector2(10, -4), center + Vector2(-10, -4), center + Vector2(-14, -14)
	])
	draw_colored_polygon(crest, C_NECRON_GOLD)
	draw_polyline(crest, C_OUTLINE, 1.4)

	# Death Mask Skull
	draw_circle(center + Vector2(0, -14), 7.5, C_LIVING_METAL)
	draw_circle(center + Vector2(0, -14), 7.5, C_OUTLINE, false, 1.4)

	# Segmented Robe Plate & Chronometron Core
	var robe = PackedVector2Array([
		center + Vector2(-10, -2), center + Vector2(10, -2),
		center + Vector2(14, 18), center + Vector2(0, 24), center + Vector2(-14, 18)
	])
	draw_colored_polygon(robe, C_BLACKSTONE)
	draw_polyline(robe, C_NECRON_GOLD, 1.5)

	# Massive Hyperphase Warscythe
	var staff_top = center + Vector2(-18, -26)
	var staff_bot = center + Vector2(18, 28)
	draw_line(staff_top, staff_bot, C_LIVING_METAL, 3.5)
	
	# Scythe Crescent Power Blade
	var blade = PackedVector2Array([
		staff_top, staff_top + Vector2(-14, 8),
		staff_top + Vector2(-22, -4), staff_top + Vector2(-8, -16)
	])
	draw_colored_polygon(blade, C_GAUSS_GREEN)
	draw_polyline(blade, C_GAUSS_CORE, 1.4)

# ==============================================================================
# UNSHADED GLOW LAYER (Eyes, Gauss Energy, Reanimation Rings)
# ==============================================================================
class NecronGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		var flip = -1.0 if p.is_facing_left else 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(flip, 1.0))
		var pulse = 0.75 + sin(Time.get_ticks_msec() * 0.008) * 0.25

		match p.type:
			0: # Scarab Optics & Underside Matrix
				draw_circle(Vector2(0, -4), 1.8 * pulse, Color(0.2, 1.0, 0.45, 0.95))
				draw_circle(Vector2(0, -4), 0.8, Color.WHITE)
			1: # Warrior Monocular Eyes & Gauss Coil
				draw_circle(Vector2(-2, -12), 1.5, Color(0.2, 1.0, 0.45, 0.9))
				draw_circle(Vector2(2, -12), 1.5, Color(0.2, 1.0, 0.45, 0.9))
				draw_line(Vector2(6, 0), Vector2(14, -2), Color(0.2, 1.0, 0.45, 0.8 * pulse), 2.5)
			2: # Cryptek Ocular Scanner, Staff Core, & Reanimation Field
				var hover = sin(p.anim_time * 4.0) * 3.5
				var c = Vector2(0, hover)
				draw_circle(c + Vector2(0, -14), 2.5 * pulse, Color(0.2, 1.0, 0.45, 0.95))
				draw_circle(c + Vector2(0, -14), 1.2, Color.WHITE)
				
				# Chronometron Chest Core
				draw_circle(c + Vector2(0, 2), 4.0 * pulse, Color(0.2, 1.0, 0.45, 0.8))
				draw_circle(c + Vector2(0, 2), 2.0, Color.WHITE)

				# Reanimation Matrix Field Rings
				if p.is_reanimating:
					draw_arc(c, 28.0, 0, TAU, 32, Color(0.2, 1.0, 0.45, pulse), 2.0)
					draw_circle(c, 28.0, Color(0.2, 1.0, 0.45, 0.15 * pulse))

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
