extends Node2D
 
const PORT = 7000
const DEFAULT_IP = "127.0.0.1"
 
# --------------------------------------------------
# CLASS DEFINITIONS & DATA
# --------------------------------------------------
enum CharacterClass {
	ADMECH_TECHPRIEST,
	SKITARII_MARSHAL,
	SISTER_OF_BATTLE,
	SPACE_MARINE
}
 
const CLASS_DATA = {
	CharacterClass.ADMECH_TECHPRIEST: {
		"name": "Tech-Priest Enginseer",
		"faction": "Adeptus Mechanicus",
		"role": "Defense & Fortification"
	},
	CharacterClass.SKITARII_MARSHAL: {
		"name": "Skitarii Marshal",
		"faction": "Adeptus Mechanicus",
		"role": "Recon & Direct Combat"
	}
}
 
@export var max_waves: int = 15
 
var player_scene = preload("res://Player.tscn")
var enemy_scene = preload("res://Enemy.tscn")
var bullet_scene = preload("res://Bullet.tscn")
var scrap_scene = preload("res://Scrap.tscn")
var building_scene = preload("res://Building.tscn")
var waaagh_idol_scene = preload("res://WaaaghIdol.tscn")
 
# Class Preview Node
var class_preview_node: Node2D = null
 
var peer: ENetMultiplayerPeer
var enemy_count: int = 0
var bullet_count: int = 0
var building_count: int = 0
 
# Resource Totals
var scrap_amount: int = 0
var requisition_amount: int = 0
 
# Class Tracking per Peer ID
var player_classes: Dictionary = {}
var player_ready: Dictionary = {}
var match_started: bool = false
 
# Wave Management
var current_wave: int = 0
var enemies_left_to_spawn: int = 0
var active_enemies: int = 0
var is_wave_active: bool = false
var wave_timer: Timer
var wave_spawn_queue: Array[int] = []
var wave_player_count: int = 1
var spawn_lane_angles: Array[float] = []
var spawn_serial: int = 0
var objective_count: int = 0
var wave_squad_queue: Array[Dictionary] = [] # Queue of { "lane": int, "units": Array[int], "delay": float }
var current_squad_timer: float = 0.0

# --- GLOBAL TECH TREE UNLOCKS ---
var tech_shields_unlocked: bool = false
var tech_lasers_unlocked: bool = false
var tech_nanobots_unlocked: bool = false

var research_ui_node: Control = null
var tech_magnet_unlocked: bool = false
 
# --------------------------------------------------
# UI & NETWORK NODE REFERENCES (Using % Unique Names)
# --------------------------------------------------
@onready var ui_layer: CanvasLayer = get_node_or_null("UI")
@onready var hud_root: Control = get_node_or_null("%RootControl")
@onready var spawner: MultiplayerSpawner = get_node_or_null("MultiplayerSpawner")

# Lobby & Connection UI
@onready var lobby_panel: Control = get_node_or_null("%ClassSelectUI")
@onready var host_button: Button = get_node_or_null("%HostButton")
@onready var join_button: Button = get_node_or_null("%JoinButton")
@onready var ip_input: LineEdit = get_node_or_null("%IPInput")
@onready var resource_label: Label = get_node_or_null("%ResourceLabel")
@onready var top_bar: Control = get_node_or_null("%TopBar")
@onready var wave_info_label: Label = get_node_or_null("%WaveInfoLabel")

# Game Over UI
@onready var game_over_ui: Control = get_node_or_null("%GameOverUI")
@onready var game_over_panel: PanelContainer = get_node_or_null("%GameOverPanel")
@onready var title_label: Label = get_node_or_null("%TitleLabel")
@onready var subtitle_label: Label = get_node_or_null("%SubtitleLabel")
@onready var restart_button: Button = get_node_or_null("%RestartButton")
@onready var bg_drawing_node: Control = get_node_or_null("%BackgroundDrawingNode")

# Class Selection Buttons & Info
@onready var techpriest_button: Button = get_node_or_null("%TechPriestButton")
@onready var skitarii_button: Button = get_node_or_null("%SkitariiButton")
@onready var ready_button: Button = get_node_or_null("%ReadyButton")
@onready var class_label: Label = get_node_or_null("%SelectedClassLabel")
@onready var roster_label: Label = get_node_or_null("%RosterLabel")
@onready var session_label: Label = get_node_or_null("%SessionLabel")

# Navigation Node Reference
@onready var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
 
var my_selected_class: CharacterClass = CharacterClass.ADMECH_TECHPRIEST
var pause_menu_ui_node: Control = null
var active_paused_peers: Dictionary = {}
var is_ready: bool = false
var settings_ui_node: Control = null
 
func _ready():
	add_to_group("main")
	if hud_root:
		hud_root.theme = AdmechTheme.make()
	if host_button: host_button.pressed.connect(_on_host_pressed)
	if join_button: join_button.pressed.connect(_on_join_pressed)
	if restart_button: restart_button.pressed.connect(_on_restart_pressed)
	
	if techpriest_button: techpriest_button.pressed.connect(_on_techpriest_selected)
	if skitarii_button: skitarii_button.pressed.connect(_on_skitarii_selected)
	if ready_button: ready_button.pressed.connect(_on_ready_pressed)
	
	if game_over_ui: game_over_ui.hide()
	if top_bar: top_bar.hide()
	
	# Network signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	
	spawner.spawn_function = _custom_spawner
	
	_show_lobby_ui()
	_update_class_ui()
	_refresh_lobby_roster()
	_setup_research_ui()
	_setup_settings_ui()
	_setup_pause_menu_ui()
 
