## TacticalSiegeResolver — Multi-phase tactical siege combat engine (TS-01).
##
## Replaces single-tick blind dice rolls with interactive, multi-stage
## breach phases (Outer Gate -> Courtyard -> Keep) featuring tactical stances,
## risk-adjusted casualty choices, captain duels, and orderly retreats.
## Integrates with CovertOpsSystem for clandestine sabotage advantages.
class_name TacticalSiegeResolver
extends RefCounted

enum Phase {
	OUTER_GATE = 0,
	COURTYARD = 1,
	KEEP = 2,
	COMPLETED = 3
}

enum SiegeStatus {
	NOT_STARTED = 0,
	IN_PROGRESS = 1,
	VICTORY = 2,
	REPELLED = 3,
	RETREATED = 4
}

# Phase Names
const PHASE_NAMES := {
	Phase.OUTER_GATE: "Outer Gate",
	Phase.COURTYARD: "Courtyard Melee",
	Phase.KEEP: "The Keep",
	Phase.COMPLETED: "Resolved"
}

# State fields
var status: SiegeStatus = SiegeStatus.NOT_STARTED
var current_phase: Phase = Phase.OUTER_GATE

var initial_army_power: int = 0
var current_army_power: int = 0
var total_garrison_power: int = 0

var phase_defender_max_hp: int = 0
var phase_defender_hp: int = 0

var casualties_suffered: int = 0
var combat_log: Array[Dictionary] = []
var covert_bonuses: Dictionary = {}

var _engine: SimEngine


func _init(engine: SimEngine = null) -> void:
	_engine = engine


## Begins a new tactical siege engagement against the castle garrison.
func start_siege(engine: SimEngine, covert_system = null) -> Dictionary:
	_engine = engine
	var units = engine.get_system(&"units")
	var assault = engine.get_system(&"assault")

	var raw_army: int = units.army_power() if units != null else 0
	var garrison_target: int = 60
	if assault != null and assault.has_method("assault_odds"):
		var odds_info: Dictionary = assault.assault_odds(engine)
		var garrison_dict: Dictionary = odds_info.get("garrison", {})
		garrison_target = int(garrison_dict.get("base_power", 60))
		var army_dict: Dictionary = odds_info.get("army", {})
		raw_army = int(army_dict.get("power", raw_army))

	covert_bonuses.clear()
	if covert_system != null and covert_system.has_method("get_bonuses"):
		covert_bonuses = covert_system.get_bonuses()

	# Clandestine sabotage modifiers
	if bool(covert_bonuses.get("wells_poisoned", false)):
		garrison_target = maxi(10, int(round(float(garrison_target) * 0.75)))

	var bonus_army: int = 15 if bool(covert_bonuses.get("arms_smuggled", false)) else 0
	initial_army_power = maxi(20, raw_army) + bonus_army
	current_army_power = initial_army_power
	total_garrison_power = maxi(10, garrison_target)

	status = SiegeStatus.IN_PROGRESS
	current_phase = Phase.OUTER_GATE
	casualties_suffered = 0
	combat_log.clear()

	_init_phase_defenses(Phase.OUTER_GATE)

	var start_event := {
		"kind": &"siege_started",
		"phase": PHASE_NAMES[Phase.OUTER_GATE],
		"army_power": current_army_power,
		"garrison_power": total_garrison_power,
		"phase_defender_hp": phase_defender_hp,
		"phase_defender_max_hp": phase_defender_max_hp,
		"text": "The war horns blow! The siege engines roll toward the Outer Gate."
	}
	combat_log.append(start_event)

	if bool(covert_bonuses.get("wells_poisoned", false)):
		combat_log.append({"kind": &"covert_bonus", "text": "Clandestine Op: Tainted cisterns weakened the garrison (-25% power)."})
	if bool(covert_bonuses.get("arms_smuggled", false)):
		combat_log.append({"kind": &"covert_bonus", "text": "Clandestine Op: Smuggled weapons armed sympathizers (+15 vanguard power)."})
	if bool(covert_bonuses.get("gatekeeper_bribed", false)):
		combat_log.append({"kind": &"covert_bonus", "text": "Clandestine Op: The bribed gatekeeper unlatched the portcullis (-50% Outer Gate defense)."})

	return start_event


func _init_phase_defenses(phase: Phase) -> void:
	match phase:
		Phase.OUTER_GATE:
			# ~35% of garrison power
			var gate_hp: int = maxi(5, int(round(total_garrison_power * 0.35)))
			if bool(covert_bonuses.get("gatekeeper_bribed", false)):
				gate_hp = maxi(2, int(round(float(gate_hp) * 0.50)))
			phase_defender_max_hp = gate_hp
		Phase.COURTYARD:
			# ~35% of garrison power
			phase_defender_max_hp = maxi(5, int(round(total_garrison_power * 0.35)))
		Phase.KEEP:
			# ~30% of garrison power
			phase_defender_max_hp = maxi(5, total_garrison_power - int(round(total_garrison_power * 0.70)))
		_:
			phase_defender_max_hp = 0

	phase_defender_hp = phase_defender_max_hp


