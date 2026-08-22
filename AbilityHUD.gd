extends Control
class_name AbilityHUD

var local_player: Node2D = null
var update_accumulator: float = 0.0
const UPDATE_INTERVAL: float = 0.06

# Theme Colors
const C_BG_DARK     := Color(0.04, 0.05, 0.08, 0.96)
const C_PANEL_EDGE  := Color(0.18, 0.22, 0.28, 0.95)
const C_BRASS       := Color(0.82, 0.62, 0.24)
const C_BRASS_DIM   := Color(0.40, 0.28, 0.10)
const C_CYAN        := Color(0.20, 0.88, 1.00)
const C_AMBER       := Color(1.00, 0.72, 0.15)
const C_RED_ALERT   := Color(0.92, 0.22, 0.18)
const C_GREEN_READY := Color(0.35, 0.95, 0.45)
const C_PARCHMENT   := Color(0.88, 0.84, 0.72)
const C_MUTED       := Color(0.50, 0.54, 0.60)

# Layout Containers
var weapon_buttons: Array[CompactSlot] = []
var action_buttons: Array[CompactSlot] = []
var augment_buttons: Array[CompactSlot] = []

var action_panel: PanelContainer = null
var tooltip_card: TooltipCard = null
var hovered_slot_data: Dictionary = {}

func _ready():
	add_to_group("ability_hud")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hud_layout()
	hide()

func _process(delta: float):
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

# ==============================================================================
# 1. MODULAR 3-POD HUD BUILDER
# ==============================================================================
func _build_hud_layout():
	for c in get_children():
		c.queue_free()

	# 1. Floating Hover Inspection Card
	tooltip_card = TooltipCard.new()
	tooltip_card.name = "TooltipCard"
	tooltip_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tooltip_card)
	tooltip_card.hide()

	# 2. Master Bottom Bar Container
	var main_hbox = HBoxContainer.new()
	main_hbox.name = "MainHUDHBox"
	main_hbox.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	main_hbox.position = Vector2(-360, -74)
	main_hbox.add_theme_constant_override("separation", 10)
	main_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(main_hbox)

	# --- POD A: ARMAMENTS (LMB, RMB, SPACE, R) ---
	var weapon_panel = _create_pod_panel("ArmamentPod", main_hbox)
	var weapon_vbox = VBoxContainer.new()
	weapon_vbox.add_theme_constant_override("separation", 2)
	weapon_panel.add_child(weapon_vbox)

	var w_title = Label.new()
	w_title.text = "ARMAMENTS & ACTIVES"
	w_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w_title.add_theme_font_size_override("font_size", 8)
	w_title.add_theme_color_override("font_color", C_BRASS)
	weapon_vbox.add_child(w_title)

	var weapon_hbox = HBoxContainer.new()
	weapon_hbox.add_theme_constant_override("separation", 4)
	weapon_vbox.add_child(weapon_hbox)

	weapon_buttons.clear()
	for i in range(3):
		var slot = CompactSlot.new("weapon", i)
		slot.custom_minimum_size = Vector2(48, 48)
		slot.mouse_entered.connect(_on_slot_hovered.bind(slot))
		slot.mouse_exited.connect(_on_slot_unhovered)
		weapon_hbox.add_child(slot)
		weapon_buttons.append(slot)

	# --- POD B: TACTICAL FORGE PALETTE ([1] - [6] FOR TECH-PRIEST) ---
	action_panel = _create_pod_panel("ActionPod", main_hbox)
	var action_vbox = VBoxContainer.new()
	action_vbox.add_theme_constant_override("separation", 2)
	action_panel.add_child(action_vbox)

	var a_title = Label.new()
	a_title.text = "TACTICAL FORGE PROTOCOLS"
	a_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a_title.add_theme_font_size_override("font_size", 8)
	a_title.add_theme_color_override("font_color", C_CYAN)
	action_vbox.add_child(a_title)

	var action_hbox = HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 4)
	action_vbox.add_child(action_hbox)

	action_buttons.clear()
	for i in range(6):
		var slot = CompactSlot.new("action", i)
		slot.custom_minimum_size = Vector2(48, 48)
		slot.mouse_entered.connect(_on_slot_hovered.bind(slot))
		slot.mouse_exited.connect(_on_slot_unhovered)
		action_hbox.add_child(slot)
		action_buttons.append(slot)

	# --- POD C: CYBERNETIC BIONICS & AUGMENTATIONS ([Z], [X], [C]) ---
	var augment_panel = _create_pod_panel("AugmentPod", main_hbox)
	var augment_vbox = VBoxContainer.new()
	augment_vbox.add_theme_constant_override("separation", 2)
	augment_panel.add_child(augment_vbox)

	var aug_title = Label.new()
	aug_title.text = "CYBERNETIC BIONICS & COHORT"
	aug_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aug_title.add_theme_font_size_override("font_size", 8)
	aug_title.add_theme_color_override("font_color", C_AMBER)
	augment_vbox.add_child(aug_title)

	var augment_hbox = HBoxContainer.new()
	augment_hbox.add_theme_constant_override("separation", 4)
	augment_vbox.add_child(augment_hbox)

	augment_buttons.clear()
	for i in range(3):
		var slot = CompactSlot.new("augment", i)
		slot.custom_minimum_size = Vector2(48, 48)
		slot.mouse_entered.connect(_on_slot_hovered.bind(slot))
		slot.mouse_exited.connect(_on_slot_unhovered)
		augment_hbox.add_child(slot)
		augment_buttons.append(slot)

