extends Control

@onready var ability_container: HBoxContainer = get_node_or_null("HBoxContainer")

@onready var slot1_panel = get_node_or_null("HBoxContainer/Slot1")
@onready var slot2_panel = get_node_or_null("HBoxContainer/Slot2")
@onready var slot3_panel = get_node_or_null("HBoxContainer/Slot3")
@onready var slot4_panel = get_node_or_null("HBoxContainer/Slot4")
@onready var slot5_panel = get_node_or_null("HBoxContainer/Slot5")
@onready var slot6_panel = get_node_or_null("HBoxContainer/Slot6")

var local_player: Node2D = null
var update_accumulator: float = 0.0
const UPDATE_INTERVAL: float = 0.08

const COLOR_BG := Color(0.06, 0.07, 0.09, 0.94)
const COLOR_BRASS := Color(0.78, 0.58, 0.22)
const COLOR_BRASS_DIM := Color(0.38, 0.28, 0.12)
const COLOR_CYAN := Color(0.20, 0.88, 1.0)
const COLOR_GOLD := Color(0.95, 0.75, 0.20)
const COLOR_RED_ALERT := Color(0.90, 0.25, 0.20)
const COLOR_DISABLED := Color(0.45, 0.48, 0.52)

func _ready():
	add_to_group("ability_hud")
	set_process(true)
	_setup_slot_containers()

func _setup_slot_containers():
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if is_instance_valid(ability_container):
		ability_container.alignment = BoxContainer.ALIGNMENT_CENTER
		ability_container.add_theme_constant_override("separation", 10)
		ability_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)

	var slots = [slot1_panel, slot2_panel, slot3_panel, slot4_panel, slot5_panel, slot6_panel]
	for slot in slots:
		if slot is PanelContainer or slot is Panel:
			slot.custom_minimum_size = Vector2(105, 66)

func _process(delta):
	if not is_instance_valid(local_player):
		_find_local_player()
		if not is_instance_valid(local_player):
			hide()
			return

	update_accumulator += delta
	if update_accumulator >= UPDATE_INTERVAL:
		update_accumulator = 0.0
		refresh_hud_display()

func _find_local_player():
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p):
			if (not multiplayer.has_multiplayer_peer()) or p.is_multiplayer_authority():
				setup_hud_for_player(p)
				return

func setup_hud_for_player(player_node: Node2D):
	local_player = player_node
	show()
	refresh_hud_display()

func _format_slot(panel: Node, key_txt: String, name_txt: String, cost_scrap: int, cost_req: int, current_scrap: int, current_req: int, is_selected: bool, is_maxed: bool = false, cooldown_remaining: float = 0.0):
	if not panel: return
	
	var key_lbl = panel.find_child("KeyLabel", true, false) as Label
	var name_lbl = panel.find_child("NameLabel", true, false) as Label
	var cost_lbl = panel.find_child("CostLabel", true, false) as Label

	var on_cooldown = (cooldown_remaining > 0.0)

	if key_lbl:
		key_lbl.text = " " + key_txt + " "
		if on_cooldown or is_maxed:
			key_lbl.add_theme_color_override("font_color", COLOR_DISABLED)
		else:
			key_lbl.add_theme_color_override("font_color", COLOR_CYAN if is_selected else Color(0.95, 0.95, 0.95))

	if name_lbl:
		name_lbl.text = name_txt
		if on_cooldown or is_maxed:
			name_lbl.add_theme_color_override("font_color", COLOR_DISABLED)
		else:
			name_lbl.add_theme_color_override("font_color", Color.WHITE)

	if cost_lbl:
		if on_cooldown:
			var time_txt = ("%.1f" % cooldown_remaining) if cooldown_remaining < 10.0 else str(int(ceil(cooldown_remaining)))
			cost_lbl.text = "⏳ " + time_txt + "s"
			cost_lbl.add_theme_color_override("font_color", COLOR_GOLD)
		elif is_maxed:
			cost_lbl.text = "◆ MAXED ◆"
			cost_lbl.add_theme_color_override("font_color", COLOR_DISABLED)
		elif cost_scrap == 0 and cost_req == 0:
			cost_lbl.text = "READY"
			cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		else:
			var parts: Array[String] = []
			if cost_scrap > 0: parts.append("⚙ " + str(cost_scrap))
			if cost_req > 0: parts.append("⚡ " + str(cost_req))
			cost_lbl.text = "  ".join(parts)

			var can_afford = (current_scrap >= cost_scrap and current_req >= cost_req)
			cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7) if can_afford else COLOR_RED_ALERT)

	var can_afford_total = (current_scrap >= cost_scrap and current_req >= cost_req) or is_selected
	if on_cooldown or is_maxed:
		panel.modulate = Color(0.50, 0.52, 0.56, 0.75)
		panel.scale = Vector2.ONE
	elif is_selected:
		var pulse = 0.85 + sin(Time.get_ticks_msec() * 0.008) * 0.15
		panel.modulate = Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, pulse)
		panel.scale = Vector2(1.04, 1.04)
	elif can_afford_total:
		panel.modulate = Color.WHITE
		panel.scale = Vector2.ONE
	else:
		panel.modulate = Color(0.60, 0.64, 0.70, 0.85)
		panel.scale = Vector2.ONE

