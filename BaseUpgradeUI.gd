extends Control
class_name BaseUpgradeUI

const GameData = preload("res://GameData.gd")

var panel_container: PanelContainer = null
var current_tier_label: Label = null
var upgrade_btn: Button = null
var cost_label: Label = null
var desc_label: Label = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("base_upgrade_ui")
	theme = AdmechTheme.make()
	hide()
	_build_ui_layout()

func _build_ui_layout():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.70)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(500, 360)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(pc)
	panel_container = pc

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel_container.add_child(vbox)

	var title = Label.new()
	title.text = "◆ MAIN SANCTUM: AUSPEX COGITATION PROTOCOLS ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	current_tier_label = Label.new()
	current_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_tier_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.20))
	vbox.add_child(current_tier_label)

	desc_label = Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	desc_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(desc_label)

	cost_label = Label.new()
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(cost_label)

	upgrade_btn = Button.new()
	upgrade_btn.custom_minimum_size = Vector2(0, 34)
	upgrade_btn.pressed.connect(_on_upgrade_pressed)
	vbox.add_child(upgrade_btn)

	var close_btn = Button.new()
	close_btn.text = "DISENGAGE [ESC / E]"
	close_btn.custom_minimum_size = Vector2(0, 30)
	close_btn.pressed.connect(close_terminal)
	vbox.add_child(close_btn)

func open_terminal():
	show()
	_refresh_display()

func close_terminal():
	hide()

func _refresh_display():
	var main_node = get_tree().get_first_node_in_group("main")
	if not main_node: return
	
	var cur_tier = main_node.get("base_radar_level")
	var cur_scrap = main_node.scrap_amount
	var cur_req = main_node.requisition_amount

	var next_tier = cur_tier + 1

	if cur_tier == GameData.BaseRadarTier.NONE:
		current_tier_label.text = "CURRENT STATUS: NOOSPHERE RADAR OFFLINE"
	elif cur_tier == GameData.BaseRadarTier.TIER_1_CARTOGRAPH:
		current_tier_label.text = "CURRENT STATUS: TIER 1 - CARTOGRAPH ONLINE [M]"
	elif cur_tier == GameData.BaseRadarTier.TIER_2_AUSPEX:
		current_tier_label.text = "CURRENT STATUS: TIER 2 - AUSPEX EARLY WARNING ACTIVE"
	else:
		current_tier_label.text = "CURRENT STATUS: TIER 3 - NOOSPHERE TELEMETRY MAXED"

	if next_tier <= GameData.BaseRadarTier.TIER_3_NOOSPHERE:
		var info = GameData.BASE_RADAR_UPGRADE_INFO[next_tier]
		desc_label.text = "NEXT UPGRADE: %s\n\n%s" % [info.name, info.desc]
		cost_label.text = "COST: ⚙ %d SCRAP   ⚡ %d REQUISITION" % [info.scrap, info.req]
		
		var can_afford = (cur_scrap >= info.scrap and cur_req >= info.req)
		cost_label.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0) if can_afford else Color(0.95, 0.25, 0.25))
		upgrade_btn.text = "CONSTRUCT %s" % info.name
		upgrade_btn.disabled = not can_afford
	else:
		desc_label.text = "Omnissian sensory augments operating at peak capacity. All battlefield frequencies synchronized."
		cost_label.text = "◆ AUSPEX MATRIX MAXED ◆"
		cost_label.add_theme_color_override("font_color", Color(0.40, 0.95, 0.50))
		upgrade_btn.text = "FULLY UPGRADED"
		upgrade_btn.disabled = true

func _on_upgrade_pressed():
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		main_node.rpc_id(1, "request_upgrade_base_radar")
		close_terminal()
