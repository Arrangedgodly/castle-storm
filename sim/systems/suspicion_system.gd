## Suspicion system (T-SIM-05): the pressure curve. Revolutionary activity
## raises the Crown's suspicion; telegraphed crackdowns at the tier-2
## threshold seize resources and scatter unassigned recruits; a maxed meter
## crushes the revolution and ends the run (failure banks meta, T-SIM-04).
##
## Fourth real system on the T-SIM-01 seam after production (§10), units
## (§11) and the run frame (§12); registers LAST (heartbeat, run, units,
## production, suspicion) because it watches its siblings' state at the tick
## boundary — registration order consistency is the only contractual part.
## Full contract in docs/sim-engine.md §14. Determinism rules apply in full:
##   - ZERO RNG draws: the meter is exact integer arithmetic end to end
##     (act bumps are whole points; fractional presence/decay accrue through
##     a SimFixed milli-point-seconds accumulator, exactly like production)
##   - all content floats cross ONE boundary — SimFixed.milli_from_float at
##     construction; thresholds/act points are ints in content already
##   - data-driven from EconomyTunables' suspicion block + per-def
##     UnitDef.suspicion_on_train; REGIME-NEUTRAL at MVP (documented: the
##     schema allots exactly one combat modifier + one economy quirk per
##     flavor, both already claimed — a suspicion-rate angle would need an
##     additive third modifier field, deferred to a pack that wants it)
##
## Heat profile (the auditable rise formula, per sim-hour):
##
##   presence = w_army x army_units
##            + w_follower x (total_units - army_units)
##            + w_building x SUM(building levels)
##            + w_offer x pending_gate_offers            [milli-points/h]
##   drift    = presence x relief_mult - decay           [milli-points/h]
##     decay  = -suspicion_decay_high_tier_per_hour while >= crackdown
##              threshold, else -suspicion_decay_per_hour; 0 while a decay
##              pause is running; never pushes the meter below 0
##   act bumps (whole points, the tick they happen):
##     + UnitDef.suspicion_on_train  per training completion (held or auto)
##     + suspicion_rise_medium       per building level gained
##     + suspicion_rise_loud         per gate arrival while offers > tolerance
##   Rises (bumps + presence) are halved-ish by the relief multiplier while
##   the post-crackdown relief window runs.
##
## Thresholds (R4 §C): WARN at 35 (chronicle line on zone entry), CRACKDOWN
## telegraph at >= 70 (>= 4h countdown, cancellable by dropping below 70 —
## the tension mechanic), CRUSH at 100 (run fails via the run system's
## defeat path; meta banks full progress). Crackdowns recur while you keep
## crossing 70, gated by the re-arm timer. Set-back-not-death until 100: a
## crackdown seizes floor(40%) of each stock and scatters ceil(50%) of the
## unassigned-recruit pool, but never touches trained army, committed
## pipeline, workers or buildings.
class_name SuspicionSystem
extends SimSystem

## The meter, whole points, clamped to [0, tunables.suspicion_max]. The
## run-scoped headline read (the Watchful Eye, T-UI-03).
var suspicion := 0

## SimFixed carry: milli-point-seconds toward (or away from) the next whole
## point. Serialized + hashed — the fractional meter is real state.
var accum := 0

## True while the meter sits at/above the warn threshold (zone-entry event
## fires once per entry, not per tick).
var warned := false

## Tick a pending crackdown lands at (-1 = none armed). The UI's countdown
## is `crackdown_land_tick - engine.tick_count`.
var crackdown_land_tick := -1

## Crackdowns executed this run (the telegraph's ordinal is this + 1).
var crackdowns_total := 0

## Tick the post-crackdown relief window ends (0 = none); rises are
## multiplied by the relief multiplier until then.
var relief_until_tick := 0

## Tick the re-arm window ends (0 = none); no new telegraph arms before it.
var rearm_until_tick := 0

## Tick the decay pause ends (0 = none): a loud act above the warn threshold
## freezes passive decay for a short window (R4 decay_reset_rule).
var decay_paused_until_tick := 0

