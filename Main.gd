extends Node2D

const GameData = preload("res://GameData.gd")

const DEFAULT_PORT: int = 7000
const DEFAULT_IP: String = "127.0.0.1"

enum CharacterClass {
	ADMECH_TECHPRIEST = 0,
	SKITARII_MARSHAL = 1,
	ADEPTA_SORORITAS = 2
}

const CLASS_DATA = {
	CharacterClass.ADMECH_TECHPRIEST: {
		"name": "Tech-Priest Enginseer",
		"faction": "Adeptus Mechanicus • Cult Mechanicus",
		"role": "Fortification Magos & Heavy Melee Cleave",
		"unit_type_id": 0,
		"arsenal": "• Primary: Omnissian Power-Axe (Heavy Cleave & Armor Shred)\n• Secondary: Plasma Caliver (Auspex Target Lock & Telemetry)\n• Cybernetics: Autonomous Scrap-Harvesting Servo-Skulls\n• Fortifications: Barricades, Plasma Dynamos, Cognis Turrets, Foundries",
		"stats": "🛡️ HP: 150   |   ⚡ SPD: 250   |   ⚙️ ROLE: Base-Builder & Frontline Tank",
		"desc": "Master of the Machine Cult. Constructs interconnected Noospheric defense grids, energizes Aegis refractor shields, and purges heresy with heavy energised axe-strikes.",
		"flavor": "\"There is no truth in flesh, only betrayal. There is no strength in flesh, only weakness.\"\n— The Hymn of Reforging"
	},
	CharacterClass.SKITARII_MARSHAL: {
		"name": "Skitarii Marshal",
		"faction": "Adeptus Mechanicus • Skitarii Legion",
		"role": "Frontline Commander & Tactical RTS Officer",
		"unit_type_id": 1,
		"arsenal": "• Primary: Radium Serpenta Carbine (Rapid Cellular Fallout)\n• Directives: Doctrina Imperative Auras (Conqueror DPS / Protector Armor)\n• Command: Priority Target Designation & Real-Time Cohort Control\n• Retinue: Galvanic Rangers, Sicarian Assassins, Vanguard Shock Troopers\n• Orbital: 220-DMG Fleet Telemetry Lance Strike",
		"stats": "🛡️ HP: 90    |   ⚡ SPD: 340   |   🚩 ROLE: RTS Cohort Commander & Fleet Caller",
		"desc": "Supreme battlefield cohort commander. Shifts sacred Doctrina canticles, coordinates squad movements, gathers combat telemetry, and calls down orbital bombardments.",
		"flavor": "\"The Omnissiah guides our feet as He guides our guns.\"\n— Marshal Directive 0101"
	},
	CharacterClass.ADEPTA_SORORITAS: {
		"name": "Sister Superior",
		"faction": "Adepta Sororitas • Order of Our Martyred Lady",
		"role": "One-Woman Army & Holy Pyre Juggernaut",
		"unit_type_id": 6, # <-- Point to SISTER_OF_BATTLE in UnitSprite
		"arsenal": "• Primary (LMB): Holy Promethium Flamer (Armor-Piercing Burn Cone)\n• Secondary (RMB): Thermal Multi-Melta (Instant Armor Liquefaction)\n• Ability [1]: Seraphim Rocket Dash (Thruster Jump & Fire Trail)\n• Ability [2]: Holy Hand Grenade (Cataclysmic Relic Blast)\n• Ability [3]: Act of Faith: Miracle Shield (Passive Dodge + Instant Regen)\n• Ultimate [4]: Righteous Pyre of Saint Katherine (Ascension Pillar)\n• Passive: Saint Celestine Martyrdom (Angelic Rebirth on Death)",
		"stats": "🛡️ HP: 135   |   ⚡ SPD: 310   |   🔥 ROLE: MOBA Juggernaut & Swarm Melter",
		"desc": "Zealous champion of the God-Emperor. Sweeps across the battlefield incinerating xenos swarms with promethium, shattering heavy armor with melta fire, and resurrecting as an angelic Living Saint.",
		"flavor": "\"In the Emperor's name we cleanse with fire. Let none survive who defy His light.\"\n— Battle Hymn of the Martyred Lady"
	}
}

@export var max_waves: int = 15

var player_scene = preload("res://Player.tscn")
var enemy_scene = preload("res://Enemy.tscn")
var bullet_scene = preload("res://Bullet.tscn")
var scrap_scene = preload("res://Scrap.tscn")
var building_scene = preload("res://Building.tscn")
var waaagh_idol_scene = preload("res://WaaaghIdol.tscn")

var peer: ENetMultiplayerPeer = null
var enemy_count: int = 0
var bullet_count: int = 0
var building_count: int = 0

var has_squig_pit: bool = true
var has_stormboy_pad: bool = true
var has_mek_foundry: bool = true

var stc_aegis_unlocked: bool = false
var stc_volkite_unlocked: bool = false
var is_warboss_spawned: bool = false

var base_auto_builder_node: Node2D = null

var stc_aegis_core_unlocked: bool = false # STC Vault 2

var scrap_amount: int = 75
var requisition_amount: int = 25 

var tech_targeting_uplink_unlocked: bool = false
var base_radar_level: int = 0
var tech_waaagh_reader_unlocked: bool = false
var wave_hud_node: Control = null
var total_wave_enemies_cached: int = 0

var wave_break_timer: float = 0.0
var is_on_wave_break: bool = false

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
var wave_squad_queue: Array[Dictionary] = []
var wave_player_count: int = 1
var spawn_lane_angles: Array[float] = []
var objective_count: int = 0

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

# --- UI CONTROLS ---
var title_root_control: Control = null
var singleplayer_root_control: Control = null
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

# Singleplayer UI Nodes
var sp_class_name_lbl: Label = null
var sp_role_lbl: Label = null
var sp_stats_lbl: Label = null
var sp_arsenal_lbl: Label = null
var sp_desc_lbl: Label = null
var sp_flavor_lbl: Label = null
var sp_sprite_preview: Node2D = null
var tutorial_hud_node: Control = null

var wave_prep_timer: float = 0.0
var is_wave_preparing: bool = false
const WAVE_PREP_DURATION: float = 8.0
const WAVE_BREAK_DURATION: float = 14.0

# --- LAN & UPNP NETWORKING ---
const LAN_BROADCAST_PORT: int = 7001
const LAN_BROADCAST_INTERVAL: float = 1.5

var lan_udp_peer: PacketPeerUDP = null
var lan_broadcast_timer: float = 0.0
var lan_found_hosts: Dictionary = {}

var upnp_instance: UPNP = null
var upnp_thread: Thread = null
var public_ip_cached: String = ""
var is_upnp_active: bool = false
var host_vox_code: String = ""
var upnp_port_cached: int = DEFAULT_PORT

var vox_code_edit: LineEdit = null
var copy_vox_btn: Button = null
var lan_list_container: VBoxContainer = null
var upnp_status_lbl: Label = null

@onready var ui_layer: CanvasLayer = get_node_or_null("UI")
@onready var spawner: MultiplayerSpawner = get_node_or_null("MultiplayerSpawner")
@onready var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")

# ==============================================================================
# LIFECYCLE & PROCESS
# ==============================================================================
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
	_build_title_menu_ui()
	_build_singleplayer_menu_ui()
	_build_procedural_lobby_ui()
	
	_show_title_screen()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_safe_cleanup_peer()

func _process(delta: float) -> void:
	if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
		if is_wave_preparing:
			wave_prep_timer -= delta
			if wave_prep_timer <= 0.0:
				is_wave_preparing = false
				_begin_wave_spawning()
			_broadcast_wave_hud()

		elif is_on_wave_break:
			wave_break_timer -= delta
			if wave_break_timer <= 0.0:
				is_on_wave_break = false
				start_next_wave()
			_broadcast_wave_hud()

		if is_wave_active:
			flanker_raid_timer -= delta
			if flanker_raid_timer <= 0.0:
				flanker_raid_timer = randf_range(28.0, 42.0)
				_spawn_flanker_raid()

	_process_lan_discovery(delta)

# ==============================================================================
# 1. UI HELPERS & NAVIGATION
# ==============================================================================
func _create_menu_action_btn(txt: String, callable: Callable) -> Button:
	var btn = Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(360, 38)
	btn.pressed.connect(callable)
	return btn

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

func _show_title_screen():
	match_started = false
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
	if title_root_control: title_root_control.show()
	if singleplayer_root_control: singleplayer_root_control.hide()
	if lobby_root_control: lobby_root_control.hide()

	# Hide all in-game HUDs and clean up beacons
	get_tree().call_group("tutorial_hud", "reset_tutorial")
	var a_hud = get_tree().get_first_node_in_group("ability_hud")
	if a_hud: a_hud.hide()
	var w_hud = get_tree().get_first_node_in_group("wave_hud")
	if w_hud: w_hud.hide()
	var m_ui = get_tree().get_first_node_in_group("minimap_ui")
	if m_ui: m_ui.hide()

func _show_singleplayer_menu():
	if title_root_control: title_root_control.hide()
	if singleplayer_root_control: singleplayer_root_control.show()
	if lobby_root_control: lobby_root_control.hide()

func _show_multiplayer_menu():
	if title_root_control: title_root_control.hide()
	if singleplayer_root_control: singleplayer_root_control.hide()
	if lobby_root_control: lobby_root_control.show()

func _hide_all_menus():
	if title_root_control: title_root_control.hide()
	if singleplayer_root_control: singleplayer_root_control.hide()
	if lobby_root_control: lobby_root_control.hide()

func _open_settings_from_title():
	if pause_menu_ui_node and pause_menu_ui_node.has_method("open_settings_from_title"):
		if title_root_control: title_root_control.hide()
		pause_menu_ui_node.open_settings_from_title()
	elif pause_menu_ui_node and pause_menu_ui_node.has_method("show_my_pause_menu"):
		pause_menu_ui_node.show_my_pause_menu()
		if pause_menu_ui_node.has_method("_switch_view"):
			pause_menu_ui_node._switch_view(1)

func _setup_core_sub_uis():
	if not has_node("UI/WaveHUD"):
		var w_hud = load("res://WaveHUD.gd").new()
		w_hud.name = "WaveHUD"
		$UI.add_child(w_hud)
		wave_hud_node = w_hud
	
	if not has_node("FogOfWar"):
		var fow = load("res://FogOfWar.gd").new()
		fow.name = "FogOfWar"
		add_child(fow)
	
	if not has_node("UI/TutorialHUD"):
		var tut_hud = load("res://TutorialHUD.gd").new()
		tut_hud.name = "TutorialHUD"
		$UI.add_child(tut_hud)
		tutorial_hud_node = tut_hud
		
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

