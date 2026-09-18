## FirstSession — the guided-by-the-world onboarding layer (T-UI-10, the
## tutorial upgrade: "a clear tutorial — the new player couldn't tell what
## to do at all").
##
## THE FIRST SESSION IS STILL NOT A WALL. Zero modal dialogs, zero
## text pages; the game is playable instantly. What this layer adds now
## is TWO printed voices in the world's own grammar:
##
## 1. THE PINNED CLERK'S NOTE (the guided objectives). Where the old
##    layer fired five terse once-only strip cues, the note PINS the
##    CURRENT objective at the table's edge — plain language, plus the
##    how ("New paper at the gate — touch Wat's card to answer.") — and
##    ADVANCES on the real action, through the arc:
##
##      accept -> assign -> raise a building -> queue training ->
##      gear a trainee -> promote -> (the storm hint at the floor)
##
##    The note is paper on the table (ObjectiveNote), never chrome. The
##    arc is FORGIVING: a later objective's action completes every step
##    before it (players who parallel-path are never scolded), every step
##    is skippable ("I know this" on the note itself), the note shows
##    only when an HONEST moment exists (it never names a card that is
##    not on the table — the reveal cannot lie), and it graduates on the
##    run's end or the storm — never to return. Every flip persists to
##    the META domain at once (additive flags in RunMeta.first_session —
##    a crash mid-arc cannot replay a step; a returning player sees
##    nothing, ever).
##
## 2. THE CONTEXTUAL FIRST-TIME HINTS. Once-EVER plain-language strip
##    lines at the key moments the arc's window can miss: the first
##    promotion-ready trainee, the first suspicion warn, the odds table's
##    first opening, the first legacy bank. Purely flag-gated statics —
##    they work in ANY session (the first bank usually lands after the
##    first session ends), fire exactly once per install, and render
##    through CopyDeck (budget-pinned in test_copy_voice).
##
##    The first produce keeps its PAYOFF print (the trickle: the real
##    amount and resource — the arc's smallest "it works" moment), and
##    graduation prints one farewell line. The gate/assign/build lines
##    moved onto the note; their keys live on.
##
## HONEST PACING (measured, docs/balance.md's own opening rows): the
## early-arrival boost puts the first recruit at minute 7; the first
## food trickle lands ~minute 12 player-paced; the trainee hop keeps its
## ~minute-141 idle cadence. The beats fire whenever they fire; nothing
## here waits or gates.
##
## Determinism: no RNG, no wall clock — every trigger is an event or a
## state compare, every line renders through CopyDeck (same state ->
## same lines; rendering never touches the engine's stream).
class_name FirstSession
extends RefCounted

## The objective arc, in journey order: flag id -> CopyDeck note key.
## The gate/assign/build steps reuse the original T-UI-10 keys; the yard,
## gear, promote and storm steps are the arc's additive keys.
const ARC: Array[Dictionary] = [
	{"id": &"gate", "key": &"first_gate"},
	{"id": &"assign", "key": &"first_assign"},
	{"id": &"build", "key": &"first_build"},
	{"id": &"train", "key": &"objective_train"},
	{"id": &"gear", "key": &"objective_gear"},
	{"id": &"promote", "key": &"objective_promote"},
	{"id": &"storm", "key": &"objective_storm"},
]

## The once-ever hint flags (RunMeta.first_session keys), in no order.
const HINT_FLAGS: Array[StringName] = [
	&"hint_promote", &"hint_warn", &"hint_odds", &"hint_bank",
]

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


# --- the guided objective arc --------------------------------------------------------------


## The CURRENT pinned objective for the clerk's note: the first arc step
## that is neither done nor skippable AND whose honest moment exists on
## the table right now. {} when the note is quiet (nothing to say that
## would not lie). Pure: reads flags + live systems, mutates nothing.
##   {id, key, index, count, text, focus}
static func current_objective(host: GameHost) -> Dictionary:
	if host.meta.first_session_flag(&"done"):
		return {}
	if not host.is_run_running():
		return {}
	for i in ARC.size():
		var step: Dictionary = ARC[i]
		var id: StringName = step["id"]
		if host.meta.first_session_flag(id):
			continue
		var moment := _moment(host, id)
		if moment.is_empty():
			continue  # the moment is gone or has not come — the note is quiet
		var text := CopyDeck.line(Inks.pack().copy, step["key"],
			host.engine.tick_count, moment["params"])
		if text.is_empty():
			return {}
		return {
			"id": id, "key": step["key"], "index": i, "count": ARC.size(),
			"text": text, "focus": String(moment["focus"]),
		}
	return {}


