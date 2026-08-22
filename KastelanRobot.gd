@tool
extends CharacterBody2D
class_name KastelanRobot

enum Protocol { ESCORT, ELIMINATION, ANCHOR_SIEGE }
var active_protocol: Protocol = Protocol.ESCORT

var player_owner: Node2D = null
var current_target_enemy: Node2D = null
var anchor_position: Vector2 = Vector2.ZERO

var rally_anchor: Vector2 = Vector2.ZERO
var has_received_player_order: bool = false

var rts_target_pos: Vector2 = Vector2.ZERO
var is_rts_moving: bool = false
var is_rts_selected: bool = false

# Combat Stats
@export var max_health: int = 750
var current_health: int = 750
@export var movement_speed: float = 175.0
@export var phosphor_damage: int = 35
@export var fist_damage: int = 80
@export var max_shield: float = 250.0
var current_shield: float = 250.0

var can_shoot: bool = true
var shoot_cooldown: float = 0.45
var can_fist_smash: bool = true
var fist_cooldown: float = 1.0

var anim_time: float = 0.0
var shield_pulse: float = 0.0
var is_facing_left: bool = false

# Palette Constants
const C_OUTLINE    := Color(0.04, 0.05, 0.07)
const C_MARS_RED   := Color(0.68, 0.16, 0.14)
const C_MARS_DARK  := Color(0.28, 0.05, 0.05)
const C_STEEL_DARK := Color(0.12, 0.14, 0.18)
const C_STEEL_MID  := Color(0.24, 0.28, 0.35)
const C_BRASS      := Color(0.82, 0.62, 0.24)
const C_CYAN       := Color(0.20, 0.88, 1.00)
const C_AMBER      := Color(1.00, 0.70, 0.15)
const C_SHIELD     := Color(0.20, 0.88, 1.00, 0.30)

@onready var health_bar: Node2D = get_node_or_null("HealthBar")

func _ready() -> void:
	add_to_group("bodyguards")
	add_to_group("kastelan_robots")
	add_to_group("friendlies")
	add_to_group("controllable_units")
	
	current_health = max_health
	current_shield = max_shield
	if health_bar and health_bar.has_method("setup"):
		health_bar.setup(current_health, max_health)
	
	# Solid collision
	var col = get_node_or_null("CollisionShape2D")
	if not col:
		col = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 16.0
		col.shape = shape
		add_child(col)

	# Procedural soft light
	if not has_node("KastelanLight"):
		var light = LightUtils.create_point_light(C_CYAN, 1.2, 2.5)
		light.name = "KastelanLight"
		add_child(light)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return

	if not is_instance_valid(player_owner):
		_find_owner_player()
		if not is_instance_valid(player_owner): return

	# Sync Protocol with Marshal's Doctrina if not locked to anchor
	var marshal_doctrina = player_owner.get("active_doctrina") if "active_doctrina" in player_owner else 0
	var is_conqueror = (marshal_doctrina == 0)

	# Check for Marshal's Painted Target
	var painted = player_owner.get("painted_target_enemy") if "painted_target_enemy" in player_owner else null
	if is_instance_valid(painted):
		current_target_enemy = painted
		if active_protocol != Protocol.ANCHOR_SIEGE:
			active_protocol = Protocol.ELIMINATION
	elif active_protocol == Protocol.ELIMINATION:
		active_protocol = Protocol.ESCORT

	# Execute Protocol Behaviors
	match active_protocol:
		Protocol.ESCORT:
			_process_escort_behavior(delta, is_conqueror)
		Protocol.ELIMINATION:
			_process_elimination_behavior(delta, is_conqueror)
		Protocol.ANCHOR_SIEGE:
			_process_anchor_siege_behavior(delta)

	move_and_slide()
	rpc("sync_transform", global_position, is_facing_left, int(active_protocol))