# --------------------------------------------------
# CLASS SELECTION & LOBBY UI
# --------------------------------------------------
 
func _setup_settings_ui():
	if not has_node("UI/SettingsUI"):
		var s_ui = SettingsUI.new()
		s_ui.name = "SettingsUI"
		$UI.add_child(s_ui)
		settings_ui_node = s_ui
		
	# Connect existing host/join UI or add a Settings Button
	_add_settings_button_to_ui()

func _setup_pause_menu_ui():
	if not has_node("UI/PauseMenuUI"):
		var p_ui = PauseMenuUI.new()
		p_ui.name = "PauseMenuUI"
		$UI.add_child(p_ui)
		pause_menu_ui_node = p_ui

func _add_settings_button_to_ui():
	# Add a settings cog button to the top bar
	if top_bar and not top_bar.has_node("SettingsBtn"):
		var btn = Button.new()
		btn.name = "SettingsBtn"
		btn.text = "⚙ AUDIO [O]"
		btn.custom_minimum_size = Vector2(100, 28)
		btn.pressed.connect(func():
			if settings_ui_node and settings_ui_node.has_method("toggle_settings"):
				settings_ui_node.toggle_settings()
		)
		top_bar.add_child(btn)

func _setup_research_ui():
	if not has_node("UI/ResearchUI"):
		var r_ui = ResearchUI.new()
		r_ui.name = "ResearchUI"
		$UI.add_child(r_ui)
		research_ui_node = r_ui

func _update_class_ui():
	if CLASS_DATA.has(my_selected_class):
		var class_info = CLASS_DATA[my_selected_class]
		if class_label:
			class_label.text = class_info["name"] + "\n" + class_info["role"]
		_update_class_preview()
		_style_class_buttons()
 
func _style_class_buttons() -> void:
	var selected := Color(0.35, 0.90, 1.0, 1.0)
	var idle := Color.WHITE
	if techpriest_button:
		techpriest_button.modulate = selected if my_selected_class == CharacterClass.ADMECH_TECHPRIEST else idle
	if skitarii_button:
		skitarii_button.modulate = selected if my_selected_class == CharacterClass.SKITARII_MARSHAL else idle
 
func _update_class_preview() -> void:
	if match_started:
		return
	if is_instance_valid(class_preview_node):
		class_preview_node.free()
		class_preview_node = null
		
	var preview_player = player_scene.instantiate()
	class_preview_node = preview_player
	
	preview_player.name = "ClassPreview"
	preview_player.process_mode = PROCESS_MODE_DISABLED
	if preview_player.has_node("CollisionShape2D"):
		preview_player.get_node("CollisionShape2D").disabled = true
	
	if preview_player.has_node("Camera2D"):
		var cam = preview_player.get_node("Camera2D")
		cam.enabled = false
		cam.queue_free()
	
	if preview_player.has_method("set_player_class"):
		var is_techpriest = (my_selected_class == CharacterClass.ADMECH_TECHPRIEST)
		preview_player.set_player_class(preview_player.PlayerClass.MELEE if is_techpriest else preview_player.PlayerClass.RANGED)
		
	preview_player.position = Vector2(430, 310)
	add_child(preview_player)
 
func _clear_class_preview() -> void:
	if is_instance_valid(class_preview_node):
		class_preview_node.free()
		class_preview_node = null
 
func _on_techpriest_selected():
	my_selected_class = CharacterClass.ADMECH_TECHPRIEST
	_update_class_ui()
	_sync_lobby_loadout()
 
func _on_skitarii_selected():
	my_selected_class = CharacterClass.SKITARII_MARSHAL
	_update_class_ui()
	_sync_lobby_loadout()
 
func _on_ready_pressed():
	if not _is_in_session():
		_set_session_text("Host or join a session first.")
		return
	is_ready = not is_ready
	_update_ready_button()
	_sync_lobby_loadout()
 
func _update_ready_button() -> void:
	if ready_button:
		ready_button.text = "UNREADY" if is_ready else "READY UP"
		ready_button.disabled = not _is_in_session()
 
func _is_in_session() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED
 
func _sync_lobby_loadout():
	if not _is_in_session() or match_started:
		_refresh_lobby_roster()
		return
	if multiplayer.is_server():
		player_classes[1] = my_selected_class
		player_ready[1] = is_ready
		_broadcast_lobby_state()
		_try_start_match()
	else:
		rpc_id(1, "report_lobby_loadout", int(my_selected_class), is_ready)
 
func _show_lobby_ui():
	match_started = false
	is_ready = false
	
	if lobby_panel: lobby_panel.show()
	if host_button: host_button.show()
	if join_button: join_button.show()
	if ip_input: ip_input.show()
	if techpriest_button: techpriest_button.show()
	if skitarii_button: skitarii_button.show()
	if ready_button: ready_button.show()
	if class_label: class_label.show()
	if roster_label: roster_label.show()
	if session_label: session_label.show()
	
	if top_bar: top_bar.hide()
	
	_update_ready_button()
	_update_class_ui()
	_refresh_lobby_roster()

