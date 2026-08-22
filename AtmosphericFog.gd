@tool
extends Node2D
class_name AtmosphericFog

@export var density: int = 16
@export var wind_velocity: Vector2 = Vector2(35.0, 18.0)
@export var fog_color: Color = Color(0.65, 0.45, 0.32, 0.08)

var motes: Array[Dictionary] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	z_index = 80 # Sits above ground & buildings, beneath UI
	rng.seed = 91823
	_init_motes()

func _init_motes() -> void:
	motes.clear()
	var bounds = get_viewport_rect().size * 3.0
	for i in range(density):
		motes.append({
			"pos": Vector2(rng.randf_range(-bounds.x, bounds.x), rng.randf_range(-bounds.y, bounds.y)),
			"size": rng.randf_range(140.0, 320.0),
			"speed": rng.randf_range(0.7, 1.3),
			"alpha": rng.randf_range(0.04, 0.10),
			"is_ember": (i % 3 == 0)
		})

func _process(delta: float) -> void:
	var bounds = get_viewport_rect().size * 2.0
	for m in motes:
		m.pos += wind_velocity * m.speed * delta
		# Wrap around screen edges
		if m.pos.x > bounds.x: m.pos.x = -bounds.x
		if m.pos.y > bounds.y: m.pos.y = -bounds.y
	queue_redraw()

func _draw() -> void:
	for m in motes:
		if m.is_ember:
			# Smoldering Forge Cinders
			draw_circle(m.pos, 1.8, Color(1.0, 0.65, 0.20, m.alpha * 5.0))
			draw_circle(m.pos, 0.8, Color.WHITE)
		else:
			# Soft Volumetric Dust Bank
			draw_circle(m.pos, m.size, Color(fog_color.r, fog_color.g, fog_color.b, m.alpha))