func _process_escort_behavior(delta: float, is_conqueror: bool) -> void:
	# 1. Moving to ordered RTS destination
	if is_rts_moving:
		var dist_to_rts = global_position.distance_to(rts_target_pos)
		if dist_to_rts > 15.0:
			velocity = global_position.direction_to(rts_target_pos) * movement_speed
			is_facing_left = (velocity.x < -0.1)
		else:
			is_rts_moving = false
			velocity = Vector2.ZERO
			# Lock position as a sentry anchor if manually ordered
			if has_received_player_order:
				anchor_position = global_position
				active_protocol = Protocol.ANCHOR_SIEGE
		
		velocity += _calculate_friendly_separation() * 50.0
		var nearby = _find_best_target(240.0)
		if is_instance_valid(nearby):
			_engage_enemy(nearby, is_conqueror)
		return

	# 2. If given a manual order, hold ground and shoot threats
	if has_received_player_order:
		velocity = velocity.move_toward(Vector2.ZERO, movement_speed * 4.0 * delta)
		var nearby_enemy = _find_best_target(320.0)
		if is_instance_valid(nearby_enemy):
			_engage_enemy(nearby_enemy, is_conqueror)
		return

	# 3. Autonomous Follow Player (Only if no manual player order was given)
	var player_facing = Vector2.RIGHT
	if is_instance_valid(player_owner) and player_owner.get("visual_sprite"):
		player_facing = Vector2.RIGHT.rotated(player_owner.visual_sprite.global_rotation)

	var flank_offset = player_facing.orthogonal() * (55.0 if get_instance_id() % 2 == 0 else -55.0)
	var lead_target = player_owner.global_position + flank_offset - (player_facing * 10.0) if is_instance_valid(player_owner) else global_position
	var dist = global_position.distance_to(lead_target)

	if dist > 25.0:
		velocity = global_position.direction_to(lead_target) * movement_speed
		is_facing_left = (velocity.x < -0.1)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, movement_speed * 4.0 * delta)

	velocity += _calculate_friendly_separation() * 60.0

	var enemy_threat = _find_best_target(240.0)
	if is_instance_valid(enemy_threat):
		_engage_enemy(enemy_threat, is_conqueror)

func _calculate_friendly_separation() -> Vector2:
	var push = Vector2.ZERO
	for u in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(u) and u != self:
			var d = global_position.distance_to(u.global_position)
			if d < 36.0 and d > 0.1:
				push += (global_position - u.global_position).normalized() * (1.0 - (d / 36.0))
	return push

func _find_best_target(max_d: float) -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var best_target: Node2D = null
	var min_d = max_d

	for e in enemies:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			if e.get("has_telemetry_mark"):
				var d = global_position.distance_to(e.global_position)
				if d <= max_d * 1.35:
					return e

	for e in enemies:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			var d = global_position.distance_to(e.global_position)
			if d < min_d:
				min_d = d
				best_target = e
	return best_target

func set_initial_rally(target_pos: Vector2) -> void:
	rally_anchor = target_pos
	has_received_player_order = false
	rts_target_pos = target_pos
	is_rts_moving = true
	active_protocol = Protocol.ESCORT
	current_target_enemy = null

func rts_move_to(pos: Vector2, _is_attack_move: bool = false) -> void:
	has_received_player_order = true
	rts_target_pos = pos
	is_rts_moving = true
	active_protocol = Protocol.ESCORT
	current_target_enemy = null

func rts_attack_target(target: Node2D) -> void:
	has_received_player_order = true
	current_target_enemy = target
	active_protocol = Protocol.ELIMINATION
	is_rts_moving = false

func rts_stop() -> void:
	has_received_player_order = true
	is_rts_moving = false
	current_target_enemy = null

func rts_hold() -> void:
	has_received_player_order = true
	is_rts_moving = false
	active_protocol = Protocol.ANCHOR_SIEGE
	anchor_position = global_position

func set_rts_selected(selected: bool) -> void:
	is_rts_selected = selected
	queue_redraw()

