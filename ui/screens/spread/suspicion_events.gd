## SuspicionEvents — the suspicion event layer on the Spread (T-UI-06).
##
## "STATES PRINT THEMSELVES" (design brief raise #2): crackdowns and
## suspicion beats write into the spread as paper on the table — NEVER
## popup chrome. This control owns the three suspicion moments:
##
##   CHOICE CARDS — at warn-zone entry (`suspicion_warn`) and telegraph
##     arming (`suspicion_telegraph`) a small print-styled card slides
##     onto the table's edge carrying the beat's line and the choices
##     that REALLY exist. THE LAY-LOW FINDING (honest, documented): the
##     sim has NO "lay low" command — laying low is a BEHAVIOR (stop loud
##     acts, let the meter decay, thin the gate), not a verb, and this
##     layer does not invent sim mechanics. What the card offers:
##       - "send the loiterers home" — the REAL dismiss_offer command,
##         once per gate offer past the recruit tolerance (the one
##         quieting verb the sim actually has; the demo policy's own
##         lay-low response plays the same move);
##       - "keep the cards close" — acknowledge; no command, the card
##         folds. Non-urgent (warn) cards are SKIPPABLE: they can sit
##     unanswered on the table's edge without blocking anything — the
##     table stays live beneath them. The armed-telegraph card frames
##     URGENTLY (the double red rule + the landing countdown, mirrored
##     from the Eye) but never hard-blocks: `back` folds it.
##
##   THE CRACKDOWN BLOCKQUOTE — when the telegraph lands, the strike
##     prints as a paper panel on the table: the struck headline + the
##     per-resource seizure counts (each line from the suspicion
##     system's own chronicle voice, the event's real payload) + the
##     scatter line with the NAMES of the gate crowd that was swept
##     (reconstructed from the pre-crackdown view — the world's own
##     record, offers-first per the sim's scatter rule). It dwells, then
##     folds itself; it is never modal. The Eye strikes and the ground
##     flashes aftermath-ink (the screen wires those; the pure params
##     live in WatchfulEye/TableGround); on relief (`crackdown_cancelled`
##     — the meter dropped below the threshold after arming) a calmer
##     line prints in the strip and the Eye retreats.
##
##   THE CRUSHED BEAT — the run-death story beat (T-UI-05's loss-restart
##     reveal mounts AFTER it): the table's cards print STRUCK, then
##     sweep off the paper; the crushing blockquote prints CENTERED over
##     the cleared table (placed in the beat path — content-sized, above
##     the table's floor, never the control's unplaced default corner)
##     with the regime voice placeholder (Prof X deepens in T-COPY-01)
##     and the banked-legacy line read from the REAL meta bank; then the
##     beat resolves and the intro's loss-restart reveal is dealt.
##     Skippable with one input from every mode (a player who has read it
##     deals the next hand).
##
## Everything here is paper over the table (the ActionFan/AssaultScreen
## composition rule): screen-level chrome outside the slots, re-placed on
## layout changes, never a Popup/Window/AcceptDialog.
##
## Pacing contract: the beat's strike/sweep/quote dwell run on
## SceneTreeTimers + Tweens (both follow Engine.time_scale — the T-UI-05
## injected-time test strategy); skip_beat() lands the settled state
## synchronously. Reduced motion (MotionProfile) collapses the strike +
## sweep; the quote still dwells (it is content, not motion).
class_name SuspicionEvents
extends Control

## A choice chip was activated while enabled: submit it (real commands —
## or the acknowledge chip, which submits none).
signal choice_made(action: Dictionary)
## The crush beat fully resolved (skip, pacing or dwell) — the intro's
## loss-restart reveal may now be dealt.
signal beat_finished()
## The choice card's entrance landed (the capture hook's settle probe).
signal choice_settled()

enum BeatPhase { IDLE, STRIKE, SWEEP, QUOTE }

## Authored pacing (MotionProfile-routed where it is motion).
const STRIKE_SECONDS := 0.55
const SWEEP_SECONDS := 0.85
const SWEEP_STAGGER := 0.035
const SWEEP_STAGGER_CAP := 0.25
## The quotes dwell on the table before folding themselves (content
## pacing — NOT shortened by reduced motion; a print must be readable).
const QUOTE_DWELL := 2.6
## The entrance slide (the choice card joining the table's edge).
const SLIDE_SECONDS := 0.45
## Panel widths (design units; grip = 48).
const CHOICE_WIDTH := 312.0
const QUOTE_WIDTH := 560.0

