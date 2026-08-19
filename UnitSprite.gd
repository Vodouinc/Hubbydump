@tool 
extends Node2D 

enum UnitType { 
	ADMECH_TECHPRIEST, 
	SKITARII_MARSHAL, 
	SKITARII_VANGUARD,
	SERVO_SKULL # Added here!
} 

var anim_time: float = 0.0
var attack_flash: float = 0.0

@export var unit_type: UnitType = UnitType.SKITARII_VANGUARD: 
	set(val): 
		unit_type = val 
		queue_redraw() 

# Core Palette Constants
const COLOR_MARS_DARK = Color(0.35, 0.04, 0.04)
const COLOR_MARS_RED = Color(0.72, 0.12, 0.08)
const COLOR_WHITE_TRIM = Color(0.92, 0.92, 0.88)
const COLOR_BRONZE = Color(0.7, 0.48, 0.22)
const COLOR_BRASS = Color(0.85, 0.65, 0.25)
const COLOR_STEEL = Color(0.55, 0.58, 0.62)
const COLOR_DARK_STEEL = Color(0.25, 0.28, 0.32)
const COLOR_CYAN_GLOW = Color(0.15, 0.9, 1.0)
const COLOR_RAD_GREEN = Color(0.2, 0.98, 0.35)
const COLOR_PURITY_PAPER = Color(0.88, 0.85, 0.75) # Aged parchment
const COLOR_PURITY_WAX = Color(0.7, 0.1, 0.1)     # Red sealing wax

func _process(delta: float) -> void:
	anim_time += delta
	attack_flash = maxf(0.0, attack_flash - delta * 5.5)
	var parent_node = get_parent()
	var movement: float = parent_node.get("velocity").length() if parent_node and "velocity" in parent_node else 0.0
	var bob_amount = 0.55 + minf(movement / 350.0, 1.0) * 1.1
	position.y = sin(anim_time * (3.0 + movement * 0.012)) * bob_amount
	queue_redraw()

func trigger_attack_fx() -> void:
	attack_flash = 1.0
	queue_redraw()

func _draw(): 
	match unit_type: 
		UnitType.ADMECH_TECHPRIEST: 
			_draw_tech_priest() 
		UnitType.SKITARII_MARSHAL: 
			_draw_marshal() 
		UnitType.SKITARII_VANGUARD: 
			_draw_vanguard() 
		UnitType.SERVO_SKULL:
			_draw_servo_skull()

# -------------------------------------------------- 
# TECH-PRIEST ENGINSEER (Heavy, Mecha-Armored, Axe)
# -------------------------------------------------- 
func _draw_tech_priest(): 
	var lens_pulse = 0.7 + sin(anim_time * 4.0) * 0.3
	# 1. Back Servo-Arm (Top-left back)
	draw_polyline(PackedVector2Array([Vector2(-6, -8), Vector2(-14, -18), Vector2(-4, -26)]), COLOR_STEEL, 3.5)
	draw_circle(Vector2(-4, -26), 3.5, COLOR_BRONZE)
	draw_circle(Vector2(-4, -26), 1.5 + lens_pulse * 0.5, Color(COLOR_CYAN_GLOW, lens_pulse)) # Sensor lens

	# 2. Main Heavy Servo-Arm with Claw (Bottom-left back)
	draw_polyline(PackedVector2Array([Vector2(-8, 6), Vector2(-18, 14), Vector2(-8, 22)]), COLOR_STEEL, 4.0)
	draw_line(Vector2(-8, 22), Vector2(-2, 19), COLOR_STEEL, 2.5) # Upper claw pincher
	draw_line(Vector2(-8, 22), Vector2(-2, 25), COLOR_STEEL, 2.5) # Lower claw pincher

	# 3. Outer Red Robe Base & Cog Rim
	draw_circle(Vector2.ZERO, 15.0, COLOR_MARS_DARK)
	draw_circle(Vector2.ZERO, 13.0, COLOR_MARS_RED)
	draw_arc(Vector2.ZERO, 13.0, 0, TAU, 12, COLOR_WHITE_TRIM, 2.0) # Cog pattern trim

	# 4. Shoulder Pauldrons & Power Pack (Front/Back width)
	draw_rect(Rect2(-10, -11, 8, 22), COLOR_DARK_STEEL) # Central Augment Pack
	draw_circle(Vector2(0, -9), 4.5, COLOR_BRONZE)        # Left Shoulder
	draw_circle(Vector2(0, 9), 4.5, COLOR_BRONZE)         # Right Shoulder

	# 5. Omnissian Axe (Wielded on lower right, facing forward)
	# Shaft
	draw_line(Vector2(-4, 12), Vector2(18, 12), COLOR_DARK_STEEL, 2.5)
	# Axe Head (Cyan energy blade facing top-right)
	var axe_blade = PackedVector2Array([Vector2(14, 12), Vector2(22, 3), Vector2(20, 12)])
	draw_polygon(axe_blade, [Color(COLOR_CYAN_GLOW, 0.75 + attack_flash * 0.25)])
	if attack_flash > 0.0:
		draw_arc(Vector2(12, 12), 15.0, -PI * 0.72, PI * 0.22, 10, Color(COLOR_CYAN_GLOW, attack_flash * 0.65), 2.5)
	# Half-Cog Counterweight (Facing bottom-right)
	draw_arc(Vector2(17, 12), 5.0, PI * 0.25, PI * 0.75, 4, COLOR_BRONZE, 3.0)

	# 6. Hood & Tech-Mask (Facing Right +X)
	draw_circle(Vector2(2, 0), 7.5, COLOR_MARS_RED)
	draw_circle(Vector2(4, 0), 4.0, COLOR_STEEL)
	# Ocular Augmetics (Glowing lenses)
	draw_circle(Vector2(6, -2), 1.8, COLOR_CYAN_GLOW)
	draw_circle(Vector2(6, 2), 1.2, COLOR_CYAN_GLOW)