# ==============================================================================
# 2. TITLE UI BUILDER
# ==============================================================================
func _build_title_menu_ui():
	if not ui_layer: return

	title_root_control = Control.new()
	title_root_control.name = "TitleUI"
	title_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_root_control.theme = AdmechTheme.make()
	ui_layer.add_child(title_root_control)

	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.95)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	title_root_control.add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_root_control.add_child(center)

	var main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(560, 460)
	center.add_child(main_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	main_panel.add_child(vbox)

	var header = Label.new()
	header.text = "◆ ADEPTUS MECHANICUS ◆"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
	header.add_theme_font_size_override("font_size", 14)
	vbox.add_child(header)

	var sub_title = Label.new()
	sub_title.text = "FORGE SANCTUM DEFENSE PROTOCOL"
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_title.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	sub_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(sub_title)

	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.25, 0.28, 0.35, 0.6)
	vbox.add_child(sep)

	var menu_desc = Label.new()
	menu_desc.text = "The Omnissiah's forge facility is besieged by xenos greenskins.\nSelect deployment directive:"
	menu_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_desc.add_theme_font_size_override("font_size", 10)
	menu_desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	vbox.add_child(menu_desc)

	var btn_vbox = VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 10)
	btn_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn_vbox)

	var sp_btn = _create_menu_action_btn("SOLO CRUSADE (Single-Player)", func(): _show_singleplayer_menu())
	var mp_btn = _create_menu_action_btn("MULTIPLAYER VOX-LINK (Co-Op Lobby)", func(): _show_multiplayer_menu())
	var opt_btn = _create_menu_action_btn("OCULAR & AUDIO SETTINGS", func(): _open_settings_from_title())
	var exit_btn = _create_menu_action_btn("SHUT DOWN COGITATOR", func(): get_tree().quit())

	btn_vbox.add_child(sp_btn)
	btn_vbox.add_child(mp_btn)
	btn_vbox.add_child(opt_btn)
	btn_vbox.add_child(exit_btn)

	var footer = Label.new()
	footer.text = "\"From the Motive Force we draw life. To the Omnissiah we return all.\""
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40))
	footer.add_theme_font_size_override("font_size", 9)
	vbox.add_child(footer)

# ==============================================================================
# 3. SINGLEPLAYER DOSSIER UI BUILDER
# ==============================================================================
func _build_singleplayer_menu_ui():
	if not ui_layer: return

	singleplayer_root_control = Control.new()
	singleplayer_root_control.name = "SinglePlayerUI"
	singleplayer_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	singleplayer_root_control.theme = AdmechTheme.make()
	ui_layer.add_child(singleplayer_root_control)

	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.95)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	singleplayer_root_control.add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	singleplayer_root_control.add_child(center)

	var main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(940, 560)
	center.add_child(main_panel)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	main_panel.add_child(root_vbox)

	var title = Label.new()
	title.text = "◆ SOLO DEPLOYMENT: SELECT CADRE COMMANDER ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	root_vbox.add_child(title)

	var body_hbox = HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 16)
	root_vbox.add_child(body_hbox)

	# Left Column
	var left_card = _create_lobby_sub_card("DESIGNATION", body_hbox)
	left_card.custom_minimum_size = Vector2(280, 0)

	var tp_choice_btn = Button.new()
	tp_choice_btn.text = "TECH-PRIEST ENGINSEER"
	tp_choice_btn.custom_minimum_size = Vector2(0, 36)
	tp_choice_btn.pressed.connect(func(): _select_sp_class(CharacterClass.ADMECH_TECHPRIEST))
	left_card.add_child(tp_choice_btn)

	var sk_choice_btn = Button.new()
	sk_choice_btn.text = "SKITARII MARSHAL"
	sk_choice_btn.custom_minimum_size = Vector2(0, 36)
	sk_choice_btn.pressed.connect(func(): _select_sp_class(CharacterClass.SKITARII_MARSHAL))
	left_card.add_child(sk_choice_btn)

	var sob_choice_btn = Button.new()
	sob_choice_btn.text = "SISTER SUPERIOR"
	sob_choice_btn.custom_minimum_size = Vector2(0, 36)
	sob_choice_btn.pressed.connect(func(): _select_sp_class(CharacterClass.ADEPTA_SORORITAS))
	left_card.add_child(sob_choice_btn)


	var preview_panel = PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(250, 220)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.95)
	sb.border_color = Color(0.82, 0.62, 0.24)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	preview_panel.add_theme_stylebox_override("panel", sb)
	left_card.add_child(preview_panel)

	var sub_viewport_container = SubViewportContainer.new()
	sub_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub_viewport_container.stretch = true
	preview_panel.add_child(sub_viewport_container)

	var sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(250, 220)
	sub_viewport.transparent_bg = true
	sub_viewport_container.add_child(sub_viewport)

	var preview_pivot = Node2D.new()
	preview_pivot.name = "PreviewPivot"
	preview_pivot.position = Vector2(125, 120)
	preview_pivot.scale = Vector2(3.5, 3.5)
	sub_viewport.add_child(preview_pivot)

	var pedestal = ClassPreviewPedestal.new()
	preview_pivot.add_child(pedestal)

	sp_sprite_preview = UnitSprite.new()
	sp_sprite_preview.name = "HeroPreviewSprite"
	sp_sprite_preview.position = Vector2.ZERO
	preview_pivot.add_child(sp_sprite_preview)

	# Right Column
	var right_card = _create_lobby_sub_card("HOLY DOSSIER & COMBAT TELEMETRY", body_hbox)
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	sp_class_name_lbl = Label.new()
	sp_class_name_lbl.text = "TECH-PRIEST ENGINSEER"
	sp_class_name_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	sp_class_name_lbl.add_theme_font_size_override("font_size", 14)
	right_card.add_child(sp_class_name_lbl)

	sp_role_lbl = Label.new()
	sp_role_lbl.text = "Fortification Magos & Heavy Melee Cleave"
	sp_role_lbl.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
	sp_role_lbl.add_theme_font_size_override("font_size", 10)
	right_card.add_child(sp_role_lbl)

	sp_stats_lbl = Label.new()
	sp_stats_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
	sp_stats_lbl.add_theme_font_size_override("font_size", 10)
	right_card.add_child(sp_stats_lbl)

	var sep_r = ColorRect.new()
	sep_r.custom_minimum_size = Vector2(0, 1)
	sep_r.color = Color(0.25, 0.28, 0.35, 0.6)
	right_card.add_child(sep_r)

	sp_desc_lbl = Label.new()
	sp_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sp_desc_lbl.add_theme_font_size_override("font_size", 10)
	sp_desc_lbl.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
	right_card.add_child(sp_desc_lbl)

	sp_arsenal_lbl = Label.new()
	sp_arsenal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sp_arsenal_lbl.add_theme_font_size_override("font_size", 9)
	sp_arsenal_lbl.add_theme_color_override("font_color", Color(0.70, 0.85, 0.95))
	right_card.add_child(sp_arsenal_lbl)

	sp_flavor_lbl = Label.new()
	sp_flavor_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sp_flavor_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp_flavor_lbl.add_theme_font_size_override("font_size", 9)
	sp_flavor_lbl.add_theme_color_override("font_color", Color(0.65, 0.58, 0.45))
	right_card.add_child(sp_flavor_lbl)

	# Bottom Bar
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", 24)
	root_vbox.add_child(bottom_hbox)

	var back_btn = Button.new()
	back_btn.text = "← RETURN TO MAIN MENU"
	back_btn.custom_minimum_size = Vector2(220, 36)
	back_btn.pressed.connect(_show_title_screen)
	bottom_hbox.add_child(back_btn)

	var launch_sp_btn = Button.new()
	launch_sp_btn.text = "⚡ DEPLOY TO FORGE WORLD (Start Game) ⚡"
	launch_sp_btn.custom_minimum_size = Vector2(340, 36)
	launch_sp_btn.pressed.connect(_start_singleplayer_game)
	bottom_hbox.add_child(launch_sp_btn)

	_select_sp_class(CharacterClass.ADMECH_TECHPRIEST)

func _select_sp_class(c_class: CharacterClass):
	my_selected_class = c_class
	var data: Dictionary = CLASS_DATA.get(c_class, {})
	if data.is_empty(): return

	if sp_class_name_lbl: sp_class_name_lbl.text = "◆ " + data.get("name", "").to_upper() + " ◆"
	if sp_role_lbl: sp_role_lbl.text = data.get("faction", "") + "\n" + data.get("role", "")
	if sp_stats_lbl: sp_stats_lbl.text = data.get("stats", "")
	if sp_desc_lbl: sp_desc_lbl.text = data.get("desc", "")
	if sp_arsenal_lbl: sp_arsenal_lbl.text = data.get("arsenal", "")
	if sp_flavor_lbl: sp_flavor_lbl.text = data.get("flavor", "")

	if sp_sprite_preview:
		sp_sprite_preview.unit_type = data.get("unit_type_id", 0) as UnitSprite.UnitType
		sp_sprite_preview.update_facing(sp_sprite_preview.global_position + Vector2(20, 35))
		sp_sprite_preview.queue_redraw()

func _start_singleplayer_game():
	# 1. Silently start the host server in the background
	_on_host_pressed()

	# 2. Lock in your chosen class and mark ready
	player_classes[1] = my_selected_class
	player_ready[1] = true

	# 3. Skip the lobby entirely and launch straight onto the battlefield
	_hide_all_menus()
	_begin_match()

