extends Control
class_name TurretUpgradeUI

const GameData = preload("res://GameData.gd")

var panel_container: PanelContainer = null
var cards_container: HBoxContainer = null
var target_turret: Node2D = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("turret_upgrade_ui")
	theme = AdmechTheme.make()
	hide()
	_build_ui_layout()

func _build_ui_layout():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.65)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(860, 340)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(pc)
	panel_container = pc

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel_container.add_child(vbox)

	var title = Label.new()
	title.text = "◆ SANCTIFY OMNISSIAN WEAPON PROTOCOL ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var sub_title = Label.new()
	sub_title.text = "Select an advanced battlefield specialization for this fortified battery:"
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_title.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	sub_title.add_theme_font_size_override("font_size", 11)
	vbox.add_child(sub_title)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(hbox)
	cards_container = hbox

	var close_btn = Button.new()
	close_btn.text = "CANCEL PROTOCOL [ESC / E]"
	close_btn.custom_minimum_size = Vector2(220, 32)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close_modal)
	vbox.add_child(close_btn)

func open_modal(turret_node: Node2D):
	target_turret = turret_node
	show()
	_refresh_cards()

func close_modal():
	hide()
	target_turret = null

func _process(_delta: float):
	if visible:
		var local_player = _get_local_player()
		if not is_instance_valid(target_turret) or not is_instance_valid(local_player) or local_player.global_position.distance_to(target_turret.global_position) > 130.0:
			close_modal()
			return

func _unhandled_input(event: InputEvent):
	if not visible: return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1 or event.keycode == KEY_KP_1:
			_select_spec(GameData.TurretSpec.COGNIS_FLAK)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_2 or event.keycode == KEY_KP_2:
			_select_spec(GameData.TurretSpec.VOLKITE_CULVERIN)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_3 or event.keycode == KEY_KP_3:
			_select_spec(GameData.TurretSpec.ARC_BLASTER)
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ESCAPE, KEY_E]:
			close_modal()
			get_viewport().set_input_as_handled()

func _refresh_cards():
	if not visible or cards_container == null: return
	for child in cards_container.get_children():
		child.queue_free()

	var main_node = get_tree().get_first_node_in_group("main")
	var cur_req = main_node.requisition_amount if main_node else 0

	for spec_id in [GameData.TurretSpec.COGNIS_FLAK, GameData.TurretSpec.VOLKITE_CULVERIN, GameData.TurretSpec.ARC_BLASTER]:
		var info = GameData.TURRET_SPEC_INFO[spec_id]
		var card = _create_spec_card(spec_id, info, cur_req)
		cards_container.add_child(card)

func _create_spec_card(spec_id: int, info: Dictionary, cur_req: int) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(245, 210)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var header = Label.new()
	header.text = "[%s] %s %s" % [info.hotkey, info.icon, info.name]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	header.add_theme_font_size_override("font_size", 13)
	vbox.add_child(header)

	var role_lbl = Label.new()
	role_lbl.text = info.role
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.20))
	role_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(role_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = info.desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(desc_lbl)

	var cost_lbl = Label.new()
	cost_lbl.text = "⚡ %d REQUISITION" % GameData.TURRET_SPEC_REQ_COST
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_color_override("font_color", Color(0.35, 0.90, 1.0) if cur_req >= GameData.TURRET_SPEC_REQ_COST else Color(0.90, 0.25, 0.20))
	cost_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(cost_lbl)

	var btn = Button.new()
	btn.text = "COMMISSION [%s]" % info.hotkey
	btn.disabled = (cur_req < GameData.TURRET_SPEC_REQ_COST)
	btn.custom_minimum_size = Vector2(0, 30)
	btn.pressed.connect(func(): _select_spec(spec_id))
	vbox.add_child(btn)

	return card

func _select_spec(spec_id: int):
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and is_instance_valid(target_turret):
		main_node.rpc_id(1, "request_specialize_turret", target_turret.name, spec_id)
		close_modal()

func _get_local_player() -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and ((not multiplayer.has_multiplayer_peer()) or p.is_multiplayer_authority()):
			return p
	return null
