## Main — the game's FRONT DOOR (the post-acceptance boot shell).
##
## The main scene is what Play/F5 runs, so this screen IS the game's
## boot: it constructs the REAL GameHost (canonical composition, NO demo
## policy — no autopilot, no accel keys), boots it against user://saves
## (meta + run domains; a fresh install starts its first run right here),
## and routes the session the honest way:
##
##   FRESH INSTALL (no run save) — the game's name as a print card on
##     the table ground: "CASTLE STORM" letterpress, one flavor line,
##     a single BEGIN affordance (one gesture, all three input modes —
##     the intro-reveal precedent). BEGIN mounts the Spread, whose
##     T-UI-05 first-deal reveal owns the opening moment.
##
##   LIVE RUN SAVE — the same title card showing the live hand (the
##     leader keeps the standard, hour N) with CONTINUE (primary, seeded
##     focus: the away window resolves through the real catch-up service
##     at the press, then the Spread opens T-UI-09's resumed unfold +
##     the while-you-were-away print) and NEW RUN (secondary, behind the
##     in-world TWO-STEP CONFIRM — the odds-COMMIT grammar: the first
##     press arms the chip and prints the clerk's caution, the second
##     ends the live hand through the REAL run_abort verb so the
##     chronicle records the abandon honestly and the bank keeps what it
##     earned; the Spread then deals the new hand through the intro's
##     own restart). Abandoning a live run banks its meta — PRODUCT.md
##     principle #3 — and the chronicle says "aborted", never a lie.
##
##   META, RUN ENDED (crushed/won last session) — the fresh title again
##     (the cleared table's flavor); BEGIN mounts the Spread with the
##     new-hand entry: the intro derives the win/loss restart variant
##     from the ACTUAL chronicle and deals the next hand under the
##     ruling regime (the existing restart logic, unchanged).
##
## The title card is paper on the table ground in the world's grammar
## (DESIGN.md's anti-goal list holds: no popup chrome, no modal) and the
## platform boundary is wired while it owns the screen — OS lifecycle
## notifications flush the save through AppLifecycle exactly like the
## Spread does once it mounts. Boot timestamps are INJECTED for tests
## (`injected_now_epoch`); the one clock read lives at the platform
## seams (the platform host's privilege, per the security inventory).
extends Control

const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const LegacyScreenScript := preload("res://ui/screens/legacy/legacy_screen.gd")
const HowToScreenScript := preload("res://ui/screens/howto/howto_screen.gd")
const GROUND_SCENE := preload("res://ui/theme/table_ground.tscn")
const RULE_SCRIPT := preload("res://ui/theme/rule_mark.gd")

## The boot routes (pure table — tests pin it).
const ROUTE_BEGIN_FRESH := &"begin_fresh"
const ROUTE_CONTINUE := &"continue"
const ROUTE_BEGIN_NEXT := &"begin_next"

## Deterministic identity source for a fresh install (the demo seed's
## twin; CS_SEED overrides — the same seam the demo host honors).
const BOOT_SEED := 20261103

## The real save root (the demo's CS_DEMO_RESET wipe is DEMO-ONLY and
## never touches the front door).
const SAVE_ROOT := "user://saves"

## The title card's paper width (the blockquote panel family; scales
## with the type factor like every text-bearing budget).
const CARD_WIDTH := 560.0

## The game's name as printed on the card (the display face's small
## caps carry the letterpress).
const GAME_NAME := "CASTLE STORM"

## The front door's Legacy chip label (L1-C — the code-side verb
## grammar, the header verbs row's own).
const LEGACY_CHIP_LABEL := "The Legacy"

## The front door's How-to-Play chip label (the tutorial upgrade — the
## pamphlet one gesture away from the very first door, every route).
const HOWTO_CHIP_LABEL := "How to Play"

## The REAL engine host this shell booted (null before _ready).
var host: GameHost

## Save root + seed + clock seam (tests inject all three BEFORE mount;
## the defaults are the player's real session).
var save_root := SAVE_ROOT
var run_seed := 0  # 0 -> BOOT_SEED unless CS_SEED overrides
var injected_now_epoch := -1  # -1 -> the platform clock at each seam

## The mounted Spread (null while the title owns the screen).
var spread: SpreadScreen

## The active boot route (set by _ready; ROUTE_*).
var route: StringName

## The platform boundary policy while the TITLE owns the screen (the
## spread mounts its own when it takes over; this one goes idle then).
var _lifecycle: AppLifecycle