var _max_points := 0
## The pack's copy table (T-COPY-01, additive-optional): the chronicle
## render query reads its variants with the event's seq as rotor; null =
## CopyDeck's code-side floor (bare sim tests read the same voice).
var _copy: CopyTable = null
var _warn_milli := 0
var _crackdown_milli := 0
var _decay_milli := 0
var _decay_high_milli := 0
var _rise_loud := 0
var _rise_medium := 0
var _on_train: Dictionary = {}  # StringName unit def id -> int suspicion_on_train
var _seize_milli := 0
var _scatter_milli := 0
var _relief_rise_milli := SimFixed.MILLI
var _telegraph_ticks := 0
var _relief_ticks := 0
var _rearm_ticks := 0
var _decay_pause_ticks := 0
var _w_army_milli := 0
var _w_follower_milli := 0
var _w_building_milli := 0
var _w_offer_milli := 0
var _recruit_tolerance := 0
var _post_crackdown_points_value := 0
var _crush_fired := false
## The run's APPLIED legacy suspicion-decay multiplier (L1-B2; serialized +
## hashed when non-identity). Scales the PASSIVE drift decay only — act
## bumps, presence weights, the pause rule and every threshold are
## untouched (the meter still moves only through the heat profile).
var _legacy_decay_milli := SimFixed.MILLI

# Last-seen sibling counters (the audit scan's baseline). Serialized +
# hashed: a restore without them would diff against zeroed counters and
# spawn phantom rises on the first post-restore tick.
var _watch_units_total := 0
var _watch_army := 0
var _watch_offers := 0
var _watch_arrivals := 0
var _watch_levels: Dictionary = {}  # StringName building id -> int level
var _watch_training: Dictionary = {}  # int uid -> true (set of running timers)


func _init(p_tunables: EconomyTunables = null, p_units: Array[UnitDef] = [],
		p_copy: CopyTable = null) -> void:
	var tunables := p_tunables if p_tunables != null else EconomyTunables.new()
	_copy = p_copy
	_max_points = maxi(1, tunables.suspicion_max)
	_warn_milli = tunables.suspicion_warn_threshold * SimFixed.MILLI
	_crackdown_milli = tunables.suspicion_crackdown_threshold * SimFixed.MILLI
	_decay_milli = SimFixed.milli_from_float(tunables.suspicion_decay_per_hour)
	_decay_high_milli = SimFixed.milli_from_float(tunables.suspicion_decay_high_tier_per_hour)
	_rise_loud = maxi(0, tunables.suspicion_rise_loud)
	_rise_medium = maxi(0, tunables.suspicion_rise_medium)
	_seize_milli = SimFixed.milli_from_float(tunables.crackdown_seize_fraction)
	_scatter_milli = SimFixed.milli_from_float(tunables.crackdown_scatter_fraction)
	_relief_rise_milli = SimFixed.milli_from_float(tunables.post_crackdown_rise_multiplier)
	_telegraph_ticks = _hours_to_ticks(tunables.crackdown_telegraph_hours)
	_relief_ticks = _hours_to_ticks(tunables.post_crackdown_relief_hours)
	_rearm_ticks = _hours_to_ticks(tunables.crackdown_rearm_hours)
	_decay_pause_ticks = _hours_to_ticks(tunables.suspicion_decay_pause_hours)
	_w_army_milli = SimFixed.milli_from_float(tunables.suspicion_presence_army_per_hour)
	_w_follower_milli = SimFixed.milli_from_float(tunables.suspicion_presence_follower_per_hour)
	_w_building_milli = SimFixed.milli_from_float(tunables.suspicion_presence_building_per_hour)
	_w_offer_milli = SimFixed.milli_from_float(tunables.suspicion_presence_offer_per_hour)
	_recruit_tolerance = maxi(0, tunables.suspicion_recruit_tolerance)
	# Post-crackdown meter: clamped to [0, max-1] defensively (the validator
	# already enforces < crackdown threshold; a crackdown must re-open
	# playable space, never sit at the crush line).
	_post_crackdown_points_value = clampi(tunables.post_crackdown_suspicion, 0, _max_points - 1)
	for def in p_units:
		if def == null:
			continue
		_on_train[def.id] = maxi(0, def.suspicion_on_train)
		if def.training_time_hours <= 0.0 and def.suspicion_on_train > 0:
			# Zero-hour trainings complete inside the command drain — invisible
			# to the tick-boundary scan (documented in §14). Loud ones get a
			# construction-time warning so no pack ships a silent gap.
			push_warning(
				"suspicion: unit '%s' trains in 0h with suspicion_on_train %d — drain-time completions do not bump the meter"
				% [def.id, def.suspicion_on_train]
			)


func system_name() -> StringName:
	return &"suspicion"