## The player's "I know this" on the note: the current objective (and
## every step before it) is struck from the arc. Returns true when a
## step was skipped (the screen re-binds the note).
func skip_current(host: GameHost) -> bool:
	var current := current_objective(host)
	if current.is_empty():
		return false
	_complete_through(host, StringName(String(current["id"])))
	return true


## One event. Returns {} or what the SCREEN should deliver:
##   {row?: {class, text}, focus?: card-id, note_changed?: bool} —
## the screen owns printing rows, moving focus and re-binding the note
## (paper politeness is a screen concern; this layer only decides).
func on_event(event: Dictionary, host: GameHost) -> Dictionary:
	_check_ended(event, host)
	if not active or host.delivering_catch_up:
		return {}
	var kind: StringName = event["type"]
	var before := current_objective(host)
	match kind:
		&"recruit_arrived":
			# The gate's moment OPENS: the note pins and focus lands on
			# the offer card (the highlight IS the focus ring).
			return _moment_nudge(host, before, &"gate")
		&"recruit_accepted":
			_advance(host, &"gate")
			return _moment_nudge(host, before, &"assign")
		&"training_started":
			match StringName(String(event["subject"])):
				&"worker", &"militia":
					_advance(host, &"assign")
				&"trainee", &"knight", &"archer":
					_advance(host, &"train")
			return _moment_nudge(host, before, &"")
		&"building_built":
			_advance(host, &"build")
			return _moment_nudge(host, before, &"")
		&"gear_equipped":
			_advance(host, &"gear")
			return _moment_nudge(host, before, &"promote")
		&"unit_promoted":
			if _is_army_def(host, StringName(String(event["subject"]))):
				_advance(host, &"promote")
				return _moment_nudge(host, before, &"")
		&"worker_assigned":
			_arm_trickle(host, StringName(String(event["subject"])))
			return {}
	return {}


## Per processed batch (the only polling-shaped hook, one signal per
## batch — the same channel pips ride): the trickle watch (production
## settles silently) and the CROWDED-TABLE graduation (a table of ten
## or more cards is long past needing the clerk — the note folds
## quietly rather than crowd a dense estate; the lane lifts with it).
## The storm moment is READ by current_objective; its completion is the
## screen's odds-open hook or the run's end. Returns the same {} /
## {row, focus, note_changed} shape.
func on_ticks(host: GameHost) -> Dictionary:
	if not active:
		return {}
	if _crowded(host) and not host.meta.first_session_flag(&"done"):
		_mark(host, &"done")
		active = false
		return {"row": {"class": Inks.LineClass.PLAIN,
			"text": CopyDeck.line(Inks.pack().copy, &"objective_graduated",
				host.engine.tick_count)}, "note_changed": true}
	if _trickle_baseline >= 0 and _trickle_resource != &"":
		var stock: int = host.engine.get_resource(_trickle_resource)
		if stock > _trickle_baseline:
			var delta: int = stock - _trickle_baseline
			_trickle_baseline = -1
			if not _mark(host, &"trickle"):
				return {}
			return {"row": {
				"class": Inks.LineClass.PLAIN,
				"text": CopyDeck.line(Inks.pack().copy, &"first_trickle",
					host.engine.tick_count,
					{"amount": delta, "resource": String(_trickle_resource)}),
			}}
	return {}


## The storm hook: the odds table opened while the storm objective stood
## (the arc's last step, performed). Completes the arc and returns the
## farewell nudge for the screen to deliver (the row must not wait for
## an event that may never come).
func complete_storm(host: GameHost) -> Dictionary:
	if not active:
		return {}
	_advance(host, &"storm")
	var out := {"note_changed": true}
	if not _graduation_row.is_empty():
		out["row"] = _graduation_row
		_graduation_row = {}
	return out


