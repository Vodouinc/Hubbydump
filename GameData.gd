class_name GameData
extends RefCounted

enum StructureType {
	BARRICADE = 0,
	GENERATOR = 1,
	TURRET = 2,
	MANUFACTORUM = 3,
	DISTRIBUTOR = 4,
	NOOSPHERE_ANTENNA = 5,
	RESEARCH_SHRINE = 6,
	CYBERNETICA_FORGE = 7
}

enum TurretSpec {
	NONE = 0,
	COGNIS_FLAK = 1,
	VOLKITE_CULVERIN = 2,
	ARC_BLASTER = 3
}

enum BaseRadarTier {
	NONE = 0,
	TIER_1_CARTOGRAPH = 1,
	TIER_2_AUSPEX = 2,
	TIER_3_NOOSPHERE = 3
}

enum CohortUnitType {
	VANGUARD = 0,
	RANGER = 1,
	RUSTSTALKER = 2,
	KASTELAN = 3,
	KATAPHRON = 4
}

const BASE_COHORT_CAP: int = 12

const COHORT_UNITS: Dictionary = {
	CohortUnitType.VANGUARD: {
		"id": CohortUnitType.VANGUARD,
		"name": "Skitarii Vanguard",
		"icon": "☣️",
		"scrap": 0,
		"req": 10,
		"pop": 1,
		"build_time": 4.0,
		"hp": 90,
		"speed": 220.0,
		"damage": 18,
		"range": 280.0,
		"desc": "Rad-carbine shock trooper. Emits an aura that weakens enemy armor and slows swarms.",
		"flavor": "\"Their bodies burn with sacred rad-fallout, decaying all who oppose the Machine Cult.\""
	},
	CohortUnitType.RANGER: {
		"id": CohortUnitType.RANGER,
		"name": "Skitarii Ranger",
		"icon": "🎯",
		"scrap": 0,
		"req": 15,
		"pop": 1,
		"build_time": 5.0,
		"hp": 75,
		"speed": 200.0,
		"damage": 45,
		"range": 440.0,
		"desc": "Long-range Galvanic marksman. Prioritizes Gretchin thieves and high-threat Stormboyz.",
		"flavor": "\"Patient hunters of Mars. Their galvanic rounds never fail their telemetry.\""
	},
	CohortUnitType.RUSTSTALKER: {
		"id": CohortUnitType.RUSTSTALKER,
		"name": "Sicarian Ruststalker",
		"icon": "⚔️",
		"scrap": 10,
		"req": 25,
		"pop": 2,
		"build_time": 7.0,
		"hp": 160,
		"speed": 280.0,
		"damage": 55,
		"range": 45.0,
		"desc": "High-speed cybernetic assassin wielding vibrating transonic blades. Cleaves tough targets.",
		"flavor": "\"A blur of bladed limbs and screaming soundwaves that slice flesh at a molecular level.\""
	},
	CohortUnitType.KASTELAN: {
		"id": CohortUnitType.KASTELAN,
		"name": "Kastelan Battle-Automata",
		"icon": "🤖",
		"scrap": 30,
		"req": 45,
		"pop": 3,
		"build_time": 12.0,
		"hp": 750,
		"speed": 150.0,
		"damage": 80,
		"range": 300.0,
		"desc": "Heavy siege automata. Projects 360° refractor bubble shield in Anchor Mode.",
		"flavor": "\"Ten millennia of continuous slaughter encoded upon sacred phosphor wafer-discs.\""
	},
	CohortUnitType.KATAPHRON: {
		"id": CohortUnitType.KATAPHRON,
		"name": "Kataphron Breacher",
		"icon": "🚜",
		"scrap": 25,
		"req": 40,
		"pop": 3,
		"build_time": 10.0,
		"hp": 520,
		"speed": 130.0,
		"damage": 65,
		"range": 260.0,
		"desc": "Treaded combat platform with Heavy Arc Rifle. Deals +100% bonus damage to enemy structures.",
		"flavor": "\"Living cybernetic battering rams engineered to breach fortified fortress gates.\""
	}
}

