## AssaultStage — the ON-TABLE stage for the assault vignette (T-UI-07).
##
## The anti-goal is popup chrome (design brief §4): the assault is CARDS
## PLAYED AGAINST THE CASTLE, staged as a moment ON THE TABLE — never a
## modal overlay. This control IS that table for the duration: the same
## print-block world (CardFrame/CardFace/ChronicleLine components, the
## regime's ground, line-form state, the misprint character), relaid as a
## SIEGE LANE —
##
##   portrait  : the castle card at the head of the table, then the open
##               corridor where the battle line forms (the march runs UP
##               the table, pressing at the wall), the print-block tally
##               MID-LANE behind the line, the army ranked TALL at the
##               foot — the portrait lane has height to spend, and every
##               stretch of it is castle, field, tally, or host (no dead
##               band; finishing #4);
##   landscape : the castle on the Crown's edge (the right, where the Eye
##               perches), the army ranked to the left, the march runs
##               ACROSS the panoramic table, the tally at the head.
##
## The print-block meter is the scoreboard: pre-commit it prints the odds
## (permille -> filled blocks + readable confidence); during the beats it
## reprints BOTH sides' remaining strength, striking lost blocks through —
## watchable auto-resolution in the world's own arithmetic.
##
## THE VIGNETTE IS EVENT-DRIVEN (the §15 contract): the stage renders a
## BeatScript folded from the event stream alone. `apply_beat(i)` is PURE
## positioning data (march fractions + milli -> struck cards newest-first,
## mirroring the sim's own casualty order); motion is presentation ON TOP
## of that data, so `settled_state()` hashes the AUTHORED sequence — same
## events -> same visual sequence hash (tests pin it), and skip/reduced
## motion land the exact same states the full pacing reaches.
##
## AUDIO HOOKS (documented, no assets yet — the sound-shape contract):
## the stage itself is silent; the SCREEN owns pacing and emits
## `beat_landed` / `outcome_printed` where a future audio director lands
## hooks (march stride on advance, impact hits at skirmish/gate strikes,
## the gate crack, a resolved chord on throne, scattered drums on rout).
class_name AssaultStage
extends Control

## Beat pacing (full motion): authored per phase, the 1.5–2.5s band the
## task contracts; rescaled by MotionProfile so reduced motion collapses
## each beat to near-instant while the printed summaries carry the story.
const TABLE_GROUND := preload("res://ui/theme/table_ground.gd")

const BEAT_SECONDS: Dictionary = {
	&"advance": 2.2,
	&"skirmish": 1.8,
	&"gate": 1.8,
	&"throne": 2.4,
	&"rout": 2.4,
}

## March gap between the battle line and the castle card.
const STANDOFF_GAP := 10.0
## Layout margins.
const MARGIN := 14.0
const GAP := 10.0
## Portrait rank cards stack taller than the shared print-scale cap (the
## vertical reserve, finishing #4): a small host ranks at 168-unit cards
## instead of 132, so the foot of the portrait lane carries its weight.
const RANK_MAX_H_PORTRAIT := 168.0

## The regime under assault (tints ground + hairlines + garrison ink).
var regime_id: StringName = &"":
	set(value):
		if regime_id != value:
			regime_id = value
			_relaid()
## The regime's display name (the castle card's title).
var regime_name := "":
	set(value):
		if regime_name != value:
			regime_name = value
			_relaid()
## True when the lane runs in portrait topology.
var portrait := true:
	set(value):
		if portrait != value:
			portrait = value
			_relaid()
## 0..1 — the aftermath wash (the morning-after light on outcome; the
## screen tweens this, skip sets it outright).
var wash := 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if wash != clamped:
			wash = clamped
			queue_redraw()
			_sync_prints()

var _title_label: Label
var _meter: VBoxContainer
var _odds_label: Label
var _army_blocks: BlocksRow
var _garrison_blocks: BlocksRow
var _castle: SiegeCard
var _ranks: Array[RankCard] = []
var _lines: Array[Control] = []
var _printed: Array[Dictionary] = []
## The FULL printed record (the strip shows the newest rows; the record
## keeps the whole story — the tests' "the summaries all printed").
var _history: Array[Dictionary] = []
var _outcome_quote: Label
var _chips: HBoxContainer

## The staged script (set by begin_battle) + the commit-time roster view.
var _script := {}
var _roster: Array[Dictionary] = []
## The staged garrison's identity (L2-C): when the odds bind carried a
## captured garrison, the castle keeps the VETERANS' crest + cycle numeral
## through the whole battle — the walls do not change hands until they
## fall (apply_outcome's swap rebinds the fallen castle bare, cycle 0).
var _garrison_crest := &""  # "" = the run regime's own crest
var _garrison_cycle := 0
## Per-beat settled hashes (the authored visual sequence).
var _sequence: Array[int] = []
## Layout rects (from lane_layout, the pure statics below).
var _layout := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_compose()
	_relaid()


func _relaid() -> void:
	# Guard: NOTIFICATION_RESIZED fires DURING _compose (adding children
	# grows the minimum size) — layout only runs on a fully composed stage.
	if _title_label == null or _chips == null or _castle == null:
		return
	if not is_inside_tree() or size.x < 8.0 or size.y < 8.0:
		return
	_layout = lane_layout(portrait, size)
	_fit(_title_label, _layout["title"])
	_fit(_meter, _layout["meter"])
	_fit(_castle, _layout["castle"])
	_fit(_outcome_quote, _layout["quote"])
	var rows: Rect2 = _layout["chronicle"]
	var row_h := rows.size.y / float(maxi(1, _lines.size()))
	for i in _lines.size():
		_fit(_lines[i], Rect2(rows.position + Vector2(0, i * row_h), Vector2(rows.size.x, row_h)))
	_fit(_chips, _layout["actions"])
	_place_ranks()
	_sync_prints()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relaid()


