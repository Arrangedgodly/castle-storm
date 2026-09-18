## RunHeader — the run's letterhead printed above the table (T-UI-03).
##
## Leader name (display face) + a rule in the regime's second ink + regime
## name + run clock: the identity strip of the current hand. Data-driven
## end to end — a restart rebinds it from the view model; a regime swap
## recolors the rule by content (Inks.regime_secondary), never by code.
## Chrome, not a control: nothing here is interactive, so it carries no
## focus (grips apply to interactive targets only).
##
## THE ESCALATION MARK (L2-C): when a captured garrison stands in the meta
## (the walls are the player's own old army), the letterhead carries a
## subtle CYCLE NUMERAL at the row's crest corner — a short double rule
## (the victory line-form; every cycle is a wall taken) + the numeral in
## the Numerals face, ink by the print rule. It is the ONLY escalation
## chrome the Spread gains: the escalation is ODDS-side pressure, and the
## Watchful Eye's meter stays the conspiracy's own story. No snapshot: the
## mark is hidden and the row's layout is the pre-L2 letterhead exactly
## (the containers skip hidden children — nothing shifts).
##
## THE LINE BUDGET (finishing refinement #6, the closing critique's caveat):
## the letterhead prints on one row at the table's full width, and the name
## WRAPS at word boundaries when the pools deal a long name (the epithet
## drops to its own line — a letterhead's own move, and the same wrap every
## other print surface in this world already uses; the old clip-at-the-plate
## fail-safe cut names like "…the Heavily Record" mid-word at 1.0x, and at
## 1.3x even mid-length names). The regime and clock plates never clip:
## their minimums fit their own measured text (a plate grows, its print
## stays whole — "THE GILDED CROWN" measured 209px on a 195px plate at
## 1.3x). The strip's minimum width never exceeds the table: the name's
## minimum is its granted plate (the refit below), never the unwrapped name.
extends HBoxContainer

const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")

## The plates' base minimums (design units at 1.0x; grown by the type
## factor AND by their own measured text — whichever is wider). The pad
## is a hair of air inside each plate (the HBox's own 14-unit separation
## is the gap between plates); 6 keeps even the widest single word
## ("Bartholomew" at 1.3x measures 242px) inside the name's plate at the
## 720 portrait strip.
const REGIME_PLATE_BASE := 150.0
const TIME_PLATE_BASE := 96.0
const PLATE_PAD := 6.0
## The HBox's plate separation (kept in sync with _ready's override).
const PLATE_SEPARATION := 14.0

var _name_plate: Control
var _name_label: Label
var _rule: Control
var _regime_plate: Control
var _regime_label: Label
var _time_plate: Control
var _time_label: Label
var _cycle_mark: Control


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# FINISHING #6 (re-dispatch): the name prints on a PLATE — a plain
	# Control wrapper whose custom_minimum_size the refit below owns —
	# with the Label full-rect inside it, unclipped. Two findings meet
	# here. (1) RENDER: in Godot 4.7 an autowrap Label with clip_text
	# draws ONLY its first line (the label's draw loop bounds itself at
	# one visible line while get_line_count() reports 2/3 — the wrapped
	# epithet vanished from the letterhead at 1.0x AND 1.3x while every
	# font-metric probe stayed green; the verifier's pixel audit caught
	# it, pinned at render level by the letterhead test's visible-line
	# assertion), so the name label must NOT clip. (2) DETERMINISM: an
	# unclipped label's OWN minimum carries its asynchronously-shaped
	# height, which lags the width a resize just granted (the layout-hash
	# pin caught the layout settling at a stale-moment header height that
	# only a full refresh corrected). A plain Control ignores its
	# children's minimums, so the plate makes the EXPLICIT refit the one
	# authority on the row's size — a pure function of text + type factor
	# + strip width — while the label inside renders every wrapped line.
	_name_plate = Control.new()
	_name_plate.custom_minimum_size = Vector2(160, 0)
	_name_plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.theme_type_variation = &"CardTitle"
	_name_label.add_theme_font_size_override("font_size", TypeScale.scaled(28))  # the letterhead fits long names at table width
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_plate.add_child(_name_label)
	add_child(_name_plate)
	_rule = RULE_SCENE.instantiate()
	_rule.set("form", 0)  # RuleMark.RuleForm.SOLID — the regime's signature
	_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)
	_regime_plate = Control.new()
	_regime_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_regime_plate)
	_regime_label = Label.new()
	_regime_label.theme_type_variation = &"RoleLine"
	# THE REGIME PLATE WRAPS (the readability pass): at 1.3x on the 720
	# portrait strip the measured regime print ("THE PAPER CROWN" 214px)
	# plus the raised clock plate starve the name below its word budget
	# (a single "Bartholomew" needs 242px — the letterhead pin caught the
	# word overflowing the shrunk plate). The plate takes a refit-capped
	# width and the print wraps to a second line — paper flow, never a
	# clipped regime and never a starved name. The label does NOT clip
	# (the 4.7 autowrap+clip defect draws only line 1); its wrapper is a
	# plain Control, so the row's height stays the refit's pure function
	# (the same determinism seam as the name plate above).
	_regime_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_regime_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_regime_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_regime_plate.add_child(_regime_label)
	_regime_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_time_plate = Control.new()
	_time_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time_plate)
	_time_label = Label.new()
	_time_label.theme_type_variation = &"PipLabel"
	_time_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_plate.add_child(_time_label)
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cycle_mark = CycleMark.new()
	_cycle_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cycle_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cycle_mark)
	_fit_plates()