func _hide_lobby_ui():
	_clear_class_preview()
	
	if lobby_panel: lobby_panel.hide()
	if host_button: host_button.hide()
	if join_button: join_button.hide()
	if ip_input: ip_input.hide()
	if techpriest_button: techpriest_button.hide()
	if skitarii_button: skitarii_button.hide()
	if ready_button: ready_button.hide()
	if class_label: class_label.hide()
	if roster_label: roster_label.hide()
	if session_label: session_label.hide()
	
	if top_bar: top_bar.show()

func _set_session_text(message: String) -> void:
	if session_label:
		session_label.text = message
 
func _refresh_lobby_roster() -> void:
	if not roster_label:
		return
	if not _is_in_session():
		roster_label.text = "No vox-link. Host a forge-fane or join an IP."
		_set_session_text("Standing by.")
		return
 
	var lines: PackedStringArray = []
	var ids: Array = player_classes.keys()
	ids.sort()
	for id in ids:
		var class_id: int = int(player_classes[id])
		var class_info = CLASS_DATA.get(class_id, {"name": "Unknown"})
		var ready_mark = "READY" if player_ready.get(id, false) else "STANDBY"
		var you = "  (you)" if _is_local_peer(int(id)) else ""
		lines.append("%s  —  %s%s" % [class_info["name"], ready_mark, you])
	roster_label.text = "\n".join(lines) if not lines.is_empty() else "Cadre assembling..."
 
func _is_local_peer(id: int) -> bool:
	if not _is_in_session():
		return id == 1
	return id == multiplayer.get_unique_id()
 
func _broadcast_lobby_state() -> void:
	if not multiplayer.is_server():
		return
	var payload: Array = []
	for id in player_classes.keys():
		payload.append([int(id), int(player_classes[id]), player_ready.get(id, false)])
	rpc("sync_lobby_state", payload, match_started)
	_refresh_lobby_roster()
 
@rpc("any_peer", "reliable")
func report_lobby_loadout(chosen_class: int, ready: bool) -> void:
	if not multiplayer.is_server() or match_started:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	player_classes[sender_id] = chosen_class
	player_ready[sender_id] = ready
	_broadcast_lobby_state()
	_try_start_match()
 
@rpc("authority", "call_local", "reliable")
func sync_lobby_state(payload: Array, started: bool) -> void:
	player_classes.clear()
	player_ready.clear()
	for entry in payload:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 3:
			continue
		var id: int = int(entry[0])
		player_classes[id] = int(entry[1])
		player_ready[id] = bool(entry[2])
	_refresh_lobby_roster()
	if started and not match_started:
		_begin_match_local()
 
func _try_start_match() -> void:
	if not multiplayer.is_server() or match_started:
		return
	var ids := _session_peer_ids()
	if ids.is_empty():
		return
		
	for id in ids:
		if not player_ready.get(id, false):
			_set_session_text("Waiting on the cadre to Ready.")
			return
			
	_begin_match()
 
func _session_peer_ids() -> Array[int]:
	var ids: Array[int] = [1]
	if multiplayer.has_multiplayer_peer():
		for peer_id in multiplayer.get_peers():
			ids.append(int(peer_id))
	return ids
 
func _begin_match() -> void:
	if not multiplayer.is_server() or match_started:
		return
	match_started = true
	_broadcast_lobby_state()
	rpc("sync_match_started")
	for id in _session_peer_ids():
		spawn_player(id)
	start_next_wave()
 
@rpc("authority", "call_local", "reliable")
func sync_match_started() -> void:
	_begin_match_local()
 
func _begin_match_local() -> void:
	match_started = true
	_hide_lobby_ui()
	if resource_label:
		resource_label.text = "SCRAP  0    REQ  0"
	if wave_info_label:
		wave_info_label.text = "PERIMETER ARMED"
 
func _on_host_pressed():
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	if error != OK: 
		_set_session_text("Failed to host. Port %d may be in use." % PORT)
		return
	
	multiplayer.multiplayer_peer = peer
	match_started = false
	is_ready = false
	player_classes.clear()
	player_ready.clear()
	player_classes[1] = my_selected_class
	player_ready[1] = false
	_update_ready_button()
	_set_session_text("Hosting on port %d — Ready when the cadre is set." % PORT)
	_broadcast_lobby_state()
 
func _on_join_pressed():
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		
	var ip = ip_input.text if ip_input.text != "" else DEFAULT_IP
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) == OK:
		multiplayer.multiplayer_peer = peer
		_set_session_text("Connecting to %s..." % ip)
		_update_ready_button()
	else:
		_set_session_text("Failed to reach %s." % ip)
 
func spawn_player(peer_id: int):
	if not multiplayer.is_server(): return
	
	for p in get_tree().get_nodes_in_group("players"):
		if p.name == str(peer_id):
			return
	
	var chosen_class = player_classes.get(peer_id, CharacterClass.SKITARII_MARSHAL)
	var spawn_data = {
		"type": "player",
		"peer_id": peer_id,
		"class": chosen_class
	}
	if spawner:
		spawner.spawn(spawn_data)
 
@rpc("any_peer", "call_local", "reliable")
func select_class(chosen_class: int):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	player_classes[sender_id] = chosen_class
	if multiplayer.is_server() and match_started:
		spawn_player(sender_id)
 
# --- MULTIPLAYER PAUSE SYNCHRONIZATION ---

@rpc("any_peer", "call_local", "reliable")
func request_set_player_paused(is_paused: bool):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1

	if is_paused:
		active_paused_peers[sender_id] = true
	else:
		active_paused_peers.erase(sender_id)

	# The game stays paused as long as AT LEAST ONE player is in their menu!
	var should_pause = not active_paused_peers.is_empty()
	rpc("sync_global_pause", should_pause)

