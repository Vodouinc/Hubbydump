extends Area2D

@export var value: int = 5
@export var float_speed: float = 3.0
@export var base_magnet_speed: float = 240.0
@export var base_magnet_range: float = 220.0

var time_passed: float = 0.0
var base_y: float = 0.0
var target_pylon: Node2D = null
var scan_timer: float = 0.0

func _ready() -> void:
	add_to_group("scrap")
	base_y = position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	time_passed += delta * float_speed
	
	# Determine if Siphon Tech is researched
	var main_node = get_tree().get_first_node_in_group("main")
	var is_siphon_upgraded = main_node.get("tech_magnet_unlocked") if main_node else false
	
	var active_range = 385.0 if is_siphon_upgraded else base_magnet_range
	var active_speed = 360.0 if is_siphon_upgraded else base_magnet_speed

	# 1. Throttle pylon search (Scans 4 times/sec)
	scan_timer += delta
	if scan_timer >= 0.25:
		scan_timer = 0.0
		_find_nearest_pylon(active_range)

	# 2. Magnetic Pull
	if is_instance_valid(target_pylon):
		var target_pos = target_pylon.global_position
		var dist = global_position.distance_to(target_pos)
		
		# Move smoothly toward pylon at active speed
		global_position = global_position.move_toward(target_pos, active_speed * delta)
		
		# Auto-absorb if Antenna (Type 5)
		var p_type = int(target_pylon.get("building_type")) if "building_type" in target_pylon else 0
		if p_type == 5 and dist <= 26.0:
			if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
				_collect_scrap_into_bank()
	else:
		position.y = base_y + sin(time_passed) * 3.5

func _find_nearest_pylon(search_range: float):
	target_pylon = null
	var min_d = search_range
	
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b): continue
		var b_type = int(b.get("building_type")) if "building_type" in b else 0
		
		if b_type in [4, 5]:
			var d = global_position.distance_to(b.global_position)
			if d < min_d:
				min_d = d
				target_pylon = b

func _on_body_entered(body: Node2D) -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		if body.is_in_group("players") or body.is_in_group("bodyguards") or body.name.begins_with("ServoSkull"):
			_collect_scrap_into_bank()

func _collect_scrap_into_bank():
	var main = get_parent()
	if not (main and main.has_method("add_scrap")):
		main = get_tree().get_first_node_in_group("main")

	if main and main.has_method("add_scrap"):
		main.add_scrap(value)
		rpc("spawn_pickup_fx", global_position)
		queue_free()

@rpc("call_local", "reliable")
func spawn_pickup_fx(spawn_pos: Vector2) -> void:
	
	AudioManager.play_sfx("scrap_pickup", spawn_pos, -2.0)
	
	var label = Label.new()
	label.script = load("res://DamageNumber.gd")
	label.global_position = spawn_pos + Vector2(-12, -20)
	get_tree().current_scene.add_child(label)
	
	label.text = "+" + str(value) + " Scrap"
	label.label_settings = LabelSettings.new()
	label.label_settings.font_color = Color(0.2, 0.95, 0.3)
	label.label_settings.font_size = 14
