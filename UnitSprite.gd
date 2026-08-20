@tool 
extends Node2D 

enum UnitType { ADMECH_TECHPRIEST, SKITARII_MARSHAL, SKITARII_VANGUARD, SERVO_SKULL } 

var anim_time: float = 0.0
var attack_flash: float = 0.0

@export var unit_type: UnitType = UnitType.SKITARII_VANGUARD: 
	set(val): 
		unit_type = val 
		queue_redraw()
		if is_instance_valid(glow_layer): glow_layer.queue_redraw()

var glow_layer: Node2D = null

const COLOR_MARS_DARK = Color(0.35, 0.04, 0.04)
const COLOR_MARS_RED = Color(0.72, 0.12, 0.08)
const COLOR_WHITE_TRIM = Color(0.92, 0.92, 0.88)
const COLOR_BRONZE = Color(0.7, 0.48, 0.22)
const COLOR_BRASS = Color(0.85, 0.65, 0.25)
const COLOR_STEEL = Color(0.55, 0.58, 0.62)
const COLOR_DARK_STEEL = Color(0.25, 0.28, 0.32)
const COLOR_CYAN_GLOW = Color(0.15, 0.9, 1.0)
const COLOR_RAD_GREEN = Color(0.2, 0.98, 0.35)
const COLOR_PURITY_PAPER = Color(0.88, 0.85, 0.75)
const COLOR_PURITY_WAX = Color(0.7, 0.1, 0.1)

func _ready() -> void:
	_setup_glow_layer()
	queue_redraw()

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
	var bob_amount = 0.55 + minf(movement / 350.0, 1.0) * 1.1
	position.y = sin(anim_time * (3.0 + movement * 0.012)) * bob_amount
	
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func trigger_attack_fx() -> void:
	attack_flash = 1.0
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func _draw():
	match unit_type: 
		UnitType.ADMECH_TECHPRIEST: _draw_tech_priest() 
		UnitType.SKITARII_MARSHAL: _draw_marshal() 
		UnitType.SKITARII_VANGUARD: _draw_vanguard() 
		UnitType.SERVO_SKULL: _draw_servo_skull()

func _draw_tech_priest(): 
	draw_polyline(PackedVector2Array([Vector2(-6, -8), Vector2(-14, -18), Vector2(-4, -26)]), COLOR_STEEL, 3.5)
	draw_circle(Vector2(-4, -26), 3.5, COLOR_BRONZE)
	draw_polyline(PackedVector2Array([Vector2(-8, 6), Vector2(-18, 14), Vector2(-8, 22)]), COLOR_STEEL, 4.0)
	draw_line(Vector2(-8, 22), Vector2(-2, 19), COLOR_STEEL, 2.5)
	draw_line(Vector2(-8, 22), Vector2(-2, 25), COLOR_STEEL, 2.5)
	draw_circle(Vector2.ZERO, 15.0, COLOR_MARS_DARK)
	draw_circle(Vector2.ZERO, 13.0, COLOR_MARS_RED)
	draw_arc(Vector2.ZERO, 13.0, 0, TAU, 12, COLOR_WHITE_TRIM, 2.0)
	draw_rect(Rect2(-10, -11, 8, 22), COLOR_DARK_STEEL)
	draw_circle(Vector2(0, -9), 4.5, COLOR_BRONZE)
	draw_circle(Vector2(0, 9), 4.5, COLOR_BRONZE)
	draw_line(Vector2(-4, 12), Vector2(18, 12), COLOR_DARK_STEEL, 2.5)
	draw_arc(Vector2(17, 12), 5.0, PI * 0.25, PI * 0.75, 4, COLOR_BRONZE, 3.0)
	draw_circle(Vector2(2, 0), 7.5, COLOR_MARS_RED)
	draw_circle(Vector2(4, 0), 4.0, COLOR_STEEL)

func _draw_marshal(): 
	var cape = PackedVector2Array([Vector2(2, -10), Vector2(-16, -15), Vector2(-12, 0), Vector2(-16, 15), Vector2(2, 10)])
	draw_polygon(cape, [COLOR_MARS_DARK])
	draw_polyline(cape, COLOR_BRASS, 2.0)
	draw_circle(Vector2.ZERO, 9.5, COLOR_MARS_RED)
	draw_circle(Vector2(1, 0), 7.0, COLOR_BRONZE)
	draw_line(Vector2(2, 6), Vector2(22, 6), COLOR_STEEL, 2.5)
	draw_rect(Rect2(6, 4, 6, 4), COLOR_BRASS)
	draw_circle(Vector2(3, 0), 5.5, COLOR_STEEL)
	draw_rect(Rect2(1, -7, 3, 14), COLOR_BRASS)

