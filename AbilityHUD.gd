extends Control

@onready var ability_container: HBoxContainer = $HBoxContainer

# Caches panel and label references to prevent dynamic lookups every frame
@onready var slot1_panel: PanelContainer = $HBoxContainer/Slot1
@onready var slot1_key: Label = $HBoxContainer/Slot1/Margin/VBox/KeyLabel
@onready var slot1_name: Label = $HBoxContainer/Slot1/Margin/VBox/NameLabel
@onready var slot1_cost: Label = $HBoxContainer/Slot1/Margin/VBox/CostLabel

@onready var slot2_panel: PanelContainer = $HBoxContainer/Slot2
@onready var slot2_key: Label = $HBoxContainer/Slot2/Margin/VBox/KeyLabel
@onready var slot2_name: Label = $HBoxContainer/Slot2/Margin/VBox/NameLabel
@onready var slot2_cost: Label = $HBoxContainer/Slot2/Margin/VBox/CostLabel

@onready var slot3_panel: PanelContainer = get_node_or_null("HBoxContainer/Slot3")
@onready var slot3_key: Label = get_node_or_null("HBoxContainer/Slot3/Margin/VBox/KeyLabel")
@onready var slot3_name: Label = get_node_or_null("HBoxContainer/Slot3/Margin/VBox/NameLabel")
@onready var slot3_cost: Label = get_node_or_null("HBoxContainer/Slot3/Margin/VBox/CostLabel")

@onready var slot4_panel: PanelContainer = get_node_or_null("HBoxContainer/Slot4")
@onready var slot4_key: Label = get_node_or_null("HBoxContainer/Slot4/Margin/VBox/KeyLabel")
@onready var slot4_name: Label = get_node_or_null("HBoxContainer/Slot4/Margin/VBox/NameLabel")
@onready var slot4_cost: Label = get_node_or_null("HBoxContainer/Slot4/Margin/VBox/CostLabel")

@onready var slot5_panel: PanelContainer = get_node_or_null("HBoxContainer/Slot5")
@onready var slot5_key: Label = get_node_or_null("HBoxContainer/Slot5/Margin/VBox/KeyLabel")
@onready var slot5_name: Label = get_node_or_null("HBoxContainer/Slot5/Margin/VBox/NameLabel")
@onready var slot5_cost: Label = get_node_or_null("HBoxContainer/Slot5/Margin/VBox/CostLabel")

var local_player: Node2D = null

# Throttling timer variables to avoid heavy per-frame string formatting/node checks
var update_accumulator: float = 0.0
const UPDATE_INTERVAL: float = 0.15 # Updates HUD ~6-7 times a second instead of every frame

func _ready():
	hide()
	set_process(true)

func setup_hud_for_player(player_node: Node2D):
	local_player = player_node
	show()
	update_hud_layout()

func _process(delta):
	if not is_instance_valid(local_player):
		hide()
		return
		
	update_accumulator += delta
	if update_accumulator >= UPDATE_INTERVAL:
		update_accumulator = 0.0
		refresh_hud_display()

