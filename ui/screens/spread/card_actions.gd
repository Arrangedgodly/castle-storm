## CardActions — the Spread's pure action model (T-UI-04).
##
## Every card's VALID ACTIONS, contextually, as data: the same view-model
## card dict the table renders feeds actions_for(), which reads ONLY the
## systems' documented query surfaces (no UI state, no history) — same sim
## state, same action list. Each action is ONE real sim command (the
## docs/sim-engine.md §11/§10 command tables) submitted through the host's
## single write path:
##
##   gate offer      -> take them in (recruit_accept) / send them home (dismiss_offer)
##   idle peasant    -> put to work (assign_role worker) / drill them (assign_role militia)
##   idle militia    -> begin training (start_training trainee)
##   idle trainee    -> THE BRANCH CHOICE, in-world: swear the sword (start_training
##                      knight) / take up the bow (start_training archer) — both chips
##                      print when both paths are open, no modal dialog
##   trainee         -> equip per MISSING slot, one chip per craftable tier (the tier
##     awaiting gear    choice card; unaffordable tiers print struck with the shortfall
##                      as their reason) — and when every slot is filled:
##                      PROMOTE (promote), the signature action
##   building        -> upgrade (upgrade_building) / lend a hand (assign_worker) /
##                      stand down (unassign_worker)
##   staked plot     -> raise it (upgrade_building 0->1 — the build-order choice,
##   (level 0)          T-UI-10; struck with the shortfall when unpayable)
##
## DISABLED ACTIONS STAY VISIBLE: {enabled: false, reason: "..."} — the fan
## renders them struck (line form, never hue) and activating one prints a
## chronicle hint, never popup chrome. Validity mirrors the systems' own
## gates (affordability, slots, worker pools) so the fan's disable reasons
## ARE the sim's denial reasons, restated in print.
##
## Units in training and workers expose NO actions: their cards carry
## state, not choices (the dashed edge counts down; workers live on the
## buildings' cards). The sworn army's ONE verb is the storm (T-UI-07):
## the assault odds table opens from any army card — the signature chip.
class_name CardActions
extends RefCounted


## The action list for one view-model card. Pure.
static func actions_for(host: GameHost, card: Dictionary) -> Array[Dictionary]:
	if host == null or not host.is_run_running() or card.is_empty():
		return []
	match card["kind"]:
		&"offer":
			return offer_actions(card)
		&"unit":
			return unit_actions(host, card)
		&"building":
			return building_actions(host, card)
	return []


## Gate offers: the two verbs of the gate (docs/sim-engine.md §11).
static func offer_actions(card: Dictionary) -> Array[Dictionary]:
	var uid := int(card["uid"])
	return [
		_action("accept", "Take them in", &"recruit_accept", &"", uid),
		_action("dismiss", "Send them home", &"dismiss_offer", &"", uid),
	]


## Estate units by lifecycle position. Pure reads off the units system.
static func unit_actions(host: GameHost, card: Dictionary) -> Array[Dictionary]:
	var units := host.units()
	var uid := int(card["uid"])
	var def_id := units.unit_def(uid)
	if def_id == &"":
		return []
	if units.is_awaiting_promotion(uid):
		return gear_actions(host, uid)
	if units.training_target(uid) != &"":
		return []  # in training: the card counts down, nothing to choose
	# THE SWORN ARMY's one verb (T-UI-07): storm the castle. Content-driven
	# (terminal combat rank = def power with no further paths); opening the
	# odds table is PRESENTATION, not a sim verb — the action carries the
	# screen id and the Spread intercepts it; the sim's own verb is
	# commit_assault, submitted only when the player COMMITs there.
	var def := _def(host, def_id)
	if def != null and def.combat_power > 0 and def.promotion_paths.is_empty():
		return [_action("storm", "Storm the castle", &"", &"", uid, true, "", true)]
	var actions: Array[Dictionary] = []
	match def_id:
		&"militia":
			actions.append(_action("train", "Begin training", &"start_training", &"trainee", uid))
		&"trainee":
			# The branch choice — both chips print when both paths are open
			# (content declares trainee -> knight|archer; this reads paths,
			# it does not hardcode them).
			for path in _def(host, def_id).promotion_paths:
				actions.append(_action("train_%s" % String(path),
					"Swear the %s" % _branch_noun(host, path),
					&"start_training", path, uid))
		_:
			if def_id == units.base_unit_id():
				actions.append(_action("assign_worker", "Put to work",
					&"assign_role", &"worker", uid))
				actions.append(_action("assign_militia", "Drill them",
					&"assign_role", &"militia", uid))
	return actions