func _draw_vanguard(): 
	var coat = PackedVector2Array([Vector2(6, -7), Vector2(-10, -10), Vector2(-7, 0), Vector2(-10, 10), Vector2(6, 7)])
	draw_polygon(coat, [COLOR_MARS_RED])
	draw_polyline(coat, COLOR_WHITE_TRIM, 1.5)
	draw_circle(Vector2.ZERO, 7.5, COLOR_MARS_DARK)
	draw_rect(Rect2(-8, -5, 4, 10), COLOR_BRONZE)
	draw_line(Vector2(-1, 4), Vector2(20, 4), COLOR_DARK_STEEL, 2.5)
	draw_line(Vector2(8, 2), Vector2(8, 6), COLOR_BRASS, 2.0)
	draw_line(Vector2(11, 2), Vector2(11, 6), COLOR_BRASS, 2.0)
	draw_line(Vector2(14, 2), Vector2(14, 6), COLOR_BRASS, 2.0)
	draw_circle(Vector2(2, -1), 5.5, COLOR_BRONZE)
	draw_rect(Rect2(4, -5, 2, 8), COLOR_BRASS)

func _draw_servo_skull():
	draw_rect(Rect2(-3, -11, 6, 4), COLOR_DARK_STEEL)
	draw_line(Vector2(0, -11), Vector2(0, -14), COLOR_BRASS, 1.5)
	draw_circle(Vector2.ZERO, 8.0, COLOR_WHITE_TRIM)
	draw_circle(Vector2.ZERO, 7.0, COLOR_STEEL)
	draw_arc(Vector2.ZERO, 7.2, -PI * 0.75, PI * 0.25, 8, COLOR_BRASS, 2.5)
	draw_circle(Vector2(3, -1), 3.5, COLOR_DARK_STEEL)
	draw_rect(Rect2(2, 3, 5, 3), COLOR_DARK_STEEL)
	draw_line(Vector2(7, 4), Vector2(14, 4), COLOR_BRASS, 2.0)
	draw_line(Vector2(-4, 3), Vector2(-6, 8), COLOR_PURITY_WAX, 2.0)
	draw_rect(Rect2(-8, 8, 5, 8), COLOR_PURITY_PAPER)
	draw_circle(Vector2(-5.5, 9.5), 1.5, COLOR_PURITY_WAX)

# --- UNSHADED NIGHT GLOW OVERLAY FOR PLAYERS & UNITS ---
class UnitGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		# 1. Player Command Halo (Glows at Night)
		var parent_node = p.get_parent()
		if parent_node and parent_node.is_in_group("players"):
			var aura = 0.55 + sin(p.anim_time * 3.0) * 0.2
			draw_arc(Vector2.ZERO, 20.0, 0, TAU, 24, Color(0.20, 0.88, 1.0, 0.45 * aura), 1.8)
			draw_circle(Vector2(0, 20), 2.5, Color(0.20, 0.88, 1.0, 0.9))

		# 2. Cybernetic Visors & Lenses
		match p.unit_type:
			0: # Tech-Priest Lenses & Axe Energy
				var lens_pulse = 0.7 + sin(p.anim_time * 4.0) * 0.3
				draw_circle(Vector2(-4, -26), 4.0, Color(0.20, 0.88, 1.0, 0.35 * lens_pulse))
				draw_circle(Vector2(-4, -26), 2.0, Color(0.20, 0.88, 1.0))
				draw_circle(Vector2(6, -2), 2.0, Color(0.20, 0.88, 1.0))
				draw_circle(Vector2(6, 2), 1.5, Color(0.20, 0.88, 1.0))
				# Axe Cyan Energy Blade
				var axe_blade = PackedVector2Array([Vector2(14, 12), Vector2(22, 3), Vector2(20, 12)])
				draw_polygon(axe_blade, [Color(0.20, 0.88, 1.0, 0.85 + p.attack_flash * 0.15)])
			1: # Marshal Visor & Archeotech Pistol
				var skull_pos = Vector2(6, -16) + Vector2(sin(p.anim_time * 2.2) * 2.0, cos(p.anim_time * 2.2) * 1.5)
				draw_circle(skull_pos + Vector2(1, -1), 1.8, Color(0.20, 0.88, 1.0))
				draw_circle(Vector2(22, 6), 3.0 + p.attack_flash * 2.5, Color(0.20, 0.88, 1.0, 0.85))
				draw_line(Vector2(5, -2), Vector2(7, -2), Color(0.20, 0.88, 1.0), 2.0)
				draw_line(Vector2(5, 2), Vector2(7, 2), Color(0.20, 0.88, 1.0), 2.0)
			2: # Vanguard Radium Green Visor & Magazine
				var rad_pulse = 0.65 + sin(p.anim_time * 5.0) * 0.25
				draw_circle(Vector2(7, 7), 3.5 + rad_pulse, Color(0.2, 0.98, 0.35, 0.8))
				draw_circle(Vector2(20, 4), 2.5 + p.attack_flash * 3.0, Color(0.2, 0.98, 0.35, 0.9))
				draw_line(Vector2(5, -2), Vector2(7, 0), Color(0.2, 0.98, 0.35), 2.0)
				draw_line(Vector2(7, 0), Vector2(5, 2), Color(0.2, 0.98, 0.35), 2.0)
			3: # Servo-Skull Main Lens
				draw_circle(Vector2(3, -1), 4.0, Color(0.20, 0.88, 1.0, 0.3))
				draw_circle(Vector2(3, -1), 2.5, Color(0.20, 0.88, 1.0))
				draw_circle(Vector2(3.5, -1.5), 1.0, Color.WHITE)
				draw_circle(Vector2(14, 4), 1.5, Color(0.20, 0.88, 1.0))