@rpc("call_local", "reliable")
func sync_global_pause(is_paused: bool):
	get_tree().paused = is_paused
	get_tree().call_group("pause_menu", "update_global_pause_state", is_paused)

# --------------------------------------------------
# ENHANCED WAVE MANAGEMENT & COMPOSITION
# --------------------------------------------------
 
func start_next_wave():
	if not multiplayer.is_server(): return
	
	current_wave += 1
	if current_wave > max_waves:
		game_over(true)
		return
 
	# Dynamic Totem Drops: A new war camp drops into the desert every 2 waves!
	if current_wave in [2, 4, 6, 8, 10, 12, 14]:
		spawn_waaagh_idol()
		
	wave_player_count = max(1, get_tree().get_nodes_in_group("players").size())
	spawn_lane_angles = _build_spawn_lanes(current_wave, wave_player_count)
	wave_squad_queue = _build_wave_squads(current_wave, wave_player_count)
	
	enemies_left_to_spawn = 0
	for squad in wave_squad_queue:
		enemies_left_to_spawn += squad["units"].size()
		
	is_wave_active = true
	_broadcast_wave_hud()
	
	if wave_timer == null:
		wave_timer = Timer.new()
		wave_timer.timeout.connect(_spawn_squad_tick)
		add_child(wave_timer)
		
	# Waves arrive faster if 3+ totems are active!
	var speed_up = 0.75 if get_active_totem_count() >= 3 else 1.0
	wave_timer.wait_time = 2.0 * speed_up
	wave_timer.start()

 
func _spawn_squad_tick():
	if not wave_squad_queue.is_empty():
		var squad = wave_squad_queue.pop_front()
		_spawn_tactical_squad(squad)
		
		# Set delay until the NEXT squad assault arrives (creates a push -> clear -> push rhythm!)
		if not wave_squad_queue.is_empty():
			var next_squad = wave_squad_queue.front()
			wave_timer.wait_time = next_squad["delay"]
			wave_timer.start()
		else:
			wave_timer.stop()
	else:
		wave_timer.stop()

## Spawns an entire squad clustered together in their assigned lane
func _spawn_tactical_squad(squad: Dictionary):
	var lane_idx: int = squad["lane"]
	var units: Array = squad["units"]
	
	var base_node = get_tree().get_first_node_in_group("base")
	var center_pos = base_node.global_position if base_node else Vector2(500, 500)
	
	var lane_angle = spawn_lane_angles[lane_idx % spawn_lane_angles.size()]
	var spawn_dist = randf_range(700.0, 850.0)
	var squad_center = center_pos + Vector2.RIGHT.rotated(lane_angle) * spawn_dist
	
	for unit_type in units:
		enemy_count += 1
		# Cluster units within 45px radius of squad center (Meatshields screen heavy units!)
		var offset = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(10.0, 48.0)
		var spawn_pos = squad_center + offset
		
		var enemy_data = {
			"type": "enemy",
			"name": "Enemy_" + str(enemy_count),
			"enemy_type": unit_type,
			"position": spawn_pos,
			"is_objective_guard": false,
			"counts_toward_wave": true
		}
		
		if spawner:
			spawner.spawn(enemy_data)
			active_enemies += 1
			enemies_left_to_spawn = max(0, enemies_left_to_spawn - 1)
			
	rpc("sync_wave_info", current_wave, "WAVE " + str(current_wave) + "/" + str(max_waves) + " — " + str(enemies_left_to_spawn + active_enemies) + " CONTACTS")

# ===========================================================================
# WAAAGH mechanics
# ===========================================================================
func get_active_totem_count() -> int:
	return get_tree().get_nodes_in_group("objectives").size()

## Each active totem grants +12% speed to all attacking Orks
func get_waaagh_speed_multiplier() -> float:
	var count = get_active_totem_count()
	return 1.0 + (count * 0.12)

## Each active totem grants +10% damage to all attacking Orks
func get_waaagh_damage_multiplier() -> float:
	var count = get_active_totem_count()
	return 1.0 + (count * 0.10)

func _broadcast_wave_hud():
	var totem_count = get_active_totem_count()
	var buff_pct = int(totem_count * 12)
	var threat_tag = " | 🔥 WAAAGH! THREAT: " + str(totem_count) + " (+" + str(buff_pct) + "% SPD)" if totem_count > 0 else ""
	var hud_msg = "WAVE " + str(current_wave) + "/" + str(max_waves) + " — " + str(enemies_left_to_spawn + active_enemies) + " CONTACTS" + threat_tag
	rpc("sync_wave_info", current_wave, hud_msg)



# ==============================================================================
# SQUAD FORMATION GENERATOR
# ==============================================================================

func _build_wave_squads(wave: int, player_count: int) -> Array[Dictionary]:
	var threat_budget = int(round((14.0 + pow(wave, 1.36) * 6.2) * (1.0 + 0.65 * (player_count - 1))))
	var squads: Array[Dictionary] = []
	var lane_counter = 0
	
	while threat_budget > 0:
		var available_squads = _get_available_squad_templates(wave)
		var affordable: Array[Dictionary] = []
		
		for t in available_squads:
			if t["cost"] <= threat_budget:
				affordable.append(t)
				
		if affordable.is_empty():
			# Dump leftover points into a small gretchin chaff pack
			squads.append({
				"lane": lane_counter % max(1, spawn_lane_angles.size()),
				"units": [0, 0, 0],
				"delay": 3.0
			})
			break
			
		var chosen = affordable.pick_random()
		squads.append({
			"lane": lane_counter % max(1, spawn_lane_angles.size()),
			"units": chosen["units"].duplicate(),
			"delay": chosen["delay"]
		})
		
		threat_budget -= chosen["cost"]
		lane_counter += 1
		
	return squads

