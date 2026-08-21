class_name IsoDraw
extends RefCounted

const C_OUTLINE   := Color(0.04, 0.05, 0.07)
const C_BRASS     := Color(0.82, 0.62, 0.24)
const C_BRASS_DIM := Color(0.40, 0.28, 0.10)
const C_IVORY     := Color(0.90, 0.86, 0.76)
const C_PARCHMENT := Color(0.88, 0.84, 0.72)
const C_SEAL_WAX  := Color(0.78, 0.08, 0.08)
const C_CYAN      := Color(0.20, 0.88, 1.00)
const C_AMBER     := Color(1.00, 0.70, 0.15)
const C_COPPER    := Color(0.82, 0.44, 0.18)

## Projects 3D Cartesian coordinates (x, y, z) into 2:1 dimetric screen space
static func project(x: float, y: float, z: float) -> Vector2:
	return Vector2((x - y) * 0.866025, (x + y) * 0.5 - z)

## Draws a 3D isometric cuboid with automatic Top/Left/Right directional shading
static func box(canvas: CanvasItem, origin: Vector3, size: Vector3, base_color: Color, outline_color: Color = C_OUTLINE, line_width: float = 1.4) -> void:
	var x = origin.x; var y = origin.y; var z = origin.z
	var w = size.x;   var d = size.y;   var h = size.z

	var p000 = project(x, y, z)
	var p100 = project(x + w, y, z)
	var p110 = project(x + w, y + d, z)
	var p010 = project(x, y + d, z)

	var p001 = project(x, y, z + h)
	var p101 = project(x + w, y, z + h)
	var p111 = project(x + w, y + d, z + h)
	var p011 = project(x, y + d, z + h)

	var c_top   = base_color.lightened(0.22)
	var c_left  = base_color
	var c_right = base_color.darkened(0.30)

	# Left Face (West to South)
	var left_poly = PackedVector2Array([p010, p110, p111, p011])
	canvas.draw_colored_polygon(left_poly, c_left)
	var cl_left = left_poly.duplicate(); cl_left.append(left_poly[0])
	canvas.draw_polyline(cl_left, outline_color, line_width)

	# Right/Front Face (East to South)
	var right_poly = PackedVector2Array([p100, p110, p111, p101])
	canvas.draw_colored_polygon(right_poly, c_right)
	var cl_right = right_poly.duplicate(); cl_right.append(right_poly[0])
	canvas.draw_polyline(cl_right, outline_color, line_width)

	# Top Face
	var top_poly = PackedVector2Array([p001, p101, p111, p011])
	canvas.draw_colored_polygon(top_poly, c_top)
	var cl_top = top_poly.duplicate(); cl_top.append(top_poly[0])
	canvas.draw_polyline(cl_top, outline_color, line_width)

## Draws a vertical isometric cylinder (for plasma coils, boilers, smokestacks, and turret rings)
static func cylinder(canvas: CanvasItem, center_3d: Vector3, radius: float, height: float, color: Color, outline_color: Color = C_OUTLINE) -> void:
	var base_pt = project(center_3d.x, center_3d.y, center_3d.z)
	var top_pt  = project(center_3d.x, center_3d.y, center_3d.z + height)

	var c_body = color.darkened(0.15)
	var c_top  = color.lightened(0.20)

	# Front curved body wall
	var body_poly = PackedVector2Array([
		base_pt - Vector2(radius * 0.866, 0),
		base_pt + Vector2(radius * 0.866, 0),
		top_pt  + Vector2(radius * 0.866, 0),
		top_pt  - Vector2(radius * 0.866, 0)
	])
	canvas.draw_colored_polygon(body_poly, c_body)

	# Bottom base shadow rim
	canvas.draw_set_transform(base_pt, 0, Vector2(1.0, 0.5))
	canvas.draw_arc(Vector2.ZERO, radius, 0, PI, 16, outline_color, 1.4)
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Side vertical outline seams
	canvas.draw_line(base_pt - Vector2(radius * 0.866, 0), top_pt - Vector2(radius * 0.866, 0), outline_color, 1.4)
	canvas.draw_line(base_pt + Vector2(radius * 0.866, 0), top_pt + Vector2(radius * 0.866, 0), outline_color, 1.4)

	# Top circular deck
	canvas.draw_set_transform(top_pt, 0, Vector2(1.0, 0.5))
	canvas.draw_circle(Vector2.ZERO, radius, c_top)
	canvas.draw_arc(Vector2.ZERO, radius, 0, TAU, 20, outline_color, 1.4)
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## Draws an industrial pipe segment running along the isometric grid
static func pipe(canvas: CanvasItem, p1_3d: Vector3, p2_3d: Vector3, thickness: float = 3.5, color: Color = Color(0.18, 0.20, 0.24)) -> void:
	var s1 = project(p1_3d.x, p1_3d.y, p1_3d.z)
	var s2 = project(p2_3d.x, p2_3d.y, p2_3d.z)
	canvas.draw_line(s1, s2, C_OUTLINE, thickness + 2.0)
	canvas.draw_line(s1, s2, color, thickness)
	canvas.draw_circle(s1, thickness * 0.75, C_BRASS)
	canvas.draw_circle(s2, thickness * 0.75, C_BRASS)

## Draws an Opus Machina Cog Wheel with Split Skull emblem
static func opus_machina_cog(canvas: CanvasItem, center: Vector2, radius: float, teeth_count: int = 8) -> void:
	for i in range(teeth_count):
		var a = i * TAU / float(teeth_count)
		var t_pos = center + Vector2(cos(a), sin(a) * 0.5) * radius
		canvas.draw_rect(Rect2(t_pos - Vector2(2, 2), Vector2(4, 4)), C_BRASS)

	canvas.draw_circle(center, radius, Color(0.08, 0.10, 0.12))
	canvas.draw_circle(center, radius, C_BRASS, false, 1.4)

	var skull_r = radius - 3.0
	var left_semi = PackedVector2Array()
	var right_semi = PackedVector2Array()
	for i in range(17):
		var a = -PI/2.0 + (i * PI / 16.0)
		left_semi.append(center + Vector2(cos(a + PI), sin(a + PI) * 0.5) * skull_r)
		right_semi.append(center + Vector2(cos(a), sin(a) * 0.5) * skull_r)

	canvas.draw_colored_polygon(left_semi, C_IVORY)
	canvas.draw_colored_polygon(right_semi, Color(0.12, 0.14, 0.18))
	canvas.draw_circle(center + Vector2(-1.5, -1), 1.0, Color.BLACK)
	canvas.draw_circle(center + Vector2(1.5, -1), 1.0, C_CYAN)

## Draws a Red Wax Purity Seal with prayer scroll
static func purity_seal(canvas: CanvasItem, screen_pos: Vector2, scroll_len: float = 7.0) -> void:
	canvas.draw_circle(screen_pos, 2.2, C_SEAL_WAX)
	canvas.draw_line(screen_pos + Vector2(-1, 2), screen_pos + Vector2(-1, 2 + scroll_len), C_PARCHMENT, 2.2)
	canvas.draw_line(screen_pos + Vector2(1, 2), screen_pos + Vector2(1, 2 + scroll_len * 0.65), C_PARCHMENT, 1.5)