var _title_layer: Control
var _card: TitleCard
var _flavor_label: Label
var _caution_label: Label
var _begin_chip: ActionFan.ActionChip
var _continue_chip: ActionFan.ActionChip
var _new_run_chip: ActionFan.ActionChip
## The Legacy deck chip on the title card (L1-C): present only once a
## hand has ended (the bank is why a player returns) — the growing deck
## opens as paper over the title's own table.
var _legacy_chip: ActionFan.ActionChip
## The How-to-Play chip on the title card (the tutorial upgrade): ALWAYS
## present, every route — the printed primer is one gesture from the
## front door.
var _howto_chip: ActionFan.ActionChip
## The how-to pamphlet composed over the title (null until first opened;
## the title's own paper, like the legacy deck).
var _howto: HowToScreenScript
## The NEW-RUN confirm latch (the odds-COMMIT grammar's armed step).
var _new_run_armed := false
## The legacy deck composed over the title (null until first opened).
var _legacy: LegacyScreenScript


func _ready() -> void:
	TypeScale.ensure_applied()  # the T-QA-05 type-scale seam (boot-time)
	# THE REAL HOST — canonical composition, the player's save root, no
	# demo policy anywhere near it.
	if run_seed == 0:
		run_seed = _seed_value()
	host = GameHost.new(run_seed, save_root)
	var loaded := host.boot(0)  # NEVER resolve the window here — the
	# title IS the foreground boundary; CONTINUE is the foreground press.
	# The persisted preferences apply BEFORE any chrome bakes sizes (the
	# press-room's boot seam — a player who set 1.3x boots at 1.3x).
	_apply_boot_preferences()
	route = route_for(loaded, host.is_run_running(), host.meta.runs_recorded)
	_compose_title()
	_lifecycle = AppLifecycle.new()
	_lifecycle.host = host
	print("[boot] title card mounted (mode=%s)" % String(route))


# --- routing (pure — the boot decision table) -------------------------------------


## The boot route: a loadable run save with a RUNNING run is CONTINUE;
## anything else is a BEGIN (the fresh install's first when nothing is
## recorded, the cleared-table BEGIN when the last session ended the
## run). `p_loaded` is host.boot()'s "a save loaded" return;
## `p_runs_recorded` separates the two BEGINs.
static func route_for(p_loaded: bool, p_run_running: bool,
		p_runs_recorded: int) -> StringName:
	if p_loaded and p_run_running:
		return ROUTE_CONTINUE
	return ROUTE_BEGIN_FRESH if p_runs_recorded == 0 else ROUTE_BEGIN_NEXT


## The spread entry the route's primary gesture mounts: the fresh first
## deal lets the spread's own boot rule decide (T-UI-05's reveal); an
## ended meta DEALS the next hand (the intro's restart, from the
## chronicle); CONTINUE resumes (T-UI-09's check-in, from the report).
static func entry_for(p_route: StringName) -> StringName:
	if p_route == ROUTE_BEGIN_NEXT:
		return SpreadScreen.ENTRY_NEW_HAND
	return SpreadScreen.ENTRY_AUTO


## The title card's copy line under the name: the fresh press's flavor,
## the cleared table's flavor, or the live hand's line (every word from
## the run lifecycle's own query surfaces — the card cannot lie about
## the hand it offers to continue).
static func flavor_line_for(p_host: GameHost, p_route: StringName) -> String:
	var table: CopyTable = Inks.pack().copy
	var rotor := p_host.meta.runs_recorded
	match p_route:
		ROUTE_CONTINUE:
			return CopyDeck.line(table, &"title_hold", rotor, {
				"first": p_host.run().leader_first_name(),
				"hours": maxi(0, p_host.engine.sim_hours()),
			})
		ROUTE_BEGIN_NEXT:
			return CopyDeck.line(table, &"title_flavor_return", rotor)
		_:
			return CopyDeck.line(table, &"title_flavor", rotor)


# --- the title card (paper on the table ground) -----------------------------------