# -------------------------------------------------- 
# SKITARII MARSHAL (Commander, Cape, Servo-Skull, Wand)
# -------------------------------------------------- 
func _draw_marshal(): 
	var cape_sway = sin(anim_time * 3.0) * 1.5
	# 1. Flowing Master-Clog Cape (Extending back-left)
	var cape = PackedVector2Array([
		Vector2(2, -10), Vector2(-16, -15 + cape_sway), Vector2(-12, 0), 
		Vector2(-16, 15 - cape_sway), Vector2(2, 10)
	])
	draw_polygon(cape, [COLOR_MARS_DARK])
	draw_polyline(cape, COLOR_BRASS, 2.0)

	# 2. Torso & Gold-Embossed Armor
	draw_circle(Vector2.ZERO, 9.5, COLOR_MARS_RED)
	draw_circle(Vector2(1, 0), 7.0, COLOR_BRONZE)

	# 3. Servo-Skull Companion (Hovering top-right)
	var skull_pos = Vector2(6, -16) + Vector2(sin(anim_time * 2.2) * 2.0, cos(anim_time * 2.2) * 1.5)
	draw_line(Vector2(-2, -6), skull_pos, COLOR_CYAN_GLOW, 1.0) # Energy tether
	draw_circle(skull_pos, 3.0, COLOR_WHITE_TRIM)                # Skull body
	draw_circle(skull_pos + Vector2(1, -1), 1.0, COLOR_CYAN_GLOW) # Lens

	# 4. Control Wand / Archeotech Pistol (Aimed Forward +X)
	draw_line(Vector2(2, 6), Vector2(22, 6), COLOR_STEEL, 2.5) # Barrel
	draw_circle(Vector2(22, 6), 2.5 + attack_flash * 2.0, Color(COLOR_CYAN_GLOW, 0.75 + attack_flash * 0.25))
	draw_rect(Rect2(6, 4, 6, 4), COLOR_BRASS)                   # Golden casing

	# 5. Marshal Crested Helmet (Facing Right +X)
	draw_circle(Vector2(3, 0), 5.5, COLOR_STEEL)
	# Transversal High Crest
	draw_rect(Rect2(1, -7, 3, 14), COLOR_BRASS)
	# Blue Command Visor Line
	draw_line(Vector2(5, -2), Vector2(7, -2), COLOR_CYAN_GLOW, 2.0)
	draw_line(Vector2(5, 2), Vector2(7, 2), COLOR_CYAN_GLOW, 2.0)

