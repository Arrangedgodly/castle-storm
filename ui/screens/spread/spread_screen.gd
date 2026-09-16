## The Spread — the game's home screen (T-UI-03).
##
## "The game IS the conspirators' card table" (design brief §3): this
## screen binds a REAL GameHost to the responsive foundation so card
## positions reflect live sim state at all layout sizes —
##   - conspirator cards: gate offers + the estate roster (workers,
##     trainees, army) + the built buildings, one composed CardFrame each,
##     state by LINE FORM;
##   - resource pips along the table edge (live values, abbreviated
##     idle-scale numerals);
##   - the Watchful Eye card creeping into the periphery as suspicion
##     rises (position + line form + dread scale — never color alone);
##   - ground tone deepening by run phase (recruiting -> training ->
##     ready-to-storm, aftermath after);
##   - the chronicle strip printing recent events in-world (offers,
##     completions, crackdowns land as printed lines — never popups);
##   - the run header (leader name + regime ink).
##
## LIVE UPDATES ARE EVENT-DRIVEN: the presenter's refresh_targets_for maps
## each event to the view sections it touches; the screen rebinds exactly
## those (stats counts every pass — tests assert no whole-state polling).
## `sim_advanced` (one signal per processed batch) is the only periodic
## hook: pips + training countdowns + the phase probe ride it, because
## production accrual and army growth settle silently (no events).
##
## Deterministic UI from sim state: every bind derives from the
## presenter's view model — same sim state -> same rendered spread
## (layout_hash pins it; focus ids are index-synced so the router's swap
## equivalence is part of the render too).
##
## Input parity (the T-UI-02 foundation): focus chains follow card order
## in both slots (the router restores place across swaps); every
## interactive card keeps the 48-unit grip. `debug_fast_forward` cycles
## the demo's time scale (1x -> 60x -> 600x); `pause` freezes the world
## through the host seam. Card interactions themselves are T-UI-04's;
## this screen is the live table they will act on.
##
## Dev inspection hook (not a game path): CS_SPREAD_SHOT=/path.png renders
## for a settling window and saves one capture, then quits; pair with
## CS_SPREAD_LOUD=1 for the pressured state (see _capture_hook).
extends ResponsiveScreen

const RUN_HEADER_SCRIPT := preload("res://ui/screens/spread/run_header.gd")
const WATCHFUL_EYE_SCRIPT := preload("res://ui/screens/spread/watchful_eye.gd")

## Default demo seed (deterministic identity + arrival draw; override
## with CS_SEED).
const DEFAULT_SEED := 20261103

## Demo time-scale ladder cycled by debug_fast_forward.
const TIME_SCALES: Array[float] = [1.0, 60.0, 600.0]

## Autosave cadence for the demo session (every sim hour).
const AUTOSAVE_TICKS := SimEngine.TICKS_PER_SIM_HOUR

## Chronicle rows the slot strip prints (the OrientationSlot contract).
const STRIP_LINES := 2

var host: GameHost
var presenter := SpreadPresenter.new()
var demo_policy: DemoPolicy
var time_scale_index := 0

## Refresh instrumentation (tests assert targeted updates, no polling).
var stats := {
	&"view_builds": 0, &"card_rebinds": 0, &"card_list_renders": 0, &"pip_refreshes": 0,
	&"eye_binds": 0, &"header_binds": 0, &"phase_binds": 0, &"chronicle_prints": 0,
}

var _view := {}
var _scale_chip: Label


func _ready() -> void:
	# Tests may attach a pre-driven host BEFORE adding the scene to the
	# tree; the demo builds its own otherwise.
	if host == null:
		host = build_demo_host()
	super._ready()
	_compose_slot_chrome()
	host.event_observed.connect(_on_event)
	host.sim_advanced.connect(_on_ticks)
	host.run_state_changed.connect(func(_running: bool) -> void: refresh_from_state())
	get_viewport().size_changed.connect(_on_layout_changed)
	get_router().orientation_changed.connect(func(_o: int) -> void: _on_layout_changed())
	_build_debug_chip()
	# DEFERRED: the slots lay themselves out via a deferred call at their
	# own _ready (queued before this one), so the first bind must land
	# AFTER settled slot rects — column ladders and the Eye's perch read
	# the real spread geometry, never the pre-layout zero (the exact
	# stale-columns failure the layout-determinism test caught).
	refresh_from_state.call_deferred()
	_capture_hook()