# ==============================================================================
# 4. MULTIPLAYER LOBBY UI BUILDER
# ==============================================================================
func _build_procedural_lobby_ui():
	if not ui_layer: return

	lobby_root_control = Control.new()
	lobby_root_control.name = "LobbyUI"
	lobby_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_root_control.theme = AdmechTheme.make()
	ui_layer.add_child(lobby_root_control)

	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.04, 0.06, 0.95)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	lobby_root_control.add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_root_control.add_child(center)

	var main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(940, 540)
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
	lobby_session_label.text = "Standing by. Host a sanctum forge or link via Vox Code."
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

	# Column 1
	var col1 = _create_lobby_sub_card("1. CONNECTION PROTOCOLS", body_hbox)
	col1.custom_minimum_size = Vector2(300, 0)

	lobby_host_btn = Button.new()
	lobby_host_btn.text = "⚡ HOST SANCTUM (Create Server)"
	lobby_host_btn.custom_minimum_size = Vector2(0, 32)
	lobby_host_btn.pressed.connect(_on_host_pressed)
	col1.add_child(lobby_host_btn)

	upnp_status_lbl = Label.new()
	upnp_status_lbl.text = "UPnP: Standby"
	upnp_status_lbl.add_theme_font_size_override("font_size", 9)
	upnp_status_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	col1.add_child(upnp_status_lbl)

	var vox_lbl = Label.new()
	vox_lbl.text = "Vox Transmission Code (Share with friends):"
	vox_lbl.add_theme_font_size_override("font_size", 9)
	col1.add_child(vox_lbl)

	var code_hbox = HBoxContainer.new()
	col1.add_child(code_hbox)

	vox_code_edit = LineEdit.new()
	vox_code_edit.placeholder_text = "Paste VOX-XXXX code..."
	vox_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_hbox.add_child(vox_code_edit)

	copy_vox_btn = Button.new()
	copy_vox_btn.text = "📋 COPY"
	copy_vox_btn.disabled = true
	copy_vox_btn.pressed.connect(func():
		if not host_vox_code.is_empty():
			DisplayServer.clipboard_set(host_vox_code)
			copy_vox_btn.text = "COPIED!"
			get_tree().create_timer(1.5).timeout.connect(func(): if copy_vox_btn: copy_vox_btn.text = "📋 COPY")
	)
	code_hbox.add_child(copy_vox_btn)

	var paste_btn = Button.new()
	paste_btn.text = "PASTE"
	paste_btn.pressed.connect(func():
		if vox_code_edit: vox_code_edit.text = DisplayServer.clipboard_get()
	)
	code_hbox.add_child(paste_btn)

	lobby_join_btn = Button.new()
	lobby_join_btn.text = "ESTABLISH VOX-LINK (Join)"
	lobby_join_btn.pressed.connect(_on_join_pressed)
	col1.add_child(lobby_join_btn)

	var lan_header = Label.new()
	lan_header.text = "◆ LOCAL SANCTUMS DETECTED (LAN) ◆"
	lan_header.add_theme_font_size_override("font_size", 9)
	lan_header.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
	col1.add_child(lan_header)

	var lan_scroll = ScrollContainer.new()
	lan_scroll.custom_minimum_size = Vector2(0, 60)
	lan_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col1.add_child(lan_scroll)

	lan_list_container = VBoxContainer.new()
	lan_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lan_scroll.add_child(lan_list_container)

	lobby_disconnect_btn = Button.new()
	lobby_disconnect_btn.text = "DISENGAGE LINK"
	lobby_disconnect_btn.disabled = true
	lobby_disconnect_btn.pressed.connect(_on_disconnect_pressed)
	col1.add_child(lobby_disconnect_btn)

	# Column 2
	var col2 = _create_lobby_sub_card("2. CADRE DESIGNATION", body_hbox)

	var class_btn_hbox = HBoxContainer.new()
	class_btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	class_btn_hbox.add_theme_constant_override("separation", 6)
	col2.add_child(class_btn_hbox)

	var tp_btn = Button.new()
	tp_btn.text = "TECH-PRIEST"
	tp_btn.pressed.connect(func(): _select_class_local(CharacterClass.ADMECH_TECHPRIEST))
	class_btn_hbox.add_child(tp_btn)

	var sob_btn = Button.new()
	sob_btn.text = "SISTER"
	sob_btn.pressed.connect(func(): _select_class_local(CharacterClass.ADEPTA_SORORITAS))
	class_btn_hbox.add_child(sob_btn)

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

	# Column 3
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

	lobby_ip_edit = LineEdit.new()
	lobby_ip_edit.text = DEFAULT_IP
	lobby_ip_edit.visible = false
	col1.add_child(lobby_ip_edit)

	lobby_port_edit = LineEdit.new()
	lobby_port_edit.text = str(DEFAULT_PORT)
	lobby_port_edit.visible = false
	col1.add_child(lobby_port_edit)

	var bottom_bar = HBoxContainer.new()
	bottom_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(bottom_bar)

	var return_btn = Button.new()
	return_btn.text = "← RETURN TO MAIN MENU"
	return_btn.custom_minimum_size = Vector2(240, 32)
	return_btn.pressed.connect(func():
		_on_disconnect_pressed()
		_show_title_screen()
	)
	bottom_bar.add_child(return_btn)

	_update_class_ui()
	_refresh_lobby_roster()
	_init_lan_listener()

# ==============================================================================
# 5. NETWORKING (UPnP, LAN, WEBSOCKETS/ENET)
# ==============================================================================

func _update_host_vox_code(port: int):
	if public_ip_cached.is_empty():
		public_ip_cached = "127.0.0.1"
	
	var raw_str = "%s:%d" % [public_ip_cached, port]
	host_vox_code = "VOX-" + Marshalls.utf8_to_base64(raw_str).replace("=", "")
	
	if vox_code_edit:
		vox_code_edit.text = host_vox_code
	if copy_vox_btn:
		copy_vox_btn.disabled = false

func _decode_vox_code(code: String) -> Dictionary:
	var clean = code.strip_edges()
	if clean.begins_with("VOX-"):
		clean = clean.substr(4)
	
	while clean.length() % 4 != 0:
		clean += "="
	
	var decoded = Marshalls.base64_to_utf8(clean)
	var parts = decoded.split(":")
	if parts.size() >= 2:
		return {"ip": parts[0], "port": int(parts[1])}
	
	if clean.contains("."):
		return {"ip": clean, "port": DEFAULT_PORT}
	
	return {}

func _init_lan_listener():
	_cleanup_lan_socket()
	lan_udp_peer = PacketPeerUDP.new()
	lan_udp_peer.set_broadcast_enabled(true)
	lan_udp_peer.bind(LAN_BROADCAST_PORT)

func _process_lan_discovery(delta: float):
	if is_instance_valid(peer) and multiplayer.is_server():
		lan_broadcast_timer += delta
		if lan_broadcast_timer >= LAN_BROADCAST_INTERVAL:
			lan_broadcast_timer = 0.0
			var msg = JSON.stringify({
				"name": "Sanctum #" + str(multiplayer.get_unique_id()),
				"port": int(lobby_port_edit.text) if lobby_port_edit else DEFAULT_PORT,
				"players": player_classes.size()
			})
			if not lan_udp_peer:
				lan_udp_peer = PacketPeerUDP.new()
				lan_udp_peer.set_broadcast_enabled(true)
			lan_udp_peer.set_dest_address("255.255.255.255", LAN_BROADCAST_PORT)
			lan_udp_peer.put_packet(msg.to_utf8_buffer())

	if not match_started and is_instance_valid(lan_udp_peer) and lan_udp_peer.is_bound():
		while lan_udp_peer.get_available_packet_count() > 0:
			var sender_ip = lan_udp_peer.get_packet_ip()
			var raw_packet = lan_udp_peer.get_packet().get_string_from_utf8()
			var parsed = JSON.parse_string(raw_packet)
			if parsed is Dictionary:
				var key = "%s:%d" % [sender_ip, int(parsed.get("port", DEFAULT_PORT))]
				lan_found_hosts[key] = {
					"ip": sender_ip,
					"port": int(parsed.get("port", DEFAULT_PORT)),
					"name": parsed.get("name", "Local Sanctum"),
					"players": parsed.get("players", 1),
					"last_seen": Time.get_ticks_msec()
				}
				_refresh_lan_ui_list()

func _refresh_lan_ui_list():
	if not is_instance_valid(lan_list_container): return

	for c in lan_list_container.get_children():
		c.queue_free()

	var now = Time.get_ticks_msec()
	for key in lan_found_hosts.keys():
		var info = lan_found_hosts[key]
		if now - info.last_seen > 4000:
			lan_found_hosts.erase(key)
			continue

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var lbl = Label.new()
		lbl.text = "⚡ %s (%d Cadre)" % [info.name, info.players]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
		row.add_child(lbl)

		var join_btn = Button.new()
		join_btn.text = "JOIN"
		join_btn.custom_minimum_size = Vector2(50, 20)
		join_btn.pressed.connect(func(): _join_game_direct(info.ip, info.port))
		row.add_child(join_btn)

		lan_list_container.add_child(row)

func _get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and not ip.begins_with("172.16.")):
			return ip
	return "127.0.0.1"

func _cleanup_lan_socket():
	if lan_udp_peer:
		lan_udp_peer.close()
		lan_udp_peer = null

func _safe_cleanup_peer():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	peer = null
	if upnp_thread and upnp_thread.is_started():
		upnp_thread.wait_to_finish()

func _on_host_pressed():
	_safe_cleanup_peer()
	
	var port = int(lobby_port_edit.text) if (lobby_port_edit and lobby_port_edit.text != "") else DEFAULT_PORT
	upnp_port_cached = port

	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 4)
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

	# Show busy state until the real external IP is verified
	if vox_code_edit:
		vox_code_edit.text = "Generating Vox Code (Negotiating UPnP)..."
	if copy_vox_btn:
		copy_vox_btn.disabled = true

	if upnp_status_lbl:
		upnp_status_lbl.text = "UPnP: Probing Gateway & Forwarding Port..."
		upnp_status_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.20))

	_set_session_text("◆ SANCTUM INITIALIZING ◆ Forwarding port & resolving IP...")
	_update_connection_buttons(true)
	_refresh_lobby_roster()
	_broadcast_lobby_state()

	_discover_public_ip_and_upnp(port)

func _discover_public_ip_and_upnp(port: int):
	# Run UPnP discovery in a background thread to prevent game stutter [1]
	upnp_thread = Thread.new()
	upnp_thread.start(_run_upnp_task.bind(port))

func _run_upnp_task(port: int):
	upnp_instance = UPNP.new()
	var discover_res = upnp_instance.discover(2000, 2, "InternetGatewayDevice")
	
	var found_ip: String = ""
	var port_mapped: bool = false
	
	if discover_res == UPNP.UPNP_RESULT_SUCCESS:
		var gateway = upnp_instance.get_gateway()
		if gateway and gateway.is_valid_gateway():
			var map_res = upnp_instance.add_port_mapping(port, port, "Godot_AdMech_Game", "UDP")
			if map_res == UPNP.UPNP_RESULT_SUCCESS:
				port_mapped = true
				found_ip = upnp_instance.query_external_address()
				print("[UPnP] Successfully mapped UDP port ", port, " on router external IP: ", found_ip)
			else:
				print("[UPnP] Port mapping failed with code: ", map_res)
		else:
			print("[UPnP] No valid UPnP gateway found.")
	else:
		print("[UPnP] UPnP discovery failed with code: ", discover_res)

	# Deliver result back to the main thread
	_on_upnp_completed.call_deferred(port_mapped, found_ip, port)