# --- Read API (UI queries; pure, deterministic, no state writes) ----------


## Whole-point meter (floor of the fractional accumulator already settled).
func suspicion_points() -> int:
	return suspicion


func max_points() -> int:
	return _max_points


func is_warned() -> bool:
	return warned


func is_decay_paused(at_tick: int) -> bool:
	return at_tick < decay_paused_until_tick


func is_in_relief(at_tick: int) -> bool:
	return at_tick < relief_until_tick


## Human-readable chronicle line for a suspicion-stream event (Professor X
## lane: T-COPY-01 — the shipped copy lives in the pack's CopyTable with
## per-event variants rotated by the event's SEQ (repeats vary; same replay
## -> same lines), CopyDeck.DEFAULTS the code-side floor; the event stream
## itself stays int-payload-only, the same identity-is-a-query pattern as M1
## finding F5). "" for other events.
func chronicle_line(event: SimEvent) -> String:
	var hours := (event.value - event.tick) / SimEngine.TICKS_PER_SIM_HOUR
	match event.type:
		&"suspicion_warn":
			return CopyDeck.line(_copy, &"suspicion_warn", event.seq)
		&"suspicion_telegraph":
			return CopyDeck.line(_copy, &"suspicion_telegraph", event.seq,
				{"hours": hours})
		&"crackdown_cancelled":
			return CopyDeck.line(_copy, &"crackdown_cancelled", event.seq)
		&"crackdown_struck":
			return CopyDeck.line(_copy, &"crackdown_struck", event.seq,
				{"count": event.value})
		&"crackdown_seized":
			return CopyDeck.line(_copy, &"crackdown_seized", event.seq,
				{"count": event.value, "resource": String(event.subject)})
		&"crackdown_scattered":
			return CopyDeck.line(_copy, &"crackdown_scattered", event.seq,
				{"count": event.value})
		&"run_crushed":
			return CopyDeck.line(_copy, &"run_crushed", event.seq)
		&"suspicion_rose":
			return CopyDeck.line(_copy, &"suspicion_rose", event.seq,
				{"points": event.value, "source": String(event.subject)})
		_:
			return ""


## Direct meter write. TEST/HOST CONSTRUCTION SEAM ONLY (mirrors
## SimEngine.set_resource): gameplay never calls this — the meter moves only
## through the heat profile; tests use it to construct exact threshold
## states; the acceptance marathon drives it honestly through real acts.
func set_suspicion(points: int) -> void:
	suspicion = clampi(points, 0, _max_points)
	accum = 0


## External act-bump seam (T-SIM-06): a sibling system applies a LOUD act the
## tick-boundary scan cannot see (the failed assault — the Crown watched the
## whole army march). Same path as internal act bumps, same order: decay-pause
## check on the PRE-bump meter (R4 decay_reset_rule), relief damping, clamp at
## the max, `suspicion_rose` event. Returns the points actually applied (0
## when damped to nothing / nothing to apply). The spike CAN reach the max —
## the crush check at this tick's on_tick then ends the run (documented
## T-SIM-06 rule: a failed assault at the meter's edge is fatal, elsewhere a
## set-back).
func apply_external_bump(engine: SimEngine, source: StringName, points: int, loud := false) -> int:
	if points <= 0:
		return 0
	if loud and suspicion * SimFixed.MILLI > _warn_milli:
		decay_paused_until_tick = engine.tick_count + _decay_pause_ticks
	var applied := points
	if engine.tick_count < relief_until_tick:
		applied = applied * _relief_rise_milli / SimFixed.MILLI
	if applied <= 0:
		return 0
	suspicion = mini(_max_points, suspicion + applied)
	engine.events.record(engine.tick_count, &"suspicion_rose", source, applied, suspicion)
	return applied


# --- Tick -----------------------------------------------------------------


func on_tick(engine: SimEngine) -> void:
	var run: Variant = engine.get_system(&"run")
	var active: bool = run != null and run.has_method("is_running") and run.is_running()
	# The audit scan ALWAYS refreshes the baseline — siblings keep moving
	# while no run is live (arrivals do not stop for your defeat), and a
	# stale baseline would spawn phantom rises at the next run's first tick.
	var scan := _scan_siblings(engine)
	if active:
		_apply_act_bumps(engine, scan)
		_apply_drift(engine, scan)
		if _check_crushed(engine, run):
			_store_watch(scan)
			return
		_check_warn(engine)
		_check_telegraph(engine)
		_check_landing(engine)
	_store_watch(scan)