const STRUCTURE_INFO: Dictionary = {
	StructureType.BARRICADE: {
		"name": "Barricade",
		"key": "1",
		"scrap": 15,
		"req": 0,
		"max_hp": 150,
		"size": Vector2(32, 32),
		"requires_industrial": false
	},
	StructureType.DISTRIBUTOR: {
		"name": "Distributor",
		"key": "2",
		"scrap": 20,
		"req": 0,
		"max_hp": 80,
		"size": Vector2(20, 20),
		"requires_industrial": false
	},
	StructureType.GENERATOR: {
		"name": "Generator",
		"key": "3",
		"scrap": 25,
		"req": 0,
		"max_hp": 100,
		"size": Vector2(48, 48),
		"requires_industrial": true
	},
	StructureType.TURRET: {
		"name": "Turret",
		"key": "4",
		"scrap": 35,
		"req": 5,
		"max_hp": 90,
		"size": Vector2(36, 36),
		"requires_industrial": false
	},
	StructureType.MANUFACTORUM: {
		"name": "Scrap Foundry",
		"key": "5",
		"scrap": 30,
		"req": 5,
		"max_hp": 220,
		"size": Vector2(56, 56),
		"requires_deposit": true,
		"requires_industrial": false
	},
	StructureType.RESEARCH_SHRINE: {
		"name": "Tech Shrine",
		"key": "6",
		"scrap": 40,
		"req": 15,
		"max_hp": 200,
		"size": Vector2(56, 56),
		"requires_industrial": true
	},
	StructureType.CYBERNETICA_FORGE: {
		"name": "Cybernetica Manufactorum",
		"key": "7",
		"scrap": 50,
		"req": 20,
		"max_hp": 350,
		"size": Vector2(64, 64),
		"requires_industrial": true
	},
	StructureType.NOOSPHERE_ANTENNA: {
		"name": "Antenna",
		"key": "",
		"scrap": 0,
		"req": 0,
		"max_hp": 120,
		"size": Vector2(20, 20),
		"requires_industrial": false
	}
}

const TURRET_UPGRADE_COSTS: Array[int] = [10, 20, 35]
const TURRET_DAMAGE_BY_LEVEL: Array[int] = [12, 16, 22, 30]
const TURRET_FIRE_INTERVALS: Array[float] = [0.45, 0.36, 0.28, 0.22]
const TURRET_RANGE_BY_LEVEL: Array[float] = [260.0, 285.0, 315.0, 350.0]

const TURRET_SPEC_REQ_COST: int = 35
const TURRET_SPEC_INFO: Dictionary = {
	TurretSpec.COGNIS_FLAK: {
		"name": "Cognis Gatling Flak",
		"icon": "⚙️",
		"hotkey": "1",
		"role": "High-RPM Anti-Swarm & Air Shredder",
		"desc": "Fires hyper-velocity dual kinetic tracers (11 shots/sec) that pulverize hordes and airborne Stormboyz.",
		"fire_interval": 0.09,
		"damage": 14,
		"range": 340.0
	},
	TurretSpec.VOLKITE_CULVERIN: {
		"name": "Volkite Culverin",
		"icon": "🔴",
		"hotkey": "2",
		"role": "Piercing Thermal Anti-Armor Ray",
		"desc": "Emits an incinerating thermal beam (90 DMG) every 1.2s that penetrates through all enemies in a line.",
		"fire_interval": 1.20,
		"damage": 90,
		"range": 380.0
	},
	TurretSpec.ARC_BLASTER: {
		"name": "Heavy Arc Blaster",
		"icon": "⚡",
		"hotkey": "3",
		"role": "Chain Lightning & EMP Crowd Control",
		"desc": "Discharges electrified arcs (45 DMG) that chain to 2 nearby enemies (30 DMG) with an EMP stun.",
		"fire_interval": 0.55,
		"damage": 45,
		"range": 320.0
	}
}

const GATE_UPGRADE_SCRAP: int = 10
const GATE_UPGRADE_REQ: int = 5
const ANTENNA_UPGRADE_REQ: int = 15

const SERVO_SKULL_SCRAP_COST: int = 20
const SERVO_SKULL_REQ_COST: int = 10
const MAX_SERVO_SKULLS: int = 2

const ORBITAL_REQ_COST: int = 50
const ORBITAL_COOLDOWN_MAX: float = 45.0

const BODYGUARD_REQ_COST: int = 5
const MAX_BODYGUARDS: int = 4

enum GuardRole {
	RANGER_SNIPER = 0,
	SICARIAN_MELEE = 1,
	VANGUARD_RAD_TROOPER = 2
}

