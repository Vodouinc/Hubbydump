extends CharacterBody2D
class_name ServoSkull

@export var speed: float = 250.0
@export var repair_rate: float = 16.0 # HP repaired per second
@export var scan_range: float = 550.0

var player_owner: Node2D = null
var current_target_building: Node2D = null
var current_target_scrap: Node2D = null

var is_repairing: bool = false
var repair_accumulator: float = 0.0
var scan_timer: float = 0.0

var hover_angle: float = 0.0
var seed_offset: float = 0.0

func _ready() -> void:
	add_to_group("ServoSkull")
	add_to_group("friendlies")
	seed_offset = randf() * 100.0
	
	z_index = 86
	var mat = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func set_owner_player(p: Node2D) -> void:
	player_owner = p

func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		queue_redraw()
		return

	scan_timer += delta
	if scan_timer >= 0.35:
		scan_timer = randf_range(-0.05, 0.05) # Desync multiple skulls
		_evaluate_priorities()

	# =========================================================================
	# 1. ACTIVE MISSION: REPAIR BUILDING
	# =========================================================================
	if is_instance_valid(current_target_building):
		var cur_hp = current_target_building.get("current_health")
		var max_hp = current_target_building.get("max_health")

		# If building was destroyed or fully healed, finish mission
		if cur_hp == null or max_hp == null or cur_hp >= max_hp:
			current_target_building = null
			is_repairing = false
			repair_accumulator = 0.0
		else:
			var b_pos = current_target_building.global_position
			var dist = global_position.distance_to(b_pos)

			if dist > 45.0:
				is_repairing = false
				repair_accumulator = 0.0
				velocity = global_position.direction_to(b_pos) * speed
			else:
				is_repairing = true
				velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)

				# Smooth fractional HP restoration
				repair_accumulator += repair_rate * delta
				if repair_accumulator >= 1.0:
					var hp_to_add = int(repair_accumulator)
					repair_accumulator -= float(hp_to_add)

					var new_hp = min(max_hp, cur_hp + hp_to_add)
					if current_target_building.has_method("sync_health"):
						current_target_building.sync_health(new_hp)
					elif current_target_building.has_method("sync_base_health"):
						current_target_building.sync_base_health(new_hp)
					else:
						current_target_building.set("current_health", new_hp)

					if new_hp >= max_hp:
						current_target_building = null
						is_repairing = false
						repair_accumulator = 0.0

			move_and_slide()
			queue_redraw()
			return

	# =========================================================================
	# 2. ACTIVE MISSION: HARVEST GROUND SCRAP
	# =========================================================================
	if is_instance_valid(current_target_scrap):
		is_repairing = false
		repair_accumulator = 0.0
		var s_pos = current_target_scrap.global_position
		var dist = global_position.distance_to(s_pos)

		if dist > 18.0:
			velocity = global_position.direction_to(s_pos) * (speed * 1.15)
		else:
			var main_node = get_tree().get_first_node_in_group("main")
			var val = current_target_scrap.get("value") if "value" in current_target_scrap else 5
			if main_node and main_node.has_method("add_scrap"):
				main_node.add_scrap(val)
			current_target_scrap.queue_free()
			current_target_scrap = null
			AudioManager.play_sfx("building_place", global_position, -4.0, 1.8)

		move_and_slide()
		queue_redraw()
		return

	# =========================================================================
	# 3. IDLE: ESCORT TECH-PRIEST / PATROL SANCTUM
	# =========================================================================
	is_repairing = false
	repair_accumulator = 0.0
	var anchor_pos = global_position
	if is_instance_valid(player_owner):
		anchor_pos = player_owner.global_position
	else:
		var base = get_tree().get_first_node_in_group("base")
		if is_instance_valid(base): anchor_pos = base.global_position

	hover_angle += delta * 1.8
	var hover_target = anchor_pos + Vector2.RIGHT.rotated(hover_angle + seed_offset) * 48.0
	hover_target.y += sin(Time.get_ticks_msec() * 0.004 + seed_offset) * 8.0

	if global_position.distance_to(hover_target) > 12.0:
		velocity = global_position.direction_to(hover_target) * (speed * 0.85)
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	queue_redraw()

# =============================================================================
# SMART TARGET SELECTION & PRIORITY MATRIX
# =============================================================================