## Reads every sibling the heat profile watches, as of NOW (this system
## ticks last; the values already include this tick's sibling transitions).
func _scan_siblings(engine: SimEngine) -> Dictionary:
	var scan := {
		"units": engine.get_system(&"units"),
		"production": engine.get_system(&"production"),
		"units_total": 0,
		"army": 0,
		"offers": 0,
		"arrivals": 0,
		"levels": {},
		"training": {},
	}
	var units: Variant = scan["units"]
	if units != null:
		if units.has_method("total_units"):
			scan["units_total"] = units.total_units()
		if units.has_method("army_roster"):
			var roster: Dictionary = units.army_roster()
			var army := 0
			for def_id in roster.keys():
				army += int(roster[def_id])
			scan["army"] = army
		if units.has_method("pending_offers"):
			scan["offers"] = units.pending_offers()
		scan["arrivals"] = units.arrivals_total  # property, not a method
		if units.has_method("training_uids"):
			for uid in units.training_uids():
				scan["training"][uid] = true
	var production: Variant = scan["production"]
	if production != null and production.has_method("building_ids") and production.has_method("building_level"):
		for id in production.building_ids():
			scan["levels"][id] = production.building_level(id)
	return scan


## Act bumps: whole points applied the tick the act happens, each recorded
## as a `suspicion_rose` event (auditable per source; the chronicle render
## prints them). Sources: training completions (content per-def), building
## level gains (medium tunable), gate arrivals past tolerance (loud tunable).
func _apply_act_bumps(engine: SimEngine, scan: Dictionary) -> void:
	var bumps: Dictionary = {}  # StringName source id -> int points
	var loud := false

	# Training completions: uids that left the running-timer set since last
	# tick. Held completions keep their target def until promote; auto
	# completions already carry the promoted def — read NOW, post-transition.
	var units: Variant = scan["units"]
	if units != null and not _watch_training.is_empty():
		var completed: Array[int] = []
		for uid in _watch_training.keys():
			if not scan["training"].has(uid):
				completed.append(int(uid))
		completed.sort()
		for uid in completed:
			var def_id := StringName(&"")
			if units.has_method("is_awaiting_promotion") and units.is_awaiting_promotion(uid):
				if units.has_method("training_target"):
					def_id = units.training_target(uid)
			elif units.has_method("unit_def"):
				def_id = units.unit_def(uid)
			var points := int(_on_train.get(def_id, 0))
			if points > 0:
				bumps[def_id] = int(bumps.get(def_id, 0)) + points
				loud = true

	# Building level gains: each level the estate grew this tick.
	var gained_levels := 0
	for id in scan["levels"].keys():
		var before := int(_watch_levels.get(id, 0))
		var now_level := int(scan["levels"][id])
		if now_level > before:
			gained_levels += now_level - before
	if gained_levels > 0:
		bumps[&"building"] = int(bumps.get(&"building", 0)) + gained_levels * _rise_medium

	# Gate arrivals past tolerance: a crowd at the gate is a loud act.
	var arrivals_delta: int = int(scan["arrivals"]) - _watch_arrivals
	if arrivals_delta > 0 and int(scan["offers"]) > _recruit_tolerance:
		bumps[&"gate"] = int(bumps.get(&"gate", 0)) + arrivals_delta * _rise_loud

	if bumps.is_empty():
		return
	# R4 decay_reset_rule: a loud act above the warn threshold freezes decay.
	if loud and suspicion * SimFixed.MILLI > _warn_milli:
		decay_paused_until_tick = engine.tick_count + _decay_pause_ticks
	var ids: Array = bumps.keys()
	ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	for id in ids:
		var points := int(bumps[id])
		if engine.tick_count < relief_until_tick:
			points = points * _relief_rise_milli / SimFixed.MILLI
		if points <= 0:
			continue
		suspicion = mini(_max_points, suspicion + points)
		engine.events.record(engine.tick_count, &"suspicion_rose", id, points, suspicion)


