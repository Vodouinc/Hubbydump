extends Node2D

enum BuildingType { BARRICADE, GENERATOR, TURRET, MANUFACTORUM }

@export var type: BuildingType = BuildingType.BARRICADE:
	set(val):
		type = val
		queue_redraw()

# Animation tracking for Generator pulse and idle visual animation
var pulse_scale: float = 0.0
var idle_timer: float = 0.0
var turret_rotation: float = 0.0
var turret_upgrade_level: int = 0

func _process(delta):
	idle_timer += delta
	var needs_redraw = false

	if pulse_scale > 0.0:
		pulse_scale = max(0.0, pulse_scale - delta * 1.8)
		needs_redraw = true
		
	# Redraw occasionally for ambient hum/plasma animation
	if type == BuildingType.GENERATOR or type == BuildingType.MANUFACTORUM or type == BuildingType.BARRICADE:
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

func pulse_generator():
	pulse_scale = 1.0
	queue_redraw()

func _draw():
	match type:
		BuildingType.BARRICADE:
			_draw_barricade()
		BuildingType.GENERATOR:
			_draw_generator()
		BuildingType.TURRET:
			_draw_turret()
		BuildingType.MANUFACTORUM:
			_draw_manufactorum()

func _draw_barricade():
	var iron_dark = Color(0.1, 0.1, 0.13)
	var iron_mid = Color(0.22, 0.23, 0.27)
	var steel_edge = Color(0.65, 0.7, 0.75)
	var brass_gold = Color(0.85, 0.68, 0.22)
	var warning_yellow = Color(0.9, 0.75, 0.15)
	var alert_red = Color(0.8, 0.15, 0.15)

	# --- Circular plasteel hardpoint ---
	draw_circle(Vector2.ZERO, 20.0, iron_dark)
	draw_arc(Vector2.ZERO, 20.0, 0, TAU, 20, brass_gold, 2.0)
	draw_circle(Vector2.ZERO, 15.5, iron_mid)
	draw_arc(Vector2.ZERO, 15.5, 0, TAU, 20, steel_edge, 1.5)

	# --- Curved blast-wall segments ---
	for angle_offset in [-2.1, 0.0, 2.1]:
		var start_angle = angle_offset - 0.62
		var end_angle = angle_offset + 0.62
		draw_arc(Vector2.ZERO, 13.0, start_angle, end_angle, 8, iron_dark, 6.0)
		draw_arc(Vector2.ZERO, 13.0, start_angle, end_angle, 8, steel_edge, 2.0)
		var marker = Vector2.RIGHT.rotated(angle_offset) * 13.0
		draw_circle(marker, 2.4, warning_yellow)

	# --- Central warning light & command rune ---
	draw_circle(Vector2.ZERO, 5.5, iron_dark)
	draw_circle(Vector2.ZERO, 5.5, brass_gold, false, 1.5)
	
	var core_glow = (sin(idle_timer * 3.5) + 1.0) * 0.5
	draw_circle(Vector2.ZERO, 2.5, Color(alert_red.r, alert_red.g, alert_red.b, 0.5 + core_glow * 0.5))

	# --- Radial anchor rivets ---
	for i in range(6):
		draw_circle(Vector2.RIGHT.rotated(float(i) * TAU / 6.0) * 17.0, 1.4, brass_gold)

