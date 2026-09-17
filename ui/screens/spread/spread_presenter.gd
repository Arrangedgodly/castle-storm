## SpreadPresenter — the Spread's pure view layer (T-UI-03).
##
## Everything the home screen renders derives from ONE deterministic view
## model built from the host's read APIs: same sim state => same view
## (view_hash pins it), so the spread is a FUNCTION of the sim, never of
## UI history. Two pure mappings sit beside it:
##
##   - refresh_targets_for(event): which view sections an event changes —
##     the event->targeted-refresh contract (no per-frame whole-state
##     polling; the screen rebinds only what an event touched);
##   - chronicle_line_for(event): the "states print themselves" render
##     query — event kinds that the strip prints become {class, text}
##     rows (Inks.line_class_for_event + placeholder Prof X voice,
##     T-COPY-01 deepens); suspicion beats DELEGATE to the system's own
##     chronicle_line (one voice source per vocabulary).
##
## State kept across events: the chronicle buffer (presentation history —
## the engine's ring is bounded and unserialized, exactly like §3 says
## presentation history lives outside the sim) and THE DAY-SHEET — the
## live run's own accumulating ledger (finishing refinement #2): every
## row that ever printed on the strip (push_row is the one choke point —
## events, nudges, refusals, the primer, the autosave line) PLUS the
## blockquote-only payloads (the scatter rows with names, the catch-up
## print's detail rows). Run-scoped by contract: a new hand turns the
## page (begin_day_sheet_page), and it is NEVER persisted — the durable
## record of a run is the chronicle entry it becomes (RunMeta); the
## day-sheet is the clerk's working paper for the hand in play.
class_name SpreadPresenter
extends RefCounted

## Chronicle rows kept in the rolling buffer (the strip shows the newest
## CHRONICLE_STRIP_LINES of these).
const CHRONICLE_BUFFER: int = 12
## Rows the slot's chronicle strip prints (the OrientationSlot contract:
## 2 composed ChronicleLine rows).
const CHRONICLE_STRIP_LINES: int = 2

## Default day-sheet ceiling (test seam: the var). Bounds the page's
## memory and the sheet's node churn at open; past it the OLDEST prints
## leave the sheet and the view reports the truncation honestly. 600 rows
## covers ~8 days of wall-time play at the sim's print cadence — far past
## any real hand's retrieval needs, small enough to stay cheap.
const DAY_SHEET_CAP_DEFAULT: int = 600

## The suspicion vocabulary (thresholds mirrored from the tunables the
## host's engine was composed with; read live via _suspicion_thresholds
## so content retunes flow through).
const EYE_STATES: Array[StringName] = [&"watching", &"closing", &"striking"]

## Rolling chronicle rows, oldest first ({class: int, text: String}).
var chronicle: Array[Dictionary] = []

## THE DAY-SHEET (finishing refinement #2): the live run's page, oldest
## first, append order — the retrieval surface for every line this hand
## has printed (the strip keeps 2 rows and the buffer 12; the day-sheet
## keeps the hand). Cleared by begin_day_sheet_page at run boundaries.
var day_sheet: Array[Dictionary] = []

## Rows pressed off the top of the page past the cap (reported honestly).
var day_sheet_dropped := 0

## Day-sheet ceiling (the test seam over DAY_SHEET_CAP_DEFAULT).
var day_sheet_cap := DAY_SHEET_CAP_DEFAULT


# --- the view model ------------------------------------------------------------------


