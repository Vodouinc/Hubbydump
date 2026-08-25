@tool 
extends Node2D 
class_name UnitSprite

enum UnitType { 
	ADMECH_TECHPRIEST = 0, 
	SKITARII_MARSHAL = 1, 
	SKITARII_VANGUARD = 2, 
	SERVO_SKULL = 3,
	SKITARII_RANGER = 4,
	SICARIAN_RUSTSTALKER = 5,
	SISTER_OF_BATTLE = 6 # <-- Appended at end so bodyguards retain their IDs
}

enum BodyFacing { FRONT, BACK, SIDE }

var current_facing: BodyFacing = BodyFacing.FRONT
var is_facing_left: bool = false
var aim_angle: float = 0.0
var aim_vector: Vector2 = Vector2.DOWN

# Attack Animation State (Driven by Parent Controller)
var is_attacking: bool = false
var attack_progress: float = 0.0
var attack_strike_angle: float = 0.0

# Sister of Battle Custom Visual States
var is_flamer_firing: bool = false
var is_celestine_ascended: bool = false

var anim_time: float = 0.0
var attack_flash: float = 0.0

@export var unit_type: UnitType = UnitType.SKITARII_VANGUARD: 
	set(val): 
		unit_type = val 
		queue_redraw()
		if is_instance_valid(glow_layer): glow_layer.queue_redraw()

var glow_layer: Node2D = null

# --- GRIMDARK 40K PALETTE ---
const C_OUTLINE      := Color(0.04, 0.05, 0.07)
const C_STEEL_DARK   := Color(0.12, 0.14, 0.18)
const C_STEEL_MID    := Color(0.24, 0.28, 0.35)
const C_STEEL_LIGHT  := Color(0.44, 0.50, 0.58)
const C_MARS_DARK    := Color(0.28, 0.05, 0.05)
const C_MARS_RED     := Color(0.68, 0.16, 0.14)
const C_MARS_LIGHT   := Color(0.85, 0.25, 0.20)
const C_WHITE_TRIM   := Color(0.92, 0.92, 0.88)
const C_BRASS        := Color(0.82, 0.62, 0.24)
const C_BRASS_LIGHT  := Color(0.96, 0.82, 0.45)
const C_COPPER       := Color(0.82, 0.44, 0.18)
const C_CYAN         := Color(0.20, 0.88, 1.00)
const C_RAD_GREEN    := Color(0.25, 0.95, 0.35)
const C_IVORY        := Color(0.90, 0.86, 0.76)
const C_PARCHMENT    := Color(0.88, 0.84, 0.72)
const C_SEAL_WAX     := Color(0.78, 0.08, 0.08)

const C_SOB_ARMOR    := Color(0.11, 0.12, 0.15)
const C_SOB_TABARD   := Color(0.68, 0.10, 0.12) # <-- ADD THIS LINE
const C_SOB_HAIR     := Color(0.92, 0.92, 0.95)
const C_GOLD_HOLY    := Color(1.00, 0.88, 0.25)
const C_FLAME_CORE   := Color(1.00, 0.92, 0.40)
const C_FLAME_BURST  := Color(1.00, 0.52, 0.15, 0.75)

func _ready() -> void:
	_setup_glow_layer()
	queue_redraw()

func update_facing(target_world_pos: Vector2) -> void:
	var to_target = (target_world_pos - global_position).normalized()
	aim_vector = to_target
	aim_angle = to_target.angle()

	if to_target.x < -0.12:
		is_facing_left = true
	elif to_target.x > 0.12:
		is_facing_left = false

	var deg = rad_to_deg(aim_angle)
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

func set_attack_state(attacking: bool, progress: float, strike_angle: float) -> void:
	is_attacking = attacking
	attack_progress = progress
	attack_strike_angle = strike_angle
	queue_redraw()
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func _setup_glow_layer():
	if not has_node("UnitGlowOverlay"):
		glow_layer = Node2D.new()
		glow_layer.name = "UnitGlowOverlay"
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		glow_layer.material = mat
		add_child(glow_layer)
		glow_layer.set_script(load("res://UnitSprite.gd").UnitGlowRenderer)
	else:
		glow_layer = get_node("UnitGlowOverlay")

func _process(delta: float) -> void:
	anim_time += delta
	attack_flash = maxf(0.0, attack_flash - delta * 5.5)
	var parent_node = get_parent()
	var movement: float = parent_node.get("velocity").length() if parent_node and "velocity" in parent_node else 0.0
	
	var bob = sin(anim_time * (4.5 + movement * 0.015)) * (minf(movement / 300.0, 1.0) * 1.5)
	position.y = bob

	# Sync states from parent if available
	if parent_node:
		if "flamer_active" in parent_node:
			is_flamer_firing = parent_node.flamer_active
		if "is_celestine_ascended" in parent_node:
			is_celestine_ascended = parent_node.is_celestine_ascended
	
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func trigger_attack_fx() -> void:
	attack_flash = 1.0
	queue_redraw()
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func draw_purity_seal(screen_pos: Vector2, scroll_len: float = 6.0) -> void:
	draw_circle(screen_pos, 1.8, C_SEAL_WAX)
	draw_line(screen_pos + Vector2(-0.8, 1.5), screen_pos + Vector2(-0.8, 1.5 + scroll_len), C_PARCHMENT, 1.8)
	draw_line(screen_pos + Vector2(0.8, 1.5), screen_pos + Vector2(0.8, 1.5 + scroll_len * 0.65), C_PARCHMENT, 1.2)

