# res://SororitasOutpost.gd
@tool
extends StaticBody2D
class_name SororitasOutpost

enum QuestState { NOT_STARTED, IN_PROGRESS, RELIC_FOUND, COMPLETED }

var quest_state: QuestState = QuestState.NOT_STARTED
var sister_1: SororitasDefender = null
var sister_2: SororitasDefender = null

var idle_anim_timer: float = 0.0
var glow_layer: Node2D = null
var point_light: PointLight2D = null

# --- GOTHIC SORORITAS PALETTE ---
const C_OUTLINE        := Color(0.04, 0.05, 0.07)
const C_MARBLE_DARK    := Color(0.12, 0.11, 0.14)
const C_MARBLE_MID     := Color(0.22, 0.20, 0.25)
const C_MARBLE_LIGHT   := Color(0.82, 0.80, 0.85)
const C_MARTYRED_RED   := Color(0.65, 0.10, 0.14)
const C_MARTYRED_DARK  := Color(0.35, 0.06, 0.08)
const C_ECCLESIARCH_G  := Color(0.88, 0.72, 0.28)
const C_GOLD_DIM       := Color(0.48, 0.36, 0.14)
const C_STEEL_DARK     := Color(0.14, 0.16, 0.20)
const C_FIRE_AMBER     := Color(1.00, 0.65, 0.15)
const C_FIRE_WHITE     := Color(1.00, 0.95, 0.75)
const C_PARCHMENT      := Color(0.88, 0.84, 0.70)
const C_SEAL_WAX       := Color(0.78, 0.08, 0.08)

func _ready() -> void:
	add_to_group("objectives")
	add_to_group("sororitas_outpost")
	add_to_group("quest_interactables")

	# Heavy Gothic Footprint Collision
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(80, 64)
	col.shape = shape
	add_child(col)

	_setup_glow_overlay()
	_setup_sanctuary_light()

	if not Engine.is_editor_hint():
		call_deferred("_spawn_sisters_guard")

func _setup_sanctuary_light() -> void:
	if has_node("SanctuaryLight"):
		get_node("SanctuaryLight").queue_free()
	
	point_light = LightUtils.create_point_light(Color(1.0, 0.75, 0.35), 1.7, 3.8)
	point_light.name = "SanctuaryLight"
	add_child(point_light)

func _setup_glow_overlay() -> void:
	if not has_node("OutpostGlowOverlay"):
		glow_layer = OutpostGlowRenderer.new()
		glow_layer.name = "OutpostGlowOverlay"
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		glow_layer.material = mat
		add_child(glow_layer)
	else:
		glow_layer = get_node("OutpostGlowOverlay")

func _spawn_sisters_guard() -> void:
	sister_1 = SororitasDefender.new()
	sister_1.sister_name = "Sister Erika"
	sister_1.weapon_type = "bolter"
	sister_1.position = global_position + Vector2(-42, 22)
	get_parent().add_child(sister_1)

	sister_2 = SororitasDefender.new()
	sister_2.sister_name = "Sister Helena"
	sister_2.weapon_type = "flamer"
	sister_2.position = global_position + Vector2(42, 22)
	get_parent().add_child(sister_2)

func _process(delta: float) -> void:
	idle_anim_timer += delta
	queue_redraw()
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func interact(player_node: Node2D) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(1, "request_interact_outpost", player_node.name)
		return

	_handle_outpost_interaction()

@rpc("any_peer", "call_local", "reliable")
func request_interact_outpost(_player_name: String) -> void:
	_handle_outpost_interaction()

func _handle_outpost_interaction() -> void:
	match quest_state:
		QuestState.NOT_STARTED:
			quest_state = QuestState.IN_PROGRESS
			_broadcast_quest_state()
			_announce_dialogue("⚜️ SISTERS: \"Greetings, servant of Mars! We seek the holy Relic of Sebastian Thor. Our Auspex just detected its signature deep in the feral wastes! Retrieve it for us, and our blades are yours!\"")
			
			var main_node = get_tree().get_first_node_in_group("main")
			if main_node and main_node.has_method("spawn_sebastian_relic_event"):
				main_node.spawn_sebastian_relic_event()
		
		QuestState.IN_PROGRESS:
			_announce_dialogue("⚜️ SISTERS: \"The sacred Relic still lies in the feral wastes. Recover it and return here!\"")

		QuestState.RELIC_FOUND:
			quest_state = QuestState.COMPLETED
			_broadcast_quest_state()
			_complete_quest()

		QuestState.COMPLETED:
			_announce_dialogue("⚜️ SISTERS: \"The Emperor Protects. We stand vigil over the Sanctum.\"")

func set_relic_found(found: bool) -> void:
	if found and quest_state == QuestState.IN_PROGRESS:
		quest_state = QuestState.RELIC_FOUND
		_broadcast_quest_state()