## The whole spread as data. Pure: reads only the systems' documented
## query surfaces; builds the SAME dictionary for the SAME sim state.
static func build_view(host: GameHost) -> Dictionary:
	var run := host.run()
	var units := host.units()
	var production := host.production()
	var suspicion := host.suspicion()
	var assault := host.assault()
	var pack := Inks.pack()

	var leader := {
		"name": run.leader_name(),
		"epithet": run.leader_epithet(),
		"regime_id": run.regime_id(),
		"regime_name": Inks.regime_name(run.regime_id()),
		"run_index": run.current_run_index(),
	}
	var resources: Array[Dictionary] = []
	for id in pack.resources:
		resources.append({"id": id, "amount": host.engine.get_resource(id)})

	var cards: Array[Dictionary] = []
	# The gate first — offers are the newest paper on the table.
	var base_id := units.base_unit_id()
	for uid in units.offer_ids():
		cards.append(offer_card_view(pack, base_id, uid))
	# The estate in arrival order (roster order is the chronicle's key).
	for uid in units.unit_ids():
		cards.append(unit_card_view(host, pack, uid))
	# The buildings last, pack order (the estate's fixed furniture) —
	# UNBUILT buildings stake their plots too (T-UI-10): the empty spread
	# carries the build-order menu as paper on the table, and the card
	# id survives the raise (the plot becomes the building in place).
	for building: BuildingDef in pack.buildings:
		cards.append(_building_card(production, building,
			production.building_level(building.id)))
	# The regime's second ink hairlines every card on the table (one
	# content-driven recolor pass — a regime swap re-inks the spread).
	for card in cards:
		card["regime_id"] = leader["regime_id"]

	var thresholds := _suspicion_thresholds(host)
	var eye := eye_metrics(
		suspicion.suspicion_points(), suspicion.max_points(),
		int(thresholds["warn"]), int(thresholds["crackdown"]),
		suspicion.crackdown_land_tick != -1, run.is_running())

	return {
		"leader": leader,
		"running": run.is_running(),
		"phase": phase_for(host),
		"resources": resources,
		"cards": cards,
		"eye": eye,
		"eye_hours_left": eye_hours_left(host),
		"sim_hours": host.engine.sim_hours(),
		"army_power": units.army_power(),
	}


## The cards section alone (the targeted path for roster-changing
## events): reads ONLY the roster/estate query surfaces — no pips, no
## eye, no header (each stays on its own channel).
static func cards_view(host: GameHost) -> Array[Dictionary]:
	var units := host.units()
	var production := host.production()
	var pack := Inks.pack()
	var regime_id := host.run().regime_id()
	var cards: Array[Dictionary] = []
	var base_id := units.base_unit_id()
	for uid in units.offer_ids():
		var card := offer_card_view(pack, base_id, uid)
		card["regime_id"] = regime_id
		cards.append(card)
	for uid in units.unit_ids():
		var card := unit_card_view(host, pack, uid)
		if card.is_empty():
			continue
		card["regime_id"] = regime_id
		cards.append(card)
	for building: BuildingDef in pack.buildings:
		var card := _building_card(production, building,
			production.building_level(building.id))
		card["regime_id"] = regime_id
		cards.append(card)
	return cards


## Determinism oracle: a stable hash over the view's CONTENT (not node
## identity) — two hosts in the same sim state build the same hash.
static func view_hash(view: Dictionary) -> int:
	var h := 0x811C9DC5
	h = _mix(h, String(view["leader"]["name"]).hash())
	h = _mix(h, String(view["leader"]["regime_id"]).hash())
	h = _mix(h, int(view["leader"]["run_index"]))
	h = _mix(h, int(view["phase"]))
	h = _mix(h, int(view["running"]))
	for resource: Dictionary in view["resources"]:
		h = _mix(h, String(resource["id"]).hash())
		h = _mix(h, int(resource["amount"]))
	for card: Dictionary in view["cards"]:
		h = _mix(h, String(card["id"]).hash())
		h = _mix(h, String(card["name"]).hash())
		h = _mix(h, String(card["role"]).hash())
		h = _mix(h, String(card["face_key"]).hash())
		h = _mix(h, Inks.edge_form_for_state(card["edge_state"]))
		h = _mix(h, int(card["misprint_seed"]))
	var eye: Dictionary = view["eye"]
	h = _mix(h, int(eye["visible"]))
	h = _mix(h, int(eye["edge_form"]))
	h = _mix(h, int(round(eye["inset"] * 1000.0)))
	h = _mix(h, int(round(eye["scale"] * 1000.0)))
	return h