## Fractional drift: presence rises net against passive decay through the
## SimFixed accumulator; whole points settle symmetrically; clamped at both
## ends (no debt below 0, no surplus above max).
func _apply_drift(engine: SimEngine, scan: Dictionary) -> void:
	var units_total := int(scan["units_total"])
	var presence := _w_army_milli * int(scan["army"]) \
		+ _w_follower_milli * maxi(0, units_total - int(scan["army"])) \
		+ _w_offer_milli * int(scan["offers"])
	for id in scan["levels"].keys():
		presence += _w_building_milli * int(scan["levels"][id])
	var decay := _decay_high_milli if suspicion * SimFixed.MILLI >= _crackdown_milli else _decay_milli
	# The L1-B2 legacy seam: the applied decay multiplier scales BOTH tiers
	# proportionally (one exact int division; the high-tier compromise keeps
	# its slower rate), never the presence side — a quieter meter, not a
	# quieter conspiracy.
	decay = decay * _legacy_decay_milli / SimFixed.MILLI
	if engine.tick_count < decay_paused_until_tick:
		decay = 0
	var net := presence - decay
	if engine.tick_count < relief_until_tick:
		net = presence * _relief_rise_milli / SimFixed.MILLI - decay
	accum += net * SimEngine.TICK_SECONDS
	if accum >= SimFixed.UNIT_ACCUM:
		var points := accum / SimFixed.UNIT_ACCUM
		suspicion = mini(_max_points, suspicion + points)
		accum -= points * SimFixed.UNIT_ACCUM
	elif accum <= -SimFixed.UNIT_ACCUM:
		var points := (-accum) / SimFixed.UNIT_ACCUM
		suspicion = maxi(0, suspicion - points)
		accum += points * SimFixed.UNIT_ACCUM
	# Floor/ceiling: clamped meters carry no debt/surplus in the carry.
	if suspicion <= 0 and accum < 0:
		accum = 0
	elif suspicion >= _max_points and accum > 0:
		accum = 0


## 100 = revolution crushed: the run fails through the run system's defeat
## path (OUTCOME_DEFEAT; failure banks full progress, T-SIM-04). The
## resolution command drains at the next tick — tick-aligned like every
## write. Returns true when the crush fired.
func _check_crushed(engine: SimEngine, run: Variant) -> bool:
	if suspicion < _max_points or _crush_fired:
		return false
	_crush_fired = true
	crackdown_land_tick = -1
	var regime_id := &"" as StringName
	var run_index := 0
	if run != null:
		if run.has_method("regime_id"):
			regime_id = run.regime_id()
		if run.has_method("current_run_index"):
			run_index = run.current_run_index()
	engine.events.record(engine.tick_count, &"run_crushed", regime_id, _max_points, run_index)
	if run != null and run.has_method("resolve_victory"):
		if not run.resolve_victory(engine, false):
			push_error("suspicion: crush at %d could not resolve — run system refused" % engine.tick_count)
	return true


## Warn zone entry (hysteresis: fires once per entry; leaving below the
## threshold re-primes it silently).
func _check_warn(engine: SimEngine) -> void:
	if not warned and suspicion * SimFixed.MILLI >= _warn_milli:
		warned = true
		engine.events.record(engine.tick_count, &"suspicion_warn", &"suspicion", suspicion, _warn_milli / SimFixed.MILLI)
	elif warned and suspicion * SimFixed.MILLI < _warn_milli:
		warned = false


## Telegraph transitions. Armed at >= 70 (rising, no double-arming, re-arm
## window respected); CANCELLED the tick the meter drops below 70 — lay low
## and the riders stand down (the R4 tension mechanic: the telegraph is a
## warning you can still heed).
func _check_telegraph(engine: SimEngine) -> void:
	if crackdown_land_tick >= 0:
		if suspicion * SimFixed.MILLI < _crackdown_milli:
			crackdown_land_tick = -1
			engine.events.record(engine.tick_count, &"crackdown_cancelled", &"crackdown", suspicion)
		return
	if suspicion * SimFixed.MILLI >= _crackdown_milli and engine.tick_count >= rearm_until_tick:
		crackdown_land_tick = engine.tick_count + _telegraph_ticks
		engine.events.record(engine.tick_count, &"suspicion_telegraph", &"crackdown", crackdown_land_tick, suspicion)


