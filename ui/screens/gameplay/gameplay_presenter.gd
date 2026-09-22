## GameplayPresenter — typed view adapter and command dispatcher for Castle Storm's
## redesigned playable interfaces (T-01).
##
## Decouples UI screens (HUD, Village, Roster, Siege) from internal SimEngine details
## and provides clean data structures and validated command submission helpers.
class_name GameplayPresenter
extends RefCounted


# --- View queries -----------------------------------------------------------


## Extract clean, formatted HUD view model for resources, leader, and suspicion.
static func get_hud_data(host: GameHost) -> Dictionary:
	if host == null or host.engine == null:
		return {}

	var run := host.run()
	var production := host.production()
	var suspicion := host.suspicion()
	var pack := Inks.pack()

	var data := {
		"leader_name": run.leader_name() if run != null else "Unknown",
		"leader_epithet": run.leader_epithet() if run != null else "",
		"regime_id": run.regime_id() if run != null else &"",
		"regime_name": Inks.regime_name(run.regime_id()) if run != null else "",
		"run_index": run.current_run_index() if run != null else 1,
		"sim_hours": host.engine.sim_hours(),
		"is_running": host.is_run_running(),
		"resources": {},
		"suspicion_points": suspicion.suspicion_points() if suspicion != null else 0,
		"suspicion_max": suspicion.max_points() if suspicion != null else 100,
		"is_warned": suspicion.is_warned() if suspicion != null else false,
	}

	for res_id in pack.resources:
		var current_stock: int = host.engine.get_resource(res_id)
		var rate_per_hour: float = 0.0
		if production != null:
			for b_id: StringName in production.building_ids():
				var b_def: BuildingDef = _building_def(pack, b_id)
				if b_def != null and b_def.resource_produced == res_id:
					rate_per_hour += float(production.production_rate_milli(b_id)) / float(SimFixed.MILLI)
		data["resources"][res_id] = {
			"amount": current_stock,
			"rate_per_hour": rate_per_hour,
			"name": String(res_id).capitalize(),
		}

	return data


## Extract structured village production and buildings data.
static func get_village_data(host: GameHost) -> Dictionary:
	if host == null or host.engine == null:
		return {}

	var production := host.production()
	if production == null:
		return {}

	var pack := Inks.pack()
	var idle_workers: int = production.idle_workers()
	var buildings: Array[Dictionary] = []

	for b_id: StringName in production.building_ids():
		var b_def: BuildingDef = _building_def(pack, b_id)
		if b_def == null:
			continue
		var level: int = production.building_level(b_id)
		var assigned: int = production.assigned_workers(b_id)
		var max_slots: int = production.worker_slots(b_id)
		var rate_milli: int = production.production_rate_milli(b_id)
		var cost: Dictionary = production.upgrade_cost(b_id)
		var can_upgrade: bool = can_afford_cost(host.engine, cost) and level < b_def.max_level

		buildings.append({
			"id": b_id,
			"name": b_def.display_name,
			"icon_id": b_def.icon_id,
			"level": level,
			"max_level": b_def.max_level,
			"assigned": assigned,
			"max_slots": max_slots,
			"rate_per_hour": float(rate_milli) / float(SimFixed.MILLI),
			"resource_id": b_def.resource_produced,
			"upgrade_cost": cost,
			"can_upgrade": can_upgrade,
			"can_assign": idle_workers > 0 and assigned < max_slots,
			"can_unassign": assigned > 0,
		})

	return {
		"idle_workers": idle_workers,
		"buildings": buildings,
	}


## Extract population, recruitment, and military roster data.
static func get_roster_data(host: GameHost) -> Dictionary:
	if host == null or host.engine == null:
		return {}

	var units := host.units()
	if units == null:
		return {}

	var pack := Inks.pack()
	var offers: Array[Dictionary] = []
	for uid: int in units.offer_ids():
		offers.append({
			"uid": uid,
			"name": SpreadPresenter.recruit_name(pack, uid),
		})

	var idle_peasants: Array[Dictionary] = []
	var workers: Array[Dictionary] = []
	var militia: Array[Dictionary] = []
	var training_units: Array[Dictionary] = []
	var soldiers: Array[Dictionary] = []

	var base_id: StringName = units.base_unit_id()
	for uid: int in units.unit_ids():
		var def_id: StringName = units.unit_def(uid)
		var unit_name: String = SpreadPresenter.recruit_name(pack, uid)
		var target: StringName = units.training_target(uid)
		var is_awaiting: bool = units.is_awaiting_promotion(uid)

		if is_awaiting or target != &"":
			var duration_milli: int = units.training_duration_milli(target)
			var progress_milli: int = units.training_progress_milli(uid)
			var progress_pct: float = 0.0
			if duration_milli > 0:
				progress_pct = clampf(float(progress_milli) / float(duration_milli), 0.0, 1.0)
			training_units.append({
				"uid": uid,
				"name": unit_name,
				"def_id": def_id,
				"target_id": target,
				"progress_pct": progress_pct,
				"is_awaiting_promotion": is_awaiting,
				"missing_gear": units.missing_gear_slots(uid) if is_awaiting else [],
			})
		elif def_id == base_id:
			idle_peasants.append({"uid": uid, "name": unit_name})
		elif def_id == &"worker":
			workers.append({"uid": uid, "name": unit_name})
		elif def_id == &"militia":
			militia.append({"uid": uid, "name": unit_name})
		else:
			var u_def: UnitDef = _unit_def(pack, def_id)
			soldiers.append({
				"uid": uid,
				"name": unit_name,
				"def_id": def_id,
				"power": u_def.combat_power if u_def != null else 0,
			})

	return {
		"offers": offers,
		"pending_offers_count": units.pending_offers(),
		"gate_capacity": units.gate_capacity(),
		"idle_peasants": idle_peasants,
		"workers": workers,
		"militia": militia,
		"training_units": training_units,
		"soldiers": soldiers,
		"total_population": units.total_units(),
		"army_power": units.army_power(),
	}


