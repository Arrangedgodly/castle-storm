## IntroPacket — the leader intro's reveal ON THE TABLE (T-UI-05).
##
## The anti-goal is popup chrome (design brief §4): the intro is a moment
## ON THE SAME TABLE — the run's opening hand dealt as paper, never a
## modal overlay. This control IS that moment's paper:
##
##   - the PACKET: the folded hand (three face-down card backs peeking
##     from under the leader card — the fold the one gesture will open);
##   - the LEADER CARD dealt face-up on the packet (name + epithet +
##     personality tags + trait in the world's print grammar, the peasant
##     face from the art manifest, the revolution's seal);
##   - the REGIME FACE CARD beside it — Major-Arcana-scale (strictly
##     larger than the leader card), the regime's crest slot + flavor
##     line + second-ink hairline, NO seal (the seal is the revolution's,
##     never the Crown's);
##   - the printed lines (ChronicleLine rows — the variant's beats:
##     fresh copy / regime-swap + bank / the-regime-remembers);
##   - THE ONE GESTURE chip (ActionFan's ActionChip unforked — the
##     signature double rule; it is the only focusable thing).
##
## THE UNFOLD (motion grammar: unfold = open / session start): the packet
## sweeps open onto the table beneath — the veil lifts first (the
## candle-lit reveal giving way to the live spread), the leader card and
## the fold sweep toward the table's heart while the regime card
## withdraws to the Crown's edge, the print fades last — 1–3s authored,
## NEAR-INSTANT under reduced motion (same end state, synchronous). The
## intro IS the loading moment into the spread: the spread is bound and
## live beneath the whole time.
##
## Determinism: bind(view) is a pure function of the presenter's view
## model; the authored sweep is a pure function of t (0..1) —
## snapshot_hash() pins the render, unfold_progress()/apply is the
## capture hook's mid-sweep probe.
class_name IntroPacket
extends Control

const FRAME_SCENE := preload("res://ui/theme/card_frame.tscn")
const FACE_SCENE := preload("res://ui/theme/card_face.tscn")
const CHRONICLE_SCENE := preload("res://ui/theme/chronicle_line.tscn")

## Layout margins/gaps (design units; grip = 48).
const MARGIN := 16.0
const GAP := 12.0
const TITLE_H := 58.0
const LINE_H := 32.0
const LINES_SHOWN := 3
## The veil's reveal opacity — dim enough that the reveal reads as its
## own candle-lit moment, never opaque enough to hide that the table
## lives beneath.
const VEIL_ALPHA := 0.92
## Any duration at/below this lands synchronously (reduced motion).
const SYNC_SECONDS := 0.1

## The bound ground (the veil keeps its hue; only alpha animates).
var _veil_ground := Inks.NEUTRAL_GROUND
## Authored sweep state: 0..1 in flight; -1 = resting at the reveal.
var _unfold_t := -1.0
var _duration := 0.16
var _on_done := Callable()

var _veil: ColorRect
var _title_label: Label
var _backs: Array[Control] = []
var _leader_frame: Control
var _leader_face: BoxContainer
var _regime_frame: Control
var _regime_face: BoxContainer
var _lines: Array[Control] = []
var _chip: Button
## Reveal-time home rects (from reveal_rects; the sweep's anchors).
var _homes := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compose()
	_relaid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _unfold_t < 0.0:
			_relaid()


# --- composition (all T-UI-01 components — nothing forked) -------------------------------


