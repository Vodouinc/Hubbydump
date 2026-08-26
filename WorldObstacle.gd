# res://WorldObstacle.gd
@tool
extends StaticBody2D
class_name WorldObstacle

enum ObstacleType {
	MOUNTAIN_CRAG = 0,
	IRONWOOD_TREE = 1,
	INDUSTRIAL_RUIN = 2,
	CRASHED_WARRECK = 3,
	RAD_CRYSTAL = 4,
	PROMETHEUM_PIPELINE = 5
}

@export var obstacle_type: ObstacleType = ObstacleType.MOUNTAIN_CRAG:
	set(val):
		obstacle_type = val
		queue_redraw()

@export var radius: float = 38.0:
	set(val):
		radius = val
		queue_redraw()

var seed_val: float = 0.0
var idle_anim_timer: float = 0.0
var glow_layer: Node2D = null

# --- 40K GRIMDARK PALETTE ---
const C_OUTLINE      := Color(0.04, 0.05, 0.07)
const C_BASALT_DARK  := Color(0.10, 0.09, 0.08)
const C_BASALT_MID   := Color(0.18, 0.16, 0.14)
const C_BASALT_LIGHT := Color(0.32, 0.28, 0.24)
const C_STEEL_DARK   := Color(0.12, 0.14, 0.18)
const C_STEEL_MID    := Color(0.24, 0.28, 0.35)
const C_STEEL_LIGHT  := Color(0.48, 0.54, 0.62)
const C_RUST_IRON    := Color(0.35, 0.20, 0.14)
const C_HAZARD_YEL   := Color(0.95, 0.78, 0.15)
const C_MARS_RED     := Color(0.68, 0.16, 0.14)
const C_BRASS        := Color(0.82, 0.62, 0.24)
const C_COPPER_ORE   := Color(0.88, 0.48, 0.22)
const C_FOLIAGE_DARK := Color(0.12, 0.22, 0.14)
const C_FOLIAGE_MID  := Color(0.20, 0.38, 0.22)
const C_VERDIGRIS    := Color(0.25, 0.55, 0.45)
const C_RAD_GREEN    := Color(0.20, 1.00, 0.45)
const C_RAD_EMERALD  := Color(0.10, 0.65, 0.30)
const C_CYAN         := Color(0.20, 0.88, 1.00)

func _ready() -> void:
	add_to_group("world_obstacles")
	seed_val = randf_range(1.0, 9999.0)

	_setup_collision()
	_setup_glow_layer()
	queue_redraw()

func _setup_collision() -> void:
	# Clean up any existing shapes
	for c in get_children():
		if c is CollisionShape2D: c.queue_free()

	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"

	match obstacle_type:
		ObstacleType.INDUSTRIAL_RUIN, ObstacleType.PROMETHEUM_PIPELINE:
			var rect_shape = RectangleShape2D.new()
			rect_shape.size = Vector2(radius * 1.8, radius * 1.2)
			col.shape = rect_shape
		ObstacleType.CRASHED_WARRECK:
			var rect_shape = RectangleShape2D.new()
			rect_shape.size = Vector2(radius * 1.6, radius * 1.4)
			col.shape = rect_shape
		_:
			var circle_shape = CircleShape2D.new()
			circle_shape.radius = radius * 0.82
			col.shape = circle_shape

	add_child(col)

func _setup_glow_layer() -> void:
	if not has_node("ObstacleGlowOverlay"):
		glow_layer = ObstacleGlowRenderer.new()
		glow_layer.name = "ObstacleGlowOverlay"
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		glow_layer.material = mat
		add_child(glow_layer)
	else:
		glow_layer = get_node("ObstacleGlowOverlay")

func _process(delta: float) -> void:
	idle_anim_timer += delta
	# Only refresh redraw for glowing/animated obstacles to save CPU
	if obstacle_type in [ObstacleType.RAD_CRYSTAL, ObstacleType.CRASHED_WARRECK, ObstacleType.PROMETHEUM_PIPELINE, ObstacleType.INDUSTRIAL_RUIN]:
		if is_instance_valid(glow_layer):
			glow_layer.queue_redraw()

func _draw() -> void:
	match obstacle_type:
		ObstacleType.MOUNTAIN_CRAG:
			_draw_mountain_crag()
		ObstacleType.IRONWOOD_TREE:
			_draw_ironwood_tree()
		ObstacleType.INDUSTRIAL_RUIN:
			_draw_industrial_ruin()
		ObstacleType.CRASHED_WARRECK:
			_draw_crashed_warreck()
		ObstacleType.RAD_CRYSTAL:
			_draw_rad_crystal()
		ObstacleType.PROMETHEUM_PIPELINE:
			_draw_prometheum_pipeline()

