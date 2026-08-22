extends Node2D

const GameData = preload("res://GameData.gd")

const DEFAULT_PORT = 7000
const DEFAULT_IP = "127.0.0.1"

enum CharacterClass {
	ADMECH_TECHPRIEST = 0,
	SKITARII_MARSHAL = 1
}

const CLASS_DATA = {
	CharacterClass.ADMECH_TECHPRIEST: {
		"name": "Tech-Priest Enginseer",
		"faction": "Adeptus Mechanicus",
		"role": "Melee & Fortification",
		"desc": "Master of the Machine Cult. Wields the heavy Omnissian Power-Axe, secondary Plasma Caliver, and constructs defense grids."
	},
	CharacterClass.SKITARII_MARSHAL: {
		"name": "Skitarii Marshal",
		"faction": "Adeptus Mechanicus",
		"role": "Tactical Commander & Ranged",
		"desc": "Frontline cohort officer. Wields rapid Radium Carbines, shifts Doctrina Imperatives, and designates priority targets for bodyguards."
	}
}

@export var max_waves: int = 15

var player_scene = preload("res://Player.tscn")
var enemy_scene = preload("res://Enemy.tscn")
var bullet_scene = preload("res://Bullet.tscn")
var scrap_scene = preload("res://Scrap.tscn")
var building_scene = preload("res://Building.tscn")
var waaagh_idol_scene = preload("res://WaaaghIdol.tscn")

var class_preview_node: Node2D = null

var peer: ENetMultiplayerPeer = null
var enemy_count: int = 0
var bullet_count: int = 0
var building_count: int = 0

var scrap_amount: int = 40
var requisition_amount: int = 10

var base_radar_level: int = 0
var tech_waaagh_reader_unlocked: bool = false
var wave_hud_node: Control = null
var total_wave_enemies_cached: int = 0

var flanker_raid_timer: float = 30.0

var player_classes: Dictionary = {}
var player_ready: Dictionary = {}
var match_started: bool = false
var my_selected_class: CharacterClass = CharacterClass.ADMECH_TECHPRIEST
var is_ready: bool = false

const WAVE_NARRATIVE_TITLES = [
	"LOST RECON SCOUTS",
	"PROBING WARBAND RAID",
	"WAAAGH! BEACON DETECTED",
	"SQUIG FLANK INVASION",
	"FRONTLINE ORK ASSAULT",
	"AIRBORNE STORMBOY INCURSION",
	"HEAVY CHOPPA SQUADRONS",
	"ORIK NOB SIEGE BREACHERS",
	"BOMBARDMENT & STIKKBOMBS",
	"MULTI-LANCE WAAAGH! CONVERGENCE",
	"ARMORED NOB WARBAND SIEGE",
	"FOUR-FRONT FORTRESS PRESSURE",
	"DESPERATE NOOSPHERIC STAND",
	"TOTAL CITADEL BREACH",
	"THE WARBOSS - THE FINAL WAAAGH!"
]

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
var wave_squad_queue: Array[Dictionary] = []

var tech_shields_unlocked: bool = false
var tech_lasers_unlocked: bool = false
var tech_nanobots_unlocked: bool = false
var tech_magnet_unlocked: bool = false
var tech_electro_barricades_unlocked: bool = false
var tech_spikes_cover_unlocked: bool = false

var pause_menu_ui_node: Control = null
var active_paused_peers: Dictionary = {}
var settings_ui_node: Control = null
var research_ui_node: Control = null

var lobby_root_control: Control = null
var lobby_session_label: Label = null
var lobby_roster_label: Label = null
var lobby_class_desc_label: Label = null
var lobby_ip_edit: LineEdit = null
var lobby_port_edit: LineEdit = null
var lobby_ready_btn: Button = null
var lobby_host_btn: Button = null
var lobby_join_btn: Button = null
var lobby_disconnect_btn: Button = null
var lobby_start_btn: Button = null

var wave_prep_timer: float = 0.0
var is_wave_preparing: bool = false
const WAVE_PREP_DURATION: float = 8.0
const WAVE_BREAK_DURATION: float = 14.0

@onready var ui_layer: CanvasLayer = get_node_or_null("UI")
@onready var spawner: MultiplayerSpawner = get_node_or_null("MultiplayerSpawner")
@onready var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("main")
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	if spawner:
		spawner.spawn_function = _custom_spawner

	_setup_core_sub_uis()
	_build_procedural_lobby_ui()
	_show_lobby_ui()

func _process(delta: float) -> void:
	if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
		if is_wave_preparing:
			wave_prep_timer -= delta
			if wave_prep_timer <= 0.0:
				is_wave_preparing = false
				_begin_wave_spawning()
			_broadcast_wave_hud()

		if is_wave_active:
			flanker_raid_timer -= delta
			if flanker_raid_timer <= 0.0:
				flanker_raid_timer = randf_range(28.0, 42.0)
				_spawn_flanker_raid()