func _draw() -> void:
	# Horizontal mirroring
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	var aiming_up = (current_facing == BodyFacing.BACK)
	var is_special = (unit_type == UnitType.ADMECH_TECHPRIEST or unit_type == UnitType.SERVO_SKULL or unit_type == UnitType.SICARIAN_RUSTSTALKER or unit_type == UnitType.SISTER_OF_BATTLE)

	# 1. Ranged weapon behind body layer (when aiming UP)
	if aiming_up and not is_special:
		_draw_ranged_weapon_layer()

	# 2. Character Body
	match unit_type:
		UnitType.ADMECH_TECHPRIEST:    _draw_tech_priest()
		UnitType.SKITARII_MARSHAL:     _draw_marshal_body()
		UnitType.SKITARII_VANGUARD:    _draw_vanguard_body()
		UnitType.SERVO_SKULL:          _draw_servo_skull()
		UnitType.SKITARII_RANGER:      _draw_ranger_body()
		UnitType.SICARIAN_RUSTSTALKER: _draw_sicarian_body()
		UnitType.SISTER_OF_BATTLE:     _draw_sister_of_battle()

	# 3. Ranged weapon in front of body layer
	if not aiming_up and not is_special:
		_draw_ranged_weapon_layer()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 1. TECH-PRIEST ENGINSEER
# ==============================================================================
func _draw_tech_priest():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 12), 11.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	var mecha_lunge = Vector2.ZERO
	if is_attacking:
		var t = attack_progress
		if t >= 0.2 and t <= 0.75:
			var s_t = (t - 0.2) / 0.55
			mecha_lunge = Vector2(sin(s_t * PI) * 8.0, 0.0)

	# Mechadendrites
	draw_polyline(PackedVector2Array([Vector2(-4, -6), Vector2(-11, -16) - mecha_lunge * 0.5, Vector2(-5, -24) + mecha_lunge]), C_STEEL_MID, 3.5)
	draw_polyline(PackedVector2Array([Vector2(4, -6), Vector2(11, -16) - mecha_lunge * 0.5, Vector2(5, -24) + mecha_lunge]), C_STEEL_MID, 3.5)
	draw_circle(Vector2(-5, -24) + mecha_lunge, 2.2, C_BRASS)
	draw_circle(Vector2(5, -24) + mecha_lunge, 2.2, C_BRASS)

	match current_facing:
		BodyFacing.BACK:
			var robe_b = PackedVector2Array([Vector2(-8, -6), Vector2(8, -6), Vector2(11, 10), Vector2(-11, 10)])
			draw_colored_polygon(robe_b, C_MARS_RED)
			draw_polyline(robe_b, C_OUTLINE, 1.4)
			draw_line(Vector2(-11, 8), Vector2(11, 8), C_WHITE_TRIM, 2.0)
			draw_rect(Rect2(-5, -12, 10, 8), C_STEEL_DARK)
			draw_circle(Vector2(0, -7), 6.0, C_MARS_RED)

		BodyFacing.FRONT:
			var robe_f = PackedVector2Array([Vector2(-8, -6), Vector2(8, -6), Vector2(11, 10), Vector2(-11, 10)])
			draw_colored_polygon(robe_f, C_MARS_RED)
			draw_polyline(robe_f, C_OUTLINE, 1.4)
			draw_line(Vector2(-11, 8), Vector2(11, 8), C_WHITE_TRIM, 2.0)
			draw_rect(Rect2(-5, -4, 10, 9), C_STEEL_DARK)
			draw_rect(Rect2(-5, -4, 10, 9), C_BRASS, false, 1.0)
			draw_circle(Vector2(0, -7), 6.2, C_MARS_RED)
			draw_circle(Vector2(-2.5, -8), 1.6, C_CYAN)
			draw_circle(Vector2(2.5, -8), 1.6, C_CYAN)
			draw_purity_seal(Vector2(-6, -2), 6.0)

		BodyFacing.SIDE:
			var robe_s = PackedVector2Array([Vector2(2, -6), Vector2(-9, -6), Vector2(-9, 10), Vector2(6, 10)])
			draw_colored_polygon(robe_s, C_MARS_RED)
			draw_polyline(robe_s, C_OUTLINE, 1.4)
			draw_line(Vector2(-9, 8), Vector2(6, 8), C_WHITE_TRIM, 2.0)
			draw_circle(Vector2(3.5, -7), 1.8, C_CYAN)

	if not is_attacking:
		var haft_start = Vector2(4, 8)
		var haft_end = Vector2(8, -18)
		draw_line(haft_start, haft_end, C_STEEL_DARK, 3.5)
		draw_line(haft_start, haft_end, C_BRASS, 1.5)
		var axe_head = haft_end
		draw_circle(axe_head, 4.5, C_BRASS)
		draw_circle(axe_head, 2.5, C_STEEL_DARK)
		var blade = PackedVector2Array([axe_head + Vector2(-5, -4), axe_head + Vector2(6, -8), axe_head + Vector2(3, 4)])
		draw_colored_polygon(blade, C_CYAN)
	else:
		_draw_axe_cleave_strike()