## Compose the boot surface: the neutral table ground full-rect, the
## centered print card (name + rule + flavor + the affordance chips),
## focus seeded on the route's primary chip.
func _compose_title() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer = Control.new()
	_title_layer.name = "TitleLayer"
	_title_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_layer)

	var ground := GROUND_SCENE.instantiate() as Control
	ground.name = "TableGround"
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_layer.add_child(ground)

	var center := CenterContainer.new()
	center.name = "TitleCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(center)

	_card = TitleCard.new()
	_card.name = "TitleCard"
	_card.custom_minimum_size = Vector2(CARD_WIDTH * TypeScale.factor(), 0.0)
	_card.gui_input.connect(_on_card_gui_input)
	center.add_child(_card)

	var box := VBoxContainer.new()
	box.name = "CardBox"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 26.0
	box.offset_top = 20.0
	box.offset_right = -26.0
	box.offset_bottom = -20.0
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(box)

	var name_label := Label.new()
	name_label.theme_type_variation = &"CardTitle"
	name_label.add_theme_font_size_override("font_size", TypeScale.scaled(44))
	name_label.text = GAME_NAME
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var rule := RULE_SCRIPT.new()
	rule.form = RULE_SCRIPT.RuleForm.SOLID
	rule.rule_ink = Inks.RED
	rule.rule_width = 3.0
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)

	_flavor_label = _card_line()
	_flavor_label.text = flavor_line_for(host, route)
	box.add_child(_flavor_label)

	_caution_label = _card_line()
	_caution_label.add_theme_color_override("font_color", Inks.RED)
	_caution_label.visible = false
	box.add_child(_caution_label)

	box.add_child(_build_chips())
	_seed_focus.call_deferred()


## One italic clerk's-hand line on the card (chronicle grammar, ink on
## paper — the print rule's light branch).
func _card_line() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ChronicleLine"
	label.add_theme_color_override("font_color", Inks.INK)
	label.add_theme_font_size_override("font_size", TypeScale.scaled(22))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The route's affordance chips: one BEGIN (fresh/ended) or CONTINUE
## (primary, signature) + NEW RUN (secondary). Full grips; the chip
## column is a cyclic focus trap (pad parity — the fan's rule).
## L1-C: once a hand has ENDED anywhere on this install, THE LEGACY
## chip joins the column — the banked points are the reason to return,
## and the door to them lives on the front door itself.
func _build_chips() -> Control:
	var table: CopyTable = Inks.pack().copy
	var rotor := host.meta.runs_recorded
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if route == ROUTE_CONTINUE:
		_continue_chip = _chip(CopyDeck.line(table, &"title_continue", rotor), true)
		_continue_chip.pressed.connect(_on_continue)
		rows.add_child(_continue_chip)
		_new_run_chip = _chip(CopyDeck.line(table, &"title_new_run", rotor), false)
		_new_run_chip.pressed.connect(_on_new_run)
		rows.add_child(_new_run_chip)
	else:
		var key := &"title_next" if route == ROUTE_BEGIN_NEXT else &"title_begin"
		_begin_chip = _chip(CopyDeck.line(table, key, rotor), true)
		_begin_chip.pressed.connect(_on_begin)
		rows.add_child(_begin_chip)
	# THE HOW-TO CHIP (the tutorial upgrade): always — the new player's
	# door to the pamphlet, before anything else is asked of them.
	_howto_chip = _chip(HOWTO_CHIP_LABEL, false)
	_howto_chip.pressed.connect(_on_howto)
	rows.add_child(_howto_chip)
	if show_legacy_chip_for(host.meta.runs_recorded):
		_legacy_chip = _chip(LEGACY_CHIP_LABEL, false)
		_legacy_chip.pressed.connect(_on_legacy)
		rows.add_child(_legacy_chip)
	_wire_chip_cycle()
	return rows


## The Legacy chip's visibility rule (pure — tests pin it): the chip
## prints only once at least one hand has ENDED (runs_recorded counts
## ended hands). A fresh install has nothing banked and no deck worth
## reading yet — the game's first door stays single.
static func show_legacy_chip_for(runs_recorded: int) -> bool:
	return runs_recorded > 0


## CONTINUE <-> NEW RUN <-> THE LEGACY: focus cycles inside the card (a
## pad player never escapes the doors into bare table). DEFERRED — the
## chips build during _ready, before the shell enters the tree, and
## NodePaths only resolve in-tree.
func _wire_chip_cycle() -> void:
	_wire_chip_cycle_paths.call_deferred()


func _wire_chip_cycle_paths() -> void:
	var column: Array[Control] = []
	for chip: ActionFan.ActionChip in [_continue_chip, _new_run_chip, _howto_chip, _legacy_chip]:
		if chip != null:
			column.append(chip)
	if _begin_chip != null:
		column.append(_begin_chip)
	var count := column.size()
	if count == 0 or not is_inside_tree():
		return
	var paths: Array[NodePath] = []
	for node in column:
		paths.append(node.get_path())
	for i in count:
		column[i].focus_neighbor_top = paths[wrapi(i - 1, 0, count)]
		column[i].focus_neighbor_bottom = paths[wrapi(i + 1, 0, count)]


