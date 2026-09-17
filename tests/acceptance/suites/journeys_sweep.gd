## Journeys sweep — T-QA-05 (Hawkeye lane, Prof X consulted).
##
## The town-hall's five primary journeys as scripted acceptance runs
## THROUGH THE REAL SCREEN, tying the arc tests together (the sim-level
## arcs live in full_run_ci/marathon_*; the per-moment UI pins live in
## the unit suites; THIS suite is each journey end to end at the screen):
##
##   J1 FIRST SESSION — fresh install -> boot reveal -> first recruit ->
##      assign a worker -> raise the farm (the build-order choice) ->
##      first food trickle -> first trainee queued (the "I get it"
##      moment, without a tutorial wall).
##   J2 DAILY CHECK-IN — 5h session -> background -> 9h37m away ->
##      foreground: the capped window resolves, the while-you-were-away
##      print lands on the live table, one suspicion event choice is
##      answered, focus never stolen -> done (the 3-minute session).
##   J3 LONG SESSION — the Deck/desktop arc: buildings raised, a trainee
##      kitted and promoted, the odds table consulted before the storm.
##   J4 FAILURE — greed gets watched: the crush beat strikes, is skipped
##      by ONE INPUT, the loss-restart reveal deals a NEW leader under
##      the SAME regime (the reset is the story, not a punishment).
##   J5 VICTORY — the storm commits, wins, and the win-restart reveal
##      deals the next hand under the new regime.
##
## No wall waits: paced paper runs under Engine.time_scale (the T-UI-05
## injected-time strategy), restored at the end.
extends RefCounted

const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")

const WATCH_SCALE := 60.0
const QUIET_SEED := 20261103
const WIN_SEED := 20261207
const T0 := 1_800_000_000

var _dir_seq := 0


func suite_name() -> String:
	return "journeys_sweep"


func run(harness) -> void:
	Engine.time_scale = WATCH_SCALE
	(harness as Node).get_tree().root.size = Vector2i(720, 720)

	await _journey_1_first_session(harness)
	await _journey_2_daily_check_in(harness)
	await _journey_3_long_session(harness)
	await _journey_4_failure_restart(harness)
	await _journey_5_victory_restart(harness)

	(harness as Node).get_tree().root.size = Vector2i(720, 720)
	Engine.time_scale = 1.0
	_erase_dir("user://cs_journeys")


# --- J1: the first session -----------------------------------------------------------------


func _journey_1_first_session(harness) -> void:
	var host := _test_host(QUIET_SEED)
	var screen = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = true
	harness.mount(screen)
	# The boot reveal (the world introduces itself — no tutorial wall).
	var revealed := false
	for i in 60:
		await _frame(harness)
		if screen._intro.is_open():
			revealed = true
			break
	harness.check(revealed, "J1: the boot reveal opens on the fresh first deal")
	await _key(harness, 4194309)  # Enter — the one gesture
	for i in 200:
		await _frame(harness)
		if not screen._intro.is_open():
			break
	harness.check(not screen._intro.is_open(), "J1: one gesture unfolds the reveal")

	# The first recruit arrives (the gate prints its offer).
	var guard := 0
	while host.units().pending_offers() == 0 and guard < 240:
		host.fast_forward(30)
		guard += 1
	harness.check(host.units().pending_offers() >= 1, "J1: the first recruit arrives at the gate")
	# Take them in; put them to work; raise the farm (the build-order
	# choice); the trickle starts; the drill queue opens — every verb is
	# the sim's own, the same commands the action fan submits.
	var uid := host.units().offer_ids()[0]
	host.submit(&"recruit_accept", &"", uid)
	host.fast_forward(10)
	var idle: Array = host.units().idle_units(host.units().base_unit_id())
	harness.check(not idle.is_empty(), "J1: the recruit stands on the table")
	host.submit(&"assign_role", &"worker", idle[0])
	host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)  # settle past the worker's (zero-hour) hop
	# The build-order choice first (a staked plot has no stations), THEN the
	# "lend a hand" verb.
	var farm_raised := false
	if host.production().building_level(&"farm") < 1:
		host.submit(&"upgrade_building", &"farm", 0)
		farm_raised = true
	host.fast_forward(10)
	if host.production().idle_workers() > 0:
		host.submit(&"assign_worker", &"farm", 1)
	host.fast_forward(10)
	harness.check(host.production().building_level(&"farm") >= 1 or farm_raised,
		"J1: the farm is raised (the build-order choice made)")
	harness.check(host.production().assigned_workers(&"farm") >= 1,
		"J1: a worker is on the farm")
	# The trickle: food actually grows over the next hour.
	var food_before: int = host.engine.get_resource(&"food")
	host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	harness.check(host.engine.get_resource(&"food") > food_before,
		"J1: the first food trickle lands (%d -> %d)" % [food_before, host.engine.get_resource(&"food")])
	# The first trainee queued (militia -> trainee drill).
	var second := false
	guard = 0
	while host.units().idle_units(host.units().base_unit_id()).is_empty() and guard < 240:
		# offers must be taken in for the table to grow (the gate's verb)
		while host.units().pending_offers() > 0:
			host.submit(&"recruit_accept", &"", host.units().offer_ids()[0])
			host.fast_forward(10)
		host.fast_forward(30)
		guard += 1
	if not host.units().idle_units(host.units().base_unit_id()).is_empty():
		var peasant: int = host.units().idle_units(host.units().base_unit_id())[0]
		host.submit(&"assign_role", &"militia", peasant)
		host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
		var militia: Array = host.units().idle_units(&"militia")
		if not militia.is_empty():
			host.submit(&"start_training", &"trainee", militia[0])
			second = true
	harness.check(second, "J1: the first trainee is queued (the drill begun)")
	# The table shows the living hand: cards for the worker, the farm, the trainee.
	host.driving = false
	await _frames(harness, 6)
	var cards: Array = screen._view["cards"]
	harness.check(cards.size() >= 3, "J1: the table carries the session's cards (%d)" % cards.size())
	screen.queue_free()
	await _frames(harness, 3)