func _draw_axe_cleave_strike():
	var t = attack_progress
	var rel_strike_angle = attack_strike_angle
	if is_facing_left: rel_strike_angle = PI - attack_strike_angle
	var cone = deg_to_rad(130.0)
	var current_angle = 0.0
	var reach = 26.0
	var pivot = Vector2(2, -4)

	if t < 0.2:
		var w_t = t / 0.2
		current_angle = rel_strike_angle - (cone * 0.5) - (sin(w_t * PI * 0.5) * deg_to_rad(20.0))
		reach = 22.0
	elif t <= 0.75:
		var s_t = (t - 0.2) / 0.55
		var eased_s = pow(s_t, 2.2)
		current_angle = rel_strike_angle - (cone * 0.5) + (eased_s * cone)
		reach = 26.0 + sin(s_t * PI) * 4.0
		draw_arc(pivot, reach + 2.0, current_angle - deg_to_rad(35.0), current_angle, 8, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.65), 5.0)
		draw_arc(pivot, reach + 2.0, current_angle - deg_to_rad(35.0), current_angle, 8, Color.WHITE, 2.0)
	else:
		var r_t = (t - 0.75) / 0.25
		current_angle = rel_strike_angle + (cone * 0.5) + (sin(r_t * PI * 0.5) * deg_to_rad(10.0))
		reach = 24.0 - (r_t * 2.0)

	var axe_dir = Vector2.RIGHT.rotated(current_angle)
	var perp = axe_dir.orthogonal()
	var axe_shaft_end = pivot + axe_dir * reach
	draw_line(pivot, axe_shaft_end, C_STEEL_DARK, 4.0)
	draw_line(pivot, axe_shaft_end, C_BRASS, 1.8)

	var head_pos = axe_shaft_end - (axe_dir * 3.0)
	draw_circle(head_pos, 5.0, C_BRASS)
	var blade_pts = PackedVector2Array([
		head_pos + perp * 9.0 - axe_dir * 3.0,
		head_pos + perp * 11.0 + axe_dir * 5.0,
		head_pos - axe_dir * 3.0
	])
	draw_colored_polygon(blade_pts, C_CYAN)
	draw_polyline(blade_pts, Color.WHITE, 1.2)