## The seeded demo session: a real save-backed host. CS_DEMO_RESET=1 (the
## Makefile default) wipes the demo save root so every `make run-game` is
## the same seeded fresh run; CS_DEMO_RESET=0 continues the session.
func build_demo_host() -> GameHost:
	var root := "user://saves"
	if OS.get_environment("CS_DEMO_RESET") != "0":
		_wipe_save_root(root)
	var seed_value := DEFAULT_SEED
	var seed_text := OS.get_environment("CS_SEED")
	if not seed_text.is_empty() and seed_text.is_valid_int():
		seed_value = int(seed_text)
	var demo := GameHost.new(seed_value, root)
	demo.autosave_interval_ticks = AUTOSAVE_TICKS
	demo.boot(0)
	if OS.get_environment("CS_SPREAD_LOUD") == "1":
		demo_policy = DemoPolicy.new(40, 40, true)
	else:
		demo_policy = DemoPolicy.new(16, 8, false)
	return demo


func _wipe_save_root(root: String) -> void:
	## Platform-host housekeeping for the demo (user:// only, never res://).
	if not root.begins_with("user://"):
		return
	for file in DirAccess.get_files_at(root):
		DirAccess.remove_absolute(root + "/" + file)


# --- full re-render (boot, run boundaries, catch-up, tests) --------------------------


## Rebuild the WHOLE view and rebind every section in both slots. The
## deterministic path: the same sim state always produces the same binds.
func refresh_from_state() -> void:
	stats[&"view_builds"] += 1
	_view = SpreadPresenter.build_view(host)
	_bind_cards_list()
	_bind_pips()
	_bind_eye()
	_bind_header()
	_bind_phase()
	_bind_chronicle()


## Determinism oracle over one slot's RENDERED layout: card ids in order +
## their settled global rects + the Eye's position. Same sim state ->
## same hash (tests pin it).
func layout_hash(slot: OrientationSlot) -> int:
	var spread := slot.get_spread()
	var h := 0x811C9DC5
	for i in spread.get_child_count():
		var card: Control = spread.get_child(i) as Control
		if card == null:
			continue
		h = _mix(h, String(card.get_meta(&"spread_card_id", "")).hash())
		var rect: Rect2 = card.get_global_rect()
		h = _mix(h, int(rect.position.x * 100.0))
		h = _mix(h, int(rect.position.y * 100.0))
		h = _mix(h, int(rect.size.x * 100.0))
		h = _mix(h, int(rect.size.y * 100.0))
	var eye := eye_of(slot)
	if eye != null:
		h = _mix(h, int(eye.global_position.x * 100.0))
		h = _mix(h, int(eye.global_position.y * 100.0))
	return h


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF


# --- event-driven targeted refresh ----------------------------------------------------


## ONE event: map -> targeted rebinds. Never a whole-state pass here
## (only the "full" target — run boundaries, catch-up, unknown kinds).
func _on_event(event: Dictionary) -> void:
	var row: Variant = presenter.chronicle_line_for(event, host)
	if row != null:
		presenter.push_row(row)
		_bind_chronicle()
	var targets := SpreadPresenter.refresh_targets_for(event["type"])
	var uid := int(event["value"])
	for target: StringName in targets:
		match target:
			&"full":
				refresh_from_state()
				return
			&"cards":
				# The card LIST changed: re-derive the roster cards only (a
				# section read, NOT a whole-view build — pips/eye/header
				# stay on their own channels).
				stats[&"card_list_renders"] += 1
				_view["cards"] = SpreadPresenter.cards_view(host)
				_bind_cards_list(false)
			&"card":
				_rebind_card_by_uid(uid)
			&"pips":
				_bind_pips()
			&"eye":
				_bind_eye()
			&"phase":
				_bind_phase()
			&"chronicle":
				pass  # printed above


## Per-batch periodic hook (the ONLY polling-adjacent path, one signal
## per processed batch — not per frame): pips (production settles
## silently), training countdown plates, the phase probe (army growth is
## silent too), and the demo policy cadence.
func _on_ticks(ticks: int) -> void:
	stats[&"pip_refreshes"] += 1
	if _view.is_empty():
		return
	var view_resources: Array = _view["resources"]
	for i in view_resources.size():
		view_resources[i]["amount"] = host.engine.get_resource(view_resources[i]["id"])
	_bind_pips()
	_rebind_training_cards()
	_bind_phase()
	if demo_policy != null and demo_policy.on_ticks(ticks):
		demo_policy.apply(host)


# --- section binds ---------------------------------------------------------------------