func _compose() -> void:
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"CardTitle"
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.clip_text = true
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	# The packet: three face-down backs (the folded hand), dealt BEHIND
	# the leader card in z-order (they peek from under its top-left).
	for i in 3:
		var back := FRAME_SCENE.instantiate() as Control
		back.set("face_up", false)
		back.set("show_seal", false)
		back.focus_mode = Control.FOCUS_NONE
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(back)
		_backs.append(back)

	_leader_frame = FRAME_SCENE.instantiate()
	_leader_frame.focus_mode = Control.FOCUS_NONE
	_leader_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_leader_frame)
	_leader_face = _face_into(_leader_frame, 14.0)
	_tune_plates(_leader_face, 22)

	_regime_frame = FRAME_SCENE.instantiate()
	_regime_frame.set("show_seal", false)
	_regime_frame.focus_mode = Control.FOCUS_NONE
	_regime_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_regime_frame)
	_regime_face = _face_into(_regime_frame, 12.0)
	# THE PLATE RULES (the first capture's find, MEASURED): long names and
	# flavor lines WRAP on their plates — a clipped name on a face card
	# reads broken. The regime's Major-Arcana title prints one size down
	# (the T-UI-07 castle-title rule) with word-smart wrap; the leader's
	# name is the reveal's hero text and keeps more size, wrapping to 2–3
	# lines; every role/flavor plate wraps instead of clipping.
	_tune_plates(_regime_face, 20)

	for i in LINES_SHOWN:
		var line: Control = CHRONICLE_SCENE.instantiate()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		_lines.append(line)

	_chip = ActionFan.ActionChip.new()
	_chip.action = {
		"id": "unfold", "label": IntroPresenter.CHIP_LABEL,
		"enabled": true, "reason": "", "signature": true,
		"command": &"", "subject": &"", "value": 0,
	}
	_chip.custom_minimum_size = Vector2(232.0, float(Inks.TOUCH_GRIP_MIN))
	add_child(_chip)


## One CardFace inset into a frame (the SpreadCards composition shape).
func _face_into(frame: Control, inset: float) -> BoxContainer:
	var box := MarginContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = inset
	box.offset_top = inset + 2.0
	box.offset_right = -inset
	box.offset_bottom = -inset
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)
	var face := FACE_SCENE.instantiate() as BoxContainer
	face.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	face.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(face)
	return face


## Word-smart wrap on every text plate (a face card's name/flavor WRAPS,
## never clips); the title plate takes `title_size`.
func _tune_plates(face: BoxContainer, title_size: int) -> void:
	for plate in face.get_children():
		if plate is not Label:
			continue
		var label := plate as Label
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = false
		if label.theme_type_variation == &"CardTitle":
			label.add_theme_font_size_override("font_size", title_size)


# --- binding (pure in the view model) ------------------------------------------------------


## Bind the presenter's view. Same view => same render (snapshot_hash).
func bind(view: Dictionary) -> void:
	var variant: StringName = view["variant"]
	var leader: Dictionary = view["leader"]
	var regime: Dictionary = view["regime"]
	_title_label.text = _title_for(variant)
	_leader_frame.set("edge_form", Inks.EdgeForm.SOLID)
	_leader_frame.set("regime_id", regime["id"])
	_leader_frame.set("misprint_seed", int(view["run_number"]) * 31 + 7)
	_leader_face.set("card_name", String(leader["name"]))
	_leader_face.set("role_line", _leader_role(leader))
	_leader_face.set("face_key", leader["face_key"])
	_regime_frame.set("edge_form", Inks.EdgeForm.SOLID)
	_regime_frame.set("regime_id", regime["id"])
	_regime_frame.set("misprint_seed", absi(String(regime["id"]).hash() % 9973))
	_regime_face.set("card_name", String(regime["name"]).to_upper())
	_regime_face.set("role_line", _wrapped(String(regime["flavor"]), 30, 3))
	_regime_face.set("face_key", regime["crest_key"])
	var ground: Color = regime["ground"]
	_veil_ground = ground
	# THE PRINT RULE (the T-UI-03 header find): the title prints on the
	# dark veil, so it follows the ink-per-stock rule like every other
	# print on a dark ground — paper-bright, never near-black on dark.
	_title_label.add_theme_color_override("font_color", Inks.ground_text_ink(ground))
	for i in LINES_SHOWN:
		var line := _lines[i]
		var rows: Array = view["lines"]
		if i < rows.size():
			line.set("line_class", int(rows[i]["class"]))
			line.set("text", String(rows[i]["text"]))
			line.set("ground", ground)
		else:
			line.set("text", "")
	_unfold_t = -1.0
	visible = true
	_relaid()
	_apply(0.0)