## The telegraph lands: seize + scatter + setback. NEVER death — the meter
## re-opens at post_crackdown_suspicion under a relief window with a re-arm
## timer; only 100 (checked earlier this tick) ends the run.
func _check_landing(engine: SimEngine) -> void:
	if crackdown_land_tick < 0 or engine.tick_count < crackdown_land_tick:
		return
	var before := suspicion
	crackdowns_total += 1
	crackdown_land_tick = -1
	engine.events.record(engine.tick_count, &"crackdown_struck", &"crackdown", crackdowns_total, before)
	# Seize floor(fraction) of EVERY stock (rounded DOWN: you lose at most
	# the declared fraction of each pile; resource ids in canonical text
	# order for the event stream).
	var ids: Array = engine.resources.keys()
	ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	for id in ids:
		var stock := engine.get_resource(id)
		var seized := stock * _seize_milli / SimFixed.MILLI
		if seized > 0:
			engine.add_resource(id, -seized)
			engine.events.record(engine.tick_count, &"crackdown_seized", id, seized, engine.get_resource(id))
	# Scatter ceil(fraction) of the unassigned pool: gate offers first, then
	# idle peasants — committed pipeline, workers, army and buildings are
	# never touched (set-back, not death).
	var units := engine.get_system(&"units")
	var pool := _pending_offers(units)
	if units != null and units.has_method("idle_units") and units.has_method("base_unit_id"):
		pool += (units.idle_units(units.base_unit_id()) as Array).size()
	if pool > 0 and units != null and units.has_method("scatter_recruits"):
		var count := (pool * _scatter_milli + SimFixed.MILLI - 1) / SimFixed.MILLI
		var scattered: int = units.scatter_recruits(count)
		if scattered > 0:
			engine.events.record(
				engine.tick_count, &"crackdown_scattered", &"units", scattered, _pending_offers(units)
			)
	# The setback: meter re-opens below the crackdown threshold; relief
	# window (rises damped) + re-arm timer (no instant second strike).
	suspicion = _post_crackdown_points_value
	accum = 0
	relief_until_tick = engine.tick_count + _relief_ticks
	rearm_until_tick = engine.tick_count + _rearm_ticks
	warned = suspicion * SimFixed.MILLI >= _warn_milli


func _pending_offers(units: Variant) -> int:
	if units == null or not units.has_method("pending_offers"):
		return 0
	return units.pending_offers()


# --- Determinism oracle + save hooks (fully overridden, never `{}`) --------


func state_hash() -> int:
	var hash_value := 0x811C9DC5
	hash_value = _mix(hash_value, suspicion)
	hash_value = _mix(hash_value, accum)
	hash_value = _mix(hash_value, 1 if warned else 0)
	hash_value = _mix(hash_value, crackdown_land_tick)
	hash_value = _mix(hash_value, crackdowns_total)
	hash_value = _mix(hash_value, relief_until_tick)
	hash_value = _mix(hash_value, rearm_until_tick)
	hash_value = _mix(hash_value, decay_paused_until_tick)
	hash_value = _mix(hash_value, 1 if _crush_fired else 0)
	hash_value = _mix(hash_value, _watch_units_total)
	hash_value = _mix(hash_value, _watch_army)
	hash_value = _mix(hash_value, _watch_offers)
	hash_value = _mix(hash_value, _watch_arrivals)
	for id in _watch_levels.keys():
		hash_value = _mix(hash_value, String(id).hash())
		hash_value = _mix(hash_value, int(_watch_levels[id]))
	var uids: Array = _watch_training.keys()
	uids.sort()
	for uid in uids:
		hash_value = _mix(hash_value, int(uid))
	# The APPLIED L1-B2 decay multiplier is hashed state — but only when
	# non-identity, so engines with no unlocks hash byte-identically to the
	# pre-L1 build (the stipend-multiplier precedent).
	if _legacy_decay_milli != SimFixed.MILLI:
		hash_value = _mix(hash_value, _legacy_decay_milli)
	return hash_value


func to_dict() -> Dictionary:
	var levels := {}
	for id in _watch_levels.keys():
		levels[String(id)] = int(_watch_levels[id])
	var training: Array[int] = []
	for uid in _watch_training.keys():
		training.append(int(uid))
	training.sort()
	var state := {
		"suspicion": suspicion,
		"accum": accum,
		"warned": warned,
		"telegraph_land_tick": crackdown_land_tick,
		"crackdowns_total": crackdowns_total,
		"relief_until_tick": relief_until_tick,
		"rearm_until_tick": rearm_until_tick,
		"decay_paused_until_tick": decay_paused_until_tick,
		"crush_fired": _crush_fired,
		"watch_units_total": _watch_units_total,
		"watch_army": _watch_army,
		"watch_offers": _watch_offers,
		"watch_arrivals": _watch_arrivals,
		"watch_building_levels": levels,
		"watch_training_uids": training,
	}
	# The applied L1-B2 decay multiplier rides along ONLY when non-identity
	# (additive-optional, the emit-when-non-null discipline): a no-unlocks
	# engine saves byte-identically to pre-L1, a modulated one restores its
	# decay verbatim (no run_start drain runs post-restore to re-resolve it).
	if _legacy_decay_milli != SimFixed.MILLI:
		state["legacy_decay_milli"] = _legacy_decay_milli
	return state