func _get_available_squad_templates(wave: int) -> Array[Dictionary]:
	var templates: Array[Dictionary] = []
	
	# 1. Gretchin Meatshield Swarm (Early & Flank distraction)
	templates.append({
		"name": "gretchin_swarm",
		"cost": 6,
		"units": [0, 0, 0, 0, 0, 0],
		"delay": 3.5
	})
	
	# 2. Squig Flank Stampede (Fast rushers)
	if wave >= 2:
		templates.append({
			"name": "squig_pack",
			"cost": 8,
			"units": [1, 1, 1, 1],
			"delay": 4.0
		})
		
	# 3. Ork Boy Patrol (Frontline infantry + chaff screen)
	if wave >= 3:
		templates.append({
			"name": "boyz_squad",
			"cost": 12,
			"units": [2, 2, 0, 0, 0, 0], # 2 Boyz screened by 4 Gretchin
			"delay": 4.5
		})
		
	# 4. Stormboy Jump Assault (Leapers bypass walls)
	if wave >= 6:
		templates.append({
			"name": "stormboy_raiders",
			"cost": 12,
			"units": [3, 3, 3, 1], # 3 Stormboyz + 1 Squig
			"delay": 5.0
		})
		
	# 5. Nob Warband (Armored Boss with Bodyguards & Meatshields)
	if wave >= 8:
		templates.append({
			"name": "nob_warband",
			"cost": 20,
			"units": [4, 2, 2, 0, 0, 0, 0], # 1 Nob + 2 Boyz + 4 Gretchin meatshields!
			"delay": 6.0
		})
		
	# 6. Armored Siege Column (Late game heavy assault)
	if wave >= 11:
		templates.append({
			"name": "armored_column",
			"cost": 28,
			"units": [4, 4, 3, 3, 2, 1, 1], # 2 Nobz, 2 Stormboyz, 1 Boy, 2 Squigs
			"delay": 7.0
		})
		
	return templates
 
func _build_wave_spawn_queue(wave: int, player_count: int) -> Array[int]:
	var threat_budget = int(round((12.0 + pow(wave, 1.35) * 5.8) * (1.0 + 0.65 * (player_count - 1))))
	# Unit threat costs: 0: Gretchin (1), 1: Squig (2), 2: Boy (4), 3: Stormboy (3), 4: Nob (8)
	var unit_costs = {0: 1, 1: 2, 2: 4, 3: 3, 4: 8}
	var roster = _get_wave_roster(wave)
	var queue: Array[int] = []
 
	while threat_budget > 0:
		var affordable: Array[Dictionary] = []
		var total_weight := 0.0
		for entry in roster:
			if unit_costs[entry.type] <= threat_budget:
				affordable.append(entry)
				total_weight += entry.weight
		if affordable.is_empty(): break
 
		var roll = randf() * total_weight
		var chosen_type: int = affordable.back().type
		for entry in affordable:
			roll -= entry.weight
			if roll <= 0.0: chosen_type = entry.type; break
		queue.append(chosen_type)
		threat_budget -= unit_costs[chosen_type]
 
	return queue


func _get_wave_roster(wave: int) -> Array[Dictionary]:
	if wave <= 2:
		return [{"type": 0, "weight": 0.80}, {"type": 1, "weight": 0.20}]
	elif wave <= 5:
		return [{"type": 0, "weight": 0.45}, {"type": 1, "weight": 0.35}, {"type": 2, "weight": 0.20}]
	elif wave <= 8:
		# Stormboyz start leaping over walls!
		return [{"type": 0, "weight": 0.30}, {"type": 1, "weight": 0.30}, {"type": 2, "weight": 0.25}, {"type": 3, "weight": 0.15}]
	elif wave <= 11:
		# Ork Nobz arrive!
		return [{"type": 0, "weight": 0.20}, {"type": 1, "weight": 0.25}, {"type": 2, "weight": 0.25}, {"type": 3, "weight": 0.20}, {"type": 4, "weight": 0.10}]
	else:
		# Late Game Waves (12-15): Heavy armored Nobz & Stormboy swarms!
		return [{"type": 0, "weight": 0.10}, {"type": 1, "weight": 0.25}, {"type": 2, "weight": 0.25}, {"type": 3, "weight": 0.25}, {"type": 4, "weight": 0.15}]

func _build_spawn_lanes(wave: int, player_count: int) -> Array[float]:
	var lane_count = 1
	if wave >= 4: lane_count += 1
	if wave >= 8: lane_count += 1
	if wave >= 12 and player_count >= 2: lane_count += 1
 
	var lanes: Array[float] = []
	var first_angle = randf() * TAU
	for i in range(lane_count):
		lanes.append(first_angle + (TAU * float(i) / float(lane_count)))
	return lanes
 
func notify_enemy_defeated():
	if multiplayer.is_server():
		active_enemies = max(0, active_enemies - 1)
		
		if enemies_left_to_spawn <= 0 and active_enemies == 0 and is_wave_active:
			is_wave_active = false
			rpc("sync_wave_info", current_wave, "WAVE CLEARED! Re-arm the perimeter — next wave in 10s...")
			get_tree().create_timer(10.0).timeout.connect(start_next_wave)
 
