extends Control
class_name ResearchUI

# Tech Definitions: Title, Cost, Description, Icon/Rune
const TECH_DATA = [
	{
		"id": 0,
		"name": "Aegis Refractor Shields",
		"cost": 20,
		"rune": "🛡️",
		"desc": "Generates a regenerating blue energy shield (40% max HP) on all structures connected to the Noosphere. Recharges after 6s out of combat."
	},
	{
		"id": 1,
		"name": "Cognis Laser Arrays",
		"cost": 30,
		"rune": "⚡",
		"desc": "Connected Turrets emit a continuous 40 DPS cutting laser at priority targets in addition to standard munitions."
	},
	{
		"id": 2,
		"name": "Necro-Mechanic Nanobots",
		"cost": 40,
		"rune": "🔧",
		"desc": "Sacred nanobot swarms slowly self-repair (3.5 HP/sec) all damaged Noosphere structures when out of combat."
	}
]

var panel_container: PanelContainer = null
var cards_container: HBoxContainer = null
var active_shrine_node: Node2D = null

# Cache state so we only refresh when numbers actually change
var last_cached_req: int = -1
var last_cached_unlocks: Array = []

func _ready():
	add_to_group("research_ui")
	theme = AdmechTheme.make()
	hide()
	_build_ui_layout()

func _build_ui_layout():
	# 1. Fullscreen Root
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 2. Semi-Transparent Tactical Dark Backdrop
	var backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.65)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(backdrop)

	# 3. CenterContainer guarantees screen centering
	var center_container = CenterContainer.new()
	center_container.name = "CenterContainer"
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center_container)

	# 4. Main Tech-Vault Panel
	var pc = PanelContainer.new()
	pc.name = "PanelContainer"
	pc.custom_minimum_size = Vector2(740, 360)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	center_container.add_child(pc)
	panel_container = pc

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 14)
	panel_container.add_child(vbox)

	# Title Header
	var title = Label.new()
	title.name = "Title"
	title.text = "◆ ARCHIVES OF THE OMNISSIAH — TECH RESEARCH ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# Cards Container
	var hbox = HBoxContainer.new()
	hbox.name = "CardsHBox"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)
	cards_container = hbox

	# Close Button
	var close = Button.new()
	close.name = "CloseButton"
	close.text = "CLOSE TERMINAL [ESC / E]"
	close.custom_minimum_size = Vector2(220, 34)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_terminal)
	vbox.add_child(close)

func open_terminal(shrine_node: Node2D):
	active_shrine_node = shrine_node
	last_cached_req = -1
	show()
	refresh_tech_cards()

func close_terminal():
	hide()
	active_shrine_node = null

func _process(_delta: float):
	if visible:
		# Auto-close if player walks away from the shrine
		var local_player = _get_local_player()
		if not is_instance_valid(active_shrine_node) or not is_instance_valid(local_player) or local_player.global_position.distance_to(active_shrine_node.global_position) > 130.0:
			close_terminal()
			return

		# ONLY refresh when Requisition or Unlocks change, NEVER every frame!
		var main_node = get_tree().get_first_node_in_group("main")
		var current_req = main_node.requisition_amount if main_node else 0
		var current_unlocks = [
			main_node.get("tech_shields_unlocked") if main_node else false,
			main_node.get("tech_lasers_unlocked") if main_node else false,
			main_node.get("tech_nanobots_unlocked") if main_node else false
		]

		if current_req != last_cached_req or current_unlocks != last_cached_unlocks:
			last_cached_req = current_req
			last_cached_unlocks = current_unlocks
			refresh_tech_cards()

func _get_local_player() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and ((not multiplayer.has_multiplayer_peer()) or p.is_multiplayer_authority()):
			return p
	return null

func refresh_tech_cards():
	if not visible or cards_container == null: 
		return

	var main_node = get_tree().get_first_node_in_group("main")
	var current_req = main_node.requisition_amount if main_node else 0
	var unlocks = [
		main_node.get("tech_shields_unlocked") if main_node else false,
		main_node.get("tech_lasers_unlocked") if main_node else false,
		main_node.get("tech_nanobots_unlocked") if main_node else false
	]

	# Clear previous cards
	for child in cards_container.get_children():
		child.queue_free()

	# Rebuild fresh cards
	for tech in TECH_DATA:
		var card = _create_tech_card(tech, unlocks[tech.id], current_req)
		cards_container.add_child(card)

func _create_tech_card(tech: Dictionary, is_unlocked: bool, current_req: int) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(210, 240)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# 1. Header with Rune
	var header = Label.new()
	header.text = tech.rune + " " + tech.name
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4) if is_unlocked else Color(0.20, 0.88, 1.0))
	vbox.add_child(header)

	# 2. Cost / Status Badge
	var cost_lbl = Label.new()
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_unlocked:
		cost_lbl.text = "◆ RESEARCHED ◆"
		cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
	else:
		cost_lbl.text = "⚡ " + str(tech.cost) + " REQUISITION"
		var can_afford = current_req >= tech.cost
		cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7) if can_afford else Color(0.9, 0.25, 0.2))
	vbox.add_child(cost_lbl)

	# 3. Description
	var desc = Label.new()
	desc.text = tech.desc
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	desc.add_theme_font_size_override("font_size", 11)
	vbox.add_child(desc)

	# 4. Action Button
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 32)
	if is_unlocked:
		btn.text = "ACTIVE"
		btn.disabled = true
	else:
		btn.text = "RESEARCH"
		btn.disabled = (current_req < tech.cost)
		btn.pressed.connect(func(): _on_research_pressed(tech.id))
	vbox.add_child(btn)

	return card

func _on_research_pressed(tech_id: int):
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and is_instance_valid(active_shrine_node):
		main_node.rpc_id(1, "request_purchase_research", active_shrine_node.name, tech_id)