func _build_procedural_lobby_ui():
	if not ui_layer: return

	lobby_root_control = Control.new()
	lobby_root_control.name = "LobbyUI"
	lobby_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_root_control.theme = AdmechTheme.make()
	ui_layer.add_child(lobby_root_control)

	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.04, 0.06, 0.92)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	lobby_root_control.add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_root_control.add_child(center)

	var main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(880, 520)
	center.add_child(main_panel)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	main_panel.add_child(root_vbox)

	var title = Label.new()
	title.text = "◆ OMNISSIAN VOX-LINK CONGREGATION CHAMBER ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	root_vbox.add_child(title)

	lobby_session_label = Label.new()
	lobby_session_label.text = "Standing by. Host a sanctum forge or link via Vox IP."
	lobby_session_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_session_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.20))
	lobby_session_label.add_theme_font_size_override("font_size", 11)
	root_vbox.add_child(lobby_session_label)

	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.25, 0.28, 0.35, 0.6)
	root_vbox.add_child(sep)

	var body_hbox = HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 14)
	root_vbox.add_child(body_hbox)

	var col1 = _create_lobby_sub_card("1. VOX-LINK PROTOCOLS", body_hbox)
	
	var ip_lbl = Label.new()
	ip_lbl.text = "Target Sanctum IP:"
	ip_lbl.add_theme_font_size_override("font_size", 10)
	col1.add_child(ip_lbl)

	lobby_ip_edit = LineEdit.new()
	lobby_ip_edit.text = DEFAULT_IP
	lobby_ip_edit.placeholder_text = "e.g. 127.0.0.1"
	col1.add_child(lobby_ip_edit)

	var port_lbl = Label.new()
	port_lbl.text = "Vox Port:"
	port_lbl.add_theme_font_size_override("font_size", 10)
	col1.add_child(port_lbl)

	lobby_port_edit = LineEdit.new()
	lobby_port_edit.text = str(DEFAULT_PORT)
	col1.add_child(lobby_port_edit)

	lobby_host_btn = Button.new()
	lobby_host_btn.text = "ACTIVATE SANCTUM (Host)"
	lobby_host_btn.pressed.connect(_on_host_pressed)
	col1.add_child(lobby_host_btn)

	lobby_join_btn = Button.new()
	lobby_join_btn.text = "ESTABLISH LINK (Join)"
	lobby_join_btn.pressed.connect(_on_join_pressed)
	col1.add_child(lobby_join_btn)

	lobby_disconnect_btn = Button.new()
	lobby_disconnect_btn.text = "DISENGAGE LINK"
	lobby_disconnect_btn.disabled = true
	lobby_disconnect_btn.pressed.connect(_on_disconnect_pressed)
	col1.add_child(lobby_disconnect_btn)

	var col2 = _create_lobby_sub_card("2. CADRE DESIGNATION", body_hbox)

	var class_btn_hbox = HBoxContainer.new()
	class_btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	class_btn_hbox.add_theme_constant_override("separation", 6)
	col2.add_child(class_btn_hbox)

	var tp_btn = Button.new()
	tp_btn.text = "TECH-PRIEST"
	tp_btn.pressed.connect(func(): _select_class_local(CharacterClass.ADMECH_TECHPRIEST))
	class_btn_hbox.add_child(tp_btn)

	var sk_btn = Button.new()
	sk_btn.text = "MARSHAL"
	sk_btn.pressed.connect(func(): _select_class_local(CharacterClass.SKITARII_MARSHAL))
	class_btn_hbox.add_child(sk_btn)

	lobby_class_desc_label = Label.new()
	lobby_class_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_class_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_class_desc_label.add_theme_font_size_override("font_size", 10)
	lobby_class_desc_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
	col2.add_child(lobby_class_desc_label)

	lobby_ready_btn = Button.new()
	lobby_ready_btn.text = "READY UP"
	lobby_ready_btn.disabled = true
	lobby_ready_btn.pressed.connect(_on_ready_pressed)
	col2.add_child(lobby_ready_btn)

	var col3 = _create_lobby_sub_card("3. CADRE MANIFEST", body_hbox)

	lobby_roster_label = Label.new()
	lobby_roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_roster_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_roster_label.add_theme_font_size_override("font_size", 11)
	col3.add_child(lobby_roster_label)

	lobby_start_btn = Button.new()
	lobby_start_btn.text = "INITIATE CRUSADE (Host)"
	lobby_start_btn.disabled = true
	lobby_start_btn.pressed.connect(_begin_match)
	col3.add_child(lobby_start_btn)

	_update_class_ui()
	_refresh_lobby_roster()

func _create_lobby_sub_card(card_title: String, parent_hbox: Container) -> VBoxContainer:
	var pc = PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.90)
	sb.border_color = Color(0.24, 0.28, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	parent_hbox.add_child(pc)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	pc.add_child(vbox)

	var t_lbl = Label.new()
	t_lbl.text = card_title
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_lbl.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
	t_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(t_lbl)

	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.25, 0.28, 0.35, 0.4)
	vbox.add_child(sep)

	return vbox

func _setup_core_sub_uis():
	if not has_node("UI/WaveHUD"):
		var w_hud = load("res://WaveHUD.gd").new()
		w_hud.name = "WaveHUD"
		$UI.add_child(w_hud)
		wave_hud_node = w_hud

	if not has_node("UI/AbilityHUD"):
		var a_hud = load("res://AbilityHUD.gd").new()
		a_hud.name = "AbilityHUD"
		$UI.add_child(a_hud)

	if not has_node("UI/CyberneticaUI"):
		var c_ui = load("res://CyberneticaUI.gd").new()
		c_ui.name = "CyberneticaUI"
		$UI.add_child(c_ui)
		
	if not has_node("UI/MinimapUI"):
		var m_ui = load("res://MinimapUI.gd").new()
		m_ui.name = "MinimapUI"
		$UI.add_child(m_ui)

	if not has_node("UI/BaseUpgradeUI"):
		var b_ui = load("res://BaseUpgradeUI.gd").new()
		b_ui.name = "BaseUpgradeUI"
		$UI.add_child(b_ui)

	if not has_node("UI/TurretUpgradeUI"):
		var t_ui = load("res://TurretUpgradeUI.gd").new()
		t_ui.name = "TurretUpgradeUI"
		$UI.add_child(t_ui)

	if not has_node("UI/SettingsUI"):
		var s_ui = load("res://SettingsUI.gd").new()
		s_ui.name = "SettingsUI"
		$UI.add_child(s_ui)
		settings_ui_node = s_ui

	if not has_node("UI/PauseMenuUI"):
		var p_ui = load("res://PauseMenuUI.gd").new()
		p_ui.name = "PauseMenuUI"
		$UI.add_child(p_ui)
		pause_menu_ui_node = p_ui

	if not has_node("UI/ResearchUI"):
		var r_ui = load("res://ResearchUI.gd").new()
		r_ui.name = "ResearchUI"
		$UI.add_child(r_ui)
		research_ui_node = r_ui

func _safe_cleanup_peer():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	peer = null

func _on_host_pressed():
	_safe_cleanup_peer()
	
	var port = int(lobby_port_edit.text) if (lobby_port_edit and lobby_port_edit.text != "") else DEFAULT_PORT
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port)
	if error != OK:
		_set_session_text("Failed to host on Port %d. Error code: %d" % [port, error])
		_safe_cleanup_peer()
		return

	multiplayer.multiplayer_peer = peer
	match_started = false
	is_ready = false
	player_classes.clear()
	player_ready.clear()
	
	player_classes[1] = my_selected_class
	player_ready[1] = false

	_set_session_text("◆ SANCTUM ACTIVATED ◆ Hosting on Port %d." % port)
	_update_connection_buttons(true)
	_refresh_lobby_roster()
	_broadcast_lobby_state()

