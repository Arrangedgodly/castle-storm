## DemoPolicy — the scripted sensible-play driver for the seeded demo run
## (T-UI-03's `make run-game`).
##
## A REDUCED sibling of the canonical `_full_stack.manage()` policy (the
## canonical one lives in tests/ — it cannot ship, and this file
## deliberately does NOT try to mirror its spend ledger). Shape, not
## parity: reads -> commands only (the UI-seam contract), zero driver-side
## RNG, so the demo run stays deterministic per seed. Once per cadence it:
## accepts gate offers up to a population cap (dismisses loiterers over
## it), branches peasants (military up to a cap, everyone else to work),
## queues trainings, crafts the cheapest missing gear, promotes kitted
## trainees, staffs idle workers across producers, builds unbuilt
## buildings and upgrades the lowest affordable producer — and LAYS LOW
## while the meter is in the crackdown zone (the R4 tension response).
## The "loud" variant (military cap high, never lays low) is the
## screenshot harness's pressured-state drive: greed gets watched.
class_name DemoPolicy
extends RefCounted

## Population ceiling (a small conspiracy is a quiet conspiracy).
var population_cap: int

## Army pipeline ceiling; the loud variant sets this high.
var military_cap: int

## True = ignore the crackdown zone (the greed probe — gets crushed).
var loud: bool

## Run the policy once every this many ticks (default: every sim hour).
var cadence_ticks: int = SimEngine.TICKS_PER_SIM_HOUR

var _since_run := 0


func _init(p_population_cap: int = 16, p_military_cap: int = 8, p_loud: bool = false) -> void:
	population_cap = p_population_cap
	military_cap = p_military_cap
	loud = p_loud


## Feed every processed-tick batch; returns true when the policy fires on
## this batch (the screen then calls apply()).
func on_ticks(ticks: int) -> bool:
	_since_run += ticks
	if _since_run >= cadence_ticks:
		_since_run = 0
		return true
	return false


