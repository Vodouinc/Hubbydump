extends Control
class_name BaseUpgradeUI

const GameData = preload("res://GameData.gd")

var panel_container: PanelContainer = null
var cards_grid: GridContainer = null
var base_node_ref: Node2D = null

func _ready():
	add_to_group("base_upgrade_ui")
	theme = AdmechTheme.make()
	hide()
	_build_ui_layout()

func _build_ui_layout():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Backdrop
	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.75)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(740, 480)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(pc)
	panel_container = pc

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel_container.add_child(vbox)

	var title = Label.new()
	title.text = "◆ MAIN SANCTUM: AUSPEX & NOOSPHERIC PROTOCOLS ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "Sanctify primary auspex arrays and psychic signal interceptors:"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	sub.add_theme_font_size_override("font_size", 10)
	vbox.add_child(sub)

	# 2x2 Grid of Upgrade Cards
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)
	cards_grid = grid

	var close_btn = Button.new()
	close_btn.text = "DISENGAGE TERMINAL [ESC / E]"
	close_btn.custom_minimum_size = Vector2(220, 32)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close_terminal)
	vbox.add_child(close_btn)

func open_terminal(base_node: Node2D = null):
	base_node_ref = base_node
	show()
	_refresh_cards()

func close_terminal():
	hide()
	base_node_ref = null

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ESCAPE, KEY_E]:
			close_terminal()
			get_viewport().set_input_as_handled()

func _refresh_cards():
	if not visible or cards_grid == null: return
	for c in cards_grid.get_children():
		c.queue_free()

	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return

	var cur_scrap = main_node.scrap_amount if "scrap_amount" in main_node else 0
	var cur_req = main_node.requisition_amount if "requisition_amount" in main_node else 0
	var radar_lvl = main_node.base_radar_level if "base_radar_level" in main_node else 0
	var waaagh_unlocked = main_node.tech_waaagh_reader_unlocked if "tech_waaagh_reader_unlocked" in main_node else false

	for tech in GameData.SANCTUM_TECH:
		var is_researched = false
		var is_locked = false

		match tech.id:
			0: is_researched = (radar_lvl >= 1)
			1: is_researched = waaagh_unlocked
			2:
				is_researched = (radar_lvl >= 2)
				is_locked = (radar_lvl < 1)
			3:
				is_researched = (radar_lvl >= 3)
				is_locked = (radar_lvl < 2)

		var card = _create_sanctum_card(tech, is_researched, is_locked, cur_scrap, cur_req)
		cards_grid.add_child(card)

func _create_sanctum_card(tech: Dictionary, is_researched: bool, is_locked: bool, cur_scrap: int, cur_req: int) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(340, 160)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "%s %s" % [tech.icon, tech.name]
	header.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0) if not is_researched else Color(0.40, 0.95, 0.50))
	header.add_theme_font_size_override("font_size", 12)
	vbox.add_child(header)

	# Cost / Status
	var cost_lbl = Label.new()
	if is_researched:
		cost_lbl.text = "◆ PROTOCOL OPERATIONAL ◆"
		cost_lbl.add_theme_color_override("font_color", Color(0.40, 0.95, 0.50))
	elif is_locked:
		cost_lbl.text = "🔒 PREREQUISITE PROTOCOL REQUIRED"
		cost_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	else:
		cost_lbl.text = "⚙ %d SCRAP   ⚡ %d REQUISITION" % [tech.scrap, tech.req]
		var can_afford = (cur_scrap >= tech.scrap and cur_req >= tech.req)
		cost_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.40) if can_afford else Color(0.92, 0.22, 0.18))
	cost_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(cost_lbl)

	# Description
	var desc = Label.new()
	desc.text = tech.desc
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	desc.add_theme_font_size_override("font_size", 10)
	vbox.add_child(desc)

	# Buy Button
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 26)
	if is_researched:
		btn.text = "INSTALLED"
		btn.disabled = true
	elif is_locked:
		btn.text = "LOCKED"
		btn.disabled = true
	else:
		var can_afford = (cur_scrap >= tech.scrap and cur_req >= tech.req)
		btn.text = "SANCTIFY PROTOCOL"
		btn.disabled = not can_afford
		btn.pressed.connect(func(): _on_tech_purchased(tech.id))
	vbox.add_child(btn)

	return card

func _on_tech_purchased(tech_id: int):
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		main_node.rpc_id(1, "request_sanctum_research", tech_id)
		close_terminal()