func _on_join_pressed():
	_safe_cleanup_peer()

	var ip = lobby_ip_edit.text.strip_edges() if (lobby_ip_edit and lobby_ip_edit.text != "") else DEFAULT_IP
	var port = int(lobby_port_edit.text) if (lobby_port_edit and lobby_port_edit.text != "") else DEFAULT_PORT

	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		_set_session_text("Transmitting Vox-Link to %s:%d..." % [ip, port])
		_update_connection_buttons(true)
	else:
		_set_session_text("Failed to initiate connection to %s:%d" % [ip, port])
		_safe_cleanup_peer()

func _on_disconnect_pressed():
	_safe_cleanup_peer()
	player_classes.clear()
	player_ready.clear()
	is_ready = false
	_set_session_text("Vox-Link disengaged. Standing by.")
	_update_connection_buttons(false)
	_refresh_lobby_roster()

func _on_connected_to_server():
	_set_session_text("◆ VOX-LINK SYNCHRONIZED ◆ Select class & Ready Up.")
	_sync_lobby_loadout()

func _on_connection_failed():
	_set_session_text("⚠️ CONNECTION FAILED: Target Sanctum unreachable.")
	_on_disconnect_pressed()

func _on_server_disconnected():
	_set_session_text("⚠️ CARRIER LOST: Sanctum Host disconnected.")
	_on_disconnect_pressed()
	if match_started:
		execute_rematch()

func _on_peer_connected(id: int):
	if not multiplayer.is_server(): return
	
	if not player_classes.has(id):
		player_classes[id] = CharacterClass.SKITARII_MARSHAL
		player_ready[id] = false
		
	if match_started:
		spawn_player(id)
		rpc_id(id, "sync_match_started")
		rpc_id(id, "sync_resources", scrap_amount, requisition_amount)
	else:
		_broadcast_lobby_state()

func _on_peer_disconnected(id: int):
	player_classes.erase(id)
	player_ready.erase(id)
	active_paused_peers.erase(id)
	
	if multiplayer.is_server():
		var should_pause = not active_paused_peers.is_empty()
		rpc("sync_global_pause", should_pause)
		if not match_started:
			_broadcast_lobby_state()
			
	var p_node = get_node_or_null(str(id))
	if p_node: p_node.queue_free()
	_refresh_lobby_roster()

func _select_class_local(chosen_class: CharacterClass):
	my_selected_class = chosen_class
	_update_class_ui()
	_sync_lobby_loadout()

func _on_ready_pressed():
	if not _is_in_session(): return
	is_ready = not is_ready
	if lobby_ready_btn:
		lobby_ready_btn.text = "UNREADY" if is_ready else "READY UP"
		lobby_ready_btn.modulate = Color(0.4, 0.95, 0.5) if is_ready else Color.WHITE
	_sync_lobby_loadout()

func _sync_lobby_loadout():
	if not _is_in_session() or match_started:
		_refresh_lobby_roster()
		return

	if multiplayer.is_server():
		player_classes[1] = my_selected_class
		player_ready[1] = is_ready
		_broadcast_lobby_state()
	else:
		rpc_id(1, "report_lobby_loadout", int(my_selected_class), is_ready)

@rpc("any_peer", "reliable")
func report_lobby_loadout(chosen_class: int, ready: bool) -> void:
	if not multiplayer.is_server() or match_started: return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	
	player_classes[sender_id] = chosen_class
	player_ready[sender_id] = ready
	_broadcast_lobby_state()

func _broadcast_lobby_state() -> void:
	if not multiplayer.is_server(): return
	var payload: Array = []
	for id in player_classes.keys():
		payload.append([int(id), int(player_classes[id]), player_ready.get(id, false)])
	rpc("sync_lobby_state", payload, match_started)
	_refresh_lobby_roster()

@rpc("authority", "call_local", "reliable")
func sync_lobby_state(payload: Array, started: bool) -> void:
	player_classes.clear()
	player_ready.clear()
	for entry in payload:
		if typeof(entry) == TYPE_ARRAY and entry.size() >= 3:
			var id = int(entry[0])
			player_classes[id] = int(entry[1])
			player_ready[id] = bool(entry[2])
			
	_refresh_lobby_roster()
	if started and not match_started:
		_begin_match_local()

func _begin_match() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	if match_started: return
	
	match_started = true
	if multiplayer.has_multiplayer_peer():
		_broadcast_lobby_state()
		rpc("sync_match_started")
	
	for id in _session_peer_ids():
		spawn_player(id)
		
	_spawn_map_scrap_deposits()
	_spawn_ork_mega_camp()
	start_next_wave()

@rpc("authority", "call_local", "reliable")
func sync_match_started() -> void:
	_begin_match_local()

func _begin_match_local() -> void:
	match_started = true
	_hide_lobby_ui()
	var hud = get_tree().get_first_node_in_group("ability_hud")
	if hud and hud.has_method("show"): hud.show()

func _is_in_session() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

func _session_peer_ids() -> Array[int]:
	var ids: Array[int] = [1]
	if multiplayer.has_multiplayer_peer():
		for p in multiplayer.get_peers():
			ids.append(int(p))
	return ids

func _set_session_text(msg: String):
	if lobby_session_label: lobby_session_label.text = msg

func _update_connection_buttons(connected: bool):
	if lobby_host_btn: lobby_host_btn.disabled = connected
	if lobby_join_btn: lobby_join_btn.disabled = connected
	if lobby_disconnect_btn: lobby_disconnect_btn.disabled = not connected
	if lobby_ready_btn: lobby_ready_btn.disabled = not connected

func _update_class_ui():
	if CLASS_DATA.has(my_selected_class) and lobby_class_desc_label:
		var info = CLASS_DATA[my_selected_class]
		lobby_class_desc_label.text = "◆ %s ◆\n%s\n\n%s" % [info.name.to_upper(), info.role, info.desc]