## The policy itself: pure reads -> commands. Mirrors _full_stack.manage
## minus the ledger (see the class header).
func apply(host: GameHost) -> void:
	var units := host.units()
	var production := host.production()
	var suspicion := host.suspicion()
	var engine := host.engine
	var laying_low := not loud \
		and suspicion.suspicion_points() >= Inks.pack().tunables.suspicion_crackdown_threshold

	# 1) Gate: accept up to the cap, send the loiterers home.
	var room: int = maxi(0, population_cap - units.total_units())
	var accepted := {}
	for uid in units.offer_ids():
		if room <= 0:
			break
		engine.submit_command(&"recruit_accept", &"", uid)
		accepted[uid] = true
		room -= 1
	if population_cap > 0 and units.total_units() + units.pending_offers() > population_cap:
		for uid in units.offer_ids():
			if not accepted.has(uid):
				engine.submit_command(&"dismiss_offer", &"", uid)

	# 2) Roles: military up to the cap (never while laying low), the rest
	#    to the workforce.
	var military := _military_total(units)
	var workers: int = units.unit_count(&"worker")
	for uid in units.idle_units(units.base_unit_id()):
		if not laying_low and workers >= 2 and military < military_cap:
			military += 1
			engine.submit_command(&"assign_role", &"militia", uid)
		else:
			workers += 1
			engine.submit_command(&"assign_role", &"worker", uid)

	# 3) Training queues: militia -> trainee, trainee -> the thinner rank.
	if not laying_low:
		for uid in units.idle_units(&"militia"):
			engine.submit_command(&"start_training", &"trainee", uid)
		var knights: int = units.unit_count(&"knight")
		var archers: int = units.unit_count(&"archer")
		for uid in units.unit_ids():
			var target := units.training_target(uid)
			if target == &"knight":
				knights += 1
			elif target == &"archer":
				archers += 1
		for uid in units.idle_units(&"trainee"):
			if knights <= archers:
				knights += 1
				engine.submit_command(&"start_training", &"knight", uid)
			else:
				archers += 1
				engine.submit_command(&"start_training", &"archer", uid)

	# 4) Gear + promotion (the forge works while laying low — equipping
	#    is not a loud act).
	var funds := {}
	for id in engine.resources.keys():
		funds[id] = int(engine.resources[id])
	for uid in units.awaiting_promotion_ids():
		for slot in units.missing_gear_slots(uid):
			for gear_id in units.gear_ids_for_slot(slot):
				if _affordable(gear_id, funds):
					_pay(gear_id, funds)
					engine.submit_command(&"equip_gear", gear_id, uid)
					break
		if units.missing_gear_slots(uid).is_empty():
			engine.submit_command(&"promote", &"", uid)

	# 5) Staffing: idle workers onto the least-assigned producer.
	var idle: int = production.idle_workers()
	var assigned := {}
	var producer_ids: Array[StringName] = []
	for building: BuildingDef in Inks.pack().buildings:
		if building.resource_produced != &"":
			producer_ids.append(building.id)
			assigned[building.id] = production.assigned_workers(building.id)
	while idle > 0:
		var pick: StringName = &""
		for id in producer_ids:
			if production.worker_slots(id) - int(assigned[id]) > 0 \
					and (pick == &"" or int(assigned[id]) < int(assigned[pick])):
				pick = id
		if pick == &"":
			break
		engine.submit_command(&"assign_worker", pick, 1)
		assigned[pick] = int(assigned[pick]) + 1
		idle -= 1

	# 6) Build order: construct EVERY unbuilt building first (the training
	#    grounds included — the canonical policy's shape), then one
	#    affordable lowest-producer upgrade. Both loud acts: suspended
	#    while laying low.
	if not laying_low:
		var pack := Inks.pack()
		for building: BuildingDef in pack.buildings:
			if production.building_level(building.id) > 0:
				continue
			if _affordable_cost(production.upgrade_cost(building.id), funds):
				_pay_cost(production.upgrade_cost(building.id), funds)
				engine.submit_command(&"upgrade_building", building.id, 1)
		var pick: StringName = &""
		var pick_level := -1
		for id in producer_ids:
			var level: int = production.building_level(id)
			if level < 1:
				continue
			if (pick_level < 0 or level < pick_level) \
					and _affordable_cost(production.upgrade_cost(id), funds):
				pick = id
				pick_level = level
		if pick != &"":
			_pay_cost(production.upgrade_cost(pick), funds)
			engine.submit_command(&"upgrade_building", pick, 1)


static func _military_total(units: UnitLifecycleSystem) -> int:
	var total: int = units.unit_count(&"militia") + units.unit_count(&"trainee") \
		+ units.unit_count(&"knight") + units.unit_count(&"archer")
	for uid in units.unit_ids():
		var target := units.training_target(uid)
		if target == &"militia" or target == &"trainee" \
				or target == &"knight" or target == &"archer":
			total += 1
	return total


static func _gear_recipe(gear_id: StringName) -> Dictionary:
	for gear: GearDef in Inks.pack().gear:
		if gear.id == gear_id:
			return gear.recipe
	return {}


static func _affordable(gear_id: StringName, funds: Dictionary) -> bool:
	return _affordable_cost(_gear_recipe(gear_id), funds)


static func _affordable_cost(cost: Dictionary, funds: Dictionary) -> bool:
	if cost.is_empty():
		return false
	for resource in cost:
		if int(funds.get(resource, 0)) < int(cost[resource]):
			return false
	return true


static func _pay(gear_id: StringName, funds: Dictionary) -> void:
	_pay_cost(_gear_recipe(gear_id), funds)


static func _pay_cost(cost: Dictionary, funds: Dictionary) -> void:
	for resource in cost:
		funds[resource] = int(funds.get(resource, 0)) - int(cost[resource])