## Cards for BOTH slots: diff the view's card list against each slot's
## spread (ids in order) — remove gone, add new, re-order moved, rebind
## the rest in place — then re-sync focus ids by index (the router's
## equivalence keys are part of the render). `count_render` bumps the
## instrumentation when called as a section render (not from full).
func _bind_cards_list(count_render := true) -> void:
	if count_render:
		stats[&"card_list_renders"] += 1
	var cards: Array = _view["cards"]
	var columns := SpreadCards.adaptive_columns(cards.size(), _portrait_spread_height())
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var spread := slot.get_spread() as Container
		var by_id := {}
		for child in spread.get_children():
			if child is Control:
				by_id[String(child.get_meta(&"spread_card_id", ""))] = child
		var view_ids := {}
		for card in cards:
			view_ids[String(card["id"])] = card
		for id in by_id.keys():
			if not view_ids.has(id):
				var gone: Node = by_id[id]
				spread.remove_child(gone)
				gone.queue_free()
		var index := 0
		for card: Dictionary in cards:
			var id := String(card["id"])
			if not by_id.has(id):
				slot.add_card(SpreadCards.conspirator_card(card))
			else:
				var node: Control = by_id[id]
				SpreadCards.rebind_card(node, card)
				if node.get_index() != index:
					spread.move_child(node, index)
			index += 1
		spread.set("columns", columns)
		spread.queue_sort()
		_sync_focus_ids(slot)


## One card's plates re-print in place (both slots) — the targeted path.
func _rebind_card_by_uid(uid: int) -> void:
	if uid <= 0:
		return
	for candidate_id in ["offer_%d" % uid, "unit_%d" % uid]:
		var card := _view_card(String(candidate_id))
		if card.is_empty():
			continue
		stats[&"card_rebinds"] += 1
		_rebind_card_nodes(String(candidate_id), card)


## Training countdowns tick silently: refresh only training/awaiting
## cards' role plates (a handful at roster scale — targeted, not a roster
## pass; the CARD LIST is untouched).
func _rebind_training_cards() -> void:
	var units := host.units()
	for card: Dictionary in _view["cards"]:
		if card["kind"] != &"unit":
			continue
		var uid := int(card["uid"])
		if units.training_target(uid) == &"" and not units.is_awaiting_promotion(uid):
			continue
		var fresh := SpreadPresenter.unit_card_view(host, Inks.pack(), uid)
		if fresh.is_empty():
			continue
		if String(fresh["role"]) != String(card["role"]) \
				or fresh["edge_state"] != card["edge_state"]:
			card["role"] = fresh["role"]
			card["edge_state"] = fresh["edge_state"]
			stats[&"card_rebinds"] += 1
			_rebind_card_nodes(String(card["id"]), card)


func _rebind_card_nodes(id: String, card: Dictionary) -> void:
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		for child in slot.get_spread().get_children():
			if child is Control and String(child.get_meta(&"spread_card_id", "")) == id:
				SpreadCards.rebind_card(child, card)


## Pips: live values into both rails (shape + glyph + numeral pips; rail
## order = pack resource order — the slot rail is FOOD/TIMBER/IRON).
## Reads ONLY the three resource ints (the pip section's own state).
func _bind_pips() -> void:
	if _view.is_empty():
		return
	var view_resources: Array = _view["resources"]
	for i in view_resources.size():
		view_resources[i]["amount"] = host.engine.get_resource(view_resources[i]["id"])
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		for i in mini(3, view_resources.size()):
			var pip := slot.get_pip(i)
			if pip != null:
				pip.set("amount", int(view_resources[i]["amount"]))


## The Eye: fresh metrics from the suspicion system (the eye section's
## own state — three ints and a countdown) bound in both slots, placed
## inside each slot's spread band (periphery = the right edge).
func _bind_eye() -> void:
	stats[&"eye_binds"] += 1
	var suspicion := host.suspicion()
	var tunables: EconomyTunables = Inks.pack().tunables
	var eye := SpreadPresenter.eye_metrics(
		suspicion.suspicion_points(), suspicion.max_points(),
		tunables.suspicion_warn_threshold, tunables.suspicion_crackdown_threshold,
		suspicion.crackdown_land_tick != -1, host.is_run_running())
	var hours_left := SpreadPresenter.eye_hours_left(host)
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var node := eye_of(slot)
		if node == null:
			continue
		node.bind(eye, hours_left)
		_place_eye(slot, node, eye)


