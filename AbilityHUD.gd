extends Control
class_name AbilityHUD

var local_player: Node2D = null
var update_accumulator: float = 0.0
const UPDATE_INTERVAL: float = 0.06

# Theme Colors
const C_BG_DARK     := Color(0.04, 0.05, 0.08, 0.94)
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
var slots_container: HBoxContainer = null
var slot_buttons: Array[SlotButton] = []
var tooltip_card: TooltipCard = null

var hovered_slot_idx: int = -1

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
# 1. UI STRUCTURE BUILDER
# ==============================================================================
func _build_hud_layout():
	for c in get_children():
		c.queue_free()

	# 1. Tooltip Inspection Card (Floats above the action bar)
	tooltip_card = TooltipCard.new()
	tooltip_card.name = "TooltipCard"
	tooltip_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tooltip_card)
	tooltip_card.hide()

	# 2. Bottom Hotbar Bar Housing
	var bar_panel = PanelContainer.new()
	bar_panel.name = "BarPanel"
	bar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar_panel.position = Vector2(-180, -68)
	bar_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(bar_panel)

	# Style the bar container
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_BG_DARK
	sb.border_color = C_BRASS_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	bar_panel.add_theme_stylebox_override("panel", sb)

	var hbox = HBoxContainer.new()
	hbox.name = "SlotsHBox"
	hbox.add_theme_constant_override("separation", 6)
	bar_panel.add_child(hbox)
	slots_container = hbox

	# Create 6 Compact Action Slots (50x50 px)
	slot_buttons.clear()
	for i in range(6):
		var btn = SlotButton.new(i)
		btn.custom_minimum_size = Vector2(52, 52)
		btn.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
		btn.mouse_exited.connect(_on_slot_mouse_exited.bind(i))
		slots_container.add_child(btn)
		slot_buttons.append(btn)

func _on_slot_mouse_entered(idx: int):
	hovered_slot_idx = idx
	_update_tooltip_content()
	if tooltip_card:
		tooltip_card.show()

func _on_slot_mouse_exited(idx: int):
	if hovered_slot_idx == idx:
		hovered_slot_idx = -1
		if tooltip_card:
			tooltip_card.hide()