func _on_upnp_completed(port_mapped: bool, external_ip: String, port: int):
	if upnp_thread and upnp_thread.is_started():
		upnp_thread.wait_to_finish()
		upnp_thread = null

	is_upnp_active = port_mapped

	if is_upnp_active and not external_ip.is_empty():
		public_ip_cached = external_ip
		if upnp_status_lbl:
			upnp_status_lbl.text = "⚡ UPnP: PORT FORWARDED (ONLINE READY)"
			upnp_status_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
		_set_session_text("◆ SANCTUM READY ◆ Share Vox Code with your cadre.")
		_update_host_vox_code(port)
	else:
		# Fallback: query public IP via HTTP if router's UPnP is disabled
		if upnp_status_lbl:
			upnp_status_lbl.text = "⚠️ UPnP: UNAVAILABLE (Resolving IP via Web / LAN)"
			upnp_status_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.20))
		
		var http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(func(_res, code, _headers, body):
			if code == 200:
				public_ip_cached = body.get_string_from_utf8().strip_edges()
			else:
				public_ip_cached = _get_local_ip()
			_update_host_vox_code(port)
			_set_session_text("◆ SANCTUM READY ◆ (Manual Port Forwarding or LAN may be required)")
			http.queue_free()
		)
		http.request("https://api.ipify.org")

func _on_join_pressed():
	var code_input = vox_code_edit.text.strip_edges() if vox_code_edit else ""
	var target_ip = DEFAULT_IP
	var target_port = DEFAULT_PORT

	if not code_input.is_empty():
		var decoded = _decode_vox_code(code_input)
		if not decoded.is_empty():
			target_ip = decoded.ip
			target_port = decoded.port
	else:
		target_ip = lobby_ip_edit.text.strip_edges() if (lobby_ip_edit and lobby_ip_edit.text != "") else DEFAULT_IP
		target_port = int(lobby_port_edit.text) if (lobby_port_edit and lobby_port_edit.text != "") else DEFAULT_PORT

	_join_game_direct(target_ip, target_port)

func _join_game_direct(ip: String, port: int):
	_safe_cleanup_peer()

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
	_cleanup_lan_socket()
	player_classes.clear()
	player_ready.clear()
	is_ready = false
	host_vox_code = ""
	if vox_code_edit: vox_code_edit.text = ""
	_set_session_text("Vox-Link disengaged. Standing by.")
	_update_connection_buttons(false)
	_refresh_lobby_roster()
	_init_lan_listener()

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
	rpc("sync_lobby_state", player_classes, player_ready, match_started)
	_refresh_lobby_roster()

@rpc("authority", "call_local", "reliable")
func sync_lobby_state(classes_data: Dictionary, ready_data: Dictionary, started: bool) -> void:
	player_classes = classes_data.duplicate()
	player_ready = ready_data.duplicate()
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
		
	_spawn_world_terrain()
	_spawn_map_scrap_deposits()
	_spawn_ork_mega_camp()
	_spawn_stc_vaults()
	
	# --- ADD THIS LINE TO ENGAGE BASE AI IF NO TECH-PRIEST IS PLAYING ---
	_check_and_initiate_base_ai()

	request_navmesh_rebake()
	start_next_wave()

@rpc("authority", "call_local", "reliable")
func sync_match_started() -> void:
	_begin_match_local()

func _begin_match_local() -> void:
	match_started = true
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_CONFINED)
	_hide_all_menus()
	
	# Show Ability HUD
	var a_hud = get_tree().get_first_node_in_group("ability_hud")
	if a_hud and a_hud.has_method("show"): 
		a_hud.show()

	# Show Wave HUD
	var w_hud = get_tree().get_first_node_in_group("wave_hud")
	if w_hud and w_hud.has_method("show"): 
		w_hud.show()

	# Show Minimap / Radar
	var m_ui = get_tree().get_first_node_in_group("minimap_ui")
	if m_ui and m_ui.has_method("show"): 
		m_ui.show()

	# --- ADD THIS: Initialize and Show Tutorial for Local Player's Chosen Class ---
	var tut_hud = get_tree().get_first_node_in_group("tutorial_hud")
	if tut_hud and tut_hud.has_method("start_tutorial_for_class"):
		tut_hud.start_tutorial_for_class(int(my_selected_class))

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
	var info: Dictionary = CLASS_DATA.get(my_selected_class, {})
	if not info.is_empty() and lobby_class_desc_label:
		lobby_class_desc_label.text = "◆ %s ◆\n%s\n\n%s" % [info.get("name", "").to_upper(), info.get("role", ""), info.get("desc", "")]
		
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

	for peer_id in ids:
		var c_id: int = int(player_classes.get(peer_id, 0))
		var info: Dictionary = CLASS_DATA.get(c_id, {"name": "Acolyte"})
		var rdy: bool = bool(player_ready.get(peer_id, false))
		if not rdy: all_ready = false
		
		var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		var tag = " (You)" if int(peer_id) == my_id else ""
		var status_str = "[READY]" if rdy else "[STANDBY]"
		lines.append("%s %s #%d%s" % [status_str, info.get("name", "Acolyte"), int(peer_id), tag])

	lobby_roster_label.text = "\n".join(lines)
	
	if lobby_start_btn and multiplayer.is_server():
		lobby_start_btn.disabled = not all_ready
		lobby_start_btn.text = "INITIATE CRUSADE" if all_ready else "WAITING ON CADRE..."

func _check_and_initiate_base_ai():
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var has_techpriest = false
	for peer_id in player_classes.keys():
		if int(player_classes[peer_id]) == CharacterClass.ADMECH_TECHPRIEST:
			has_techpriest = true
			break

	if not has_techpriest:
		print("◆ ENGAGING SANCTUM AUTOMATED COGITATOR DEFENSE SUBROUTINE ◆")
		if not is_instance_valid(base_auto_builder_node):
			var builder_script = load("res://BaseAutoBuilder.gd")
			base_auto_builder_node = builder_script.new()
			base_auto_builder_node.name = "SanctumAutoBuilder"
			add_child(base_auto_builder_node)

# ==============================================================================
# 6. SPAWNER & ENTITY ROUTING
# ==============================================================================
func _spawn_world_terrain():
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2(500, 500)
	var obs_idx = 0

	# 1. MOUNTAIN RIDGES (Create 6-8 natural winding chokepoint walls)
	for ridge in range(7):
		var ridge_angle = (float(ridge) * TAU / 7.0) + randf_range(-0.3, 0.3)
		var ridge_start = base_pos + Vector2.RIGHT.rotated(ridge_angle) * randf_range(650.0, 1100.0)
		var ridge_dir = Vector2.RIGHT.rotated(ridge_angle + randf_range(1.1, 1.8))
		var segment_count = randi_range(6, 11)
		var current_pos = ridge_start

		for seg in range(segment_count):
			obs_idx += 1
			var r = randf_range(38.0, 56.0)
			spawn_entity({
				"type": "world_obstacle",
				"name": "MountainRidge_" + str(obs_idx),
				"position": current_pos.snapped(Vector2(24, 24)),
				"obstacle_type": WorldObstacle.ObstacleType.MOUNTAIN_CRAG,
				"radius": r
			})
			current_pos += ridge_dir * (r * 1.35) + Vector2.RIGHT.rotated(randf() * TAU) * 12.0

	# 2. IRONWOOD FOREST GROVES (10 dense forest pockets)
	for grove in range(10):
		var grove_angle = randf() * TAU
		var grove_center = base_pos + Vector2.RIGHT.rotated(grove_angle) * randf_range(600.0, 2200.0)
		var tree_count = randi_range(7, 14)

		for t in range(tree_count):
			obs_idx += 1
			var t_pos = grove_center + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(15.0, 120.0)
			spawn_entity({
				"type": "world_obstacle",
				"name": "Tree_" + str(obs_idx),
				"position": t_pos.snapped(Vector2(16, 16)),
				"obstacle_type": WorldObstacle.ObstacleType.IRONWOOD_TREE,
				"radius": randf_range(24.0, 36.0)
			})

	# 3. INDUSTRIAL SECTOR RUINS (Urban chokes on the perimeter)
	for ruin in range(12):
		obs_idx += 1
		var ruin_pos = base_pos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(750.0, 2100.0)
		spawn_entity({
			"type": "world_obstacle",
			"name": "Ruin_" + str(obs_idx),
			"position": ruin_pos.snapped(Vector2(32, 32)),
			"obstacle_type": WorldObstacle.ObstacleType.INDUSTRIAL_RUIN,
			"radius": randf_range(42.0, 60.0)
		})

func spawn_entity(data: Dictionary) -> Node:
	if spawner and multiplayer.has_multiplayer_peer():
		return spawner.spawn(data)
	else:
		var node = _custom_spawner(data)
		if is_instance_valid(node):
			add_child(node)
		return node

func spawn_player(peer_id: int):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	for p in get_tree().get_nodes_in_group("players"):
		if p.name == str(peer_id): return

	var chosen_class = player_classes.get(peer_id, my_selected_class)
	var p_node = spawn_entity({
		"type": "player",
		"peer_id": peer_id,
		"class": chosen_class
	})

	# Starter Servo-Skull for Tech-Priest
	if chosen_class == CharacterClass.ADMECH_TECHPRIEST:
		spawn_entity({
			"type": "servo_skull",
			"name": "ServoSkull_Starter_" + str(peer_id),
			"position": p_node.position + Vector2(35, -20),
			"owner_id": peer_id
		})

	# Launch Class-Specific Tutorial for Local Player
	if peer_id == multiplayer.get_unique_id() or (peer_id == 1 and not multiplayer.has_multiplayer_peer()):
		var tut = get_tree().get_first_node_in_group("tutorial_hud")
		if tut and tut.has_method("start_tutorial_for_class"):
			tut.start_tutorial_for_class(int(chosen_class))