## A held trainee's gear ladder + the signature promote action. One chip
## per craftable tier of every MISSING slot (occupied slots may refit to a
## strictly higher tier via the same command — the fan keeps to the gate
## path at MVP; the sim accepts refits whenever the player is given the
## chip). Fully geared: the choice collapses to PROMOTE.
static func gear_actions(host: GameHost, uid: int) -> Array[Dictionary]:
	var units := host.units()
	var actions: Array[Dictionary] = []
	for slot in units.missing_gear_slots(uid):
		var tier := 0
		for gear_id in units.gear_ids_for_slot(slot):
			tier += 1
			var gear := _gear(host, gear_id)
			if gear == null:
				continue
			var shortfall := _shortfall(host, gear.recipe)
			actions.append(_action("equip_%s_t%d" % [String(slot), tier],
				"%s (tier %d)" % [gear.display_name, gear.tier],
				&"equip_gear", gear_id, uid,
				shortfall.is_empty(), _shortfall_reason(shortfall)))
	if not actions.is_empty():
		return actions
	# Every required slot filled: the one action left is THE one.
	var target := units.training_target(uid)
	return [_action("promote", "Promote — %s" % _display_name(host, target),
		&"promote", &"", uid, true, "", true)]


## Buildings: growth + staffing (docs/sim-engine.md §10 command table).
## A level-0 building is a STAKED PLOT (T-UI-10): its one verb is the
## raise (upgrade_building 0→1 constructs at base_cost) — the build-order
## choice as a card on the table, struck with the shortfall when the
## pool cannot pay it yet (disabled-but-visible, the fan's grammar).
static func building_actions(host: GameHost, card: Dictionary) -> Array[Dictionary]:
	var production := host.production()
	var building_id := StringName(String(card["building_id"]))
	var def := _building(host, building_id)
	if def == null:
		return []
	if production.building_level(building_id) < 1:
		var raise_shortfall := _shortfall(host, production.upgrade_cost(building_id))
		return [_action("build", "Raise the %s" % def.display_name,
			&"upgrade_building", building_id, 0,
			raise_shortfall.is_empty(), _shortfall_reason(raise_shortfall))]
	var actions: Array[Dictionary] = []
	# Upgrade — the growth verb; reasons mirror upgrade_denied's gates.
	var level: int = production.building_level(building_id)
	if level >= def.max_level:
		actions.append(_action("upgrade", "Raise it higher", &"upgrade_building",
			building_id, 0, false, "at its final level"))
	else:
		var shortfall := _shortfall(host, production.upgrade_cost(building_id))
		actions.append(_action("upgrade", "Raise it to %d" % (level + 1), &"upgrade_building",
			building_id, 0, shortfall.is_empty(), _shortfall_reason(shortfall)))
	# Lend a hand — the assignment verb (workers pool onto buildings).
	var idle: int = production.idle_workers()
	var free: int = production.worker_slots(building_id) - production.assigned_workers(building_id)
	var hand_reason := "no idle hands" if idle <= 0 else "no free stations"
	actions.append(_action("assign_hand", "Lend a hand", &"assign_worker",
		building_id, 1, idle > 0 and free > 0, hand_reason))
	# Stand down — the reverse.
	var assigned: int = production.assigned_workers(building_id)
	actions.append(_action("stand_down", "Stand them down", &"unassign_worker",
		building_id, 1, assigned > 0, "none stationed"))
	return actions


## THE write path down (the UI-seam contract): one action, one command.
## Invalid actions are never submitted (the fan refuses them first); the
## sim's own denials remain the last-line defense and print in the
## chronicle as they always have.
static func submit(host: GameHost, action: Dictionary) -> void:
	host.submit(action["command"], action["subject"], int(action["value"]))


# --- helpers ---------------------------------------------------------------------------


static func _action(id: String, label: String, command: StringName,
		subject: StringName, value: int, enabled := true,
		reason := "", signature := false) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"command": command,
		"subject": subject,
		"value": value,
		"enabled": enabled,
		"reason": reason,
		"signature": signature,
	}


## Shortfall per resource ({} when the recipe is payable in full).
static func _shortfall(host: GameHost, recipe: Dictionary) -> Dictionary:
	var missing := {}
	for resource in recipe:
		var short_by: int = int(recipe[resource]) - host.engine.get_resource(resource)
		if short_by > 0:
			missing[resource] = short_by
	return missing


## "short 12 iron, 3 timber" — the print-voiced refusal.
static func _shortfall_reason(shortfall: Dictionary) -> String:
	if shortfall.is_empty():
		return ""
	var parts: Array[String] = []
	for resource in shortfall:
		parts.append("short %d %s" % [int(shortfall[resource]), String(resource)])
	return ", ".join(parts)


static func _branch_noun(host: GameHost, path: StringName) -> String:
	## "sword" for knight, "bow" for archer — the branch verbs; unknown
	## ranks fall back to their display name (content-driven).
	match path:
		&"knight":
			return "sword"
		&"archer":
			return "bow"
	return _display_name(host, path)


static func _def(host: GameHost, id: StringName) -> UnitDef:
	for def: UnitDef in Inks.pack().units:
		if def.id == id:
			return def
	return null


static func _gear(host: GameHost, id: StringName) -> GearDef:
	for gear: GearDef in Inks.pack().gear:
		if gear.id == id:
			return gear
	return null


static func _building(host: GameHost, id: StringName) -> BuildingDef:
	for building: BuildingDef in Inks.pack().buildings:
		if building.id == id:
			return building
	return null


static func _display_name(host: GameHost, id: StringName) -> String:
	var def := _def(host, id)
	return def.display_name if def != null else String(id)
