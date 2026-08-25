extends Area2D
class_name Bullet

enum BulletType {
	GALVANIC_SNIPER = 0,   # Ranger: Needle-thin, hyper-velocity kinetic tracer
	RADIUM_FLECHETTE = 1,  # Vanguard/Marshal: Irradiated green flechette dart
	PLASMA_BOLT = 2,       # Tech-Priest: Heavy superheated cyan plasma orb
	KINETIC_TRACER = 3,    # Cognis Turret / Heavy Stubber: Amber tracer streak
	PHOSPHOR_ROUND = 4,    # Kastelan Automata: Heavy incendiary white-hot bolt
	ORK_SLUG = 5           # Gretchin/Orks: Heavy jagged iron scrap slug
}

@export var bullet_type: BulletType = BulletType.KINETIC_TRACER:
	set(val):
		bullet_type = val
		if is_node_ready():
			_apply_bullet_type_stats()

@export var speed: float = 650.0
@export var damage: int = 25
var direction: Vector2 = Vector2.RIGHT
var is_enemy_bullet: bool = false
var is_plasma_caliver: bool = false

var point_light: PointLight2D = null

func _ready():
	var unshaded_mat = CanvasItemMaterial.new()
	unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded_mat

	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	monitoring = true
	monitorable = true

	_apply_bullet_type_stats()
	_setup_bullet_light()

	get_tree().create_timer(3.0).timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func _apply_bullet_type_stats():
	match bullet_type:
		BulletType.GALVANIC_SNIPER:
			speed = 1050.0
			is_enemy_bullet = false
		BulletType.RADIUM_FLECHETTE:
			speed = 680.0
			is_enemy_bullet = false
		BulletType.PLASMA_BOLT:
			speed = 520.0
			is_plasma_caliver = true
			is_enemy_bullet = false
		BulletType.KINETIC_TRACER:
			speed = 720.0
			# Only set to false if not already set as enemy
			if not is_enemy_bullet:
				is_enemy_bullet = false
		BulletType.PHOSPHOR_ROUND:
			speed = 580.0
			is_enemy_bullet = false
		BulletType.ORK_SLUG:
			speed = 460.0
			is_enemy_bullet = true

func _setup_bullet_light():
	if point_light: point_light.queue_free()

	var light_col = Color.WHITE
	var energy = 0.8
	var scale_factor = 1.8

	match bullet_type:
		BulletType.GALVANIC_SNIPER:
			light_col = Color(0.35, 0.90, 1.0)
			energy = 0.9
			scale_factor = 1.4
		BulletType.RADIUM_FLECHETTE:
			light_col = Color(0.25, 0.95, 0.35)
			energy = 0.8
			scale_factor = 1.5
		BulletType.PLASMA_BOLT:
			light_col = Color(0.20, 0.88, 1.0)
			energy = 1.4
			scale_factor = 2.4
		BulletType.KINETIC_TRACER:
			light_col = Color(1.0, 0.75, 0.25)
			energy = 0.7
			scale_factor = 1.3
		BulletType.PHOSPHOR_ROUND:
			light_col = Color(1.0, 0.85, 0.40)
			energy = 1.3
			scale_factor = 2.2
		BulletType.ORK_SLUG:
			light_col = Color(1.0, 0.40, 0.15)
			energy = 0.6
			scale_factor = 1.2

	point_light = LightUtils.create_point_light(light_col, energy, scale_factor)
	point_light.name = "BulletLight"
	add_child(point_light)

func _physics_process(delta: float):
	position += direction * speed * delta