func _complete_quest() -> void:
	AudioManager.play_sfx("orbital_strike", global_position, 2.0, 1.2)
	_announce_dialogue("⚜️ SISTERS: \"By the Throne! The Holy Relic is recovered! We now march to defend your Sanctum to the death!\"")

	if is_instance_valid(sister_1):
		sister_1.order_march_to_base(0.0)
	if is_instance_valid(sister_2):
		sister_2.order_march_to_base(PI)

	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.has_method("add_requisition"):
		main_node.add_requisition(50)

func _broadcast_quest_state() -> void:
	if multiplayer.has_multiplayer_peer():
		rpc("sync_quest_state", int(quest_state))
	else:
		sync_quest_state(int(quest_state))

@rpc("call_local", "reliable")
func sync_quest_state(state_idx: int) -> void:
	quest_state = state_idx as QuestState
	queue_redraw()
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func _announce_dialogue(msg: String) -> void:
	get_tree().call_group("event_banner", "post_banner", 
		"⚜️ ADEPTA SORORITAS • ORDER OF OUR MARTYRED LADY", 
		msg, 
		1 # SORORITAS_HOLY
	)

func _draw() -> void:
	var pulse = 0.70 + sin(idle_anim_timer * 3.5) * 0.30

	# 1. SANCTIFIED MARBLE & GOLD GROUND PLINTH
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
	draw_circle(Vector2.ZERO, 110.0, Color(0.02, 0.02, 0.04, 0.55)) # Shadow
	draw_arc(Vector2.ZERO, 105.0, 0, TAU, 40, Color(C_ECCLESIARCH_G.r, C_ECCLESIARCH_G.g, C_ECCLESIARCH_G.b, 0.35 * pulse), 1.6)
	draw_arc(Vector2.ZERO, 75.0, 0, TAU, 32, Color(C_ECCLESIARCH_G.r, C_ECCLESIARCH_G.g, C_ECCLESIARCH_G.b, 0.55 * pulse), 1.4)
	
	# Flagstone radial rays
	for i in range(8):
		var a = i * (TAU / 8.0)
		draw_line(Vector2(cos(a), sin(a)) * 50.0, Vector2(cos(a), sin(a)) * 105.0, Color(C_ECCLESIARCH_G.r, C_ECCLESIARCH_G.g, C_ECCLESIARCH_G.b, 0.25), 1.2)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# 2. CRIMSON CARPET RUNNER (Extends south toward entrance)
	var carpet_p1 = IsoDraw.project(-10, 20, 0)
	var carpet_p2 = IsoDraw.project(10, 20, 0)
	var carpet_p3 = IsoDraw.project(12, 55, 0)
	var carpet_p4 = IsoDraw.project(-12, 55, 0)
	var carpet_poly = PackedVector2Array([carpet_p1, carpet_p2, carpet_p3, carpet_p4])
	draw_colored_polygon(carpet_poly, C_MARTYRED_RED)
	draw_polyline(carpet_poly, C_ECCLESIARCH_G, 1.4)

	# 3. GOTHIC SHRINE BASAL PLINTH (3D Isometric)
	IsoDraw.box(self, Vector3(-28, -28, 0), Vector3(56, 56, 8), C_MARBLE_DARK)

	# 4. CORNER GOTHIC COLUMNS (Marble pillars with gold trim)
	for c in [Vector3(-24, -24, 8), Vector3(16, -24, 8), Vector3(-24, 16, 8), Vector3(16, 16, 8)]:
		IsoDraw.box(self, c, Vector3(8, 8, 18), C_MARBLE_MID)
		var col_top = IsoDraw.project(c.x + 4, c.y + 4, c.z + 18)
		draw_circle(col_top, 2.6, C_ECCLESIARCH_G)

	# 5. CENTRAL NAVE BASTION (Martyred Lady Red Stone)
	IsoDraw.box(self, Vector3(-18, -18, 8), Vector3(36, 36, 16), C_MARTYRED_DARK)

	# Gothic Stained-Glass Lancet Archway
	var door_p = IsoDraw.project(0, 18, 2)
	draw_rect(Rect2(door_p - Vector2(10, 14), Vector2(20, 14)), C_MARBLE_DARK, true)
	draw_rect(Rect2(door_p - Vector2(10, 14), Vector2(20, 14)), C_ECCLESIARCH_G, false, 1.6)

	# Rose Window / Golden Altar Glow
	var glow_flicker = 0.7 + sin(idle_anim_timer * 6.0) * 0.3
	draw_circle(door_p - Vector2(0, 7), 5.0, Color(C_FIRE_AMBER.r, C_FIRE_AMBER.g, C_FIRE_AMBER.b, glow_flicker * 0.6))
	draw_circle(door_p - Vector2(0, 7), 2.2, Color.WHITE)

	# 6. UPPER GOTHIC ROOF & SPIRE
	IsoDraw.box(self, Vector3(-12, -12, 24), Vector3(24, 24, 12), C_MARBLE_MID)

	# Golden Fleur-de-lis Spire Apex
	var apex_p = IsoDraw.project(0, 0, 36)
	draw_line(apex_p, apex_p + Vector2(0, -18), C_ECCLESIARCH_G, 2.5)
	
	# Fleur-de-lis petals at spire tip
	var tip = apex_p + Vector2(0, -18)
	draw_colored_polygon(PackedVector2Array([
		tip, tip + Vector2(-6, -4), tip + Vector2(0, -10), tip + Vector2(6, -4)
	]), C_ECCLESIARCH_G)
	draw_circle(tip + Vector2(0, -2), 2.5, C_ECCLESIARCH_G)

	# 7. HANGING PURITY SEALS
	IsoDraw.purity_seal(self, IsoDraw.project(-18, 16, 14), 10.0)
	IsoDraw.purity_seal(self, IsoDraw.project(18, 16, 14), 10.0)

	# 8. TWIN PROMETHEUM BRAZIERS (Left and Right of entrance)
	for bx in [-36.0, 36.0]:
		var b_base = IsoDraw.project(bx, 24, 0)
		draw_set_transform(b_base, 0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 6.0, Color(0.01, 0.01, 0.02, 0.45))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

		# Iron Brazier Stand
		draw_line(b_base, b_base + Vector2(0, -14), C_STEEL_DARK, 3.5)
		draw_line(b_base + Vector2(-4, -14), b_base + Vector2(4, -14), C_ECCLESIARCH_G, 2.2)

		# Fire Flames
		var flame_h = 10.0 + sin(idle_anim_timer * 10.0 + bx) * 4.0
		var f_top = b_base + Vector2(0, -14 - flame_h)
		var fire_poly = PackedVector2Array([
			b_base + Vector2(-5, -14), f_top, b_base + Vector2(5, -14)
		])
		draw_colored_polygon(fire_poly, C_FIRE_AMBER)
		draw_colored_polygon(PackedVector2Array([
			b_base + Vector2(-2.5, -14), f_top + Vector2(0, 4), b_base + Vector2(2.5, -14)
		]), C_FIRE_WHITE)

