extends Control
class_name CyberneticaUI

var panel_container: PanelContainer = null
var unit_cards_container: HBoxContainer = null
var queue_container: HBoxContainer = null
var res_summary_label: Label = null
var pop_label: Label = null
var rally_label: Label = null
var active_forge_node: Node2D = null

var last_cached_queue: Array = []
var last_cached_timer: float = -1.0

var cached_scrap: int = -1
var cached_req: int = -1
var cached_pop: int = -1

func _ready():
	add_to_group("cybernetica_ui")
	theme = AdmechTheme.make()
	hide()
	_build_ui_layout()

func _build_ui_layout():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	pc.custom_minimum_size = Vector2(820, 480)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(pc)
	panel_container = pc

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	panel_container.add_child(root_vbox)

	var title = Label.new()
	title.text = "◆ LEGIO CYBERNETICA & COHORT FABRICATION TERMINAL ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	title.add_theme_font_size_override("font_size", 15)
	root_vbox.add_child(title)

	var sub_bar = HBoxContainer.new()
	sub_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_bar.add_theme_constant_override("separation", 24)
	root_vbox.add_child(sub_bar)

	res_summary_label = Label.new()
	res_summary_label.text = "⚙ SCRAP: 40   ⚡ REQ: 10"
	res_summary_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
	res_summary_label.add_theme_font_size_override("font_size", 11)
	sub_bar.add_child(res_summary_label)

	pop_label = Label.new()
	pop_label.text = "🤖 COHORT: 0 / 12"
	pop_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	pop_label.add_theme_font_size_override("font_size", 11)
	sub_bar.add_child(pop_label)

	rally_label = Label.new()
	rally_label.text = "🚩 RALLY: ACTIVE"
	rally_label.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	rally_label.add_theme_font_size_override("font_size", 11)
	sub_bar.add_child(rally_label)

	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.25, 0.28, 0.35, 0.6)
	root_vbox.add_child(sep)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	unit_cards_container = HBoxContainer.new()
	unit_cards_container.add_theme_constant_override("separation", 10)
	unit_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(unit_cards_container)

	var queue_title = Label.new()
	queue_title.text = "◆ ACTIVE MANUFACTURING FABRICATION QUEUE (MAX 5) ◆"
	queue_title.add_theme_font_size_override("font_size", 10)
	queue_title.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
	root_vbox.add_child(queue_title)

	queue_container = HBoxContainer.new()
	queue_container.add_theme_constant_override("separation", 8)
	queue_container.custom_minimum_size = Vector2(0, 48)
	root_vbox.add_child(queue_container)

	var bottom_bar = HBoxContainer.new()
	bottom_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(bottom_bar)

	var close_btn = Button.new()
	close_btn.text = "DISENGAGE TERMINAL [ESC / E]"
	close_btn.custom_minimum_size = Vector2(240, 32)
	close_btn.pressed.connect(close_terminal)
	bottom_bar.add_child(close_btn)

func open_terminal(forge_node: Node2D):
	active_forge_node = forge_node
	show()
	_refresh_display()

func close_terminal():
	hide()
	active_forge_node = null

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ESCAPE, KEY_E]:
			close_terminal()
			get_viewport().set_input_as_handled()

func _process(_delta: float):
	if not visible or not is_instance_valid(active_forge_node): return

	var main_node = get_tree().get_first_node_in_group("main")
	var cur_scrap = main_node.scrap_amount if main_node and "scrap_amount" in main_node else 0
	var cur_req = main_node.requisition_amount if main_node and "requisition_amount" in main_node else 0
	var cur_pop = main_node.get_cohort_population() if main_node and main_node.has_method("get_cohort_population") else 0

	# Real-time resource header updates
	if res_summary_label:
		res_summary_label.text = "⚙ SCRAP: %d   ⚡ REQUISITION: %d" % [cur_scrap, cur_req]
	if pop_label:
		pop_label.text = "🤖 COHORT: %d / %d" % [cur_pop, GameData.BASE_COHORT_CAP]

	# Auto-refresh card buttons as resources/pop change
	if cur_scrap != cached_scrap or cur_req != cached_req or cur_pop != cached_pop:
		cached_scrap = cur_scrap
		cached_req = cur_req
		cached_pop = cur_pop
		_refresh_display()

	# FIX: Only update queue UI if queue array or rounded timer changes
	var q: Array = active_forge_node.production_queue if "production_queue" in active_forge_node else []
	var cur_timer: float = active_forge_node.production_timer if "production_timer" in active_forge_node else 0.0
	if q != last_cached_queue or abs(cur_timer - last_cached_timer) > 0.05:
		last_cached_queue = q.duplicate()
		last_cached_timer = cur_timer
		_refresh_queue_display()

