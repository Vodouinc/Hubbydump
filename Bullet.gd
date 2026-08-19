extends Area2D

@export var speed: float = 600.0
@export var damage: int = 25
var direction: Vector2 = Vector2.RIGHT

func _ready():
	# Auto-destroy after 3 seconds if it misses everything
	get_tree().create_timer(3.0).timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	# Movement is calculated everywhere for smooth prediction
	position += direction * speed * delta
	queue_redraw()

func _draw() -> void:
	# A short plasma tracer gives every projectile a readable direction and speed.
	draw_line(Vector2(-10, 0), Vector2(2, 0), Color(0.2, 0.88, 1.0, 0.35), 4.0)
	draw_line(Vector2(-8, 0), Vector2(3, 0), Color(0.85, 0.98, 1.0, 0.95), 1.4)
	draw_circle(Vector2(3, 0), 2.0, Color(0.35, 0.95, 1.0))

func _on_body_entered(body):
	# Ignore players, bodyguards, and other friendly units
	if body.is_in_group("players") or body.is_in_group("bodyguards") or body == self:
		return

	# Damage logic only runs on the Host/Server
	if multiplayer.is_server():
		if body.has_method("take_damage") and (body.is_in_group("enemies") or body.is_in_group("objectives")):
			body.take_damage(damage)
		
		# Safely defer queue_free so it doesn't crash during physics queries
		call_deferred("queue_free")