func _process_elimination_behavior(delta: float, is_conqueror: bool) -> void:
	if not is_instance_valid(current_target_enemy):
		active_protocol = Protocol.ESCORT
		return

	var dist = global_position.distance_to(current_target_enemy.global_position)
	is_facing_left = (current_target_enemy.global_position.x < global_position.x)

	if is_conqueror:
		# CONQUEROR PROTOCOL: Charge into melee range and smash with Power Fists
		if dist > 35.0:
			velocity = global_position.direction_to(current_target_enemy.global_position) * (movement_speed * 1.35)
		else:
			velocity = Vector2.ZERO
			if can_fist_smash:
				_smash_power_fist(current_target_enemy)
		# Fire phosphor cannons while charging
		if can_shoot and dist <= 280.0:
			_fire_heavy_phosphor(current_target_enemy.global_position)
	else:
		# PROTECTOR PROTOCOL: Maintain heavy suppressive fire line
		if dist > 180.0:
			velocity = global_position.direction_to(current_target_enemy.global_position) * movement_speed
		elif dist < 100.0:
			velocity = -global_position.direction_to(current_target_enemy.global_position) * (movement_speed * 0.7)
		else:
			velocity = Vector2.ZERO

		if can_shoot and dist <= 350.0:
			_fire_heavy_phosphor(current_target_enemy.global_position)

func _process_anchor_siege_behavior(delta: float) -> void:
	var dist = global_position.distance_to(anchor_position)
	if dist > 10.0:
		velocity = global_position.direction_to(anchor_position) * movement_speed
	else:
		velocity = Vector2.ZERO
		# Recharge and project 360° Refractor Shield Dome
		if current_shield < max_shield:
			current_shield = minf(max_shield, current_shield + 35.0 * delta)

	var target = _find_nearest_enemy(340.0)
	if is_instance_valid(target) and can_shoot:
		_fire_heavy_phosphor(target.global_position)

func _engage_enemy(enemy: Node2D, is_conqueror: bool) -> void:
	var dist = global_position.distance_to(enemy.global_position)
	is_facing_left = (enemy.global_position.x < global_position.x)
	if is_conqueror and dist <= 40.0 and can_fist_smash:
		_smash_power_fist(enemy)
	elif can_shoot and dist <= 300.0:
		_fire_heavy_phosphor(enemy.global_position)

func _fire_heavy_phosphor(target_pos: Vector2) -> void:
	can_shoot = false
	AudioManager.play_sfx("radium_shot", global_position, 1.5, 0.8)

	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and "spawner" in main_node and main_node.spawner:
		var dir = (target_pos - global_position).normalized()
		# Twin alternating phosphor shots
		for offset_y in [-6.0, 6.0]:
			var spawn_p = global_position + (dir * 20.0) + dir.orthogonal() * offset_y
			main_node.spawner.spawn({
				"type": "bullet",
				"name": "PhosphorBolt_" + str(randi()),
				"position": spawn_p,
				"direction": dir,
				"damage": phosphor_damage
			})

	var cd = 0.30 if active_protocol == Protocol.ELIMINATION else shoot_cooldown
	get_tree().create_timer(cd).timeout.connect(func(): if is_instance_valid(self): can_shoot = true)

func _smash_power_fist(target: Node2D) -> void:
	can_fist_smash = false
	AudioManager.play_sfx("hit", global_position, 3.0, 0.7)
	
	if target.has_method("take_damage"):
		var knockback = (target.global_position - global_position).normalized() * 350.0
		target.take_damage(fist_damage, knockback)

	get_tree().create_timer(fist_cooldown).timeout.connect(func(): if is_instance_valid(self): can_fist_smash = true)

func set_directive_anchor(pos: Vector2) -> void:
	active_protocol = Protocol.ANCHOR_SIEGE
	anchor_position = pos
	current_target_enemy = null

func set_directive_recall() -> void:
	active_protocol = Protocol.ESCORT
	current_target_enemy = null

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer(): return

	var dmg_left = float(amount)
	# Refractor shield absorbs damage first
	if active_protocol == Protocol.ANCHOR_SIEGE and current_shield > 0.0:
		var shield_dmg = minf(current_shield, dmg_left)
		current_shield -= shield_dmg
		dmg_left -= shield_dmg

	if dmg_left > 0.0:
		current_health = max(0, current_health - int(dmg_left))
		rpc("sync_health", current_health, current_shield)

@rpc("call_local", "reliable")
func sync_health(hp: int, shield: float) -> void:
	current_health = hp
	current_shield = shield
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
		if health_bar.has_method("update_shield"):
			health_bar.update_shield(int(current_shield), int(max_shield))
	if current_health <= 0:
		queue_free()