## One print-styled chip (ActionFan's ActionChip unforked — the intro
## packet's one-gesture precedent; the primary carries the signature's
## red double rule).
func _chip(label: String, signature: bool) -> ActionFan.ActionChip:
	var chip := ActionFan.ActionChip.new()
	chip.action = {
		"id": label, "label": label, "command": &"",
		"subject": &"", "value": 0, "enabled": true, "reason": "",
		"signature": signature,
	}
	chip.custom_minimum_size = Vector2(232.0, float(Inks.TOUCH_GRIP_MIN))
	return chip


## Focus lands on the route's primary affordance (chips need a frame in
## the tree — the intro's deferred-seeding precedent).
func _seed_focus() -> void:
	if _title_layer == null or not is_inside_tree():
		return
	var primary := primary_chip()
	if primary != null:
		primary.grab_focus()


## The route's primary chip (CONTINUE when a hand is live, else BEGIN).
func primary_chip() -> ActionFan.ActionChip:
	return _continue_chip if route == ROUTE_CONTINUE else _begin_chip


# --- the gestures ----------------------------------------------------------------


## BEGIN (fresh install / ended meta): no platform boundary to resolve —
## a fresh boot already started its first run, an ended meta deals the
## next hand through the intro's own restart. One gesture into the game.
func _on_begin() -> void:
	_mount_spread(entry_for(route))


## CONTINUE: THE FOREGROUND PRESS — the away window resolves through the
## real catch-up service right now (the report becomes the resumed
## reveal's away line + the while-you-were-away print), then the table
## takes over with T-UI-09's check-in unfold.
func _on_continue() -> void:
	host.foreground(_now())
	_mount_spread(SpreadScreen.ENTRY_AUTO)


## NEW RUN — the TWO-STEP CONFIRM (the odds-COMMIT grammar): the first
## press ARMS (the chip re-labels, the clerk's caution prints in red —
## one mispress never ends a hand); the second press executes. Executing
## resolves any away window first (the hand banks as it actually stood —
## an in-window crush even ends it honestly as a defeat), then the REAL
## run_abort verb goes down the host's one write path: the chronicle
## records the abandon, the bank keeps the score, the save flushes, and
## the Spread deals the new hand through the intro's loss-restart.
func _on_new_run() -> void:
	if not _new_run_armed:
		_new_run_armed = true
		var table: CopyTable = Inks.pack().copy
		var rotor := host.meta.runs_recorded
		_new_run_chip._label.text = CopyDeck.line(table, &"title_new_run_armed", rotor)
		_new_run_chip.action["label"] = CopyDeck.line(table, &"title_new_run_armed", rotor)
		_caution_label.text = CopyDeck.line(table, &"title_new_run_caution", rotor)
		_caution_label.visible = true
		return
	host.foreground(_now())
	if host.is_run_running():
		host.submit(&"run_abort")
		host.advance_ticks(1)  # the tick that drains the abort + banks the run
	host.save_all()
	_mount_spread(SpreadScreen.ENTRY_NEW_HAND)


## THE LEGACY (L1-C): the growing deck opens as PAPER OVER THE TITLE'S
## OWN TABLE (the chronicle's composition rule — the front door has its
## ground, the deck is paper on it; no modal chrome). The real host
## rides across; closing returns focus to the chip that opened it. A
## live hand beneath is fine — the deck prints the mount rule honestly.
func _on_legacy() -> void:
	if _legacy == null:
		_legacy = LegacyScreenScript.new()
		_legacy.name = "LegacyScreen"
		_legacy.set_anchors_preset(Control.PRESET_FULL_RECT)
		_title_layer.add_child(_legacy)
		_legacy.closed.connect(_on_legacy_closed)
	_legacy.open(host)


## The deck folded away over the title: focus returns to The Legacy
## chip (the affordance that opened it).
func _on_legacy_closed() -> void:
	if _legacy_chip != null:
		_legacy_chip.grab_focus()