func _get_minimum_size() -> Vector2:
	## A full grip-height row: the display-face name plate (~44 units at
	## size 28) must fit INSIDE the strip — an undersized minimum made the
	## labels overflow into the chronicle below (caught by screenshot
	## inspection, not by the rect tests — labels draw outside rects). A
	## wrapped name (finishing #6) grows the row past this floor through
	## the HBox's own child accounting; this floor is the single-line rest.
	return Vector2(Inks.TOUCH_GRIP_MIN * 4.0, Inks.TOUCH_GRIP_MIN)


## The measured width of one label's text in its resolved face (the
## font-metric seam the copy budget tests share).
func _text_width(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, label.get_theme_font_size(&"font_size")).x


## The measured width of the WIDEST WORD (the wrap-atomic unit — a plate
## narrower than its widest word clips mid-word, the letterhead pin's
## 1.3x find).
func _widest_word_width(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	var size := label.get_theme_font_size(&"font_size")
	var widest := 0.0
	for word in label.text.split(" "):
		widest = maxf(widest, font.get_string_size(String(word),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x)
	return widest


## The plates' UNCAPPED minimums (their measured text plus a pad; the
## authored bases grown by the type factor floor them). Measured on every
## bind; the STRIP-AWARE caps are refit's business (below) — bind cannot
## know the strip width. Heights stay 0 here: the wrap heights are the
## REFIT's pure function of the strip width (a bind-time height guess
## spikes the row's minimum and the topology lays the table at the
## spike — the -48px spread the layout-hash pin caught).
func _fit_plates() -> void:
	if _regime_label == null:
		return
	var regime_w := maxf(
		REGIME_PLATE_BASE * TypeScale.factor(),
		_text_width(_regime_label) + PLATE_PAD)
	var time_w := maxf(
		TIME_PLATE_BASE * TypeScale.factor(),
		_text_width(_time_label) + PLATE_PAD)
	_set_plate_mins(regime_w, 0.0, time_w, 0.0)


## The wrappers are plain Controls (the refit's one authority — see the
## _ready note), so their mins are set HERE only.
func _set_plate_mins(regime_w: float, regime_h: float,
		time_w: float, time_h: float) -> void:
	if _regime_plate == null or _time_plate == null:
		return
	_regime_plate.custom_minimum_size = Vector2(regime_w, regime_h)
	_time_plate.custom_minimum_size = Vector2(time_w, time_h)


## Re-fit the letterhead's budgets for one strip width (called by the
## slot's layout_topology BEFORE it reads this row's combined minimum, so
## the row's height is a PURE function of text + type factor + strip
## width — never of which width a previous layout pass happened to leave
## behind; the layout-hash determinism pin caught exactly that drift).
##
## THE WORD-BUDGET SHARE (the readability pass): the name's plate keeps
## at least its widest word (a word cannot wrap). The regime and clock
## plates CAP at their share of what remains and their prints WRAP (the
## plates' heights are the measured wraps at the capped widths — pure).
## A plate whose measured print fits under its cap keeps it whole.
func refit(strip_w: float) -> void:
	if _name_plate == null or _rule == null:
		return
	var fixed := _rule.get_combined_minimum_size().x + 3.0 * PLATE_SEPARATION
	if _cycle_mark != null and _cycle_mark.visible:
		fixed += _cycle_mark.get_combined_minimum_size().x + PLATE_SEPARATION
	var font: Font = _name_label.get_theme_font(&"font")
	var size_now: int = _name_label.get_theme_font_size(&"font_size")
	var name_need := _widest_word_width(_name_label) + 4.0
	var name_need_w := maxf(160.0, name_need)
	# The regime (62%) and clock (the rest) split what the strip can spare
	# beyond the name's word budget and the fixed chrome. A plate never
	# goes below its own widest word (words cannot wrap) — the word floor
	# beats the cap; the print wraps when the cap binds.
	var regime_measured := _text_width(_regime_label) + PLATE_PAD
	var regime_word := _widest_word_width(_regime_label) + PLATE_PAD
	var time_measured := _text_width(_time_label) + PLATE_PAD
	var time_word := _widest_word_width(_time_label) + PLATE_PAD
	var spare := maxf(160.0, strip_w - fixed - name_need_w)
	var regime_w := clampf(regime_measured,
		minf(REGIME_PLATE_BASE * TypeScale.factor(), 90.0), spare * 0.62)
	regime_w = clampf(maxf(regime_w, regime_word), 60.0, regime_measured)
	var time_w := clampf(time_measured,
		minf(TIME_PLATE_BASE * TypeScale.factor(), 80.0), maxf(60.0, spare - regime_w))
	time_w = clampf(maxf(time_w, time_word), 60.0, time_measured)
	# The wraps at the capped widths (the labels autowrap; the wrappers
	# carry the measured heights so the row never lies about its size).
	var rfont: Font = _regime_label.get_theme_font(&"font")
	var rsize := _regime_label.get_theme_font_size(&"font_size")
	var regime_h := rfont.get_multiline_string_size(_regime_label.text,
		HORIZONTAL_ALIGNMENT_LEFT, regime_w - PLATE_PAD, rsize).y
	var tfont: Font = _time_label.get_theme_font(&"font")
	var tsize := _time_label.get_theme_font_size(&"font_size")
	var time_h := tfont.get_multiline_string_size(_time_label.text,
		HORIZONTAL_ALIGNMENT_LEFT, time_w - PLATE_PAD, tsize).y
	_set_plate_mins(regime_w, regime_h, time_w, time_h)
	var others := fixed + regime_w + time_w
	var avail := maxf(name_need_w, strip_w - others)
	var wrapped := font.get_multiline_string_size(_name_label.text,
		HORIZONTAL_ALIGNMENT_LEFT, avail, size_now)
	# The plate's minimum is the row's one authority (the wrapper ignores
	# its child's own minimum, so the label's asynchronous re-shaping can
	# never leak a stale height into the layout): width = the share this
	# strip actually grants the name (the chronicle live-label's own
	# width-floor find), height = the measured wrap at that width.
	_name_plate.custom_minimum_size = Vector2(avail, wrapped.y)


## Bind from the view model's leader block + run clock + the ground the
## strip prints on. THE PRINT RULE (screenshot-inspection find): the
## header sits on the dark TABLE, so its text follows the same
## ink-per-stock rule as the chronicle — paper-bright on dark grounds,
## ink on the pale aftermath. Ink-on-dark was illegible. `escalation`
## (the presenter's standing-garrison block, {} = none) sets the cycle
## mark — additive; an empty block hides it and the row is the pre-L2
## letterhead exactly.
func bind(leader: Dictionary, sim_hours: float, army_power: int, ground: Color,
		escalation := {}) -> void:
	if _name_label == null:
		return
	var text_ink := Inks.ground_text_ink(ground)
	_name_label.text = str(leader["name"]) if not str(leader["name"]).is_empty() else "The Empty Chair"
	_name_label.add_theme_color_override("font_color", text_ink)
	_regime_label.text = str(leader["regime_name"]).to_upper()
	_regime_label.add_theme_color_override("font_color", Inks.regime_secondary(leader["regime_id"]))
	_rule.set("rule_ink", Inks.regime_secondary(leader["regime_id"]))
	_time_label.text = "%dh · power %d" % [int(sim_hours), army_power]
	_time_label.add_theme_color_override("font_color", text_ink)
	if _cycle_mark != null:
		_cycle_mark.set("value", int(escalation.get("cycle", 0)))
		_cycle_mark.set("ink", text_ink)
	_fit_plates()


## CycleMark — the escalation cycle's numeral at the letterhead's crest
## corner (L2-C): a short DOUBLE rule (the victory line-form — every cycle
## is a wall the player's own army took) beside the numeral in the Numerals
## face, ink by the print rule against the live ground. Line-form
## consistent: a printed mark carrying a count, never a hue. Hidden (value
## 0) = no standing garrison = the pre-L2 letterhead, layout and all.
class CycleMark:
	extends Control

	var value := 0:
		set(new_value):
			if value == new_value:
				return
			value = new_value
			_sync_label()
			queue_redraw()

	var ink := Inks.PAPER:
		set(new_ink):
			if ink != new_ink:
				ink = new_ink
				queue_redraw()

	var _label: Label

	const RULE_W := 8.0
	const RULE_GAP := 3.0
	const LABEL_W := 26.0
	const MARK_H := 22.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(RULE_W + RULE_GAP + LABEL_W, MARK_H)

	func _ready() -> void:
		_label = Label.new()
		_label.theme_type_variation = &"Numerals"
		_label.add_theme_font_size_override("font_size", TypeScale.scaled(17))
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.clip_text = true
		_label.position = Vector2(RULE_W + RULE_GAP, 0.0)
		_label.size = Vector2(LABEL_W, MARK_H)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		_sync_label()

	func _sync_label() -> void:
		visible = value > 0
		if _label != null:
			# Re-apply the baked size each reprint — the press-room's live
			# type-scale step re-flows a letterhead composed at another
			# factor the next time a hand binds.
			_label.add_theme_font_size_override("font_size", TypeScale.scaled(17))
			_label.text = str(value)

	func _draw() -> void:
		if value <= 0:
			return
		# The double rule (victory form) at the mark's lead edge, vertically
		# centered — the numeral reads as a COUNT of taken walls.
		var mid := size.y * 0.5
		draw_line(Vector2(0.0, mid - 2.0), Vector2(RULE_W, mid - 2.0), ink, 1.6, true)
		draw_line(Vector2(0.0, mid + 2.0), Vector2(RULE_W, mid + 2.0), ink, 1.6, true)