# ==============================================================================
# 2. SISTER SUPERIOR (ADEPTA SORORITAS & SAINT CELESTINE)
# ==============================================================================
func _draw_sister_of_battle():
	# Ground Contact Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 10.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	var parent_node = get_parent()
	var is_dashing_now = parent_node.get("is_dashing") == true if parent_node else false
	var is_moving = parent_node.get("velocity").length() > 20.0 if parent_node and "velocity" in parent_node else false

	# 1. Saint Celestine Angelic Wings & Divine Aureola
	if is_celestine_ascended:
		var flap = sin(anim_time * 8.0) * 6.0
		var l_wing = PackedVector2Array([
			Vector2(-4, -6), Vector2(-30, -28 + flap), Vector2(-38, -14 + flap), Vector2(-18, 4)
		])
		draw_colored_polygon(l_wing, C_GOLD_HOLY)
		draw_polyline(l_wing, Color.WHITE, 1.4)

		var r_wing = PackedVector2Array([
			Vector2(4, -6), Vector2(30, -28 + flap), Vector2(38, -14 + flap), Vector2(18, 4)
		])
		draw_colored_polygon(r_wing, C_GOLD_HOLY)
		draw_polyline(r_wing, Color.WHITE, 1.4)

		# Golden Halo Aureola
		draw_arc(Vector2(0, -18), 8.5, 0, TAU, 16, C_GOLD_HOLY, 1.6)
		draw_circle(Vector2(0, -18), 1.5, Color.WHITE)

	var armor_base = C_SOB_ARMOR if not is_celestine_ascended else Color(0.85, 0.72, 0.22)

	# 2. Seraphim Jump Pack (Worn on shoulders with active thrusters)
	_draw_seraphim_jump_pack(is_dashing_now, is_moving)

	# 3. Power Armor Body & Corset (Short battle tabard instead of cape)
	match current_facing:
		BodyFacing.BACK:
			var tabard_b = PackedVector2Array([Vector2(-6, 2), Vector2(6, 2), Vector2(7, 12), Vector2(-7, 12)])
			draw_colored_polygon(tabard_b, C_SOB_TABARD)
			draw_polyline(tabard_b, C_OUTLINE, 1.2)

			draw_line(Vector2(-4, 6), Vector2(-4, 14), armor_base, 2.8)
			draw_line(Vector2(4, 6), Vector2(4, 14), armor_base, 2.8)
			draw_circle(Vector2(0, -8), 5.5, C_SOB_HAIR)

		BodyFacing.FRONT:
			var tabard_f = PackedVector2Array([Vector2(-5, 2), Vector2(5, 2), Vector2(6, 12), Vector2(-6, 12)])
			draw_colored_polygon(tabard_f, C_SOB_TABARD)
			draw_polyline(tabard_f, C_OUTLINE, 1.2)
			draw_line(Vector2(-5, 11), Vector2(5, 11), C_WHITE_TRIM, 1.5)

			draw_rect(Rect2(-6, -5, 12, 11), armor_base)
			draw_rect(Rect2(-6, -5, 12, 11), C_BRASS, false, 1.0)
			draw_circle(Vector2(0, -1), 2.2, Color.WHITE)
			draw_line(Vector2(-3, -1), Vector2(3, -1), Color.WHITE, 1.0)
			draw_purity_seal(Vector2(-5, 1), 6.0)

			draw_line(Vector2(-3.5, 7), Vector2(-3.5, 14), armor_base, 2.8)
			draw_line(Vector2(3.5, 7), Vector2(3.5, 14), armor_base, 2.8)

			draw_circle(Vector2(0, -7), 5.8, C_SOB_HAIR)
			draw_circle(Vector2(0, -6), 4.2, Color(0.92, 0.82, 0.72))
			draw_circle(Vector2(-1.8, -7), 1.2, C_CYAN if not is_celestine_ascended else C_GOLD_HOLY)
			draw_circle(Vector2(1.8, -7), 1.2, C_CYAN if not is_celestine_ascended else C_GOLD_HOLY)

		BodyFacing.SIDE:
			var tabard_s = PackedVector2Array([Vector2(2, 2), Vector2(-5, 2), Vector2(-4, 11), Vector2(3, 9)])
			draw_colored_polygon(tabard_s, C_SOB_TABARD)
			draw_polyline(tabard_s, C_OUTLINE, 1.2)

			draw_rect(Rect2(-3, -5, 7, 11), armor_base)
			draw_line(Vector2(-2, 7), Vector2(-2, 14), armor_base, 2.8)
			draw_line(Vector2(2, 7), Vector2(2, 14), armor_base, 2.8)

			draw_circle(Vector2(0, -7), 5.5, C_SOB_HAIR)
			draw_circle(Vector2(2.0, -7), 1.2, C_CYAN if not is_celestine_ascended else C_GOLD_HOLY)

	# 4. Flamer / Multi-Melta Weapon Mount
	_draw_sister_weapon_mount()

func _draw_seraphim_jump_pack(is_dashing_now: bool, is_moving: bool):
	var flame_intensity = 1.0 if is_dashing_now else (0.45 if is_moving else 0.15)
	var jet_l = randf_range(16.0, 28.0) * flame_intensity if is_dashing_now else randf_range(5.0, 9.0) * flame_intensity

	# Jump Pack Body Housing
	draw_rect(Rect2(-9, -12, 18, 9), C_STEEL_DARK)
	draw_rect(Rect2(-9, -12, 18, 9), C_BRASS, false, 1.0)
	
	# Twin Left & Right Thruster Turbine Intakes
	draw_circle(Vector2(-8, -8), 3.2, C_BRASS)
	draw_circle(Vector2(8, -8), 3.2, C_BRASS)

	# Angled Stabilizer Winglets
	draw_line(Vector2(-9, -10), Vector2(-16, -16), C_SOB_ARMOR, 2.2)
	draw_line(Vector2(-9, -10), Vector2(-16, -16), C_BRASS, 1.0)
	draw_line(Vector2(9, -10), Vector2(16, -16), C_SOB_ARMOR, 2.2)
	draw_line(Vector2(9, -10), Vector2(16, -16), C_BRASS, 1.0)

	# Downward Rocket Exhaust Bells
	draw_line(Vector2(-7, -4), Vector2(-7, 1), C_COPPER, 2.5)
	draw_line(Vector2(7, -4), Vector2(7, 1), C_COPPER, 2.5)

	# Active Rocket Thruster Plumes
	if flame_intensity > 0.1:
		for noz_x in [-7.0, 7.0]:
			var noz_pos = Vector2(noz_x, 1.0)
			var flame_end = noz_pos + Vector2(0, jet_l)
			draw_line(noz_pos, flame_end, Color(1.0, 0.52, 0.15, 0.85), 3.8 if is_dashing_now else 2.2)
			draw_line(noz_pos, noz_pos + Vector2(0, jet_l * 0.6), Color(1.0, 0.95, 0.4, 0.95), 1.8 if is_dashing_now else 1.0)
			draw_circle(noz_pos, 2.0 if is_dashing_now else 1.2, Color.WHITE)

