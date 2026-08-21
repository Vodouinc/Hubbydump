@tool 
extends Node2D 

enum UnitType { ADMECH_TECHPRIEST, SKITARII_MARSHAL, SKITARII_VANGUARD, SERVO_SKULL } 
enum BodyFacing { FRONT, BACK, SIDE }

var current_facing: BodyFacing = BodyFacing.FRONT
var is_facing_left: bool = false
var aim_angle: float = 0.0
var aim_vector: Vector2 = Vector2.DOWN

# Melee Attack Animation State (Driven by Player.gd)
var is_attacking: bool = false
var attack_progress: float = 0.0
var attack_strike_angle: float = 0.0

var anim_time: float = 0.0
var attack_flash: float = 0.0

@export var unit_type: UnitType = UnitType.SKITARII_VANGUARD: 
	set(val): 
		unit_type = val 
		queue_redraw()
		if is_instance_valid(glow_layer): glow_layer.queue_redraw()

var glow_layer: Node2D = null

# --- GRIMDARK FORGE-WORLD PALETTE ---
const C_OUTLINE     := Color(0.04, 0.05, 0.07)
const C_STEEL_DARK  := Color(0.12, 0.14, 0.18)
const C_STEEL_MID   := Color(0.24, 0.28, 0.35)
const C_STEEL_LIGHT := Color(0.44, 0.50, 0.58)
const C_MARS_DARK   := Color(0.28, 0.05, 0.05)
const C_MARS_RED    := Color(0.68, 0.16, 0.14)
const C_MARS_LIGHT  := Color(0.85, 0.25, 0.20)
const C_WHITE_TRIM  := Color(0.92, 0.92, 0.88)
const C_BRASS       := Color(0.82, 0.62, 0.24)
const C_BRASS_LIGHT := Color(0.96, 0.82, 0.45)
const C_COPPER      := Color(0.82, 0.44, 0.18)
const C_CYAN        := Color(0.20, 0.88, 1.00)
const C_RAD_GREEN   := Color(0.25, 0.95, 0.35)
const C_IVORY       := Color(0.90, 0.86, 0.76)
const C_PARCHMENT   := Color(0.88, 0.84, 0.72)
const C_SEAL_WAX    := Color(0.78, 0.08, 0.08)

func _ready() -> void:
	_setup_glow_layer()
	queue_redraw()

## Updates facing with a smooth 15-degree hysteresis buffer to prevent flickering
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
	
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func trigger_attack_fx() -> void:
	attack_flash = 1.0
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
	
	# 1. Ranged weapon rear layer
	if aiming_up and unit_type != UnitType.ADMECH_TECHPRIEST and unit_type != UnitType.SERVO_SKULL:
		_draw_ranged_weapon_layer()

	# 2. Character Body
	match unit_type:
		UnitType.ADMECH_TECHPRIEST: _draw_tech_priest()
		UnitType.SKITARII_MARSHAL:  _draw_marshal_body()
		UnitType.SKITARII_VANGUARD: _draw_vanguard_body()
		UnitType.SERVO_SKULL:       _draw_servo_skull()

	# 3. Ranged weapon front layer
	if not aiming_up and unit_type != UnitType.ADMECH_TECHPRIEST and unit_type != UnitType.SERVO_SKULL:
		_draw_ranged_weapon_layer()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 1. TECH-PRIEST ENGINSEER (HEAVY TWO-HANDED POWER-AXE CLEAVE SYSTEM)