## True when the whole arc has printed (or the world ended it).
func graduated(host: GameHost) -> bool:
	return host.meta.first_session_flag(&"done")


# --- the contextual first-time hints (once EVER, any session) ------------------------------


## One event through the hint gate. Returns {} or one strip row. Flags
## persist at once — a hint is printed exactly once per install, and
## only when its fact is the world's own (the reveal cannot lie).
static func hint_on_event(event: Dictionary, host: GameHost) -> Dictionary:
	var kind: StringName = event["type"]
	match kind:
		&"suspicion_warn":
			if _hint_flag(host, &"hint_warn"):
				return {"row": {"class": Inks.LineClass.PLAIN,
					"text": CopyDeck.line(Inks.pack().copy, &"hint_warn",
						host.engine.tick_count)}}
		&"run_won", &"run_lost", &"run_aborted":
			# The first bank: the REAL score the run lifecycle just
			# banked rides the event's value.
			if _hint_flag(host, &"hint_bank"):
				return {"row": {"class": Inks.LineClass.PLAIN,
					"text": CopyDeck.line(Inks.pack().copy, &"hint_bank",
						host.meta.runs_recorded,
						{"points": int(event["value"])})}}
	return {}


## Per batch: the promotion-available moment is a STATE (a fully geared
## trainee stands awaiting the oath), not an event. Returns {} or a row.
static func hint_on_ticks(host: GameHost) -> Dictionary:
	var units := host.units()
	for uid in units.awaiting_promotion_ids():
		if units.missing_gear_slots(uid).is_empty():
			if _hint_flag(host, &"hint_promote"):
				return {"row": {"class": Inks.LineClass.PLAIN,
					"text": CopyDeck.line(Inks.pack().copy, &"hint_promote",
						host.engine.tick_count)}}
			return {}
	return {}


## The odds table's first opening (the screen's open_assault verb calls
## this). Returns {} or a row.
static func hint_odds_if_first(host: GameHost) -> Dictionary:
	if _hint_flag(host, &"hint_odds"):
		return {"row": {"class": Inks.LineClass.PLAIN,
			"text": CopyDeck.line(Inks.pack().copy, &"hint_odds",
				host.engine.tick_count)}}
	return {}


static func _hint_flag(host: GameHost, flag: StringName) -> bool:
	if host.meta.first_session_flag(flag):
		return false
	host.meta.set_first_session_flag(flag)
	host.save_manager.save_meta(host.meta)
	return true


# --- internals -----------------------------------------------------------------------------


## The honest MOMENT a step's note can pin on: {params, focus} or {} —
## the note never names a card that is not on the table.
static func _moment(host: GameHost, id: StringName) -> Dictionary:
	var units := host.units()
	match id:
		&"gate":
			var offers: Array[int] = units.offer_ids()
			if offers.is_empty():
				return {}
			return {"params": {"name": _recruit_name(host, int(offers[0]))},
				"focus": "offer_%d" % int(offers[0])}
		&"assign":
			var idle: Array = units.idle_units(units.base_unit_id())
			if idle.is_empty():
				return {}
			return {"params": {"name": _recruit_name(host, int(idle[0]))},
				"focus": "unit_%d" % int(idle[0])}
		&"build":
			var plot := _affordable_plot(host)
			if plot.is_empty():
				return {}
			return {"params": {"building": String(plot["name"])},
				"focus": "bld_%s" % String(plot["id"])}
		&"train":
			if units.idle_units(&"militia").is_empty():
				return {}
			return {"params": {}, "focus": ""}
		&"gear":
			if units.awaiting_promotion_ids().is_empty():
				return {}
			return {"params": {}, "focus": ""}
		&"promote":
			for uid in units.awaiting_promotion_ids():
				if units.missing_gear_slots(int(uid)).is_empty():
					return {"params": {}, "focus": "unit_%d" % int(uid)}
			return {}
		&"storm":
			if not host.assault().floor_met(host.engine):
				return {}
			return {"params": {}, "focus": ""}
	return {}