## Returns list of available tactics for the current phase.
func get_available_tactics() -> Array[Dictionary]:
	if status != SiegeStatus.IN_PROGRESS:
		return []

	match current_phase:
		Phase.OUTER_GATE:
			return [
				{
					"id": &"ram_charge",
					"title": "Battering Ram Assault",
					"desc": "Heavy breach power (+35%), but exposes front lines to gate counter-attacks.",
					"risk": "Moderate",
					"perk": "+35% Breach Impact"
				},
				{
					"id": &"archer_suppression",
					"title": "Archery Suppression",
					"desc": "Rain arrows upon the parapets. Zero casualty risk, but inflicts moderate breach damage.",
					"risk": "Low",
					"perk": "Safe Attrition"
				},
				{
					"id": &"sapper_tunnel",
					"title": "Sapper Mine Collapse",
					"desc": "Detonate subterranean supports. High chance to instantly breach with zero losses.",
					"risk": "Technical",
					"perk": "Instant Breach on Success"
				}
			]
		Phase.COURTYARD:
			return [
				{
					"id": &"shield_wall",
					"title": "Form Shield Wall",
					"desc": "Cautious advance through courtyard crossfire. Halves incoming damage.",
					"risk": "Low",
					"perk": "-50% Casualties"
				},
				{
					"id": &"knight_assault",
					"title": "Heavy Shock Charge",
					"desc": "Crush defending infantry lines rapidly with overwhelming shock combat.",
					"risk": "Moderate",
					"perk": "+40% Combat Impact"
				},
				{
					"id": &"challenge_captain",
					"title": "Challenge Garrison Captain",
					"desc": "Send your champion to duel the enemy commander. Victory routs the courtyard immediately.",
					"risk": "High Duel Risk",
					"perk": "Courtyard Rout on Win"
				}
			]
		Phase.KEEP:
			var tactics: Array[Dictionary] = [
				{
					"id": &"decisive_storm",
					"title": "Storm the Inner Sanctum",
					"desc": "All-out decisive push into the throne room to claim the castle.",
					"risk": "High",
					"perk": "Decisive Throne Breach"
				}
			]
			# If defender is bloodied (<= 40% HP), allow demand surrender
			if phase_defender_hp <= int(round(phase_defender_max_hp * 0.40)):
				tactics.append({
					"id": &"demand_surrender",
					"title": "Demand Unconditional Surrender",
					"desc": "Defenders are broken. Demand they lay down swords with 0 further casualties.",
					"risk": "None",
					"perk": "Bloodless Victory"
				})
			return tactics
		_:
			return []


## Executes a player-chosen tactical stance for the active phase.
func execute_tactic(tactic_id: StringName) -> Dictionary:
	if status != SiegeStatus.IN_PROGRESS:
		return {"success": false, "error": "No active siege"}

	var rng_draw: int = _engine.rng.randi_range(0, 999) if _engine != null and _engine.rng != null else randi() % 1000
	var damage_dealt: int = 0
	var casualty_occurred: bool = false
	var log_text: String = ""
	var combat_power := maxi(10, current_army_power)

	match tactic_id:
		# --- PHASE 1 TACTICS ---
		&"ram_charge":
			damage_dealt = maxi(4, int(round((combat_power / 2.5) * 1.35)))
			if rng_draw < 350:  # 35% counter-attack casualty
				casualty_occurred = true
				_apply_army_loss(1)
				log_text = "The ram smashes the iron gate timbers (-%d HP), but boiling oil claims a squad!" % damage_dealt
			else:
				log_text = "The battering ram shatters the outer gate reinforcements (-%d HP)!" % damage_dealt

		&"archer_suppression":
			damage_dealt = maxi(3, int(round(combat_power / 3.0)))
			log_text = "Archer volleys darken the sky, suppressing the parapet defenders (-%d HP)." % damage_dealt

		&"sapper_tunnel":
			if rng_draw < 700:  # 70% success
				damage_dealt = phase_defender_hp
				log_text = "The mine explodes with thunderous force! The gatehouse wall crumbles to dust!"
			else:
				damage_dealt = 3
				log_text = "Defenders flooded the sapper tunnels! The breach only weakly scorched the gate."

		# --- PHASE 2 TACTICS ---
		&"shield_wall":
			damage_dealt = maxi(3, int(round(combat_power / 3.0)))
			if rng_draw < 150:  # only 15% casualty risk
				casualty_occurred = true
				_apply_army_loss(1)
				log_text = "The shield wall holds firm against crossfire (-%d HP), suffering minor attrition." % damage_dealt
			else:
				log_text = "An impenetrable testudo marches forward, steadily grinding courtyard resistance (-%d HP)." % damage_dealt

		&"knight_assault":
			damage_dealt = maxi(5, int(round((combat_power / 2.2) * 1.40)))
			if rng_draw < 300:
				casualty_occurred = true
				_apply_army_loss(1)
				log_text = "The knight charge devastates the courtyard lines (-%d HP), trading blows in fierce melee!" % damage_dealt
			else:
				log_text = "A thunderous armored charge sweeps the courtyard clear (-%d HP)!" % damage_dealt

		&"challenge_captain":
			if rng_draw < 650:  # 65% duel victory
				damage_dealt = phase_defender_hp
				log_text = "Your champion cuts down the garrison captain! Terror grips the courtyard—the defenders rout!"
			else:
				damage_dealt = 2
				casualty_occurred = true
				_apply_army_loss(1)
				log_text = "The garrison captain parries fiercely and rallies the defenders (-%d HP)." % damage_dealt

		# --- PHASE 3 TACTICS ---
		&"decisive_storm":
			damage_dealt = maxi(5, int(round(combat_power / 2.0)))
			if rng_draw < 250:
				casualty_occurred = true
				_apply_army_loss(1)
				log_text = "Your warriors break into the throne chamber (-%d HP) amidst desperate resistance!" % damage_dealt
			else:
				log_text = "A relentless surge breaches the throne hall doors (-%d HP)!" % damage_dealt

		&"demand_surrender":
			damage_dealt = phase_defender_hp
			log_text = "Faced with certain doom, the castellan yields his sword. The Keep surrenders unconditionally!"

		_:
			damage_dealt = maxi(2, int(round(combat_power / 4.0)))
			log_text = "Your forces press the assault (-%d HP)." % damage_dealt

	phase_defender_hp = maxi(0, phase_defender_hp - damage_dealt)

	var round_result := {
		"tactic": tactic_id,
		"phase": PHASE_NAMES[current_phase],
		"damage_dealt": damage_dealt,
		"defender_hp": phase_defender_hp,
		"defender_max_hp": phase_defender_max_hp,
		"casualty": casualty_occurred,
		"army_power": current_army_power,
		"text": log_text
	}
	combat_log.append(round_result)

	# Check if current phase resolved
	if phase_defender_hp <= 0:
		_advance_phase()

	# Check if army was completely destroyed
	if current_army_power <= 0:
		_handle_defeat()
		round_result["text"] = log_text + " Your forces have been routed and repelled!"

	return round_result