func _custom_spawner(data: Variant) -> Node:
	var dict_data: Dictionary = {}
	if data is Array and not data.is_empty():
		if data[0] is Dictionary:
			dict_data = data[0]
	elif data is Dictionary:
		dict_data = data
	else:
		return null

	var obj_type = dict_data.get("type", "")
	match obj_type:
		"player":
			var player = player_scene.instantiate()
			var peer_id = dict_data.get("peer_id", 1)
			player.name = str(peer_id)
			var chosen_class = dict_data.get("class", CharacterClass.ADMECH_TECHPRIEST)
			
			player.current_class = int(chosen_class)
			if player.has_method("set_player_class"):
				player.set_player_class(player.current_class)
			
			var base_node = get_tree().get_first_node_in_group("base")
			var base_pos = base_node.global_position if base_node else Vector2(500, 500)
			var offset_x = -30.0 if peer_id == 1 else 30.0
			player.position = base_pos + Vector2(offset_x, 80.0)
			return player

		"world_obstacle":
			var obs = WorldObstacle.new()
			obs.name = str(dict_data.get("name", "Obstacle"))
			obs.position = dict_data.get("position", Vector2.ZERO)
			obs.obstacle_type = dict_data.get("obstacle_type", WorldObstacle.ObstacleType.MOUNTAIN_CRAG)
			obs.radius = dict_data.get("radius", 36.0)
			return obs

		"cohort_infantry":
			var inf_script = load("res://SkitariiInfantry.gd")
			var inf = CharacterBody2D.new()
			inf.set_script(inf_script)
			inf.name = str(dict_data.get("name", "Infantry"))
			inf.position = dict_data.get("position", Vector2.ZERO)
			inf.unit_type = dict_data.get("unit_type", GameData.CohortUnitType.VANGUARD)
			inf.set_multiplayer_authority(1)
			return inf

		"kataphron_unit":
			var kata_script = load("res://KataphronUnit.gd")
			var kata = CharacterBody2D.new()
			kata.set_script(kata_script)
			kata.name = str(dict_data.get("name", "Kataphron"))
			kata.position = dict_data.get("position", Vector2.ZERO)
			kata.set_multiplayer_authority(1)
			return kata

		"building":
			var building = building_scene.instantiate()
			building.name = str(dict_data.get("name", "Building"))
			building.position = dict_data.get("position", Vector2.ZERO)
			if "building_type" in dict_data:
				building.building_type = dict_data["building_type"]
			return building

		"enemy":
			var enemy = enemy_scene.instantiate()
			enemy.name = str(dict_data.get("name", "Enemy"))
			enemy.position = dict_data.get("position", Vector2.ZERO)
			if "enemy_type" in dict_data: enemy.type = int(dict_data["enemy_type"])
			if "is_objective_guard" in dict_data: enemy.is_objective_guard = dict_data["is_objective_guard"]
			if "guard_anchor" in dict_data: enemy.guard_anchor = dict_data["guard_anchor"]
			if "counts_toward_wave" in dict_data: enemy.counts_toward_wave = dict_data["counts_toward_wave"]
			return enemy

		"bullet":
			var bullet = bullet_scene.instantiate()
			bullet.name = str(dict_data.get("name", "Bullet"))
			bullet.position = dict_data.get("position", Vector2.ZERO)
			bullet.direction = dict_data.get("direction", Vector2.RIGHT)
			bullet.rotation = bullet.direction.angle()
			if "damage" in dict_data: bullet.damage = dict_data["damage"]
			if "bullet_type" in dict_data: bullet.bullet_type = int(dict_data["bullet_type"])
			if "is_enemy_bullet" in dict_data: bullet.is_enemy_bullet = dict_data["is_enemy_bullet"]
			if "is_plasma_caliver" in dict_data: bullet.is_plasma_caliver = dict_data["is_plasma_caliver"]
			return bullet

		"kastelan_robot":
			var robot_script = load("res://KastelanRobot.gd")
			var robot = CharacterBody2D.new()
			robot.set_script(robot_script)
			robot.name = str(dict_data.get("name", "Kastelan"))
			robot.position = dict_data.get("position", Vector2.ZERO)
			robot.set_multiplayer_authority(1)
			var owner_id = dict_data.get("owner_id", 1)
			var p_node = get_node_or_null(str(owner_id))
			if not p_node:
				p_node = get_tree().get_first_node_in_group("players")
			if p_node:
				robot.player_owner = p_node
				p_node.active_kastelan_robot = robot
			return robot

		"scrap":
			var scrap = scrap_scene.instantiate()
			scrap.name = str(dict_data.get("name", "Scrap"))
			scrap.position = dict_data.get("position", Vector2.ZERO)
			return scrap

		"scrap_deposit":
			var dep = StaticBody2D.new()
			dep.set_script(load("res://ScrapDeposit.gd"))
			dep.name = str(dict_data.get("name", "ScrapDeposit"))
			dep.position = dict_data.get("position", Vector2.ZERO)
			return dep

		"ork_citadel":
			var cit = StaticBody2D.new()
			cit.set_script(load("res://OrkCitadel.gd"))
			cit.name = str(dict_data.get("name", "OrkCitadel"))
			cit.position = dict_data.get("position", Vector2.ZERO)
			return cit

		"stc_vault":
			var vault = STCVault.new()
			vault.name = str(dict_data.get("name", "STCVault"))
			vault.position = dict_data.get("position", Vector2.ZERO)
			vault.relic_id = dict_data.get("relic_id", 0)
			return vault

		"ork_satellite":
			var sat = OrkSatelliteCamp.new()
			sat.name = str(dict_data.get("name", "Satellite"))
			sat.position = dict_data.get("position", Vector2.ZERO)
			sat.sub_type = dict_data.get("sub_type", "squig_pit")
			return sat

		"ork_scrap_heap":
			var heap = StaticBody2D.new()
			heap.set_script(load("res://OrkScrapHeap.gd"))
			heap.name = str(dict_data.get("name", "ScrapHeap"))
			heap.position = dict_data.get("position", Vector2.ZERO)
			return heap

		"waaagh_idol":
			var idol = waaagh_idol_scene.instantiate()
			idol.name = str(dict_data.get("name", "WaaaghIdol"))
			idol.position = dict_data.get("position", Vector2.ZERO)
			return idol

		"bodyguard":
			var bodyguard_scene = preload("res://SkitariiBodyguard.tscn")
			var bg = bodyguard_scene.instantiate()
			bg.name = str(dict_data.get("name", "Bodyguard"))
			bg.position = dict_data.get("position", Vector2.ZERO)
			if "guard_role" in dict_data:
				bg.guard_role = int(dict_data["guard_role"])
			bg.set_multiplayer_authority(1)
			var owner_id = dict_data.get("owner_id", 1)
			var p_node = get_node_or_null(str(owner_id))
			if not p_node:
				p_node = get_tree().get_first_node_in_group("players")
			if p_node:
				bg.player_owner = p_node
				if "active_bodyguards" in p_node:
					p_node.active_bodyguards.append(bg)
			return bg

		"servo_skull":
			var servoskull_scene = preload("res://ServoSkull.tscn")
			var skull = servoskull_scene.instantiate()
			skull.name = str(dict_data.get("name", "ServoSkull"))
			skull.position = dict_data.get("position", Vector2.ZERO)
			skull.set_multiplayer_authority(1)
			var owner_id = dict_data.get("owner_id", 1)
			var p_node = get_node_or_null(str(owner_id))
			if not p_node:
				p_node = get_tree().get_first_node_in_group("players")
			if p_node:
				if skull.has_method("set_owner_player"):
					skull.set_owner_player(p_node)
				elif "player_owner" in skull:
					skull.player_owner = p_node
				if "active_servo_skulls" in p_node:
					p_node.active_servo_skulls.append(skull)
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
	var target_building = _find_building_by_name(building_name)
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
	var target_building = _find_building_by_name(building_name)
	if is_instance_valid(target_building) and target_building.has_method("set_rally_point"):
		target_building.set_rally_point(rally_pos)
		if multiplayer.has_multiplayer_peer():
			target_building.rpc("set_rally_point", rally_pos)

func _spawn_map_scrap_deposits():
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2(500, 500)

	# 2 starter deposits right next to base
	for i in range(2):
		var angle = (PI * 0.75) if i == 0 else (-PI * 0.25)
		spawn_entity({
			"type": "scrap_deposit",
			"name": "ScrapDeposit_Start_" + str(i + 1),
			"position": (base_pos + Vector2.RIGHT.rotated(angle) * 260.0).snapped(Vector2(32, 32))
		})

	# 14 Wild expansion deposits scattered across the big map
	for i in range(14):
		var angle = (float(i) * TAU / 14.0) + randf_range(-0.25, 0.25)
		var dist = randf_range(750.0, 2300.0)
		spawn_entity({
			"type": "scrap_deposit",
			"name": "ScrapDeposit_Wild_" + str(i + 1),
			"position": (base_pos + Vector2.RIGHT.rotated(angle) * dist).snapped(Vector2(32, 32))
		})

func _spawn_ork_mega_camp():
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2(500, 500)

	# Main Citadel positioned deep in the wilderness
	var camp_pos = (base_pos + Vector2.RIGHT.rotated(randf_range(-PI, PI)) * 2300.0).snapped(Vector2(32, 32))
	spawn_entity({
		"type": "ork_citadel",
		"name": "OrkCitadel_Core",
		"position": camp_pos
	})

	has_squig_pit = true
	has_stormboy_pad = true
	has_mek_foundry = true

	var dir_to_base = (base_pos - camp_pos).normalized()
	
	# 1. Spawn 3 Strategic Satellite Camps around the Citadel
	var satellite_data = [
		{"name": "SquigPit", "pos": camp_pos + dir_to_base.rotated(1.8) * 160.0, "type": "squig_pit", "guard_type": 1},
		{"name": "StormboyPad", "pos": camp_pos + dir_to_base.rotated(-1.8) * 160.0, "type": "stormboy_pad", "guard_type": 3},
		{"name": "MekFoundry", "pos": camp_pos - (dir_to_base * 160.0), "type": "mek_foundry", "guard_type": 4}
	]

	for sat in satellite_data:
		spawn_entity({
			"type": "ork_satellite",
			"name": sat["name"],
			"position": sat["pos"].snapped(Vector2(32, 32)),
			"sub_type": sat["type"]
		})
		
		# Spawn 2 dedicated guards per satellite camp
		for g in range(2):
			spawn_entity({
				"type": "enemy",
				"name": "SatGuard_" + str(randi()),
				"enemy_type": sat["guard_type"],
				"position": sat["pos"] + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(25.0, 60.0),
				"is_objective_guard": true,
				"guard_anchor": sat["pos"],
				"counts_toward_wave": false
			})

	# 2. Spawn Heavy Citadel Core Warband Garrison (2 Nobz, 4 Boyz, 2 Squigs)
	var citadel_garrison = [4, 4, 2, 2, 2, 2, 1, 1]
	for g_type in citadel_garrison:
		spawn_entity({
			"type": "enemy",
			"name": "CitadelGarrison_" + str(randi()),
			"enemy_type": g_type,
			"position": camp_pos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 110.0),
			"is_objective_guard": true,
			"guard_anchor": camp_pos,
			"counts_toward_wave": false
		})

	# Register on Minimap
	get_tree().call_group("minimap_ui", "register_citadel_position", camp_pos)

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
	# 35 seconds on Wave 1 so new players have time to build; 8s on subsequent waves
	wave_prep_timer = 35.0 if current_wave == 1 else 8.0
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