func _draw() -> void:
	match bullet_type:
		BulletType.GALVANIC_SNIPER:
			# Needle-thin, hyper-velocity kinetic tracer
			draw_line(Vector2(-24, 0), Vector2(6, 0), Color(0.20, 0.88, 1.0, 0.45), 2.2) # Ionizing slipstream
			draw_line(Vector2(-18, 0), Vector2(8, 0), Color(0.85, 0.95, 1.0, 0.95), 1.0) # Razor-sharp core
			draw_circle(Vector2(8, 0), 1.0, Color.WHITE)

		BulletType.RADIUM_FLECHETTE:
			# Glowing irradiated green dart
			draw_line(Vector2(-12, 0), Vector2(3, 0), Color(0.25, 0.95, 0.35, 0.45), 3.0)
			draw_line(Vector2(-8, 0), Vector2(4, 0), Color(0.45, 1.0, 0.55, 0.95), 1.5)
			draw_circle(Vector2(4, 0), 1.6, Color(0.85, 1.0, 0.85))

		BulletType.PLASMA_BOLT:
			# Superheated cyan plasma orb with outer thermal corona
			draw_circle(Vector2(2, 0), 9.0, Color(0.20, 0.88, 1.0, 0.35))
			draw_line(Vector2(-16, 0), Vector2(4, 0), Color(0.20, 0.88, 1.0, 0.85), 5.0)
			draw_circle(Vector2(3, 0), 4.5, Color(0.55, 0.95, 1.0))
			draw_circle(Vector2(3, 0), 2.0, Color.WHITE)

		BulletType.KINETIC_TRACER:
			# Crisp high-RPM brass/amber ballistic tracer
			draw_line(Vector2(-14, 0), Vector2(3, 0), Color(1.0, 0.70, 0.20, 0.4), 3.0)
			draw_line(Vector2(-10, 0), Vector2(4, 0), Color(1.0, 0.90, 0.50, 0.95), 1.5)
			draw_circle(Vector2(4, 0), 1.4, Color.WHITE)

		BulletType.PHOSPHOR_ROUND:
			# Incandescent white-hot phosphor shell
			draw_circle(Vector2(2, 0), 7.5, Color(1.0, 0.55, 0.15, 0.35))
			draw_line(Vector2(-16, 0), Vector2(4, 0), Color(1.0, 0.75, 0.25, 0.8), 4.5)
			draw_circle(Vector2(4, 0), 3.2, Color(1.0, 0.95, 0.6))
			draw_circle(Vector2(4, 0), 1.5, Color.WHITE)

		BulletType.ORK_SLUG:
			# Crude, blunt iron bullet with propellant sparks
			draw_line(Vector2(-10, 0), Vector2(2, 0), Color(1.0, 0.45, 0.15, 0.65), 3.5)
			draw_rect(Rect2(Vector2(-2, -2), Vector2(6, 4)), Color(0.25, 0.22, 0.20))
			draw_circle(Vector2(4, 0), 1.8, Color(1.0, 0.85, 0.20))
			draw_circle(Vector2(4, 0), 0.8, Color.WHITE)

func _on_body_entered(body: Node2D):
	if body == self: return

	# 1. ENEMY BULLETS (Gretchin scrap slugs, etc.)
	if is_enemy_bullet:
		# COMPLETELY IGNORE ALL ENEMIES (No self-harm or friendly fire)
		if body.is_in_group("enemies") or body.is_in_group("ork_citadel") or body.is_in_group("ork_structures"):
			return

		if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
			if body.is_in_group("players") or body.is_in_group("bodyguards") or body.is_in_group("buildings") or body.is_in_group("base") or body.is_in_group("friendlies"):
				if body.has_method("take_damage"):
					body.take_damage(damage)
				call_deferred("queue_free")
			elif body.is_in_group("world_obstacles"):
				call_deferred("queue_free")

	# 2. PLAYER & DEFENDER BULLETS
	else:
		# COMPLETELY IGNORE PLAYERS AND FRIENDLIES
		if body.is_in_group("players") or body.is_in_group("bodyguards") or body.is_in_group("friendlies") or body.is_in_group("buildings") or body.is_in_group("base"):
			return

		if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
			if body.is_in_group("enemies") or body.is_in_group("objectives") or body.is_in_group("ork_citadel") or body.is_in_group("ork_structures"):
				if "is_plasma_caliver" in self and is_plasma_caliver and body.has_method("apply_telemetry_mark"):
					body.apply_telemetry_mark(6.0)
				if body.has_method("take_damage"):
					body.take_damage(damage)
				call_deferred("queue_free")
			elif body.is_in_group("world_obstacles"):
				call_deferred("queue_free")