func _draw_sister_weapon_mount():
	var shoulder = Vector2(4, -2) if current_facing != BodyFacing.SIDE else Vector2(2, -2)
	var rel_angle = aim_angle
	if is_facing_left: rel_angle = PI - aim_angle
	var arm_dir = Vector2.RIGHT.rotated(rel_angle)

	# Two-handed Flamer / Melta Casing
	var w_root = shoulder - (arm_dir * 2.0)
	var w_tip = shoulder + (arm_dir * 18.0)

	draw_line(w_root, w_tip, C_SOB_ARMOR, 3.8)
	draw_line(w_root + arm_dir * 4.0, w_tip, C_BRASS, 1.6)

	# Brass Fuel Canister & Pilot Flame Igniter
	var canister_pos = w_root + arm_dir * 6.0 - arm_dir.orthogonal() * 2.5
	draw_circle(canister_pos, 2.0, C_BRASS)
	draw_circle(w_tip, 1.4, Color(1.0, 0.7, 0.2)) # Pilot light

	# Hands Gripping Weapon
	draw_circle(shoulder, 1.8, C_STEEL_LIGHT)
	draw_circle(w_root + arm_dir * 8.0, 1.6, C_STEEL_LIGHT)

	# 4. Active Flamer Promethium Cone FX
	if is_flamer_firing:
		var flame_len = randf_range(120.0, 175.0)
		var perp = arm_dir.orthogonal()
		var spread_w = 48.0

		var cone_poly = PackedVector2Array([
			w_tip,
			w_tip + (arm_dir * flame_len) - (perp * spread_w * 0.5),
			w_tip + (arm_dir * flame_len * 1.12),
			w_tip + (arm_dir * flame_len) + (perp * spread_w * 0.5)
		])
		draw_colored_polygon(cone_poly, C_FLAME_BURST)
		
		# Inner Intense White-Hot Core
		var core_poly = PackedVector2Array([
			w_tip,
			w_tip + (arm_dir * flame_len * 0.6) - (perp * spread_w * 0.25),
			w_tip + (arm_dir * flame_len * 0.7),
			w_tip + (arm_dir * flame_len * 0.6) + (perp * spread_w * 0.25)
		])
		draw_colored_polygon(core_poly, Color(1.0, 0.95, 0.6, 0.85))

# ==============================================================================
# RANGED WEAPONS (MARSHAL, VANGUARD, RANGER)
# ==============================================================================
func _draw_ranged_weapon_layer():
	var shoulder = Vector2(4, -4) if current_facing != BodyFacing.SIDE else Vector2(2, -4)
	var rel_angle = aim_angle
	if is_facing_left: rel_angle = PI - aim_angle
	var arm_dir = Vector2.RIGHT.rotated(rel_angle)

	match unit_type:
		UnitType.SKITARII_MARSHAL:
			var p_root = shoulder + arm_dir * 2.0
			var p_tip = shoulder + arm_dir * 14.0
			draw_line(p_root, p_tip, C_STEEL_MID, 3.2)
			draw_line(p_root, p_tip, C_BRASS, 1.2)
			draw_circle(p_root + arm_dir * 6.0, 1.5, C_CYAN)
			draw_circle(shoulder, 1.8, C_STEEL_LIGHT)

		UnitType.SKITARII_VANGUARD:
			var r_root = shoulder - arm_dir * 3.0
			var r_tip = shoulder + arm_dir * 17.0
			draw_line(r_root, r_tip, C_STEEL_DARK, 3.4)
			draw_line(r_root + arm_dir * 4.0, r_tip, C_BRASS, 1.5)
			draw_rect(Rect2(r_tip - arm_dir * 3.0 - Vector2(1, 1), Vector2(3, 3)), C_STEEL_LIGHT)
			var cyl_pos = r_root + arm_dir * 8.0 - arm_dir.orthogonal() * 2.0
			draw_rect(Rect2(cyl_pos - Vector2(2, 1.5), Vector2(4, 3)), C_RAD_GREEN)
			draw_circle(cyl_pos, 1.0, Color.WHITE)
			draw_circle(shoulder, 1.8, C_STEEL_LIGHT)
			draw_circle(r_root + arm_dir * 7.0, 1.6, C_STEEL_LIGHT)

		UnitType.SKITARII_RANGER:
			var g_root = shoulder - arm_dir * 4.0
			var g_tip = shoulder + arm_dir * 24.0
			draw_line(g_root, g_tip, Color(0.22, 0.18, 0.14), 3.2)
			draw_line(g_root + arm_dir * 6.0, g_tip, C_BRASS, 2.0)
			draw_line(g_root + arm_dir * 8.0 - arm_dir.orthogonal() * 3.0, g_root + arm_dir * 16.0 - arm_dir.orthogonal() * 3.0, C_STEEL_MID, 1.8)
			draw_circle(g_root + arm_dir * 16.0 - arm_dir.orthogonal() * 3.0, 1.2, C_CYAN)
			draw_circle(shoulder, 1.8, C_STEEL_LIGHT)
			draw_circle(shoulder + arm_dir * 8.0, 1.6, C_STEEL_LIGHT)