var beat_phase: int = BeatPhase.IDLE
## Instrumentation (the screen's stats mirror reads these).
var strikes_played := 0
var retreats_played := 0

var _choice: ChoiceCard
var _quote: EventQuote
var _beat_cards: Array[Control] = []
var _beat_tweens: Array[Tween] = []
var _beat_timers: Array[SceneTreeTimer] = []
var _beat_done := false
var _beat_lines: Array[Dictionary] = []
var _beat_bounds := Vector2.ZERO
var _beat_floor := 0.0
## The quote's LAST placement discipline (every `_place_quote` refreshes
## them): an append re-places through the same bounds + floor the open
## used, so the grown panel never outgrows them (round-3 fix).
var _quote_bounds := Vector2.ZERO
var _quote_floor_y := 0.0
var _quote_placed := false
var _strike_fx := Callable()  # the screen's eye-strike + ground-flash wiring


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice = ChoiceCard.new()
	_choice.name = "ChoiceCard"
	add_child(_choice)
	_choice.choice_made.connect(_on_choice_made)
	_choice.settled.connect(func() -> void: choice_settled.emit())
	_quote = EventQuote.new()
	_quote.name = "EventQuote"
	add_child(_quote)


# ----------------------------------------------------------------------------
# The choice model (pure — same sim state, same card)
# ----------------------------------------------------------------------------


## The choice card for a warn/telegraph event, as data. Pure reads of the
## host's query surfaces; every command on every chip is a REAL sim verb
## (or the acknowledge chip, which submits nothing — see the class header
## for the lay-low finding). T-COPY-01: the card's lines are the CARD
## BUDGET forms (the ~232px label — the full beat line stays in the strip,
## where the wide chronicle carries it), variants rotated by the event's
## seq through the pack's CopyTable.
static func choice_card_for(host: GameHost, event: Dictionary) -> Dictionary:
	var suspicion := host.suspicion()
	var tunables: EconomyTunables = Inks.pack().tunables
	var table: CopyTable = Inks.pack().copy
	var rotor := int(event["seq"])
	var offers: int = host.units().pending_offers()
	var telegraph: bool = event["type"] == &"suspicion_telegraph"
	var chips: Array[Dictionary] = []
	if offers > tunables.suspicion_recruit_tolerance:
		var uids: Array[int] = []
		for uid in host.units().offer_ids():
			uids.append(uid)
		chips.append({
			"id": "thin_the_gate",
			"label": CopyDeck.line(table, &"chip_dismiss", rotor, {"count": offers}),
			"multi_command": &"dismiss_offer",
			"subjects": uids,
			"enabled": true,
			"reason": "",
			"signature": false,
		})
	chips.append({
		"id": "keep_close",
		"label": CopyDeck.line(table, &"chip_keep", rotor),
		"command": &"",
		"enabled": true,
		"reason": "",
		"signature": false,
	})
	var lines: Array[Dictionary] = []
	lines.append({
		"class": Inks.line_class_for_event(event["type"]),
		"text": CopyDeck.line(table,
			&"card_telegraph_line" if telegraph else &"card_warn_line", rotor),
	})
	lines.append({
		"class": Inks.LineClass.WARN,
		"text": CopyDeck.line(table,
			&"telegraph_context" if telegraph else &"warn_context", rotor),
	})
	var hours := -1
	if telegraph:
		hours = maxi(0, int(event["value"]) - host.engine.tick_count) / SimEngine.TICKS_PER_SIM_HOUR
	return {
		"id": "telegraph" if telegraph else "warn",
		"urgent": telegraph,
		"title": "RIDERS IN THE YARD" if telegraph else "THE CROWN TAKES NOTICE",
		"lines": lines,
		"chips": chips,
		"hours_left": hours,
	}


## Determinism oracle over the choice model (same state -> same card).
static func choice_model_hash(model: Dictionary) -> int:
	var h := 0x811C9DC5
	h = _mix(h, String(model["id"]).hash())
	h = _mix(h, int(model["urgent"]))
	h = _mix(h, String(model["title"]).hash())
	h = _mix(h, int(model["hours_left"]))
	for line: Dictionary in model["lines"]:
		h = _mix(h, int(line["class"]))
		h = _mix(h, String(line["text"]).hash())
	for chip: Dictionary in model["chips"]:
		h = _mix(h, String(chip["id"]).hash())
		h = _mix(h, String(chip["label"]).hash())
		h = _mix(h, String(chip.get("multi_command", &"")).hash())
		for uid in chip.get("subjects", []):
			h = _mix(h, int(uid))
	return h