# ==============================================================================
# 1. LAYERED BASALT MOUNTAIN CRAG (With copper-ore striations)
# ==============================================================================
func _draw_mountain_crag() -> void:
	# Deep Ground Shadow
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.50))
	draw_circle(Vector2(4, 12), radius * 0.95, Color(0.01, 0.01, 0.02, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var num_pts = 11
	var outer_pts: PackedVector2Array = []
	var mid_pts: PackedVector2Array = []

	for i in range(num_pts):
		var a = (float(i) / float(num_pts)) * TAU
		var var_r = radius + (sin(a * 4.0 + seed_val) * (radius * 0.22)) + (cos(a * 2.0 + seed_val * 0.5) * (radius * 0.15))
		outer_pts.append(Vector2(cos(a), sin(a) * 0.70) * var_r)
		mid_pts.append(Vector2(cos(a), sin(a) * 0.70) * (var_r * 0.58) + Vector2(0, -var_r * 0.25))

	# Base Basalt Rockbody
	draw_colored_polygon(outer_pts, C_BASALT_DARK)
	var cl = outer_pts.duplicate(); cl.append(outer_pts[0])
	draw_polyline(cl, C_OUTLINE, 1.8)

	# Stepped Ridge Facet
	draw_colored_polygon(mid_pts, C_BASALT_MID)
	var cl_m = mid_pts.duplicate(); cl_m.append(mid_pts[0])
	draw_polyline(cl_m, C_BASALT_LIGHT, 1.2)

	# Mineral Striation Crevices & Copper Ore Veins
	for j in range(3):
		var p_start = outer_pts[(j * 3) % num_pts]
		var p_apex = mid_pts[(j * 3 + 1) % num_pts]
		draw_line(p_start, p_apex, C_OUTLINE, 2.0)
		draw_line(p_start, p_start.lerp(p_apex, 0.65), C_COPPER_ORE, 1.4)

# ==============================================================================
# 2. CYBERNETIC IRONWOOD GROVE (With verdigris foliage & data-vines)
# ==============================================================================
func _draw_ironwood_tree() -> void:
	# Ground Canopy Shadow
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2(6, 14), radius * 0.90, Color(0.01, 0.02, 0.03, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Twisted Bionic Trunk & Steel Roots
	for i in range(4):
		var root_a = i * (TAU / 4.0) + (seed_val * 0.1)
		var root_end = Vector2(cos(root_a), sin(root_a) * 0.6) * (radius * 0.65)
		draw_line(Vector2(0, 4), root_end, C_STEEL_DARK, 3.5)
		draw_line(Vector2(0, 4), root_end, C_RUST_IRON, 1.8)

	# Metal Trunk Core
	draw_circle(Vector2(0, 2), radius * 0.32, C_STEEL_DARK)
	draw_circle(Vector2(0, 2), radius * 0.32, C_OUTLINE, false, 1.2)

	# Dense Multi-Layered Cyber Foliage Clusters
	var clusters = [
		Vector2(-radius * 0.28, -radius * 0.28),
		Vector2(radius * 0.30, -radius * 0.20),
		Vector2(0, radius * 0.22),
		Vector2(0, -radius * 0.38)
	]

	for c in clusters:
		var cr = radius * 0.55
		draw_circle(c + Vector2(0, 2), cr, C_FOLIAGE_DARK)
		draw_circle(c, cr * 0.88, C_FOLIAGE_MID)
		draw_arc(c + Vector2(-2, -2), cr * 0.72, -PI * 0.8, 0.2, 12, C_VERDIGRIS, 1.8)

	# Hanging Fiber-Optic Data Cables
	for k in range(3):
		var vine_start = clusters[k % clusters.size()]
		var vine_end = vine_start + Vector2(sin(seed_val + k) * 6.0, radius * 0.45)
		draw_line(vine_start, vine_end, C_STEEL_DARK, 1.8)
		draw_circle(vine_end, 1.5, C_CYAN)

# ==============================================================================
# 3. GOTHIC INDUSTRIAL RUIN (With hazard chevrons & broken rebar)
# ==============================================================================
func _draw_industrial_ruin() -> void:
	var w = radius * 1.7
	var h = radius * 1.1
	var rect = Rect2(-w * 0.5, -h * 0.5, w, h)

	# Ground Shadow
	draw_rect(Rect2(rect.position + Vector2(4, 8), rect.size), Color(0.01, 0.01, 0.02, 0.55), true)

	# Concrete Wall Plinth
	draw_rect(rect, C_STEEL_DARK, true)
	draw_rect(rect, C_OUTLINE, false, 2.0)

	# Collapsed Section Cutout
	var notch = Rect2(rect.position.x + w * 0.2, rect.position.y - 2, w * 0.35, h * 0.4)
	draw_rect(notch, Color(0.08, 0.06, 0.06), true)

	# Exposed Rusty Rebar Rods
	for r in range(4):
		var rx = notch.position.x + 4.0 + (r * 6.0)
		draw_line(Vector2(rx, notch.position.y + notch.size.y), Vector2(rx + randf_range(-2, 2), notch.position.y - 6), C_RUST_IRON, 1.6)

	# Industrial Yellow/Black Hazard Chevron Strip
	var stripe_bar = Rect2(rect.position.x + 4, rect.position.y + h - 10, w - 8, 6)
	draw_rect(stripe_bar, Color(0.1, 0.1, 0.1), true)
	for s in range(5):
		var sx = stripe_bar.position.x + (s * 10.0)
		draw_line(Vector2(sx, stripe_bar.position.y + stripe_bar.size.y), Vector2(sx + 5, stripe_bar.position.y), C_HAZARD_YEL, 2.5)

	# Ancient Mechanicus Cog Emblem
	draw_circle(rect.position + Vector2(10, 10), 4.5, C_BRASS)
	draw_circle(rect.position + Vector2(10, 10), 2.0, Color.BLACK)

# ==============================================================================
# 4. CRASHED WAR-WRECK (Split armored hull plate with exhaust)
# ==============================================================================
func _draw_crashed_warreck() -> void:
	var w = radius * 1.5
	var h = radius * 1.2

	# Impact Crater Scorched Soil
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2(0, 6), radius * 1.1, Color(0.04, 0.03, 0.03, 0.65))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Angular Fractured Hull Armor Plating
	var hull = PackedVector2Array([
		Vector2(-w * 0.5, h * 0.3), Vector2(-w * 0.3, -h * 0.5),
		Vector2(w * 0.4, -h * 0.4), Vector2(w * 0.55, h * 0.2), Vector2(0, h * 0.5)
	])
	draw_colored_polygon(hull, C_MARS_RED)
	draw_polyline(hull, C_OUTLINE, 2.0)

	# Internal Machinery & Broken Hydraulics
	draw_line(Vector2(-w * 0.1, -h * 0.1), Vector2(w * 0.2, h * 0.2), C_STEEL_DARK, 4.0)
	draw_line(Vector2(-w * 0.1, -h * 0.1), Vector2(w * 0.2, h * 0.2), C_BRASS, 1.6)

	# Exhaust Vent Grille
	var vent_pos = Vector2(-w * 0.25, -h * 0.1)
	draw_rect(Rect2(vent_pos - Vector2(6, 4), Vector2(12, 8)), C_STEEL_DARK, true)
	for i in range(3):
		draw_line(vent_pos + Vector2(-4 + i * 4, -3), vent_pos + Vector2(-4 + i * 4, 3), C_RUST_IRON, 1.2)

# ==============================================================================
# 5. GLOWING RAD-CRYSTAL CLUSTER (Subterranean radioactive spires)
# ==============================================================================
func _draw_rad_crystal() -> void:
	# Radiating Ground Glow Ring
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.50))
	draw_circle(Vector2.ZERO, radius * 0.95, Color(C_RAD_GREEN.r, C_RAD_GREEN.g, C_RAD_GREEN.b, 0.10))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Cracked Bedrock Base
	draw_circle(Vector2(0, 4), radius * 0.42, C_BASALT_DARK)
	draw_circle(Vector2(0, 4), radius * 0.42, C_OUTLINE, false, 1.4)

	# 5 Angular Emerald Spire Crystals
	var spires = [
		{"pos": Vector2(0, -radius * 0.55), "sz": Vector2(8, radius * 0.7)},
		{"pos": Vector2(-radius * 0.35, -radius * 0.2), "sz": Vector2(6, radius * 0.55)},
		{"pos": Vector2(radius * 0.32, -radius * 0.25), "sz": Vector2(7, radius * 0.6)},
		{"pos": Vector2(-radius * 0.15, radius * 0.1), "sz": Vector2(5, radius * 0.35)},
		{"pos": Vector2(radius * 0.2, radius * 0.12), "sz": Vector2(5, radius * 0.35)}
	]

	for sp in spires:
		var p_tip = sp["pos"]
		var p_l = p_tip + Vector2(-sp["sz"].x * 0.5, sp["sz"].y)
		var p_r = p_tip + Vector2(sp["sz"].x * 0.5, sp["sz"].y)

		var shard_l = PackedVector2Array([p_tip, p_l, p_tip + Vector2(0, sp["sz"].y * 0.85)])
		var shard_r = PackedVector2Array([p_tip, p_r, p_tip + Vector2(0, sp["sz"].y * 0.85)])

		draw_colored_polygon(shard_l, C_RAD_EMERALD)
		draw_colored_polygon(shard_r, C_RAD_GREEN)
		draw_line(p_tip, p_l, C_OUTLINE, 1.2)
		draw_line(p_tip, p_r, C_OUTLINE, 1.2)
		draw_line(p_tip, p_tip + Vector2(0, sp["sz"].y * 0.85), Color.WHITE, 1.0)