## FNV-flavored 32-bit mix (the SimEngine._mix shape — stable, no
## platform-sensitive ordering anywhere near it).
static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF


# --- cards ----------------------------------------------------------------------------


## A recruit name from the identity pool — deterministic per uid (the
## identity-is-a-query pattern, M1 finding F5: no per-unit name state).
static func recruit_name(pack: ContentPack, uid: int) -> String:
	var pool: Array = pack.identity.recruit_names
	if pool.is_empty():
		return "Recruit %d" % uid
	return String(pool[(uid - 1) % pool.size()])


## One gate-offer card view (public: the screen re-derives single cards
## for targeted refreshes).
static func offer_card_view(pack: ContentPack, base_id: StringName, uid: int) -> Dictionary:
	var def := _unit_def(pack, base_id)
	return {
		"id": "offer_%d" % uid,
		"uid": uid,
		"kind": &"offer",
		"name": recruit_name(pack, uid),
		"role": "waits at the gate",
		"face_key": def.face_id if def != null else &"",
		"edge_state": &"held",
		"misprint_seed": uid,
	}


## One estate-unit card view (public: the screen's countdown plates
## re-derive single cards without a roster pass).
static func unit_card_view(host: GameHost, pack: ContentPack, uid: int) -> Dictionary:
	var units := host.units()
	var def_id := units.unit_def(uid)
	if def_id == &"":
		return {}
	var def := _unit_def(pack, def_id)
	var state := &"idle"
	var role := "loafs by the fire"
	match def_id:
		&"worker":
			state = &"working"
			role = "works the estate"
		&"militia":
			state = &"ready"
			role = "drills in the yard"
		&"trainee", &"knight", &"archer":
			state = &"ready"
			role = "stands ready"
	var target := units.training_target(uid)
	if units.is_awaiting_promotion(uid):
		state = &"awaiting_gear"
		role = "awaits a kit (%d missing)" % units.missing_gear_slots(uid).size()
	elif target != &"":
		state = &"training"
		role = "trains (%s) — %s left" % [
			_display_name(pack, target), _hours_left_label(units, uid)]
	elif def_id == &"knight":
		role = "sworn sword"
	elif def_id == &"archer":
		role = "the watching bow"
	return {
		"id": "unit_%d" % uid,
		"uid": uid,
		"kind": &"unit",
		"name": recruit_name(pack, uid),
		"role": role,
		"face_key": def.face_id if def != null else &"",
		"edge_state": state,
		"misprint_seed": uid,
	}


static func _building_card(production: ProductionSystem, building: BuildingDef, level: int) -> Dictionary:
	# Level 0 = the STAKED PLOT (T-UI-10): the build-order choice as a
	# card on the table — dashed edge (queued paper), the "Raise it" verb
	# in its fan when the pool can pay. Same card id as the built card,
	# so raising it rebinds the paper in place instead of re-dealing.
	var role := "level %d · %d/%d workers" % [
		level, production.assigned_workers(building.id), production.worker_slots(building.id)]
	var edge := &"ready"
	if level < 1:
		role = "staked plot — unbuilt"
		edge = &"queued"
	return {
		"id": "bld_%s" % String(building.id),
		"uid": 0,
		"kind": &"building",
		"building_id": String(building.id),
		"name": building.display_name,
		"role": role,
		"face_key": building.icon_id,
		"edge_state": edge,
		"misprint_seed": absi(String(building.id).hash() % 9973),
	}


static func _unit_def(pack: ContentPack, id: StringName) -> UnitDef:
	for def: UnitDef in pack.units:
		if def.id == id:
			return def
	return null