## The scatter line's NAMES, reconstructed from the world's own record:
## the pre-crackdown view still held the gate crowd when the riders came
## (the struck/seized/scattered events arrive after the mutation, all in
## one drain). Offers go first in arrival order (the sim's scatter rule),
## so the FIRST (offers_before - offers_left) names are the swept. Pure.
static func scatter_names(pre_cards: Array, scattered: int, offers_left: int) -> Dictionary:
	var offer_names: Array[String] = []
	for card in pre_cards:
		if card is Dictionary and card.get("kind", &"") == &"offer":
			offer_names.append(String(card["name"]))
	var scattered_offers := clampi(offer_names.size() - maxi(0, offers_left), 0, maxi(0, scattered))
	return {
		"names": offer_names.slice(0, scattered_offers),
		"peasants": maxi(0, scattered - scattered_offers),
	}


## The scatter rows for the blockquote (T-COPY-01: the NAMES are the
## pre-crackdown gate crowd, offers-first per the sim's scatter rule; the
## row is shaped to the quote label's 476px budget — the old 527px tail
## clipped at the label edge, the deferred T-UI-06 content matter). Two
## rows when peasants followed the offers out; one otherwise. Pure.
static func scatter_line(pre_cards: Array, event: Dictionary) -> Array[Dictionary]:
	var table: CopyTable = Inks.pack().copy
	var rotor := int(event.get("seq", 0))
	var info := scatter_names(pre_cards, int(event["value"]), int(event["value2"]))
	var names: Array = info["names"]
	var scattered := int(event["value"])
	if scattered <= 0:
		return [{"class": Inks.LineClass.STRIKE,
			"text": CopyDeck.line(table, &"scatter_none", rotor)}]
	# At most two NAMES lead the row (the blockquote's label is single-line:
	# the tail counts the rest — the sim's own scatter rule, offers first).
	var named_count := mini(2, names.size())
	var who := ", ".join(names.slice(0, named_count))
	var more := maxi(0, scattered - named_count)
	var rows: Array[Dictionary] = [{
		"class": Inks.LineClass.STRIKE,
		"text": CopyDeck.line(table, &"scatter_row", rotor,
			{"who": who, "count": more}),
	}]
	if int(info["peasants"]) > 0:
		rows.append({
			"class": Inks.LineClass.STRIKE,
			"text": CopyDeck.line(table, &"scatter_peasants", rotor,
				{"count": int(info["peasants"])}),
		})
	return rows


## The crushing blockquote's lines (T-COPY-01 failure-feel pass): the
## regime's SMUGNESS stings first, the chronicle's record second, the
## concrete banked number banks the hope — a number you keep, read from
## the REAL meta bank after the loss resolved. The same-crest revenge
## line prints moments later in the intro's loss-restart reveal (the beat
## ends, the reveal names the crest that did it). LINE BUDGET: the
## blockquote panel is QUOTE_WIDTH wide and its chronicle rows CLIP past
## the label edge (the row grammar) — every line fits the panel in the
## REAL font metrics (docs/voice-bible.md §4; the mounted placement tests
## pin the no-clip guarantee). Variants rotate by the RUN number. Pure.
static func crush_lines(host: GameHost) -> Array[Dictionary]:
	var regime_name := Inks.regime_name(host.run().regime_id())
	if regime_name.is_empty():
		regime_name = "The Crown"
	var table: CopyTable = Inks.pack().copy
	var rotor := host.meta.runs_recorded
	return [
		{"class": Inks.LineClass.STRIKE,
			"text": CopyDeck.line(table, &"crush_regime", rotor, {"regime": regime_name})},
		{"class": Inks.LineClass.STRIKE,
			"text": CopyDeck.line(table, &"crush_chronicle", rotor)},
		{"class": Inks.LineClass.PLAIN,
			"text": CopyDeck.line(table, &"crush_bank", rotor,
				{"points": host.meta.legacy_points})},
	]


## Where the choice card slides onto: the table's LEFT edge, vertically
## centered-low (paper set apart from the deck's head at top-right).
## Always fully inside the design bounds. Pure.
static func choice_rect(bounds: Vector2, panel_size: Vector2) -> Rect2:
	var panel := Vector2(minf(CHOICE_WIDTH, bounds.x - 12.0), panel_size.y)
	var y := clampf(bounds.y * 0.5 + 30.0, 8.0, maxf(8.0, bounds.y - panel.y - 8.0))
	return Rect2(Vector2(10.0, y), panel)