# --- composition (all T-UI-01 components — nothing forked) ----------------------------


func _compose() -> void:
	_title_label = Label.new()
	_title_label.theme_type_variation = &"CardTitle"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.clip_text = true
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	_meter = VBoxContainer.new()
	_meter.add_theme_constant_override("separation", 3)
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_odds_label = Label.new()
	_odds_label.theme_type_variation = &"RoleLine"
	_odds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_odds_label.clip_text = true
	_odds_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.add_child(_odds_label)
	_army_blocks = BlocksRow.new()
	_army_blocks.side = &"army"
	_meter.add_child(_army_blocks)
	_garrison_blocks = BlocksRow.new()
	_garrison_blocks.side = &"garrison"
	_meter.add_child(_garrison_blocks)
	add_child(_meter)

	_castle = SiegeCard.new()
	_castle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_castle)

	_outcome_quote = Label.new()
	_outcome_quote.theme_type_variation = &"ChronicleLine"
	_outcome_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outcome_quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_quote.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outcome_quote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outcome_quote.visible = false
	add_child(_outcome_quote)

	for i in 2:
		var line: Control = preload("res://ui/theme/chronicle_line.tscn").instantiate()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lines.append(line)
		add_child(line)

	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 14)
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_chips)


# --- odds binding (pre-commit) ----------------------------------------------------------


## Bind the pre-commit odds view (AssaultPresenter.odds_view): castle
## card, ranked army cards with contribution pips, the print-block odds
## meter. The action chips are the SCREEN's (set_chips — it owns input).
func bind_odds(view: Dictionary) -> void:
	_script = {}
	_roster = view["roster"]
	_sequence.clear()
	_printed.clear()
	_history.clear()
	_bind_garrison_identity(view)
	_castle.bind(regime_name, _garrison_crest_key(),
		AssaultPresenter.garrison_line(view, regime_name),
		regime_id, Inks.EdgeForm.SOLID, false, _garrison_cycle)
	_castle.snap_home()
	for rank in _ranks:
		rank.queue_free()
	_ranks.clear()
	for entry: Dictionary in _roster:
		var rank := RankCard.new()
		add_child(rank)
		rank.bind(entry, regime_id)
		_ranks.append(rank)
	_odds_label.text = AssaultPresenter.confidence_line(int(view["win_permille"]))
	if not bool(view["floor_met"]):
		_odds_label.text += "  ·  " + AssaultPresenter.floor_line(view)
	_army_blocks.regime_ink = Inks.regime_secondary(regime_id)
	_garrison_blocks.regime_ink = Inks.regime_secondary(regime_id)
	_army_blocks.bind_odds(int(view["win_permille"]))
	_garrison_blocks.bind_odds(1000 - int(view["win_permille"]))
	_title_label.text = "THE ASSAULT"
	_outcome_quote.visible = false
	_relaid()


## Silent-drift refresh (per batch while the odds screen is open): the
## meters, confidence and floor line re-print; the ranked cards are NOT
## rebuilt (rebuild churn is bind_odds's business, on roster changes).
func refresh_odds(view: Dictionary) -> void:
	_odds_label.text = AssaultPresenter.confidence_line(int(view["win_permille"]))
	if not bool(view["floor_met"]):
		_odds_label.text += "  ·  " + AssaultPresenter.floor_line(view)
	_army_blocks.bind_odds(int(view["win_permille"]))
	_garrison_blocks.bind_odds(1000 - int(view["win_permille"]))


## The ranked army cards (the screen tweens these toward their targets).
func ranks() -> Array[RankCard]:
	return _ranks.duplicate()


func set_chips(chip_actions: Array[Dictionary]) -> void:
	for chip in _chips.get_children():
		# Detach BEFORE the free (the EventQuote._rebuild precedent): a
		# queue_free'd chip stays in the tree until idle, so a RE-open's
		# _focus_commit iterated the dying chips and deferred its grab on
		# a freed instance — the odds table reopened with NO focus and a
		# controller player was stranded (found by the T-QA-05 sweep).
		_chips.remove_child(chip)
		chip.queue_free()
	for action: Dictionary in chip_actions:
		var chip: Button = ActionFan.ActionChip.new()
		chip.action = action
		chip.custom_minimum_size = Vector2(216.0, float(Inks.TOUCH_GRIP_MIN) \
			+ (14.0 if not String(action.get("reason", "")).is_empty() else 0.0))
		_chips.add_child(chip)
	_wire_chip_focus()


## The stage's chips in print order (focus wiring + tests).
func chips() -> Array:
	return _chips.get_children()


func _wire_chip_focus() -> void:
	## The pad trap: cyclic neighbors, no dead ends (the fan's own rule).
	var list := chips()
	var count := list.size()
	if count == 0:
		return
	for i in count:
		var chip: Control = list[i]
		var prev: Control = list[wrapi(i - 1, 0, count)]
		var next: Control = list[wrapi(i + 1, 0, count)]
		chip.focus_neighbor_left = chip.get_path_to(prev)
		chip.focus_neighbor_top = chip.get_path_to(prev)
		chip.focus_neighbor_right = chip.get_path_to(next)
		chip.focus_neighbor_bottom = chip.get_path_to(next)
		chip.focus_previous = chip.get_path_to(prev)
		chip.focus_next = chip.get_path_to(next)


# --- the battle (event-driven; the §15 replay contract) ----------------------------------