func _refresh_lobby_roster():
	if not lobby_roster_label: return

	if not _is_in_session():
		lobby_roster_label.text = "No Vox-Link. Host or Join to assemble cadre."
		if lobby_start_btn: lobby_start_btn.disabled = true
		return

	var lines: PackedStringArray = []
	var ids: Array = player_classes.keys()
	ids.sort()
	var all_ready = true

	for id in ids:
		var c_id: int = int(player_classes[id])
		var info = CLASS_DATA.get(c_id, {"name": "Acolyte"})
		var rdy = player_ready.get(id, false)
		if not rdy: all_ready = false
		
		var tag = " (You)" if (id == multiplayer.get_unique_id() or (id == 1 and not multiplayer.has_multiplayer_peer())) else ""
		var status_str = "[READY]" if rdy else "[STANDBY]"
		lines.append("%s %s %s%s" % [status_str, info.name, ("#%d" % id), tag])

	lobby_roster_label.text = "\n".join(lines)
	
	if lobby_start_btn and multiplayer.is_server():
		lobby_start_btn.disabled = not all_ready
		lobby_start_btn.text = "INITIATE CRUSADE" if all_ready else "WAITING ON CADRE..."

func _show_lobby_ui():
	match_started = false
	if lobby_root_control: lobby_root_control.show()

func _hide_lobby_ui():
	if lobby_root_control: lobby_root_control.hide()

func spawn_player(peer_id: int):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	for p in get_tree().get_nodes_in_group("players"):
		if p.name == str(peer_id): return

	var chosen_class = player_classes.get(peer_id, CharacterClass.SKITARII_MARSHAL)
	var spawn_data = {
		"type": "player",
		"peer_id": peer_id,
		"class": chosen_class
	}
	if spawner:
		spawner.spawn(spawn_data)
	else:
		var p_node = _custom_spawner(spawn_data)
		if is_instance_valid(p_node):
			add_child(p_node)

func _custom_spawner(data) -> Node:
	if typeof(data) == TYPE_ARRAY and data.size() > 0: data = data[0]
	if typeof(data) != TYPE_DICTIONARY: return null

	var obj_type = data.get("type", "")
	match obj_type:
		"player":
			var player = player_scene.instantiate()
			var peer_id = data["peer_id"]
			player.name = str(peer_id)
			var chosen_class = data.get("class", CharacterClass.ADMECH_TECHPRIEST)
			if player.has_method("set_player_class"):
				player.set_player_class(player.PlayerClass.MELEE if chosen_class == CharacterClass.ADMECH_TECHPRIEST else player.PlayerClass.RANGED)
			
			var base_node = get_tree().get_first_node_in_group("base")
			var base_pos = base_node.global_position if base_node else Vector2(500, 500)
			var offset_x = -30.0 if peer_id == 1 else 30.0
			player.position = base_pos + Vector2(offset_x, 80.0)
			return player

		"kastelan_robot":
			var robot_script = load("res://KastelanRobot.gd")
			var robot = CharacterBody2D.new()
			robot.set_script(robot_script)
			robot.name = str(data["name"])
			robot.position = data["position"]
			robot.set_multiplayer_authority(1)
			var owner_id = data.get("owner_id", 1)
			var p_node = get_node_or_null(str(owner_id))
			if p_node:
				robot.player_owner = p_node
				if "active_kastelan_robot" in p_node:
					p_node.active_kastelan_robot = robot
			return robot

		"cohort_infantry":
			var inf_script = load("res://SkitariiInfantry.gd")
			var inf = CharacterBody2D.new()
			inf.set_script(inf_script)
			inf.name = str(data["name"])
			inf.position = data["position"] # Fixed: uses position, not global_position
			inf.unit_type = data.get("unit_type", GameData.CohortUnitType.VANGUARD)
			inf.set_multiplayer_authority(1)
			return inf

		"kataphron_unit":
			var kata_script = load("res://KataphronUnit.gd")
			var kata = CharacterBody2D.new()
			kata.set_script(kata_script)
			kata.name = str(data["name"])
			kata.position = data["position"] # Fixed: uses position, not global_position
			kata.set_multiplayer_authority(1)
			return kata

		"building":
			var building = building_scene.instantiate()
			building.name = str(data["name"])
			building.position = data["position"]
			if "building_type" in data:
				building.building_type = data["building_type"]
			return building

		"enemy":
			var enemy = enemy_scene.instantiate()
			enemy.name = str(data["name"])
			enemy.position = data["position"]
			if "enemy_type" in data: enemy.type = int(data["enemy_type"])
			if "is_objective_guard" in data: enemy.is_objective_guard = data["is_objective_guard"]
			if "guard_anchor" in data: enemy.guard_anchor = data["guard_anchor"]
			if "counts_toward_wave" in data: enemy.counts_toward_wave = data["counts_toward_wave"]
			return enemy

		"bullet":
			var bullet = bullet_scene.instantiate()
			bullet.name = str(data["name"])
			bullet.position = data["position"]
			bullet.direction = data["direction"]
			bullet.rotation = data["direction"].angle()
			if "damage" in data: bullet.damage = data["damage"]
			if "is_enemy_bullet" in data: bullet.is_enemy_bullet = data["is_enemy_bullet"]
			if "is_plasma_caliver" in data: bullet.is_plasma_caliver = data["is_plasma_caliver"]
			return bullet

		"kastelan_robot":
			var robot_script = load("res://KastelanRobot.gd")
			var robot = CharacterBody2D.new()
			robot.set_script(robot_script)
			robot.name = str(data["name"])
			robot.position = data["position"] # Fixed: uses position
			robot.set_multiplayer_authority(1)
			var owner_id = data["owner_id"]
			var p_node = get_node_or_null(str(owner_id))
			if p_node:
				robot.player_owner = p_node
				p_node.active_kastelan_robot = robot
			return robot

		"scrap":
			var scrap = scrap_scene.instantiate()
			scrap.name = str(data["name"])
			scrap.position = data["position"]
			return scrap

		"scrap_deposit":
			var dep = StaticBody2D.new()
			dep.set_script(load("res://ScrapDeposit.gd"))
			dep.name = str(data["name"])
			dep.position = data["position"]
			return dep

		"ork_citadel":
			var cit = StaticBody2D.new()
			cit.set_script(load("res://OrkCitadel.gd"))
			cit.name = str(data["name"])
			cit.position = data["position"]
			return cit

		"ork_scrap_heap":
			var heap = StaticBody2D.new()
			heap.set_script(load("res://OrkScrapHeap.gd"))
			heap.name = str(data["name"])
			heap.position = data["position"]
			return heap

		"waaagh_idol":
			var idol = waaagh_idol_scene.instantiate()
			idol.name = str(data["name"])
			idol.position = data["position"]
			return idol

		"bodyguard":
			var bodyguard_scene = preload("res://SkitariiBodyguard.tscn")
			var bg = bodyguard_scene.instantiate()
			bg.name = str(data["name"])
			bg.position = data["position"]
			bg.set_multiplayer_authority(1)
			var owner_id = data["owner_id"]
			var p_node = get_node_or_null(str(owner_id))
			if p_node:
				bg.player_owner = p_node
				if "active_bodyguards" in p_node: p_node.active_bodyguards.append(bg)
			return bg

		"servo_skull":
			var servoskull_scene = preload("res://ServoSkull.tscn")
			var skull = servoskull_scene.instantiate()
			skull.name = str(data["name"])
			skull.position = data["position"]
			skull.set_multiplayer_authority(1)
			var owner_id = data["owner_id"]
			var p_node = get_node_or_null(str(owner_id))
			if p_node:
				skull.set_owner_player(p_node)
				if "active_servo_skulls" in p_node: p_node.active_servo_skulls.append(skull)
			return skull

	return null