## Complete a step and every step before it (the forgiving arc: a later
## action finishes the earlier teachings). Prints the farewell line when
## the whole arc completes through its LAST step; the run-end
## graduation stays quiet (the world's ending lines carry it).
func _advance(host: GameHost, id: StringName) -> void:
	var last := StringName(String(ARC[ARC.size() - 1]["id"]))
	var was_last := id == last
	_complete_through(host, id)
	if was_last and not host.meta.first_session_flag(&"done"):
		_mark(host, &"done")
		_graduation_row = {"class": Inks.LineClass.PLAIN,
			"text": CopyDeck.line(Inks.pack().copy, &"objective_graduated",
				host.engine.tick_count)}


func _complete_through(host: GameHost, id: StringName) -> void:
	for step: Dictionary in ARC:
		var step_id: StringName = step["id"]
		if not host.meta.first_session_flag(step_id):
			_mark(host, step_id)
		if step_id == id:
			return


## The nudge the screen delivers after a trigger: the note's change plus
## the new moment's focus (p_landed names a step whose OWN moment should
## be highlighted — the arrival's offer, the accept's idle body, the
## gear step's ready trainee). A row (the graduation farewell) rides
## along when the arc just completed.
func _moment_nudge(host: GameHost, before: Dictionary, p_landed: StringName) -> Dictionary:
	var out := {}
	if not _graduation_row.is_empty():
		out["row"] = _graduation_row
		_graduation_row = {}
	var current := current_objective(host)
	if current.is_empty():
		return out
	var focus := String(current["focus"])
	if not p_landed.is_empty() and StringName(String(current["id"])) != p_landed \
			and not before.is_empty() and StringName(String(before["id"])) == p_landed:
		focus = String(before["focus"])  # the landed step's own affordance leads
	if not focus.is_empty():
		out["focus"] = focus
	if before.is_empty() or String(current["text"]) != String(before["text"]):
		out["note_changed"] = true
	return out


## The farewell line a completing arc leaves for the screen (consumed by
## the next _moment_nudge; {} = none pending).
var _graduation_row: Dictionary = {}


## Fire = flip + persist the META domain NOW (the once-only guarantee
## must survive a crash one print later). Returns true when it flipped.
func _mark(host: GameHost, beat: StringName) -> bool:
	if not host.meta.set_first_session_flag(beat):
		return false
	host.save_manager.save_meta(host.meta)
	return true


## The run ended (any outcome) or a new hand was dealt: the first
## session's arc is over whatever steps remain — graduate quietly.
func _check_ended(event: Dictionary, host: GameHost) -> void:
	if not active:
		return
	match event["type"]:
		&"run_won", &"run_lost", &"run_aborted", &"run_crushed", \
			&"run_restarted", &"run_started":
			if not host.meta.first_session_flag(&"done"):
				_mark(host, &"done")
			active = false


## The crowded-table graduation's threshold: ten people on or awaiting
## the table (units + gate offers) is a working estate — the opening
## lesson is over whether or not every step printed.
static func _crowded(host: GameHost) -> bool:
	return host.units().total_units() + host.units().pending_offers() >= 10


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
## note never names a verb the pool cannot pay).
static func _affordable_plot(host: GameHost) -> Dictionary:
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


static func _any_built(host: GameHost) -> bool:
	for building: BuildingDef in Inks.pack().buildings:
		if host.production().building_level(building.id) > 0:
			return true
	return false


static func _payable(host: GameHost, cost: Dictionary) -> bool:
	for resource in cost:
		if host.engine.get_resource(resource) < int(cost[resource]):
			return false
	return true


## True for terminal combat ranks (knight/archer) — the promotion into
## them completes the arc (the same rule the spread's flip uses).
static func _is_army_def(host: GameHost, def_id: StringName) -> bool:
	for def: UnitDef in Inks.pack().units:
		if def.id == def_id:
			return def.combat_power > 0 and def.promotion_paths.is_empty()
	return false


static func _recruit_name(host: GameHost, uid: int) -> String:
	return SpreadPresenter.recruit_name(Inks.pack(), uid)
