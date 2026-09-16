## FirstSession — the guided-by-the-world onboarding layer (T-UI-10).
##
## THE FIRST SESSION IS NOT A TUTORIAL. There is no wall: zero modal
## dialogs, zero text pages, nothing the player must dismiss before
## playing — the game is the lesson. What this layer adds is FIVE
## PRINTED CUES in the world's own grammar, one per beat of journey 1
## (town-hall: leader intro → first recruit → assign → first trickle →
## build order → first trainee):
##
##   gate    the first recruit offer arrives -> one strip hint naming the
##           card's touch, focus lands on the offer card (the highlight
##           IS the focus ring — never an arrow mascot)
##   assign  the first accepted body stands idle -> one strip hint for the
##           role fan, focus lands on the unit card
##   build   the build-order choice surfaces -> one strip hint, focus
##           lands on the affordable plot card (the staked plots ARE the
##           menu; "Raise it" is the fan's verb)
##   trickle the first produced whole resource lands in stock -> one strip
##           line with the real amount and resource
##   train   the first trainee hop is queued -> one strip line; the arc is
##           complete and the layer graduates
##
## CONTRACT (the worker brief, pinned by tests):
##   - ONCE: every beat fires at most once per INSTALL. Flags persist in
##     the META domain (RunMeta.first_session, additive-optional) — the
##     flip is saved immediately, so a crash mid-arc cannot replay a
##     nudge; a returning player ("seen" set at the first fresh boot)
##     sees NOTHING, ever.
##   - SKIPPABLE: a hint is a printed chronicle row — it blocks nothing,
##     consumes no input, scrolls away as the world keeps printing, and
##     dismisses on action (the beat's verb landing IS the dismissal;
##     the flag means it can never re-print).
##   - HONEST PACING (measured, docs/balance.md's own opening rows): the
##     T-SIM-08 early-arrival boost puts the first recruit at minute 7;
##     the CHOICE arc (gate answered, role chosen, plot raised) completes
##     by minute ~9 of wall time at 1x — that is the "I get it" window.
##     The two PAYOFF prints land when the sim brings them: the first
##     whole food ~minute 49 (worker hop 0.5h + 6 food/h), the trainee
##     hop ~minute 140 (militia drills 2h) — the idle-game cadence the
##     check-in flow (T-UI-09) serves. The beats fire whenever they fire;
##     nothing here waits or gates.
##
## Determinism: no RNG, no wall clock — every trigger is an event or a
## stock compare, every line renders through CopyDeck with the beat's
## tick as rotor (same state → same lines; rendering never touches the
## engine's stream).
class_name FirstSession
extends RefCounted

## The arc's beats, in journey order (the flag keys in RunMeta).
const BEATS: Array[StringName] = [&"gate", &"assign", &"build", &"trickle", &"train"]

## Session-local latch: true from begin() on the one true first deal.
var active := false

## The trickle watch: resource id + stock baseline captured when the
## first worker staffed a producer (-1 = not armed).
var _trickle_resource: StringName = &""
var _trickle_baseline := -1


## True when THIS boot is the one true first session — the fresh first
## deal (no chronicle, the boot tick, the run live) AND the persisted
## "seen" flag unset (a returning player is never nudged). Mirrors the
## intro's own freshness rule (spread_screen._maybe_open_boot_intro).
static func arms(host: GameHost) -> bool:
	if host.meta.first_session_flag(&"seen"):
		return false
	if host.meta.runs_recorded != 0:
		return false
	if host.engine.tick_count > 1:
		return false  # a resumed first hand — the check-in owns its entry
	return host.is_run_running()


## Arm the layer (the screen calls this once at mount). Marks "seen" and
## persists BOTH domains immediately: a fresh install has no run save
## yet (the first autosave is an hour out), and a meta-without-run
## boundary would boot the next launch into the loud load refusal —
## writing the run slot here keeps the disk pair coherent. Whatever
## happens next — quit, crash, victory — this install has had its
## first session.
func begin(host: GameHost) -> void:
	if not arms(host):
		return
	active = true
	if _mark(host, &"seen"):
		host.save_all()


# --- the beats -------------------------------------------------------------------------


## One event. Returns {} or the nudge to deliver: {row: {class, text},
## focus: card-id-or-""} — the SCREEN owns pushing the row and moving
## focus (paper politeness is a screen concern; this layer only decides).
func on_event(event: Dictionary, host: GameHost) -> Dictionary:
	if not active:
		return {}
	_check_ended(event, host)
	if not active or host.delivering_catch_up:
		return {}
	var kind: StringName = event["type"]
	match kind:
		&"recruit_arrived":
			var uid := int(event["value"])
			return _fire(host, &"gate", {"name": _recruit_name(host, uid)},
				"offer_%d" % uid)
		&"recruit_accepted":
			var uid := int(event["value"])
			return _fire(host, &"assign", {"name": _recruit_name(host, uid)},
				"unit_%d" % uid)
		&"worker_assigned":
			_arm_trickle(host, StringName(String(event["subject"])))
			return {}
		&"training_started":
			if event["subject"] == &"trainee":
				return _fire(host, &"train",
					{"name": _recruit_name(host, int(event["value"]))}, "")
			return {}
	return {}


