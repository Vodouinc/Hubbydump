# res://NecronTomb.gd
extends StaticBody2D
class_name NecronTomb

enum TombState { DORMANT = 0, HACKING = 1, AWAKENED = 2, REWARD_READY = 3, COMPLETED = 4 }

var tomb_state: TombState = TombState.DORMANT
var hack_timer: float = 15.0
const HACK_DURATION: float = 15.0
var hack_spawn_wave_timer: float = 0.0
var idle_anim_timer: float = 0.0

var cryptek_boss_instance: Node2D = null
var glow_layer: Node2D = null
var point_light: PointLight2D = null

# --- DYNASTIC PALETTE ---
const C_BLACKSTONE   := Color(0.06, 0.08, 0.10)
const C_BLACKSTONE_M := Color(0.12, 0.15, 0.18)
const C_NECRON_GOLD  := Color(0.78, 0.65, 0.25)
const C_GAUSS_GREEN  := Color(0.20, 1.00, 0.45)
const C_GAUSS_CORE   := Color(0.85, 1.00, 0.90)

func _ready() -> void:
	add_to_group("objectives")
	add_to_group("necron_tomb")
	add_to_group("quest_interactables")

	# Heavy 3D Collision Base
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(90, 70)
	col.shape = shape
	add_child(col)

	_setup_unshaded_glow_overlay()
	_setup_beacon_light()

func _setup_beacon_light() -> void:
	point_light = LightUtils.create_point_light(Color(0.20, 1.0, 0.45), 1.8, 4.2)
	point_light.name = "NecronBeaconLight"
	add_child(point_light)

func _setup_unshaded_glow_overlay() -> void:
	glow_layer = TombGlowRenderer.new()
	glow_layer.name = "TombGlowOverlay"
	var mat = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow_layer.material = mat
	add_child(glow_layer)

func _process(delta: float) -> void:
	idle_anim_timer += delta

	if tomb_state == TombState.HACKING:
		hack_timer -= delta
		hack_spawn_wave_timer += delta

		if hack_spawn_wave_timer >= 3.5:
			hack_spawn_wave_timer = 0.0
			_spawn_scarab_pack()

		if hack_timer <= 0.0:
			_awaken_tomb_boss()

	queue_redraw()
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func interact(player_node: Node2D) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(1, "request_interact_tomb", player_node.name)
		return

	_handle_tomb_interaction()

@rpc("any_peer", "call_local", "reliable")
func request_interact_tomb(_player_name: String) -> void:
	_handle_tomb_interaction()

func _handle_tomb_interaction() -> void:
	match tomb_state:
		TombState.DORMANT:
			tomb_state = TombState.HACKING
			hack_timer = HACK_DURATION
			_broadcast_tomb_state()
			AudioManager.play_sfx("volkite_beam", global_position, 2.0, 0.6)
			_announce_dialogue("⚠️ COGITATOR: Deciphering Noctilith Glyph Lock! DEFEND THE MONOLITH!")
			_spawn_scarab_pack()

		TombState.REWARD_READY:
			tomb_state = TombState.COMPLETED
			_broadcast_tomb_state()
			_grant_tomb_reward()

func _spawn_scarab_pack() -> void:
	for i in range(3):
		var scarab = NecronEnemy.new()
		scarab.necron_type = NecronEnemy.NecronType.SCARAB
		scarab.position = global_position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(55.0, 110.0)
		get_parent().add_child(scarab)

func _awaken_tomb_boss() -> void:
	tomb_state = TombState.AWAKENED
	_broadcast_tomb_state()

	AudioManager.play_sfx("orbital_strike", global_position, 3.0, 0.6)
	_announce_dialogue("☠️ DANGER: Ancient Necron Cryptek Warden has awakened from stasis!")

	cryptek_boss_instance = NecronEnemy.new()
	cryptek_boss_instance.necron_type = NecronEnemy.NecronType.CRYPTEK_BOSS
	cryptek_boss_instance.position = global_position + Vector2(0, 65)
	get_parent().add_child(cryptek_boss_instance)

	for offset in [Vector2(-50, 55), Vector2(50, 55)]:
		var warrior = NecronEnemy.new()
		warrior.necron_type = NecronEnemy.NecronType.WARRIOR
		warrior.position = global_position + offset
		get_parent().add_child(warrior)