func _create_pod_panel(pod_name: String, parent_container: Container) -> PanelContainer:
	var pc = PanelContainer.new()
	pc.name = pod_name
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_BG_DARK
	sb.border_color = C_BRASS_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 4
	pc.add_theme_stylebox_override("panel", sb)
	parent_container.add_child(pc)
	return pc

func _on_slot_hovered(slot: CompactSlot):
	hovered_slot_data = slot.cached_data
	if not hovered_slot_data.is_empty():
		_update_tooltip_position(slot)
		tooltip_card.show()

func _on_slot_unhovered():
	hovered_slot_data.clear()
	if tooltip_card:
		tooltip_card.hide()

# ==============================================================================
# 2. DATA PROVIDER (ERGONOMIC WASD SHORTCUTS & ADMECH CANTICLES)
# ==============================================================================
func _get_data_for_category(category: String, idx: int) -> Dictionary:
	if not is_instance_valid(local_player): return {}
	var is_techpriest = (local_player.current_class == 0)

	match category:
		"weapon":
			if is_techpriest:
				match idx:
					0: return {
						"key": "LMB", "name": "Omnissian Power-Axe", "sub": "Heavy Melee Cleave",
						"icon": "axe", "scrap": 0, "req": 0, "type_id": -1,
						"desc": "Heavy two-handed energized power-axe. Cleaves forward in a wide 130° arc (40 DMG) that penetrates enemy armor and shreds swarms.",
						"flavor": "\"The blade is the voice of the Omnissiah; it speaks in the severance of heretical flesh.\""
					}
					1: return {
						"key": "RMB", "name": "Plasma Caliver", "sub": "Secondary Ranged Weapon",
						"icon": "plasma_pistol", "scrap": 0, "req": 0, "type_id": -1,
						"desc": "Fires a superheated overcharged plasma bolt (30 DMG / 0.65s CD). Instantly snipes and vaporizes fleeing Gretchins and distant Squigs.",
						"flavor": "\"Vaporize the scavenger before its filthy hands defile the sacred scrap.\""
					}
					2: return {} # Empty third slot for Tech-Priest
			else:
				# SKITARII MARSHAL COMBAT ACTIVES
				match idx:
					0: return {
						"key": "LMB", "name": "Radium Serpenta Carbine", "sub": "Primary Ranged Weapon",
						"icon": "gun", "scrap": 0, "req": 0, "type_id": -1,
						"desc": "Rapid-fire irradiated rifle. Fires phosphor-laced munitions that decay the cellular composition of organic targets.",
						"flavor": "\"Breathe deep the holy fallout, and let your flesh be cleansed in phosphor fire.\""
					}
					1:
						var is_conq = (local_player.active_doctrina == 0) if "active_doctrina" in local_player else true
						return {
							"key": "SPACE", "name": "Doctrina: " + ("CONQUEROR (DPS)" if is_conq else "PROTECTOR (ARMOR)"),
							"sub": "Noospheric Stance Shift",
							"icon": "doctrina_conq" if is_conq else "doctrina_prot", "scrap": 0, "req": 0, "type_id": -1,
							"desc": "+60% Movement Speed & +25% Fire Rate / -20% Armor" if is_conq else "+35% Armor & Ranged Resistance / -15% Speed",
							"flavor": "\"The Omnissiah guides our feet as He guides our guns. Upload the sacred canticle.\""
						}
					2: return {
						"key": "R", "name": "Orbital Lance Strike", "sub": "Fleet Telemetry Bombardment",
						"icon": "orbital", "scrap": 0, "req": GameData.ORBITAL_REQ_COST, "type_id": -1,
						"desc": "Calls down a searing orbital lance strike from low-orbit void cruisers directly at your cursor (220 DMG / 45s CD).",
						"flavor": "\"Let the stars themselves descend upon the blasphemer in cleansing fire.\""
					}

		"action":
			if is_techpriest:
				match idx:
					0: return {
						"key": "1", "name": "Aegis Blast Rampart", "sub": "Tactical Fortification",
						"icon": "barricade", "scrap": 15, "req": 0, "type_id": 0,
						"desc": "Heavy sloped ballistic blast wall. Snap-links into continuous defensive ramparts with dragon's teeth spikes. Upgradable to Motorized Gate [E].",
						"flavor": "\"Armor is the iron shroud that preserves the sacred flesh of the faithful.\""
					}
					1: return {
						"key": "2", "name": "Electro-Relay Substation", "sub": "Power & Scrap Distribution",
						"icon": "distributor", "scrap": 20, "req": 0, "type_id": 4,
						"desc": "Extends Noosphere power conduit channels. Magnetically siphons loose battlefield scrap directly to the base bank. Upgradable to Transmission Mast [E].",
						"flavor": "\"Where the conductor reaches, the will of the Motive Force flows unbroken.\""
					}
					2: return {
						"key": "3", "name": "Imperial Plasma Dynamo", "sub": "Energy Generation",
						"icon": "generator", "scrap": 25, "req": 0, "type_id": 1,
						"desc": "Siphons atom-fire to generate +2 Requisition per cycle. Energizes Noosphere Aegis shields and Necro-Mechanic repair swarms.",
						"flavor": "\"From the caged fury of the atom do we draw the breath of civilization.\""
					}
					3: return {
						"key": "4", "name": "Cognis Defense Battery", "sub": "Automated Heavy Emplacement",
						"icon": "turret", "scrap": 35, "req": 5, "type_id": 2,
						"desc": "Automated tracking battery with dual autocannons. Upgradable through 4 tiers to specialized Cognis Flak, Volkite Thermal Rays, or Arc Blasters.",
						"flavor": "\"Let the wrath of the Machine God strike swift and without hesitation.\""
					}
					4: return {
						"key": "5", "name": "Promethium Scrap Smelter", "sub": "Ore Extraction & Refining",
						"icon": "foundry", "scrap": 30, "req": 5, "type_id": 3,
						"desc": "Must be constructed over an active Scrap Deposit. Automatically extracts and refines raw debris, generating +5 Scrap periodically.",
						"flavor": "\"The broken iron of the foe is remade into the sanctified bulwarks of Mars.\""
					}
					5: return {
						"key": "6", "name": "Omnissian Reliquary Vault", "sub": "Cogitator Archives",
						"icon": "shrine", "scrap": 40, "req": 15, "type_id": 6,
						"desc": "Houses ancient schematics of the Mechanicum. Access terminal [E] to research Aegis Shields, Cutting Lasers, Siphons, and Nanobots.",
						"flavor": "\"Knowledge is the true holy relic; safeguard it from the taint of the xeno.\""
					}
			else:
				return {} # Marshal has no building palette

		"augment":
			if is_techpriest:
				match idx:
					0:
						var skulls = local_player.active_servo_skulls.size() if "active_servo_skulls" in local_player else 0
						return {
							"key": "C", "name": "Fabricate Servo-Skull", "sub": "Autonomous Cyber-Drone",
							"icon": "skull", "scrap": GameData.SERVO_SKULL_SCRAP_COST, "req": GameData.SERVO_SKULL_REQ_COST, "type_id": -1,
							"current_rank": skulls, "max_rank": GameData.MAX_SERVO_SKULLS,
							"desc": "Deploys an autonomous hovering Servo-Skull drone to retrieve distant scrap and zap nearby pests (%d/%d Active)." % [skulls, GameData.MAX_SERVO_SKULLS],
							"flavor": "\"Even in death, the servant of the Omnissiah performs the holy work.\""
						}
					_: return {}
			else:
				# SKITARII MARSHAL BIONIC IMPLANTS & COHORT
				match idx:
					0:
						var dmg_lvl = local_player.damage_upgrade_level if "damage_upgrade_level" in local_player else 0
						return {
							"key": "Z", "name": "Galvanic Weapon Calibration", "sub": "Damage Overcharge",
							"icon": "dmg_up", "scrap": 0, "req": GameData.DAMAGE_UPGRADE_REQ_COST, "type_id": -1,
							"current_rank": dmg_lvl, "max_rank": GameData.MAX_DAMAGE_UPGRADES,
							"desc": "Permanent weapon damage amplification (+10 Damage per rank, %d/%d)." % [dmg_lvl, GameData.MAX_DAMAGE_UPGRADES],
							"flavor": "\"Recalibrate the coils, sanctify the firing pin, and let the discharge sing.\""
						}
					1:
						var spd_lvl = local_player.speed_upgrade_level if "speed_upgrade_level" in local_player else 0
						return {
							"key": "X", "name": "Bionic Locomotion Servos", "sub": "Speed Augment",
							"icon": "speed_up", "scrap": 0, "req": GameData.SPEED_UPGRADE_REQ_COST, "type_id": -1,
							"current_rank": spd_lvl, "max_rank": GameData.MAX_SPEED_UPGRADES,
							"desc": "Replaces organic leg joints with high-speed bionic servos (+35 Speed per rank, %d/%d)." % [spd_lvl, GameData.MAX_SPEED_UPGRADES],
							"flavor": "\"Cast aside the sluggish flesh; embrace the relentless stride of steel.\""
						}
					2:
						var lvl = local_player.bodyguard_level if "bodyguard_level" in local_player else 0
						return {
							"key": "C", "name": "Recruit Vanguard Cadre", "sub": "Cohort Reinforcement",
							"icon": "squad", "scrap": 0, "req": GameData.BODYGUARD_REQ_COST, "type_id": -1,
							"current_rank": lvl, "max_rank": GameData.MAX_BODYGUARDS,
							"desc": "Summons Skitarii Vanguard snipers and Sicarian melee shock troops into your retinue (%d/%d Active)." % [lvl, GameData.MAX_BODYGUARDS],
							"flavor": "\"No soldier of Mars fights alone while the Noosphere weaves our minds into one.\""
						}
					_: return {}

	return {}

