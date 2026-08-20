extends Area2D

@export var speed: float = 600.0
@export var damage: int = 25
var direction: Vector2 = Vector2.RIGHT

func _ready():
	# Make bullet completely ignore night darkening so it glows brightly
	var unshaded_mat = CanvasItemMaterial.new()
	unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded_mat

	get_tree().create_timer(3.0).timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float):
	position += direction * speed * delta
	# Note: queue_redraw() removed; transform handles movement cleanly in hardware.

func _draw() -> void:
	# 1. Soft Outer Plasma Glow
	draw_circle(Vector2(2, 0), 8.0, Color(0.15, 0.85, 1.0, 0.18))
	draw_circle(Vector2(2, 0), 5.0, Color(0.20, 0.90, 1.0, 0.40))
	
	# 2. High-Velocity Tracer
	draw_line(Vector2(-12, 0), Vector2(2, 0), Color(0.15, 0.85, 1.0, 0.45), 4.5)
	draw_line(Vector2(-9, 0), Vector2(3, 0), Color(0.85, 0.98, 1.0, 0.95), 1.8)
	
	# 3. Core Hotspot
	draw_circle(Vector2(3, 0), 2.2, Color.WHITE)

func _on_body_entered(body: Node2D):
	if body.is_in_group("players") or body.is_in_group("bodyguards") or body == self:
		return

	if multiplayer.is_server():
		if body.has_method("take_damage") and (body.is_in_group("enemies") or body.is_in_group("objectives")):
			body.take_damage(damage)
		call_deferred("queue_free")
