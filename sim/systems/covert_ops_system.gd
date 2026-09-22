## CovertOpsSystem — Clandestine infiltration and castle sabotage simulation (CO-01).
##
## Manages espionage, bribery, well-poisoning, and weapon smuggling operations.
## Prepares tactical advantages for the upcoming castle siege while managing
## risk and royal suspicion.
class_name CovertOpsSystem
extends RefCounted

signal operation_completed(result: Dictionary)

const OPERATIONS := {
	&"bribe_gatekeeper": {
		"id": &"bribe_gatekeeper",
		"title": "Bribe Outer Gatekeeper",
		"desc": "Pay off the gate guards to unlatch the portcullis locks before the attack.",
		"cost": {"gold": 25},
		"base_success_chance": 75,
		"suspicion_on_fail": 12,
		"bonus_tag": "gatekeeper_bribed",
		"perk": "Halves Outer Gate Fortification HP"
	},
	&"poison_wells": {
		"id": &"poison_wells",
		"title": "Poison Castle Cisterns",
		"desc": "Infiltrate nighttime water carriers to taint the castle garrison cisterns.",
		"cost": {"gold": 15, "food": 20},
		"base_success_chance": 65,
		"suspicion_on_fail": 18,
		"bonus_tag": "wells_poisoned",
		"perk": "-25% Castle Garrison Strength"
	},
	&"smuggle_arms": {
		"id": &"smuggle_arms",
		"title": "Smuggle Rebel Armaments",
		"desc": "Clandestinely sneak crate shipments of blades and armor to sympathizers inside.",
		"cost": {"iron": 25, "gold": 10},
		"base_success_chance": 80,
		"suspicion_on_fail": 10,
		"bonus_tag": "arms_smuggled",
		"perk": "+15 Conspirator Army Vanguard Power"
	},
	&"forge_decrees": {
		"id": &"forge_decrees",
		"title": "Forge Royal Decrees",
		"desc": "Counterfeit royal seal documents to divert inquisitor patrols away from the village.",
		"cost": {"gold": 30},
		"base_success_chance": 70,
		"suspicion_on_fail": 15,
		"bonus_tag": "decrees_forged",
		"perk": "Reduces Suspicion & Baffles Castle Watch"
	}
}

var completed_operations: Dictionary = {
	"gatekeeper_bribed": false,
	"wells_poisoned": false,
	"arms_smuggled": false,
	"decrees_forged": false
}

var operation_history: Array[Dictionary] = []


## Returns array of all operation descriptor dictionaries.
func get_all_operations() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id in OPERATIONS.keys():
		var op: Dictionary = OPERATIONS[id].duplicate()
		op["completed"] = is_operation_active(id)
		list.append(op)
	return list


## Returns details of a specific operation.
func get_operation(op_id: StringName) -> Dictionary:
	return OPERATIONS.get(op_id, {})


## Returns true if the operation was already successfully executed for this run.
func is_operation_active(op_id: StringName) -> bool:
	var def: Dictionary = OPERATIONS.get(op_id, {})
	var tag: String = def.get("bonus_tag", "")
	return bool(completed_operations.get(tag, false))


## Checks if the engine currently possesses enough resources for the operation.
func can_afford(op_id: StringName, engine: SimEngine) -> bool:
	if engine == null:
		return false
	var def: Dictionary = OPERATIONS.get(op_id, {})
	var cost: Dictionary = def.get("cost", {})
	for res_id in cost.keys():
		if engine.get_resource(res_id) < int(cost[res_id]):
			return false
	return true


## Executes a covert operation against the castle.
func execute_operation(op_id: StringName, engine: SimEngine) -> Dictionary:
	if not OPERATIONS.has(op_id):
		return {"success": false, "error": "Unknown operation"}

	if is_operation_active(op_id):
		return {"success": false, "error": "Operation already established"}

	if not can_afford(op_id, engine):
		return {"success": false, "error": "Insufficient resources"}

	var def: Dictionary = OPERATIONS[op_id]
	var cost: Dictionary = def.get("cost", {})

	# Deduct costs
	for res_id in cost.keys():
		engine.add_resource(res_id, -int(cost[res_id]))

	# Roll success / fail
	var roll: int = engine.rng.randi_range(1, 100) if engine.rng != null else (randi() % 100) + 1
	var base_chance: int = int(def.get("base_success_chance", 70))
	var is_success: bool = roll <= base_chance
	var bonus_tag: String = def.get("bonus_tag", "")
	var log_text: String = ""

	if is_success:
		completed_operations[bonus_tag] = true
		match op_id:
			&"bribe_gatekeeper":
				log_text = "The gatekeeper took the purse of coin. The outer portcullis mechanism is primed to yield!"
			&"poison_wells":
				log_text = "Night operatives tainted the water supply. Sickness spreads through the garrison ranks!"
			&"smuggle_arms":
				log_text = "Weapons reached the inner castle cell. Rebel sympathizers stand armed and ready!"
			&"forge_decrees":
				log_text = "The forged dispatch redirected the inquisitors! Castle watch suspicion is diverted."
				var susp = engine.get_system(&"suspicion")
				if susp != null and susp.has_method("apply_external_bump"):
					susp.apply_external_bump(engine, &"decrees_forged", -15, false)

		var result := {
			"op_id": op_id,
			"title": def["title"],
			"success": true,
			"bonus_tag": bonus_tag,
			"text": log_text
		}
		operation_history.append(result)
		operation_completed.emit(result)
		return result
	else:
		# Failure
		var fail_susp: int = int(def.get("suspicion_on_fail", 10))
		log_text = "The operation was detected! Operatives were forced to flee, alerting the royal watch (+%d Suspicion)." % fail_susp
		var susp = engine.get_system(&"suspicion")
		if susp != null and susp.has_method("apply_external_bump"):
			susp.apply_external_bump(engine, &"covert_op_compromised", fail_susp, true)

		var result := {
			"op_id": op_id,
			"title": def["title"],
			"success": false,
			"bonus_tag": bonus_tag,
			"text": log_text,
			"suspicion_incurred": fail_susp
		}
		operation_history.append(result)
		operation_completed.emit(result)
		return result


## Returns active clandestine bonuses for tactical siege consumption.
func get_bonuses() -> Dictionary:
	return completed_operations.duplicate()


## Resets covert operations state (e.g. for new run).
func reset() -> void:
	for k in completed_operations.keys():
		completed_operations[k] = false
	operation_history.clear()