# ==============================================================================
# 2. DATA PROVIDER (STATS & GRIMDARK 40K FLAVOR TEXT)
# ==============================================================================
func _get_slot_data(idx: int) -> Dictionary:
	if not is_instance_valid(local_player): return {}
	
	var is_techpriest = (local_player.current_class == 0)

	if is_techpriest:
		match idx:
			0: return {
				"key": "1", "name": "Aegis Blast Rampart", "sub": "Tactical Fortification",
				"icon": "barricade", "scrap": 15, "req": 0, "type_id": 0,
				"desc": "Heavy sloped ballistic blast wall. Snap-links into continuous defensive ramparts with dragon's teeth spikes. Upgradable to Motorized Gate [E].",
				"flavor": "\"Armor is the iron shroud that preserves the sacred flesh of the faithful.\" — Catechism of the Bastion"
			}
			1: return {
				"key": "2", "name": "Electro-Relay Substation", "sub": "Power & Scrap Distribution",
				"icon": "distributor", "scrap": 20, "req": 0, "type_id": 4,
				"desc": "Extends Noosphere power conduit channels. Magnetically siphons loose battlefield scrap directly to the base bank. Upgradable to Transmission Mast [E].",
				"flavor": "\"Where the conductor reaches, the will of the Motive Force flows unbroken.\" — Canticles of the Pylon"
			}
			2: return {
				"key": "3", "name": "Imperial Plasma Dynamo", "sub": "Energy Generation",
				"icon": "generator", "scrap": 25, "req": 0, "type_id": 1,
				"desc": "Siphons atom-fire to generate +2 Requisition per cycle. Energizes Noosphere Aegis shields and Necro-Mechanic repair swarms.",
				"flavor": "\"From the caged fury of the atom do we draw the breath of civilization.\" — Litany of the Core"
			}
			3: return {
				"key": "4", "name": "Cognis Defense Battery", "sub": "Automated Heavy Emplacement",
				"icon": "turret", "scrap": 35, "req": 5, "type_id": 2,
				"desc": "Automated tracking battery with dual autocannons. Upgradable through 4 tiers to specialized Cognis Flak, Volkite Thermal Rays, or Arc Blasters.",
				"flavor": "\"Let the wrath of the Machine God strike swift and without hesitation.\" — Litany of the Iron Soul"
			}
			4: return {
				"key": "5", "name": "Promethium Scrap Smelter", "sub": "Ore Extraction & Refining",
				"icon": "foundry", "scrap": 30, "req": 5, "type_id": 3,
				"desc": "Must be constructed over an active Scrap Deposit. Automatically extracts and refines raw debris, generating +5 Scrap periodically.",
				"flavor": "\"The broken iron of the foe is remade into the sanctified bulwarks of Mars.\" — Rite of Transmutation"
			}
			5: return {
				"key": "6", "name": "Omnissian Reliquary Vault", "sub": "Cogitator Archives",
				"icon": "shrine", "scrap": 40, "req": 15, "type_id": 6,
				"desc": "Houses ancient schematics of the Mechanicum. Access terminal [E] to research Aegis Shields, Cutting Lasers, Siphons, and Nanobots.",
				"flavor": "\"Knowledge is the true holy relic; safeguard it from the taint of the xeno.\" — Prime Directive 01"
			}
	else:
		# SKITARII MARSHAL (RANGED COMMANDER)
		match idx:
			0: return {
				"key": "LMB", "name": "Radium Serpenta & Carbine", "sub": "Primary Archeotech Weaponry",
				"icon": "gun", "scrap": 0, "req": 0, "type_id": -1,
				"desc": "Fires hyper-velocity irradiated munitions that scourge the cellular composition of organic targets.",
				"flavor": "\"Breathe deep the holy fallout, and let your flesh be cleansed in phosphor fire.\""
			}
			1: 
				var is_conq = (local_player.get("active_doctrina") == 0)
				return {
					"key": "SPACE", "name": "Doctrina Imperative: " + ("CONQUEROR" if is_conq else "PROTECTOR"),
					"sub": "Noospheric Stance Calibration",
					"icon": "doctrina_conq" if is_conq else "doctrina_prot", "scrap": 0, "req": 0, "type_id": -1,
					"desc": "+60% Movement Speed & +25% Fire Rate / -20% Armor" if is_conq else "+35% Armor & Ranged Resistance / -15% Speed",
					"flavor": "\"The Omnissiah guides our feet as He guides our guns. Upload the sacred canticle.\""
				}
			2:
				var lvl = local_player.bodyguard_level if "bodyguard_level" in local_player else 0
				return {
					"key": "N", "name": "Skitarii Vanguard Cadre", "sub": "Cohort Reinforcement",
					"icon": "squad", "scrap": 0, "req": GameData.BODYGUARD_REQ_COST, "type_id": -1,
					"desc": "Recruit Vanguard Troopers and Sicarian Infiltrators into your bodyguard retinue (%d/%d Active)." % [lvl, GameData.MAX_BODYGUARDS],
					"flavor": "\"No soldier of Mars fights alone while the Noosphere weaves our minds into one.\""
				}
			3:
				var dmg_lvl = local_player.damage_upgrade_level if "damage_upgrade_level" in local_player else 0
				return {
					"key": "M", "name": "Galvanic Weapon Calibration", "sub": "Capacitor Overcharge",
					"icon": "dmg_up", "scrap": 0, "req": GameData.DAMAGE_UPGRADE_REQ_COST, "type_id": -1,
					"desc": "Permanent weapon damage amplification (+10 Damage per rank, %d/%d)." % [dmg_lvl, GameData.MAX_DAMAGE_UPGRADES],
					"flavor": "\"Recalibrate the coils, sanctify the firing pin, and let the discharge sing.\""
				}
			4: return {
				"key": "X", "name": "Orbital Lance Strike", "sub": "Fleet Telemetry Bombardment",
				"icon": "orbital", "scrap": 0, "req": GameData.ORBITAL_REQ_COST, "type_id": -1,
				"desc": "Designates ground coordinates for a devastating cataclysmic lance beam from low-orbit cruisers (220 DMG / 45s Cooldown).",
				"flavor": "\"Let the stars themselves descend upon the blasphemer in cleansing fire.\""
			}
			5: return {}

	return {}