# --------------------------------------------------
# GAME OVER & REMATCH
# --------------------------------------------------
 
func spawn_enemy(enemy_type: int = 0, lane_index: int = -1):
	if not multiplayer.is_server(): return
	
	enemy_count += 1
	var spawn_angle = randf() * TAU
	if lane_index >= 0 and lane_index < spawn_lane_angles.size():
		spawn_angle = spawn_lane_angles[lane_index] + randf_range(-0.22, 0.22)
	var spawn_dist = randf_range(650.0, 800.0)
	var base_node = get_tree().get_first_node_in_group("base")
	var center_pos = base_node.global_position if base_node else Vector2(500, 500)
	
	var enemy_data = {
		"type": "enemy",
		"name": "Enemy_" + str(enemy_count),
		"enemy_type": enemy_type,
		"position": center_pos + Vector2.RIGHT.rotated(spawn_angle) * spawn_dist
	}
	
	if spawner:
		spawner.spawn(enemy_data)
 
func spawn_waaagh_idol() -> void:
	if not multiplayer.is_server():
		return
	objective_count += 1
	var base_node = get_tree().get_first_node_in_group("base")
	var center_pos = base_node.global_position if base_node else Vector2(500, 500)
	
	# Spawn 700 to 1000px out into the desert terrain!
	var camp_pos = center_pos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(720.0, 1020.0)
	
	if spawner:
		spawner.spawn({
			"type": "waaagh_idol",
			"name": "WaaaghIdol_" + str(objective_count),
			"position": camp_pos
		})
		
		# Spawn 6-10 camp defenders (Gretchen + Squigs + Boyz)
		var total_guards = 6 + int(current_wave * 0.5)
		for i in range(total_guards):
			var guard_type = 0
			if i % 3 == 0: guard_type = 1 # Squig
			elif i % 5 == 0 and current_wave >= 6: guard_type = 2 # Ork Boy
			spawn_objective_defender(camp_pos, guard_type)
 
func spawn_objective_defender(objective_pos: Vector2, enemy_type: int) -> void:
	if not spawner:
		return
	enemy_count += 1
	var guard_position = objective_pos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(45.0, 115.0)
	spawner.spawn({
		"type": "enemy",
		"name": "IdolGuard_" + str(enemy_count),
		"enemy_type": enemy_type,
		"position": guard_position,
		"is_objective_guard": true,
		"guard_anchor": objective_pos,
		"counts_toward_wave": false
	})
 
func game_over(is_victory: bool):
	if multiplayer.is_server():
		if wave_timer: wave_timer.stop()
		rpc("sync_game_over", is_victory)
 
@rpc("call_local", "reliable")
func sync_game_over(is_victory: bool):
	if game_over_ui:
		game_over_ui.show()
		
	if bg_drawing_node:
		bg_drawing_node.is_victory_screen = is_victory
		bg_drawing_node.queue_redraw()
		
		var theme_color = Color("#2b6cb0")
		
		if is_victory:
			title_label.text = "PRAISE THE OMNISSAH — VICTORY"
			title_label.add_theme_color_override("font_color", Color("#48bb78"))
			subtitle_label.text = "The facility successfully withstood all " + str(max_waves) + " waves of the xeno onslaught."
			theme_color = Color("#22543d")
		else:
			title_label.text = "CRITICAL SYSTEM FAILURE — DEFEAT"
			title_label.add_theme_color_override("font_color", Color("#f56565"))
			subtitle_label.text = "The core breach occurred on Wave " + str(current_wave) + ". The base has fallen."
			theme_color = Color("#742a2a")
			
		if game_over_panel and game_over_panel.has_theme_stylebox("panel"):
			var sb = game_over_panel.get_theme_stylebox("panel").duplicate()
			if sb is StyleBoxFlat:
				sb.bg_color = theme_color
				game_over_panel.add_theme_stylebox_override("panel", sb)
 
func _on_restart_pressed():
	rpc_id(1, "request_rematch")
 
@rpc("any_peer", "call_local", "reliable")
func request_rematch():
	if not multiplayer.is_server(): return
	rpc("execute_rematch")
 
@rpc("call_local", "reliable")
func execute_rematch():
	if game_over_ui: 
		game_over_ui.hide()
	
	current_wave = 0
	active_enemies = 0
	enemies_left_to_spawn = 0
	is_wave_active = false
	wave_spawn_queue.clear()
	spawn_lane_angles.clear()
	spawn_serial = 0
	scrap_amount = 0
	requisition_amount = 0
	building_count = 0
	wave_squad_queue.clear()
	
	# Reset Tech Tree
	tech_shields_unlocked = false
	tech_lasers_unlocked = false
	tech_nanobots_unlocked = false
	tech_magnet_unlocked = false
	
	if multiplayer.is_server():
		if wave_timer: 
			wave_timer.stop()
			
		for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
		for player in get_tree().get_nodes_in_group("players"): player.queue_free()
		for building in get_tree().get_nodes_in_group("buildings"): building.queue_free()
		for objective in get_tree().get_nodes_in_group("objectives"): objective.queue_free()
		for bg in get_tree().get_nodes_in_group("bodyguards"): bg.queue_free()
		for skull in get_tree().get_nodes_in_group("ServoSkull"): skull.queue_free()
		for scrap in get_tree().get_nodes_in_group("scrap"): scrap.queue_free()
		
		var base = get_tree().get_first_node_in_group("base")
		if base and base.has_method("sync_base_health"):
			base.rpc("sync_base_health", base.max_health)
		
		rpc("sync_resources", scrap_amount, requisition_amount)
		rpc("sync_tech_tree", false, false, false, false)
		request_navmesh_rebake()

	match_started = false
	for peer_id in player_ready.keys():
		player_ready[peer_id] = false
	is_ready = false
	
	_show_lobby_ui()
	_set_session_text("Match reset. Ready up when the cadre is set.")
	
	if multiplayer.is_server():
		_broadcast_lobby_state()
 