func _draw_manufactorum():
	var iron_dark = Color(0.12, 0.12, 0.15)
	var iron_mid = Color(0.25, 0.26, 0.30)
	var mars_red = Color(0.65, 0.1, 0.1)
	var mars_red_dark = Color(0.4, 0.05, 0.05)
	var brass_gold = Color(0.85, 0.68, 0.22)
	var brass_dark = Color(0.5, 0.38, 0.1)
	var cyan_plasma = Color(0.2, 0.85, 1.0, 0.8)

	# --- Heavy Octagonal Foundation Plinth ---
	var base_poly = PackedVector2Array([
		Vector2(-36, -20), Vector2(-20, -36), Vector2(20, -36), Vector2(36, -20),
		Vector2(36, 20), Vector2(20, 36), Vector2(-20, 36), Vector2(-36, 20)
	])
	draw_colored_polygon(base_poly, iron_dark)
	var closed_base_poly = base_poly.duplicate()
	closed_base_poly.append(base_poly[0])
	draw_polyline(closed_base_poly, brass_dark, 2.5)

	# Corner Hazard Striping / Anchors
	for corner in [Vector2(-30, -30), Vector2(30, -30), Vector2(-30, 30), Vector2(30, 30)]:
		draw_rect(Rect2(corner - Vector2(4, 4), Vector2(8, 8)), iron_mid)
		draw_rect(Rect2(corner - Vector2(4, 4), Vector2(8, 8)), brass_gold, false, 1.0)

	# --- Gothic Sanctum Wings (Cruciform Structure) ---
	draw_rect(Rect2(-28, -24, 56, 48), mars_red_dark)
	draw_rect(Rect2(-24, -28, 48, 56), mars_red_dark)
	draw_rect(Rect2(-26, -22, 52, 44), mars_red)
	draw_rect(Rect2(-22, -26, 44, 52), mars_red)

	# Brass Trim Borders
	draw_rect(Rect2(-26, -22, 52, 44), brass_gold, false, 1.5)
	draw_rect(Rect2(-22, -26, 44, 52), brass_gold, false, 1.5)

	# --- Industrial Exhaust Chimneys / Spire Columns ---
	var chimney_positions = [Vector2(-20, -20), Vector2(20, -20), Vector2(-20, 20), Vector2(20, 20)]
	for pos in chimney_positions:
		draw_circle(pos, 6.0, iron_dark)
		draw_circle(pos, 6.0, brass_gold, false, 1.5)
		var heat_val = (sin(idle_timer * 3.0 + pos.x) + 1.0) * 0.5
		draw_circle(pos, 3.0, Color(1.0, 0.4, 0.1, 0.5 + heat_val * 0.4))

	# --- Central Opus Machina (Cogwheel Emblem) ---
	var cog_center = Vector2.ZERO
	var cog_radius = 14.0
	var num_teeth = 8

	for i in range(num_teeth):
		var angle = (i * TAU / num_teeth)
		var tooth_dir = Vector2.RIGHT.rotated(angle)
		var tooth_rect_center = cog_center + tooth_dir * cog_radius
		draw_set_transform(tooth_rect_center, angle, Vector2.ONE)
		draw_rect(Rect2(-2.5, -2.5, 5.0, 5.0), brass_gold)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	draw_circle(cog_center, cog_radius, iron_dark)
	draw_circle(cog_center, cog_radius, brass_gold, false, 2.0)

	var left_semi = PackedVector2Array()
	var right_semi = PackedVector2Array()
	for i in range(17):
		var a = -PI/2 + (i * PI / 16.0)
		left_semi.append(cog_center + Vector2(cos(a + PI), sin(a + PI)) * (cog_radius - 2))
		right_semi.append(cog_center + Vector2(cos(a), sin(a)) * (cog_radius - 2))

	draw_colored_polygon(left_semi, Color(0.9, 0.9, 0.9))
	draw_colored_polygon(right_semi, iron_mid)

	# Gothic Cathedral Lancet Arch Entrance
	var arch_poly = PackedVector2Array([
		Vector2(-6, 26), Vector2(-6, 18), Vector2(0, 12), Vector2(6, 18), Vector2(6, 26)
	])
	draw_colored_polygon(arch_poly, iron_dark)
	draw_polyline(arch_poly, brass_gold, 1.5)

	# Stained Glass Plasma Vent Window
	draw_circle(Vector2(0, -6), 4.0, cyan_plasma)
	draw_circle(Vector2(0, -6), 5.0, brass_gold, false, 1.0)

func _draw_generator():
	var iron_dark = Color(0.12, 0.12, 0.16)
	var iron_mid = Color(0.28, 0.30, 0.35)
	var brass_gold = Color(0.85, 0.65, 0.2)

	var plasma_cyan = Color(0.15, 0.8, 1.0)
	var plasma_white = Color(0.85, 0.98, 1.0)
	var glow_intensity = 0.4 + (pulse_scale * 0.6) + (sin(idle_timer * 4.0) * 0.1)

	# --- Base Hexagonal Heavy Plate ---
	var hex_poly = PackedVector2Array()
	for i in range(6):
		var angle = i * TAU / 6.0
		hex_poly.append(Vector2(cos(angle), sin(angle)) * 22.0)
	draw_colored_polygon(hex_poly, iron_dark)
	var closed_hex_poly = hex_poly.duplicate()
	closed_hex_poly.append(hex_poly[0])
	draw_polyline(closed_hex_poly, brass_gold, 2.0)

	# --- Radiator Fins ---
	for i in range(6):
		var angle = i * TAU / 6.0
		var fin_dir = Vector2.RIGHT.rotated(angle)
		draw_line(fin_dir * 14.0, fin_dir * 25.0, iron_mid, 4.0)
		draw_line(fin_dir * 14.0, fin_dir * 25.0, brass_gold, 1.5)
		draw_circle(fin_dir * 23.0, 2.0, Color(1.0, 0.5, 0.1, 0.8))

	# --- Outer Containment Vessel Ring ---
	draw_circle(Vector2.ZERO, 15.0, iron_mid)
	draw_circle(Vector2.ZERO, 15.0, brass_gold, false, 2.0)

	# --- Pulsing Archeotech Plasma Field ---
	var aura_radius = 12.0 + (pulse_scale * 8.0)
	draw_circle(Vector2.ZERO, aura_radius, Color(plasma_cyan.r, plasma_cyan.g, plasma_cyan.b, glow_intensity * 0.4))

	draw_circle(Vector2.ZERO, 10.0, Color(0.05, 0.2, 0.35))
	draw_arc(Vector2.ZERO, 10.0, 0, TAU, 24, plasma_cyan, 2.0)

	for i in range(3):
		var arc_start = idle_timer * 3.0 + (i * TAU / 3.0)
		draw_arc(Vector2.ZERO, 7.0, arc_start, arc_start + 1.8, 12, plasma_white, 2.0)

	var core_r = 4.0 + (pulse_scale * 4.0)
	draw_circle(Vector2.ZERO, core_r, plasma_white)
	draw_circle(Vector2.ZERO, core_r * 0.5, Color(1, 1, 1))