## Arm the stage from a folded BeatScript + the commit-time roster (whose
## per-unit totals turn milli attrition into struck CARDS, newest-first —
## the sim's own casualty order). No beat is applied here.
func begin_battle(script: Dictionary, roster: Array[Dictionary]) -> void:
	_script = script
	_roster = roster
	_sequence.clear()
	_printed.clear()
	_history.clear()
	_castle.bind(regime_name, _garrison_crest_key(), _castle.role_line,
		regime_id, Inks.EdgeForm.SOLID, false, _garrison_cycle)
	_castle.snap_home()
	# The ranks build from the COMMIT-TIME ROSTER alone (not from whatever
	# the odds screen left): (script, roster) is the whole staging input —
	# a cold stage replays identically to a live one.
	for rank in _ranks:
		rank.queue_free()
	_ranks.clear()
	for entry: Dictionary in _roster:
		var rank := RankCard.new()
		add_child(rank)
		rank.bind(entry, regime_id)
		_ranks.append(rank)
	_relaid()
	var beats: Array = _script["beats"]
	var initial_garrison := int((beats[0] as Dictionary)["garrison_milli"]) if not beats.is_empty() else 0
	_army_blocks.bind_strength(int(_script["initial_army_milli"]), int(_script["initial_army_milli"]))
	_garrison_blocks.bind_strength(initial_garrison, initial_garrison)
	_title_label.text = "THE STORM"


## Apply one beat's SETTLED state (pure data -> authored positions): the
## phase's march fraction, milli attrition -> cards struck NEWEST-FIRST
## (the sim's apply_army_losses order; the last beat lands exactly on the
## true survivors), garrison -> the castle's edge form, meters reprinted.
## Motion (the tween toward these targets) is presentation;
## settled_state() reads the targets, so skip and reduced motion land
## exactly here. Returns the beat's dictionary.
func apply_beat(beat_index: int) -> Dictionary:
	var beats: Array = _script["beats"]
	if beat_index < 0 or beat_index >= beats.size():
		return {}
	var beat: Dictionary = beats[beat_index]
	var fraction := BeatScript.march_fraction(beat["phase"])
	var fallen_through := _fallen_through(beat_index)
	_beat_targets(fraction)
	for i in _ranks.size():
		var rank := _ranks[i]
		if rank.struck:
			continue  # the fallen stay where they fell
		if i >= _ranks.size() - fallen_through:
			rank.struck = true  # line form carries the casualty — never hue
	_apply_castle_form(beat["phase"])
	_army_blocks.bind_strength(int(beat["army_milli"]), int(_script["initial_army_milli"]))
	_garrison_blocks.bind_strength(int(beat["garrison_milli"]), int((beats[0] as Dictionary)["garrison_milli"]))
	_sequence.append(settled_hash())
	return beat


## Apply the outcome's settled state: the castle's fate — STRUCK edge +
## the flip to the fallen plate (the revolution's seal stamped) on win;
## held SOLID on loss. `instant` lands the fall without the authored
## turn (skip path; reduced motion runs it synchronously anyway).
func apply_outcome(instant := false) -> void:
	if _script["outcome"] == &"win":
		var swap := func() -> void:
			_castle.bind("THE CASTLE FALLS", _crest_key(), "the seal of the new hand",
				regime_id, Inks.EdgeForm.STRUCK, true)
		if instant:
			_castle.snap_fall(swap)
		else:
			_castle.play_fall(swap)
	else:
		_castle.set_form(Inks.EdgeForm.SOLID)  # the castle held
	_sequence.append(settled_hash())


## Snap every rank card onto its authored target (skip / relayout guard).
func snap_ranks() -> void:
	for rank in _ranks:
		rank.snap()


## Record the outcome row into the sequence oracle (after the wash).
func seal_sequence() -> void:
	_sequence.append(settled_hash())


## The authored sequence hashes so far (per settled beat + outcome).
func sequence_hashes() -> Array[int]:
	return _sequence.duplicate()


## Settled visual state as data: castle form + fallen flag, per-rank
## {uid, struck, target}, meter blocks, wash. Pure read off targets —
## tween jitter never enters the oracle.
func settled_state() -> Dictionary:
	var ranks := []
	for rank in _ranks:
		ranks.append({
			"uid": rank.uid,
			"struck": rank.struck,
			"x": int(round(rank.target.x)),
			"y": int(round(rank.target.y)),
		})
	return {
		"castle_form": _castle.edge_form,
		"castle_fallen": _castle.fallen,
		"ranks": ranks,
		"army_blocks": _army_blocks.filled,
		"garrison_blocks": _garrison_blocks.filled,
		"wash": int(round(wash * 100.0)),
	}


func settled_hash() -> int:
	var h := 0x811C9DC5
	var state := settled_state()
	h = _mix(h, int(state["castle_form"]))
	h = _mix(h, int(state["castle_fallen"]))
	h = _mix(h, int(state["army_blocks"]))
	h = _mix(h, int(state["garrison_blocks"]))
	h = _mix(h, int(state["wash"]))
	for rank: Dictionary in state["ranks"]:
		h = _mix(h, int(rank["uid"]))
		h = _mix(h, int(rank["struck"]))
		h = _mix(h, int(rank["x"]))
		h = _mix(h, int(rank["y"]))
	return h


# --- printing --------------------------------------------------------------------------


## Print one row on the stage's chronicle strip (rolling, newest first).
func print_line(line_class: int, text: String) -> void:
	var row := {"class": line_class, "text": text}
	_printed.append(row)
	_history.append(row)
	if _printed.size() > _lines.size():
		_printed = _printed.slice(_printed.size() - _lines.size())
	_render_lines()
	_sync_prints()