## The masthead per variant: the first deal, the next hand, or the
## returning hand (T-UI-09's check-in — the same hand resumes).
static func _title_for(variant: StringName) -> String:
	match variant:
		IntroPresenter.VARIANT_FIRST_RUN:
			return "THE FIRST HAND"
		IntroPresenter.VARIANT_RESUMED:
			return "THE HAND RETURNS"
		_:
			return "THE NEXT HAND"


## The leader's plate: the personality tags + trait stub in the print
## grammar (T-COPY-01 deepens the voice; the DATA is the sim's own).
func _leader_role(leader: Dictionary) -> String:
	var tags: Array = leader["tags"]
	var parts: Array[String] = []
	for tag in tags:
		parts.append(String(tag).replace("_", " "))
	return "%s · %s" % [" and ".join(parts), String(leader["trait"])]


## Greedy word-wrap at a character width, capped at max_lines (the
## regime's flavor is content-long; a clipped flavor on the face card
## reads broken — the castle-card rule).
func _wrapped(text: String, width: int, max_lines: int) -> String:
	if text.length() <= width:
		return text
	var lines: Array[String] = []
	var remaining := text
	while remaining.length() > width and lines.size() < max_lines - 1:
		var cut := remaining.rfind(" ", width)
		if cut <= 0:
			cut = width
		lines.append(remaining.substr(0, cut))
		remaining = remaining.substr(cut + 1)
	lines.append(remaining)
	return "\n".join(lines)


# --- layout (pure statics) -----------------------------------------------------------------


func _relaid() -> void:
	if _title_label == null or size.x < 8.0 or size.y < 8.0:
		return
	_homes = reveal_rects(size)
	_fit(_title_label, _homes["title"])
	_fit(_regime_frame, _homes["regime"])
	_fit(_leader_frame, _homes["leader"])
	for i in _backs.size():
		_fit(_backs[i], (_homes["backs"] as Array)[i])
	var rows: Rect2 = _homes["lines"]
	for i in LINES_SHOWN:
		_fit(_lines[i], Rect2(rows.position + Vector2(0, i * LINE_H), Vector2(rows.size.x, LINE_H)))
	_fit(_chip, _homes["chip"])