## Where a blockquote prints: bottom-center, parked one breath (8px)
## above `floor_y` — the lowest paper edge the quote must clear. PORTRAIT
## passes the bottom chronicle strip's top (the quote sits above the
## strip); LANDSCAPE passes the table's bottom edge (the strip is at the
## top there, so its implied bound is negative — the old clamp parked the
## quote at the TOP, contradicting the bottom/center-bottom intent; the
## table's floor parks it center-bottom, clear of the bottom pips rail).
## Always fully inside the design bounds. Pure.
static func quote_rect(bounds: Vector2, panel_size: Vector2, floor_y: float) -> Rect2:
	var panel := Vector2(minf(QUOTE_WIDTH, bounds.x - 12.0), panel_size.y)
	var y := clampf(floor_y - panel.y - 8.0, 8.0, maxf(8.0, bounds.y - panel.y - 8.0))
	return Rect2(Vector2((bounds.x - panel.x) * 0.5, y), panel)


static func _as_sim_event(event: Dictionary) -> SimEvent:
	var sim_event := SimEvent.new()
	sim_event.seq = int(event["seq"])
	sim_event.tick = int(event["tick"])
	sim_event.type = event["type"]
	sim_event.subject = event["subject"]
	sim_event.value = int(event["value"])
	sim_event.value2 = int(event["value2"])
	return sim_event


# ----------------------------------------------------------------------------
# The choice card (open/fold + input)
# ----------------------------------------------------------------------------


## Slide the choice card on (replaces any card already on the edge — the
## telegraph supersedes the warn). Places itself within `bounds`, then
## plays the entrance (the screen re-places WITHOUT re-sliding on layout
## changes).
func open_choice(model: Dictionary, bounds: Vector2) -> void:
	_choice.open(model)
	_place_choice(bounds)
	_choice.play_entrance()


## Re-place the open card after a layout change (the screen's deferred
## relayout hook — no second entrance, the paper is already on the table).
func replace_choice(bounds: Vector2) -> void:
	if _choice.is_open():
		_place_choice(bounds)


func _place_choice(bounds: Vector2) -> void:
	_choice.size = _choice.get_combined_minimum_size()
	var rect := choice_rect(bounds, _choice.size)
	_choice.size = rect.size
	_choice.position = rect.position


func fold_choice() -> void:
	_choice.fold()


func choice_is_open() -> bool:
	return _choice.is_open()


func choice_model() -> Dictionary:
	return _choice.model


## The pad's A button when the engine does not route it as ui_accept (the
## ActionFan parity guarantee, mirrored here).
func activate_focused_choice() -> void:
	_choice.activate_focused()


## Grab focus on the card's first chip (deferred — chips need a frame in
## the tree). The screen decides WHEN seeding is polite.
func seed_choice_focus() -> void:
	_choice.seed_focus()


## True when the focused control is inside the choice card (the screen
## returns focus kindly when the card folds).
func choice_holds_focus() -> bool:
	if not _choice.is_open():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and _choice.is_ancestor_of(focus)


## Refresh the telegraph countdown on an open card (rides the per-batch
## sim_advanced signal, never per-frame polling).
func refresh_countdown(hours_left: int) -> void:
	_choice.refresh_countdown(hours_left)


func _on_choice_made(action: Dictionary) -> void:
	choice_made.emit(action)


# ----------------------------------------------------------------------------
# The blockquote (crackdown results / the crushing beat's quote)
# ----------------------------------------------------------------------------


## Begin the crackdown blockquote: headline from the struck event, in the
## system's own voice. Seized/scattered rows append as they arrive (the
## same drain). `pre_cards` is the pre-crackdown view model (the gate
## crowd's names — see scatter_names). `floor_y` is the blockquote's
## floor (see quote_rect).
func begin_quote(event: Dictionary, host: GameHost, bounds: Vector2, floor_y: float) -> void:
	var line: String = host.suspicion().chronicle_line(_as_sim_event(event))
	var rows: Array[Dictionary] = []
	if not line.is_empty():
		rows.append({"class": Inks.line_class_for_event(event["type"]), "text": line})
	_quote.open_rows(rows, QUOTE_DWELL * 2.0)
	_place_quote(bounds, floor_y)


## Open the blockquote with ALREADY-COMPOSED rows (T-UI-09's catch-up
## print: the while-you-were-away panel speaks the summary payload, not
## the suspicion vocabulary). Same grammar as every blockquote this layer
## prints — placed within bounds above floor_y, dwells, folds itself,
## never modal.
func open_quote_rows(rows: Array[Dictionary], bounds: Vector2, floor_y: float,
		dwell: float) -> void:
	_quote.open_rows(rows, dwell)
	_place_quote(bounds, floor_y)