func _place_eye(slot: OrientationSlot, node: Control, metrics: Dictionary) -> void:
	## The perch hugs the table's right edge, vertically centered in the
	## spread band; inset slides the card toward the table's heart. Always
	## fully inside the slot rect (nothing may clip outside the design).
	var spread_rect: Rect2 = slot.get_spread().get_global_rect()
	var slot_rect := slot.get_global_rect()
	var inset: float = metrics["inset"]
	var card_size: Vector2 = node.get_combined_minimum_size()
	var max_inset: float = maxf(0.0, spread_rect.size.x * 0.5 - card_size.x)
	node.size = card_size
	node.global_position = Vector2(
		slot_rect.end.x - card_size.x - 8.0 - inset * max_inset,
		clampf(spread_rect.get_center().y - card_size.y * 0.5,
			slot_rect.position.y + 4.0, slot_rect.end.y - card_size.y - 4.0))


## The header strip (leader + regime ink + clock) in both slots.
func _bind_header() -> void:
	stats[&"header_binds"] += 1
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var strip := slot.get_header()
		if strip == null:
			continue
		var header: Control = strip.get_child(0) if strip.get_child_count() > 0 else null
		if header == null:
			header = RUN_HEADER_SCRIPT.new()
			header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			strip.add_child(header)
		header.bind(_view["leader"], _view["sim_hours"], _view["army_power"],
			Inks.ground_for(_view["leader"]["regime_id"], _view["phase"]))


## Ground tone by run phase (regime ink + phase depth) in both slots.
func _bind_phase() -> void:
	stats[&"phase_binds"] += 1
	var regime_id: StringName = _view["leader"]["regime_id"]
	var phase: int = _view["phase"]
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var ground := slot.get_ground()
		if ground != null:
			ground.set("regime_id", regime_id)
			ground.set("phase", phase)


## The chronicle strip: newest prints at the top, both slots, inks chosen
## by the ground beneath (the print rule).
func _bind_chronicle() -> void:
	stats[&"chronicle_prints"] += 1
	var rows := presenter.chronicle_strip()
	var ground := Inks.ground_for(_view["leader"]["regime_id"], _view["phase"])
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		for i in STRIP_LINES:
			var line := slot.get_chronicle_line(i)
			if line == null:
				continue
			if i < rows.size():
				line.set("line_class", int(rows[i]["class"]))
				line.set("text", String(rows[i]["text"]))
				line.set("ground", ground)
			else:
				line.set("text", "")


# --- helpers ----------------------------------------------------------------------------


## Viewport/orientation changed: re-place the periphery chrome the slot's
## own relayout cannot know about (the Eye card) and re-run the column
## ladder against the settled spread height (cards must never sink below
## the grip when the table changes shape). DEFERRED: size_changed fires
## before the layout pass settles the new rects — placing against
## half-settled rects would strand the Eye at the old edge (the exact
## failure the layout-determinism test caught).
func _on_layout_changed() -> void:
	if host == null or _view.is_empty():
		return
	_apply_columns.call_deferred()
	_bind_eye.call_deferred()


## The adaptive column ladder, re-derived from the CURRENT spread height
## and applied to both slots' spreads (a re-sort costs one sort pass).
func _apply_columns() -> void:
	if _view.is_empty():
		return
	var columns := SpreadCards.adaptive_columns(
		(_view["cards"] as Array).size(), _portrait_spread_height())
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var spread := slot.get_spread() as Container
		if spread != null:
			spread.set("columns", columns)
			spread.queue_sort()


## Compose the per-slot chrome the foundation doesn't own: the Watchful
## Eye card in each slot (equivalence across orientation swaps). The
## spreads' `resized` signals drive the column ladder + Eye re-placement:
## a spread's final rect settles AFTER the slot's own deferred layout
## pass (and again on every window resize), and both the ladder and the
## perch must read the SETTLED geometry (the stale-columns failure the
## layout-determinism test caught).
func _compose_slot_chrome() -> void:
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var eye := WATCHFUL_EYE_SCRIPT.new()
		eye.name = "WatchfulEye"
		slot.add_child(eye)
		var spread := slot.get_spread()
		if spread != null:
			spread.resized.connect(_on_layout_changed)


func eye_of(slot: Control) -> Control:
	for child in slot.get_children():
		if child.name == &"WatchfulEye":
			return child
	return null


func _view_card(id: String) -> Dictionary:
	for card: Dictionary in _view["cards"]:
		if String(card["id"]) == id:
			return card
	return {}