## Per processed batch (the only polling-shaped hook, one signal per
## batch — the same channel pips ride): the build-order beat (affordability
## is state, not an event) and the trickle watch (production settles
## silently). Returns the same {} / {row, focus} shape.
func on_ticks(host: GameHost) -> Dictionary:
	if not active:
		return {}
	if not host.meta.first_session_flag(&"build") \
			and host.meta.first_session_flag(&"assign"):
		var plot := _affordable_plot(host)
		if not plot.is_empty():
			return _fire(host, &"build", {"building": plot["name"]},
				"bld_%s" % String(plot["id"]))
	if _trickle_baseline >= 0 and _trickle_resource != &"":
		var stock: int = host.engine.get_resource(_trickle_resource)
		if stock > _trickle_baseline:
			var delta: int = stock - _trickle_baseline
			_trickle_baseline = -1
			return _fire(host, &"trickle",
				{"amount": delta, "resource": String(_trickle_resource)}, "")
	return {}


## True when the whole arc has printed (or the world ended it).
func graduated(host: GameHost) -> bool:
	return host.meta.first_session_flag(&"done")


# --- internals ---------------------------------------------------------------------------


## Fire one beat: once-only gate, flag flip + immediate meta persist,
## CopyDeck render (rotor = the beat's tick — deterministic, varies by
## when the world brought the moment).
func _fire(host: GameHost, beat: StringName, params: Dictionary,
		focus: String) -> Dictionary:
	if host.meta.first_session_flag(beat):
		return {}
	if not _mark(host, beat):
		return {}
	var text := CopyDeck.line(Inks.pack().copy, StringName("first_%s" % String(beat)),
		host.engine.tick_count, params)
	if text.is_empty():
		return {}
	var row := {"class": Inks.LineClass.PLAIN, "text": text}
	if beat == &"train":
		_mark(host, &"done")  # the arc is complete — graduate
	return {"row": row, "focus": focus}


## Flip a flag and persist the meta domain NOW (the once-only guarantee
## must survive a crash one print later). Returns true when it flipped.
func _mark(host: GameHost, beat: StringName) -> bool:
	if not host.meta.set_first_session_flag(beat):
		return false
	host.save_manager.save_meta(host.meta)
	return true


## The run ended (any outcome) or a new hand was dealt: the first
## session's arc is over whatever beats remain — graduate quietly.
func _check_ended(event: Dictionary, host: GameHost) -> void:
	if not active:
		return
	match event["type"]:
		&"run_won", &"run_lost", &"run_aborted", &"run_crushed", \
			&"run_restarted", &"run_started":
			if not host.meta.first_session_flag(&"done"):
				_mark(host, &"done")
			active = false


## Arm the trickle watch at the first staffing of a producer: remember
## WHICH resource and the stock as it stood (the print carries the real
## first increase, whatever its size).
func _arm_trickle(host: GameHost, building_id: StringName) -> void:
	if host.meta.first_session_flag(&"trickle") or _trickle_baseline >= 0:
		return
	for building: BuildingDef in Inks.pack().buildings:
		if building.id == building_id and building.resource_produced != &"":
			_trickle_resource = building.resource_produced
			_trickle_baseline = host.engine.get_resource(_trickle_resource)
			return


## The first AFFORDABLE plot (the build-order choice that can be acted
## on NOW): producers in pack order first — food is the sensible first
## raise — then the flavor cards. {} when nothing is affordable (the
## beat waits; the hint never prints a verb the pool cannot pay).
func _affordable_plot(host: GameHost) -> Dictionary:
	if _any_built(host):
		return {}
	var pack := Inks.pack()
	for pass_kind in [&"producer", &"flavor"]:
		for building: BuildingDef in pack.buildings:
			var is_producer: bool = building.resource_produced != &""
			if (pass_kind == &"producer") != is_producer:
				continue
			if _payable(host, host.production().upgrade_cost(building.id)):
				return {"id": building.id, "name": building.display_name}
	return {}


func _any_built(host: GameHost) -> bool:
	for building: BuildingDef in Inks.pack().buildings:
		if host.production().building_level(building.id) > 0:
			return true
	return false


func _payable(host: GameHost, cost: Dictionary) -> bool:
	for resource in cost:
		if host.engine.get_resource(resource) < int(cost[resource]):
			return false
	return true


static func _recruit_name(host: GameHost, uid: int) -> String:
	return SpreadPresenter.recruit_name(Inks.pack(), uid)