func _advance_phase() -> void:
	match current_phase:
		Phase.OUTER_GATE:
			current_phase = Phase.COURTYARD
			_init_phase_defenses(Phase.COURTYARD)
			combat_log.append({
				"kind": &"phase_transition",
				"phase": PHASE_NAMES[Phase.COURTYARD],
				"text": "The Outer Gate has fallen! Your army surges into the Courtyard!"
			})
		Phase.COURTYARD:
			current_phase = Phase.KEEP
			_init_phase_defenses(Phase.KEEP)
			combat_log.append({
				"kind": &"phase_transition",
				"phase": PHASE_NAMES[Phase.KEEP],
				"text": "The Courtyard is conquered! Only the Keep stands between you and victory!"
			})
		Phase.KEEP:
			current_phase = Phase.COMPLETED
			status = SiegeStatus.VICTORY
			combat_log.append({
				"kind": &"siege_victory",
				"phase": "Victory",
				"text": "The castle has fallen! Total victory crowns your rebellion!"
			})
			_handle_victory()


## Orders an orderly retreat, preserving all surviving army units.
func order_retreat() -> Dictionary:
	if status != SiegeStatus.IN_PROGRESS:
		return {"success": false, "error": "No active siege"}

	status = SiegeStatus.RETREATED
	var retreat_event := {
		"kind": &"siege_retreated",
		"phase": PHASE_NAMES[current_phase],
		"casualties_avoided": true,
		"army_power": current_army_power,
		"text": "The war horn signals retreat! Surviving soldiers withdraw in disciplined order."
	}
	combat_log.append(retreat_event)

	# Incur minor suspicion bump (10 points) instead of full disaster
	if _engine != null:
		var susp = _engine.get_system(&"suspicion")
		if susp != null and susp.has_method("apply_external_bump"):
			susp.apply_external_bump(_engine, &"siege_retreat", 10, false)

	return retreat_event


func _apply_army_loss(units_count: int) -> void:
	casualties_suffered += units_count
	current_army_power = maxi(0, current_army_power - (units_count * 10))

	if _engine != null:
		var units = _engine.get_system(&"units")
		if units != null and units.has_method("apply_army_losses"):
			units.apply_army_losses(units_count)


func _handle_victory() -> void:
	if _engine == null:
		return

	var run = _engine.get_system(&"run")
	if run != null and run.has_method("resolve_victory"):
		run.resolve_victory(_engine, true, current_army_power)


func _handle_defeat() -> void:
	status = SiegeStatus.REPELLED
	combat_log.append({
		"kind": &"siege_repelled",
		"phase": PHASE_NAMES[current_phase],
		"text": "The assault has broken against the castle walls. Your forces are repelled!"
	})

	if _engine != null:
		var susp = _engine.get_system(&"suspicion")
		if susp != null and susp.has_method("apply_external_bump"):
			susp.apply_external_bump(_engine, &"siege_defeat", 25, true)