# ==============================================================================
# 6. PROMETHEUM PIPELINE CONDUIT (With heavy valves & flanges)
# ==============================================================================
func _draw_prometheum_pipeline() -> void:
	var len_x = radius * 1.8
	var pipe_w = radius * 0.45
	var p_start = Vector2(-len_x * 0.5, 0)
	var p_end = Vector2(len_x * 0.5, 0)

	# Ground Shadow
	draw_line(p_start + Vector2(0, 8), p_end + Vector2(0, 8), Color(0.01, 0.01, 0.02, 0.50), pipe_w + 4.0)

	# Main Conduit Cylinder
	draw_line(p_start, p_end, C_STEEL_DARK, pipe_w + 3.0)
	draw_line(p_start, p_end, C_RUST_IRON, pipe_w)
	draw_line(p_start, p_end, C_STEEL_LIGHT, 2.0) # Metallic reflection highlight

	# Reinforced Joint Flanges
	for fx in [-len_x * 0.35, 0.0, len_x * 0.35]:
		draw_line(Vector2(fx, -pipe_w * 0.7), Vector2(fx, pipe_w * 0.7), C_STEEL_DARK, 5.0)
		draw_line(Vector2(fx, -pipe_w * 0.7), Vector2(fx, pipe_w * 0.7), C_BRASS, 2.2)

	# Center Pressure Valve Handwheel
	var valve_center = Vector2(0, -pipe_w * 0.7 - 4)
	draw_line(Vector2(0, 0), valve_center, C_STEEL_MID, 2.5)
	draw_circle(valve_center, 4.0, C_MARS_RED)
	draw_circle(valve_center, 4.0, C_OUTLINE, false, 1.2)
	draw_circle(valve_center, 1.5, C_BRASS)