func get_waaagh_speed_multiplier() -> float:
	var totems = get_active_totem_count()
	# Each active WAAAGH! totem increases all Ork speed by +10%
	return 1.0 + (totems * 0.10)

func get_waaagh_damage_multiplier() -> float:
	var totems = get_active_totem_count()
	# Each active WAAAGH! totem increases all Ork damage by +12%
	return 1.0 + (totems * 0.12)

func get_waaagh_intensity_pct() -> float:
	var totems = get_active_totem_count()
	# 0 to 100% based on active totems + current wave escalation
	return clampf((totems * 0.25) + (float(current_wave) / float(max_waves)) * 0.35, 0.0, 1.0)

# Dynamic TAB Break Pacing (Breather vs High-Tension)
func _get_wave_break_duration(wave: int) -> float:
	match wave:
		4, 8, 11:
			return 22.0 # Extended economic recovery / tech research window
		5, 10, 14:
			return 18.0 # Post-Climax repair window
		_:
			if wave >= 12:
				return 10.0 # Rapid relentless pressure
			return 14.0     # Standard break

func _generate_procedural_tab_horde(squads_array: Array[Dictionary], budget: int, player_count: int) -> void:
	# 1. Fast Screen
	var screen_count = clampi(int(budget * 0.25 / 2.0), 6, 24)
	var screen_units = []
	for i in range(screen_count):
		screen_units.append(1 if i % 2 == 0 else 0)
	_add_squad(squads_array, screen_units, 1.5, player_count)

	# 2. Main Line & Air Support
	var main_count = clampi(int(budget * 0.40 / 4.0), 4, 16)
	var main_units = []
	for i in range(main_count):
		main_units.append(3 if i % 3 == 0 else 2)
	_add_squad(squads_array, main_units, 3.0, player_count)

	# 3. Nob Siege Vanguard
	var nob_count = clampi(int(budget * 0.35 / 8.0), 2, 10)
	var heavy_units = []
	for i in range(nob_count):
		heavy_units.append(4)
		heavy_units.append(2)
	_add_squad(squads_array, heavy_units, 4.5, player_count)

func _spawn_flanker_raid():
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2.ZERO
	# Spawn from extreme map edge
	var edge_pos = base_pos + Vector2.RIGHT.rotated(randf() * TAU) * 2600.0
	
	for t in [1, 1, 3]:
		enemy_count += 1
		spawn_entity({
			"type": "enemy",
			"name": "Flanker_" + str(enemy_count),
			"enemy_type": t,
			"position": edge_pos + Vector2.RIGHT.rotated(randf() * TAU) * 35.0,
			"is_objective_guard": false,
			"counts_toward_wave": false
		})

func _spawn_tactical_squad(squad: Dictionary):
	var units: Array = squad["units"]
	var citadel = get_tree().get_first_node_in_group("ork_citadel")
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2(500, 500)
	
	var spawn_origin = citadel.global_position if is_instance_valid(citadel) else (base_pos + Vector2(2200, 0))
	var squad_center = spawn_origin + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(20.0, 60.0)

	# Pick lane angle
	var assigned_lane_angle = spawn_lane_angles.pick_random() if not spawn_lane_angles.is_empty() else randf() * TAU
	var citadel_angle = (spawn_origin - base_pos).angle()
	var angle_diff = fposmod(assigned_lane_angle - citadel_angle + PI, TAU) - PI
	
	var waypoints: Array[Vector2] = []
	
	# Only generate intermediate waypoint if lane is significantly on the other side
	if abs(angle_diff) > 0.6:
		var mid_angle = citadel_angle + (angle_diff * 0.5)
		waypoints.append(base_pos + Vector2.RIGHT.rotated(mid_angle) * 2100.0)
		waypoints.append(base_pos + Vector2.RIGHT.rotated(assigned_lane_angle) * 1400.0)
	else:
		# Direct corridor to assigned staging
		waypoints.append(base_pos + Vector2.RIGHT.rotated(assigned_lane_angle) * 1400.0)

	for unit_type in units:
		var final_type = unit_type
		if unit_type == 1 and not has_squig_pit: final_type = 0
		if unit_type == 3 and not has_stormboy_pad: final_type = 2

		enemy_count += 1
		var spawn_pos = squad_center + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(15.0, 45.0)
		
		var enemy_node = spawn_entity({
			"type": "enemy",
			"name": "Enemy_" + str(enemy_count),
			"enemy_type": final_type,
			"position": spawn_pos,
			"is_objective_guard": false,
			"counts_toward_wave": true
		})

		if is_instance_valid(enemy_node):
			enemy_node.march_waypoints = waypoints.duplicate()
			if enemy_node.has_method("_update_nav_target"):
				enemy_node._update_nav_target()

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

@rpc("any_peer", "call_local", "reliable")
func request_call_wave_early():
	# Ensure only host/server executes the state change in multiplayer
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not is_wave_preparing or wave_prep_timer <= 1.0:
		return
	
	# Calculate bounty for time skipped
	var seconds_saved = wave_prep_timer
	var bonus_scrap = int(seconds_saved * 1.5)
	var bonus_req = int(seconds_saved * 0.5)

	add_scrap(bonus_scrap)
	add_requisition(bonus_req)

	# Trigger wave immediately
	wave_prep_timer = 0.0
	is_wave_preparing = false
	_begin_wave_spawning()

	if multiplayer.has_multiplayer_peer():
		rpc("trigger_wave_alert_sfx")
	else:
		trigger_wave_alert_sfx()

func _spawn_stc_vaults():
	var base_node = get_tree().get_first_node_in_group("base")
	var base_pos = base_node.global_position if base_node else Vector2(500, 500)

	for i in range(2):
		var angle = (float(i) * PI) + randf_range(0.4, 1.2)
		var vault_pos = base_pos + Vector2.RIGHT.rotated(angle) * randf_range(1600.0, 2200.0)

		spawn_entity({
			"type": "stc_vault",
			"name": "STCVault_" + str(i + 1),
			"position": vault_pos.snapped(Vector2(32, 32)),
			"relic_id": i
		})

		# Spawn guardian feral warband around the vault
		for g in range(5):
			spawn_entity({
				"type": "enemy",
				"name": "VaultGuard_" + str(randi()),
				"enemy_type": 2 if g % 2 == 0 else 0, # Ork Boyz & Gretchin
				"position": vault_pos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 85.0),
				"is_objective_guard": true,
				"guard_anchor": vault_pos,
				"counts_toward_wave": false
			})

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

func notify_satellite_destroyed(sub_type: String):
	match sub_type:
		"squig_pit":
			has_squig_pit = false
			_announce_tactical_update("🔥 SQUIG BREEDING PITS DESTROYED — SQUIG WAVES DISABLED!")
		"stormboy_pad":
			has_stormboy_pad = false
			_announce_tactical_update("🔥 STORMBOY LAUNCHPAD CRUSHED — AIR JUMP RAIDS OFFLINE!")
		"mek_foundry":
			has_mek_foundry = false
			_announce_tactical_update("🔥 MEKBOY FOUNDRY DESTROYED — ENEMY WAVE SIZES REDUCED!")

	# Calculate remaining satellite camps (0, 1, 2, or 3)
	var remaining_outposts = int(has_squig_pit) + int(has_stormboy_pad) + int(has_mek_foundry)
	
	var cit = get_tree().get_first_node_in_group("ork_citadel")
	if is_instance_valid(cit) and cit.has_method("update_shield_state"):
		cit.update_shield_state(remaining_outposts)

	if remaining_outposts == 0:
		_announce_tactical_update("⚡ KUSTOM FORCE FIELD COLLAPSED — ORK CITADEL IS NOW VULNERABLE! ⚡")
		AudioManager.play_sfx("orbital_strike", Vector2.ZERO, 3.0, 0.8)
	else:
		_announce_tactical_update("⚠️ CITADEL SHIELD WEAKENED (%d/3 OUTPOSTS REMAINING)" % remaining_outposts)

func notify_citadel_destroyed():
	# If Warboss hasn't spawned yet, spawn him for the final climactic duel
	if not is_warboss_spawned:
		is_warboss_spawned = true
		_announce_tactical_update("💀 CITADEL BREACHED! MEGA-ARMORED WARBOSS HAS AWAKENED!")
		
		var cit = get_tree().get_first_node_in_group("ork_citadel")
		var boss_pos = cit.global_position if is_instance_valid(cit) else Vector2(1500, 1500)
		
		spawn_entity({
			"type": "enemy",
			"name": "Mega_Warboss",
			"enemy_type": 5, # WARBOSS
			"position": boss_pos,
			"counts_toward_wave": false
		})
	else:
		# Warboss already dead -> Victory!
		game_over(true)

func _announce_tactical_update(text_msg: String):
	AudioManager.play_sfx("klaxon_alert", Vector2.ZERO, 2.0, 1.3)
	# Display popup across all player screens
	for p in get_tree().get_nodes_in_group("players"):
		var label = Label.new()
		label.script = load("res://DamageNumber.gd")
		label.global_position = p.global_position + Vector2(-120, -55)
		get_parent().add_child(label)
		label.text = text_msg
		label.label_settings = LabelSettings.new()
		label.label_settings.font_color = Color(1.0, 0.85, 0.2)
		label.label_settings.font_size = 14

func notify_enemy_defeated():
	if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
		active_enemies = max(0, active_enemies - 1)
		
		# IMMEDIATELY REFRESH HUD SO TOP BAR TICKS DOWN IN REAL TIME
		_broadcast_wave_hud()

		if enemies_left_to_spawn <= 0 and active_enemies == 0 and is_wave_active:
			is_wave_active = false
			if multiplayer.has_multiplayer_peer():
				rpc("sync_incoming_threat_lanes", [])
			else:
				sync_incoming_threat_lanes([])
			
			# Wave Clear Resource Bounty
			var wave_scrap_bounty = 20 + (current_wave * 6)
			var wave_req_bounty = 6 + (current_wave * 2)
			add_scrap(wave_scrap_bounty)
			add_requisition(wave_req_bounty)

			# Start Break Countdown
			var break_duration = _get_wave_break_duration(current_wave)
			wave_break_timer = break_duration
			is_on_wave_break = true
			_broadcast_wave_hud()

