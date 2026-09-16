## Unit tests for the Spread's card interactions (T-UI-04) — Daredevil lane.
##
## Mirrors ui/screens/spread/card_actions.gd + action_fan.gd +
## card_motion.gd + ui/theme/motion_profile.gd + the CardFrame flip seam's
## authored animation + the screen wiring. What is pinned:
##   - THE ACTION MODEL: exact action sets per card state (offer / idle
##     peasant / militia / trainee branch choice / held-trainee gear tiers
##     / fully-geared promote / building), disable reasons restating the
##     sim's gates, and submission through the real command path;
##   - THE PROMOTION FLIP: signals fire exactly once per flip in contract
##     order, the content swap lands at the crossing, end state is correct,
##     interrupted flips still complete, reduced motion is near-instant,
##     the flourish prints and fades, and OFFLINE promotions replay capped;
##   - THE ENTRANCE: slide-and-settle with a completion callback that
##     fires exactly once (animated, snapped, reduced);
##   - INPUT PARITY: the fan opens from touch AND from pad/kb focus, its
##     chips are a >=48dp focus trap with no dead ends, disabled chips are
##     focusable-but-marked and refuse with a printed chronicle hint
##     (never popup chrome), and back closes the fan and returns focus.
##
## WAITING STRATEGY (T-UI-05 fix round — the harness budget): the flip,
## flourish and entrance pacing are Tweens living in GAME code
## (untouchable here), so this suite INJECTS TIME instead of waiting the
## wall clock: `Engine.time_scale = MOTION_SCALE` advances every flip and
## settle tween ~12x per frame (a watched 0.65s turn costs ~3 frames of
## wall). The scale is deliberately BELOW every pinned in-flight window:
## one injected frame advances 0.2s, under the flip's 0.273s 90-degree
## crossing (so "is_flipping && swap not yet run" still catches the turn
## mid-flight) and two frames advance 0.4s, under the full 0.65s turn
## (so the interrupted-flip test still interrupts a genuinely in-flight
## flip). after() restores 1.0 so no sibling suite ever sees the fast
## clock.
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")

## Injected-time scale for watched tweens (see WAITING STRATEGY above).
const MOTION_SCALE := 12.0

var _dir_seq := 0


func before_test() -> void:
	Engine.time_scale = MOTION_SCALE


func after() -> void:
	Engine.time_scale = 1.0  # never leak the injected fast clock
	## MotionProfile.forced is a process-global static — never leak a
	## reduced-motion override into sibling suites.
	MotionProfile.forced = -1
	_erase_dir("user://cs_ui04_tests")
	get_window().size = Vector2i(720, 720)


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


func _test_host(run_seed: int = 20261204) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_ui04_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _fund(host: GameHost, food: int, timber: int, iron: int) -> void:
	## The documented construction/test seam (never a game verb).
	host.engine.set_resource(&"food", food)
	host.engine.set_resource(&"timber", timber)
	host.engine.set_resource(&"iron", iron)


func _first_offer_card(host: GameHost) -> Dictionary:
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	var uid := host.units().offer_ids()[0]
	return SpreadPresenter.offer_card_view(Inks.pack(), host.units().base_unit_id(), uid)


func _peasant(host: GameHost) -> int:
	## One accepted, idle peasant.
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	var uid := host.units().offer_ids()[0]
	host.submit(&"recruit_accept", &"", uid)
	host.fast_forward(10)
	return host.units().idle_units(host.units().base_unit_id())[0]


func _idle_unit(host: GameHost, def_id: StringName) -> int:
	var idle := host.units().idle_units(def_id)
	assert_int(idle.size()).is_greater(0)
	return idle[0]