# ==============================================================================
# 3. HUD REFRESH LOOP
# ==============================================================================
func refresh_hud_display():
	if not is_instance_valid(local_player): return

	var main_node = get_tree().get_first_node_in_group("main")
	var cur_scrap = main_node.scrap_amount if main_node else 0
	var cur_req = main_node.requisition_amount if main_node else 0

	var is_techpriest = (local_player.current_class == 0)
	var selected_type = local_player.selected_building_type if "selected_building_type" in local_player else 0
	var is_building = local_player.is_building_mode if "is_building_mode" in local_player else false

	for i in range(slot_buttons.size()):
		var btn = slot_buttons[i]
		var data = _get_slot_data(i)
		if data.is_empty():
			btn.hide()
			continue
		
		btn.show()
		btn.key_txt = data.key
		btn.icon_type = data.icon
		btn.scrap_cost = data.scrap
		btn.req_cost = data.req
		
		# Affordability & Selection State
		btn.can_afford = (cur_scrap >= data.scrap and cur_req >= data.req)
		
		if is_techpriest:
			btn.is_selected = (is_building and selected_type == data.type_id)
			btn.is_maxed = false
			btn.cooldown_left = 0.0
		else:
			btn.is_selected = (i == 1) # Doctrina active pulse
			if i == 2:
				var lvl = local_player.bodyguard_level if "bodyguard_level" in local_player else 0
				btn.is_maxed = (lvl >= GameData.MAX_BODYGUARDS)
			elif i == 3:
				var dmg_lvl = local_player.damage_upgrade_level if "damage_upgrade_level" in local_player else 0
				btn.is_maxed = (dmg_lvl >= GameData.MAX_DAMAGE_UPGRADES)
			elif i == 4:
				btn.cooldown_left = local_player.get("orbital_strike_cooldown") if "orbital_strike_cooldown" in local_player else 0.0

		btn.queue_redraw()

	if hovered_slot_idx != -1 and tooltip_card and tooltip_card.visible:
		_update_tooltip_content()

func _update_tooltip_content():
	if hovered_slot_idx < 0 or hovered_slot_idx >= slot_buttons.size(): return
	var data = _get_slot_data(hovered_slot_idx)
	if data.is_empty():
		tooltip_card.hide()
		return

	var main_node = get_tree().get_first_node_in_group("main")
	var cur_scrap = main_node.scrap_amount if main_node else 0
	var cur_req = main_node.requisition_amount if main_node else 0

	var btn = slot_buttons[hovered_slot_idx]
	var btn_center_x = btn.global_position.x + (btn.size.x * 0.5)

	tooltip_card.set_data(data, cur_scrap, cur_req, btn.cooldown_left, btn.is_maxed)
	tooltip_card.global_position = Vector2(btn_center_x - (tooltip_card.size.x * 0.5), btn.global_position.y - tooltip_card.size.y - 12)