static func _display_name(pack: ContentPack, id: StringName) -> String:
	var def := _unit_def(pack, id)
	return def.display_name if def != null else String(id)


## "2.4h" from a running training timer (milli-ticks -> hours).
static func _hours_left_label(units: UnitLifecycleSystem, uid: int) -> String:
	var duration := units.training_duration_milli(units.training_target(uid))
	var left_milli := duration - units.training_progress_milli(uid)
	var hours := float(maxi(0, left_milli)) / 1000.0 / float(SimEngine.TICKS_PER_SIM_HOUR)
	if hours >= 1.0:
		return "%.1fh" % hours
	return "%dm" % int(round(hours * 60.0))


# --- the Watchful Eye (the design's signature tension visual) -------------------------


## The Eye's render metrics from the meter. POSITION (inset 0..1: how far
## the card has crept INTO the table from its right-edge perch) and the
## LINE-FORM channel (the Daredevil floor: readable without color — solid
## watching / dashed closing / struck strike-imminent) BOTH scale with the
## meter, plus dread (alpha) and scale. Thresholds are the sim's own
## (warn/crackdown); the telegraph countdown overrides to the STRUCK form
## — the Crown's verdict is being printed. No run: the Eye withdraws.
##
## THE ARMED ESCALATION (finishing refinement #3, the closing critique's
## P2): an armed telegraph is a STATE, not a level — the Eye OVERRIDES the
## meter's own creep and commits to the deep seat (inset 1.0, full card
## scale, full dread) whatever the meter's residue. The RESTING creep is
## untouched: unarmed metrics are exactly the authored meter functions
## (the quiet creep is the design; only the armed state is loud).
static func eye_metrics(points: int, max_points: int, warn: int, crackdown: int,
		telegraph_armed: bool, run_alive: bool) -> Dictionary:
	var clamped_max := maxi(1, max_points)
	var progress: float = clampf(float(points) / float(clamped_max), 0.0, 1.0)
	var visible: bool = run_alive and points > 0
	# A dead run has no armed telegraph (the Eye withdraws; the table's
	# lane reserve lifts with it — see the screen's eye-reserve bind).
	var armed := telegraph_armed and run_alive
	var edge_form: int = Inks.EdgeForm.SOLID
	if telegraph_armed or points >= crackdown:
		edge_form = Inks.EdgeForm.STRUCK
	elif points >= warn:
		edge_form = Inks.EdgeForm.DASHED
	return {
		"visible": visible,
		"points": points,
		"max_points": clamped_max,
		"inset": 1.0 if armed else progress,
		"scale": 1.0 if armed else 0.55 + 0.45 * progress,
		"dread": 1.0 if armed else 0.55 + 0.45 * progress,
		"edge_form": edge_form,
		"armed": armed,
	}


## Hours until an armed telegraph lands (crackdown countdown), -1 unarmed.
static func eye_hours_left(host: GameHost) -> int:
	var suspicion := host.suspicion()
	if suspicion.crackdown_land_tick == -1:
		return -1
	var ticks := suspicion.crackdown_land_tick - host.engine.tick_count
	return maxi(0, ticks) / SimEngine.TICKS_PER_SIM_HOUR


# --- run phase (the phase-deepening ground) -------------------------------------------


## Recruiting -> training -> ready-to-storm via ARMY STATE (the brief's
## ambient-progress raise): the assault's own knight floor decides
## "ready"; any military pipeline (militia/trainee/commissioned army)
## deepens to training; a dead run washes to aftermath.
static func phase_for(host: GameHost) -> Inks.Phase:
	if not host.is_run_running():
		return Inks.Phase.AFTERMATH
	var units := host.units()
	var assault := host.assault()
	if assault != null and assault.floor_met(host.engine):
		return Inks.Phase.READY
	var military: int = units.unit_count(&"militia") + units.unit_count(&"trainee") \
		+ units.unit_count(&"knight") + units.unit_count(&"archer")
	if military > 0 or units.army_power() > 0:
		return Inks.Phase.TRAINING
	return Inks.Phase.RECRUITING


