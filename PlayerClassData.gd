class_name PlayerClassData
extends Resource

@export_category("Visuals & UI")
@export var class_name_text: String = "Tech-Priest"
@export var unit_type_id: int = 0 # 0 for Melee/Tech-Priest, 1 for Ranged/Marshal

@export_category("Base Stats")
@export var max_health: int = 100
@export var movement_speed: float = 300.0

@export_category("Combat Stats")
@export var attack_cooldown: float = 0.4
@export var base_damage: int = 20
@export var attack_anim_duration: float = 0.2