# -------------------------------------------------- 
# SKITARII VANGUARD (Infantry, Coat, Radium Carbine)
# -------------------------------------------------- 
func _draw_vanguard(): 
	var rad_pulse = 0.65 + sin(anim_time * 5.0) * 0.25
	# 1. Greatcoat Base (Facing Right +X)
	var coat = PackedVector2Array([
		Vector2(6, -7), Vector2(-10, -10), Vector2(-7, 0), 
		Vector2(-10, 10), Vector2(6, 7)
	])
	draw_polygon(coat, [COLOR_MARS_RED])
	draw_polyline(coat, COLOR_WHITE_TRIM, 1.5) # White interior lining trim

	# 2. Leather/Steel Torso & Backpack
	draw_circle(Vector2.ZERO, 7.5, COLOR_MARS_DARK)
	draw_rect(Rect2(-8, -5, 4, 10), COLOR_BRONZE) # Power generator pack on back

	# 3. Radium Carbine (Two-handed grip, pointing right +X)
	# Gun Stock & Barrel
	draw_line(Vector2(-1, 4), Vector2(20, 4), COLOR_DARK_STEEL, 2.5)
	# Radium Heat Vent Ribs
	draw_line(Vector2(8, 2), Vector2(8, 6), COLOR_BRASS, 2.0)
	draw_line(Vector2(11, 2),Vector2(11, 6), COLOR_BRASS, 2.0)
	draw_line(Vector2(14, 2), Vector2(14, 6), COLOR_BRASS, 2.0)
	# Round Glowing Radium Drum Magazine (Under barrel)
	draw_circle(Vector2(7, 7), 2.5 + rad_pulse, Color(COLOR_RAD_GREEN, 0.65 + rad_pulse * 0.25))
	# Muzzle Radiation Glow
	draw_circle(Vector2(20, 4), 1.5 + attack_flash * 2.5, Color(COLOR_RAD_GREEN, 0.7 + attack_flash * 0.3))

	# 4. Vanguard Helmet (Dome Helmet with Broad Front Crux)
	draw_circle(Vector2(2, -1), 5.5, COLOR_BRONZE)
	# Characteristic Vanguard Helmet Ridge (Transversal Front Crest)
	draw_rect(Rect2(4, -5, 2, 8), COLOR_BRASS)
	# Toxic Rad-Green Visor Slot
	draw_line(Vector2(5, -2), Vector2(7, 0), COLOR_RAD_GREEN, 2.0)
	draw_line(Vector2(7, 0), Vector2(5, 2), COLOR_RAD_GREEN, 2.0)

# -------------------------------------------------- 
# SERVO-SKULL COMPANION (Augmetic Skull, Antennas, Data-Spike)
# -------------------------------------------------- 
func _draw_servo_skull():
	# 1. Anti-Grav Engine / Top Exhaust Vent Mount
	draw_rect(Rect2(-3, -11, 6, 4), COLOR_DARK_STEEL)
	draw_line(Vector2(0, -11), Vector2(0, -14), COLOR_BRASS, 1.5) # Top antenna spike

	# 2. Cybernetic Cranium & Mechanical Plate Framing
	draw_circle(Vector2.ZERO, 8.0, COLOR_WHITE_TRIM)
	draw_circle(Vector2.ZERO, 7.0, COLOR_STEEL)
	draw_arc(Vector2.ZERO, 7.2, -PI * 0.75, PI * 0.25, 8, COLOR_BRASS, 2.5)

	# 3. Central Ocular Augment (Glowing Cyan Main Lens)
	draw_circle(Vector2(3, -1), 3.5, COLOR_DARK_STEEL)
	draw_circle(Vector2(3, -1), 2.0, COLOR_CYAN_GLOW)
	draw_circle(Vector2(3.5, -1.5), 0.7, Color.WHITE)

	# 4. Lower Jaw Augment & Data-Spike (Pointing Forward/Right)
	draw_rect(Rect2(2, 3, 5, 3), COLOR_DARK_STEEL)
	draw_line(Vector2(7, 4), Vector2(14, 4), COLOR_BRASS, 2.0)
	draw_circle(Vector2(14, 4), 1.0, COLOR_CYAN_GLOW)

	# 5. Purity Seal
	draw_line(Vector2(-4, 3), Vector2(-6, 8), COLOR_PURITY_WAX, 2.0)
	draw_rect(Rect2(-8, 8, 5, 8), COLOR_PURITY_PAPER)
	draw_circle(Vector2(-5.5, 9.5), 1.5, COLOR_PURITY_WAX)

	# 6. Attack Zap Animation (ONLY draws when attacking an enemy)
	# Note: We check if the parent CharacterBody2D has an active zap_visual_timer > 0
	var is_zapping = false
	if get_parent() and "zap_visual_timer" in get_parent():
		if get_parent().zap_visual_timer > 0:
			is_zapping = true

	if is_zapping:
		var zap_start = Vector2(14, 4) # Fires out from the data-spike tip!
		var zap_end = Vector2(40, randi() % 20 - 10) # Jitters toward a target vector/offset
		
		var points = PackedVector2Array()
		points.append(zap_start)
		
		var segments = 4
		for i in range(1, segments):
			var t = float(i) / float(segments)
			var lerped_pos = zap_start.lerp(zap_end, t)
			var jitter = Vector2(randf_range(-6, 6), randf_range(-6, 6)) # Crackling chaos
			points.append(lerped_pos + jitter)
			
		points.append(zap_end)
		
		# Draw striking electrical arc
		draw_polyline(points, Color(COLOR_CYAN_GLOW.r, COLOR_CYAN_GLOW.g, COLOR_CYAN_GLOW.b, 0.5), 4.0)
		draw_polyline(points, Color.WHITE, 1.5)
