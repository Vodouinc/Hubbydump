# res://Scrap.gd
extends Area2D

@export var value: int = 6
@export var float_speed: float = 3.0
@export var player_vacuum_range: float = 75.0
@export var player_vacuum_speed: float = 380.0

var time_passed: float = 0.0
var base_y: float = 0.0
var target_collector: Node2D = null
var scan_timer: float = 0.0
var is_collected: bool = false

func _ready() -> void:
	add_to_group("scrap")
	base_y = position.y
	monitoring = true
	monitorable = true
	
	# Detect bodies (players, enemies, drones)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if is_collected: return
	time_passed += delta * float_speed

	scan_timer += delta
	if scan_timer >= 0.15:
		scan_timer = 0.0
		_find_nearest_collector()

	# Magnetic pull toward player or antenna pylon
	if is_instance_valid(target_collector):
		var target_pos = target_collector.global_position
		global_position = global_position.move_toward(target_pos, player_vacuum_speed * delta)
		if global_position.distance_to(target_pos) <= 22.0:
			_collect_scrap_into_bank()
	else:
		position.y = base_y + sin(time_passed) * 3.5

func _find_nearest_collector():
	target_collector = null
	var min_d = player_vacuum_range

	# 1. Vacuum toward nearby players
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and not p.get("is_dead"):
			var d = global_position.distance_to(p.global_position)
			if d < min_d:
				min_d = d
				target_collector = p

	# 2. Vacuum toward Noosphere Antenna / Distributor if Magnet tech is unlocked
	if target_collector == null:
		var main_node = get_tree().get_first_node_in_group("main")
		var has_magnet = main_node.get("tech_magnet_unlocked") if main_node else false
		var pylon_range = 380.0 if has_magnet else 220.0
		
		for b in get_tree().get_nodes_in_group("buildings"):
			if is_instance_valid(b) and int(b.get("building_type")) in [4, 5]:
				var d = global_position.distance_to(b.global_position)
				if d < pylon_range and d < min_d:
					min_d = d
					target_collector = b

func _on_body_entered(body: Node2D) -> void:
	if is_collected: return
	if body.is_in_group("players") or body.is_in_group("friendlies") or body.is_in_group("ServoSkull"):
		_collect_scrap_into_bank()

func _on_area_entered(area: Area2D) -> void:
	if is_collected: return
	if area.is_in_group("players") or area.is_in_group("friendlies"):
		_collect_scrap_into_bank()

func _collect_scrap_into_bank():
	if is_collected: return
	is_collected = true

	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.has_method("add_scrap"):
		main_node.add_scrap(value)

	AudioManager.play_sfx("scrap_pickup", global_position, -2.0, 1.2)
	queue_free()