@rpc("unreliable")
func sync_transform(pos: Vector2, facing_left: bool, protocol_id: int) -> void:
	if not multiplayer.is_server():
		global_position = global_position.lerp(pos, 0.45)
		is_facing_left = facing_left
		active_protocol = protocol_id as Protocol
		queue_redraw()

func _find_nearest_enemy(max_d: float) -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var closest: Node2D = null
	var min_d = max_d
	for e in enemies:
		if is_instance_valid(e):
			var d = global_position.distance_to(e.global_position)
			if d < min_d: min_d = d; closest = e
	return closest

func _find_owner_player() -> void:
	var fallback_player = null
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p):
			if p.get("current_class") == 1: # Prioritize Skitarii Marshal
				player_owner = p
				return
			elif fallback_player == null:
				fallback_player = p
	player_owner = fallback_player

# ==============================================================================
# 2.5D KASTELAN BATTLE-AUTOMATA PROCEDURAL DRAWING
# ==============================================================================
func _process(delta: float) -> void:
	anim_time += delta
	if active_protocol == Protocol.ANCHOR_SIEGE:
		shield_pulse += delta * 3.0
	queue_redraw()

func _draw() -> void:
		# Draw RTS Selection Circle
	if is_rts_selected:
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(0.20, 0.88, 1.0, 0.85), 1.6)

	# 1. Projected 360° Refractor Shield Dome (Anchor/Siege Mode)
	if active_protocol == Protocol.ANCHOR_SIEGE and current_shield > 0.0:
		var pulse = 0.55 + sin(shield_pulse) * 0.15
		draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.60))
		draw_circle(Vector2.ZERO, 65.0, Color(0.20, 0.88, 1.0, 0.18 * pulse))
		draw_arc(Vector2.ZERO, 65.0, 0, TAU, 32, Color(0.20, 0.88, 1.0, 0.75 * pulse), 2.0)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# 2. Ground Contact Shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
	draw_circle(Vector2(0, 8), 18.0, Color(0.02, 0.02, 0.04, 0.55))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# 3. Horizontal Flip
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if is_facing_left else 1.0, 1.0))

	# Heavy Hydraulic Leg Pistons
	draw_line(Vector2(-9, 4), Vector2(-12, 14), C_STEEL_DARK, 4.5)
	draw_line(Vector2(9, 4), Vector2(12, 14), C_STEEL_DARK, 4.5)
	draw_circle(Vector2(-12, 14), 3.0, C_BRASS)
	draw_circle(Vector2(12, 14), 3.0, C_BRASS)

	# Massive Mars Crimson Dome Torso
	var torso = PackedVector2Array([
		Vector2(-16, -6), Vector2(16, -6),
		Vector2(18, 8), Vector2(12, 14),
		Vector2(-12, 14), Vector2(-18, 8)
	])
	draw_colored_polygon(torso, C_MARS_RED)
	var cl = torso.duplicate(); cl.append(torso[0])
	draw_polyline(cl, C_OUTLINE, 1.5)

	# Curved Black Glass Head Visor (Glows based on Protocol)
	var visor_poly = PackedVector2Array([
		Vector2(-8, -12), Vector2(8, -12),
		Vector2(11, -4), Vector2(-11, -4)
	])
	draw_colored_polygon(visor_poly, Color(0.05, 0.06, 0.08))
	draw_polyline(visor_poly, C_BRASS, 1.2)

	# Visor Phosphor Scanline (Red in Conqueror / Cyan in Protector)
	var visor_color = Color(1.0, 0.2, 0.1) if active_protocol == Protocol.ELIMINATION else C_CYAN
	draw_line(Vector2(-6, -8), Vector2(6, -8), visor_color, 2.0)
	draw_circle(Vector2(sin(anim_time * 6.0) * 5.0, -8), 1.2, Color.WHITE)

	# Heavy Twin Phosphor Arm Cannons
	draw_rect(Rect2(-24, -2, 8, 14), C_STEEL_MID)
	draw_rect(Rect2(16, -2, 8, 14), C_STEEL_MID)
	draw_rect(Rect2(-24, 10, 8, 4), C_BRASS)
	draw_rect(Rect2(16, 10, 8, 4), C_BRASS)

	# Mechanicum Brass Cog Badge
	IsoDraw.opus_machina_cog(self, Vector2(0, 4), 6.0, 6)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