# ==============================================================================
# 3. SKITARII MARSHAL
# ==============================================================================
func _draw_marshal_body():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 10.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match current_facing:
		BodyFacing.BACK:
			var cape_b = PackedVector2Array([Vector2(-7, -6), Vector2(7, -6), Vector2(12, 12), Vector2(-12, 12)])
			draw_colored_polygon(cape_b, C_MARS_DARK)
			draw_polyline(cape_b, C_BRASS, 1.4)
			draw_rect(Rect2(-4, -12, 8, 8), C_STEEL_DARK)
			draw_line(Vector2(3, -12), Vector2(3, -22), C_BRASS, 1.8)
			draw_circle(Vector2(3, -22), 1.5, C_CYAN)
			draw_circle(Vector2(0, -6), 5.0, C_BRASS)

		BodyFacing.FRONT:
			var cape_f = PackedVector2Array([Vector2(-9, -4), Vector2(-12, 11), Vector2(12, 11), Vector2(9, -4)])
			draw_colored_polygon(cape_f, C_MARS_DARK)
			draw_polyline(cape_f, C_OUTLINE, 1.2)
			draw_circle(Vector2.ZERO, 8.0, C_MARS_RED)
			draw_rect(Rect2(-4, -2, 8, 8), C_BRASS)
			draw_circle(Vector2(0, -7), 5.2, C_BRASS)
			draw_rect(Rect2(-1, -13, 2, 6), C_BRASS_LIGHT)
			draw_line(Vector2(-3, -7), Vector2(3, -7), C_CYAN, 2.0)
			draw_purity_seal(Vector2(-6, 0), 6.0)

		BodyFacing.SIDE:
			var cape_s = PackedVector2Array([Vector2(0, -6), Vector2(-13, -2), Vector2(-10, 12), Vector2(2, 7)])
			draw_colored_polygon(cape_s, C_MARS_DARK)
			draw_polyline(cape_s, C_BRASS, 1.4)
			draw_circle(Vector2(0, 0), 7.0, C_MARS_RED)
			draw_circle(Vector2(1, -6), 4.8, C_BRASS)
			draw_line(Vector2(-1, -12), Vector2(2, -6), C_BRASS_LIGHT, 2.0)
			draw_circle(Vector2(4, -6), 1.8, C_CYAN)

# ==============================================================================
# 4. SKITARII VANGUARD
# ==============================================================================
func _draw_vanguard_body():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 9.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match current_facing:
		BodyFacing.BACK:
			var coat_b = PackedVector2Array([Vector2(-7, -5), Vector2(7, -5), Vector2(10, 11), Vector2(-10, 11)])
			draw_colored_polygon(coat_b, C_MARS_RED)
			draw_polyline(coat_b, C_OUTLINE, 1.2)
			for i in range(4): draw_rect(Rect2(-8 + i * 4.5, 9, 2.5, 2), C_IVORY)
			draw_line(Vector2(-4, 9), Vector2(-4, 16), C_STEEL_MID, 2.2)
			draw_line(Vector2(4, 9), Vector2(4, 16), C_STEEL_MID, 2.2)
			draw_rect(Rect2(-5, -11, 10, 8), C_STEEL_DARK)
			draw_rect(Rect2(-5, -11, 10, 8), C_BRASS, false, 1.0)
			draw_line(Vector2(-3, -11), Vector2(-3, -16), C_COPPER, 2.0)
			draw_line(Vector2(3, -11), Vector2(3, -16), C_COPPER, 2.0)
			draw_circle(Vector2(-3, -16), 1.0, C_RAD_GREEN)
			draw_circle(Vector2(3, -16), 1.0, C_RAD_GREEN)
			draw_circle(Vector2(0, -7), 6.0, C_MARS_RED)

		BodyFacing.FRONT:
			var coat_f = PackedVector2Array([Vector2(-7, -4), Vector2(7, -4), Vector2(9, 11), Vector2(-9, 11)])
			draw_colored_polygon(coat_f, C_MARS_RED)
			draw_polyline(coat_f, C_OUTLINE, 1.2)
			for i in range(4): draw_rect(Rect2(-8 + i * 4.5, 9, 2.5, 2), C_IVORY)
			draw_line(Vector2(-4, 9), Vector2(-4, 16), C_STEEL_MID, 2.2)
			draw_line(Vector2(4, 9), Vector2(4, 16), C_STEEL_MID, 2.2)
			draw_rect(Rect2(-4, -3, 8, 7), C_STEEL_DARK)
			draw_rect(Rect2(-4, -3, 8, 7), C_BRASS, false, 1.0)
			draw_circle(Vector2(0, 0), 1.8, C_BRASS)
			draw_purity_seal(Vector2(-5, 0), 6.0)
			draw_circle(Vector2(0, -7), 6.0, C_MARS_RED)
			var mask = PackedVector2Array([Vector2(-2.5, -5), Vector2(2.5, -5), Vector2(0, -2)])
			draw_colored_polygon(mask, C_COPPER)
			draw_circle(Vector2(-2.2, -7), 1.2, C_RAD_GREEN)
			draw_circle(Vector2(2.2, -7), 1.2, C_RAD_GREEN)

		BodyFacing.SIDE:
			var coat_s = PackedVector2Array([Vector2(3, -5), Vector2(-8, -6), Vector2(-6, 11), Vector2(4, 8)])
			draw_colored_polygon(coat_s, C_MARS_RED)
			draw_polyline(coat_s, C_OUTLINE, 1.2)
			draw_line(Vector2(-3, 9), Vector2(-3, 16), C_STEEL_MID, 2.2)
			draw_line(Vector2(3, 9), Vector2(3, 16), C_STEEL_MID, 2.2)
			draw_circle(Vector2(0, -7), 5.8, C_MARS_RED)
			draw_rect(Rect2(2, -6, 3.5, 4), C_COPPER)
			draw_circle(Vector2(2.2, -7), 1.2, C_RAD_GREEN)
			draw_rect(Rect2(-7, -10, 4, 8), C_STEEL_DARK)
			draw_line(Vector2(-5, -10), Vector2(-5, -15), C_COPPER, 1.8)