func notify_cryptek_slain() -> void:
	tomb_state = TombState.REWARD_READY
	_broadcast_tomb_state()
	AudioManager.play_sfx("binary_canticle", global_position, 2.0, 1.2)
	_announce_dialogue("✨ CRYPTEK VANQUISHED! Interact with the Monolith [E] to extract Noctilith Archeotech!")

func _grant_tomb_reward() -> void:
	AudioManager.play_sfx("orbital_strike", global_position, 3.0, 1.3)
	_announce_dialogue("⚡ NOCTILITH ARCHEOTECH SECURED: +180 Scrap, +60 Requisition & Gauss Turrets unlocked!")

	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.has_method("unlock_necron_archeotech"):
		main_node.unlock_necron_archeotech()

func _broadcast_tomb_state() -> void:
	if multiplayer.has_multiplayer_peer():
		rpc("sync_tomb_state", int(tomb_state))
	else:
		sync_tomb_state(int(tomb_state))

@rpc("call_local", "reliable")
func sync_tomb_state(state_idx: int) -> void:
	tomb_state = state_idx as TombState
	queue_redraw()
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()

func _announce_dialogue(msg: String) -> void:
	get_tree().call_group("event_banner", "post_banner", 
		"💀 NOCTILITH ARCHIVES • ANCIENT TOMB", 
		msg, 
		2 # NECRON_ARCHEOTECH
	)

func _draw() -> void:
	var pulse = 0.70 + sin(idle_anim_timer * 3.5) * 0.30

	# 1. GROUND LEY-LINE CIRCUIT MATRIX (180px radius radiating out into desert sand)
	draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.50))
	draw_circle(Vector2.ZERO, 150.0, Color(0.01, 0.02, 0.03, 0.55)) # Crater shadow
	draw_arc(Vector2.ZERO, 140.0, 0, TAU, 48, Color(C_GAUSS_GREEN.r, C_GAUSS_GREEN.g, C_GAUSS_GREEN.b, 0.35 * pulse), 1.6)
	draw_arc(Vector2.ZERO, 90.0, 0, TAU, 32, Color(C_GAUSS_GREEN.r, C_GAUSS_GREEN.g, C_GAUSS_GREEN.b, 0.55 * pulse), 1.4)

	# Radiating Circuit Branches
	for i in range(8):
		var a = i * (TAU / 8.0)
		var p_in = Vector2(cos(a), sin(a)) * 55.0
		var p_out = Vector2(cos(a), sin(a)) * 140.0
		var p_elbow = Vector2(cos(a + 0.15), sin(a + 0.15)) * 110.0
		draw_line(p_in, p_elbow, Color(C_GAUSS_GREEN.r, C_GAUSS_GREEN.g, C_GAUSS_GREEN.b, 0.45 * pulse), 1.8)
		draw_line(p_elbow, p_out, Color(C_GAUSS_GREEN.r, C_GAUSS_GREEN.g, C_GAUSS_GREEN.b, 0.65 * pulse), 1.8)
		draw_circle(p_out, 3.0, C_GAUSS_GREEN)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# 2. STEPPED PYRAMIDAL MONOLITH (Using Isometric Projection)
	# Tier 1: Giant Stepped Base
	IsoDraw.box(self, Vector3(-34, -34, 0), Vector3(68, 68, 8), C_BLACKSTONE)
	
	# Tier 2: Mid-Ziggurat Terrace with Gold Dynastic Inlays
	IsoDraw.box(self, Vector3(-24, -24, 8), Vector3(48, 48, 14), C_BLACKSTONE_M)
	var mid_p = IsoDraw.project(0, 24, 12)
	draw_line(mid_p - Vector2(16, 0), mid_p + Vector2(16, 0), C_NECRON_GOLD, 1.8)

	# Tier 3: Apex Capstone & Dynastic Ankh
	IsoDraw.box(self, Vector3(-14, -14, 22), Vector3(28, 28, 16), C_BLACKSTONE)
	var apex_p = IsoDraw.project(0, 0, 38)
	draw_circle(apex_p, 4.5, C_NECRON_GOLD)
	draw_circle(apex_p, 2.5, C_GAUSS_GREEN)

	# 3. PORTAL ARCHWAY (South-Facing Gate)
	var door_p = IsoDraw.project(0, 24, 0)
	draw_rect(Rect2(door_p - Vector2(12, 16), Vector2(24, 16)), C_BLACKSTONE, true)
	draw_rect(Rect2(door_p - Vector2(12, 16), Vector2(24, 16)), C_NECRON_GOLD, false, 1.6)

	# Swirling Gauss Plasma Vortex
	var vortex_pulse = 0.75 + sin(idle_anim_timer * 7.0) * 0.25
	draw_rect(Rect2(door_p - Vector2(10, 14), Vector2(20, 14)), Color(C_GAUSS_GREEN.r, C_GAUSS_GREEN.g, C_GAUSS_GREEN.b, 0.45 * vortex_pulse), true)

	# 4. FOUR HOVERING BLACKSTONE CORNER OBELISKS
	var hover_z = 12.0 + sin(idle_anim_timer * 3.0) * 4.0
	for corner in [Vector2(-48, -48), Vector2(48, -48), Vector2(-48, 48), Vector2(48, 48)]:
		var p_base = IsoDraw.project(corner.x, corner.y, 0)
		draw_set_transform(p_base, 0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 6.0, Color(0.01, 0.01, 0.02, 0.4)) # Ground shadow
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

		# Floating Spire Pylon
		IsoDraw.box(self, Vector3(corner.x - 3, corner.y - 3, hover_z), Vector3(6, 6, 18), C_BLACKSTONE)
		var p_tip = IsoDraw.project(corner.x, corner.y, hover_z + 18)
		draw_circle(p_tip, 2.5, C_GAUSS_GREEN)

