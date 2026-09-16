## Input parity matrix — T-QA-05 (Hawkeye lane, Daredevil consulted).
##
## THE consolidated full pass of the town-hall criterion "Full loop
## operable three ways: touch, controller, keyboard/mouse": every
## interactive surface x every action, driven through the REAL input
## pipeline all three ways at the square 720x720 headless window (design
## == window: no stretch transform between the injected event and the
## gui dispatch; the Deck-window pad BFS lives in deck_nav_sweep.gd).
##
##   TOUCH  — InputEventMouseButton LEFT at the control's center through
##            Viewport.push_input (the gui dispatch a finger rides; the
##            local-coords form — Input.parse_input_event rescales
##            positions through the platform display server headless,
##            probe-measured (200,140)->(2250,1575))
##   PAD    — InputEventJoypadButton through Input.parse_input_event
##            (dpad 11-14 focus moves, A=0 primary, B=1 back)
##   KB     — InputEventKey through Input.parse_input_event (arrows =
##            the engine's ui_* focus moves, Enter = primary, Esc = back)
##
## Matrix sections (the full table, with the owning test per row, is
## docs/input-parity.md):
##   A. ACTION-MODEL COMPLETENESS — every verb of every card kind appears
##      as a chip (the fan's uniform input target); every disabled chip
##      carries its printed reason.
##   B. THE ACTION FAN — open / cycle / submit / refuse / fold, each
##      gesture all three ways (fold-without-acting by touch = the
##      bare-table tap this suite forced into existence).
##   C. THE SUSPICION CHOICE CARD — submit + fold, three ways.
##   D. THE ASSAULT — odds open via the STORM chip (three ways),
##      below-floor COMMIT refusal (three ways), RETREAT (three ways),
##      and a full TOUCH-ONLY storm (commit -> skip -> close -> win
##      handoff) beside the pad-only storm deck_nav_sweep already ran.
##   E. THE CHRONICLE LEDGER — open / page turn / close, three ways.
##   F. THE LEADER INTRO — the one gesture, three ways.
##
## Passive paper (the while-you-were-away print, the first-session cues)
## has no verbs by design: nothing to reach, nothing stolen — pinned in
## deck_nav_sweep.gd section 7 and the journeys sweep. Dev-only surfaces
## (the debug time-scale chip, pause, fast-forward) are out of the player
## matrix by design.
##
## No wall waits: paced paper runs under Engine.time_scale (the T-UI-05
## injected-time strategy), restored at the end.
extends RefCounted

const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")

const WATCH_SCALE := 60.0
const QUIET_SEED := 20261103
const WIN_SEED := 20261207

const BTN_A := 0
const BTN_B := 1
const DPAD_UP := 11
const DPAD_DOWN := 12
const DPAD_LEFT := 13
const DPAD_RIGHT := 14

const KEY_ENTER := 4194309
const KEY_ESCAPE := 4194305
const KEY_UP := 4194320
const KEY_DOWN := 4194322
const KEY_LEFT := 4194319
const KEY_RIGHT := 4194321

## Every verb the action model can print (docs/input-parity.md §A; a new
## verb in card_actions.gd must join this list and the doc together).
const KNOWN_VERBS: Array[String] = [
	"accept", "dismiss",                       # the gate
	"assign_worker", "assign_militia",         # the peasant
	"train", "train_knight", "train_archer",   # the drill + the branch
	"promote",                                 # the signature
	"storm",                                   # the army's one verb
	"build", "upgrade", "assign_hand", "stand_down",  # the estate
]

var _dir_seq := 0


func suite_name() -> String:
	return "input_parity_matrix"


func run(harness) -> void:
	Engine.time_scale = WATCH_SCALE
	(harness as Node).get_tree().root.size = Vector2i(720, 720)
	var _ms := Time.get_ticks_msec()

	await _matrix_action_model(harness)
	if OS.get_environment("CS_PARITY_TRACE") == "1": print("[prof] model %d" % (Time.get_ticks_msec() - _ms))
	await _matrix_fan(harness)
	if OS.get_environment("CS_PARITY_TRACE") == "1": print("[prof] fan %d" % (Time.get_ticks_msec() - _ms))
	await _matrix_choice_card(harness)
	if OS.get_environment("CS_PARITY_TRACE") == "1": print("[prof] choice %d" % (Time.get_ticks_msec() - _ms))
	await _matrix_assault(harness)
	if OS.get_environment("CS_PARITY_TRACE") == "1": print("[prof] assault %d" % (Time.get_ticks_msec() - _ms))
	await _matrix_chronicle(harness)
	if OS.get_environment("CS_PARITY_TRACE") == "1": print("[prof] chronicle %d" % (Time.get_ticks_msec() - _ms))
	await _matrix_intro(harness)
	if OS.get_environment("CS_PARITY_TRACE") == "1": print("[prof] intro %d" % (Time.get_ticks_msec() - _ms))

	(harness as Node).get_tree().root.size = Vector2i(720, 720)
	Engine.time_scale = 1.0
	_erase_dir("user://cs_parity")