# ==============================================================================
# 3. REFRESH DISPLAY LOOP
# ==============================================================================
func refresh_hud_display():
	if not is_instance_valid(local_player): return

	var main_node = get_tree().get_first_node_in_group("main")
	var cur_scrap = main_node.scrap_amount if main_node and "scrap_amount" in main_node else 0
	var cur_req = main_node.requisition_amount if main_node and "requisition_amount" in main_node else 0

	var is_techpriest = (local_player.current_class == 0)
	var selected_type = local_player.selected_building_type if "selected_building_type" in local_player else 0
	var is_building = local_player.is_building_mode if "is_building_mode" in local_player else false

	# 1. Update Armament Pod
	for i in range(weapon_buttons.size()):
		var slot = weapon_buttons[i]
		var data = _get_data_for_category("weapon", i)
		_populate_slot(slot, data, cur_scrap, cur_req)
		if is_techpriest and i == 1:
			var can_plasma = local_player.can_plasma_attack if "can_plasma_attack" in local_player else true
			var cd = local_player.plasma_cooldown if "plasma_cooldown" in local_player else 0.65
			slot.cooldown_left = 0.0 if can_plasma else cd
		elif not is_techpriest and i == 2:
			slot.cooldown_left = local_player.orbital_strike_cooldown if "orbital_strike_cooldown" in local_player else 0.0

	# 2. Update Tactical Forge Action Pod (Hidden for Marshal)
	if is_instance_valid(action_panel):
		action_panel.visible = is_techpriest

	if is_techpriest:
		for i in range(action_buttons.size()):
			var slot = action_buttons[i]
			var data = _get_data_for_category("action", i)
			_populate_slot(slot, data, cur_scrap, cur_req)
			slot.is_selected = (is_building and selected_type == data.get("type_id", -1))

	# 3. Update Cybernetic Augment Pod
	for i in range(augment_buttons.size()):
		var slot = augment_buttons[i]
		var data = _get_data_for_category("augment", i)
		_populate_slot(slot, data, cur_scrap, cur_req)
		
		if not data.is_empty() and data.has("current_rank") and data.has("max_rank"):
			slot.current_rank = data.current_rank
			slot.max_rank = data.max_rank
			slot.is_maxed = (slot.current_rank >= slot.max_rank)

	if not hovered_slot_data.is_empty() and tooltip_card and tooltip_card.visible:
		tooltip_card.set_data(hovered_slot_data, cur_scrap, cur_req)