# ==============================================================================
# UNSHADED GLOW & LIGHTNING ARC OVERLAY
# ==============================================================================
class TombGlowRenderer extends Node2D:
	func _draw() -> void:
		var p = get_parent()
		if not p: return

		var pulse = 0.75 + sin(p.idle_anim_timer * 4.5) * 0.25
		var green = Color(0.20, 1.00, 0.45, 0.90 * pulse)
		var core_col = Color(0.85, 1.00, 0.90, pulse)

		# 1. Doorway Portal Core
		var door_p = IsoDraw.project(0, 24, 0)
		draw_circle(door_p - Vector2(0, 7), 5.0 * pulse, green)
		draw_circle(door_p - Vector2(0, 7), 2.2, core_col)

		# 2. Apex Capstone Glyph
		var apex_p = IsoDraw.project(0, 0, 38)
		draw_circle(apex_p, 3.5 * pulse, green)

		# 3. Pylon Energy Arc Lighting (Arcs from corner pylons to apex capstone)
		var hover_z = 12.0 + sin(p.idle_anim_timer * 3.0) * 4.0
		for corner in [Vector2(-48, -48), Vector2(48, -48), Vector2(-48, 48), Vector2(48, 48)]:
			var p_tip = IsoDraw.project(corner.x, corner.y, hover_z + 18)
			draw_circle(p_tip, 3.5 * pulse, green)
			draw_circle(p_tip, 1.4, Color.WHITE)

			# Intermittent Tesla Arcs
			if fmod(p.idle_anim_timer * 2.0 + corner.x, 2.0) < 0.35:
				var mid_arc = p_tip.lerp(apex_p, 0.5) + Vector2(randf_range(-6, 6), randf_range(-6, 6))
				draw_line(p_tip, mid_arc, Color(0.20, 1.0, 0.45, 0.75), 1.8)
				draw_line(mid_arc, apex_p, Color(0.20, 1.0, 0.45, 0.75), 1.8)
				draw_line(p_tip, mid_arc, Color.WHITE, 1.0)
				draw_line(mid_arc, apex_p, Color.WHITE, 1.0)

		# 4. Status Badge Text
		var prompt = "◆ ANCIENT TOMB MONOLITH [E] ◆"
		if p.tomb_state == TombState.HACKING: prompt = "DECIPHERING GLYPH: %.1fs" % p.hack_timer
		elif p.tomb_state == TombState.AWAKENED: prompt = "☠️ CRYPTEK WARDEN ACTIVE"
		elif p.tomb_state == TombState.REWARD_READY: prompt = "[E] EXTRACT ARCHEOTECH"
		elif p.tomb_state == TombState.COMPLETED: prompt = "◆ NOCTILITH CORE SECURED ◆"

		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(-80, -58), prompt, HORIZONTAL_ALIGNMENT_CENTER, 160, 8, green)