# ==============================================================================
# 4. COMPACT NOOSPHERIC SLOT BUTTON (52x52 px)
# ==============================================================================
class SlotButton extends Button:
	var slot_index: int = 0
	var key_txt: String = "1"
	var icon_type: String = "barricade"
	var scrap_cost: int = 0
	var req_cost: int = 0
	var can_afford: bool = true
	var is_selected: bool = false
	var is_maxed: bool = false
	var cooldown_left: float = 0.0

	func _init(idx: int):
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
		elif not can_afford:
			border_color = Color(0.70, 0.20, 0.18, 0.8)
		elif is_hovered():
			border_color = Color(0.95, 0.78, 0.35)

		# 1. Base Plate & Border
		draw_rect(rect, bg_color, true)
		draw_rect(rect, border_color, false, 1.2 if not is_selected else 1.8)

		# Corner Brackets
		var c_len = 4.0
		draw_line(rect.position, rect.position + Vector2(c_len, 0), border_color, 1.5)
		draw_line(rect.position, rect.position + Vector2(0, c_len), border_color, 1.5)
		var tr = rect.position + Vector2(rect.size.x, 0)
		draw_line(tr, tr - Vector2(c_len, 0), border_color, 1.5)
		draw_line(tr, tr + Vector2(0, c_len), border_color, 1.5)

		# 2. Draw Procedural AdMech Vector Icon
		_draw_slot_icon(rect.get_center())

		# 3. Hotkey Badge (Top-Left)
		var font = ThemeDB.fallback_font
		var key_color = Color(0.20, 0.88, 1.0) if is_selected else Color(0.85, 0.88, 0.92)
		if cooldown_left > 0.0 or is_maxed: key_color = Color(0.5, 0.5, 0.5)
		draw_string(font, Vector2(4, 11), key_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, key_color)

		# 4. Cost Badges (Bottom Right / Center)
		if cooldown_left > 0.0:
			var cd_str = "%.1fs" % cooldown_left if cooldown_left < 10.0 else "%ds" % int(ceil(cooldown_left))
			draw_string(font, Vector2(0, size.y - 4), cd_str, HORIZONTAL_ALIGNMENT_CENTER, size.x, 9, Color(1.0, 0.85, 0.2))
		elif is_maxed:
			draw_string(font, Vector2(0, size.y - 4), "MAX", HORIZONTAL_ALIGNMENT_CENTER, size.x, 8, Color(0.5, 0.55, 0.6))
		elif scrap_cost > 0 or req_cost > 0:
			var parts: Array[String] = []
			if scrap_cost > 0: parts.append("⚙%d" % scrap_cost)
			if req_cost > 0: parts.append("⚡%d" % req_cost)
			var cost_str = " ".join(parts)
			var c_color = Color(0.9, 0.85, 0.7) if can_afford else Color(0.92, 0.22, 0.18)
			draw_string(font, Vector2(0, size.y - 4), cost_str, HORIZONTAL_ALIGNMENT_CENTER, size.x, 8, c_color)

	func _draw_slot_icon(center: Vector2):
		var gold = Color(0.82, 0.62, 0.24)
		var cyan = Color(0.20, 0.88, 1.0)
		var red  = Color(0.68, 0.16, 0.14)
		var icon_y = center.y - 2.0
		var p_mid = Vector2(center.x, icon_y)

		match icon_type:
			"barricade":
				# Armored Aegis Shield
				var shield = PackedVector2Array([
					p_mid + Vector2(-8, -8), p_mid + Vector2(8, -8),
					p_mid + Vector2(6, 4), p_mid + Vector2(0, 9), p_mid + Vector2(-6, 4)
				])
				draw_colored_polygon(shield, red)
				draw_polyline(shield, gold, 1.2)
				draw_line(p_mid + Vector2(-4, -2), p_mid + Vector2(4, -2), gold, 1.0)
			"distributor":
				# Tesla Capacitor Pylon
				draw_line(p_mid + Vector2(0, 8), p_mid + Vector2(0, -6), Color(0.24, 0.28, 0.35), 3.0)
				draw_circle(p_mid + Vector2(0, -6), 3.0, Color(1.0, 0.72, 0.15))
				draw_line(p_mid + Vector2(-6, 0), p_mid + Vector2(6, 0), gold, 1.2)
			"generator":
				# Plasma Reactor Core
				draw_rect(Rect2(p_mid - Vector2(7, 7), Vector2(14, 14)), red)
				draw_rect(Rect2(p_mid - Vector2(7, 7), Vector2(14, 14)), gold, false, 1.0)
				draw_circle(p_mid, 3.5, cyan)
				draw_circle(p_mid, 1.2, Color.WHITE)
			"turret":
				# Twin Autocannon Cupola
				draw_circle(p_mid, 6.0, red)
				draw_arc(p_mid, 6.0, 0, TAU, 12, gold, 1.0)
				draw_line(p_mid + Vector2(2, -2.5), p_mid + Vector2(9, -2.5), Color(0.4, 0.45, 0.5), 2.0)
				draw_line(p_mid + Vector2(2, 2.5), p_mid + Vector2(9, 2.5), Color(0.4, 0.45, 0.5), 2.0)
			"foundry":
				# Smelter Furnace & Smokestacks
				draw_rect(Rect2(p_mid - Vector2(7, 4), Vector2(14, 11)), Color(0.2, 0.22, 0.28))
				draw_rect(Rect2(p_mid - Vector2(5, 8), Vector2(3, 4)), gold)
				draw_rect(Rect2(p_mid + Vector2(2, -8), Vector2(3, 4)), gold)
				draw_circle(p_mid + Vector2(0, 2), 2.5, Color(1.0, 0.5, 0.1))
			"shrine":
				# Gothic Reliquary Arch & Gear
				var arch = PackedVector2Array([
					p_mid + Vector2(-7, 7), p_mid + Vector2(-7, -2),
					p_mid + Vector2(0, -8), p_mid + Vector2(7, -2), p_mid + Vector2(7, 7)
				])
				draw_colored_polygon(arch, red)
				draw_polyline(arch, gold, 1.2)
				draw_circle(p_mid + Vector2(0, 1), 2.5, cyan)
			"gun":
				# Radium Serpenta Pistol
				draw_line(p_mid + Vector2(-6, 2), p_mid + Vector2(8, 2), Color(0.4, 0.45, 0.5), 2.5)
				draw_line(p_mid + Vector2(-4, 2), p_mid + Vector2(-6, 7), gold, 2.0)
				draw_circle(p_mid + Vector2(2, 2), 1.5, cyan)
			"doctrina_conq":
				# Dual Crossed Blades (Conqueror)
				draw_line(p_mid + Vector2(-6, -6), p_mid + Vector2(6, 6), Color(1.0, 0.80, 0.20), 2.0)
				draw_line(p_mid + Vector2(-6, 6), p_mid + Vector2(6, -6), Color(1.0, 0.80, 0.20), 2.0)
			"doctrina_prot":
				# Iron Aegis Shield (Protector)
				draw_arc(p_mid, 7.0, 0, TAU, 16, cyan, 1.8)
				draw_circle(p_mid, 2.5, Color.WHITE)
			"squad":
				# Skitarii Vanguard Helmets
				draw_circle(p_mid + Vector2(-3.5, 0), 4.0, red)
				draw_circle(p_mid + Vector2(3.5, 0), 4.0, red)
				draw_circle(p_mid + Vector2(-3.5, 0), 1.2, Color(0.2, 0.95, 0.35))
				draw_circle(p_mid + Vector2(3.5, 0), 1.2, Color(0.2, 0.95, 0.35))
			"dmg_up":
				# Weapon Calibration Chevrons
				draw_polyline(PackedVector2Array([p_mid + Vector2(-6, 4), p_mid + Vector2(0, -2), p_mid + Vector2(6, 4)]), cyan, 1.8)
				draw_polyline(PackedVector2Array([p_mid + Vector2(-6, -1), p_mid + Vector2(0, -7), p_mid + Vector2(6, -1)]), gold, 1.8)
			"orbital":
				# Searing Orbital Lance Strike
				draw_circle(p_mid, 7.0, Color(0.2, 0.88, 1.0, 0.3))
				draw_line(p_mid + Vector2(0, -10), p_mid + Vector2(0, 10), cyan, 2.2)
				draw_line(p_mid + Vector2(-10, 0), p_mid + Vector2(10, 0), cyan, 2.2)
				draw_circle(p_mid, 2.0, Color.WHITE)

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
		custom_minimum_size = Vector2(340, 0)
		_setup_ui()

	func _setup_ui():
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.05, 0.08, 0.96)
		sb.border_color = Color(0.82, 0.62, 0.24)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.shadow_color = Color(0, 0, 0, 0.6)
		sb.shadow_size = 6
		add_theme_stylebox_override("panel", sb)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 5)
		add_child(vbox)

		# 1. Header Title
		title_lbl = Label.new()
		title_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
		title_lbl.add_theme_font_size_override("font_size", 13)
		vbox.add_child(title_lbl)

		# 2. Sub-Role
		sub_lbl = Label.new()
		sub_lbl.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
		sub_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(sub_lbl)

		# 3. Cost / Telemetry Bar
		cost_lbl = Label.new()
		cost_lbl.add_theme_font_size_override("font_size", 11)
		vbox.add_child(cost_lbl)

		# Divider
		var sep = ColorRect.new()
		sep.custom_minimum_size = Vector2(0, 1)
		sep.color = Color(0.25, 0.28, 0.35, 0.6)
		vbox.add_child(sep)

		# 4. Mechanical Gameplay Stats / Description
		desc_lbl = Label.new()
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
		desc_lbl.add_theme_font_size_override("font_size", 11)
		vbox.add_child(desc_lbl)

		# 5. Grimdark 40K Lore & Canticle
		flavor_lbl = Label.new()
		flavor_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor_lbl.add_theme_color_override("font_color", Color(0.72, 0.65, 0.50))
		flavor_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(flavor_lbl)

	func set_data(data: Dictionary, cur_scrap: int, cur_req: int, cooldown_left: float, is_maxed: bool):
		title_lbl.text = "◆ %s [%s] ◆" % [data.name.to_upper(), data.key]
		sub_lbl.text = data.sub.to_upper()
		desc_lbl.text = data.desc
		flavor_lbl.text = data.flavor

		if cooldown_left > 0.0:
			cost_lbl.text = "⏳ COOLDOWN RECHARGING (%.1fs Remaining)" % cooldown_left
			cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.15))
		elif is_maxed:
			cost_lbl.text = "◆ COHORT ALLOCATION MAXED ◆"
			cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
		elif data.scrap == 0 and data.req == 0:
			cost_lbl.text = "STATUS: NOOSPHERIC LINK ACTIVE"
			cost_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
		else:
			var parts: Array[String] = []
			if data.scrap > 0: parts.append("⚙ %d SCRAP" % data.scrap)
			if data.req > 0: parts.append("⚡ %d REQUISITION" % data.req)
			var can_afford = (cur_scrap >= data.scrap and cur_req >= data.req)
			cost_lbl.text = "RESOURCE COST: " + "   ".join(parts)
			cost_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45) if can_afford else Color(0.92, 0.22, 0.18))
