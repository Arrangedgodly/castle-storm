## Shared MVP-pack fixture for the acceptance suites + save-debug
## (T-DATA-02). NOT a suite: the leading underscore keeps the marathon
## runner's discovery (`tests/acceptance/run_headless.gd`) from loading it as
## one. Every suite that needs content now loads the SAME pack through the
## loud gate (`ContentValidator.load_pack` — a broken pack fails `make test`
## here, not silently in the fixture), and bootstraps through the
## `grant_resources` command (M1 finding F1): no acceptance suite calls
## `engine.set_resource` anymore — that method is a documented test/unit
## construction seam only.
##
## Stipend shapes:
##   - the PACK's starting grant (default) — the honest boot the game ships;
##   - MARATHON_STIPEND — effectively-infinite funds for curve/flow suites
##     that must never stall on affordability (paid through the SAME verb;
##     the run system carries it as boot-injected content).
extends RefCounted

const PACK_PATH := "res://content/mvp/pack.tres"

## Effectively-infinite stipend for marathon suites (1e9 each resource; paid
## through grant_resources exactly like the honest boot).
const MARATHON_STIPEND: Dictionary = {
	&"food": 1_000_000_000,
	&"timber": 1_000_000_000,
	&"iron": 1_000_000_000,
}


## Loads + validates the pack ONCE per process (the cache also skips
## re-running the validator — management loops call accessors per batch and
## must not re-validate hundreds of times). (Named load_mvp to avoid the
## built-in load() signature clash.)
static var _cache: ContentPack = null


static func load_mvp() -> ContentPack:
	if _cache == null:
		_cache = ContentValidator.load_pack(PACK_PATH)
		assert(_cache != null, "MVP pack failed to load/validate: %s" % PACK_PATH)
	return _cache


## The honest stipend the game boots with (pack data).
static func starting_grants() -> Dictionary:
	return load_mvp().starting_grants


## Building ids split by role (host scripts drive content by id; the pack is
## the single source of truth — no id may appear in a suite unguarded).
static func producer_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for building: BuildingDef in load_mvp().buildings:
		if building.resource_produced != &"":
			ids.append(building.id)
	return ids


static func building_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for building: BuildingDef in load_mvp().buildings:
		ids.append(building.id)
	return ids


static func regime(id: StringName) -> RegimeDef:
	for entry: RegimeDef in load_mvp().regimes:
		if entry.id == id:
			return entry
	return null


## Full stack (heartbeat + run + units + production) from pack content.
## Registration order mirrors causality: the run frame exists before the
## recruits/economy it governs (the marathon convention; only ordering
## CONSISTENCY is contractual). `stipend` overrides the pack's starting
## grants (pass MARATHON_STIPEND for marathon funds); `{}` (default) uses
## the pack's own starting_grants.
static func full_stack(run_seed: int, stipend: Dictionary = {}) -> SimEngine:
	var pack := load_mvp()
	return stack_with_regimes(
		run_seed, pack.regimes, pack.units, pack.buildings,
		stipend if not stipend.is_empty() else pack.starting_grants
	)


## Same stack but with the regime pool overridden (the save suite's sweep
## forces single-regime draws) and optionally without the units system (the
## production marathon is a production-only curve suite).
static func stack_with_regimes(
	run_seed: int,
	regimes: Array[RegimeDef],
	units: Array[UnitDef],
	buildings: Array[BuildingDef],
	stipend: Dictionary,
	with_units := true
) -> SimEngine:
	var pack := load_mvp()
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(regimes, pack.identity, null, stipend))
	if with_units:
		engine.register_system(UnitLifecycleSystem.new(units, pack.gear, pack.tunables))
	engine.register_system(ProductionSystem.new(buildings, pack.tunables, null))
	return engine