func get_cohort_population() -> int:
	var total = 0
	for u in get_tree().get_nodes_in_group("controllable_units"):
		if is_instance_valid(u) and not u.is_in_group("players"):
			total += 1
	return total

func notify_cohort_unit_lost():
	var hud = get_tree().get_first_node_in_group("ability_hud")
	if hud and hud.has_method("refresh_hud_display"):
		hud.refresh_hud_display()

@rpc("any_peer", "call_local", "reliable")
func request_queue_cohort_unit(building_name: String, unit_type_id: int):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var target_building = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.name == building_name:
			target_building = b
			break
	if not target_building:
		target_building = get_node_or_null(building_name)

	if is_instance_valid(target_building) and target_building.has_method("try_queue_unit"):
		target_building.try_queue_unit(unit_type_id)

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_gate(building_name: String):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var b = _find_building_by_name(building_name)
	if is_instance_valid(b) and b.has_method("try_upgrade_to_gate"):
		b.try_upgrade_to_gate()

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_turret(building_name: String):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var b = _find_building_by_name(building_name)
	if is_instance_valid(b) and b.has_method("try_upgrade_turret"):
		b.try_upgrade_turret()

@rpc("any_peer", "call_local", "reliable")
func request_upgrade_distributor(building_name: String):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var b = _find_building_by_name(building_name)
	if is_instance_valid(b) and b.has_method("try_upgrade_distributor"):
		b.try_upgrade_distributor()

func _find_building_by_name(b_name: String) -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.name == b_name:
			return b
	return get_node_or_null(b_name)

@rpc("any_peer", "call_local", "reliable")
func request_set_rally_point(building_name: String, rally_pos: Vector2):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var target_building = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.name == building_name:
			target_building = b
			break
	if not target_building:
		target_building = get_node_or_null(building_name)

	if is_instance_valid(target_building) and target_building.has_method("set_rally_point"):
		target_building.set_rally_point(rally_pos)
		if multiplayer.has_multiplayer_peer():
			target_building.rpc("set_rally_point", rally_pos)

func _spawn_map_scrap_deposits():
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2(500, 500)

	for i in range(2):
		var angle = (PI * 0.75) if i == 0 else (-PI * 0.25)
		var dep_data = {
			"type": "scrap_deposit",
			"name": "ScrapDeposit_Start_" + str(i + 1),
			"position": (base_pos + Vector2.RIGHT.rotated(angle) * 240.0).snapped(Vector2(32, 32))
		}
		if spawner: spawner.spawn(dep_data)
		else: add_child(_custom_spawner(dep_data))

	for i in range(5):
		var angle = (float(i) * TAU / 5.0) + randf_range(-0.3, 0.3)
		var dep_data = {
			"type": "scrap_deposit",
			"name": "ScrapDeposit_Wild_" + str(i + 1),
			"position": (base_pos + Vector2.RIGHT.rotated(angle) * randf_range(650.0, 1050.0)).snapped(Vector2(32, 32))
		}
		if spawner: spawner.spawn(dep_data)
		else: add_child(_custom_spawner(dep_data))

func _spawn_ork_mega_camp():
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2(500, 500)

	var camp_pos = (base_pos + Vector2.RIGHT.rotated(randf_range(-PI, PI)) * 1450.0).snapped(Vector2(32, 32))
	var citadel_data = {
		"type": "ork_citadel",
		"name": "OrkCitadel_Core",
		"position": camp_pos
	}
	if spawner: spawner.spawn(citadel_data)
	else: add_child(_custom_spawner(citadel_data))

	var dir_to_base = (base_pos - camp_pos).normalized()
	var heap_positions = [
		camp_pos + dir_to_base.rotated(2.2) * 110.0,
		camp_pos + dir_to_base.rotated(-2.2) * 110.0,
		camp_pos - (dir_to_base * 110.0)
	]

	for i in range(heap_positions.size()):
		var heap_data = {
			"type": "ork_scrap_heap",
			"name": "OrkScrapHeap_" + str(i + 1),
			"position": heap_positions[i].snapped(Vector2(32, 32))
		}
		if spawner: spawner.spawn(heap_data)
		else: add_child(_custom_spawner(heap_data))

func start_next_wave():
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	current_wave += 1
	if current_wave > max_waves:
		game_over(true)
		return

	if current_wave in [2, 4, 6, 8, 10, 12, 14]:
		spawn_waaagh_idol()
		
	wave_player_count = max(1, get_tree().get_nodes_in_group("players").size())
	spawn_lane_angles = _build_spawn_lanes(current_wave, wave_player_count)
	wave_squad_queue = _build_wave_squads(current_wave, wave_player_count)
	
	enemies_left_to_spawn = 0
	for squad in wave_squad_queue:
		enemies_left_to_spawn += squad["units"].size()
	total_wave_enemies_cached = enemies_left_to_spawn

	is_wave_preparing = true
	wave_prep_timer = WAVE_PREP_DURATION
	_broadcast_wave_hud()
	
	if base_radar_level >= 2:
		if multiplayer.has_multiplayer_peer():
			rpc("sync_incoming_threat_lanes", spawn_lane_angles)
			rpc("trigger_wave_alert_sfx")
		else:
			sync_incoming_threat_lanes(spawn_lane_angles)
			trigger_wave_alert_sfx()
	else:
		if multiplayer.has_multiplayer_peer():
			rpc("sync_incoming_threat_lanes", [])
		else:
			sync_incoming_threat_lanes([])