const BODYGUARD_ROSTER: Dictionary = {
	GuardRole.RANGER_SNIPER: {
		"id": GuardRole.RANGER_SNIPER,
		"name": "Skitarii Ranger",
		"sub": "Galvanic Sniper Cadre",
		"icon": "🎯",
		"scrap": 15,
		"req": 5,
		"hp": 110,
		"speed": 260.0,
		"damage": 55,
		"range": 580.0,
		"desc": "Long-range marksman wielding a Galvanic Arquebus. Snipes high-value threats from safety; deploys bipod when holding ground.",
		"flavor": "\"Their targeting telemetry is sanctified in holy oil; they never miss the xeno spark.\""
	},
	GuardRole.SICARIAN_MELEE: {
		"id": GuardRole.SICARIAN_MELEE,
		"name": "Sicarian Ruststalker",
		"sub": "Cybernetic Assassin",
		"icon": "⚔️",
		"scrap": 20,
		"req": 10,
		"hp": 175,
		"speed": 320.0,
		"damage": 45,
		"range": 240.0,
		"desc": "High-velocity cybernetic assassin on digitigrade bionic stilts. Charges into melee and cleaves swarms with vibrating transonic blades.",
		"flavor": "\"A blur of blades and screaming soundwaves that cleave organic flesh at a molecular level.\""
	},
	GuardRole.VANGUARD_RAD_TROOPER: {
		"id": GuardRole.VANGUARD_RAD_TROOPER,
		"name": "Skitarii Vanguard",
		"sub": "Rad-Shock Infantry",
		"icon": "☣️",
		"scrap": 10,
		"req": 5,
		"hp": 130,
		"speed": 280.0,
		"damage": 22,
		"range": 380.0,
		"desc": "Frontline shock trooper with a rapid-fire Radium Carbine. Emits a passive rad-fallout aura that decays enemy armor and slows runners.",
		"flavor": "\"Their bodies burn with sacred rad-fallout, withering any heretic who draws near.\""
	}
}

const DAMAGE_UPGRADE_REQ_COST: int = 10
const MAX_DAMAGE_UPGRADES: int = 3

const SPEED_UPGRADE_REQ_COST: int = 10
const MAX_SPEED_UPGRADES: int = 3

const ORK_CITADEL_MAX_HEALTH: int = 2500
const ORK_SCRAP_HEAP_MAX_HEALTH: int = 400

const SANCTUM_TECH: Array[Dictionary] = [
	{
		"id": 0,
		"name": "Omnissian Cartograph",
		"icon": "🗺️",
		"scrap": 25,
		"req": 10,
		"desc": "Unlocks the Tactical Minimap scope and Fullscreen Battlefield Map [M] tracking friendly outposts and ore deposits.",
		"flavor": "\"Chart the wasteland, that the tread of our cohorts may find sure footing in the dust.\""
	},
	{
		"id": 1,
		"name": "WAAAGH! Psychic Interceptor",
		"icon": "🔥",
		"scrap": 30,
		"req": 15,
		"desc": "Calibrates auspex receivers to the xeno psychic wavelength, displaying active WAAAGH! field buffs and totem telemetry by the minimap.",
		"flavor": "\"The psychic gestalt of the greenskins burns across the ether. Intercept their profane frequency.\""
	},
	{
		"id": 2,
		"name": "Long-Range Auspex Array",
		"icon": "📡",
		"scrap": 45,
		"req": 25,
		"desc": "Enables the 8-second assault warning vector system and adds periodic radar sweeps revealing hostile positions.",
		"flavor": "\"No foe moves in the shadow where the piercing gaze of the Omnissiah falls.\""
	},
	{
		"id": 3,
		"name": "Noospheric Global Uplink",
		"icon": "👁️",
		"scrap": 70,
		"req": 50,
		"desc": "Continuous real-time tracking of all hostiles, WAAAGH! Totems, and the Ork Warboss Citadel across the entire planet.",
		"flavor": "\"All data is sacred. When the Noosphere encompasses the world, victory is pre-ordained.\""
	}
]

const TECH_DATA: Array[Dictionary] = [
	{
		"id": 0,
		"name": "Aegis Refractor Shields",
		"cost": 20,
		"rune": "🛡️",
		"desc": "Generates a regenerating blue energy shield (40% max HP) on all structures connected to the Noosphere."
	},
	{
		"id": 1,
		"name": "Necro-Mechanic Nanobots",
		"cost": 35,
		"rune": "🔧",
		"desc": "Sacred nanobot swarms slowly self-repair (3.5 HP/sec) all damaged Noosphere structures when out of combat."
	},
	{
		"id": 2,
		"name": "Galvanic Scrap Siphon",
		"cost": 20,
		"rune": "🧲",
		"desc": "Expands magnetic scrap retrieval range of Distributors & Antennas by +75% (220px -> 385px)."
	},
	{
		"id": 3,
		"name": "Electrified Aegis Mesh",
		"cost": 25,
		"rune": "⚡",
		"desc": "Noosphere-connected Barricades & Gates electrify with active arcs, shocking melee attackers for 12 DPS."
	},
	{
		"id": 4,
		"name": "Adamantine Spikes & Mantlets",
		"cost": 25,
		"rune": "⚔️",
		"desc": "Barricades sprout recoil spikes (18 DMG to melee attackers) and grant -35% ranged damage reduction."
	},
	{
		"id": 5,
		"name": "Servitor Noosphere Targeting Uplink",
		"cost": 30,
		"rune": "👁️",
		"desc": "Hardwires turret servitors into the Noosphere. Batteries prioritize priority targets and painted enemies."
	}
]