## The reveal's layout rects. PORTRAIT stacks the hand (the regime's face
## card above — the Crown looms over the peasant — the leader dealt under
## it on the packet); LANDSCAPE/square lays them BESIDE each other (the
## regime at the Crown's edge — the right, where the Eye and the castle
## perch). Every rect is inside bounds by construction (the four-size
## unclipped guarantee) and the regime card is strictly larger than the
## leader card (Major-Arcana scale).
static func reveal_rects(bounds: Vector2) -> Dictionary:
	var stacked := bounds.y > bounds.x
	var regime_w := clampf(bounds.x * 0.30, 140.0, 232.0)
	var regime_h := regime_w * 1.30
	# MEASURED plate widths (IM Fell SC / Alegreya, the capture find): the
	# longest leader name is 318px at 18pt and the longest regime title
	# 243px at 22 — both wrap on their plates, and the leader card is
	# nearly the regime's width so the wrap stays 2–3 lines, never 5.
	var leader_w := regime_w * 0.92
	var leader_h := leader_w * 1.24
	var chip_h := float(Inks.TOUCH_GRIP_MIN)
	var lines_w := minf(bounds.x - 2.0 * MARGIN, 560.0)
	var lines_h := float(LINES_SHOWN) * LINE_H
	var title: Rect2 = Rect2(Vector2(MARGIN, MARGIN), Vector2(bounds.x - 2.0 * MARGIN, TITLE_H))
	var chip := Rect2(
		Vector2((bounds.x - 232.0) * 0.5, bounds.y - MARGIN - chip_h),
		Vector2(232.0, chip_h))
	var lines := Rect2(
		Vector2((bounds.x - lines_w) * 0.5, chip.position.y - GAP - lines_h),
		Vector2(lines_w, lines_h))
	var regime: Rect2
	var leader: Rect2
	if stacked:
		regime = Rect2(Vector2((bounds.x - regime_w) * 0.5, title.end.y + GAP),
			Vector2(regime_w, regime_h))
		leader = Rect2(
			Vector2((bounds.x - leader_w) * 0.5, regime.end.y + GAP),
			Vector2(leader_w, leader_h))
	else:
		# The dealt pair, centered together: leader at the gate side (left),
		# the regime's face card beside it toward the Crown's edge.
		var pair_w := leader_w + 2.0 * GAP + regime_w
		var left := (bounds.x - pair_w) * 0.5
		var band_top := title.end.y + GAP
		var band_bottom := lines.position.y - GAP
		var band_mid := (band_top + band_bottom) * 0.5
		leader = Rect2(Vector2(left, band_mid - leader_h * 0.5), Vector2(leader_w, leader_h))
		regime = Rect2(
			Vector2(left + leader_w + 2.0 * GAP, band_mid - regime_h * 0.5),
			Vector2(regime_w, regime_h))
	# Degenerate-tall guard: the cards may not intrude on the print.
	if leader.end.y > lines.position.y - GAP:
		var trim := leader.end.y - (lines.position.y - GAP)
		leader.size.y = maxf(float(Inks.TOUCH_GRIP_MIN * 2.0), leader.size.y - trim)
	if regime.end.y > lines.position.y - GAP:
		var trim_r := regime.end.y - (lines.position.y - GAP)
		regime.size.y = maxf(float(Inks.TOUCH_GRIP_MIN * 2.0), regime.size.y - trim_r)
	# The folded hand peeks from under the leader card's shoulder
	# (up-left, toward the dealt stack — never past the bounds).
	var backs: Array[Rect2] = []
	for i in 3:
		var step := Vector2(-8.0, -10.0) * float(i + 1)
		var origin := leader.position + step
		origin.x = maxf(0.0, origin.x)
		origin.y = maxf(0.0, origin.y)
		backs.append(Rect2(origin, leader.size))
	return {"title": title, "regime": regime, "leader": leader, "backs": backs,
		"lines": lines, "chip": chip, "stacked": stacked}