static func _suspicion_thresholds(host: GameHost) -> Dictionary:
	var tunables: EconomyTunables = Inks.pack().tunables
	return {"warn": tunables.suspicion_warn_threshold, "crackdown": tunables.suspicion_crackdown_threshold}


# --- event -> targeted refresh (THE no-polling contract) ------------------------------


## View sections an event touches. The screen rebinds ONLY these — a
## training tick never rebuilds the roster, a suspicion rise never touches
## the cards. "full" = everything (run boundaries, catch-up, the unknown-
## kind safety net — loud).
static func refresh_targets_for(event_type: StringName) -> Array[StringName]:
	match event_type:
		&"recruit_arrived":
			return [&"cards"]
		&"recruit_accepted", &"recruit_dismissed", &"crackdown_scattered", &"assault_casualties":
			return [&"cards", &"phase"]
		&"training_started", &"training_complete", &"training_progress", &"gear_equipped":
			return [&"card"]
		&"unit_promoted":
			return [&"card", &"phase"]
		&"building_built", &"building_upgraded", &"building_milestone":
			return [&"card", &"cards", &"pips", &"phase"]
		&"worker_added", &"worker_removed", &"worker_assigned", &"worker_unassigned":
			return [&"card"]
		&"resources_granted":
			return [&"pips"]
		&"suspicion_rose", &"suspicion_warn", &"crackdown_cancelled", &"crackdown_struck", &"crackdown_seized":
			return [&"eye", &"pips"]
		&"suspicion_telegraph":
			return [&"eye"]
		&"run_crushed", &"run_won", &"run_lost", &"run_aborted", &"run_started", &"run_restarted", &"escalation_captured":
			return [&"full"]
		&"catch_up_applied", &"catch_up_clock_rewound":
			return [&"full"]
		&"assault_won", &"assault_lost", &"assault_denied", &"assault_beat":
			return [&"cards", &"phase"]
		&"hour_struck":
			return [&"phase"]
		&"ping_counted", &"command_rejected", &"run_denied", &"lifecycle_denied", &"upgrade_denied", \
				&"worker_pool_denied", &"assignment_denied":
			return [&"chronicle"]
		_:
			push_warning("spread: unknown event kind '%s' — full refresh (extend the map)" % event_type)
			return [&"full"]


# --- the chronicle (states print themselves — never popup chrome) ---------------------