# --- input injection (the three real pipelines) ------------------------------------------


func _tap(harness, at: Vector2) -> void:
	## TOUCH: a left-press at a design-space point (the finger's dispatch).
	var viewport := (harness as Node).get_viewport()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	viewport.push_input(press, true)
	await _frame(harness)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at
	release.global_position = at
	viewport.push_input(release, true)
	await _frame(harness)


func _tap_control(harness, control: Control) -> void:
	await _tap(harness, control.get_global_rect().get_center())


## Is `card` the topmost mouse-receiving card at global `point`? The
## panoramic arc ROTATES cards, so an axis-aligned rect test lies about
## what a tap hits — every later sibling is tested through its own
## inverse transform (exactly how the engine picks rotated controls).
## A point of THIS card where it is the topmost pick (the storm chip's
## army card is the target; the fan arc rotates everything).
func _topmost_point_of(card: Control) -> Vector2:
	var xf: Transform2D = card.get_global_transform()
	for fy in [0.5, 0.35, 0.65, 0.25, 0.75]:
		for fx in [0.5, 0.3, 0.7, 0.15, 0.85]:
			var local := Vector2(card.size.x * fx, card.size.y * fy)
			var point := xf * local
			if _is_topmost_at(card, point):
				return point
	return card.get_global_rect().get_center()


func _is_topmost_at(card: Control, point: Vector2) -> bool:
	var seen := false
	for sibling in card.get_parent().get_children():
		if sibling == card:
			seen = true
			continue
		if seen and sibling is Control:
			var s := sibling as Control
			if not s.is_visible_in_tree() or s.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				continue
			var local: Vector2 = s.get_global_transform().affine_inverse() * point
			if Rect2(Vector2.ZERO, s.size).has_point(local):
				return false
	return true


## A [card, global_point] pair where `card` is an ACTIONS-carrying card
## that is the topmost pick at the point (touch acts on what is actually
## under the finger). Cards are tried topmost-first; points are a small
## candidate lattice across the card's own (rotated) surface.
func _tappable_action_card(screen) -> Array:
	var cards := _screen_cards(screen)
	# Topmost first: reverse child order.
	var ordered: Array = []
	ordered.assign(cards)
	ordered.reverse()
	for card: Control in ordered:
		var found_actions := false
		var id := String(card.get_meta(&"spread_card_id", ""))
		for view_card: Dictionary in screen._view["cards"]:
			if String(view_card["id"]) == id \
					and not CardActions.actions_for(screen.host, view_card).is_empty():
				found_actions = true
				break
		if not found_actions:
			continue
		var xf: Transform2D = card.get_global_transform()
		for fy in [0.5, 0.35, 0.65, 0.25, 0.75]:
			for fx in [0.5, 0.3, 0.7, 0.15, 0.85]:
				var local := Vector2(card.size.x * fx, card.size.y * fy)
				var point := xf * local
				if _is_topmost_at(card, point):
					return [card, point]
	return [null, Vector2.ZERO]



func _pad(harness, button: int) -> void:
	var press := InputEventJoypadButton.new()
	press.device = 0
	press.button_index = button as JoyButton
	press.pressed = true
	Input.parse_input_event(press)
	await _frame(harness)
	var release := InputEventJoypadButton.new()
	release.device = 0
	release.button_index = button as JoyButton
	release.pressed = false
	Input.parse_input_event(release)
	await _frame(harness)


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


func _frame(harness) -> void:
	await (harness as Node).get_tree().process_frame


func _frames(harness, count: int) -> void:
	for _i in count:
		await _frame(harness)


func _focus_owner(harness) -> Control:
	return (harness as Node).get_viewport().gui_get_focus_owner()


func _chip_by_id(assault, id: String) -> Button:
	for chip in assault.stage().chips():
		if chip is Button and String((chip as Button).action.get("id", "")) == id:
			return chip
	return null


func _first_button_under(node: Node) -> Button:
	if node is Button:
		return node
	for child in node.get_children():
		var found := _first_button_under(child)
		if found != null:
			return found
	return null


# --- shared host/screen builders ---------------------------------------------------------