## Extract assault odds and castle siege data.
static func get_siege_data(host: GameHost) -> Dictionary:
	if host == null or host.engine == null:
		return {}

	var assault := host.assault()
	if assault == null:
		return {}

	var odds_data: Dictionary = assault.assault_odds(host.engine)
	var win_permille: int = int(odds_data.get("win_permille", 0))
	var win_odds_pct: float = float(win_permille) / 10.0  # 1000 permille = 100.0%

	var army_dict: Dictionary = odds_data.get("army", {})
	var garrison_dict: Dictionary = odds_data.get("garrison", {})

	return {
		"win_odds_percent": win_odds_pct,
		"floor_met": bool(odds_data.get("floor_met", false)),
		"floor_power": int(odds_data.get("floor_power", 0)),
		"army_power": int(army_dict.get("power", 0)),
		"army_units": int(army_dict.get("units", 0)),
		"garrison_power": int(garrison_dict.get("base_power", 0)),
		"can_assault": bool(odds_data.get("can_assault", false)) and host.is_run_running(),
	}


# --- Helpers ----------------------------------------------------------------


## Check whether current resources on the engine satisfy a cost dictionary.
static func can_afford_cost(engine: SimEngine, cost: Dictionary) -> bool:
	if engine == null or cost.is_empty():
		return false
	for resource: StringName in cost:
		if engine.get_resource(resource) < int(cost[resource]):
			return false
	return true


static func _building_def(pack: ContentPack, id: StringName) -> BuildingDef:
	if pack == null:
		return null
	for def in pack.buildings:
		if def != null and def.id == id:
			return def
	return null


static func _unit_def(pack: ContentPack, id: StringName) -> UnitDef:
	if pack == null:
		return null
	for def in pack.units:
		if def != null and def.id == id:
			return def
	return null


# --- Command dispatchers ----------------------------------------------------


## Accept an incoming recruit offer from the gate.
static func accept_offer(host: GameHost, uid: int) -> void:
	if host != null:
		host.submit(&"recruit_accept", &"", uid)


## Dismiss an incoming recruit offer.
static func dismiss_offer(host: GameHost, uid: int) -> void:
	if host != null:
		host.submit(&"dismiss_offer", &"", uid)


## Assign an idle peasant to the worker role.
static func assign_peasant_to_worker(host: GameHost, uid: int) -> void:
	if host != null:
		host.submit(&"assign_role", &"worker", uid)


## Assign an idle peasant to the militia role.
static func assign_peasant_to_militia(host: GameHost, uid: int) -> void:
	if host != null:
		host.submit(&"assign_role", &"militia", uid)


## Assign an available worker to a specific production building.
static func assign_worker_to_building(host: GameHost, building_id: StringName) -> void:
	if host != null:
		host.submit(&"assign_worker", building_id, 1)


## Unassign a worker from a specific production building.
static func unassign_worker_from_building(host: GameHost, building_id: StringName) -> void:
	if host != null:
		host.submit(&"unassign_worker", building_id, 1)


## Upgrade or construct a building.
static func upgrade_building(host: GameHost, building_id: StringName) -> void:
	if host != null:
		host.submit(&"upgrade_building", building_id, 0)


## Start training a militia or trainee toward a target military branch.
static func start_training(host: GameHost, uid: int, target_def_id: StringName) -> void:
	if host != null:
		host.submit(&"start_training", target_def_id, uid)


## Commit assault on the castle.
static func commit_assault(host: GameHost) -> void:
	if host != null:
		host.submit(&"commit_assault", &"", 0)
