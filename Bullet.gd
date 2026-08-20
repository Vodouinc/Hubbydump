extends Area2D

@export var speed: float = 600.0
@export var damage: int = 25
var direction: Vector2 = Vector2.RIGHT
var is_enemy_bullet: bool = false # Distinguishes player vs enemy projectiles!

func _ready():
	var unshaded_mat = CanvasItemMaterial.new()
	unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded_mat

	get_tree().create_timer(3.0).timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float):
	position += direction * speed * delta

func _draw() -> void:
	if is_enemy_bullet:
		# Rusty Orange/Yellow Scrap Slug
		draw_circle(Vector2(2, 0), 6.0, Color(1.0, 0.4, 0.1, 0.25))
		draw_line(Vector2(-8, 0), Vector2(2, 0), Color(1.0, 0.6, 0.1, 0.6), 3.5)
		draw_circle(Vector2(2, 0), 2.5, Color(1.0, 0.85, 0.2))
	else:
		# Cyan Luminous Plasma Tracer (Player / Turret / Guard)
		draw_circle(Vector2(2, 0), 8.0, Color(0.15, 0.85, 1.0, 0.18))
		draw_circle(Vector2(2, 0), 5.0, Color(0.20, 0.90, 1.0, 0.40))
		draw_line(Vector2(-12, 0), Vector2(2, 0), Color(0.15, 0.85, 1.0, 0.45), 4.5)
		draw_line(Vector2(-9, 0), Vector2(3, 0), Color(0.85, 0.98, 1.0, 0.95), 1.8)
		draw_circle(Vector2(3, 0), 2.2, Color.WHITE)

func _on_body_entered(body: Node2D):
	if body == self: return

	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		if is_enemy_bullet:
			# Enemy Bullets ONLY hit Players, Bodyguards, Buildings, and Base (Ignore allied Orks!)
			if body.is_in_group("players") or body.is_in_group("bodyguards") or body.is_in_group("buildings") or body.is_in_group("base"):
				if body.has_method("take_damage"):
					body.take_damage(damage)
				call_deferred("queue_free")
		else:
			# Friendly Bullets ONLY hit Enemies and Waaagh Idols (Ignore friendly buildings/players!)
			if body.is_in_group("enemies") or body.is_in_group("objectives"):
				if body.has_method("take_damage"):
					body.take_damage(damage)
				call_deferred("queue_free")