# ==============================================================================
# UNSHADED HOLY CANDLELIGHT & PROMETHEUM GLOW OVERLAY
# ==============================================================================
class OutpostGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		var pulse = 0.75 + sin(p.idle_anim_timer * 4.0) * 0.25
		var gold = Color(0.88, 0.72, 0.28, 0.90 * pulse)

		# 1. Altar Rose Window Light
		var door_p = IsoDraw.project(0, 18, 2)
		draw_circle(door_p - Vector2(0, 7), 6.0 * pulse, Color(1.0, 0.7, 0.2, 0.8))
		draw_circle(door_p - Vector2(0, 7), 2.5, Color.WHITE)

		# 2. Spire Fleur-de-lis Halo
		var apex_p = IsoDraw.project(0, 0, 36) + Vector2(0, -20)
		draw_circle(apex_p, 4.0 * pulse, gold)
		draw_circle(apex_p, 1.5, Color.WHITE)

		# 3. Brazier Flame Cores & Drifting Embers
		for bx in [-36.0, 36.0]:
			var b_base = IsoDraw.project(bx, 24, 0)
			var f_center = b_base + Vector2(0, -18)
			draw_circle(f_center, 4.5 * pulse, Color(1.0, 0.65, 0.15, 0.85))
			draw_circle(f_center, 2.0, Color.WHITE)

			# Drifting holy spark embers
			for s in range(2):
				var ember_y = fmod(p.idle_anim_timer * 22.0 + s * 14.0, 24.0)
				var ember_x = sin(p.idle_anim_timer * 5.0 + s + bx) * 5.0
				draw_circle(f_center - Vector2(ember_x, ember_y), 1.2, Color(1.0, 0.9, 0.4, 1.0 - (ember_y / 24.0)))

		# 4. Status Badge Text
		var prompt = "⚜️ SORORITAS SANCTUARY [E] ⚜️"
		if p.quest_state == QuestState.IN_PROGRESS: prompt = "QUEST: RECOVER SEBASTIAN RELIC"
		elif p.quest_state == QuestState.RELIC_FOUND: prompt = "[E] DELIVER SEBASTIAN RELIC"
		elif p.quest_state == QuestState.COMPLETED: prompt = "⚜️ ETERNAL VIGIL ACTIVE AT BASE ⚜️"

		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(-90, -56), prompt, HORIZONTAL_ALIGNMENT_CENTER, 180, 8, gold)
