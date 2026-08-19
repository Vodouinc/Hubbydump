extends Area2D

@export var value: int = 5
@export var float_speed: float = 3.0

var time_passed: float = 0.0
var base_y: float = 0.0

func _ready() -> void:
	add_to_group("scrap")
	base_y = position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# Subtle bobbing animation on the local screen
	time_passed += delta * float_speed
	position.y = base_y + sin(time_passed) * 4.0

func _on_body_entered(body: Node2D) -> void:
	if multiplayer.is_server():
		# Allow players OR servo-skulls/bodyguards to pick up the scrap
		if body.is_in_group("players") or body.is_in_group("bodyguards") or body.name.begins_with("ServoSkull"):
			# Try finding parent or main node in group
			var main = get_parent()
			if not (main and main.has_method("add_scrap")):
				main = get_tree().get_first_node_in_group("main")

			if main and main.has_method("add_scrap"):
				main.add_scrap(value)
				rpc("spawn_pickup_fx", global_position)
				queue_free()

@rpc("call_local", "reliable")
func spawn_pickup_fx(spawn_pos: Vector2) -> void:
	# Spawn a green floating number via DamageNumber.gd
	var label = Label.new()
	label.script = load("res://DamageNumber.gd")
	label.global_position = spawn_pos + Vector2(-12, -20)
	
	# Add to main node or scene root so it stays visible after scrap node frees
	get_tree().current_scene.add_child(label)
	
	label.text = "+" + str(value) + " Scrap"
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.2, 0.95, 0.3) # Bright Green
	label.label_settings.font_size = 14