func _populate_slot(slot: CompactSlot, data: Dictionary, cur_scrap: int, cur_req: int):
	if data.is_empty():
		slot.hide()
		slot.cached_data.clear()
		return
	
	slot.show()
	slot.cached_data = data
	slot.key_txt = data.key
	slot.icon_type = data.icon
	slot.scrap_cost = data.scrap
	slot.req_cost = data.req
	slot.can_afford = (cur_scrap >= data.scrap and cur_req >= data.req)
	slot.queue_redraw()

func _update_tooltip_position(slot: CompactSlot):
	var main_node = get_tree().get_first_node_in_group("main")
	var cur_scrap = main_node.scrap_amount if main_node and "scrap_amount" in main_node else 0
	var cur_req = main_node.requisition_amount if main_node and "requisition_amount" in main_node else 0

	var slot_center_x = slot.global_position.x + (slot.size.x * 0.5)
	tooltip_card.set_data(slot.cached_data, cur_scrap, cur_req, slot.cooldown_left, slot.is_maxed)
	tooltip_card.global_position = Vector2(slot_center_x - (tooltip_card.size.x * 0.5), slot.global_position.y - tooltip_card.size.y - 12)

# ==============================================================================
# 4. COMPACT NOOSPHERIC SLOT BUTTON (48x48 px)
# ==============================================================================
class CompactSlot extends Button:
	var category: String = "action"
	var slot_index: int = 0
	var key_txt: String = "1"
	var icon_type: String = "barricade"
	var scrap_cost: int = 0
	var req_cost: int = 0
	var can_afford: bool = true
	var is_selected: bool = false
	var is_maxed: bool = false
	var cooldown_left: float = 0.0
	var current_rank: int = 0
	var max_rank: int = 0
	var cached_data: Dictionary = {}

	func _init(cat: String, idx: int):
		category = cat
		slot_index = idx
		flat = true

	func _draw():
		var rect = Rect2(Vector2.ZERO, size)
		var bg_color = Color(0.06, 0.07, 0.10, 0.95)
		var border_color = Color(0.24, 0.28, 0.35)

		if cooldown_left > 0.0 or is_maxed:
			border_color = Color(0.40, 0.42, 0.48, 0.5)
		elif is_selected:
			var pulse = 0.85 + sin(Time.get_ticks_msec() * 0.008) * 0.15
			border_color = Color(0.20, 0.88, 1.00, pulse)
		elif not can_afford and (scrap_cost > 0 or req_cost > 0):
			border_color = Color(0.70, 0.20, 0.18, 0.8)
		elif is_hovered():
			border_color = Color(0.95, 0.78, 0.35)

		# 1. Base Plate & Outline
		draw_rect(rect, bg_color, true)
		draw_rect(rect, border_color, false, 1.2 if not is_selected else 1.8)

		# 2. Corner Brackets
		var c_len = 3.5
		draw_line(rect.position, rect.position + Vector2(c_len, 0), border_color, 1.2)
		draw_line(rect.position, rect.position + Vector2(0, c_len), border_color, 1.2)
		var tr = rect.position + Vector2(rect.size.x, 0)
		draw_line(tr, tr - Vector2(c_len, 0), border_color, 1.2)
		draw_line(tr, tr + Vector2(0, c_len), border_color, 1.2)

		# 3. Procedural Vector Icon
		_draw_icon(rect.get_center())

		# 4. Keycap Badge (Top-Left)
		var font = ThemeDB.fallback_font
		var key_color = Color(0.20, 0.88, 1.0) if is_selected else Color(0.85, 0.88, 0.92)
		if cooldown_left > 0.0 or is_maxed: key_color = Color(0.5, 0.5, 0.5)
		draw_string(font, Vector2(3, 10), key_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, key_color)

		# 5. Hardware Rank Pips (for Augments) vs. Cost Badges
		if max_rank > 0 and category == "augment":
			_draw_rank_pips(rect)
		elif cooldown_left > 0.0:
			var cd_str = "%.1fs" % cooldown_left if cooldown_left < 10.0 else "%ds" % int(ceil(cooldown_left))
			draw_string(font, Vector2(0, size.y - 3), cd_str, HORIZONTAL_ALIGNMENT_CENTER, size.x, 8, Color(1.0, 0.85, 0.2))
		elif is_maxed:
			draw_string(font, Vector2(0, size.y - 3), "MAX", HORIZONTAL_ALIGNMENT_CENTER, size.x, 8, Color(0.45, 0.9, 0.5))
		elif scrap_cost > 0 or req_cost > 0:
			var parts: Array[String] = []
			if scrap_cost > 0: parts.append("⚙%d" % scrap_cost)
			if req_cost > 0: parts.append("⚡%d" % req_cost)
			var cost_str = " ".join(parts)
			var c_color = Color(0.9, 0.85, 0.7) if can_afford else Color(0.92, 0.22, 0.18)
			draw_string(font, Vector2(0, size.y - 3), cost_str, HORIZONTAL_ALIGNMENT_CENTER, size.x, 7, c_color)

	func _draw_rank_pips(rect: Rect2):
		var pips_y = rect.size.y - 4.0
		var start_x = (rect.size.x - (max_rank * 6.0)) * 0.5
		for i in range(max_rank):
			var pip_pos = Vector2(start_x + (i * 6.0) + 2.0, pips_y)
			if i < current_rank:
				draw_circle(pip_pos, 1.8, Color(0.20, 0.88, 1.0)) # Filled cyan pip
			else:
				draw_circle(pip_pos, 1.2, Color(0.25, 0.28, 0.35)) # Empty pip

	func _draw_icon(center: Vector2):
		var gold = Color(0.82, 0.62, 0.24)
		var cyan = Color(0.20, 0.88, 1.0)
		var red  = Color(0.68, 0.16, 0.14)
		var p_mid = Vector2(center.x, center.y - 1.0)

		match icon_type:
			"axe": # Power-Axe
				draw_line(p_mid + Vector2(-6, 7), p_mid + Vector2(6, -7), Color(0.2, 0.24, 0.3), 3.0)
				draw_circle(p_mid + Vector2(4, -5), 3.5, gold)
				draw_colored_polygon(PackedVector2Array([p_mid + Vector2(2, -9), p_mid + Vector2(8, -9), p_mid + Vector2(7, -1)]), cyan)
			"plasma_pistol": # Plasma Caliver
				draw_line(p_mid + Vector2(-6, 2), p_mid + Vector2(7, 2), Color(0.25, 0.28, 0.35), 3.0)
				draw_circle(p_mid + Vector2(1, 2), 2.5, cyan)
				draw_circle(p_mid + Vector2(7, 2), 1.5, Color.WHITE)
			"gun": # Radium Serpenta
				draw_line(p_mid + Vector2(-6, 2), p_mid + Vector2(8, 2), Color(0.4, 0.45, 0.5), 2.5)
				draw_line(p_mid + Vector2(-4, 2), p_mid + Vector2(-6, 6), gold, 1.8)
				draw_circle(p_mid + Vector2(2, 2), 1.5, cyan)
			"barricade": # Rampart
				var shield = PackedVector2Array([p_mid + Vector2(-7, -7), p_mid + Vector2(7, -7), p_mid + Vector2(5, 3), p_mid + Vector2(0, 7), p_mid + Vector2(-5, 3)])
				draw_colored_polygon(shield, red)
				draw_polyline(shield, gold, 1.2)
			"distributor": # Substation
				draw_line(p_mid + Vector2(0, 7), p_mid + Vector2(0, -5), Color(0.24, 0.28, 0.35), 2.8)
				draw_circle(p_mid + Vector2(0, -5), 2.5, Color(1.0, 0.72, 0.15))
			"generator": # Dynamo
				draw_rect(Rect2(p_mid - Vector2(6, 6), Vector2(12, 12)), red)
				draw_rect(Rect2(p_mid - Vector2(6, 6), Vector2(12, 12)), gold, false, 1.0)
				draw_circle(p_mid, 3.0, cyan)
			"turret": # Cognis Battery
				draw_circle(p_mid, 5.5, red)
				draw_arc(p_mid, 5.5, 0, TAU, 12, gold, 1.0)
				draw_line(p_mid + Vector2(2, -2), p_mid + Vector2(8, -2), Color(0.4, 0.45, 0.5), 1.8)
				draw_line(p_mid + Vector2(2, 2), p_mid + Vector2(8, 2), Color(0.4, 0.45, 0.5), 1.8)
			"foundry": # Smelter
				draw_rect(Rect2(p_mid - Vector2(6, 3), Vector2(12, 10)), Color(0.2, 0.22, 0.28))
				draw_circle(p_mid + Vector2(0, 2), 2.2, Color(1.0, 0.5, 0.1))
			"shrine": # Reliquary
				var arch = PackedVector2Array([p_mid + Vector2(-6, 6), p_mid + Vector2(-6, -2), p_mid + Vector2(0, -7), p_mid + Vector2(6, -2), p_mid + Vector2(6, 6)])
				draw_colored_polygon(arch, red)
				draw_polyline(arch, gold, 1.2)
				draw_circle(p_mid + Vector2(0, 1), 2.0, cyan)
			"doctrina_conq": # Conqueror
				draw_line(p_mid + Vector2(-5, -5), p_mid + Vector2(5, 5), Color(1.0, 0.80, 0.20), 1.8)
				draw_line(p_mid + Vector2(-5, 5), p_mid + Vector2(5, -5), Color(1.0, 0.80, 0.20), 1.8)
			"doctrina_prot": # Protector
				draw_arc(p_mid, 6.0, 0, TAU, 16, cyan, 1.6)
				draw_circle(p_mid, 2.0, Color.WHITE)
			"skull": # Servo-Skull
				draw_circle(p_mid, 5.0, Color(0.88, 0.85, 0.75))
				draw_circle(p_mid + Vector2(1.5, -0.5), 1.5, cyan)
				draw_line(p_mid + Vector2(3, 2), p_mid + Vector2(6, 2), gold, 1.2)
			"squad": # Vanguard Cadre
				draw_circle(p_mid + Vector2(-3, 0), 3.5, red)
				draw_circle(p_mid + Vector2(3, 0), 3.5, red)
				draw_circle(p_mid + Vector2(-3, 0), 1.0, Color(0.2, 0.95, 0.35))
				draw_circle(p_mid + Vector2(3, 0), 1.0, Color(0.2, 0.95, 0.35))
			"dmg_up": # Damage Upgrade
				draw_polyline(PackedVector2Array([p_mid + Vector2(-5, 3), p_mid + Vector2(0, -2), p_mid + Vector2(5, 3)]), cyan, 1.5)
				draw_polyline(PackedVector2Array([p_mid + Vector2(-5, -1), p_mid + Vector2(0, -6), p_mid + Vector2(5, -1)]), gold, 1.5)
			"speed_up": # Speed Upgrade
				draw_line(p_mid + Vector2(-6, 0), p_mid + Vector2(6, 0), Color(0.2, 0.95, 0.45), 2.0)
				draw_line(p_mid + Vector2(2, -4), p_mid + Vector2(6, 0), Color(0.2, 0.95, 0.45), 2.0)
				draw_line(p_mid + Vector2(2, 4), p_mid + Vector2(6, 0), Color(0.2, 0.95, 0.45), 2.0)
			"orbital": # Orbital Lance
				draw_circle(p_mid, 6.0, Color(0.2, 0.88, 1.0, 0.3))
				draw_line(p_mid + Vector2(0, -8), p_mid + Vector2(0, 8), cyan, 1.8)
				draw_line(p_mid + Vector2(-8, 0), p_mid + Vector2(8, 0), cyan, 1.8)