# --------------------------------------------------
# CUSTOM SPAWNER
# --------------------------------------------------
 
func _custom_spawner(data) -> Node:
	if typeof(data) == TYPE_ARRAY and data.size() > 0:
		data = data[0]
	if typeof(data) == TYPE_INT:
		var player = player_scene.instantiate()
		player.name = str(data)
		if player.has_method("set_player_class"):
			player.set_player_class(player.PlayerClass.MELEE if data == 1 else player.PlayerClass.RANGED)
		
		var base_node = get_tree().get_first_node_in_group("base")
		var base_pos = base_node.global_position if base_node else Vector2.ZERO
		player.position = base_pos + Vector2(-30.0 if data == 1 else 30.0, 100.0)
		return player
	elif typeof(data) == TYPE_DICTIONARY:
		var object_type = data.get("type", "")
		match object_type:
			"player":
				var player = player_scene.instantiate()
				var peer_id = data["peer_id"]
				player.name = str(peer_id)
				
				var selected_class = data.get("class", CharacterClass.ADMECH_TECHPRIEST)
				var is_techpriest = (selected_class == CharacterClass.ADMECH_TECHPRIEST)
				
				if player.has_method("set_player_class"):
					player.set_player_class(player.PlayerClass.MELEE if is_techpriest else player.PlayerClass.RANGED)
				var base_node = get_tree().get_first_node_in_group("base")
				var base_pos = base_node.global_position if base_node else Vector2.ZERO
				
				var x_offset = -30.0 if peer_id == 1 else 30.0
				
				if player_classes.size() > 2:
					var player_index = player_classes.keys().find(peer_id)
					if player_index != -1:
						x_offset = (player_index * 50.0) - 50.0
				player.position = base_pos + Vector2(x_offset, 100.0)
				return player
			"enemy":
				var enemy = enemy_scene.instantiate()
				enemy.name = str(data["name"])
				enemy.position = data["position"]
				if "enemy_type" in data:
					enemy.type = data["enemy_type"]
				if "is_objective_guard" in data:
					enemy.is_objective_guard = data["is_objective_guard"]
				if "guard_anchor" in data:
					enemy.guard_anchor = data["guard_anchor"]
				if "counts_toward_wave" in data:
					enemy.counts_toward_wave = data["counts_toward_wave"]
				return enemy
				
			"bodyguard":
				var bodyguard_scene = preload("res://SkitariiBodyguard.tscn")
				var bg = bodyguard_scene.instantiate()
				bg.name = str(data["name"])
				bg.global_position = data["position"]
				bg.set_multiplayer_authority(1)
				
				var owner_id = data["owner_id"]
				var player_node = get_node_or_null(str(owner_id))
				if player_node:
					bg.player_owner = player_node
					if "active_bodyguards" in player_node:
						player_node.active_bodyguards.append(bg)
						
				return bg
			"bullet":
				var bullet = bullet_scene.instantiate()
				bullet.name = str(data["name"])
				bullet.position = data["position"]
				bullet.direction = data["direction"]
				bullet.rotation = data["direction"].angle()
				if "damage" in data and "damage" in bullet:
					bullet.damage = data["damage"]
				return bullet
			"building":
				var building = building_scene.instantiate()
				building.name = str(data["name"])
				building.position = data["position"]
				if "building_type" in data and "building_type" in building:
					building.building_type = data["building_type"]
				return building
			"scrap":
				var scrap = scrap_scene.instantiate()
				scrap.name = str(data["name"])
				scrap.position = data["position"]
				return scrap
			"waaagh_idol":
				var idol = waaagh_idol_scene.instantiate()
				idol.name = str(data["name"])
				idol.position = data["position"]
				return idol
			
			"servo_skull":
				var servoskull_scene = preload("res://ServoSkull.tscn")
				var skull = servoskull_scene.instantiate()
				skull.name = str(data["name"])
				skull.global_position = data["position"]
				skull.set_multiplayer_authority(1)
				
				var owner_id = data["owner_id"]
				var player_node = get_node_or_null(str(owner_id))
				if player_node:
					skull.set_owner_player(player_node)
					if "active_servo_skulls" in player_node:
						player_node.active_servo_skulls.append(skull)
						
				return skull
 
	return null
 
# --------------------------------------------------
# RESOURCE, TECH & BUILDING MANAGEMENT
# --------------------------------------------------
 
func add_scrap(amount: int):
	scrap_amount += amount
	rpc("sync_resources", scrap_amount, requisition_amount)
 
func add_requisition(amount: int):
	requisition_amount += amount
	rpc("sync_resources", scrap_amount, requisition_amount)
 
func spend_requisition(amount: int) -> bool:
	if requisition_amount >= amount:
		requisition_amount -= amount
		rpc("sync_resources", scrap_amount, requisition_amount)
		return true
	return false
	