# ==============================================================================
# UNSHADED GLOW LAYER (Warning lamps, crystal facet glow, and emergency strobes)
# ==============================================================================
class ObstacleGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		var pulse = 0.75 + sin(p.idle_anim_timer * 4.0) * 0.25

		match p.obstacle_type:
			ObstacleType.RAD_CRYSTAL:
				# Pulsing Emerald Radiation Glow
				draw_circle(Vector2(0, -p.radius * 0.4), 8.0 * pulse, Color(C_RAD_GREEN.r, C_RAD_GREEN.g, C_RAD_GREEN.b, 0.35 * pulse))
				draw_circle(Vector2(0, -p.radius * 0.4), 3.0, Color.WHITE)

			ObstacleType.CRASHED_WARRECK:
				# Flickering Red Emergency Strobe Light
				var strobe = 0.5 + sin(p.idle_anim_timer * 8.0) * 0.5
				var lamp_pos = Vector2(p.radius * 0.3, -p.radius * 0.35)
				draw_circle(lamp_pos, 4.0 * strobe, Color(1.0, 0.2, 0.15, 0.85 * strobe))
				draw_circle(lamp_pos, 1.5, Color.WHITE)

			ObstacleType.INDUSTRIAL_RUIN:
				# Occasional Electrical Spark on Exposed Rebar
				if fmod(p.idle_anim_timer * 2.5, 3.0) < 0.25:
					var spark_pos = Vector2(p.radius * 0.2, -p.radius * 0.3)
					draw_circle(spark_pos, 2.5, C_CYAN)
					draw_circle(spark_pos, 1.0, Color.WHITE)
