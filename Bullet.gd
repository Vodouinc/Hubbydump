extends Area2D

@export var speed: float = 550.0
@export var damage: int = 25
var direction: Vector2 = Vector2.RIGHT
var is_enemy_bullet: bool = false
var is_plasma_caliver: bool = false

func _ready():
	var unshaded_mat = CanvasItemMaterial.new()
	unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded_mat

	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	monitoring = true
	monitorable = true

	get_tree().create_timer(3.0).timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float):
	position += direction * speed * delta

func _draw() -> void:
	if is_enemy_bullet:
		draw_circle(Vector2(2, 0), 7.0, Color(1.0, 0.45, 0.1, 0.3))
		draw_line(Vector2(-10, 0), Vector2(2, 0), Color(1.0, 0.55, 0.15, 0.75), 4.0)
		draw_circle(Vector2(2, 0), 3.0, Color(1.0, 0.90, 0.2))
		draw_circle(Vector2(2, 0), 1.5, Color.WHITE)
	elif is_plasma_caliver:
		draw_circle(Vector2(2, 0), 12.0, Color(0.20, 0.88, 1.0, 0.35))
		draw_circle(Vector2(2, 0), 7.0, Color(0.35, 0.95, 1.0, 0.75))
		draw_line(Vector2(-16, 0), Vector2(4, 0), Color(0.20, 0.88, 1.0, 0.9), 5.5)
		draw_circle(Vector2(4, 0), 3.5, Color.WHITE)
	else:
		draw_circle(Vector2(2, 0), 8.0, Color(0.15, 0.85, 1.0, 0.2))
		draw_circle(Vector2(2, 0), 5.0, Color(0.20, 0.90, 1.0, 0.45))
		draw_line(Vector2(-12, 0), Vector2(2, 0), Color(0.15, 0.85, 1.0, 0.5), 4.5)
		draw_line(Vector2(-9, 0), Vector2(3, 0), Color(0.85, 0.98, 1.0, 0.95), 1.8)
		draw_circle(Vector2(3, 0), 2.2, Color.WHITE)

func _on_body_entered(body: Node2D):
	if body == self: return

	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		if is_enemy_bullet:
			if body.is_in_group("players") or body.is_in_group("bodyguards") or body.is_in_group("buildings") or body.is_in_group("base"):
				if body.has_method("take_damage"):
					body.take_damage(damage)
				call_deferred("queue_free")
		else:
			if body.is_in_group("enemies") or body.is_in_group("objectives"):
				if is_plasma_caliver and body.has_method("apply_telemetry_mark"):
					body.apply_telemetry_mark(6.0)
				if body.has_method("take_damage"):
					body.take_damage(damage)
				call_deferred("queue_free")