func unlock_tech(tech_index: int):
	match tech_index:
		0: tech_shields_unlocked = true
		1: tech_lasers_unlocked = true
		2: tech_nanobots_unlocked = true
		3: tech_magnet_unlocked = true
	rpc("sync_tech_tree", tech_shields_unlocked, tech_lasers_unlocked, tech_nanobots_unlocked, tech_magnet_unlocked)

@rpc("call_local", "reliable")
func sync_tech_tree(shields: bool, lasers: bool, nanobots: bool, magnet: bool = false):
	tech_shields_unlocked = shields
	tech_lasers_unlocked = lasers
	tech_nanobots_unlocked = nanobots
	tech_magnet_unlocked = magnet
	get_tree().call_group("buildings", "_apply_tech_stats")
	get_tree().call_group("research_ui", "refresh_tech_cards")

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_gate(building_name: String) -> void:
	if not multiplayer.is_server(): return
	var building = _find_building_by_name(building_name)
	if is_instance_valid(building) and building.has_method("try_upgrade_to_gate"):
		building.try_upgrade_to_gate()

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_turret(building_name: String) -> void:
	if not multiplayer.is_server(): return
	var building = _find_building_by_name(building_name)
	if is_instance_valid(building) and building.has_method("try_upgrade_turret"):
		building.try_upgrade_turret()

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_distributor(building_name: String) -> void:
	if not multiplayer.is_server(): return
	var building = _find_building_by_name(building_name)
	if is_instance_valid(building) and building.has_method("try_upgrade_distributor"):
		building.try_upgrade_distributor()
		
@rpc("any_peer", "call_local", "reliable")
func request_purchase_research(building_name: String, tech_index: int) -> void:
	if not multiplayer.is_server(): return
	var building = _find_building_by_name(building_name)
	if is_instance_valid(building) and int(building.get("building_type")) == 6: # Research Shrine
		if building.has_method("try_purchase_research"):
			building.try_purchase_research(tech_index)

func _find_building_by_name(b_name: String) -> Node2D:
	if has_node(b_name): return get_node(b_name) as Node2D
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.name == b_name: return b
	return null
 
@rpc("call_local", "reliable")
func sync_resources(scrap: int, requisition: int):
	scrap_amount = scrap
	requisition_amount = requisition
	if resource_label:
		resource_label.text = "⚙ SCRAP: %d      ⚡ REQUISITION: %d" % [scrap_amount, requisition_amount]
 
@rpc("call_local", "reliable")
func sync_wave_info(wave_number: int, message: String):
	current_wave = wave_number
	if wave_info_label:
		wave_info_label.text = message
 
@rpc("any_peer", "call_local", "reliable")
func request_build_structure(build_pos: Vector2, building_type: int = 0):
	if not multiplayer.is_server():
		return
		
	# Costs for: 0: Barricade, 1: Generator, 2: Turret, 3: Manufactorum, 4: Distributor, 5: Antenna, 6: Research Shrine
	var scrap_costs = [15, 25, 35, 60, 20, 0, 40]
	var req_costs   = [0,  0,  5,  25, 0,  0, 15]

	var scrap_c = scrap_costs[clamp(building_type, 0, scrap_costs.size() - 1)]
	var req_c = req_costs[clamp(building_type, 0, req_costs.size() - 1)]

	if scrap_amount >= scrap_c and requisition_amount >= req_c:
		scrap_amount -= scrap_c
		requisition_amount -= req_c
		
		rpc("sync_resources", scrap_amount, requisition_amount)
		
		building_count += 1
		var building_data = {
			"type": "building",
			"name": "Building_" + str(building_count),
			"position": build_pos,
			"building_type": building_type
		}
		
		if spawner:
			spawner.spawn(building_data)
			get_tree().call_group("buildings", "refresh_barricade_connections")
			request_navmesh_rebake()

func request_navmesh_rebake() -> void:
	update_navmesh()
 
func update_navmesh():
	if not nav_region:
		nav_region = get_node_or_null("NavigationRegion2D")
		
	if nav_region:
		nav_region.call_deferred("bake_navigation_polygon", true)
 
# --------------------------------------------------
# NETWORK SIGNALS
# --------------------------------------------------
 
func _on_peer_connected(id: int):
	if not multiplayer.is_server():
		return
	if not player_classes.has(id):
		player_classes[id] = CharacterClass.SKITARII_MARSHAL
		player_ready[id] = false
	if match_started:
		spawn_player(id)
		var current_msg = "WAVE " + str(current_wave) + "/" + str(max_waves) if is_wave_active else "PERIMETER ARMED"
		rpc_id(id, "sync_wave_info", current_wave, current_msg)
		rpc_id(id, "sync_resources", scrap_amount, requisition_amount)
		rpc_id(id, "sync_match_started")
	else:
		_broadcast_lobby_state()
 
func _on_connected_to_server():
	_set_session_text("Linked. Select a class and Ready when the cadre is set.")
	_update_ready_button()
	_sync_lobby_loadout()
 
func _on_peer_disconnected(id: int):
	player_classes.erase(id)
	player_ready.erase(id)
	active_paused_peers.erase(id) # Clean up paused peer if they quit while paused
	if multiplayer.is_server():
		var should_pause = not active_paused_peers.is_empty()
		rpc("sync_global_pause", should_pause)
		if not match_started: _broadcast_lobby_state()
	if has_node(str(id)):
		get_node(str(id)).queue_free()
