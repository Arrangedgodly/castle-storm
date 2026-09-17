## RunHeader — the run's letterhead printed above the table (T-UI-03).
##
## Leader name (display face) + a rule in the regime's second ink + regime
## name + run clock: the identity strip of the current hand. Data-driven
## end to end — a restart rebinds it from the view model; a regime swap
## recolors the rule by content (Inks.regime_secondary), never by code.
## Chrome, not a control: nothing here is interactive, so it carries no
## focus (grips apply to interactive targets only).
##
## THE LINE BUDGET (finishing refinement #6, the closing critique's caveat):
## the letterhead prints on one row at the table's full width, and the name
## WRAPS at word boundaries when the pools deal a long name (the epithet
## drops to its own line — a letterhead's own move, and the same wrap every
## other print surface in this world already uses; the old clip-at-the-plate
## fail-safe cut names like "…the Heavily Record" mid-word at 1.0x, and at
## 1.3x even mid-length names). The regime and clock plates never clip:
## their minimums fit their own measured text (the plate grows, the text
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
var _regime_label: Label
var _time_label: Label


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
	_regime_label = Label.new()
	_regime_label.theme_type_variation = &"RoleLine"
	_regime_label.clip_text = true
	_regime_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_regime_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_regime_label)
	_time_label = Label.new()
	_time_label.theme_type_variation = &"PipLabel"
	_time_label.clip_text = true
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time_label)
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


## The plates' minimums fit their own text: the authored base grown by the
## type factor, or the measured text plus a pad — whichever is wider. A
## plate never clips its print ("THE GILDED CROWN" measured 209px at 1.3x;
## the old fixed plate was 195px). Measured on every bind so a longer
## regime name or clock simply widens its plate and the name cedes the
## difference (wrapping another line if it must).
func _fit_plates() -> void:
	if _regime_label == null:
		return
	_regime_label.custom_minimum_size = Vector2(maxf(
		REGIME_PLATE_BASE * TypeScale.factor(),
		_text_width(_regime_label) + PLATE_PAD), 0.0)
	_time_label.custom_minimum_size = Vector2(maxf(
		TIME_PLATE_BASE * TypeScale.factor(),
		_text_width(_time_label) + PLATE_PAD), 0.0)


## Re-fit the letterhead's budgets for one strip width (called by the
## slot's layout_topology BEFORE it reads this row's combined minimum, so
## the row's height is a PURE function of text + type factor + strip
## width — never of which width a previous layout pass happened to leave
## behind; the layout-hash determinism pin caught exactly that drift).
func refit(strip_w: float) -> void:
	if _name_plate == null or _rule == null:
		return
	_fit_plates()
	var others := _rule.get_combined_minimum_size().x \
		+ _regime_label.custom_minimum_size.x \
		+ _time_label.custom_minimum_size.x \
		+ 3.0 * PLATE_SEPARATION
	var avail := maxf(160.0, strip_w - others)
	var font: Font = _name_label.get_theme_font(&"font")
	var size_now: int = _name_label.get_theme_font_size(&"font_size")
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
## ink on the pale aftermath. Ink-on-dark was illegible.
func bind(leader: Dictionary, sim_hours: float, army_power: int, ground: Color) -> void:
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
	_fit_plates()