## Render query: the printed line for an event, or null to stay silent
## (plumbing noise: quarter-marks, hour bells, worker moves, vignette
## beats — T-UI-07 owns the beat stream's own rendering). T-COPY-01: the
## strip's copy reads the pack's CopyTable through CopyDeck, variant
## rotated by the event's seq (repeats vary, replay is identical); the
## suspicion vocabulary delegates to the system's own voice (same table,
## its own copy seam).
func chronicle_line_for(event: Dictionary, host: GameHost) -> Variant:
	var kind: StringName = event["type"]
	var pack := Inks.pack()
	var suspicion := host.suspicion()
	# Suspicion vocabulary delegates to the system's own voice.
	var line := suspicion.chronicle_line(_as_sim_event(event))
	if not line.is_empty():
		return {"class": Inks.line_class_for_event(kind), "text": line}
	var table: CopyTable = pack.copy
	var rotor := int(event["seq"])
	var name := recruit_name(pack, int(event["value"]))
	match kind:
		&"recruit_arrived":
			return _row(kind, CopyDeck.line(table, &"recruit_arrived", rotor, {"name": name}))
		&"recruit_accepted":
			return _row(kind, CopyDeck.line(table, &"recruit_accepted", rotor, {"name": name}))
		&"recruit_dismissed":
			return _row(kind, CopyDeck.line(table, &"recruit_dismissed", rotor, {"name": name}))
		&"training_started":
			return _row(kind, CopyDeck.line(table, &"training_started", rotor,
				{"name": name, "rank": _display_name(pack, event["subject"])}))
		&"training_complete":
			return _row(kind, CopyDeck.line(table, &"training_complete", rotor,
				{"name": name, "rank": _display_name(pack, event["subject"])}))
		&"unit_promoted":
			return _row(kind, CopyDeck.line(table, &"unit_promoted", rotor,
				{"name": name, "rank": _display_name(pack, event["subject"]),
					"count": int(event["value2"])}))
		&"gear_equipped":
			return _row(kind, CopyDeck.line(table, &"gear_equipped", rotor,
				{"name": name, "gear": _gear_name(pack, event["subject"])}))
		&"building_built":
			return _row(kind, CopyDeck.line(table, &"building_built", rotor,
				{"building": _building_name(pack, event["subject"])}))
		&"building_upgraded":
			return _row(kind, CopyDeck.line(table, &"building_upgraded", rotor,
				{"building": _building_name(pack, event["subject"]), "level": int(event["value"])}))
		&"building_milestone":
			return _row(kind, CopyDeck.line(table, &"building_milestone", rotor,
				{"building": _building_name(pack, event["subject"])}))
		&"resources_granted":
			return _row(kind, CopyDeck.line(table, &"resources_granted", rotor,
				{"count": int(event["value"]), "resource": String(event["subject"])}))
		&"run_started":
			return _row(kind, CopyDeck.line(table, &"run_started", rotor, {
				"first": host.run().leader_first_name(),
				"regime": Inks.regime_name(host.run().regime_id())}))
		&"run_restarted":
			return _row(kind, CopyDeck.line(table, &"run_restarted", rotor, {
				"first": host.run().leader_first_name(),
				"regime": Inks.regime_name(host.run().regime_id())}))
		&"run_won":
			return _row(kind, CopyDeck.line(table, &"run_won", rotor,
				{"points": int(event["value"])}))
		&"escalation_captured":
			# The L2 victory beat (L2-B): the winning army takes the wall as
			# the next cycle's garrison — printed right before the outcome's
			# own row. The snapshot stands in the run system's meta window;
			# the leader prints by FIRST name (the single-line pool rule).
			var snapshot: Dictionary = host.run().escalation_garrison()
			var captured_leader := String(snapshot.get("leader", ""))
			var leader_split := captured_leader.find(" ")
			return _row(kind, CopyDeck.line(table, &"escalation_captured", rotor, {
				"leader": captured_leader if leader_split <= 0 else captured_leader.substr(0, leader_split),
				"cycle": int(event["value"]),
			}))
		&"run_lost":
			return _row(kind, CopyDeck.line(table, &"run_lost", rotor,
				{"points": int(event["value"])}))
		&"run_aborted":
			return _row(kind, CopyDeck.line(table, &"run_aborted", rotor,
				{"points": int(event["value"])}))
		&"assault_casualties":
			return _row(kind, CopyDeck.line(table, &"assault_casualties", rotor,
				{"count": int(event["value"])}))
		&"assault_lost":
			# The spread's rolling record (the vignette owns the moment; the
			# chronicle owns the history — both in-world, never chrome).
			return _row(kind, CopyDeck.line(table, &"assault_lost", rotor,
				{"regime": Inks.regime_name(event["subject"]) if event["subject"] != &"" else "the Crown"}))
		&"assault_denied":
			return _row(kind, CopyDeck.line(table, &"assault_denied", rotor,
				{"power": int(event["value2"])}))
		&"catch_up_applied":
			# One voice source for the window's headline: the strip row, the
			# blockquote's lead and the check-in reveal's away line all read
			# CatchUpPrint (T-UI-09). value2 = the clamped seconds that
			# actually applied.
			return _row(kind, CatchUpPrint.headline_text(int(event["value2"])))
		&"catch_up_clock_rewound":
			return _row(kind, CopyDeck.line(table, &"catch_up_clock_rewound", rotor))
		&"upgrade_denied", &"lifecycle_denied", &"run_denied":
			return _row(kind, CopyDeck.line(table, &"clerk_denied", rotor,
				{"reason": int(event["value"])}))
		&"command_rejected":
			return _row(kind, CopyDeck.line(table, &"command_rejected", rotor,
				{"command": String(event["subject"])}))
		_:
			return null