func refresh_hud_display():
	if not is_instance_valid(local_player): return
	show()

	var main_node = get_tree().get_first_node_in_group("main")
	var current_req = 0
	var current_scrap = 0
	
	if main_node:
		if "requisition_amount" in main_node: current_req = main_node.requisition_amount
		if "scrap_amount" in main_node: current_scrap = main_node.scrap_amount

	var is_techpriest = (local_player.current_class == 0)

	# --- TECH-PRIEST (MELEE & BUILDER) ---
	if is_techpriest:
		var selected_type = local_player.selected_building_type if "selected_building_type" in local_player else 0
		var is_building = local_player.is_building_mode if "is_building_mode" in local_player else false

		# Slot 1: Barricade [1]
		if slot1_panel:
			slot1_panel.show()
			var info = GameData.STRUCTURE_INFO[GameData.StructureType.BARRICADE]
			_format_slot(slot1_panel, "1", info.name, info.scrap, info.req, current_scrap, current_req, is_building and selected_type == 0)

		# Slot 2: Distributor [2]
		if slot2_panel:
			slot2_panel.show()
			var info = GameData.STRUCTURE_INFO[GameData.StructureType.DISTRIBUTOR]
			_format_slot(slot2_panel, "2", info.name, info.scrap, info.req, current_scrap, current_req, is_building and selected_type == 4)

		# Slot 3: Generator [3]
		if slot3_panel:
			slot3_panel.show()
			var info = GameData.STRUCTURE_INFO[GameData.StructureType.GENERATOR]
			_format_slot(slot3_panel, "3", info.name, info.scrap, info.req, current_scrap, current_req, is_building and selected_type == 1)

		# Slot 4: Turret [4]
		if slot4_panel:
			slot4_panel.show()
			var info = GameData.STRUCTURE_INFO[GameData.StructureType.TURRET]
			_format_slot(slot4_panel, "4", info.name, info.scrap, info.req, current_scrap, current_req, is_building and selected_type == 2)

		# Slot 5: Scrap Foundry [5]
		if slot5_panel:
			slot5_panel.show()
			var info = GameData.STRUCTURE_INFO[GameData.StructureType.MANUFACTORUM]
			_format_slot(slot5_panel, "5", info.name, info.scrap, info.req, current_scrap, current_req, is_building and selected_type == 3)

		# Slot 6: Tech Shrine [6]
		if slot6_panel:
			slot6_panel.show()
			var info = GameData.STRUCTURE_INFO[GameData.StructureType.RESEARCH_SHRINE]
			_format_slot(slot6_panel, "6", info.name, info.scrap, info.req, current_scrap, current_req, is_building and selected_type == 6)

	# --- SKITARII MARSHAL (RANGED COMMANDER) ---
	else:
		# Slot 1: Primary Shot
		if slot1_panel:
			slot1_panel.show()
			_format_slot(slot1_panel, "LMB", "Radium Carbine", 0, 0, current_scrap, current_req, false)

		# Slot 2: Doctrina Imperative Stance [SPACE / F]
		if slot2_panel:
			slot2_panel.show()
			var is_conqueror = (local_player.get("active_doctrina") == 0)
			
			if is_conqueror:
				_format_slot(slot2_panel, "SPACE", "CONQUEROR (DPS)", 0, 0, current_scrap, current_req, true)
				var cost_lbl = slot2_panel.find_child("CostLabel", true, false) as Label
				if cost_lbl:
					cost_lbl.text = "+60% SPD / -20% ARM"
					cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.80, 0.20))
			else:
				_format_slot(slot2_panel, "SPACE", "PROTECTOR (ARM)", 0, 0, current_scrap, current_req, true)
				var cost_lbl = slot2_panel.find_child("CostLabel", true, false) as Label
				if cost_lbl:
					cost_lbl.text = "+35% ARM / -15% SPD"
					cost_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))

		# Slot 3: Squad Recruitment [N]
		if slot3_panel:
			slot3_panel.show()
			var current_lvl = local_player.bodyguard_level if "bodyguard_level" in local_player else 0
			var is_maxed = (current_lvl >= GameData.MAX_BODYGUARDS)
			var squad_label = "Squad (" + str(current_lvl) + "/" + str(GameData.MAX_BODYGUARDS) + ")"
			_format_slot(slot3_panel, "N", squad_label, 0, GameData.BODYGUARD_REQ_COST, current_scrap, current_req, false, is_maxed)

		# Slot 4: Weapon DMG Up [M]
		if slot4_panel:
			slot4_panel.show()
			var dmg_lvl = local_player.damage_upgrade_level if "damage_upgrade_level" in local_player else 0
			var is_maxed = (dmg_lvl >= GameData.MAX_DAMAGE_UPGRADES)
			_format_slot(slot4_panel, "M", "DMG Up (" + str(dmg_lvl) + "/" + str(GameData.MAX_DAMAGE_UPGRADES) + ")", 0, GameData.DAMAGE_UPGRADE_REQ_COST, current_scrap, current_req, false, is_maxed)

		# Slot 5: Orbital Lance Strike [X]
		if slot5_panel:
			slot5_panel.show()
			var cd = local_player.get("orbital_strike_cooldown") if "orbital_strike_cooldown" in local_player else 0.0
			_format_slot(slot5_panel, "X", "Orbital Lance", 0, GameData.ORBITAL_REQ_COST, current_scrap, current_req, false, false, cd)

		if slot6_panel: slot6_panel.hide()