# ==============================================================================
func _draw_tech_priest():
	# Ground Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 12), 11.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	# --- 1. MECHADENDRITES (REACT TO ATTACK STRIKE) ---
	var mecha_lunge = Vector2.ZERO
	if is_attacking:
		var t = attack_progress
		if t >= 0.2 and t <= 0.75:
			var s_t = (t - 0.2) / 0.55
			mecha_lunge = Vector2(sin(s_t * PI) * 8.0, 0.0)

	# Left & Right Mechadendrites
	draw_polyline(PackedVector2Array([Vector2(-4, -6), Vector2(-11, -16) - mecha_lunge * 0.5, Vector2(-5, -24) + mecha_lunge]), C_STEEL_MID, 3.5)
	draw_polyline(PackedVector2Array([Vector2(4, -6), Vector2(11, -16) - mecha_lunge * 0.5, Vector2(5, -24) + mecha_lunge]), C_STEEL_MID, 3.5)
	draw_circle(Vector2(-5, -24) + mecha_lunge, 2.2, C_BRASS)
	draw_circle(Vector2(5, -24) + mecha_lunge, 2.2, C_BRASS)

	# --- 2. ROBE BODY ---
	match current_facing:
		BodyFacing.BACK:
			var robe_b = PackedVector2Array([Vector2(-8, -6), Vector2(8, -6), Vector2(11, 10), Vector2(-11, 10)])
			draw_colored_polygon(robe_b, C_MARS_RED)
			var cl_b = robe_b.duplicate(); cl_b.append(robe_b[0])
			draw_polyline(cl_b, C_OUTLINE, 1.4)
			draw_line(Vector2(-11, 8), Vector2(11, 8), C_WHITE_TRIM, 2.0)

			draw_rect(Rect2(-5, -12, 10, 8), C_STEEL_DARK)
			draw_circle(Vector2(-2.5, -12), 1.8, C_COPPER)
			draw_circle(Vector2(2.5, -12), 1.8, C_COPPER)
			draw_circle(Vector2(0, -7), 6.0, C_MARS_RED)

		BodyFacing.FRONT:
			var robe_f = PackedVector2Array([Vector2(-8, -6), Vector2(8, -6), Vector2(11, 10), Vector2(-11, 10)])
			draw_colored_polygon(robe_f, C_MARS_RED)
			var cl_f = robe_f.duplicate(); cl_f.append(robe_f[0])
			draw_polyline(cl_f, C_OUTLINE, 1.4)
			draw_line(Vector2(-11, 8), Vector2(11, 8), C_WHITE_TRIM, 2.0)

			# Bionic Chestplate
			draw_rect(Rect2(-5, -4, 10, 9), C_STEEL_DARK)
			draw_rect(Rect2(-5, -4, 10, 9), C_BRASS, false, 1.0)
			draw_circle(Vector2(0, 0), 2.2, C_BRASS)

			# Hood & Optics
			draw_circle(Vector2(0, -7), 6.2, C_MARS_RED)
			draw_circle(Vector2(0, -7), 6.2, C_OUTLINE, false, 1.2)
			draw_rect(Rect2(-2, -5, 4, 3), C_BRASS)
			draw_circle(Vector2(-2.5, -8), 1.6, C_CYAN)
			draw_circle(Vector2(2.5, -8), 1.6, C_CYAN)
			draw_purity_seal(Vector2(-6, -2), 6.0)

		BodyFacing.SIDE:
			var robe_s = PackedVector2Array([Vector2(2, -6), Vector2(-9, -6), Vector2(-9, 10), Vector2(6, 10)])
			draw_colored_polygon(robe_s, C_MARS_RED)
			var cl_s = robe_s.duplicate(); cl_s.append(robe_s[0])
			draw_polyline(cl_s, C_OUTLINE, 1.4)
			draw_line(Vector2(-9, 8), Vector2(6, 8), C_WHITE_TRIM, 2.0)

			var hood_p = PackedVector2Array([Vector2(-3, -13), Vector2(6, -7), Vector2(-3, -1)])
			draw_colored_polygon(hood_p, C_MARS_RED)
			draw_polyline(hood_p, C_OUTLINE, 1.2)
			draw_circle(Vector2(3.5, -7), 1.8, C_CYAN)

	# --- 3. TWO-HANDED POWER-AXE (RESTING STANCE VS. ACTIVE PHYSICAL CLEAVE) ---
	if not is_attacking:
		# IDLE STANCE: Heavy Power-Axe rests majestically over shoulder
		var haft_start = Vector2(4, 8)
		var haft_end = Vector2(8, -18)
		draw_line(haft_start, haft_end, C_STEEL_DARK, 3.5)
		draw_line(haft_start, haft_end, C_BRASS, 1.5)

		# Opus Machina Brass Cog Head
		var axe_head = haft_end
		draw_circle(axe_head, 4.5, C_BRASS)
		draw_circle(axe_head, 2.5, C_STEEL_DARK)

		# Power Blade Resting Upward
		var blade = PackedVector2Array([
			axe_head + Vector2(-5, -4),
			axe_head + Vector2(6, -8),
			axe_head + Vector2(3, 4)
		])
		draw_colored_polygon(blade, C_CYAN)
		draw_polyline(blade, C_OUTLINE, 1.0)
	else:
		# ACTIVE CLEAVE ANIMATION: Full physical momentum slash across 130° cone
		_draw_axe_cleave_strike()

