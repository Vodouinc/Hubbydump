@tool
extends Node2D

enum EnemyType { GRETCHIN, SQUIG, ORK_BOY }
var type: EnemyType = EnemyType.GRETCHIN
var anim_time: float = 0.0
var attack_flash: float = 0.0

func _ready() -> void:
	queue_redraw()

func _process(delta: float) -> void:
	anim_time += delta
	var parent_node = get_parent()
	var movement: float = parent_node.get("velocity").length() if parent_node and "velocity" in parent_node else 0.0
	
	# Hardware transform bobbing (ZERO CPU redraw cost!)
	position.y = sin(anim_time * (4.0 + movement * 0.015)) * (0.5 + minf(movement / 300.0, 1.0))
	
	if attack_flash > 0.0:
		attack_flash = maxf(0.0, attack_flash - delta * 5.0)
		queue_redraw()

func play_attack_fx() -> void:
	attack_flash = 1.0
	queue_redraw()

func set_enemy_type(new_type: EnemyType) -> void:
	type = new_type
	queue_redraw()

func _draw() -> void:
	match type:
		EnemyType.GRETCHIN: _draw_gretchin()
		EnemyType.SQUIG: _draw_squig()
		EnemyType.ORK_BOY: _draw_ork_boy()

func _draw_gretchin() -> void:
	draw_circle(Vector2.ZERO, 10.0, Color("#8fb935"))
	draw_circle(Vector2(0, 10), 8.0, Color("#5c4033"))
	
	var left_ear = PackedVector2Array([Vector2(-6, -4), Vector2(-22, -12), Vector2(-4, 2)])
	var right_ear = PackedVector2Array([Vector2(6, -4), Vector2(22, -12), Vector2(4, 2)])
	draw_polygon(left_ear, [Color("#8fb935")])
	draw_polygon(right_ear, [Color("#8fb935")])

	var nose = PackedVector2Array([Vector2(-3, 0), Vector2(0, 8), Vector2(3, 0)])
	draw_polygon(nose, [Color("#769c28")])
	
	draw_circle(Vector2(-4, -3), 2.5, Color(1.0, 0.93, 0.0))
	draw_circle(Vector2(4, -3), 2.5, Color(1.0, 0.93, 0.0))

func _draw_squig() -> void:
	draw_circle(Vector2.ZERO, 20.0, Color("#a61212"))
	
	var horn_l = PackedVector2Array([Vector2(-10, -15), Vector2(-18, -32), Vector2(-4, -18)])
	var horn_r = PackedVector2Array([Vector2(10, -15), Vector2(18, -32), Vector2(4, -18)])
	draw_polygon(horn_l, [Color("#e8e4c9")])
	draw_polygon(horn_r, [Color("#e8e4c9")])
	
	var mouth = PackedVector2Array([Vector2(-14, 2), Vector2(0, 16), Vector2(14, 2), Vector2(0, -2)])
	draw_polygon(mouth, [Color("#3a0000")])
	
	draw_line(Vector2(-10, -1), Vector2(-8, 8), Color("#e8e4c9"), 3.0)
	draw_line(Vector2(-2, -2), Vector2(0, 12), Color("#e8e4c9"), 3.5)
	draw_line(Vector2(8, -1), Vector2(6, 8), Color("#e8e4c9"), 3.0)

	draw_circle(Vector2(-10, -10), 2.0 + attack_flash * 2.0, Color("#ffcc00"))
	draw_circle(Vector2(10, -10), 2.0 + attack_flash * 2.0, Color("#ffcc00"))

func _draw_ork_boy() -> void:
	draw_circle(Vector2(0, 6), 24.0, Color("#b81d13"))
	draw_circle(Vector2(0, -4), 16.0, Color("#2e6918"))
	
	var metal_jaw = PackedVector2Array([Vector2(-14, 2), Vector2(-8, 16), Vector2(8, 16), Vector2(14, 2)])
	draw_polygon(metal_jaw, [Color("#4a4e51")])
	draw_polyline(metal_jaw, Color("#1a1a1a"), 2.0)

	draw_line(Vector2(-6, 4), Vector2(-8, -4), Color("#e8e4c9"), 3.5)
	draw_line(Vector2(6, 4), Vector2(8, -4), Color("#e8e4c9"), 3.5)

	draw_circle(Vector2(-6, -6), 2.5 + attack_flash * 2.0, Color("#ff0000"))
	draw_circle(Vector2(6, -6), 2.5 + attack_flash * 2.0, Color("#ff0000"))
	
	draw_line(Vector2(18, 10), Vector2(28, -20), Color("#2a2a2a"), 5.0)
	var blade = PackedVector2Array([Vector2(26, -20), Vector2(38, -16), Vector2(32, -40), Vector2(24, -28)])
	draw_polygon(blade, [Color("#d1d5db")])