# ==============================================================================
# 5. EXPANDED AUSPEX COGITATOR TOOLTIP INSPECTION CARD
# ==============================================================================
class TooltipCard extends PanelContainer:
	var title_lbl: Label
	var sub_lbl: Label
	var cost_lbl: Label
	var desc_lbl: Label
	var flavor_lbl: Label

	func _init():
		custom_minimum_size = Vector2(320, 0)
		_setup_ui()

	func _setup_ui():
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.05, 0.08, 0.96)
		sb.border_color = Color(0.82, 0.62, 0.24)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		sb.shadow_color = Color(0, 0, 0, 0.65)
		sb.shadow_size = 6
		add_theme_stylebox_override("panel", sb)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		add_child(vbox)

		title_lbl = Label.new()
		title_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
		title_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(title_lbl)

		sub_lbl = Label.new()
		sub_lbl.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
		sub_lbl.add_theme_font_size_override("font_size", 9)
		vbox.add_child(sub_lbl)

		cost_lbl = Label.new()
		cost_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(cost_lbl)

		var sep = ColorRect.new()
		sep.custom_minimum_size = Vector2(0, 1)
		sep.color = Color(0.25, 0.28, 0.35, 0.6)
		vbox.add_child(sep)

		desc_lbl = Label.new()
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
		desc_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(desc_lbl)

		flavor_lbl = Label.new()
		flavor_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor_lbl.add_theme_color_override("font_color", Color(0.72, 0.65, 0.50))
		flavor_lbl.add_theme_font_size_override("font_size", 9)
		vbox.add_child(flavor_lbl)

	func set_data(data: Dictionary, cur_scrap: int, cur_req: int, cooldown_left: float = 0.0, is_maxed: bool = false):
		title_lbl.text = "◆ %s [%s] ◆" % [data.get("name", "").to_upper(), data.get("key", "")]
		sub_lbl.text = data.get("sub", "").to_upper()
		desc_lbl.text = data.get("desc", "")
		flavor_lbl.text = data.get("flavor", "")

		var scrap = data.get("scrap", 0)
		var req = data.get("req", 0)

		if cooldown_left > 0.0:
			cost_lbl.text = "⏳ RECHARGING (%.1fs Remaining)" % cooldown_left
			cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.15))
		elif is_maxed:
			cost_lbl.text = "◆ AUGMENTATION MAXED ◆"
			cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
		elif scrap == 0 and req == 0:
			cost_lbl.text = "STATUS: NOOSPHERIC LINK READY"
			cost_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
		else:
			var parts: Array[String] = []
			if scrap > 0: parts.append("⚙ %d SCRAP" % scrap)
			if req > 0: parts.append("⚡ %d REQ" % req)
			var can_afford = (cur_scrap >= scrap and cur_req >= req)
			cost_lbl.text = "COST: " + "   ".join(parts)
			cost_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45) if can_afford else Color(0.92, 0.22, 0.18))