func _held_trainee(host: GameHost, branch: StringName) -> int:
	## One trainee holding for the given army branch's gear.
	var peasant := _peasant(host)
	host.submit(&"assign_role", &"militia", peasant)
	host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
	host.submit(&"start_training", &"trainee", _idle_unit(host, &"militia"))
	host.fast_forward(5 * SimEngine.TICKS_PER_SIM_HOUR)
	var trainee := _idle_unit(host, &"trainee")
	host.submit(&"start_training", branch, trainee)
	host.fast_forward(13 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_bool(host.units().is_awaiting_promotion(trainee)).is_true()
	return trainee


func _geared_trainee(host: GameHost, branch: StringName = &"knight") -> int:
	## One fully geared, promotion-ready trainee standing by.
	var uid := _held_trainee(host, branch)
	_fund(host, 500, 500, 500)
	for slot in host.units().missing_gear_slots(uid):
		host.submit(&"equip_gear", host.units().gear_ids_for_slot(slot)[0], uid)
	host.fast_forward(2)
	assert_int(host.units().missing_gear_slots(uid).size()).is_zero()
	return uid


func _unit_card(host: GameHost, uid: int) -> Dictionary:
	return SpreadPresenter.unit_card_view(host, Inks.pack(), uid)


func _building_card(host: GameHost, building_id: StringName) -> Dictionary:
	for card: Dictionary in SpreadPresenter.cards_view(host):
		if card["kind"] == &"building" and StringName(String(card["building_id"])) == building_id:
			return card
	return {}


func _ids(actions: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for action: Dictionary in actions:
		ids.append(String(action["id"]))
	return ids


func _by_id(actions: Array[Dictionary], id: String) -> Dictionary:
	for action: Dictionary in actions:
		if String(action["id"]) == id:
			return action
	return {}


func _mounted_screen(host: GameHost) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = false  # these suites pin THE TABLE; the intro's suite owns the opening flow
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _left_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _enter_key() -> InputEventKey:
	## The routed keyboard form of ui_accept on a focused control.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	return key


func _await_settled(card: Control, max_frames := 300) -> void:
	for i in max_frames:
		await get_tree().process_frame
		var flipping: bool = card.call("is_flipping")
		if not flipping and is_equal_approx(card.scale.x, 1.0):
			return


func _face_key_of(card: Control) -> StringName:
	for child in card.get_children():
		if child is MarginContainer:
			for face in (child as MarginContainer).get_children():
				if face is BoxContainer:
					return StringName(String(face.get("face_key")))
	return &""


# --- the action model: exact sets per card state ----------------------------------------


func test_offer_card_actions_are_accept_and_dismiss() -> void:
	var host := _test_host()
	var card := _first_offer_card(host)
	var actions := CardActions.actions_for(host, card)
	assert_array(_ids(actions)).is_equal(["accept", "dismiss"])
	var accept := _by_id(actions, "accept")
	assert_str(String(accept["command"])).is_equal("recruit_accept")
	assert_int(int(accept["value"])).is_equal(int(card["uid"]))
	assert_bool(bool(accept["enabled"])).is_true()
	var dismiss := _by_id(actions, "dismiss")
	assert_str(String(dismiss["command"])).is_equal("dismiss_offer")
	assert_int(int(dismiss["value"])).is_equal(int(card["uid"]))


func test_idle_peasant_actions_are_the_two_assignments() -> void:
	var host := _test_host()
	var uid := _peasant(host)
	var actions := CardActions.actions_for(host, _unit_card(host, uid))
	assert_array(_ids(actions)).is_equal(["assign_worker", "assign_militia"])
	assert_str(String(_by_id(actions, "assign_worker")["subject"])).is_equal("worker")
	assert_str(String(_by_id(actions, "assign_militia")["subject"])).is_equal("militia")
	for action: Dictionary in actions:
		assert_str(String(action["command"])).is_equal("assign_role")
		assert_int(int(action["value"])).is_equal(uid)


func test_militia_and_trainee_action_sets() -> void:
	var host := _test_host()
	var peasant := _peasant(host)
	host.submit(&"assign_role", &"militia", peasant)
	host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_array(_ids(CardActions.actions_for(host, _unit_card(host, peasant)))) \
		.is_equal(["train"])
	assert_str(String(_by_id(CardActions.actions_for(host, _unit_card(host, peasant)), "train")["command"])) \
		.is_equal("start_training")
	host.submit(&"start_training", &"trainee", peasant)
	host.fast_forward(5 * SimEngine.TICKS_PER_SIM_HOUR)
	# THE BRANCH CHOICE — both paths open, both chips print.
	var branch := CardActions.actions_for(host, _unit_card(host, peasant))
	assert_array(_ids(branch)).is_equal(["train_knight", "train_archer"])
	assert_str(String(_by_id(branch, "train_knight")["subject"])).is_equal("knight")
	assert_str(String(_by_id(branch, "train_archer")["subject"])).is_equal("archer")


func test_held_trainee_equips_per_slot_with_tier_choice() -> void:
	var host := _test_host()
	var uid := _held_trainee(host, &"knight")
	_fund(host, 500, 500, 500)
	var actions := CardActions.actions_for(host, _unit_card(host, uid))
	# Two missing slots x three craftable tiers = six in-world choices.
	assert_array(_ids(actions)).is_equal([
		"equip_weapon_t1", "equip_weapon_t2", "equip_weapon_t3",
		"equip_armor_t1", "equip_armor_t2", "equip_armor_t3"])
	for action: Dictionary in actions:
		assert_str(String(action["command"])).is_equal("equip_gear")
		assert_int(int(action["value"])).is_equal(uid)
		assert_bool(bool(action["enabled"])).is_true()
	# Tier order within a slot ascends (gear_ids_for_slot is tier-sorted).
	var t1: GearDef = _gear_def(_by_id(actions, "equip_weapon_t1")["subject"])
	var t3: GearDef = _gear_def(_by_id(actions, "equip_weapon_t3")["subject"])
	assert_int(t1.tier).is_less(t3.tier)


func test_unaffordable_gear_prints_disabled_with_shortfall_reason() -> void:
	var host := _test_host()
	var uid := _held_trainee(host, &"archer")
	_fund(host, 0, 0, 0)
	var actions := CardActions.actions_for(host, _unit_card(host, uid))
	assert_int(actions.size()).is_greater(0)
	for action: Dictionary in actions:
		assert_bool(bool(action["enabled"])).is_false()
		assert_str(String(action["reason"])).contains("short")


func test_fully_geared_trainee_has_the_signature_promote_action() -> void:
	var host := _test_host()
	var uid := _geared_trainee(host, &"knight")
	var actions := CardActions.actions_for(host, _unit_card(host, uid))
	assert_array(_ids(actions)).is_equal(["promote"])
	var promote := actions[0]
	assert_bool(bool(promote["signature"])).is_true()
	assert_str(String(promote["command"])).is_equal("promote")
	assert_int(int(promote["value"])).is_equal(uid)
	assert_bool(bool(promote["enabled"])).is_true()
	assert_str(String(promote["label"])).contains("Promote")


func test_building_actions_are_upgrade_hand_and_stand_down() -> void:
	var host := _test_host()
	var policy := DemoPolicy.new(16, 8, false)
	for cycle in 8:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var farm := _building_card(host, &"farm")
	assert_bool(farm.is_empty()).is_false()
	# Broken: upgrade refuses with the shortfall; every hand is at work.
	_fund(host, 0, 0, 0)
	var broke := CardActions.actions_for(host, farm)
	assert_array(_ids(broke)).is_equal(["upgrade", "assign_hand", "stand_down"])
	assert_bool(bool(_by_id(broke, "upgrade")["enabled"])).is_false()
	assert_str(String(_by_id(broke, "upgrade")["reason"])).contains("short")
	# Funded: upgrade enables; the staffing verbs follow the pools.
	_fund(host, 5000, 5000, 5000)
	var funded := CardActions.actions_for(host, farm)
	assert_bool(bool(_by_id(funded, "upgrade")["enabled"])).is_true()
	assert_str(String(_by_id(funded, "assign_hand")["command"])).is_equal("assign_worker")
	# The training grounds never get staffed (non-producing): standing
	# down nobody refuses with its reason.
	var grounds := _building_card(host, &"training_grounds")
	var idle_actions := CardActions.actions_for(host, grounds)
	var stand := _by_id(idle_actions, "stand_down")
	assert_bool(bool(stand["enabled"])).is_false()
	assert_str(String(stand["reason"])).is_equal("none stationed")


func test_state_cards_carry_no_actions() -> void:
	var host := _test_host()
	# A worker: pooled labor lives on the buildings' cards.
	var uid := _peasant(host)
	host.submit(&"assign_role", &"worker", uid)
	host.fast_forward(2 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_array(_ids(CardActions.actions_for(host, _unit_card(host, uid)))).is_empty()
	# A unit mid-training: the dashed card counts down, nothing to choose.
	var other := _peasant(host)
	host.submit(&"assign_role", &"militia", other)
	host.fast_forward(10)
	assert_array(_ids(CardActions.actions_for(host, _unit_card(host, other)))).is_empty()
	# A sworn knight: the army's ONE verb is the storm — T-UI-07 landed on
	# the seam this suite reserved ("the army waits for the assault"): a
	# single signature action (opens the odds table), not a menu.
	var knight := _geared_trainee(host, &"knight")
	host.submit(&"promote", &"", knight)
	host.fast_forward(2)
	assert_str(String(host.units().unit_def(knight))).is_equal("knight")
	assert_array(_ids(CardActions.actions_for(host, _unit_card(host, knight)))).is_equal(["storm"])


func test_dead_run_has_no_actions() -> void:
	var host := _test_host()
	var card := _first_offer_card(host)
	host.submit(&"resolve_victory", &"loss", 0)
	host.fast_forward(5)
	assert_bool(host.is_run_running()).is_false()
	assert_array(_ids(CardActions.actions_for(host, card))).is_empty()


func test_submit_issues_the_real_command() -> void:
	var host := _test_host()
	var card := _first_offer_card(host)
	var uid := int(card["uid"])
	CardActions.submit(host, _by_id(CardActions.actions_for(host, card), "accept"))
	host.fast_forward(5)
	assert_str(String(host.units().unit_def(uid))).is_not_empty()


func test_gear_def_helper() -> void:
	## The suite's own probe resolves content (used for tier ordering).
	assert_that(_gear_def(&"gear_weapon_t1")).is_not_null()


func _gear_def(id: StringName) -> GearDef:
	for gear: GearDef in Inks.pack().gear:
		if gear.id == id:
			return gear
	return null


# --- the promotion flip (the signature moment) ------------------------------------------


func _flip_frame() -> Control:
	var frame := (load("res://ui/theme/card_frame.tscn") as PackedScene).instantiate() as Control
	frame.size = Vector2(160.0, 220.0)
	add_child(frame)
	return frame


func test_promotion_flip_signals_swap_and_end_state_animated() -> void:
	MotionProfile.forced = 0
	var frame := _flip_frame()
	auto_free(frame)
	var events: Array = []
	var swaps := [0]
	frame.flip_started.connect(func(up: bool) -> void: events.append(["started", up]))
	frame.flip_completed.connect(func(up: bool) -> void: events.append(["completed", up]))
	frame.play_promotion_flip(func() -> void: swaps[0] += 1)
	await get_tree().process_frame
	assert_bool(frame.is_flipping()).is_true()
	assert_bool(events.any(func(e) -> bool: return e == ["started", true])).is_true()
	assert_int(swaps[0]).is_zero()  # the swap waits for the crossing
	for i in 300:
		await get_tree().process_frame
		if not frame.is_flipping():
			break
	# Contract: started once, completed once, swap exactly once between them.
	assert_int(swaps[0]).is_equal(1)
	assert_bool(events[0] == ["started", true]).is_true()
	assert_bool(events[events.size() - 1] == ["completed", true]).is_true()
	assert_int(events.filter(func(e) -> bool: return e[0] == "completed").size()).is_equal(1)
	# End state: face up, scale at rest, the flourish fresh off the press.
	assert_bool(frame.is_face_up()).is_true()
	assert_float(frame.scale.x).is_equal_approx(1.0, 0.01)
	assert_float(frame.flourish).is_greater(0.01)


func test_promotion_flip_reduced_motion_is_near_instant() -> void:
	MotionProfile.forced = 1
	var frame := _flip_frame()
	auto_free(frame)
	var events: Array = []
	var swaps := [0]
	frame.flip_completed.connect(func(up: bool) -> void: events.append(up))
	frame.play_promotion_flip(func() -> void: swaps[0] += 1)
	# Synchronous: no frames awaited, everything already landed.
	assert_int(events.size()).is_equal(1)
	assert_bool(events[0]).is_true()
	assert_int(swaps[0]).is_equal(1)
	assert_bool(frame.is_face_up()).is_true()
	assert_bool(frame.is_flipping()).is_false()
	assert_float(frame.flourish).is_zero()  # the flourish is celebration; reduced skips it


func test_promotion_flip_hides_then_reveals_the_face() -> void:
	MotionProfile.forced = 1
	var frame := _flip_frame()
	auto_free(frame)
	var plate := ColorRect.new()
	auto_free(plate)
	frame.add_child(plate)
	var mid_back := [false]
	frame.play_promotion_flip(func() -> void:
		mid_back[0] = not plate.visible)  # at the swap: the back shows (content hidden)
	assert_bool(mid_back[0]).is_true()
	assert_bool(plate.visible).is_true()  # revealed on landing


func test_interrupted_flip_still_completes_exactly_once() -> void:
	MotionProfile.forced = 0
	var frame := _flip_frame()
	auto_free(frame)
	var started := [0]
	var completed := [0]
	var swaps := [0]
	frame.flip_started.connect(func(_up: bool) -> void: started[0] += 1)
	frame.flip_completed.connect(func(_up: bool) -> void: completed[0] += 1)
	frame.play_promotion_flip(func() -> void: swaps[0] += 1)
	await get_tree().process_frame
	await get_tree().process_frame
	# A second flip arrives mid-turn: the first is snap-finished in order.
	frame.play_promotion_flip(func() -> void: swaps[0] += 1)
	assert_int(started[0]).is_equal(2)
	for i in 300:
		await get_tree().process_frame
		if not frame.is_flipping() and completed[0] >= 2:
			break
	assert_int(completed[0]).is_equal(2)
	assert_int(swaps[0]).is_equal(2)
	assert_float(frame.scale.x).is_equal_approx(1.0, 0.01)


func test_flip_flourish_prints_then_fades() -> void:
	MotionProfile.forced = 0
	var frame := _flip_frame()
	auto_free(frame)
	frame.play_promotion_flip(func() -> void: pass)
	for i in 300:
		await get_tree().process_frame
		if not frame.is_flipping():
			break
	assert_float(frame.flourish).is_greater(0.01)
	for i in 120:
		await get_tree().process_frame
		if frame.flourish <= 0.01:
			break
	assert_float(frame.flourish).is_less_equal(0.01)


func test_flip_queue_keeps_latest_three() -> void:
	var queue := CardMotion.PromotionFlipQueue.new()
	for i in 7:
		queue.push("unit_%d" % i)
	assert_int(queue.size()).is_equal(3)
	assert_array(queue.take_all()).is_equal(["unit_4", "unit_5", "unit_6"])
	assert_int(queue.size()).is_zero()
	# A re-queue moves to the back (latest wins).
	queue.push("unit_a")
	queue.push("unit_b")
	queue.push("unit_a")
	assert_array(queue.take_all()).is_equal(["unit_b", "unit_a"])


# --- the entrance (slide-and-settle) -----------------------------------------------------


func test_entrance_reduced_completes_synchronously() -> void:
	MotionProfile.forced = 1
	var parent := Control.new()
	auto_free(parent)
	add_child(parent)  # tweens step only for in-tree nodes
	var card := Control.new()
	auto_free(card)
	card.position = Vector2(100.0, 100.0)
	parent.add_child(card)
	var done := [0]
	CardMotion.settle_in(card, func() -> void: done[0] += 1)
	assert_int(done[0]).is_equal(1)
	assert_bool(CardMotion.is_settling(card)).is_false()
	# No slide: the card never left its seat.
	assert_float(card.position.x).is_equal_approx(100.0, 0.05)
	assert_float(card.position.y).is_equal_approx(100.0, 0.05)


func test_entrance_slides_then_settles_with_callback() -> void:
	MotionProfile.forced = 0
	var parent := Control.new()
	auto_free(parent)
	add_child(parent)  # tweens step only for in-tree nodes
	parent.size = Vector2(600.0, 600.0)
	var card := Control.new()
	auto_free(card)
	card.position = Vector2(200.0, 300.0)
	parent.add_child(card)
	var done := [0]
	CardMotion.settle_in(card, func() -> void: done[0] += 1)
	assert_bool(CardMotion.is_settling(card)).is_true()
	assert_int(done[0]).is_zero()
	# The slide starts offset from the deck (top-right of the seat).
	assert_float(card.position.x).is_equal_approx(200.0 + CardMotion.DEAL_OFFSET.x, 0.05)
	assert_float(card.position.y).is_equal_approx(300.0 + CardMotion.DEAL_OFFSET.y, 0.05)
	for i in 300:
		await get_tree().process_frame
		if not CardMotion.is_settling(card):
			break
	assert_bool(CardMotion.is_settling(card)).is_false()
	assert_float(card.position.x).is_equal_approx(200.0, 0.05)
	assert_float(card.position.y).is_equal_approx(300.0, 0.05)
	assert_int(done[0]).is_equal(1)


func test_entrance_snap_lands_mid_slide_firing_once() -> void:
	MotionProfile.forced = 0
	var parent := Control.new()
	auto_free(parent)
	add_child(parent)  # tweens step only for in-tree nodes
	var card := Control.new()
	auto_free(card)
	card.position = Vector2(50.0, 50.0)
	parent.add_child(card)
	var done := [0]
	CardMotion.settle_in(card, func() -> void: done[0] += 1)
	await get_tree().process_frame
	CardMotion.snap(card)
	assert_float(card.position.x).is_equal_approx(50.0, 0.05)
	assert_float(card.position.y).is_equal_approx(50.0, 0.05)
	assert_int(done[0]).is_equal(1)
	# A redundant snap never re-fires the callback.
	CardMotion.snap(card)
	assert_int(done[0]).is_equal(1)
	CardMotion.snap_all(parent)
	assert_int(done[0]).is_equal(1)


# --- the action fan ----------------------------------------------------------------------


func _fan_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	actions.append({"id": "go", "label": "Go", "command": &"c", "subject": &"", "value": 1,
		"enabled": true, "reason": "", "signature": false})
	actions.append({"id": "no", "label": "No", "command": &"c", "subject": &"", "value": 2,
		"enabled": false, "reason": "short 12 iron", "signature": false})
	actions.append({"id": "promote", "label": "Promote", "command": &"c", "subject": &"", "value": 3,
		"enabled": true, "reason": "", "signature": true})
	return actions


func _mounted_fan() -> ActionFan:
	var fan := ActionFan.new()
	add_child(fan)
	return fan


func test_fan_chips_are_grips_and_disabled_stay_printed() -> void:
	var fan := _mounted_fan()
	auto_free(fan)
	fan.open("unit_1", _fan_actions())
	await get_tree().process_frame
	assert_int(fan.chips().size()).is_equal(3)
	# The hint strip prints at the foot and is not focusable.
	var hint := fan.get_child(fan.get_child_count() - 1) as Label
	assert_str(hint.text).contains("choose")
	assert_int(hint.focus_mode).is_equal(Control.FOCUS_NONE)
	for chip in fan.chips():
		var min_size: Vector2 = chip.get_combined_minimum_size()
		assert_float(min_size.x).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)
		assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)
		assert_int(chip.focus_mode).is_equal(Control.FOCUS_ALL)  # disabled = focusable-but-marked
	# Seeded focus lands on the first chip.
	assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
	assert_bool(get_viewport().gui_get_focus_owner() == fan.chips()[0]).is_true()
	# Closing folds it away.
	fan.close()
	assert_bool(fan.is_open()).is_false()
	assert_str(fan.card_id).is_empty()


func test_fan_focus_trap_has_no_dead_ends() -> void:
	var fan := _mounted_fan()
	auto_free(fan)
	fan.open("unit_1", _fan_actions())
	await get_tree().process_frame
	var chips := fan.chips()
	var chip_paths := {}
	for chip in chips:
		chip_paths[chip.get_path()] = true
	for chip in chips:
		for neighbor in [
			chip.focus_neighbor_left, chip.focus_neighbor_right,
			chip.focus_neighbor_top, chip.focus_neighbor_bottom,
			chip.focus_previous, chip.focus_next,
		]:
			var path: NodePath = neighbor
			assert_bool(path.is_empty()).is_false()
			var resolved: Node = chip.get_node_or_null(path)
			assert_that(resolved).is_not_null()
			if resolved != null:
				assert_bool(chip_paths.has(resolved.get_path())).is_true()
	# Cyclic: walking backwards from the first lands on the last.
	assert_bool(chips[0].get_node(chips[0].focus_previous) == chips[chips.size() - 1]).is_true()
	assert_bool(chips[chips.size() - 1].get_node(chips[chips.size() - 1].focus_next) == chips[0]).is_true()


func test_chip_press_routes_chosen_and_refused() -> void:
	var fan := _mounted_fan()
	auto_free(fan)
	var chosen: Array = []
	var refused: Array = []
	fan.action_chosen.connect(func(action: Dictionary) -> void: chosen.append(action["id"]))
	fan.action_refused.connect(func(action: Dictionary) -> void: refused.append(action["id"]))
	fan.open("unit_1", _fan_actions())
	await get_tree().process_frame
	fan.chips()[0].pressed.emit()
	fan.chips()[1].pressed.emit()  # disabled: refused, not chosen
	fan.chips()[2].pressed.emit()
	assert_array(chosen).is_equal(["go", "promote"])
	assert_array(refused).is_equal(["no"])
	# The pad-A fallback activates the FOCUSED chip the same way.
	get_viewport().gui_get_focus_owner().release_focus()
	fan.chips()[1].grab_focus()
	fan.activate_focused()
	assert_array(refused).is_equal(["no", "no"])


# --- the screen wiring -------------------------------------------------------------------


func _offer_node(screen: SpreadScreen) -> Control:
	var active := screen.get_active_slot() as OrientationSlot
	for child in active.get_spread().get_children():
		var card := child as Control
		if card != null and String(card.get_meta(&"spread_card_id", "")).begins_with("offer_"):
			return card
	return null


func test_fan_opens_from_touch_tap_and_pad_keyboard_primary() -> void:
	var host := _test_host()
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	var screen: SpreadScreen = await _mounted_screen(host)
	var card := _offer_node(screen)
	assert_that(card).is_not_null()
	# TOUCH: a tap focuses the card and fans its actions.
	screen._on_card_gui_input(_left_click(), card)
	await get_tree().process_frame
	assert_bool(screen._fan.is_open()).is_true()
	var touch_ids: Array = []
	for chip in screen._fan.chips():
		touch_ids.append(String(chip.action["id"]))
	assert_array(touch_ids).is_equal(["accept", "dismiss"])
	screen.close_fan()
	# PAD/KEYBOARD: focus + primary fans the SAME actions.
	card.grab_focus()
	screen._unhandled_input(_action_event(&"primary"))
	await get_tree().process_frame
	assert_bool(screen._fan.is_open()).is_true()
	var focus_ids: Array = []
	for chip in screen._fan.chips():
		focus_ids.append(String(chip.action["id"]))
	assert_array(focus_ids).is_equal(touch_ids)
	# A bare-table positional press never fans the focused card.
	screen.close_fan()
	card.grab_focus()
	screen._unhandled_input(_left_click())
	assert_bool(screen._fan.is_open()).is_false()
	screen.queue_free()
	await get_tree().process_frame


func test_actions_reachable_three_ways_and_back_returns_focus() -> void:
	var host := _test_host()
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	var offer_uid := host.units().offer_ids()[0]
	var screen: SpreadScreen = await _mounted_screen(host)
	var card := _offer_node(screen)
	# 1) open via keyboard primary on focus
	card.grab_focus()
	screen._unhandled_input(_action_event(&"primary"))
	await get_tree().process_frame
	var chip := screen._fan.chips()[0]
	assert_bool(get_viewport().gui_get_focus_owner() == chip).is_true()
	# 2) the routed keyboard form (Enter through the real input pipeline:
	#    the viewport delivers it to the focus owner as ui_accept)
	var chosen: Array = []
	screen._fan.action_chosen.connect(func(action: Dictionary) -> void: chosen.append(action["id"]))
	Input.parse_input_event(_enter_key())
	for i in 6:
		await get_tree().process_frame
	assert_array(chosen).is_equal(["accept"])
	# acting folds the fan and returns focus to the card
	assert_bool(screen._fan.is_open()).is_false()
	assert_bool(get_viewport().gui_get_focus_owner() == card).is_true()
	# 3) the pad path: reopen (the command is still pending — the card is
	#    on the table until a tick drains it), focus a chip, primary acts
	screen.open_fan_for_card(card)
	await get_tree().process_frame
	var chip2 := screen._fan.chips()[0]
	chip2.grab_focus()
	screen._unhandled_input(_action_event(&"primary"))
	assert_array(chosen).is_equal(["accept", "accept"])
	# 4) BACK closes the fan and returns focus to the card
	screen.open_fan_for_card(card)
	await get_tree().process_frame
	screen._unhandled_input(_action_event(&"back"))
	assert_bool(screen._fan.is_open()).is_false()
	assert_bool(get_viewport().gui_get_focus_owner() == card).is_true()
	# And the command flowed down the real write path (the second submit
	# is denied loudly by the sim — the first accept wins).
	host.fast_forward(5)
	assert_str(String(host.units().unit_def(offer_uid))).is_not_empty()
	screen.queue_free()
	await get_tree().process_frame


func test_live_promotion_flips_the_trainee_card() -> void:
	var host := _test_host()
	var uid := _geared_trainee(host, &"knight")
	var screen: SpreadScreen = await _mounted_screen(host)
	var active := screen.get_active_slot() as OrientationSlot
	var card := screen._card_node_in(active, "unit_%d" % uid)
	assert_that(card).is_not_null()
	var completed := [0]
	card.flip_completed.connect(func(_up: bool) -> void: completed[0] += 1)
	host.submit(&"promote", &"", uid)
	host.fast_forward(2)
	# The event drove the flip immediately (not on button press — on the
	# event, the honest event-driven path).
	assert_int(screen.stats[&"flips_played"]).is_equal(1)
	await get_tree().process_frame
	assert_bool(bool(card.call("is_flipping"))).is_true()
	await _await_settled(card)
	assert_int(completed[0]).is_equal(1)
	assert_bool(card.is_face_up()).is_true()
	assert_str(String(_face_key_of(card))).is_equal(
		String(_unit_def_face(host, &"knight")))
	screen.queue_free()
	await get_tree().process_frame


func _unit_def_face(host: GameHost, def_id: StringName) -> StringName:
	for def: UnitDef in Inks.pack().units:
		if def.id == def_id:
			return def.face_id
	return &""


func test_offline_promotion_replays_capped_on_foreground() -> void:
	var host := _test_host()
	var uid := _geared_trainee(host, &"knight")
	var screen: SpreadScreen = await _mounted_screen(host)
	var active := screen.get_active_slot() as OrientationSlot
	var card := screen._card_node_in(active, "unit_%d" % uid)
	var offline := [false]
	host.event_observed.connect(func(event: Dictionary) -> void:
		if event["type"] == &"unit_promoted":
			offline[0] = host.delivering_catch_up)
	# The promote command is submitted, then the app backgrounds BEFORE it
	# drains — the away window's fast-forward resolves it OFFLINE.
	host.submit(&"promote", &"", uid)
	var now := 1_700_000_000
	host.background(now)
	host.foreground(now + 2 * 3600)
	assert_bool(offline[0]).is_true()
	assert_str(String(host.units().unit_def(uid))).is_equal("knight")
	# The replay is staged on the foreground boundary and turns the card.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(screen.stats[&"flip_replays"]).is_equal(1)
	await _await_settled(card)
	assert_bool(card.is_face_up()).is_true()
	screen.queue_free()
	await get_tree().process_frame


func test_refused_action_prints_a_chronicle_hint_not_a_command() -> void:
	var host := _test_host()
	var uid := _held_trainee(host, &"archer")
	_fund(host, 0, 0, 0)
	var screen: SpreadScreen = await _mounted_screen(host)
	var active := screen.get_active_slot() as OrientationSlot
	var card := screen._card_node_in(active, "unit_%d" % uid)
	screen.open_fan_for_card(card)
	await get_tree().process_frame
	var chips := screen._fan.chips()
	assert_int(chips.size()).is_greater(0)
	# Every gear chip is struck with its reason; activating one REFUSES.
	for chip in chips:
		assert_bool(bool(chip.action["enabled"])).is_false()
	chips[0].pressed.emit()
	await get_tree().process_frame
	assert_int(screen.stats[&"refusals_printed"]).is_equal(1)
	var rows := (screen.presenter as SpreadPresenter).chronicle
	assert_str(String(rows[rows.size() - 1]["text"])).contains("short")
	# No command went down: nothing was equipped after a tick.
	host.fast_forward(5)
	assert_int(host.units().missing_gear_slots(uid).size()).is_greater(0)
	# And no popup chrome was raised for the refusal.
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
		for child in node.get_children():
			stack.append(child)
	screen.queue_free()
	await get_tree().process_frame


func test_screen_deals_joined_cards_after_the_first_bind() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	# The boot deal is the unfold's (T-UI-05): no entrance motion at mount.
	assert_int(screen.stats[&"entrances"]).is_zero()
	# A recruit JOINING the live table deals in (slide-and-settle).
	var arrived := [false]
	host.event_observed.connect(func(event: Dictionary) -> void:
		if event["type"] == &"recruit_arrived":
			arrived[0] = true)
	for i in 400:
		host.fast_forward(30)
		if arrived[0]:
			break
	assert_bool(arrived[0]).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(screen.stats[&"entrances"]).is_greater_equal(1)
	# The entrance settles onto its seat (never strands mid-slide).
	for i in 300:
		await get_tree().process_frame
		var settling := false
		for child in (screen.get_active_slot() as OrientationSlot).get_spread().get_children():
			if child is Control and CardMotion.is_settling(child as Control):
				settling = true
		if not settling:
			break
	screen.queue_free()
	await get_tree().process_frame


func test_fan_folds_when_its_card_leaves_the_table() -> void:
	var host := _test_host()
	_first_offer_card(host)
	var screen: SpreadScreen = await _mounted_screen(host)
	var card := _offer_node(screen)
	screen.open_fan_for_card(card)
	await get_tree().process_frame
	assert_bool(screen._fan.is_open()).is_true()
	# The recruit is sent home: the diff retires the card, the fan folds.
	var uid := int(String(card.get_meta(&"spread_card_id", "")).trim_prefix("offer_"))
	host.submit(&"dismiss_offer", &"", uid)
	host.fast_forward(2)
	await get_tree().process_frame
	assert_bool(screen._fan.is_open()).is_false()
	screen.queue_free()
	await get_tree().process_frame