func _build_spawn_lanes(wave: int, player_count: int) -> Array[float]:
	var lanes: Array[float] = []
	var primary_angle: float = randf() * TAU
	
	if wave == 15 or wave == max_waves:
		# FINAL CATACLYSM: 4-Way Compass Siege (North, East, South, West)
		for i in range(4):
			lanes.append(fmod(primary_angle + (float(i) * (TAU / 4.0)), TAU))
	elif wave in [10, 12, 14]:
		# 3-Front Pincer Convergence
		for i in range(3):
			lanes.append(fmod(primary_angle + (float(i) * (TAU / 3.0)) + randf_range(-0.2, 0.2), TAU))
	elif wave in [4, 7, 8, 9, 13]:
		# 2-Front Flank Assault
		lanes.append(primary_angle)
		lanes.append(fmod(primary_angle + PI + randf_range(-0.4, 0.4), TAU))
	else:
		# Single-Front Concentrated Push
		lanes.append(primary_angle)

	return lanes

func _build_wave_squads(wave: int, player_count: int) -> Array[Dictionary]:
	var squads: Array[Dictionary] = []
	
	# TAB Co-Op Multiplier (Base 1.0x -> 2P: 1.65x -> 3P: 2.3x -> 4P: 2.95x)
	var co_op_mult: float = 1.0 + 0.65 * max(0, player_count - 1)
	
	# Exponential TAB Threat Budget
	var threat_budget: int = int(round((20.0 + pow(wave, 1.45) * 8.5) * co_op_mult))
	
	match wave:
		# --- TIER 1: EARLY PROBING (Waves 1-4) ---
		1: # Probing Gretchin Line
			_add_squad(squads, [0, 0, 0, 0], 2.0, player_count)
			_add_squad(squads, [0, 0, 0, 0, 0], 3.0, player_count)

		2: # Squig Vanguard + Boyz
			_add_squad(squads, [1, 1, 1], 1.5, player_count)          # Vanguard screen
			_add_squad(squads, [0, 0, 0, 0, 1, 1], 3.0, player_count) # Main push

		3: # Heavy Choppa Boyz Introduction
			_add_squad(squads, [1, 1, 1, 0, 0], 2.0, player_count)
			_add_squad(squads, [2, 2, 0, 0], 3.5, player_count)       # First armored line

		4: # [BREATHER WAVE] - High Scrap Swarm
			_add_squad(squads, [0, 0, 0, 0, 0, 0, 0], 1.8, player_count)
			_add_squad(squads, [1, 1, 1, 1, 0, 0], 2.5, player_count)

		# --- TIER 2: SPECIALIZED TACTICAL INCURSIONS (Waves 5-9) ---
		5: # [CLIMAX 1] Stormboy Airborne Blitz (Bypasses frontline chokes)
			_add_squad(squads, [1, 1, 1, 1], 1.5, player_count)
			_add_squad(squads, [3, 3, 3], 2.0, player_count)          # Stormboy air team 1
			_add_squad(squads, [3, 3, 3, 2, 2], 3.5, player_count)    # Stormboy air team 2 + Shootas

		6: # Stikkbomb Artillery & Line Screen
			_add_squad(squads, [0, 0, 0, 0, 0, 0], 1.5, player_count)
			_add_squad(squads, [2, 2, 2, 2], 3.0, player_count)
			_add_squad(squads, [2, 2, 1, 1, 1], 4.0, player_count)

		7: # First Nob Breachers (Fortress Cracking Test)
			_add_squad(squads, [1, 1, 1, 1, 1], 1.5, player_count)
			_add_squad(squads, [4, 2, 2, 0, 0], 3.5, player_count)    # Nob + Escort
			_add_squad(squads, [4, 3, 3, 1], 4.5, player_count)       # Nob + Stormboy flank

		8: # [BREATHER WAVE] - Fast Pincer Harass
			_add_squad(squads, [1, 1, 1, 1, 1, 1], 1.5, player_count)
			_add_squad(squads, [0, 0, 0, 0, 0, 0, 0, 0], 2.5, player_count)
			_add_squad(squads, [2, 2, 2, 2], 3.5, player_count)

		9: # Combined Arms Siege Push
			_add_squad(squads, [1, 1, 1, 1, 0, 0], 1.5, player_count)
			_add_squad(squads, [3, 3, 3, 3], 2.5, player_count)
			_add_squad(squads, [4, 4, 2, 2], 4.0, player_count)       # Double Nob Breaker line

		# --- TIER 3: LATE-GAME MEGA HORDE (Waves 10-15) ---
		10: # [CLIMAX 2] Armored Warband Convergence
			_add_squad(squads, [1, 1, 1, 1, 1, 1], 1.5, player_count) # Fast screen
			_add_squad(squads, [3, 3, 3, 3, 3], 2.5, player_count)    # Air drop
			_add_squad(squads, [4, 4, 2, 2, 2], 4.0, player_count)    # Nob Heavy Vanguard
			_add_squad(squads, [4, 4, 4, 2, 2], 5.5, player_count)    # Nob Breacher Main

		11: # [BREATHER WAVE] - High Volume Scrap Bounty
			_add_squad(squads, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 1.5, player_count)
			_add_squad(squads, [1, 1, 1, 1, 1, 1, 1, 1], 2.5, player_count)
			_add_squad(squads, [2, 2, 2, 2, 2, 2], 3.5, player_count)

		12: # Heavy Air Blitz & Breachers
			_add_squad(squads, [3, 3, 3, 3, 3, 3], 2.0, player_count)
			_add_squad(squads, [4, 4, 4, 2, 2], 3.5, player_count)
			_add_squad(squads, [4, 4, 3, 3, 1, 1], 4.5, player_count)

		13: # 3-Front Overwhelm Assault
			_add_squad(squads, [1, 1, 1, 1, 1, 1, 1, 1], 1.5, player_count)
			_add_squad(squads, [4, 4, 2, 2, 2, 2], 3.0, player_count)
			_add_squad(squads, [3, 3, 3, 3, 3, 3], 4.0, player_count)
			_add_squad(squads, [4, 4, 4, 4, 2, 2], 5.5, player_count)

		14: # Citadel Vanguard Siege
			_add_squad(squads, [0, 0, 0, 0, 1, 1, 1, 1, 1, 1], 1.5, player_count)
			_add_squad(squads, [3, 3, 3, 3, 3, 3, 3], 2.5, player_count)
			_add_squad(squads, [4, 4, 4, 4, 2, 2, 2], 4.0, player_count)
			_add_squad(squads, [4, 4, 4, 4, 4, 2, 2], 5.5, player_count)

		15: # [THE FINAL WAAAGH! - TOTAL CATACLYSM]
			# Echelon 1: The Flood Screen
			_add_squad(squads, [1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0], 1.5, player_count)
			# Echelon 2: Sky Incursion (Jump Troops to distract turrets)
			_add_squad(squads, [3, 3, 3, 3, 3, 3, 3, 3], 2.5, player_count)
			# Echelon 3: Armored Nob Citadel Breakers
			_add_squad(squads, [4, 4, 4, 4, 4, 2, 2, 2, 2], 4.0, player_count)
			# Echelon 4: Heavy Ranged Bombardment Line
			_add_squad(squads, [2, 2, 2, 2, 2, 2, 2, 2], 5.0, player_count)
			# Echelon 5: The Final Warlord Hammer
			_add_squad(squads, [4, 4, 4, 4, 4, 4, 3, 3, 3], 6.5, player_count)

		_: # Procedural Fallback scaling beyond Wave 15 (Endless / Sandbox)
			_generate_procedural_tab_horde(squads, threat_budget, player_count)

	return squads

func _add_squad(squads_array: Array[Dictionary], base_units: Array, delay: float, player_count: int = 1) -> void:
	var final_units = base_units.duplicate()
	
	# Add extra screening/line units per additional player
	if player_count > 1:
		var bonus_count = int(base_units.size() * 0.45 * (player_count - 1))
		for i in range(bonus_count):
			final_units.append(base_units[i % base_units.size()])
			
	squads_array.append({
		"units": final_units,
		"delay": delay
	})
	
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
	
	var min_dist = 1100.0 + (current_wave * 45.0)
	var max_dist = 1450.0 + (current_wave * 55.0)
	var spawn_distance = randf_range(min_dist, max_dist)
	var camp_pos = center + Vector2.RIGHT.rotated(randf() * TAU) * spawn_distance

	spawn_entity({
		"type": "waaagh_idol",
		"name": "WaaaghIdol_" + str(objective_count),
		"position": camp_pos
	})

	# Spawn guarding retinue around the idol
	for i in range(6):
		spawn_entity({
			"type": "enemy",
			"name": "IdolGuard_" + str(randi()),
			"enemy_type": 0 if i % 2 == 0 else 1,
			"position": camp_pos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 100.0),
			"is_objective_guard": true,
			"guard_anchor": camp_pos,
			"counts_toward_wave": false
		})

func notify_totem_destroyed():
	_broadcast_wave_hud()

func get_active_totem_count() -> int:
	return get_tree().get_nodes_in_group("waaagh_totems").size()