## Print the outcome BLOCKQUOTE — the wide print the strip never carries
## (the loss lands as the chronicle's own record of the rout; the win as
## the victory double rule). The screen owns the outcome SEQUENCE — under
## L2-C the victory prints its CAPTURE BEAT through print_line just before
## this, so the capture line stays visible beside the seal row.
func print_outcome(text: String, victory: bool) -> void:
	_outcome_quote.text = text
	_outcome_quote.visible = true
	if victory:
		var row := {"class": Inks.LineClass.VICTORY, "text": "The seal changes hands."}
		_printed.append(row)
		_history.append(row)
		if _printed.size() > _lines.size():
			_printed = _printed.slice(_printed.size() - _lines.size())
		_render_lines()
	_sync_prints()


## The FULL printed record so far (tests pin the whole printed story).
func printed_lines() -> Array[Dictionary]:
	return _history.duplicate()


func _render_lines() -> void:
	for i in _lines.size():
		if i < _printed.size():
			var row: Dictionary = _printed[_printed.size() - 1 - i]
			_lines[i].set("line_class", int(row["class"]))
			_lines[i].set("text", String(row["text"]))
		else:
			_lines[i].set("text", "")


## Ink choices follow the print rule for the CURRENT ground (the wash
## changes the stock; every print re-inks).
func _sync_prints() -> void:
	if _title_label == null:
		return
	var ground := ground_color()
	var ink := Inks.ground_text_ink(ground)
	_title_label.add_theme_color_override("font_color", ink)
	_odds_label.add_theme_color_override("font_color", ink)
	_outcome_quote.add_theme_color_override("font_color", ink)
	for line in _lines:
		line.set("ground", ground)
	_army_blocks.ground = ground
	_garrison_blocks.ground = ground


func ground_color() -> Color:
	var ready := Inks.ground_for(regime_id, Inks.Phase.READY)
	var aftermath := Inks.ground_for(regime_id, Inks.Phase.AFTERMATH)
	return ready.lerp(aftermath, wash)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ground_color())
	# The paper grain, the same whisper TableGround prints — ONE tiled
	# draw off the shared baked tile (the T-PERF-02 find: this per-circle
	# grid was ~1,250 draw calls per frame under the storm, measured as
	# the vignette state's dominant cost). The wash drifts the grid's
	# offset exactly as the integer-jitter form did.
	var tile: Texture2D = TABLE_GROUND.dot_tile_for(int(round(wash * 26.0)) % 26)  # shared baked grain
	var offset := Vector2.ONE * (float(int(round(wash * 26.0)) % 26) - 26.0)
	draw_texture_rect(tile, Rect2(offset, size - 2.0 * offset), true, Color(1, 1, 1, 1))


# --- internals --------------------------------------------------------------------------


func _crest_key() -> StringName:
	for regime: RegimeDef in Inks.pack().regimes:
		if regime.id == regime_id:
			return regime.crest_id
	return &""


## Remember whose crest + which cycle the odds bind staged (L2-C): the
## captured garrison's own crest when escalation stands, else the run
## regime's (the pre-L2 castle, unchanged). Read back by every battle-path
## castle bind until the walls fall.
func _bind_garrison_identity(view: Dictionary) -> void:
	if String(view.get("garrison_source", "")) == "escalation":
		_garrison_crest = StringName(String(view.get("garrison_crest_id", "")))
		_garrison_cycle = int(view.get("garrison_cycle", 0))
	else:
		_garrison_crest = &""
		_garrison_cycle = 0


func _garrison_crest_key() -> StringName:
	return _garrison_crest if _garrison_crest != &"" else _crest_key()


## Cards fallen through beat `beat_index` (inclusive): the milli
## attrition mapped onto the commit-time roster NEWEST-FIRST (the sim's
## own apply_army_losses order), so the final beat lands exactly on the
## true survivor count the roster holds. On the WIN path the beats
## narrate attrition but the roster is TERMINAL at victory (§15: no
## losses applied) — cards track ROSTER truth (the casualties event),
## the meter tracks the narration's arithmetic, so no card ever prints
## struck for a unit the table still holds.
func _fallen_through(beat_index: int) -> int:
	if _script.get("outcome", &"") == &"win":
		return 0
	var beats: Array = _script["beats"]
	if _roster.is_empty() or beats.is_empty() or beat_index >= beats.size():
		return 0
	var initial_milli := int(_script["initial_army_milli"])
	if initial_milli <= 0:
		return 0
	var total_power := _total_roster_power()
	var share := clampf(
		float((beats[beat_index] as Dictionary)["army_milli"]) / float(initial_milli), 0.0, 1.0)
	var kept := 0
	var kept_power := 0
	for i in _roster.size():  # survivors accumulate oldest-first
		var power := int(_roster[i]["total"])
		if kept_power + power <= int(round(share * float(total_power))) + 0:
			kept_power += power
			kept += 1
		else:
			break
	return maxi(0, _roster.size() - kept)


func _total_roster_power() -> int:
	var total := 0
	for entry: Dictionary in _roster:
		total += int(entry["total"])
	return maxi(1, total)


func _apply_castle_form(phase: StringName) -> void:
	match phase:
		&"gate":
			_castle.set_form(Inks.EdgeForm.DASHED)  # breached — in progress
		&"throne":
			_castle.set_form(Inks.EdgeForm.STRUCK)
		&"rout":
			_castle.set_form(Inks.EdgeForm.SOLID)  # the castle held