## HOW TO PLAY (the tutorial upgrade): the printed primer opens as PAPER
## OVER THE TITLE'S OWN TABLE (the legacy deck's composition rule — no
## modal chrome at the front door either). Closing returns focus to the
## chip that opened it.
func _on_howto() -> void:
	if _howto == null:
		_howto = HowToScreenScript.new()
		_howto.name = "HowToScreen"
		_howto.set_anchors_preset(Control.PRESET_FULL_RECT)
		_title_layer.add_child(_howto)
		_howto.closed.connect(_on_howto_closed)
	_howto.open(host)


func _on_howto_closed() -> void:
	if _howto_chip != null:
		_howto_chip.grab_focus()


## The whole title card is the single-chip modes' affordance (the intro
## packet's precedent — touch parity: a tap anywhere on the paper is the
## gesture). The continue mode carries two doors; only the chips answer.
func _on_card_gui_input(event: InputEvent) -> void:
	if route == ROUTE_CONTINUE:
		return
	var pressed_here := false
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed_here = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed_here = true
	if pressed_here and _begin_chip != null:
		_begin_chip.pressed.emit()
		_card.accept_event()


## Project actions only (never ui_*): the pad's primary is NOT
## ui_accept, so a focused chip on the title answers the pad's A here —
## exactly the Spread's BaseButton fallback, one press, once.
func _unhandled_input(event: InputEvent) -> void:
	if spread != null:
		return  # the table owns input now
	if event.is_action_pressed(&"primary") and not (event is InputEventMouseButton) \
			and not (event is InputEventScreenTouch):
		var focus := get_viewport().gui_get_focus_owner()
		if focus is BaseButton:
			(focus as BaseButton).pressed.emit()
			get_viewport().set_input_as_handled()


# --- mounting the spread -----------------------------------------------------------


## Hand the screen to the Spread: the real host rides across (the
## screen's own external-mount contract — host attached BEFORE the
## tree), the title's paper folds away, and the spread's own lifecycle
## owns the platform boundary from here.
func _mount_spread(p_entry: StringName) -> void:
	if spread != null:
		return
	_lifecycle = null  # the spread wires its own
	_release_title()
	spread = SPREAD_SCENE.instantiate()
	spread.name = "SpreadScreen"
	spread.host = host
	spread.entry_mode = p_entry
	add_child(spread)


## Fold the title away (the paper never stacks on the table it dealt).
func _release_title() -> void:
	if _title_layer == null:
		return
	_title_layer.queue_free()
	_title_layer = null
	_card = null
	_flavor_label = null
	_caution_label = null
	_begin_chip = null
	_continue_chip = null
	_new_run_chip = null
	_legacy_chip = null
	_howto_chip = null
	_legacy = null  # the deck is the title's own paper — it folds with it
	_howto = null  # the primer is the title's own paper — it folds with it


# --- the platform seams -------------------------------------------------------------


## The platform host's clock (injected in tests; the ONE clock read per
## seam, the same privilege the Spread's `_notification` holds).
func _now() -> int:
	return injected_now_epoch if injected_now_epoch >= 0 \
		else int(Time.get_unix_time_from_system())


## OS lifecycle while the TITLE owns the screen: background/close take
## the away anchor and flush both save domains through AppLifecycle — a
## player who quits at the door loses nothing. Once the Spread mounts it
## owns this seam (its own `_notification`); this one goes idle.
func _notification(what: int) -> void:
	if _lifecycle == null or host == null:
		return
	_lifecycle.handle_notification(what, _now())


## The persisted preferences (the press-room's meta-domain keys) apply
## before the title bakes any size — the Spread re-applies at its own
## boot seam (idempotent, same values).
func _apply_boot_preferences() -> void:
	if host == null:
		return
	var scale_pref := host.meta.type_scale_preference()
	if scale_pref > 0.0:
		TypeScale.apply_preference(scale_pref)
	var motion_pref := host.meta.reduced_motion_preference()
	if motion_pref >= 0:
		MotionProfile.forced = motion_pref


## CS_SEED overrides the boot identity source (the demo's seam); the
## default keeps the fresh-install draw deterministic.
func _seed_value() -> int:
	var text := OS.get_environment("CS_SEED")
	if not text.is_empty() and text.is_valid_int():
		return int(text)
	return BOOT_SEED


## The title's print card: the blockquote panel grammar (cheap paper,
## double ink border) — one print block, no chrome.
class TitleCard extends Control:
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Inks.PAPER)
		draw_rect(rect.grow(-2.0), Inks.INK, false, 2.0)
		draw_rect(rect.grow(-6.0), Inks.INK, false, 1.0)