func _broadcast_wave_hud():
	var title = WAVE_NARRATIVE_TITLES[clampi(current_wave - 1, 0, WAVE_NARRATIVE_TITLES.size() - 1)]
	var contacts_remaining = active_enemies + enemies_left_to_spawn

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc("sync_wave_telemetry",
			current_wave, max_waves, title, 
			is_wave_preparing, wave_prep_timer,
			is_on_wave_break, wave_break_timer,
			contacts_remaining, total_wave_enemies_cached
		)
	else:
		sync_wave_telemetry(
			current_wave, max_waves, title, 
			is_wave_preparing, wave_prep_timer,
			is_on_wave_break, wave_break_timer,
			contacts_remaining, total_wave_enemies_cached
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
		1: tech_nanobots_unlocked = true
		2: tech_magnet_unlocked = true
		3: tech_electro_barricades_unlocked = true
		4: tech_spikes_cover_unlocked = true
		5: tech_targeting_uplink_unlocked = true
		6: tech_lasers_unlocked = true        # STC Vault 1: Cutting Lasers
		7: stc_aegis_core_unlocked = true      # STC Vault 2: Master Aegis Core
		
	if multiplayer.has_multiplayer_peer():
		rpc("sync_tech_tree", tech_shields_unlocked, tech_nanobots_unlocked, tech_magnet_unlocked, tech_electro_barricades_unlocked, tech_spikes_cover_unlocked, tech_targeting_uplink_unlocked, tech_lasers_unlocked, stc_aegis_core_unlocked)
	else:
		sync_tech_tree(tech_shields_unlocked, tech_nanobots_unlocked, tech_magnet_unlocked, tech_electro_barricades_unlocked, tech_spikes_cover_unlocked, tech_targeting_uplink_unlocked, tech_lasers_unlocked, stc_aegis_core_unlocked)

@rpc("call_local", "reliable")
func sync_tech_tree(
	shields: bool = false, 
	nanobots: bool = false, 
	magnet: bool = false, 
	electro_walls: bool = false, 
	spikes_cover: bool = false, 
	targeting: bool = false, 
	lasers: bool = false, 
	stc_core: bool = false
):
	tech_shields_unlocked = shields
	tech_nanobots_unlocked = nanobots
	tech_magnet_unlocked = magnet
	tech_electro_barricades_unlocked = electro_walls
	tech_spikes_cover_unlocked = spikes_cover
	tech_targeting_uplink_unlocked = targeting
	tech_lasers_unlocked = lasers
	stc_aegis_core_unlocked = stc_core
	get_tree().call_group("buildings", "_apply_tech_stats")
	get_tree().call_group("research_ui", "refresh_tech_cards")

@rpc("any_peer", "call_local", "reliable")
func request_build_structure(build_pos: Vector2, building_type: int = 0):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server(): return
	var info = GameData.STRUCTURE_INFO.get(building_type, null)
	if not info: return

	var scrap_c = info["scrap"]
	var req_c = info["req"]

	var requires_dep = info.get("requires_deposit", false)
	var deposits = get_tree().get_nodes_in_group("scrap_deposits")
	
	if requires_dep:
		var has_valid_dep = false
		for dep in deposits:
			if is_instance_valid(dep) and dep.global_position.distance_to(build_pos) < 32.0:
				has_valid_dep = true
				break
		if not has_valid_dep: return
	else:
		for dep in deposits:
			if is_instance_valid(dep) and dep.global_position.distance_to(build_pos) < 42.0:
				return

	if scrap_amount >= scrap_c and requisition_amount >= req_c:
		scrap_amount -= scrap_c
		requisition_amount -= req_c
		if multiplayer.has_multiplayer_peer():
			rpc("sync_resources", scrap_amount, requisition_amount)
		
		building_count += 1
		spawn_entity({
			"type": "building",
			"name": "Building_" + str(building_count),
			"position": build_pos,
			"building_type": building_type
		})
		
		if building_type == 0:
			Building.rebuild_all_barricade_connections(get_tree())
		request_navmesh_rebake()

func request_navmesh_rebake():
	call_deferred("_setup_and_bake_navmesh")

func _setup_and_bake_navmesh() -> void:
	if not is_instance_valid(nav_region):
		nav_region = get_node_or_null("NavigationRegion2D")
		if not nav_region: return

	var base_node = get_tree().get_first_node_in_group("base")
	var center = base_node.global_position if is_instance_valid(base_node) else Vector2(500, 500)

	# 1. Create a massive 7000x7000 navigation polygon centered on the map
	var nav_poly = NavigationPolygon.new()
	var half_size = 3600.0
	var outline = PackedVector2Array([
		center + Vector2(-half_size, -half_size),
		center + Vector2(half_size, -half_size),
		center + Vector2(half_size, half_size),
		center + Vector2(-half_size, half_size)
	])
	nav_poly.add_outline(outline)
	nav_poly.agent_radius = 18.0
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	
	# Parse entire scene tree for world obstacles & structures
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_poly.source_geometry_group_name = &"world_obstacles" # <-- Fixed property name

	nav_poly.make_polygons_from_outlines()
	nav_region.navigation_polygon = nav_poly

	# 2. Bake navigation mesh with colliders
	nav_region.bake_navigation_polygon(false)

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
	var t_hud = get_tree().get_first_node_in_group("tutorial_hud")
	if t_hud: t_hud.hide()

	var p_ui = get_tree().get_first_node_in_group("pause_menu")
	if p_ui: p_ui.hide()

	_show_game_over_screen(is_victory)

func _show_game_over_screen(is_victory: bool):
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
	var go_ui = get_node_or_null("%GameOverUI")
	if not go_ui and has_node("UI/GameOverUI"):
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
				sub_lbl.text = "The facility successfully withstood all %d waves." % max_waves
		else:
			if title_lbl:
				title_lbl.text = "◆ CRITICAL SYSTEM FAILURE — DEFEAT ◆"
				title_lbl.add_theme_color_override("font_color", Color(0.92, 0.22, 0.18))
			if sub_lbl:
				sub_lbl.text = "Core breach on Wave %d. Press [ESC] or Restart below." % current_wave

		if bg_draw:
			bg_draw.set("is_victory_screen", is_victory)
			bg_draw.queue_redraw()

		var restart_btn = go_ui.get_node_or_null("%RestartButton")
		if restart_btn and not restart_btn.pressed.is_connected(_on_restart_pressed):
			restart_btn.pressed.connect(_on_restart_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# If Game Over screen is active, allow ESC to return to title
		var go_ui = get_node_or_null("%GameOverUI")
		if not go_ui and has_node("UI/GameOverUI"): go_ui = $UI/GameOverUI
		if go_ui and go_ui.visible and event.keycode == KEY_ESCAPE:
			_on_restart_pressed()
			get_viewport().set_input_as_handled()

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
	
	get_tree().call_group("minimap_ui", "reset_minimap_state")
	get_tree().call_group("fog_of_war", "reset_fog")
	get_tree().call_group("tutorial_hud", "reset_tutorial")
	
	var go_ui = get_node_or_null("%GameOverUI")
	if not go_ui and has_node("UI/GameOverUI"): go_ui = $UI/GameOverUI
	if go_ui: go_ui.hide()

	var p_ui = get_tree().get_first_node_in_group("pause_menu")
	if p_ui: p_ui.hide()

	var a_hud = get_tree().get_first_node_in_group("ability_hud")
	if a_hud: a_hud.hide()

	var w_hud = get_tree().get_first_node_in_group("wave_hud")
	if w_hud: w_hud.hide()

	current_wave = 0
	active_enemies = 0
	enemies_left_to_spawn = 0
	is_wave_active = false
	is_wave_preparing = false
	scrap_amount = 75
	requisition_amount = 20
	building_count = 0
	base_radar_level = 0
	tech_waaagh_reader_unlocked = false
	
	tech_shields_unlocked = false
	tech_lasers_unlocked = false
	tech_nanobots_unlocked = false
	tech_magnet_unlocked = false
	tech_electro_barricades_unlocked = false
	tech_spikes_cover_unlocked = false
	tech_targeting_uplink_unlocked = false

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
		for obs in get_tree().get_nodes_in_group("world_obstacles"): obs.queue_free()

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

	if is_instance_valid(base_auto_builder_node):
		base_auto_builder_node.queue_free()
		base_auto_builder_node = null

	_show_title_screen()

# ==============================================================================
# 7. INNER CLASSES
# ==============================================================================
class ClassPreviewPedestal extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0, Vector2(1.0, 0.45))
		draw_circle(Vector2(0, 10), 16.0, Color(0.03, 0.05, 0.08, 0.95))
		draw_arc(Vector2(0, 10), 16.0, 0, TAU, 24, Color(0.82, 0.62, 0.24, 0.65), 1.2)
		draw_arc(Vector2(0, 10), 11.0, 0, TAU, 16, Color(0.20, 0.88, 1.0, 0.45), 1.0)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

class STCVault extends StaticBody2D:
	var relic_id: int = 0
	var is_cleansed: bool = false

	func _ready() -> void:
		add_to_group("objectives")
		add_to_group("stc_vaults")
		
		var col = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 32.0
		col.shape = shape
		add_child(col)

	func interact_relic(_player_node: Node2D) -> void:
		if is_cleansed: return
		is_cleansed = true
		AudioManager.play_sfx("volkite_beam", global_position, 3.0, 1.2)
		
		var main_node = get_tree().get_first_node_in_group("main")
		if main_node:
			if relic_id == 0:
				main_node.unlock_tech(6) # Unlocks Cutting Lasers (ID 6)
				main_node._announce_tactical_update("⚡ STC RECOVERED: COGNIS THERMAL LASER ARRAYS ONLINE!")
			else:
				main_node.unlock_tech(7) # Unlocks Master Aegis Core (ID 7)
				main_node._announce_tactical_update("⚡ STC RECOVERED: MASTER AEGIS FORTRESS CORE ONLINE (+75 WALL HP)!")
		queue_redraw()

	func _draw() -> void:
		var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.005) * 0.3
		var col = Color(0.20, 0.88, 1.0, 0.9 * pulse) if not is_cleansed else Color(0.35, 0.95, 0.45)
		
		# Ancient Sanctified Plinth
		draw_rect(Rect2(-24, -24, 48, 48), Color(0.08, 0.10, 0.14), true)
		draw_rect(Rect2(-24, -24, 48, 48), col, false, 2.0)
		draw_circle(Vector2.ZERO, 12.0, col)
		draw_arc(Vector2.ZERO, 20.0, 0, TAU, 16, col, 1.2)
		
		# Floating Hologram Prompt if unclaimed
		if not is_cleansed:
			var font = ThemeDB.fallback_font
			draw_string(font, Vector2(-36, -32), "[E] CLAIM STC", HORIZONTAL_ALIGNMENT_CENTER, 72, 8, Color(0.20, 0.88, 1.0))


class OrkSatelliteCamp extends StaticBody2D:
	var sub_type: String = "squig_pit"
	var max_health: int = 400
	var current_health: int = 400

	func _ready() -> void:
		add_to_group("enemies")
		add_to_group("ork_structures")
		
		var col = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 32.0
		col.shape = shape
		add_child(col)

	func take_damage(amount: int, _knockback = Vector2.ZERO) -> void:
		current_health -= amount
		if current_health <= 0:
			var main_node = get_tree().get_first_node_in_group("main")
			if main_node and main_node.has_method("notify_satellite_destroyed"):
				main_node.notify_satellite_destroyed(sub_type)
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var hp_ratio = float(current_health) / float(max_health)
		draw_rect(Rect2(-28, -28, 56, 56), Color(0.22, 0.16, 0.12), true)
		draw_rect(Rect2(-28, -28, 56, 56), Color(1.0, 0.3, 0.2), false, 2.0)
		# Health fill indicator
		draw_rect(Rect2(-24, -36, 48 * hp_ratio, 6), Color(0.9, 0.2, 0.2))