## Append one printed row to the open quote (extends the dwell — the
## blockquote is one story, the timer restarts per print). The grown
## panel RE-PLACES through the same discipline every open uses (bounds +
## floor, content-sized at the designed width): the appends arrive in
## the same drain as the open, and an uncorrected append left the panel
## at its content-min width (~220px) growing DOWN past its floor — in
## landscape the strip ran off the window bottom and cut the scatter
## line off-screen (the round-2 verifier's find, fixed round-3).
func append_quote_row(row: Dictionary) -> void:
	_quote.append_row(row, QUOTE_DWELL * 2.0)
	if _quote_placed:
		_place_quote(_quote_bounds, _quote_floor_y)


## The scatter rows, composed with names, appended to the open quote.
func append_scatter_row(pre_cards: Array, event: Dictionary) -> void:
	for row: Dictionary in scatter_line(pre_cards, event):
		append_quote_row(row)


## Re-place an open quote after a layout change.
func replace_quote(bounds: Vector2, floor_y: float) -> void:
	if _quote.is_open():
		_place_quote(bounds, floor_y)


func _place_quote(bounds: Vector2, floor_y: float) -> void:
	_quote_bounds = bounds
	_quote_floor_y = floor_y
	_quote_placed = true
	_quote.size = _quote.get_combined_minimum_size()
	var rect := quote_rect(bounds, _quote.size, floor_y)
	_quote.size = rect.size
	_quote.position = rect.position


func quote_is_open() -> bool:
	return _quote.is_open()


## The quote's printed rows (tests + the capture hook read them).
func quote_rows() -> Array[Dictionary]:
	return _quote.rows()


func fold_quote() -> void:
	_quote.fold()


# ----------------------------------------------------------------------------
# The crushed beat (the run-death story)
# ----------------------------------------------------------------------------


## Play the beat: the table's cards print STRUCK (the Eye strikes + the
## ground flashes via `strike_fx`), then sweep off the paper, then the
## crushing blockquote dwells — PLACED like every blockquote this layer
## prints (content-sized, centered over the cleared table within `bounds`
## above `floor_y` — the beat must not inherit a stale placement or, on a
## first death with no prior crackdown, the control's unplaced default
## corner), then `beat_finished` fires (once — pacing, dwell or skip all
## land the same completion). Reduced motion collapses the strike + sweep;
## the quote still dwells.
func play_crush(cards: Array[Control], lines: Array[Dictionary], strike_fx: Callable,
		bounds: Vector2, floor_y: float) -> void:
	if beat_phase != BeatPhase.IDLE:
		return  # one death at a time; the run is over anyway
	_strike_fx = strike_fx
	_beat_cards = cards.duplicate()
	_beat_lines = lines.duplicate()
	_beat_bounds = bounds
	_beat_floor = floor_y
	_beat_done = false
	_fold_all()  # the choice card and any stale quote fold — the beat owns the paper
	beat_phase = BeatPhase.STRIKE
	for card in _beat_cards:
		if is_instance_valid(card):
			card.set("edge_form", Inks.EdgeForm.STRUCK)
			if card.has_meta(CardMotion.SETTLING_META) and CardMotion.is_settling(card):
				CardMotion.snap(card)  # a card still dealing in lands before it is swept
	if _strike_fx.is_valid():
		_strike_fx.call()
	var strike := MotionProfile.duration(STRIKE_SECONDS)
	if strike <= 0.05:
		_beat_sweep()
		return
	_after(strike, _beat_sweep)


## Skip: land the settled state NOW (cards swept, quote printed) and fire
## the completion — a player who has read the beat deals the next hand.
## Works from any phase; the completion fires exactly once.
func skip_beat() -> void:
	if beat_phase == BeatPhase.IDLE:
		return
	for tween in _beat_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_beat_tweens.clear()
	_beat_timers.clear()
	_free_beat_cards()
	_beat_open_quote(_beat_lines)
	_finish_beat()


## True while the beat owns the table (the screen freezes card re-deals).
func beat_active() -> bool:
	return beat_phase != BeatPhase.IDLE