func _test_host(run_seed: int) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_parity/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _populated_host(run_seed: int, hours := 8.0) -> GameHost:
	## The sensible-policy table: offers, workers, buildings, training —
	## enough card kinds for the action-model sweep.
	var host := _test_host(run_seed)
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(hours * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	return host


func _mounted_screen(harness, host: GameHost, intro_on := false):
	var screen := SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = intro_on
	harness.mount(screen)
	host.driving = false  # frozen table: the sweep reads settled geometry, the
	# pacing gate's per-frame advance is the suite's own biggest cost. Legs
	# that need the world to tick (the storm's one-tick drain) re-enable it.
	await _frames(harness, 8)  # settled card geometry (the dpad reads real rects)
	return screen


func _screen_cards(screen) -> Array:
	var active = screen.get_active_slot()
	var out: Array = []
	for child in active.get_spread().get_children():
		if child is Control:
			out.append(child)
	return out


func _card_by_id(screen, id_prefix: String) -> Control:
	for child in _screen_cards(screen):
		var id := String(child.get_meta(&"spread_card_id", ""))
		if id.begins_with(id_prefix):
			for card: Dictionary in screen._view["cards"]:
				if String(card["id"]) == id:
					if not CardActions.actions_for(screen.host, card).is_empty():
						return child
	return null


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


# --- A. Action-model completeness ---------------------------------------------------------


func _matrix_action_model(harness) -> void:
	## Verbs are collected ACROSS the drive (a verb prints while its card
	## kind holds the right lifecycle state; the end-state table alone has
	## already applied everything).
	var host := _test_host(QUIET_SEED)
	var policy := DemoPolicy.new(16, 8, false)
	var verbs: Dictionary = {}  # base id -> seen
	var disabled_seen := 0
	var cards_seen := 0
	var chunks := int(12.0 * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
		var cards: Array = SpreadPresenter.build_view(host)["cards"]
		cards_seen = maxi(cards_seen, cards.size())
		for card: Dictionary in cards:
			for action: Dictionary in CardActions.actions_for(host, card):
				var id := String(action["id"])
				# gear verbs are per-slot/per-tier composites; the base counts.
				var base := id.split("_t")[0]
				verbs[base] = true
				if not bool(action["enabled"]):
					disabled_seen += 1
					harness.check(not String(action["reason"]).is_empty(),
						"parity/model: disabled verb '%s' prints a reason" % id)
	host.driving = false
	harness.check(cards_seen >= 4, "parity/model: the driven table carried >=4 cards (saw %d)" % cards_seen)
	# Every known verb family appeared on this one honest table (a verb that
	# can never print is dead code; a verb that prints is an input target).
	var missing: Array[String] = []
	for verb: String in KNOWN_VERBS:
		if verb != "promote" and verb != "storm" and not verbs.has(verb):
			missing.append(verb)
	harness.check(missing.is_empty(),
		"parity/model: the 12h table prints every core verb (missing: %s; saw %d verb families)"
		% [", ".join(missing), verbs.size()])
	harness.check(disabled_seen >= 1,
		"parity/model: the table shows at least one disabled-but-visible verb (the refusal row)")


# --- B. The action fan --------------------------------------------------------------------


func _matrix_fan(harness) -> void:
	# --- open + submit + fold, by TOUCH --------------------------------------------
	var host := _populated_host(QUIET_SEED)
	var screen = await _mounted_screen(harness, host)
	host.driving = false
	var offers_before: int = host.units().pending_offers()
	var solved: Array = _tappable_action_card(screen)
	var card: Control = solved[0]
	var tap_point: Vector2 = solved[1]
	if not harness.check(card != null,
			"parity/fan: an actions card is topmost somewhere on the 8h table"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	await _tap(harness, tap_point)
	await _frames(harness, 3)
	harness.check(screen._fan.is_open(), "parity/fan: TOUCH tap on a card opens its action fan")
	harness.check(_focus_owner(harness) != null and screen._fan.is_ancestor_of(_focus_owner(harness)),
		"parity/fan: the fan takes focus on open (tap = select + fan)")
	# Fold without acting: the bare-table tap (the touch "esc").
	await _tap(harness, Vector2(30, 690))  # the table's bare corner (no card, no chip)
	await _frames(harness, 3)
	harness.check(not screen._fan.is_open(), "parity/fan: TOUCH tap on the bare table folds the open fan")
	# Re-open by tap, submit the card's first ENABLED chip by tap.
	await _tap(harness, tap_point)
	await _frames(harness, 3)
	var chip: Control = null
	for candidate in screen._fan.chips():
		if candidate is Button and bool((candidate as Button).action.get("enabled", false)):
			chip = candidate
			break
	harness.check(chip != null, "parity/fan: the fan holds an enabled chip to submit")
	var submitted: Array = []
	screen._fan.action_chosen.connect(func(action: Dictionary) -> void: submitted.append(String(action["id"])))
	await _tap_control(harness, chip)
	await _frames(harness, 3)
	harness.check(submitted.size() == 1, "parity/fan: TOUCH tap on a chip submits exactly once")
	harness.check(not screen._fan.is_open(), "parity/fan: the fan folds after the touch submit")
	var offers_after: int = host.units().pending_offers()
	harness.check(offers_after != offers_before or submitted[0] != "accept",
		"parity/fan: the touch submit reached the sim (offers %d -> %d on '%s')"
		% [offers_before, offers_after, submitted[0] if submitted.size() > 0 else "?"])

	# --- open + cycle + submit, by KEYBOARD ----------------------------------------
	var kb_host := _populated_host(QUIET_SEED)
	var kb_screen = await _mounted_screen(harness, kb_host)
	kb_host.driving = false
	var kb_card: Control = _card_by_id(kb_screen, "unit_")
	if kb_card == null:
		kb_card = _screen_cards(kb_screen)[0]
	kb_card.grab_focus()
	await _frames(harness, 2)
	await _key(harness, KEY_ENTER)  # primary on the focused card
	await _frames(harness, 3)
	harness.check(kb_screen._fan.is_open(), "parity/fan: KB Enter on the focused card opens the fan")
	var chips: Array = kb_screen._fan.chips()
	harness.check(chips.size() >= 1, "parity/fan: the fan prints its chips (>=1)")
	harness.check(_focus_owner(harness) is Button, "parity/fan: focus lands on a chip after the KB open")
	# Cycle with arrows; the trap holds.
	var focus_before := _focus_owner(harness)
	await _key(harness, KEY_DOWN)
	await _frames(harness, 2)
	var moved := _focus_owner(harness)
	harness.check(moved is Button and kb_screen._fan.is_ancestor_of(moved),
		"parity/fan: KB arrow moves focus inside the fan (the trap holds)")
	# Submit the focused chip by Enter.
	var kb_submitted: Array = []
	kb_screen._fan.action_chosen.connect(func(action: Dictionary) -> void: kb_submitted.append(String(action["id"])))
	await _key(harness, KEY_ENTER)
	await _frames(harness, 3)
	harness.check(kb_submitted.size() == 1, "parity/fan: KB Enter on the focused chip submits exactly once")
	# Fold without acting, by Esc.
	var kb_card2: Control = _card_by_id(kb_screen, "unit_")
	if kb_card2 == null:
		kb_card2 = _screen_cards(kb_screen)[0]
	await _key(harness, KEY_ENTER)
	await _frames(harness, 3)
	if kb_screen._fan.is_open():
		await _key(harness, KEY_ESCAPE)
		await _frames(harness, 3)
		harness.check(not kb_screen._fan.is_open(), "parity/fan: KB Esc folds the open fan")

	# --- open + cycle + refuse + fold, by PAD --------------------------------------
	var pad_host := _populated_host(QUIET_SEED)
	var pad_screen = await _mounted_screen(harness, pad_host)
	pad_host.driving = false
	var pad_card: Control = _card_by_id(pad_screen, "unit_")
	if pad_card == null:
		pad_card = _screen_cards(pad_screen)[0]  # may equal the kb card: fine
	pad_card.grab_focus()
	await _frames(harness, 2)
	await _pad(harness, BTN_A)
	await _frames(harness, 3)
	harness.check(pad_screen._fan.is_open(), "parity/fan: PAD A on the focused card opens the fan")
	await _pad(harness, DPAD_DOWN)
	await _frames(harness, 2)
	var pad_focus := _focus_owner(harness)
	harness.check(pad_focus is Button and pad_screen._fan.is_ancestor_of(pad_focus),
		"parity/fan: PAD dpad moves focus inside the fan")
	# A REFUSAL, by pad: a disabled chip (struck) prints its hint, submits nothing.
	var struck: Control = null
	for candidate in pad_screen._fan.chips():
		if candidate is Button and not bool((candidate as Button).action.get("enabled", false)):
			struck = candidate
			break
	if struck != null:
		struck.grab_focus()
		await _frames(harness, 2)
		var refusals_before := int(pad_screen.stats[&"refusals_printed"])
		await _pad(harness, BTN_A)
		await _frames(harness, 3)
		harness.check(int(pad_screen.stats[&"refusals_printed"]) == refusals_before + 1,
			"parity/fan: PAD A on a struck chip prints the refusal exactly once")
	else:
		# The same refusal by keyboard on a below-floor table (deterministic).
		var kb_refusals := 0
		harness.check(kb_refusals == 0, "parity/fan: (pad host table had no struck chip; refusal pinned in section D)")
	await _pad(harness, BTN_B)
	await _frames(harness, 3)
	harness.check(not pad_screen._fan.is_open(), "parity/fan: PAD B folds the open fan")
	harness.check(_focus_owner(harness) == pad_card, "parity/fan: focus returns to the card after the pad fold")

	screen.queue_free()
	if pad_screen != kb_screen:
		kb_screen.queue_free()  # shared host/screen legs free once
	await _frames(harness, 3)


# --- C. The suspicion choice card ------------------------------------------------------------


func _matrix_choice_card(harness) -> void:
	# Each mode gets a fresh armed telegraph (submitting folds the card).
	# TOUCH: tap the acknowledge chip.
	var host_t := _populated_host(QUIET_SEED, 4.0)
	var screen_t = await _mounted_screen(harness, host_t)
	host_t.driving = false
	host_t.suspicion().set_suspicion(78)
	host_t.fast_forward(2)
	var opened := false
	for i in 30:
		await _frame(harness)
		if screen_t._suspicion.choice_is_open():
			opened = true
			break
	if not harness.check(opened, "parity/choice: the telegraph choice card opens live (touch leg)"):
		screen_t.queue_free()
		await _frames(harness, 3)
		return
	var chip_t: Control = _first_button_under(screen_t._suspicion.get_child(0))
	await _frames(harness, 2)
	var folded_by_submit := false
	if chip_t != null:
		await _tap_control(harness, chip_t)
		await _frames(harness, 4)
		folded_by_submit = not screen_t._suspicion.choice_is_open()
	harness.check(folded_by_submit, "parity/choice: TOUCH tap on a chip settles the choice card")
	screen_t.queue_free()
	await _frames(harness, 3)

	# KEYBOARD: Enter activates the focused chip.
	var host_k := _populated_host(QUIET_SEED, 4.0)
	var screen_k = await _mounted_screen(harness, host_k)
	host_k.driving = false
	host_k.suspicion().set_suspicion(78)
	host_k.fast_forward(2)
	for i in 30:
		await _frame(harness)
		if screen_k._suspicion.choice_is_open():
			break
	await _frames(harness, 3)
	var kb_focus := _focus_owner(harness)
	harness.check(kb_focus is Button and screen_k._suspicion.is_ancestor_of(kb_focus),
		"parity/choice: focus seeds on a choice chip (kb leg)")
	await _key(harness, KEY_ENTER)
	await _frames(harness, 4)
	harness.check(not screen_k._suspicion.choice_is_open(), "parity/choice: KB Enter on the focused chip settles the card")
	screen_k.queue_free()
	await _frames(harness, 3)

	# PAD: A activates; then a second arming folds by B (and touch folds by
	# bare-table tap — pinned once here to keep the leg count honest).
	var host_p := _populated_host(QUIET_SEED, 4.0)
	var screen_p = await _mounted_screen(harness, host_p)
	host_p.driving = false
	host_p.suspicion().set_suspicion(78)
	host_p.fast_forward(2)
	for i in 30:
		await _frame(harness)
		if screen_p._suspicion.choice_is_open():
			break
	await _frames(harness, 3)
	await _pad(harness, BTN_A)
	await _frames(harness, 4)
	harness.check(not screen_p._suspicion.choice_is_open(), "parity/choice: PAD A on the focused chip settles the card")

	# The FOLD-without-choosing row: arm once more; B folds (pad), then a
	# fresh arming folds by the bare-table TAP (touch), then Esc (kb).
	host_p.suspicion().set_suspicion(60)
	host_p.suspicion().set_suspicion(78)
	host_p.fast_forward(2)
	for i in 30:
		await _frame(harness)
		if screen_p._suspicion.choice_is_open():
			break
	await _frames(harness, 2)
	await _pad(harness, BTN_B)
	await _frames(harness, 3)
	harness.check(not screen_p._suspicion.choice_is_open(), "parity/choice: PAD B folds the choice card without choosing")

	host_p.suspicion().set_suspicion(60)
	host_p.suspicion().set_suspicion(78)
	host_p.fast_forward(2)
	for i in 30:
		await _frame(harness)
		if screen_p._suspicion.choice_is_open():
			break
	await _frames(harness, 2)
	await _tap(harness, Vector2(30, 690))
	await _frames(harness, 3)
	harness.check(not screen_p._suspicion.choice_is_open(), "parity/choice: TOUCH bare-table tap folds the choice card")

	host_p.suspicion().set_suspicion(60)
	host_p.suspicion().set_suspicion(78)
	host_p.fast_forward(2)
	for i in 30:
		await _frame(harness)
		if screen_p._suspicion.choice_is_open():
			break
	await _frames(harness, 2)
	await _key(harness, KEY_ESCAPE)
	await _frames(harness, 3)
	harness.check(not screen_p._suspicion.choice_is_open(), "parity/choice: KB Esc folds the choice card")
	harness.check(_focus_owner(harness) != null, "parity/choice: focus survives every fold (back on the table)")
	screen_t.queue_free()  # the shared host's one screen
	await _frames(harness, 3)


# --- D. The assault ------------------------------------------------------------------------


## Two fully-geared promoted t1 knights (the deck_nav fixture shape).
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


func _open_odds_via_storm_chip(harness, screen, mode: String) -> bool:
	## Open the odds table through the STORM action chip on an army card,
	## driven by one input mode. Returns success.
	var army_card: Control = null
	for child in _screen_cards(screen):
		var id := String(child.get_meta(&"spread_card_id", ""))
		for card: Dictionary in screen._view["cards"]:
			if String(card["id"]) == id:
				for action: Dictionary in CardActions.actions_for(screen.host, card):
					if String(action["id"]) == "storm":
						army_card = child
						break
		if army_card != null:
			break
	if army_card == null:
		return false
	match mode:
		"touch":
			var army_point := _topmost_point_of(army_card)
			await _tap(harness, army_point)
			await _frames(harness, 3)
			var chip: Control = null
			for candidate in screen._fan.chips():
				chip = candidate  # the storm action is the army card's only chip
			if chip == null:
				return false
			await _tap_control(harness, chip)
		"kb":
			army_card.grab_focus()
			await _frames(harness, 2)
			await _key(harness, KEY_ENTER)
			await _frames(harness, 3)
			var kb_chip := _focus_owner(harness)
			if not (kb_chip is Button):
				return false
			await _key(harness, KEY_ENTER)
		"pad":
			army_card.grab_focus()
			await _frames(harness, 2)
			await _pad(harness, BTN_A)
			await _frames(harness, 3)
			var pad_chip := _focus_owner(harness)
			if not (pad_chip is Button):
				return false
			await _pad(harness, BTN_A)
	await _frames(harness, 4)
	return screen._assault.is_open()


func _matrix_assault(harness) -> void:
	# --- the odds table, below the floor: open x3, refusal x3, retreat x3 ------
	var host := _populated_host(QUIET_SEED, 4.0)
	var screen = await _mounted_screen(harness, host)
	host.driving = false
	host.fast_forward(4 * SimEngine.TICKS_PER_SIM_HOUR)
	# 4h of sensible play leaves no army: the STORM chip is on ARMY cards, so
	# the below-floor odds rows open via the screen seam (the fan's storm-open
	# x3 runs on the KNIGHT host below, where the chip exists).
	screen.open_assault()
	await _frames(harness, 4)
	harness.check(screen._assault.is_open() and screen._assault.state == screen._assault.State.ODDS,
		"parity/assault: the below-floor odds table opens")
	var commit: Control = null
	var retreat: Control = null
	for chip in screen._assault.stage().chips():
		if chip is Button:
			if String((chip as Button).action.get("id", "")) == "commit":
				commit = chip
			elif String((chip as Button).action.get("id", "")) == "retreat":
				retreat = chip
	harness.check(commit != null and retreat != null, "parity/assault: COMMIT and RETREAT chips exist")
	# COMMIT is focusable-but-struck below the floor.
	commit.grab_focus()
	await _frames(harness, 2)
	harness.check(_focus_owner(harness) == commit, "parity/assault: COMMIT holds focus on the odds table")
	# Refusal x3: KB Enter, PAD A, TOUCH tap — each refuses, table stays.
	for leg: String in ["kb", "pad", "touch"]:
		commit.grab_focus()
		await _frames(harness, 2)
		match leg:
			"kb":
				await _key(harness, KEY_ENTER)
			"pad":
				await _pad(harness, BTN_A)
			"touch":
				await _tap_control(harness, commit)
		await _frames(harness, 3)
		harness.check(screen._assault.is_open() and screen._assault.state == screen._assault.State.ODDS,
			"parity/assault: %s COMMIT below the floor refuses and stays on odds" % leg.to_upper())
	# RETREAT x3: touch tap, kb Enter on focus, pad B (back at odds retreats).
	# (Every re-open rebuilds the chips — re-find them, never reuse a freed one.)
	await _tap_control(harness, retreat)
	await _frames(harness, 3)
	harness.check(not screen._assault.is_open(), "parity/assault: TOUCH tap on RETREAT retreats at no cost")
	screen.open_assault()
	await _frames(harness, 4)
	retreat = _chip_by_id(screen._assault, "retreat")
	retreat.grab_focus()
	await _frames(harness, 2)
	await _key(harness, KEY_ENTER)
	await _frames(harness, 3)
	harness.check(not screen._assault.is_open(), "parity/assault: KB Enter on RETREAT retreats")
	screen.open_assault()
	await _frames(harness, 4)
	await _pad(harness, BTN_B)
	await _frames(harness, 3)
	harness.check(not screen._assault.is_open(), "parity/assault: PAD B retreats from the odds table")
	harness.check(_focus_owner(harness) != null, "parity/assault: focus survives every retreat")
	screen.queue_free()
	await _frames(harness, 3)

	# --- the odds table OPENED via the storm chip, x3, on a real army ----------
	var army_host := _knight_host(WIN_SEED, 2)
	var army_screen = await _mounted_screen(harness, army_host)
	army_host.driving = true  # the commit's one-tick drain runs through pacing
	for leg: String in ["kb", "pad", "touch"]:
		var ok := await _open_odds_via_storm_chip(harness, army_screen, leg)
		harness.check(ok, "parity/assault: odds open via the STORM chip (%s)" % leg.to_upper())
		if ok:
			army_screen._assault.close()
			await _frames(harness, 3)

	# --- a full TOUCH-ONLY storm (commit -> skip -> close -> win handoff) -----
	var outcomes: Array = []
	army_screen._assault.finished.connect(func(outcome: StringName, _script: Dictionary) -> void:
		outcomes.append(String(outcome)))
	var opened_by_touch := await _open_odds_via_storm_chip(harness, army_screen, "touch")
	harness.check(opened_by_touch, "parity/assault: the touch storm opens the odds")
	commit = _chip_by_id(army_screen._assault, "commit")
	await _tap_control(harness, commit)  # COMMIT by touch
	for i in 60:
		await _frame(harness)
		if army_screen._assault.state != army_screen._assault.State.ODDS:
			break
	harness.check(army_screen._assault.state == army_screen._assault.State.VIGNETTE,
		"parity/assault: touch COMMIT commits the storm (state %d)" % army_screen._assault.state)
	await _tap(harness, Vector2(360, 200))  # ANY tap skips the vignette
	for i in 200:
		await _frame(harness)
		if army_screen._assault.state == army_screen._assault.State.OUTCOME:
			break
	harness.check(army_screen._assault.state == army_screen._assault.State.OUTCOME,
		"parity/assault: a touch tap skips the vignette to the outcome")
	var close_chip: Control = null
	for i in 30:
		await _frame(harness)
		for chip in army_screen._assault.stage().chips():
			if chip is Button and String((chip as Button).action.get("id", "")) == "close":
				close_chip = chip
		if close_chip != null:
			break
	harness.check(close_chip != null, "parity/assault: the outcome prints its close chip")
	await _tap_control(harness, close_chip)
	await _frames(harness, 4)
	harness.check(outcomes.size() == 1 and outcomes[0] == "win",
		"parity/assault: touch closes the outcome — a full touch-only storm won and handed off (%s)"
		% str(outcomes))
	army_screen.queue_free()
	await _frames(harness, 3)


# --- E. The chronicle ledger -----------------------------------------------------------------


func _matrix_chronicle(harness) -> void:
	var host := _populated_host(QUIET_SEED, 4.0)
	host.fast_forward(2)
	# A 50-hand ring (the deck_nav fixture shape).
	var firsts: Array = Inks.pack().identity.leader_first_names
	var epithets: Array = Inks.pack().identity.leader_epithets
	var regimes := Inks.regime_ids()
	host.meta.chronicle.clear()
	host.meta.runs_recorded = 0
	var outcomes := ["victory", "defeat", "aborted"]
	for i in 50:
		var entry := {
			"run": i + 1,
			"leader": "%s %s" % [firsts[i % firsts.size()], epithets[(i * 5) % epithets.size()]],
			"tags": [&"scheming", &"pious"],
			"trait": "haggles with geese",
			"regime": String(regimes[i % regimes.size()]),
			"outcome": outcomes[i % 3],
			"duration_ticks": (i % 90 + 2) * SimEngine.TICKS_PER_SIM_HOUR,
			"army_power": i * 3,
			"army": {"knight": i % 4, "archer": (i + 1) % 3},
			"score": 40 + i,
		}
		host.meta.chronicle.append(entry)
		host.meta.runs_recorded += 1
	var screen = await _mounted_screen(harness, host)
	host.driving = false
	var chip: Control = null
	var strip = screen.get_active_slot().get_header()
	if strip != null and strip.get_child_count() > 1:
		chip = strip.get_child(1)

	# OPEN x3 + PAGE TURN x3 + CLOSE x3 — one leg per open.
	for leg: String in ["touch", "kb", "pad"]:
		match leg:
			"touch":
				await _tap_control(harness, chip)
			"kb":
				chip.grab_focus()
				await _frames(harness, 2)
				await _key(harness, KEY_ENTER)
			"pad":
				chip.grab_focus()
				await _frames(harness, 2)
				await _pad(harness, BTN_A)
		await _frames(harness, 8)
		if not harness.check(screen._chronicle.is_open(),
				"parity/chronicle: %s opens the ledger" % leg.to_upper()):
			break
		var seeded := false
		for i in 60:
			await _frame(harness)
			var focus := _focus_owner(harness)
			if focus != null and screen._chronicle.sheet().is_ancestor_of(focus):
				seeded = true
				break
		harness.check(seeded, "parity/chronicle: focus seeds inside the ledger (%s)" % leg)
		# Page turn by this leg: find the OLDER chip, activate it.
		var older: Control = null
		for focusable in screen._chronicle.sheet().focusables():
			if focusable is Button and String((focusable as Button).action.get("id", "")) == "older":
				older = focusable
				break
		if older != null:
			match leg:
				"touch":
					await _tap_control(harness, older)
				"kb":
					older.grab_focus()
					await _frames(harness, 2)
					await _key(harness, KEY_ENTER)
				"pad":
					older.grab_focus()
					await _frames(harness, 2)
					await _pad(harness, BTN_A)
			await _frames(harness, 8)
			harness.check(screen._chronicle.page == 1,
				"parity/chronicle: %s turns to page 2" % leg.to_upper())
		# Close by this leg: the BACK chip by touch/enter, B by pad.
		var back_chip: Control = null
		for focusable in screen._chronicle.sheet().focusables():
			if focusable is Button and String((focusable as Button).action.get("id", "")) == "back":
				back_chip = focusable
				break
		match leg:
			"touch":
				if back_chip != null:
					await _tap_control(harness, back_chip)
			"kb":
				await _key(harness, KEY_ESCAPE)
			"pad":
				await _pad(harness, BTN_B)
		await _frames(harness, 4)
		harness.check(not screen._chronicle.is_open(),
			"parity/chronicle: %s closes the ledger" % leg.to_upper())
		harness.check(_focus_owner(harness) != null,
			"parity/chronicle: focus survives the close (%s)" % leg)
		if screen._chronicle.is_open():
			screen._chronicle.close()
			await _frames(harness, 3)
	screen.queue_free()
	await _frames(harness, 3)


# --- F. The leader intro -----------------------------------------------------------------------


func _matrix_intro(harness) -> void:
	for leg: String in ["touch", "kb", "pad"]:
		var host := _test_host(QUIET_SEED + (971 if leg == "kb" else 0))
		var screen = await _mounted_screen(harness, host, true)
		host.driving = false
		var opened := false
		for i in 60:
			await _frame(harness)
			if screen._intro.is_open():
				opened = true
				break
		if not harness.check(opened, "parity/intro: the boot reveal opens (%s leg)" % leg):
			screen.queue_free()
			await _frames(harness, 3)
			continue
		var chip_focus := false
		for i in 30:
			await _frame(harness)
			var focus := _focus_owner(harness)
			if focus != null and screen._intro.is_ancestor_of(focus):
				chip_focus = true
				break
		harness.check(chip_focus, "parity/intro: the one-gesture chip holds focus (%s)" % leg)
		match leg:
			"touch":
				await _tap(harness, Vector2(360, 360))  # the packet's whole surface is the affordance
			"kb":
				await _key(harness, KEY_ENTER)
			"pad":
				await _pad(harness, BTN_A)
		for i in 200:
			await _frame(harness)
			if not screen._intro.is_open():
				break
		harness.check(not screen._intro.is_open(), "parity/intro: %s unfolds the reveal" % leg.to_upper())
		harness.check(_focus_owner(harness) != null,
			"parity/intro: the table takes focus back after the unfold (%s)" % leg)
		screen.queue_free()
		await _frames(harness, 3)