## The battle line's staging band — where the march lands. Portrait: the
## CORRIDOR the lane reserves between the castle and the mid-lane tally
## (the open field below the walls — `line` in lane_layout). Landscape:
## the slice of the army band NEAREST the castle (the Crown's edge). The
## march's authored targets are a FORMATION in this band (its own fitted
## grid, cards pressing at the wall), so settled beats never stack cards
## into an overlapping clump: the line is a rank, not a fan.
func _line_band() -> Rect2:
	return _layout["line"]


## Author every rank's target for a march fraction: home seat lerped
## toward its line-formation seat, home size lerped toward the line's
## (smaller) fitted size — the depth cue of cards pressing at the wall.
func _beat_targets(fraction: float) -> void:
	if _layout.is_empty() or _ranks.is_empty():
		return
	var line := _line_band()
	var line_seats := army_seats(line, _ranks.size())
	var line_size := army_card_size(line, _ranks.size())
	for i in _ranks.size():
		var rank := _ranks[i]
		if rank.struck:
			continue  # the fallen stay where they fell
		rank.target = rank.seat.lerp(line_seats[i], clampf(fraction, 0.0, 1.0))
		rank.target_size = rank.home_size.lerp(line_size, clampf(fraction, 0.0, 1.0))


func _place_ranks() -> void:
	if _layout.is_empty() or _ranks.is_empty():
		return
	# Portrait ranks stack taller (the vertical reserve, finishing #4); the
	# landscape band keeps the shared print-scale cap — same value as the
	# statics' default, so landscape rects stay bit-identical.
	var rank_max := RANK_MAX_H_PORTRAIT if portrait else 132.0
	var seats := army_seats(_layout["army"], _ranks.size(), rank_max)
	var card_size := army_card_size(_layout["army"], _ranks.size(), rank_max)
	for i in _ranks.size():
		var rank := _ranks[i]
		rank.seat = seats[i]
		rank.home_size = card_size
		if _script.is_empty() or _sequence.is_empty():
			# No beat applied yet (odds screen, or the battle armed but
			# not begun): the ranks stand at their seats.
			rank.target = seats[i]
			rank.target_size = card_size
		else:
			# Mid-battle relayout: re-derive the target at the CURRENT
			# beat's fraction so an orientation swap never strands a card.
			var beats: Array = _script["beats"]
			var played := mini(_sequence.size(), beats.size()) - 1
			var phase: StringName = (beats[played] as Dictionary)["phase"] if played >= 0 else &"advance"
			_beat_targets(BeatScript.march_fraction(phase))
			break
	rank_snap_all()


func rank_snap_all() -> void:
	for rank in _ranks:
		rank.snap()