## Append an already-rendered row to the rolling buffer (the screen's
## event path; rows render once, at event time). The SAME row lands on the
## day-sheet — one choke point, so strip, buffer and the run's page can
## never disagree about what printed.
func push_row(row: Dictionary) -> void:
	chronicle.append(row)
	if chronicle.size() > CHRONICLE_BUFFER:
		chronicle = chronicle.slice(chronicle.size() - CHRONICLE_BUFFER)
	day_sheet.append(row)
	while day_sheet.size() > day_sheet_cap:
		day_sheet.pop_front()
		day_sheet_dropped += 1


## Append blockquote-only rows to the day-sheet (WITHOUT the rolling
## buffer — these payloads printed as paper on the table, not as strip
## lines: the scatter rows with the swept gate crowd's NAMES, the
## while-you-were-away print's detail rows beyond the headline). The
## day-sheet records what the player SAW print, blockquote included.
func push_rows(rows: Array[Dictionary]) -> void:
	for row in rows:
		day_sheet.append(row)
	while day_sheet.size() > day_sheet_cap:
		day_sheet.pop_front()
		day_sheet_dropped += 1


## A new hand was dealt: the page turns. The caller invokes this at the
## run_started/run_restarted boundary BEFORE the boundary's own line
## prints, so the new page opens with its own announcement.
func begin_day_sheet_page() -> void:
	day_sheet.clear()
	day_sheet_dropped = 0


## The page as the sheet prints it: NEWEST FIRST (documented choice — the
## strip reads newest-first, the chronicle ring pages newest-first, and
## the line being sought is almost always a recent one; reading order
## matches arrival order on every print surface in this world).
func day_sheet_newest_first() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in day_sheet.size():
		rows.append(day_sheet[day_sheet.size() - 1 - i])
	return rows


## Append an event's line to the rolling buffer (no-op for silent kinds).
func push_chronicle(event: Dictionary, host: GameHost) -> void:
	var row: Variant = chronicle_line_for(event, host)
	if row == null:
		return
	push_row(row)


## The strip rows to print, NEWEST FIRST (the top of the strip is the
## latest print — reading order matches arrival order).
func chronicle_strip() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in mini(CHRONICLE_STRIP_LINES, chronicle.size()):
		rows.append(chronicle[chronicle.size() - 1 - i])
	return rows


func _row(kind: StringName, text: String) -> Dictionary:
	return {"class": Inks.line_class_for_event(kind), "text": text}


static func _gear_name(pack: ContentPack, id: StringName) -> String:
	for gear: GearDef in pack.gear:
		if gear.id == id:
			return gear.display_name
	return String(id)


static func _building_name(pack: ContentPack, id: StringName) -> String:
	for building: BuildingDef in pack.buildings:
		if building.id == id:
			return building.display_name
	return String(id)


## A transient SimEvent for the suspicion system's own render query (its
## chronicle_line reads the pooled shape; we hand it a copy of ours).
static func _as_sim_event(event: Dictionary) -> SimEvent:
	var sim_event := SimEvent.new()
	sim_event.seq = int(event["seq"])
	sim_event.tick = int(event["tick"])
	sim_event.type = event["type"]
	sim_event.subject = event["subject"]
	sim_event.value = int(event["value"])
	sim_event.value2 = int(event["value2"])
	return sim_event