func _draw_axe_cleave_strike():
	var t = attack_progress # 0.0 -> 1.0
	var rel_strike_angle = attack_strike_angle
	if is_facing_left:
		rel_strike_angle = PI - attack_strike_angle

	var cone = deg_to_rad(130.0)
	var current_angle = 0.0
	var reach = 26.0
	var pivot = Vector2(2, -4)

	if t < 0.2:
		# 1. WINDUP: Axe coils backward, charging with plasma
		var w_t = t / 0.2
		current_angle = rel_strike_angle - (cone * 0.5) - (sin(w_t * PI * 0.5) * deg_to_rad(20.0))
		reach = 22.0
	elif t <= 0.75:
		# 2. POWER SLASH: Axe sweeps powerfully across forward cone
		var s_t = (t - 0.2) / 0.55
		var eased_s = pow(s_t, 2.2) # Explosive acceleration & follow-through
		current_angle = rel_strike_angle - (cone * 0.5) + (eased_s * cone)
		reach = 26.0 + sin(s_t * PI) * 4.0 # Lunges forward

		# Blazing Crescent Plasma Trail Wake
		var trail_start = current_angle - deg_to_rad(35.0)
		draw_arc(pivot, reach + 2.0, trail_start, current_angle, 8, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.65), 5.0)
		draw_arc(pivot, reach + 2.0, trail_start, current_angle, 8, Color.WHITE, 2.0)
	else:
		# 3. RECOVERY: Decelerates and transitions back to shoulder rest
		var r_t = (t - 0.75) / 0.25
		current_angle = rel_strike_angle + (cone * 0.5) + (sin(r_t * PI * 0.5) * deg_to_rad(10.0))
		reach = 24.0 - (r_t * 2.0)

	var axe_dir = Vector2.RIGHT.rotated(current_angle)
	var perp = axe_dir.orthogonal()
	var axe_shaft_end = pivot + axe_dir * reach

	# Physical Sweeping Axe Shaft
	draw_line(pivot, axe_shaft_end, C_STEEL_DARK, 4.0)
	draw_line(pivot, axe_shaft_end, C_BRASS, 1.8)

	# Opus Machina Cog Head
	var head_pos = axe_shaft_end - (axe_dir * 3.0)
	draw_circle(head_pos, 5.0, C_BRASS)
	draw_circle(head_pos, 2.5, C_STEEL_DARK)

	# Flaring Energy Blade
	var energy_flare = 1.0 + attack_flash * 0.5
	var blade_pts = PackedVector2Array([
		head_pos + perp * (9.0 * energy_flare) - axe_dir * 3.0,
		head_pos + perp * (11.0 * energy_flare) + axe_dir * 5.0,
		head_pos - axe_dir * 3.0
	])
	draw_colored_polygon(blade_pts, C_CYAN)
	draw_polyline(blade_pts, Color.WHITE, 1.2)

# ==============================================================================
# RANGED WEAPON LAYER (MARSHAL & VANGUARD)
# ==============================================================================
func _draw_ranged_weapon_layer():
	var shoulder = Vector2(5, -4) if current_facing != BodyFacing.SIDE else Vector2(2, -4)
	var rel_angle = aim_angle
	if is_facing_left:
		rel_angle = PI - aim_angle

	var arm_dir = Vector2.RIGHT.rotated(rel_angle)

	match unit_type:
		UnitType.SKITARII_MARSHAL:
			# Archeotech Radium Serpenta Pistol
			var p_root = shoulder + arm_dir * 2.0
			var p_tip = shoulder + arm_dir * 14.0
			draw_line(p_root, p_tip, C_STEEL_MID, 3.2)
			draw_line(p_root, p_tip, C_BRASS, 1.2)
			draw_rect(Rect2(p_root + arm_dir * 4.0 - Vector2(1.5, 1.5), Vector2(3, 3)), C_BRASS_LIGHT)
			draw_circle(p_root + arm_dir * 6.0, 1.5, C_CYAN)

		UnitType.SKITARII_VANGUARD:
			# Radium Carbine
			var r_root = shoulder - arm_dir * 2.0
			var r_tip = shoulder + arm_dir * 16.0
			draw_line(r_root, r_tip, C_STEEL_DARK, 3.5)
			draw_line(r_root + arm_dir * 4.0, r_tip, C_BRASS, 1.2)
			draw_circle(r_root + arm_dir * 7.0, 2.0, C_RAD_GREEN)