func _fit(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF


# --- pure layout statics (test-pinned) ---------------------------------------------------
#
# The siege lane as pure rect math. Portrait: title at the head, then the
# castle, the open corridor where the battle line forms, the tally
# MID-LANE, the army band at the foot (the vertical reserve spent —
# finishing #4: the old head-meter layout left a ~30% dead band at small
# rosters). Landscape: the tally at the head, the castle at the far end,
# the army band between the tally and the chronicle/actions foot. Same
# bounds -> same rects (the deterministic render contract every screen in
# this codebase keeps).


static func lane_layout(p_portrait: bool, bounds: Vector2) -> Dictionary:
	var m := MARGIN
	var gap := GAP
	var wide := maxf(0.0, bounds.x - 2.0 * m)
	var title := Rect2(Vector2(m, m + 2.0), Vector2(wide, 46.0))
	var actions := Rect2(Vector2(m, bounds.y - m - float(Inks.TOUCH_GRIP_MIN) - 12.0),
		Vector2(wide, float(Inks.TOUCH_GRIP_MIN) + 12.0))
	var chronicle := Rect2(
		actions.position - Vector2(0, 2.0 * float(Inks.TOUCH_GRIP_MIN) + gap + 4.0),
		Vector2(wide, 2.0 * float(Inks.TOUCH_GRIP_MIN)))
	var quote := Rect2(
		chronicle.position - Vector2(0, 92.0 + gap),
		Vector2(wide, 92.0))
	var lane_bottom := quote.position.y - gap
	if p_portrait:
		var lane_top := title.end.y + gap
		var lane_height := maxf(120.0, lane_bottom - lane_top)
		var castle_w := clampf(wide * 0.34, 120.0, 208.0)
		var castle_h := clampf(lane_height * 0.5, 120.0, castle_w * 1.3)
		var castle := Rect2(
			Vector2(m + (wide - castle_w) * 0.5, lane_top),
			Vector2(castle_w, castle_h))
		# The corridor (the battle line's reserved field, STANDOFF_GAP off
		# the walls): proportional to the lane, never crowding out the
		# tally or the host's minimum band when the lane runs short.
		var line_w := clampf(castle_w * 1.6, 150.0, wide)
		var corridor_h := clampf(lane_height * 0.15, 104.0, 150.0)
		corridor_h = clampf(corridor_h, 0.0,
			maxf(0.0, lane_height - castle_h - 3.0 * gap - 86.0 - 96.0))
		var line := Rect2(
			Vector2(castle.get_center().x - line_w * 0.5, castle.end.y + gap),
			Vector2(line_w, corridor_h))
		# The tally MID-LANE: behind the line it counts the fight; on the
		# odds screen the measure of the contest prints BETWEEN the castle
		# and the host.
		var meter := Rect2(Vector2(m, line.end.y + gap), Vector2(wide, 86.0))
		var army := Rect2(
			Vector2(m, meter.end.y + gap),
			Vector2(wide, maxf(96.0, lane_bottom - meter.end.y - gap)))
		return {
			"title": title, "meter": meter, "castle": castle, "army": army,
			"line": line, "chronicle": chronicle, "quote": quote, "actions": actions,
		}
	var meter := Rect2(title.position + Vector2(0, title.size.y + gap), Vector2(wide, 86.0))
	var lane_top := meter.end.y + gap
	var lane_height := maxf(120.0, lane_bottom - lane_top)
	var castle_size := Vector2(clampf(wide * 0.22, 150.0, 210.0), clampf(lane_height, 140.0, 272.0))
	var castle_l := Rect2(
		Vector2(bounds.x - m - castle_size.x, lane_top + (lane_height - castle_size.y) * 0.5),
		castle_size)
	var army_l := Rect2(
		Vector2(m, lane_top),
		Vector2(maxf(96.0, castle_l.position.x - m - gap * 2.0), lane_height))
	var line_w := clampf(army_l.size.x * 0.34, 120.0, 280.0)
	return {
		"title": title, "meter": meter, "castle": castle_l, "army": army_l,
		"line": Rect2(Vector2(army_l.end.x - line_w, army_l.position.y), Vector2(line_w, army_l.size.y)),
		"chronicle": chronicle, "quote": quote, "actions": actions,
	}


## The fitted rank grid: the LARGEST card height (scanned down from the
## print-scale cap to the readability floor) whose cols x rows grid
## actually FITS the band on both axes. Area heuristics quantize badly
## (a width-derived column count can overflow height); the scan
## guarantees no settled formation ever overlaps or spills. Deterministic
## in (band, count) alone.
static func _fit_grid(band: Rect2, count: int, min_h := 56.0, max_h := 132.0) -> Dictionary:
	const ASPECT := 0.78
	if count <= 0:
		return {"size": Vector2(96.0, 120.0), "cols": 1}
	var height := max_h
	while height >= min_h:
		var width := height * ASPECT
		var cols := maxi(1, int((band.size.x + GAP) / (width + GAP)))
		var rows := ceili(float(count) / float(cols))
		if float(rows) * height + float(rows - 1) * GAP <= band.size.y + 0.5 \
				and float(cols) * width + float(cols - 1) * GAP <= band.size.x + 0.5:
			return {"size": Vector2(width, height), "cols": cols}
		height -= 2.0
	var cols := maxi(1, int((band.size.x + GAP) / (min_h * ASPECT + GAP)))
	return {"size": Vector2(min_h * ASPECT, min_h), "cols": cols}


## Uniform card size for a ranked band (the fitted grid's card). `max_h`
## raises the cap for the portrait home band (the vertical reserve); the
## default is the shared print-scale cap, so existing calls are unchanged.
static func army_card_size(band: Rect2, count: int, max_h := 132.0) -> Vector2:
	return _fit_grid(band, count, 56.0, max_h)["size"]


## Grid seats for the ranked band (row-major, centered) — deterministic
## in (band, count) alone.
static func army_seats(band: Rect2, count: int, max_h := 132.0) -> Array[Vector2]:
	var seats: Array[Vector2] = []
	if count <= 0:
		return seats
	var fit: Dictionary = _fit_grid(band, count, 56.0, max_h)
	var card: Vector2 = fit["size"]
	var cols := int(fit["cols"])
	var rows := ceili(float(count) / float(cols))
	var grid_w := float(cols) * card.x + float(cols - 1) * GAP
	var grid_h := float(rows) * card.y + float(rows - 1) * GAP
	var origin := band.position + Vector2(
		(band.size.x - grid_w) * 0.5, (band.size.y - grid_h) * 0.5)
	for i in count:
		var col := i % cols
		var row := i / cols
		seats.append(origin + Vector2(
			float(col) * (card.x + GAP), float(row) * (card.y + GAP)))
	return seats


# --- components ---------------------------------------------------------------------------


## BlocksRow — one side of the print-block meter: a row of printed blocks
## whose FILLED share carries the number (remaining strength, or the odds
## share pre-commit), struck-through where strength was lost. Line-form
## grammar at meter scale; color is redundant tertiary.
class BlocksRow:
	extends Control

	## Which side this row prints (label prefix).
	var side: StringName = &"army"
	## Current filled blocks (0..total).
	var filled := 0
	## Total blocks in the row.
	var total := AssaultPresenter.METER_BLOCKS
	## The regime's second ink (the garrison row prints in it).
	var regime_ink := Inks.INK
	## Ground beneath (the row's label ink follows the print rule).
	var ground := Inks.NEUTRAL_GROUND

	const BLOCK_W := 13.0
	const BLOCK_H := 17.0
	const BLOCK_GAP := 5.0
	const LABEL_W := 74.0


	func _ready() -> void:
		custom_minimum_size = Vector2(
			LABEL_W + float(total) * (BLOCK_W + BLOCK_GAP), 30.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE


	func bind_odds(permille: int) -> void:
		filled = AssaultPresenter.meter_blocks(permille)
		queue_redraw()


	func bind_strength(current_milli: int, initial_milli: int) -> void:
		var share := clampf(float(current_milli) / float(maxi(1, initial_milli)), 0.0, 1.0)
		filled = int(round(share * float(total)))
		queue_redraw()


	func _draw() -> void:
		var ink := Inks.ground_text_ink(ground)
		var side_ink: Color = Inks.ground_accent_ink(ground) if side == &"army" else regime_ink
		draw_string(ThemeDB.fallback_font, Vector2(2.0, size.y * 0.5 + 5.0),
			String(side).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, 12, ink)
		# Blocks run directly from the label (a printed table row, no
		# orphaned label): filled = strength held, thin outline = spent.
		var x := LABEL_W + 2.0
		var y := (size.y - BLOCK_H) * 0.5
		for i in total:
			var rect := Rect2(Vector2(x, y), Vector2(BLOCK_W, BLOCK_H))
			if i < filled:
				draw_rect(rect, side_ink)
			else:
				draw_rect(rect, Color(ink, 0.45), false, 1.5)
			x += BLOCK_W + BLOCK_GAP


## RankCard — one army card on the march: a CardFrame (state by line
## form, regime hairline, misprint) with a name plate, a contribution
## line, and the per-unit CONTRIBUTION PIPS (solid ink = sworn power, red
## = gear power) — the odds panel's "where does my power come from".
class RankCard:
	extends Control

	var uid := 0
	var struck := false:
		set(value):
			if struck != value:
				struck = value
				if _frame != null:
					_frame.set("edge_form", Inks.EdgeForm.STRUCK if value else Inks.EdgeForm.SOLID)
	var seat := Vector2.ZERO
	var home_size := Vector2(96.0, 120.0)
	var target := Vector2.ZERO
	var target_size := Vector2(96.0, 120.0)

	var _frame: Control


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


	func _ready() -> void:
		_frame = preload("res://ui/theme/card_frame.tscn").instantiate()
		_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame.set("show_seal", true)
		_frame.focus_mode = Control.FOCUS_NONE
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_frame)
		var inset := MarginContainer.new()
		inset.set_anchors_preset(Control.PRESET_FULL_RECT)
		inset.offset_left = 9.0
		inset.offset_top = 9.0
		inset.offset_right = -9.0
		inset.offset_bottom = -7.0
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(inset)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 1)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(column)
		var name_label := Label.new()
		name_label.theme_type_variation = &"RoleLine"
		name_label.add_theme_font_size_override("font_size", TypeScale.scaled(14))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.name = &"NamePlate"
		name_label.resized.connect(_refit_plates)
		column.add_child(name_label)
		var role_label := Label.new()
		role_label.theme_type_variation = &"PipLabel"
		role_label.add_theme_font_size_override("font_size", TypeScale.scaled(11))
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role_label.clip_text = true
		role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		role_label.name = &"RolePlate"
		role_label.resized.connect(_refit_plates)
		column.add_child(role_label)
		var pips := ContributionPips.new()
		pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pips.size_flags_vertical = Control.SIZE_SHRINK_END
		pips.name = &"Pips"
		column.add_child(pips)


	func bind(entry: Dictionary, p_regime_id: StringName) -> void:
		uid = int(entry["uid"])
		struck = false
		_frame.set("regime_id", p_regime_id)
		_frame.set("misprint_seed", int(entry["uid"]))
		_frame.set("edge_form", Inks.EdgeForm.SOLID)
		var name_plate := _plate(&"NamePlate") as Label
		var role_plate := _plate(&"RolePlate") as Label
		if name_plate != null:
			name_plate.text = String(entry["name"])
		if role_plate != null:
			role_plate.text = AssaultPresenter.contribution_line(entry)
		# The plate fit (the card grammar's shared pass): the plates step
		# their local TypeScale sizes down to the card's width before the
		# T-UI-03 clip fail-safe ever engages. Text changes refit directly;
		# width changes arrive through the plates' `resized`.
		_refit_plates()
		var pips := _plate(&"Pips") as ContributionPips
		if pips != null:
			pips.bind(int(entry["def_power"]), int(entry["gear_power"]))


	## The rank plates' fit (see CardFace.fit_label_to_width — same grammar,
	## locally baked sizes). Guarded by text+width so the fit's own min-size
	## ripple cannot ping-pong the relayout.
	var _fit_key := ""

	func _refit_plates() -> void:
		var name_plate := _plate(&"NamePlate") as Label
		var role_plate := _plate(&"RolePlate") as Label
		if name_plate == null or role_plate == null:
			return
		var key := "%s|%s@%.1f" % [name_plate.text, role_plate.text, size.x]
		if key == _fit_key:
			return
		_fit_key = key
		CardFace.fit_label_to_width(name_plate, 0.7, 2, TypeScale.scaled(14))
		CardFace.fit_label_to_width(role_plate, 0.75, 1, TypeScale.scaled(11))


	## Land on the authored target right now (the CardMotion rule: a
	## re-laid table never strands a card short of its seat).
	func snap() -> void:
		position = target
		size = target_size


	func _plate(plate_name: StringName) -> Node:
		for child in _frame.get_children():
			if child is MarginContainer:
				for column in child.get_children():
					if column is VBoxContainer:
						for node in column.get_children():
							if node.name == plate_name:
								return node
		return null