func _spawn_flanker_raid():
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2.ZERO
	var edge_pos = base_pos + Vector2.RIGHT.rotated(randf() * TAU) * 1500.0
	
	for t in [1, 1, 3]:
		enemy_count += 1
		var enemy_data = {
			"type": "enemy",
			"name": "Flanker_" + str(enemy_count),
			"enemy_type": t,
			"position": edge_pos + Vector2.RIGHT.rotated(randf() * TAU) * 35.0,
			"is_objective_guard": false,
			"counts_toward_wave": false
		}
		if spawner: spawner.spawn(enemy_data)
		else: add_child(_custom_spawner(enemy_data))

func _spawn_tactical_squad(squad: Dictionary):
	var units: Array = squad["units"]
	var citadel = get_tree().get_first_node_in_group("ork_citadel")
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2.ZERO
	
	var spawn_origin = citadel.global_position if is_instance_valid(citadel) else (base_pos + Vector2(1200, 0))
	var dir_to_base = (base_pos - spawn_origin).normalized()
	var squad_center = spawn_origin + Vector2.RIGHT.rotated(dir_to_base.angle() + randf_range(-0.4, 0.4)) * 180.0

	for unit_type in units:
		enemy_count += 1
		var spawn_pos = squad_center + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(15.0, 50.0)
		var enemy_data = {
			"type": "enemy",
			"name": "Enemy_" + str(enemy_count),
			"enemy_type": unit_type,
			"position": spawn_pos,
			"is_objective_guard": false,
			"counts_toward_wave": true
		}
		if spawner: spawner.spawn(enemy_data)
		else: add_child(_custom_spawner(enemy_data))

		active_enemies += 1
		enemies_left_to_spawn = max(0, enemies_left_to_spawn - 1)
			
	_broadcast_wave_hud()

func _begin_wave_spawning():
	is_wave_active = true
	_broadcast_wave_hud()
	if wave_timer == null:
		wave_timer = Timer.new()
		wave_timer.timeout.connect(_spawn_squad_tick)
		add_child(wave_timer)
		
	wave_timer.wait_time = 1.5
	wave_timer.start()

func _spawn_squad_tick():
	if not wave_squad_queue.is_empty():
		var squad = wave_squad_queue.pop_front()
		_spawn_tactical_squad(squad)
		if not wave_squad_queue.is_empty():
			wave_timer.wait_time = wave_squad_queue.front()["delay"]
			wave_timer.start()
		else:
			wave_timer.stop()
	else:
		wave_timer.stop()

func notify_enemy_defeated():
	if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
		active_enemies = max(0, active_enemies - 1)
		if enemies_left_to_spawn <= 0 and active_enemies == 0 and is_wave_active:
			is_wave_active = false
			if multiplayer.has_multiplayer_peer():
				rpc("sync_incoming_threat_lanes", [])
			else:
				sync_incoming_threat_lanes([])
			var break_tween = create_tween()
			break_tween.tween_interval(WAVE_BREAK_DURATION)
			break_tween.tween_callback(start_next_wave)

func _build_spawn_lanes(wave: int, player_count: int) -> Array[float]:
	var lanes: Array[float] = [randf() * TAU]
	if wave >= 4: lanes.append(lanes[0] + randf_range(1.2, 2.0))
	if wave >= 8: lanes.append(lanes[0] + PI + randf_range(-0.4, 0.4))
	return lanes

func _build_wave_squads(wave: int, player_count: int) -> Array[Dictionary]:
	var threat_budget = int(round((14.0 + pow(wave, 1.36) * 6.2) * (1.0 + 0.65 * (player_count - 1))))
	var squads: Array[Dictionary] = []
	while threat_budget > 0:
		var templates = _get_available_squad_templates(wave)
		var affordable: Array[Dictionary] = []
		for t in templates:
			if t["cost"] <= threat_budget: affordable.append(t)
		if affordable.is_empty(): break
		var chosen = affordable.pick_random()
		squads.append({"units": chosen["units"].duplicate(), "delay": chosen["delay"]})
		threat_budget -= chosen["cost"]
	return squads

func _get_available_squad_templates(wave: int) -> Array[Dictionary]:
	var t: Array[Dictionary] = [{"cost": 6, "units": [0, 0, 0, 0, 0], "delay": 3.5}]
	if wave >= 2: t.append({"cost": 8, "units": [1, 1, 1, 1], "delay": 4.0})
	if wave >= 3: t.append({"cost": 12, "units": [2, 2, 0, 0], "delay": 4.5})
	if wave >= 6: t.append({"cost": 14, "units": [3, 3, 3, 1], "delay": 5.0})
	if wave >= 8: t.append({"cost": 20, "units": [4, 2, 2, 0], "delay": 6.0})
	return t

func spawn_waaagh_idol():
	objective_count += 1
	var base_node = get_tree().get_first_node_in_group("base")
	var center = base_node.global_position if base_node else Vector2(500, 500)
	var camp_pos = center + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(720.0, 1020.0)

	var idol_data = {"type": "waaagh_idol", "name": "WaaaghIdol_" + str(objective_count), "position": camp_pos}
	if spawner: spawner.spawn(idol_data)
	else: add_child(_custom_spawner(idol_data))

	for i in range(6):
		var guard_data = {
			"type": "enemy", "name": "IdolGuard_" + str(randi()), "enemy_type": 0 if i % 2 == 0 else 1,
			"position": camp_pos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 100.0),
			"is_objective_guard": true, "guard_anchor": camp_pos, "counts_toward_wave": false
		}
		if spawner: spawner.spawn(guard_data)
		else: add_child(_custom_spawner(guard_data))

func notify_totem_destroyed():
	_broadcast_wave_hud()

func get_active_totem_count() -> int:
	return get_tree().get_nodes_in_group("waaagh_totems").size()