# --- J2: the daily check-in ------------------------------------------------------------------


func _journey_2_daily_check_in(harness) -> void:
	var host := _test_host(QUIET_SEED + 1)
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(5.0 * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var screen = await _mounted(harness, host)
	host.driving = false  # the boundary drives everything; wall pacing stays out
	var a_card: Control = null
	for child in screen.get_active_slot().get_spread().get_children():
		if child is Control:
			a_card = child
			break
	a_card.grab_focus()
	await _frames(harness, 2)

	# Foreground after 9h37m: the capped window resolves on the LIVE table.
	host.background(T0)
	host.foreground(T0 + 9 * 3600 + 37 * 60)
	var printed := false
	for i in 60:
		await _frame(harness)
		if int(screen.stats[&"catch_up_prints"]) > 0:
			printed = true
			break
	harness.check(printed, "J2: the while-you-were-away print lands on the live table")
	harness.check(int(screen.stats[&"catch_up_prints"]) == 1,
		"J2: exactly one print (never a modal, never spam)")
	harness.check(_focus(harness) == a_card,
		"J2: the print is passive — the check-in never steals focus")

	# One suspicion event choice, answered by keyboard (the parity-proven
	# chip path), then the session ends with the table still holding focus.
	host.suspicion().set_suspicion(78)
	host.fast_forward(2)
	var opened := false
	for i in 30:
		await _frame(harness)
		if screen._suspicion.choice_is_open():
			opened = true
			break
	harness.check(opened, "J2: one suspicion choice arrives during the check-in")
	var focus := _focus(harness)
	harness.check(focus is Button and screen._suspicion.is_ancestor_of(focus),
		"J2: the choice chips take focus when the card opens")
	await _key(harness, 4194309)  # Enter — answer it
	await _frames(harness, 4)
	harness.check(not screen._suspicion.choice_is_open(), "J2: the choice is answered and folds")
	harness.check(_focus(harness) != null, "J2: the table takes focus back — session complete")
	screen.queue_free()
	await _frames(harness, 3)


# --- J3: the long session ----------------------------------------------------------------------


var _j3_host: GameHost  # J3's army, carried into J5's storm (one build)


func _journey_3_long_session(harness) -> void:
	var host := _knight_host(WIN_SEED, 2)
	_j3_host = host
	var screen = await _mounted(harness, host)
	# The evening arc's visible state: buildings standing, an army
	# assembled, and the odds table consulted BEFORE the storm.
	var view: Dictionary = AssaultPresenter.odds_view(host.assault().assault_odds(host.engine))
	harness.check(bool(view["floor_met"]), "J3: the knight floor is met (the long session's work)")
	harness.check(int(view["army_units"]) >= 2, "J3: the sworn army stands (%d units)" % int(view["army_units"]))
	harness.check(int(view["army_power"]) >= 23, "J3: the army's power clears the floor line")
	screen.open_assault()
	await _frames(harness, 6)
	harness.check(screen._assault.is_open() and screen._assault.state == screen._assault.State.ODDS,
		"J3: the odds table is consulted before committing")
	harness.check(not AssaultPresenter.confidence_line(int(view["win_permille"])).is_empty(),
		"J3: the odds print their confidence line")
	screen._assault.close()
	await _frames(harness, 3)
	screen.queue_free()
	await _frames(harness, 3)


# --- J4: failure -------------------------------------------------------------------------------


func _journey_4_failure_restart(harness) -> void:
	var host := _test_host(QUIET_SEED)
	var screen = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = true
	harness.mount(screen)
	for i in 60:
		await _frame(harness)
		if screen._intro.is_open():
			break
	await _key(harness, 4194309)  # unfold the boot reveal
	for i in 200:
		await _frame(harness)
		if not screen._intro.is_open():
			break
	var regime_before: StringName = host.run().regime_id()
	# Greed gets watched: the loud policy never lays low.
	var policy := DemoPolicy.new(40, 40, true)
	var hours := 0.0
	while host.is_run_running() and hours < 200.0:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		if policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
			policy.apply(host)
		hours += 1.0
	harness.check(not host.is_run_running(), "J4: the suspicion maxed — the run is crushed (%.0fh of greed)" % hours)
	var beat := false
	for i in 90:
		await _frame(harness)
		if int(screen.stats[&"crushes_played"]) >= 1:
			beat = true
			break
	harness.check(beat, "J4: the crushed beat plays over the swept table")
	# The beat's ONE INPUT skip, by touch (the positional branch; the kb/pad
	# primary branch is the beat's own uniform handler — pinned in the unit
	# suites). The skip must land the same settled state.
	var viewport := (harness as Node).get_viewport()
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(360, 360)
	tap.global_position = Vector2(360, 360)
	viewport.push_input(tap, true)
	var restart := false
	for i in 240:
		await _frame(harness)
		if screen._intro.is_open() and screen._intro.variant == &"loss_restart":
			restart = true
			break
	harness.check(restart, "J4: the loss-restart reveal deals the next hand")
	harness.check(host.run().regime_id() == regime_before,
		"J4: the SAME regime still rules after the failure")
	harness.check(host.is_run_running(), "J4: the new leader's run is live beneath the reveal")
	screen.queue_free()
	await _frames(harness, 3)


# --- J5: victory --------------------------------------------------------------------------------


func _journey_5_victory_restart(harness) -> void:
	# J3's host still holds its sworn army (the odds were only CONSULTED —
	# retreat is free): the evening arc flows straight into the storm.
	var host := _j3_host
	# intro ON: the victory handoff's reveal IS the journey's final beat.
	var screen := SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = true
	harness.mount(screen)
	await _frames(harness, 10)
	# (J3's table was freed; this fresh mount re-binds the same host)
	for i in 60:
		await _frame(harness)
		if screen._intro.is_open():
			break
	await _key(harness, 4194309)  # unfold the boot reveal (the fresh install's)
	for i in 200:
		await _frame(harness)
		if not screen._intro.is_open():
			break
	host.driving = true  # the commit's one-tick drain runs through pacing
	var regime_before: StringName = host.run().regime_id()
	var outcomes: Array = []
	screen._assault.finished.connect(func(outcome: StringName, _script: Dictionary) -> void:
		outcomes.append(String(outcome)))
	screen.open_assault()
	await _frames(harness, 4)
	var commit: Button = null
	for chip in screen._assault.stage().chips():
		if chip is Button and String((chip as Button).action.get("id", "")) == "commit":
			commit = chip
			break
	commit.grab_focus()
	await _frames(harness, 2)
	await _key(harness, 4194309)  # the FIRST keyboard COMMIT arms the die
	await _frames(harness, 3)
	harness.check(screen._assault.state == screen._assault.State.ODDS,
		"J5: one Enter arms — the die is not yet cast")
	commit = null  # the armed table re-laid its chips; find the new verb
	for chip in screen._assault.stage().chips():
		if chip is Button and String((chip as Button).action.get("id", "")) == "commit":
			commit = chip
			break
	commit.grab_focus()
	await _frames(harness, 2)
	await _key(harness, 4194309)  # the SECOND Enter casts
	for i in 90:
		await _frame(harness)
		if screen._assault.state != screen._assault.State.ODDS:
			break
	for i in 240:
		await _frame(harness)
		if screen._assault.state == screen._assault.State.OUTCOME:
			break
	harness.check(screen._assault.state == screen._assault.State.OUTCOME,
		"J5: the storm resolves to the outcome print")
	var close_chip: Button = null
	for i in 60:
		await _frame(harness)
		for chip in screen._assault.stage().chips():
			if chip is Button and String((chip as Button).action.get("id", "")) == "close":
				close_chip = chip
		if close_chip != null:
			break
	harness.check(close_chip != null, "J5: the outcome prints its close chip")
	close_chip.grab_focus()
	await _frames(harness, 2)
	await _key(harness, 4194309)  # deal the next hand, by keyboard
	var closed := false
	for i in 90:
		await _frame(harness)
		if not screen._assault.is_open():
			closed = true
			break
	harness.check(closed and outcomes.size() == 1 and outcomes[0] == "win",
		"J5: the storm is WON and handed off (%s)" % str(outcomes))
	var restart := false
	for i in 600:
		await _frame(harness)
		if screen._intro.is_open() and screen._intro.variant == &"win_restart":
			restart = true
			break
	harness.check(restart, "J5: the win-restart reveal deals the next hand")
	await _key(harness, 4194309)  # the reveal's one gesture deals the next hand
	for i in 200:
		await _frame(harness)
		if not screen._intro.is_open():
			break
	harness.check(not screen._intro.is_open(), "J5: the reveal folds on its one gesture")
	# The regime card is REDRAWN by the sim's own draw (it may draw the
	# same flavor — the swap rule is the sim's; the reveal is the check).
	harness.check(host.is_run_running() and host.run().regime_id() != regime_before,
		"J5: the new leader's run is live under the redrawn regime (%s, was %s)"
		% [String(host.run().regime_id()), String(regime_before)])
	# The chronicle carries the won hand.
	var sealed := false
	for entry in host.meta.chronicle:
		if String(entry.get("outcome", "")) == "victory":
			sealed = true
			break
	harness.check(sealed, "J5: the won hand is sealed in the chronicle")
	screen.queue_free()
	await _frames(harness, 3)


# --- shared helpers ----------------------------------------------------------------------------


func _frame(harness) -> void:
	await (harness as Node).get_tree().process_frame


func _frames(harness, count: int) -> void:
	for _i in count:
		await _frame(harness)


func _focus(harness) -> Control:
	return (harness as Node).get_viewport().gui_get_focus_owner()


func _key(harness, physical_keycode: int) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = physical_keycode as Key
	press.pressed = true
	Input.parse_input_event(press)
	await _frame(harness)
	var release := InputEventKey.new()
	release.physical_keycode = physical_keycode as Key
	release.pressed = false
	Input.parse_input_event(release)
	await _frame(harness)


func _test_host(run_seed: int) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_journeys/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _mounted(harness, host: GameHost):
	var screen := SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = false
	harness.mount(screen)
	host.driving = false  # frozen: journeys drive the world by fast_forward
	await _frames(harness, 8)
	return screen


## The floor-met army fixture (the parity suite's shape: 2 fully-geared
## promoted t1 knights — a deterministic WIN on WIN_SEED).
func _knight_host(run_seed: int, count: int) -> GameHost:
	var host := _test_host(run_seed)
	var knights: Array[int] = []
	while knights.size() < count:
		while host.units().pending_offers() == 0:
			host.fast_forward(30)
		var uid := host.units().offer_ids()[0]
		host.submit(&"recruit_accept", &"", uid)
		host.fast_forward(10)
		var idle: Array = host.units().idle_units(host.units().base_unit_id())
		host.submit(&"assign_role", &"militia", idle[0])
		host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
		var militia: Array = host.units().idle_units(&"militia")
		host.submit(&"start_training", &"trainee", militia[0])
		host.fast_forward(5 * SimEngine.TICKS_PER_SIM_HOUR)
		var trainee: Array = host.units().idle_units(&"trainee")
		host.submit(&"start_training", &"knight", trainee[0])
		host.fast_forward(13 * SimEngine.TICKS_PER_SIM_HOUR)
		knights.append(trainee[0])
	host.engine.set_resource(&"food", 500)
	host.engine.set_resource(&"timber", 500)
	host.engine.set_resource(&"iron", 500)
	for uid in knights:
		for slot in host.units().missing_gear_slots(uid):
			host.submit(&"equip_gear", host.units().gear_ids_for_slot(slot)[0], uid)
	host.fast_forward(5)
	for uid in knights:
		if host.units().is_awaiting_promotion(uid) and host.units().missing_gear_slots(uid).is_empty():
			host.submit(&"promote", &"", uid)
	host.fast_forward(5)
	return host


func _erase_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var dirs: Array[String] = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				dirs.append(entry)
			else:
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for file_name: String in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