# ==============================================================================
# 5. SKITARII RANGER
# ==============================================================================
func _draw_ranger_body():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 9.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match current_facing:
		BodyFacing.BACK:
			var coat_b = PackedVector2Array([Vector2(-7, -5), Vector2(7, -5), Vector2(10, 11), Vector2(-10, 11)])
			draw_colored_polygon(coat_b, C_MARS_RED)
			draw_polyline(coat_b, C_OUTLINE, 1.2)
			draw_rect(Rect2(-4, -10, 8, 8), C_STEEL_DARK)
			draw_line(Vector2(3, -10), Vector2(3, -22), C_STEEL_MID, 1.5)
			draw_circle(Vector2(0, -7), 6.2, C_MARS_RED)

		BodyFacing.FRONT:
			var coat_f = PackedVector2Array([Vector2(-7, -4), Vector2(7, -4), Vector2(9, 11), Vector2(-9, 11)])
			draw_colored_polygon(coat_f, C_MARS_RED)
			draw_polyline(coat_f, C_OUTLINE, 1.2)
			draw_rect(Rect2(-4, -3, 8, 7), C_STEEL_DARK)
			draw_purity_seal(Vector2(-5, 0), 6.0)
			draw_circle(Vector2(0, -7), 6.5, C_MARS_RED)
			draw_circle(Vector2(0, -7), 1.2, C_CYAN)

		BodyFacing.SIDE:
			var coat_s = PackedVector2Array([Vector2(3, -5), Vector2(-8, -6), Vector2(-6, 11), Vector2(4, 8)])
			draw_colored_polygon(coat_s, C_MARS_RED)
			draw_polyline(coat_s, C_OUTLINE, 1.2)
			draw_circle(Vector2(0, -7), 6.0, C_MARS_RED)
			draw_circle(Vector2(3.0, -7), 1.2, C_CYAN)

# ==============================================================================
# 6. SICARIAN RUSTSTALKER
# ==============================================================================
func _draw_sicarian_body():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 10.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	var swing = (attack_progress * 14.0) if is_attacking else 0.0
	var is_slashing = is_attacking and attack_progress > 0.1

	match current_facing:
		BodyFacing.BACK:
			draw_polyline(PackedVector2Array([Vector2(-4, 4), Vector2(-7, 9), Vector2(-4, 14)]), C_STEEL_MID, 2.2)
			draw_polyline(PackedVector2Array([Vector2(4, 4), Vector2(7, 9), Vector2(4, 14)]), C_STEEL_MID, 2.2)
			var tabard_b = PackedVector2Array([Vector2(-5, 2), Vector2(5, 2), Vector2(6, 11), Vector2(-6, 11)])
			draw_colored_polygon(tabard_b, C_MARS_DARK)
			draw_circle(Vector2(0, -7), 5.5, C_STEEL_DARK)
			if is_slashing:
				_draw_transonic_blade(Vector2(-7, -2), Vector2(-12, -22 - swing))
				_draw_transonic_blade(Vector2(7, -2), Vector2(12, -22 - swing))
			else:
				_draw_transonic_blade(Vector2(-7, -2), Vector2(-14, -18))
				_draw_transonic_blade(Vector2(7, -2), Vector2(14, -18))

		BodyFacing.FRONT:
			draw_polyline(PackedVector2Array([Vector2(-5, 4), Vector2(-8, 9), Vector2(-5, 14)]), C_STEEL_MID, 2.2)
			draw_polyline(PackedVector2Array([Vector2(5, 4), Vector2(8, 9), Vector2(5, 14)]), C_STEEL_MID, 2.2)
			var tabard_f = PackedVector2Array([Vector2(-5, 2), Vector2(5, 2), Vector2(6, 11), Vector2(-6, 11)])
			draw_colored_polygon(tabard_f, C_MARS_RED)
			draw_circle(Vector2(0, -7), 5.5, C_STEEL_DARK)
			draw_line(Vector2(-3.5, -7), Vector2(3.5, -7), C_CYAN, 2.0)
			if is_slashing:
				_draw_transonic_blade(Vector2(-7, 1), Vector2(8, 12 + swing))
				_draw_transonic_blade(Vector2(7, 1), Vector2(-8, 12 + swing))
			else:
				_draw_transonic_blade(Vector2(-7, 1), Vector2(-15, 11))
				_draw_transonic_blade(Vector2(7, 1), Vector2(15, 11))

		BodyFacing.SIDE:
			draw_polyline(PackedVector2Array([Vector2(-3, 4), Vector2(-7, 9), Vector2(-4, 14)]), C_STEEL_MID, 2.2)
			draw_polyline(PackedVector2Array([Vector2(3, 4), Vector2(7, 9), Vector2(4, 14)]), C_STEEL_MID, 2.2)
			draw_circle(Vector2(0, -7), 5.2, C_STEEL_DARK)
			draw_line(Vector2(0, -7), Vector2(4, -7), C_CYAN, 2.0)
			if is_slashing:
				_draw_transonic_blade(Vector2(-2, 1), Vector2(22, 2 + swing))
				_draw_transonic_blade(Vector2(2, 3), Vector2(20, -10 - swing))
			else:
				_draw_transonic_blade(Vector2(-2, 1), Vector2(16, -6))
				_draw_transonic_blade(Vector2(2, 3), Vector2(18, 3))