## ContributionPips — the per-unit odds panel: one solid ink pip per
## point of sworn power, one red pip per point of gear power (the tier
## refits a player spent iron on, made visible where it counts). The pip
## size ADAPTS to the card's width (a t3 refit's many pips shrink, they
## never overflow the card's edge).
class ContributionPips:
	extends Control

	var _def_power := 0
	var _gear_power := 0

	const PIP_MAX := 7.0
	const PIP_MIN := 3.0
	const PIP_GAP := 2.0


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(8.0, PIP_MAX + 2.0)


	func bind(def_power: int, gear_power: int) -> void:
		_def_power = def_power
		_gear_power = gear_power
		queue_redraw()


	func _pip_size() -> float:
		var count := _def_power + _gear_power
		if count <= 0:
			return PIP_MAX
		var fitted := (size.x - 4.0) / float(count) - PIP_GAP
		return clampf(fitted, PIP_MIN, PIP_MAX)


	func _draw() -> void:
		var pip := _pip_size()
		var x := 2.0
		var y := size.y * 0.5 - pip * 0.5
		for i in _def_power:
			draw_rect(Rect2(Vector2(x, y), Vector2(pip, pip)), Inks.INK)
			x += pip + PIP_GAP
		for i in _gear_power:
			draw_rect(Rect2(Vector2(x, y), Vector2(pip, pip)), Inks.RED)
			x += pip + PIP_GAP