func refresh_hud_display():
	var main_node = get_tree().get_first_node_in_group("main")
	var current_requisition = 0
	var current_scrap = 0
	
	if main_node:
		if "requisition_amount" in main_node: current_requisition = main_node.requisition_amount
		elif "requisition" in main_node: current_requisition = main_node.requisition
		elif main_node.has_method("get_requisition"): current_requisition = main_node.get_requisition()
		
		if "scrap_amount" in main_node: current_scrap = main_node.scrap_amount
		elif "scrap" in main_node: current_scrap = main_node.scrap

	# --- TECH-PRIEST ENGINSEER HUD ---
	if local_player.current_class == local_player.PlayerClass.MELEE:
		var selected_type = local_player.selected_building_type
		var costs = local_player.BUILDING_COSTS # [15, 25, 35]
		
		# Slot 1: Primary Attack [LMB]
		if slot1_panel:
			slot1_panel.show()
			slot1_key.text = "[LMB]Omnissian Axe"
			slot1_name.text = "Melee attack"
			slot1_cost.text = "40 DMG Melee Arc"
			slot1_panel.modulate = Color.WHITE

		# Slot 2: Barricade [1]
		if slot2_panel:
			slot2_panel.show()
			slot2_key.text = "[1] Barricade"
			slot2_name.text = "Blocks enemy path"
			slot2_cost.text = "Cost: " + str(costs[0]) + " Scrap"
			if local_player.is_building_mode and selected_type == 0:
				slot2_panel.modulate = Color("#3182ce")
			else:
				slot2_panel.modulate = Color.WHITE if current_scrap >= costs[0] else Color("#718096")

		# Slot 3: Generator [2]
		if slot3_panel:
			slot3_panel.show()
			slot3_key.text = "[2] Generator"
			slot3_name.text = "Generates Requisiton"
			slot3_cost.text = "Cost: " + str(costs[1]) + " Scrap"
			if local_player.is_building_mode and selected_type == 1:
				slot3_panel.modulate = Color("#3182ce")
			else:
				slot3_panel.modulate = Color.WHITE if current_scrap >= costs[1] else Color("#718096")

		# Slot 4: Turret [3]
		if slot4_panel:
			slot4_panel.show()
			slot4_key.text = "[3] Turret"
			slot4_name.text = "Auto-fires at enemies"
			
			# Define costs matching Main.gd
			var turret_scrap_cost = costs[2] # 35
			var turret_req_cost = 5         # Adjust this to match your desired Req cost
			
			slot4_cost.text = "Cost: " + str(turret_scrap_cost) + " Scrap + " + str(turret_req_cost) + " Req"
			
			if local_player.is_building_mode and selected_type == 2:
				slot4_panel.modulate = Color("#3182ce")
			else:
				# Check if player has *both* resources available
				var has_enough = (current_scrap >= turret_scrap_cost and current_requisition >= turret_req_cost)
				slot4_panel.modulate = Color.WHITE if has_enough else Color("#718096")

		# Slot 5: Servo-Skull Companion [K]
		if slot5_panel:
			slot5_panel.show()
			slot5_key.text = "[K] Servo-Skull"
			slot5_name.text = "Augmetic Recon Skull"
			
			# Define your servo-skull resource costs (adjust as balanced for your game)
			var skull_scrap_cost = 20
			var skull_req_cost = 10
			
			slot5_cost.text = "Cost: " + str(skull_scrap_cost) + " Scrap + " + str(skull_req_cost) + " Req"
			
			# Check if player has enough resources
			var has_enough_skull = (current_scrap >= skull_scrap_cost and current_requisition >= skull_req_cost)
			slot5_panel.modulate = Color.WHITE if has_enough_skull else Color("#718096")

	# --- SKITARII MARSHAL HUD ---
	elif local_player.current_class == local_player.PlayerClass.RANGED:
		# Slot 1: Primary Attack [LMB]
		if slot1_panel:
			slot1_panel.show()
			slot1_key.text = "[LMB]"
			slot1_name.text = "Radium Carbine"
			slot1_cost.text = str(local_player.bullet_damage) + " DMG Ranged Shot\nFree"
			slot1_panel.modulate = Color.WHITE

		# Slot 2: Bodyguards [N]
		if slot2_panel:
			slot2_panel.show()
			slot2_key.text = "[N] Bodyguard"
			var current_lvl = local_player.bodyguard_level
			if current_lvl >= 2:
				slot2_name.text = "2/2 Active guards"
				slot2_cost.text = "MAXED"
				slot2_panel.modulate = Color("#4a5568")
			else:
				slot2_name.text = "Fights by your side"
				slot2_cost.text = "Cost: " + str(local_player.bodyguard_cost) + " Req (" + str(current_lvl) + "/2)"
				slot2_panel.modulate = Color.WHITE if current_requisition >= local_player.bodyguard_cost else Color("#718096")

		# Slot 3: Damage Upgrade [M]
		if slot3_panel:
			slot3_panel.show()
			slot3_key.text = "[M] Damage"
			var dmg_lvl = local_player.damage_upgrade_level
			if dmg_lvl >= local_player.MAX_DAMAGE_UPGRADES:
				slot3_name.text = "Max weapon damage"
				slot3_cost.text = "MAXED"
				slot3_panel.modulate = Color("#4a5568")
			else:
				slot3_name.text = "+10 Weapon DMG"
				slot3_cost.text = "Cost: " + str(local_player.damage_upgrade_cost) + " Req (Lvl " + str(dmg_lvl) + "/" + str(local_player.MAX_DAMAGE_UPGRADES) + ")"
				slot3_panel.modulate = Color.WHITE if current_requisition >= local_player.damage_upgrade_cost else Color("#718096")

		# Slot 4: Speed Upgrade [V]
		if slot4_panel:
			slot4_panel.show()
			slot4_key.text = "[V] Speed"
			var spd_lvl = local_player.speed_upgrade_level
			if spd_lvl >= local_player.MAX_SPEED_UPGRADES:
				slot4_name.text = "Max movement speed"
				slot4_cost.text = "MAXED"
				slot4_panel.modulate = Color("#4a5568")
			else:
				slot4_name.text = "+35 Movement Speed"
				slot4_cost.text = "Cost: " + str(local_player.speed_upgrade_cost) + " Req (Lvl " + str(spd_lvl) + "/" + str(local_player.MAX_SPEED_UPGRADES) + ")"
				slot4_panel.modulate = Color.WHITE if current_requisition >= local_player.speed_upgrade_cost else Color("#718096")

func update_hud_layout():
	if not is_instance_valid(local_player): return
	# Force an immediate evaluation frame
	refresh_hud_display()