func _draw_transonic_blade(hand_pos: Vector2, tip_pos: Vector2) -> void:
	var blade_dir = (tip_pos - hand_pos).normalized()
	var hilt_end = hand_pos - blade_dir * 3.0
	draw_line(hilt_end, hand_pos, C_STEEL_DARK, 2.5)
	draw_circle(hilt_end, 1.2, C_BRASS)
	draw_line(hand_pos, tip_pos, C_CYAN, 3.2)
	draw_line(hand_pos, tip_pos, Color.WHITE, 1.2)
	draw_circle(hand_pos, 1.6, C_STEEL_LIGHT)

# ==============================================================================
# 7. SERVO-SKULL
# ==============================================================================
func _draw_servo_skull():
	draw_rect(Rect2(-3, -11, 6, 4), C_STEEL_DARK)
	draw_line(Vector2(0, -11), Vector2(0, -14), C_BRASS, 1.5)
	draw_circle(Vector2.ZERO, 7.0, C_IVORY)
	draw_circle(Vector2.ZERO, 7.0, C_OUTLINE, false, 1.2)
	draw_circle(Vector2(2.5, -1), 1.8, C_CYAN)
	draw_purity_seal(Vector2(-3, 4), 7.0)

# ==============================================================================
# UNSHADED NIGHT GLOW OVERLAY
# ==============================================================================
class UnitGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		var flip = -1.0 if p.is_facing_left else 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(flip, 1.0))

		var parent_node = p.get_parent()
		if parent_node and parent_node.is_in_group("players"):
			var aura = 0.55 + sin(p.anim_time * 3.0) * 0.2
			var aura_col = Color(0.20, 0.88, 1.0, 0.45 * aura)
			if p.unit_type == 2:
				aura_col = Color(1.0, 0.85, 0.2, 0.55 * aura) if p.is_celestine_ascended else Color(0.9, 0.3, 0.15, 0.35 * aura)
			draw_arc(Vector2.ZERO, 16.0, 0, TAU, 24, aura_col, 1.5)

		match p.unit_type:
			0: # Tech-Priest
				if p.current_facing != BodyFacing.BACK:
					var ep = Vector2(3.5, -7) if p.current_facing == BodyFacing.SIDE else Vector2(0, -8)
					draw_circle(ep, 2.2, Color(0.20, 0.88, 1.0, 0.9))
			1: # Marshal
				if p.current_facing != BodyFacing.BACK:
					var vp = Vector2(4, -6) if p.current_facing == BodyFacing.SIDE else Vector2(0, -7)
					draw_circle(vp, 2.0, Color(0.20, 0.88, 1.0, 0.9))
			2: # Vanguard
				if p.current_facing != BodyFacing.BACK:
					var gp = Vector2(3, -6) if p.current_facing == BodyFacing.SIDE else Vector2(0, -6)
					draw_circle(gp, 2.2, Color(0.25, 0.95, 0.35, 0.9))
			3: # Servo-Skull
				draw_circle(Vector2(2.5, -1), 2.0, Color(0.20, 0.88, 1.0, 0.9))
			4: # Ranger
				if p.current_facing != BodyFacing.BACK:
					var rp = Vector2(3.0, -7) if p.current_facing == BodyFacing.SIDE else Vector2(0, -7)
					draw_circle(rp, 1.8, Color(0.20, 0.88, 1.0, 0.9))
			5: # Sicarian
				if p.current_facing != BodyFacing.BACK:
					var sp = Vector2(3.0, -7) if p.current_facing == BodyFacing.SIDE else Vector2(0, -7)
					draw_circle(sp, 2.5, Color(0.20, 0.88, 1.0, 0.8))
			6: # Sister of Battle (Halo & Flamer Glow)
				if p.is_celestine_ascended:
					draw_arc(Vector2(0, -18), 8.0, 0, TAU, 16, Color(1.0, 0.9, 0.3, 0.9), 1.8)
					draw_circle(Vector2(0, -18), 2.0, Color.WHITE)
				if p.is_flamer_firing:
					draw_circle(Vector2(18, -2), 6.0, Color(1.0, 0.6, 0.1, 0.85))

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