func _evaluate_priorities() -> void:
	# If already engaged in repairing a valid building, don't abandon it unless finished
	if is_instance_valid(current_target_building):
		var cur_hp = current_target_building.get("current_health")
		var max_hp = current_target_building.get("max_health")
		if cur_hp != null and max_hp != null and cur_hp < max_hp:
			return # Commit to current repair task

	# -------------------------------------------------------------------------
	# 1. SCAN FOR DAMAGED BUILDINGS (Weighted by Strategic Importance)
	# -------------------------------------------------------------------------
	var candidates: Array = get_tree().get_nodes_in_group("buildings")
	var base_node = get_tree().get_first_node_in_group("base")
	if is_instance_valid(base_node): candidates.append(base_node)

	var best_building: Node2D = null
	var highest_repair_priority: float = -100.0

	for b in candidates:
		if is_instance_valid(b) and not b.get("is_preview"):
			# Check if another skull is already actively repairing this building
			if _is_building_claimed_by_another_skull(b):
				continue

			var cur_hp = float(b.get("current_health")) if b.get("current_health") != null else 1.0
			var max_hp = float(b.get("max_health")) if b.get("max_health") != null else 1.0

			if max_hp > 0.0 and cur_hp < max_hp:
				var dist = global_position.distance_to(b.global_position)
				if dist <= scan_range:
					var damage_pct = 1.0 - (cur_hp / max_hp) # 0.0 (full) to 1.0 (dead)
					
					# Importance Weight
					var importance = 1.0
					if b.is_in_group("base"):
						importance = 4.0 # Base core is top emergency
					elif "building_type" in b:
						match int(b.building_type):
							1, 2, 4: importance = 2.8 # Dynamos, Turrets, Distributors
							3, 6, 7: importance = 2.0 # Factories, Shrines
							0:       importance = 1.2 # Barricades

					# Calculate final priority score (urgency + importance - distance penalty)
					var priority_score = (damage_pct * 30.0 * importance) - (dist / scan_range * 5.0)

					if priority_score > highest_repair_priority:
						highest_repair_priority = priority_score
						best_building = b

	if is_instance_valid(best_building):
		current_target_building = best_building
		current_target_scrap = null
		return

	# -------------------------------------------------------------------------
	# 2. SCAN FOR UNCLAIMED GROUND SCRAP (Low Priority)
	# -------------------------------------------------------------------------
	# If we already have a scrap target, ensure it's still unclaimed
	if is_instance_valid(current_target_scrap) and not _is_scrap_claimed_by_another_skull(current_target_scrap):
		return

	var scrap_list = get_tree().get_nodes_in_group("scrap")
	var closest_scrap: Node2D = null
	var min_scrap_dist = scan_range

	for s in scrap_list:
		if is_instance_valid(s):
			if _is_scrap_claimed_by_another_skull(s):
				continue

			var d = global_position.distance_to(s.global_position)
			if d < min_scrap_dist:
				min_scrap_dist = d
				closest_scrap = s

	current_target_scrap = closest_scrap
	current_target_building = null

# Check if another friendly Servo-Skull is already targeting this building
func _is_building_claimed_by_another_skull(building: Node2D) -> bool:
	for skull in get_tree().get_nodes_in_group("ServoSkull"):
		if is_instance_valid(skull) and skull != self:
			if skull.current_target_building == building:
				return true
	return false

# Check if another friendly Servo-Skull is already flying toward this scrap item
func _is_scrap_claimed_by_another_skull(scrap: Node2D) -> bool:
	for skull in get_tree().get_nodes_in_group("ServoSkull"):
		if is_instance_valid(skull) and skull != self:
			if skull.current_target_scrap == scrap:
				return true
	return false

# =============================================================================
# VISUAL RENDERING
# =============================================================================

func _draw() -> void:
	# --- DRAW REPAIR WELDING BEAM ---
	if is_repairing and is_instance_valid(current_target_building):
		var local_b = to_local(current_target_building.global_position)
		var pulse = 0.8 + sin(Time.get_ticks_msec() * 0.03) * 0.2
		var beam_col = Color(0.20, 0.88, 1.00, 0.9 * pulse)
		
		# Core arc + glow
		draw_line(Vector2(0, 2), local_b, Color(0.20, 0.88, 1.00, 0.35), 4.0)
		draw_line(Vector2(0, 2), local_b, beam_col, 1.5)
		draw_circle(local_b, 3.5 * pulse, Color(0.55, 0.95, 1.0))
		draw_circle(local_b, 1.5, Color.WHITE)

		# Spark particles
		for i in range(3):
			var spark_offset = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(4.0, 14.0)
			draw_circle(local_b + spark_offset, 1.0, Color(1.0, 0.85, 0.2))

	# --- DRAW SERVO-SKULL CHASSIS ---
	# Hover shadow
	draw_set_transform(Vector2(0, 14), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 5.0, Color(0.02, 0.03, 0.05, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Cranium Bone / Brass plating
	draw_circle(Vector2(0, -2), 6.5, Color(0.82, 0.76, 0.65)) # Bone Cranium
	draw_circle(Vector2(0, -2), 4.5, Color(0.92, 0.86, 0.75))

	# Cybernetic Ocular Lenses (Left: Brass mount, Right: Glowing Cyan Sensor)
	draw_circle(Vector2(-2.5, -2), 2.2, Color(0.25, 0.22, 0.18))
	draw_circle(Vector2(2.5, -2), 2.2, Color(0.20, 0.88, 1.00)) # Glowing Lens
	draw_circle(Vector2(2.5, -2), 1.0, Color.WHITE)

	# Trailing Mechatendril Cables
	var t = Time.get_ticks_msec() * 0.008 + seed_offset
	draw_line(Vector2(-3, 3), Vector2(-4 + sin(t) * 3.0, 10), Color(0.20, 0.22, 0.25), 1.2)
	draw_line(Vector2(0, 4), Vector2(0 + sin(t + 1.5) * 3.0, 12), Color(0.20, 0.22, 0.25), 1.2)
	draw_line(Vector2(3, 3), Vector2(4 + sin(t + 3.0) * 3.0, 10), Color(0.20, 0.22, 0.25), 1.2)