func _refresh_display():
	if not visible or not is_instance_valid(active_forge_node): return

	var main_node = get_tree().get_first_node_in_group("main")
	var cur_scrap = main_node.scrap_amount if main_node and "scrap_amount" in main_node else 0
	var cur_req = main_node.requisition_amount if main_node and "requisition_amount" in main_node else 0
	var current_pop = main_node.get_cohort_population() if main_node and main_node.has_method("get_cohort_population") else 0

	for c in unit_cards_container.get_children():
		c.queue_free()

	for u_type in GameData.COHORT_UNITS.keys():
		var data = GameData.COHORT_UNITS[u_type]
		var card = _create_unit_card(data, cur_scrap, cur_req, current_pop)
		unit_cards_container.add_child(card)

	_refresh_queue_display()

func _create_unit_card(data: Dictionary, cur_scrap: int, cur_req: int, cur_pop: int) -> PanelContainer:
	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(150, 220)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.94)
	sb.border_color = Color(0.24, 0.28, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	pc.add_child(vbox)

	var icon_lbl = Label.new()
	icon_lbl.text = "%s %s" % [data.icon, data.name]
	icon_lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
	icon_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(icon_lbl)

	var cost_parts: Array[String] = []
	if data.scrap > 0: cost_parts.append("⚙ %d" % data.scrap)
	if data.req > 0: cost_parts.append("⚡ %d" % data.req)
	cost_parts.append("👥 %d" % data.pop)
	cost_parts.append("⏱ %.0fs" % data.build_time)

	var cost_lbl = Label.new()
	cost_lbl.text = " ".join(cost_parts)
	var can_afford = (cur_scrap >= data.scrap and cur_req >= data.req and (cur_pop + data.pop <= GameData.BASE_COHORT_CAP))
	cost_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45) if can_afford else Color(0.92, 0.22, 0.18))
	cost_lbl.add_theme_font_size_override("font_size", 9)
	vbox.add_child(cost_lbl)

	var stats_lbl = Label.new()
	stats_lbl.text = "HP: %d | DMG: %d | SPD: %d" % [data.hp, data.damage, int(data.speed)]
	stats_lbl.add_theme_color_override("font_color", Color(0.82, 0.62, 0.24))
	stats_lbl.add_theme_font_size_override("font_size", 9)
	vbox.add_child(stats_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = data.desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	desc_lbl.add_theme_font_size_override("font_size", 9)
	vbox.add_child(desc_lbl)

	var btn = Button.new()
	btn.text = "FABRICATE"
	btn.custom_minimum_size = Vector2(0, 24)
	btn.disabled = not can_afford
	btn.pressed.connect(func(): _on_fabricate_pressed(data.id))
	vbox.add_child(btn)

	return pc

func _on_fabricate_pressed(unit_type_id: int):
	if is_instance_valid(active_forge_node):
		var main_node = get_tree().get_first_node_in_group("main")
		if (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server():
			# Execute directly on Host/Singleplayer
			if active_forge_node.has_method("try_queue_unit"):
				active_forge_node.try_queue_unit(unit_type_id)
		else:
			# Send RPC from Client to Server
			if main_node:
				main_node.rpc_id(1, "request_queue_cohort_unit", active_forge_node.name, unit_type_id)
		_refresh_display()

func _refresh_queue_display():
	if not visible or not is_instance_valid(active_forge_node): return
	
	var q: Array = active_forge_node.production_queue if "production_queue" in active_forge_node else []
	var cur_timer: float = active_forge_node.production_timer if "production_timer" in active_forge_node else 0.0

	for c in queue_container.get_children():
		c.queue_free()

	for i in range(5):
		var slot = PanelContainer.new()
		slot.custom_minimum_size = Vector2(148, 44)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.09, 0.92)
		sb.border_color = Color(0.24, 0.28, 0.35)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		slot.add_theme_stylebox_override("panel", sb)

		if i < q.size():
			var u_id = q[i]
			var data = GameData.COHORT_UNITS.get(u_id, {})
			var slot_vbox = VBoxContainer.new()
			slot_vbox.add_theme_constant_override("separation", 2)
			slot.add_child(slot_vbox)

			var lbl = Label.new()
			lbl.text = "%s %s" % [data.get("icon", ""), data.get("name", "")]
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0))
			slot_vbox.add_child(lbl)

			if i == 0:
				var pbar = ProgressBar.new()
				pbar.custom_minimum_size = Vector2(0, 8)
				pbar.max_value = data.get("build_time", 5.0)
				pbar.value = cur_timer
				pbar.show_percentage = false
				slot_vbox.add_child(pbar)
			else:
				var queued_lbl = Label.new()
				queued_lbl.text = "QUEUED #%d" % (i + 1)
				queued_lbl.add_theme_font_size_override("font_size", 8)
				queued_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
				slot_vbox.add_child(queued_lbl)
		else:
			var empty_lbl = Label.new()
			empty_lbl.text = "SLOT %d: IDLE" % (i + 1)
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty_lbl.add_theme_font_size_override("font_size", 9)
			empty_lbl.add_theme_color_override("font_color", Color(0.35, 0.40, 0.45))
			slot.add_child(empty_lbl)

		queue_container.add_child(slot)