func from_dict(state: Dictionary) -> void:
	suspicion = clampi(int(state.get("suspicion", 0)), 0, _max_points)
	accum = int(state.get("accum", 0))
	warned = bool(state.get("warned", false))
	crackdown_land_tick = int(state.get("telegraph_land_tick", -1))
	crackdowns_total = int(state.get("crackdowns_total", 0))
	relief_until_tick = int(state.get("relief_until_tick", 0))
	rearm_until_tick = int(state.get("rearm_until_tick", 0))
	decay_paused_until_tick = int(state.get("decay_paused_until_tick", 0))
	_crush_fired = bool(state.get("crush_fired", false))
	_watch_units_total = int(state.get("watch_units_total", 0))
	_watch_army = int(state.get("watch_army", 0))
	_watch_offers = int(state.get("watch_offers", 0))
	_watch_arrivals = int(state.get("watch_arrivals", 0))
	_watch_levels.clear()
	var levels: Dictionary = state.get("watch_building_levels", {})
	for id in levels.keys():
		_watch_levels[StringName(String(id))] = int(levels[id])
	_watch_training.clear()
	for uid in state.get("watch_training_uids", []):
		_watch_training[int(uid)] = true
	# Tolerant read of the applied L1-B2 decay multiplier: absent key = a
	# pre-L1 (or no-unlocks) save = identity — the next fold re-resolves
	# from the live provider anyway.
	_legacy_decay_milli = int(state.get("legacy_decay_milli", SimFixed.MILLI))


## Public legacy seam (L1-B2, docs/sim-engine.md §18): apply the resolved
## unlock-tree bundle's suspicion-decay field. RunLifecycleSystem calls this
## synchronously at the run_start/run_restart drains (the same drain-time
## pattern as production's set_regime), so purchases land at the next run
## start — never mid-run. NOT part of reset_run: the multiplier is
## engine-session config re-applied by the fold that follows the reset, and
## a restore reloads it verbatim from the run payload (the regime-quirks
## discipline).
func set_legacy_modifiers(mods: LegacyModifiers) -> void:
	_legacy_decay_milli = SimFixed.MILLI if mods == null else mods.suspicion_decay_milli


## Run-reset seam (T-SIM-04 reset contract, docs/sim-engine.md §12): the
## meter, telegraph, windows and audit baseline all run-scoped — back to
## constructed state. Called synchronously by the run system at the
## run_restart drain.
func reset_run(_p_regime: RegimeDef = null) -> void:
	suspicion = 0
	accum = 0
	warned = false
	crackdown_land_tick = -1
	crackdowns_total = 0
	relief_until_tick = 0
	rearm_until_tick = 0
	decay_paused_until_tick = 0
	_crush_fired = false
	_watch_units_total = 0
	_watch_army = 0
	_watch_offers = 0
	_watch_arrivals = 0
	_watch_levels.clear()
	_watch_training.clear()


# --- Internals ---------------------------------------------------------------


func _store_watch(scan: Dictionary) -> void:
	_watch_units_total = int(scan["units_total"])
	_watch_army = int(scan["army"])
	_watch_offers = int(scan["offers"])
	_watch_arrivals = int(scan["arrivals"])
	_watch_levels = (scan["levels"] as Dictionary).duplicate()
	_watch_training = (scan["training"] as Dictionary).duplicate()


## Content hours -> whole ticks via the single float boundary (milli first,
## integer after): 4.0h -> 240 ticks exactly, 1.5h -> 90.
static func _hours_to_ticks(hours: float) -> int:
	return SimFixed.milli_from_float(hours) * SimEngine.TICKS_PER_SIM_HOUR / SimFixed.MILLI


## FNV-flavored 32-bit-safe mix (same shape as SimEngine._mix —
## docs/sim-engine.md §2: no signed overflow, no platform-sensitive ops).
static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