func _beat_sweep() -> void:
	if beat_phase == BeatPhase.IDLE:
		return
	beat_phase = BeatPhase.SWEEP
	var sweep := MotionProfile.duration(SWEEP_SECONDS)
	var off := Vector2(size.x * 0.7, 46.0)
	var stagger := 0.0
	var animated := sweep > 0.05
	if animated:
		for card in _beat_cards:
			if not is_instance_valid(card):
				continue
			# The stagger rides the TWEENER (Tween has no set_delay in
			# 4.x): both the slide and the fade share it.
			var delay := minf(stagger, SWEEP_STAGGER_CAP)
			var tween := card.create_tween()
			var move := tween.tween_property(card, "position", card.position + off, sweep) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			move.set_delay(delay)
			var fade := tween.parallel().tween_property(card, "modulate:a", 0.0, sweep)
			fade.set_delay(delay)
			_beat_tweens.append(tween)
			stagger += SWEEP_STAGGER
		_after(sweep + minf(stagger, SWEEP_STAGGER_CAP), _beat_land_sweep)
	else:
		_beat_land_sweep()


func _beat_land_sweep() -> void:
	if beat_phase == BeatPhase.IDLE:
		return
	_free_beat_cards()
	_beat_tweens.clear()
	_beat_open_quote(_beat_lines)


func _free_beat_cards() -> void:
	for card in _beat_cards:
		if is_instance_valid(card) and card.get_parent() != null:
			card.get_parent().remove_child(card)
			card.queue_free()
	_beat_cards.clear()


func _beat_open_quote(lines: Array[Dictionary]) -> void:
	beat_phase = BeatPhase.QUOTE
	if not lines.is_empty():
		_quote.open_rows(lines, QUOTE_DWELL)
		_place_quote(_beat_bounds, _beat_floor)
		_after(QUOTE_DWELL, _finish_beat)
	else:
		_finish_beat()


func _finish_beat() -> void:
	if beat_phase == BeatPhase.IDLE:
		return
	beat_phase = BeatPhase.IDLE
	_beat_timers.clear()
	if not _beat_done:
		_beat_done = true
		beat_finished.emit()


## Fire `what` after `seconds` of SCALED scene time (Engine.time_scale
## applies — the T-UI-05 injected-time strategy for tests; a skipped beat
## flips the phase to IDLE, the callbacks no-op).
func _after(seconds: float, what: Callable) -> void:
	var timer := get_tree().create_timer(seconds)
	_beat_timers.append(timer)
	timer.timeout.connect(what)


func _fold_all() -> void:
	_choice.fold()
	_quote.fold()


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF


# ----------------------------------------------------------------------------
# ChoiceCard — the print-styled choice card at the table's edge
# ----------------------------------------------------------------------------