func _portrait_spread_height() -> float:
	## The stacked spread's height budget (the portrait column ladder's
	## input); degenerates safely to the grip floor before layout.
	var spread := get_portrait_slot().get_spread() as Control
	return maxf(spread.size.y, float(Inks.TOUCH_GRIP_MIN * 3))


func _sync_focus_ids(slot: OrientationSlot) -> void:
	## focus_id == index in BOTH slots: the router's swap equivalence and
	## the layout hash both key on it.
	var spread := slot.get_spread()
	for i in spread.get_child_count():
		var child := spread.get_child(i)
		if child is Control:
			child.set_meta(&"focus_id", "spread_card_%d" % i)


# --- debug chip (demo chrome — outside the slots, swaps never touch it) ------------------


func _build_debug_chip() -> void:
	## Bottom-RIGHT: the landscape rail's pips start from the left edge —
	## the chip must never sit on a pip (screenshot-inspection find).
	_scale_chip = Label.new()
	_scale_chip.theme_type_variation = &"PipLabel"
	_scale_chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_scale_chip.offset_left = -150.0
	_scale_chip.offset_top = -34.0
	_scale_chip.offset_right = -16.0
	_scale_chip.offset_bottom = -10.0
	_scale_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scale_chip.add_theme_color_override("font_color", Inks.ground_text_ink(Inks.NEUTRAL_GROUND))
	_scale_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scale_chip)
	_refresh_chip()


func _refresh_chip() -> void:
	if _scale_chip == null:
		return
	_scale_chip.text = "x%d — %dh — %s" % [
		int(TIME_SCALES[time_scale_index]), int(host.engine.sim_hours()),
		"paused" if not host.driving else "running"]


func _unhandled_input(event: InputEvent) -> void:
	## Project actions only (never ui_* — focus owns those): the demo's
	## time-scale toggle and the world-freeze pause seam.
	if event.is_action_pressed(&"debug_fast_forward"):
		time_scale_index = (time_scale_index + 1) % TIME_SCALES.size()
		host.time_scale = TIME_SCALES[time_scale_index]
		_refresh_chip()
	elif event.is_action_pressed(&"pause"):
		host.set_driving(not host.driving)
		_refresh_chip()


func _process(delta: float) -> void:
	host.advance(delta)
	if Engine.get_process_frames() % 15 == 0:
		_refresh_chip()


# --- dev inspection hook -----------------------------------------------------------------


## CS_SPREAD_SHOT=/path.png: settle the demo at 600x for
## CS_SPREAD_SETTLE_SECONDS (default 2.5), then save ONE capture and quit.
## With CS_SPREAD_LOUD=1 the demo runs the greed policy and the harness
## keeps fast-forwarding until a crackdown telegraph is armed (or 40h) —
## the pressured screenshot state (it prints what it reached).
func _capture_hook() -> void:
	var shot := OS.get_environment("CS_SPREAD_SHOT")
	if shot.is_empty():
		return
	host.time_scale = TIME_SCALES[TIME_SCALES.size() - 1]
	time_scale_index = TIME_SCALES.size() - 1
	var settle := OS.get_environment("CS_SPREAD_SETTLE_SECONDS").to_float()
	settle = settle if settle > 0.0 else 2.5
	if OS.get_environment("CS_SPREAD_LOUD") == "1":
		_pressure_then_capture()
	else:
		_settle_then_capture(settle)


func _pressure_then_capture() -> void:
	var suspicion := host.suspicion()
	var waited_hours := 0.0
	while suspicion.crackdown_land_tick == -1 and suspicion.crackdowns_total == 0 \
			and waited_hours < 40.0:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
			demo_policy.apply(host)
		waited_hours += 1.0
	refresh_from_state()
	print("[spread] pressured state: suspicion %d/%d, telegraph %s, after %.0fh"
		% [suspicion.suspicion_points(), suspicion.max_points(),
			"armed" if suspicion.crackdown_land_tick != -1 else "unarmed", waited_hours])
	_settle_then_capture(0.5)


func _settle_then_capture(settle: float) -> void:
	for i in maxi(2, int(settle * 60.0)):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_capture_path())
	print("[spread] screenshot %s (%s) — settled %.1fs wall, sim %dh, cards %d"
		% [_capture_path(), "ok" if err == OK else "FAILED %d" % err, settle,
			int(host.engine.sim_hours()), host.units().total_units() + host.units().pending_offers()])
	get_tree().quit(0)


func _capture_path() -> String:
	return OS.get_environment("CS_SPREAD_SHOT")