# ==============================================================================
# SKITARII MARSHAL, VANGUARD & SERVO-SKULL
# ==============================================================================
func _draw_marshal_body():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 10.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match current_facing:
		BodyFacing.BACK:
			var cape_b = PackedVector2Array([Vector2(-7, -6), Vector2(7, -6), Vector2(12, 12), Vector2(-12, 12)])
			draw_colored_polygon(cape_b, C_MARS_DARK)
			var cl_cb = cape_b.duplicate(); cl_cb.append(cape_b[0])
			draw_polyline(cl_cb, C_BRASS, 1.4)
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
			draw_circle(Vector2(0, 2), 1.8, C_BRASS_LIGHT)
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

func _draw_vanguard_body():
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 10), 9.0, Color(0.02, 0.02, 0.04, 0.45))
	draw_set_transform(Vector2.ZERO, 0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	match current_facing:
		BodyFacing.BACK:
			var coat_b = PackedVector2Array([Vector2(-6, -5), Vector2(6, -5), Vector2(9, 11), Vector2(-9, 11)])
			draw_colored_polygon(coat_b, C_MARS_RED)
			draw_polyline(coat_b, C_WHITE_TRIM, 1.4)
			draw_rect(Rect2(-4, -10, 8, 8), C_STEEL_DARK)
			draw_line(Vector2(3, -10), Vector2(3, -20), C_STEEL_LIGHT, 1.5)
			draw_circle(Vector2(0, -6), 4.8, C_BRASS)

		BodyFacing.FRONT:
			var coat_f = PackedVector2Array([Vector2(-6, -4), Vector2(6, -4), Vector2(8, 11), Vector2(-8, 11)])
			draw_colored_polygon(coat_f, C_MARS_RED)
			draw_polyline(coat_f, C_WHITE_TRIM, 1.4)
			draw_circle(Vector2(0, -6), 5.2, C_BRASS)
			draw_circle(Vector2(-2.2, -6), 1.8, C_RAD_GREEN)
			draw_circle(Vector2(2.2, -6), 1.8, C_RAD_GREEN)
			draw_rect(Rect2(-2, -3, 4, 3), C_COPPER)

		BodyFacing.SIDE:
			var coat_s = PackedVector2Array([Vector2(3, -5), Vector2(-8, -6), Vector2(-6, 11), Vector2(3, 7)])
			draw_colored_polygon(coat_s, C_MARS_RED)
			draw_polyline(coat_s, C_WHITE_TRIM, 1.4)
			draw_circle(Vector2(0, -6), 4.8, C_BRASS)
			draw_circle(Vector2(3, -6), 1.8, C_RAD_GREEN)
			draw_circle(Vector2(1, -3), 1.5, C_COPPER)

func _draw_servo_skull():
	draw_rect(Rect2(-3, -11, 6, 4), C_STEEL_DARK)
	draw_line(Vector2(0, -11), Vector2(0, -14), C_BRASS, 1.5)
	draw_circle(Vector2.ZERO, 7.0, C_IVORY)
	draw_circle(Vector2.ZERO, 7.0, C_OUTLINE, false, 1.2)
	draw_arc(Vector2.ZERO, 6.4, -PI * 0.75, PI * 0.25, 8, C_BRASS, 2.0)
	draw_circle(Vector2(2.5, -1), 2.8, C_STEEL_DARK)
	draw_circle(Vector2(2.5, -1), 1.8, C_CYAN)
	draw_circle(Vector2(3.0, -1.5), 0.7, Color.WHITE)
	draw_rect(Rect2(1, 3, 4, 3), C_STEEL_DARK)
	draw_line(Vector2(5, 4), Vector2(11, 4), C_BRASS, 1.8)
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

		# Player Command Halo
		var parent_node = p.get_parent()
		if parent_node and parent_node.is_in_group("players"):
			var aura = 0.55 + sin(p.anim_time * 3.0) * 0.2
			draw_arc(Vector2.ZERO, 16.0, 0, TAU, 24, Color(0.20, 0.88, 1.0, 0.45 * aura), 1.5)

		match p.unit_type:
			0: # Tech-Priest
				if p.current_facing != BodyFacing.BACK:
					var ep = Vector2(3.5, -7) if p.current_facing == BodyFacing.SIDE else Vector2(0, -8)
					draw_circle(ep, 2.2, Color(0.20, 0.88, 1.0, 0.9))
					draw_circle(ep, 4.0, Color(0.20, 0.88, 1.0, 0.35))
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

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