## A paper quad on the table's edge: a title under a leading rule (SOLID
## ink for the warn card, the DOUBLE red rule for the urgent telegraph —
## the signature form language), the beat's chronicle lines (ink on
## paper), the landing countdown while the telegraph is armed, and a
## column of ActionChips (unforked — the intro's composition rule). The
## chips are focusable >=48 grips; the card does NOT trap focus (it opens
## by the world, not the player — navigation may leave; `back` folds it).
class ChoiceCard:
	extends MarginContainer

	signal choice_made(action: Dictionary)
	signal settled

	const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")
	const CHRONICLE_SCENE := preload("res://ui/theme/chronicle_line.tscn")
	const PAD := 12.0
	## The entrance slide's travel (from off the table's left edge).
	const CHOICE_SLIDE_OFFSET := 90.0

	var model := {}

	var _title: Label
	var _rule: Control
	var _countdown: Label
	var _content: VBoxContainer
	var _line_rows: Array[Control] = []
	var _chips: Array[ActionFan.ActionChip] = []
	var _slide: Tween


	func _init() -> void:
		add_theme_constant_override("margin_left", PAD)
		add_theme_constant_override("margin_right", PAD)
		add_theme_constant_override("margin_top", PAD)
		add_theme_constant_override("margin_bottom", PAD)
		mouse_filter = Control.MOUSE_FILTER_PASS
		visible = false


	func _ready() -> void:
		_content = VBoxContainer.new()
		_content.add_theme_constant_override("separation", 5)
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_content)

		_rule = RULE_SCENE.instantiate()
		_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(_rule)

		_title = Label.new()
		_title.theme_type_variation = &"CardTitle"
		_title.add_theme_font_size_override("font_size", 22)
		_title.clip_text = true
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(_title)

		_countdown = Label.new()
		_countdown.theme_type_variation = &"RoleLine"
		_countdown.add_theme_font_size_override("font_size", 17)
		_countdown.add_theme_color_override("font_color", Inks.RED)
		_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(_countdown)

		for i in 2:
			var line: Control = CHRONICLE_SCENE.instantiate()
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_content.add_child(line)
			_line_rows.append(line)


	func _draw() -> void:
		## The paper quad + its ink border (cheap print, chamfered by hand:
		## two corner cuts — the card grammar's cut stock, not rounded luxe).
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Inks.PAPER)
		draw_rect(rect.grow(-1.5), Inks.INK, false, 2.0)
		var c := 7.0
		draw_line(Vector2(c, 0), Vector2(0, c), Inks.PAPER, 4.0, true)
		draw_line(Vector2(rect.end.x - c, 0), Vector2(rect.end.x, c), Inks.PAPER, 4.0, true)
		draw_line(Vector2(c, rect.end.y), Vector2(0, rect.end.y - c), Inks.PAPER, 4.0, true)
		draw_line(Vector2(rect.end.x - c, rect.end.y), Vector2(rect.end.x, rect.end.y - c), Inks.PAPER, 4.0, true)


	func open(for_model: Dictionary) -> void:
		model = for_model
		var urgent := bool(model.get("urgent", false))
		_rule.set("form", 3 if urgent else 0)  # RuleForm.DOUBLE / SOLID
		_rule.set("rule_ink", Inks.RED if urgent else Inks.INK)
		_title.text = String(model.get("title", ""))
		_title.add_theme_color_override("font_color", Inks.RED if urgent else Inks.INK)
		var rows: Array = model.get("lines", [])
		for i in _line_rows.size():
			var line := _line_rows[i]
			if i < rows.size():
				line.set("line_class", int(rows[i]["class"]))
				line.set("text", String(rows[i]["text"]))
				line.set("ground", Inks.PAPER)
				line.visible = true
			else:
				line.visible = false
		refresh_countdown(int(model.get("hours_left", -1)))
		_rebuild_chips()
		visible = true
		size = get_combined_minimum_size()


	func _rebuild_chips() -> void:
		for chip in _chips:
			chip.queue_free()
		_chips.clear()
		for action in model.get("chips", []):
			var chip := ActionFan.ActionChip.new()
			chip.action = action
			chip.custom_minimum_size = Vector2(272.0, float(Inks.TOUCH_GRIP_MIN))
			chip.pressed.connect(_on_chip.bind(chip))
			_content.add_child(chip)
			_chips.append(chip)
		_wire_pad_column()


	## THE PAD COLUMN (T-PERF-02's Deck sweep find): the card does NOT
	## trap focus (left/right may leave it — the documented design), but
	## its OWN vertical walk must resolve inside the paper. The engine's
	## geometric neighbor resolution races the table beneath the edge card
	## and the dpad skipped chips outright on the Deck profile, leaving
	## verbs unreachable by pad. Wire the paper's column cyclically (the
	## fan's own rule, vertical form): every row and chip is reachable
	## from every other by dpad up/down; left/right stay free to leave.
	func _wire_pad_column() -> void:
		var column: Array[Control] = []
		for line in _line_rows:
			if line.visible:
				column.append(line)
		for chip in _chips:
			column.append(chip)
		var count := column.size()
		if count == 0:
			return
		for i in count:
			var node := column[i]
			var prev: Control = column[wrapi(i - 1, 0, count)]
			var next: Control = column[wrapi(i + 1, 0, count)]
			node.focus_neighbor_top = node.get_path_to(prev)
			node.focus_neighbor_bottom = node.get_path_to(next)


	## The entrance slide: from off the table's left edge to the placed
	## seat (the caller places FIRST — the position set here is final).
	## An interrupted slide lands immediately (re-open supersedes).
	func play_entrance() -> void:
		if _slide != null and _slide.is_valid():
			_slide.kill()
		var duration := MotionProfile.duration(SLIDE_SECONDS)
		if duration <= 0.05 or not is_inside_tree():
			settled.emit()
			return
		var final_position := position
		pivot_offset = size * 0.5
		position = final_position - Vector2(CHOICE_SLIDE_OFFSET, 0.0)
		_slide = create_tween()
		_slide.tween_property(self, "position", final_position, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_slide.tween_callback(func() -> void: settled.emit())


	func fold() -> void:
		visible = false
		model = {}
		if _slide != null and _slide.is_valid():
			_slide.kill()


	func is_open() -> bool:
		return visible


	func chips() -> Array:
		return _chips


	func refresh_countdown(hours_left: int) -> void:
		if hours_left >= 0:
			_countdown.visible = true
			_countdown.text = "the crackdown lands in %dh" % hours_left
		else:
			_countdown.visible = false


	func seed_focus() -> void:
		if not _chips.is_empty():
			_chips[0].grab_focus.call_deferred()


	func activate_focused() -> void:
		if not visible:
			return
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null and focus is ActionFan.ActionChip and focus.get_parent() == _content:
			_on_chip(focus)


	func _on_chip(chip: ActionFan.ActionChip) -> void:
		if bool(chip.action.get("enabled", false)):
			choice_made.emit(chip.action)
		# Choice chips never print disabled-with-reason (the model only
		# offers real, enabled verbs — the honest-card rule).


# ----------------------------------------------------------------------------
# EventQuote — a blockquote printed on the table (crackdown / crush)
# ----------------------------------------------------------------------------


## A centered paper panel printing ChronicleLine rows (ink on paper):
## the crackdown's seized/scattered accounting or the crushing beat's
## lines. Opens for a dwell, appends extend the dwell (one story), folds
## itself — never modal, never blocking.
class EventQuote:
	extends MarginContainer

	const PAD := 14.0
	const MAX_ROWS := 7

	var _rows: Array[Dictionary] = []
	var _lines: Array[Control] = []
	var _content: VBoxContainer
	var _dwell_gen := 0
	var _dwell_timer: SceneTreeTimer


	func _init() -> void:
		add_theme_constant_override("margin_left", PAD)
		add_theme_constant_override("margin_right", PAD)
		add_theme_constant_override("margin_top", PAD)
		add_theme_constant_override("margin_bottom", PAD)
		mouse_filter = Control.MOUSE_FILTER_PASS
		visible = false


	func _ready() -> void:
		_content = VBoxContainer.new()
		_content.add_theme_constant_override("separation", 4)
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_content)


	func _draw() -> void:
		## The paper quad with a DOUBLE ink border — a blockquote is the
		## chronicle's own voice at panel scale, quoted.
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Inks.PAPER)
		draw_rect(rect.grow(-2.0), Inks.INK, false, 2.0)
		draw_rect(rect.grow(-6.0), Inks.INK, false, 1.0)


	func open_rows(rows: Array[Dictionary], dwell: float) -> void:
		_rows = rows.duplicate()
		_rebuild()
		visible = true
		size = get_combined_minimum_size()
		_arm_dwell(dwell)


	## Append one row; measurement is EXACT (dying rows are detached
	## before their free — see _rebuild), but PLACEMENT belongs to the
	## layer: SuspicionEvents.append_quote_row re-places through
	## quote_rect after this, restoring the designed panel width.
	func append_row(row: Dictionary, dwell: float) -> void:
		if not visible:
			open_rows([row], dwell)
			return
		_rows.append(row)
		if _rows.size() > MAX_ROWS:
			_rows = _rows.slice(_rows.size() - MAX_ROWS)
		_rebuild()
		size = get_combined_minimum_size()
		_arm_dwell(dwell)


	func fold() -> void:
		visible = false
		_rows = []
		_rebuild()


	func is_open() -> bool:
		return visible


	func rows() -> Array[Dictionary]:
		return _rows.duplicate()


	func _rebuild() -> void:
		for line in _lines:
			# Detach BEFORE the free: a queue_free'd row stays in the tree
			# until idle and would count toward get_combined_minimum_size()
			# at append-measure time (old + new rows both measured — the
			# inflated heights of the round-2 landscape artifact).
			_content.remove_child(line)
			line.queue_free()
		_lines.clear()
		for row in _rows:
			var line: Control = preload("res://ui/theme/chronicle_line.tscn").instantiate()
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_content.add_child(line)
			line.set("line_class", int(row["class"]))
			line.set("text", String(row["text"]))
			line.set("ground", Inks.PAPER)
			_lines.append(line)


	## Arm the self-fold dwell. A GENERATION counter guards the fold: only
	## the newest timer's callback folds (an append re-arms; a re-opened
	## quote is never folded early by a stale timer). The connection is a
	## BOUND METHOD, not a lambda: SceneTreeTimers cannot be cancelled, and
	## a method Callable on a freed instance is silently invalidated — a
	## freed capture in a lambda would print into the log every time.
	func _arm_dwell(dwell: float) -> void:
		if dwell <= 0.0:
			return
		_dwell_gen += 1
		_dwell_timer = get_tree().create_timer(dwell)
		_dwell_timer.timeout.connect(_fold_if_current.bind(_dwell_gen))


	func _fold_if_current(gen: int) -> void:
		if visible and _dwell_gen == gen:
			fold()