func _broadcast_wave_hud():
	var title = WAVE_NARRATIVE_TITLES[clampi(current_wave - 1, 0, WAVE_NARRATIVE_TITLES.size() - 1)]
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc("sync_wave_telemetry",
			current_wave, max_waves, title, is_wave_preparing, wave_prep_timer,
			(not is_wave_active and not is_wave_preparing), 0.0,
			active_enemies + enemies_left_to_spawn, total_wave_enemies_cached
		)
	else:
		sync_wave_telemetry(
			current_wave, max_waves, title, is_wave_preparing, wave_prep_timer,
			(not is_wave_active and not is_wave_preparing), 0.0,
			active_enemies + enemies_left_to_spawn, total_wave_enemies_cached
		)

@rpc("any_peer", "call_local", "reliable")
func request_specialize_turret(building_name: String, spec_id: int):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var b = _find_building_by_name(building_name)
	if is_instance_valid(b) and b.has_method("try_specialize_turret"):
		b.try_specialize_turret(spec_id)

@rpc("call_local", "reliable")
func sync_wave_telemetry(wave: int, max_w: int, title_txt: String, preparing: bool, prep_left: float, on_break: bool, break_left: float, contacts_active: int, contacts_total: int):
	current_wave = wave
	if not is_instance_valid(wave_hud_node):
		wave_hud_node = get_tree().get_first_node_in_group("wave_hud")
	if wave_hud_node and wave_hud_node.has_method("update_telemetry"):
		wave_hud_node.update_telemetry(wave, max_w, title_txt, preparing, prep_left, on_break, break_left, contacts_active, contacts_total)

func add_scrap(amount: int):
	scrap_amount += amount
	if multiplayer.has_multiplayer_peer():
		rpc("sync_resources", scrap_amount, requisition_amount)

func add_requisition(amount: int):
	requisition_amount += amount
	if multiplayer.has_multiplayer_peer():
		rpc("sync_resources", scrap_amount, requisition_amount)

func spend_requisition(amount: int) -> bool:
	if requisition_amount >= amount:
		requisition_amount -= amount
		if multiplayer.has_multiplayer_peer():
			rpc("sync_resources", scrap_amount, requisition_amount)
		return true
	return false

@rpc("call_local", "reliable")
func sync_resources(scrap: int, requisition: int):
	scrap_amount = scrap
	requisition_amount = requisition

@rpc("any_peer", "call_local", "reliable")
func request_purchase_research(building_name: String, tech_id: int):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var b = _find_building_by_name(building_name)
	if is_instance_valid(b) and b.has_method("try_purchase_research"):
		b.try_purchase_research(tech_id)

@rpc("any_peer", "call_local", "reliable")
func request_sanctum_research(tech_id: int):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	if tech_id < 0 or tech_id >= GameData.SANCTUM_TECH.size(): return
	
	var info = GameData.SANCTUM_TECH[tech_id]
	if scrap_amount >= info.scrap and requisition_amount >= info.req:
		scrap_amount -= info.scrap
		requisition_amount -= info.req
		
		match tech_id:
			0: base_radar_level = 1
			1: tech_waaagh_reader_unlocked = true
			2: base_radar_level = 2
			3: base_radar_level = 3
			
		if multiplayer.has_multiplayer_peer():
			rpc("sync_resources", scrap_amount, requisition_amount)
			rpc("sync_sanctum_tech", base_radar_level, tech_waaagh_reader_unlocked)
		else:
			sync_sanctum_tech(base_radar_level, tech_waaagh_reader_unlocked)
		AudioManager.play_sfx("building_place", Vector2.ZERO, 3.0, 1.4)

@rpc("call_local", "reliable")
func sync_sanctum_tech(radar_lvl: int, waaagh_reader: bool):
	base_radar_level = radar_lvl
	tech_waaagh_reader_unlocked = waaagh_reader
	get_tree().call_group("base_upgrade_ui", "_refresh_cards")

func unlock_tech(tech_index: int):
	match tech_index:
		0: tech_shields_unlocked = true
		1: tech_lasers_unlocked = true
		2: tech_nanobots_unlocked = true
		3: tech_magnet_unlocked = true
		4: tech_electro_barricades_unlocked = true
		5: tech_spikes_cover_unlocked = true
	if multiplayer.has_multiplayer_peer():
		rpc("sync_tech_tree", tech_shields_unlocked, tech_lasers_unlocked, tech_nanobots_unlocked, tech_magnet_unlocked, tech_electro_barricades_unlocked, tech_spikes_cover_unlocked)
	else:
		sync_tech_tree(tech_shields_unlocked, tech_lasers_unlocked, tech_nanobots_unlocked, tech_magnet_unlocked, tech_electro_barricades_unlocked, tech_spikes_cover_unlocked)

@rpc("call_local", "reliable")
func sync_tech_tree(shields: bool, lasers: bool, nanobots: bool, magnet: bool, electro_walls: bool, spikes_cover: bool):
	tech_shields_unlocked = shields
	tech_lasers_unlocked = lasers
	tech_nanobots_unlocked = nanobots
	tech_magnet_unlocked = magnet
	tech_electro_barricades_unlocked = electro_walls
	tech_spikes_cover_unlocked = spikes_cover
	get_tree().call_group("buildings", "_apply_tech_stats")
	get_tree().call_group("research_ui", "refresh_tech_cards")

@rpc("any_peer", "call_local", "reliable")
func request_build_structure(build_pos: Vector2, building_type: int = 0):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var info = GameData.STRUCTURE_INFO.get(building_type, null)
	if not info: return

	var scrap_c = info["scrap"]
	var req_c = info["req"]

	if scrap_amount >= scrap_c and requisition_amount >= req_c:
		scrap_amount -= scrap_c
		requisition_amount -= req_c
		if multiplayer.has_multiplayer_peer():
			rpc("sync_resources", scrap_amount, requisition_amount)
		
		building_count += 1
		var b_data = {
			"type": "building",
			"name": "Building_" + str(building_count),
			"position": build_pos,
			"building_type": building_type
		}
		if spawner: spawner.spawn(b_data)
		else: add_child(_custom_spawner(b_data))
		
		if building_type == 0:
			Building.rebuild_all_barricade_connections(get_tree())
		request_navmesh_rebake()

func request_navmesh_rebake():
	if nav_region:
		nav_region.bake_navigation_polygon(true)