func _fit(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


# --- the authored unfold --------------------------------------------------------------------


## Play the one-gesture unfold. `duration` comes through MotionProfile
## (full motion = the authored 1–3s sweep, reduced = near-instant); any
## duration <= SYNC_SECONDS lands SYNCHRONOUSLY — same end state, the
## done Callable fires before this returns.
func play_unfold(duration: float, on_done: Callable) -> void:
	_on_done = on_done
	_duration = maxf(0.016, duration)
	_unfold_t = 0.0
	visible = true
	if duration <= SYNC_SECONDS:
		# The sync land is COMPLETE: progress reports 1.0 (never 0.00 after
		# a synchronous completion — the round-1 verifier's reporting nit).
		# Reporting only: _land() applies the same end state either way.
		_unfold_t = 1.0
		_apply(1.0)
		_land()
		return


## True while the authored sweep is in flight.
func is_unfolding() -> bool:
	return _unfold_t >= 0.0 and _unfold_t < 1.0


## The sweep's progress 0..1 (-1 = resting at the reveal; 1 = complete).
func unfold_progress() -> float:
	return _unfold_t


func _process(delta: float) -> void:
	if _unfold_t < 0.0 or _unfold_t >= 1.0:
		return
	_unfold_t = minf(1.0, _unfold_t + delta / _duration)
	_apply(_unfold_t)
	if _unfold_t >= 1.0:
		_land()


## The authored sweep as a pure function of t: the VEIL lifts first (the
## live spread shows through), the leader card + the fold sweep toward
## the table's heart, the regime card withdraws to its edge, the print
## fades last. Reduced motion lands at apply(1.0) — the exact same end
## state the pacing reaches.
func _apply(t: float) -> void:
	if _homes.is_empty():
		return
	var e := smoothstep(0.0, 1.0, t)
	_veil.color = Color(_veil_ground, (1.0 - clampf(t / 0.45, 0.0, 1.0)) * VEIL_ALPHA)
	var stacked: bool = size.y > size.x
	# The leader card + the fold sweep toward the table's heart (portrait:
	# down the column toward the spread; landscape: across to the gate
	# side, the left).
	var heart := Vector2(-size.x * 0.10, size.y * 0.12) if stacked \
		else Vector2(-size.x * 0.22, size.y * 0.06)
	_leader_frame.position = (_homes["leader"] as Rect2).position + heart * e
	_leader_frame.modulate = Color(1, 1, 1, 1.0 - clampf((t - 0.25) / 0.6, 0.0, 1.0))
	for i in _backs.size():
		var back := _backs[i]
		var home: Rect2 = (_homes["backs"] as Array)[i]
		back.position = home.position + heart * e * (1.0 + 0.35 * float(i))
		back.rotation_degrees = 1.6 * float(i + 1) * e
		back.modulate = Color(1, 1, 1, 1.0 - clampf((t - 0.10) / 0.5, 0.0, 1.0))
	# The regime card withdraws to the Crown's edge (portrait: up and
	# away — the Crown leaves the peasant to it; landscape: right, where
	# it perches).
	var crown := Vector2(size.x * 0.14, -size.y * 0.10) if stacked \
		else Vector2(size.x * 0.18, -size.y * 0.06)
	_regime_frame.position = (_homes["regime"] as Rect2).position + crown * e
	_regime_frame.modulate = Color(1, 1, 1, 1.0 - clampf((t - 0.20) / 0.6, 0.0, 1.0))
	_title_label.position = (_homes["title"] as Rect2).position - Vector2(0.0, 22.0 * e)
	_title_label.modulate = Color(1, 1, 1, 1.0 - clampf(t / 0.5, 0.0, 1.0))
	var print_fade := 1.0 - clampf((t - 0.35) / 0.5, 0.0, 1.0)
	for line in _lines:
		line.modulate = Color(1, 1, 1, print_fade)
	_chip.modulate = Color(1, 1, 1, print_fade)
	_chip.position = (_homes["chip"] as Rect2).position + Vector2(0.0, 10.0 * e)


## The sweep's landing: everything off in one settled state (the spread
## beneath is the screen's business now).
func _land() -> void:
	_apply(1.0)
	visible = false
	var done := _on_done
	_on_done = Callable()
	if done.is_valid():
		done.call()


## The render oracle: every printed plate + the layout's stack mode. Same
## view => same hash (tests pin the reveal's determinism end to end).
func snapshot_hash() -> int:
	var h := 0x811C9DC5
	h = _mix(h, _title_label.text.hash())
	h = _mix(h, String(_leader_face.get("card_name")).hash())
	h = _mix(h, String(_leader_face.get("role_line")).hash())
	h = _mix(h, StringName(String(_leader_face.get("face_key"))).hash())
	h = _mix(h, int(_leader_frame.get("edge_form")))
	h = _mix(h, String(_regime_face.get("card_name")).hash())
	h = _mix(h, String(_regime_face.get("role_line")).hash())
	h = _mix(h, StringName(String(_regime_face.get("face_key"))).hash())
	h = _mix(h, String(_chip.action.get("label", "")).hash())
	for line in _lines:
		h = _mix(h, String(line.get("text")).hash())
		h = _mix(h, int(line.get("line_class")))
	h = _mix(h, int(bool(_homes.get("stacked", false))))
	return h


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