## SiegeCard — the castle: the regime's own face card on the table (crest
## art slot, garrison composition line, regime hairline; NO red seal —
## the seal is the revolution's stamp and lands only when it FALLS). Under
## L2 a CAPTURED garrison re-faces it: the veterans' crest in the slot, the
## escalation garrison line on the plate, and the CYCLE NUMERAL at the
## crest corner (top-right — mirroring the revolution's seal corner; the
## ladder's count, in the world's numeral grammar). The fall plays the
## CardFrame flip seam — the world's one card turn, the promotion flip's
## rhyme at payoff scale — and drops the numeral (the walls changed hands).
class SiegeCard:
	extends Control

	var fallen := false
	var edge_form: int = Inks.EdgeForm.SOLID
	var role_line := ""
	## The escalation cycle the staged garrison opens (0 = no numeral — the
	## static castle, or the fallen one).
	var cycle := 0

	var _frame: Control
	var _face: BoxContainer
	var _cycle_plate: Control


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


	func _ready() -> void:
		_frame = preload("res://ui/theme/card_frame.tscn").instantiate()
		_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame.set("show_seal", false)
		_frame.focus_mode = Control.FOCUS_NONE
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_frame)
		var inset := MarginContainer.new()
		inset.set_anchors_preset(Control.PRESET_FULL_RECT)
		inset.offset_left = 12.0
		inset.offset_top = 12.0
		inset.offset_right = -12.0
		inset.offset_bottom = -12.0
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(inset)
		_face = preload("res://ui/theme/card_face.tscn").instantiate() as BoxContainer
		_face.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_face.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inset.add_child(_face)
		# The cycle numeral plate rides ABOVE the frame (the world's corner
		# mark grammar; see CyclePlate) — placed at the crest corner on
		# every resize + bind, deterministic in size alone.
		_cycle_plate = CyclePlate.new()
		add_child(_cycle_plate)
		_place_cycle_plate()
		# The castle's title plate prints one size down: full display
		# scale clips regime names at card width ("he Paper Crow" — the
		# capture find), and a clipped name on the castle reads broken.
		for plate in _face.get_children():
			if plate is Label and (plate as Label).theme_type_variation == &"CardTitle":
				(plate as Label).add_theme_font_size_override("font_size", TypeScale.scaled(22))


	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_place_cycle_plate()


	func _place_cycle_plate() -> void:
		if _cycle_plate == null:
			return
		var plate_size := Vector2(30.0, 22.0)
		_cycle_plate.size = plate_size
		_cycle_plate.position = Vector2(size.x - 13.0 - plate_size.x, 13.0)


	func bind(title: String, crest_key: StringName, p_role_line: String,
			p_regime_id: StringName, form: int, stamp_seal: bool,
			p_cycle := 0) -> void:
		edge_form = form
		fallen = stamp_seal
		role_line = p_role_line
		cycle = p_cycle
		_frame.set("edge_form", form)
		_frame.set("regime_id", p_regime_id)
		_frame.set("show_seal", stamp_seal)
		_face.set("card_name", title)
		_face.set("role_line", _wrapped_role())
		_face.set("face_key", crest_key)
		if _cycle_plate != null:
			_cycle_plate.set("value", 0 if fallen else cycle)


	func _wrapped_role() -> String:
		## The garrison line wraps to two plates at card scale (long
		## regime names must never widen the card past the table edge).
		if role_line.length() <= 26:
			return role_line
		var cut := role_line.rfind(" ", 26)
		if cut <= 0:
			return role_line
		return "%s\n%s" % [role_line.substr(0, cut), role_line.substr(cut + 1)]


	func set_form(form: int) -> void:
		edge_form = form
		_frame.set("edge_form", form)


	func snap_home() -> void:
		_frame.scale = Vector2.ONE
		edge_form = Inks.EdgeForm.SOLID
		fallen = false


	## The authored fall: the world's one card turn on the frame seam.
	func play_fall(swap: Callable) -> void:
		fallen = true
		_frame.play_promotion_flip(swap)


	## The skip path: the plates swap and the card lands, no turn.
	func snap_fall(swap: Callable) -> void:
		fallen = true
		swap.call()
		_frame.scale = Vector2.ONE


## CyclePlate — the escalation cycle's numeral at the castle card's crest
## corner (L2-C): a small paper quad with an ink outline and the numeral in
## the Numerals face — the ladder's count in the world's own numeral
## grammar (the armed Eye's countdown plate family). Line-form consistent:
## a printed plate carrying a NUMBER, never a hue; hidden when value is 0
## (the static castle) or when the walls fall.
class CyclePlate:
	extends Control

	var value := 0:
		set(new_value):
			if value == new_value:
				return
			value = new_value
			_sync_label()
			queue_redraw()

	var _label: Label

	const PLATE_SIZE := Vector2(30.0, 22.0)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = PLATE_SIZE

	func _ready() -> void:
		_label = Label.new()
		_label.theme_type_variation = &"Numerals"
		_label.add_theme_font_size_override("font_size", TypeScale.scaled(15))
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		_sync_label()

	func _sync_label() -> void:
		visible = value > 0
		if _label != null:
			# The baked size re-applies on every value change — the
			# press-room's live type-scale step re-flows a card composed at
			# another factor the next time the numeral reprints.
			_label.add_theme_font_size_override("font_size", TypeScale.scaled(15))
			_label.text = str(value)

	func _draw() -> void:
		if value <= 0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Inks.PAPER)
		draw_rect(rect.grow(-1.0), Inks.INK, false, 1.5)