@rpc("any_peer", "call_local", "reliable")
func request_set_player_paused(is_paused: bool):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1

	if is_paused: active_paused_peers[sender_id] = true
	else: active_paused_peers.erase(sender_id)

	var should_pause = not active_paused_peers.is_empty()
	if multiplayer.has_multiplayer_peer():
		rpc("sync_global_pause", should_pause)
	else:
		sync_global_pause(should_pause)

@rpc("call_local", "reliable")
func sync_global_pause(is_paused: bool):
	get_tree().paused = is_paused
	get_tree().call_group("pause_menu", "update_global_pause_state", is_paused)

@rpc("call_local", "reliable")
func trigger_wave_alert_sfx():
	AudioManager.play_sfx("klaxon_alert", Vector2.ZERO, 3.0, 1.0)

@rpc("call_local", "reliable")
func sync_incoming_threat_lanes(lane_angles: Array):
	get_tree().call_group("navigation_pointers", "set_threat_lanes", lane_angles)

func game_over(is_victory: bool):
	if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
		if wave_timer: wave_timer.stop()
		if multiplayer.has_multiplayer_peer():
			rpc("sync_game_over", is_victory)
		else:
			sync_game_over(is_victory)

@rpc("call_local", "reliable")
func sync_game_over(is_victory: bool):
	var a_hud = get_tree().get_first_node_in_group("ability_hud")
	if a_hud: a_hud.hide()
	var w_hud = get_tree().get_first_node_in_group("wave_hud")
	if w_hud: w_hud.hide()
	var m_ui = get_tree().get_first_node_in_group("minimap_ui")
	if m_ui: m_ui.hide()

	var p_ui = get_tree().get_first_node_in_group("pause_menu")
	if p_ui: p_ui.hide()

	_show_game_over_screen(is_victory)

func _show_game_over_screen(is_victory: bool):
	var go_ui = get_node_or_null("%GameOverUI")
	if not go_ui:
		go_ui = $UI.get_node_or_null("GameOverUI")

	if go_ui:
		go_ui.show()

		var title_lbl = go_ui.get_node_or_null("%TitleLabel")
		var sub_lbl = go_ui.get_node_or_null("%SubtitleLabel")
		var bg_draw = go_ui.get_node_or_null("%BackgroundDrawingNode")

		if is_victory:
			if title_lbl:
				title_lbl.text = "◆ PRAISE THE OMNISSIAH — VICTORY ◆"
				title_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
			if sub_lbl:
				sub_lbl.text = "The facility successfully withstood all %d waves of the xeno onslaught." % max_waves
		else:
			if title_lbl:
				title_lbl.text = "◆ CRITICAL SYSTEM FAILURE — DEFEAT ◆"
				title_lbl.add_theme_color_override("font_color", Color(0.92, 0.22, 0.18))
			if sub_lbl:
				sub_lbl.text = "Core breach occurred on Wave %d. The base has fallen." % current_wave

		if bg_draw:
			bg_draw.set("is_victory_screen", is_victory)
			bg_draw.queue_redraw()

		var restart_btn = go_ui.get_node_or_null("%RestartButton")
		if restart_btn and not restart_btn.pressed.is_connected(_on_restart_pressed):
			restart_btn.pressed.connect(_on_restart_pressed)

func _on_restart_pressed():
	if not multiplayer.has_multiplayer_peer():
		execute_rematch()
	elif multiplayer.is_server():
		rpc("execute_rematch")
	else:
		rpc_id(1, "request_rematch")

@rpc("any_peer", "call_local", "reliable")
func request_rematch():
	if not multiplayer.is_server(): return
	rpc("execute_rematch")

@rpc("authority", "call_local", "reliable")
func execute_rematch():
	get_tree().paused = false
	active_paused_peers.clear()

	var go_ui = get_node_or_null("%GameOverUI")
	if not go_ui and has_node("UI/GameOverUI"): go_ui = $UI/GameOverUI
	if go_ui: go_ui.hide()

	var p_ui = get_tree().get_first_node_in_group("pause_menu")
	if p_ui: p_ui.hide()

	var a_hud = get_tree().get_first_node_in_group("ability_hud")
	if a_hud: a_hud.hide()

	current_wave = 0
	active_enemies = 0
	enemies_left_to_spawn = 0
	is_wave_active = false
	is_wave_preparing = false
	scrap_amount = 40
	requisition_amount = 10
	building_count = 0
	base_radar_level = 0
	tech_waaagh_reader_unlocked = false
	
	tech_shields_unlocked = false
	tech_lasers_unlocked = false
	tech_nanobots_unlocked = false
	tech_magnet_unlocked = false
	tech_electro_barricades_unlocked = false
	tech_spikes_cover_unlocked = false

	if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
		if wave_timer: wave_timer.stop()
		for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
		for player in get_tree().get_nodes_in_group("players"): player.queue_free()
		for building in get_tree().get_nodes_in_group("buildings"): building.queue_free()
		for objective in get_tree().get_nodes_in_group("objectives"): objective.queue_free()
		for bg in get_tree().get_nodes_in_group("bodyguards"): bg.queue_free()
		for skull in get_tree().get_nodes_in_group("ServoSkull"): skull.queue_free()
		for scrap in get_tree().get_nodes_in_group("scrap"): scrap.queue_free()
		for dep in get_tree().get_nodes_in_group("scrap_deposits"): dep.queue_free()
		for cit in get_tree().get_nodes_in_group("ork_citadel"): cit.queue_free()
		for heap in get_tree().get_nodes_in_group("ork_structures"): heap.queue_free()

		var base = get_tree().get_first_node_in_group("base")
		if base and base.has_method("sync_base_health"):
			base.sync_base_health(base.max_health)
			
		if multiplayer.has_multiplayer_peer():
			rpc("sync_resources", scrap_amount, requisition_amount)
			rpc("sync_sanctum_tech", 0, false)
			rpc("sync_tech_tree", false, false, false, false, false, false)
		else:
			sync_sanctum_tech(0, false)
			sync_tech_tree(false, false, false, false, false, false)
		request_navmesh_rebake()

	match_started = false
	is_ready = false
	for peer_id in player_ready.keys():
		player_ready[peer_id] = false

	_show_lobby_ui()
	_set_session_text("Cadre standing by. Select class and Ready Up.")
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_broadcast_lobby_state()