func _draw_turret():
	var iron_dark = Color(0.12, 0.12, 0.15)
	var iron_mid = Color(0.3, 0.32, 0.36)
	var mars_red = Color(0.7, 0.1, 0.1)
	var brass_gold = Color(0.85, 0.68, 0.22)

	# --- Ground Mount Ring (Stays locked to the floor, does NOT rotate) ---
	draw_circle(Vector2.ZERO, 19.0, iron_dark)
	draw_circle(Vector2.ZERO, 19.0, brass_gold, false, 2.0)
	for level in range(turret_upgrade_level):
		var ring_radius = 22.0 + level * 3.0
		var arc_start = idle_timer * (1.5 + level * 0.25) + level * 1.4
		draw_arc(Vector2.ZERO, ring_radius, arc_start, arc_start + PI * 1.35, 16, Color(0.25, 0.88, 1.0, 0.82), 1.5)

	for i in range(8):
		var a = i * TAU / 8.0
		var bolt_pos = Vector2(cos(a), sin(a)) * 16.5
		draw_circle(bolt_pos, 1.5, brass_gold)

	# --- ROTATING UPPER ASSEMBLY (Heavy Turret Housing & Barrels) ---
	draw_set_transform(Vector2.ZERO, turret_rotation, Vector2.ONE)

	# Twin Heavy Barrels
	draw_rect(Rect2(2, -9, 18, 5), iron_dark)
	draw_rect(Rect2(2, 4, 18, 5), iron_dark)
	draw_rect(Rect2(16, -10, 5, 7), iron_mid)
	draw_rect(Rect2(16, 3, 5, 7), iron_mid)
	draw_rect(Rect2(18, -9.5, 2, 6), brass_gold)
	draw_rect(Rect2(18, 3.5, 2, 6), brass_gold)

	# Armored Turret Housing
	var housing_poly = PackedVector2Array([
		Vector2(-14, -14), Vector2(2, -14), Vector2(10, -7),
		Vector2(10, 7), Vector2(2, 14), Vector2(-14, 14)
	])
	draw_colored_polygon(housing_poly, mars_red)
	var closed_housing_poly = housing_poly.duplicate()
	closed_housing_poly.append(housing_poly[0])
	draw_polyline(closed_housing_poly, brass_gold, 2.0)

	# Ammo Feeder Drums & Vent Grilles
	draw_rect(Rect2(-10, -17, 10, 3), iron_mid)
	draw_rect(Rect2(-10, 14, 10, 3), iron_mid)
	draw_rect(Rect2(-10, -17, 10, 3), brass_gold, false, 1.0)
	draw_rect(Rect2(-10, 14, 10, 3), brass_gold, false, 1.0)
	draw_rect(Rect2(-12, -8, 4, 16), iron_dark)
	draw_line(Vector2(-10, -6), Vector2(-10, 6), brass_gold, 1.5)

	# Omnissiah Targeter Lens
	draw_circle(Vector2(3, 0), 4.5, iron_dark)
	draw_circle(Vector2(3, 0), 4.5, brass_gold, false, 1.0)
	var eye_pulse = (sin(idle_timer * 5.0) + 1.0) * 0.5
	draw_circle(Vector2(4, 0), 2.5, Color(1.0, 0.2, 0.2, 0.8 + eye_pulse * 0.2))
	draw_circle(Vector2(4.8, -0.8), 0.8, Color(1, 1, 1))

	# Reset transform so subsequent drawings aren't affected
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
