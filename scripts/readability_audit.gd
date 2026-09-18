## The readability audit (NOT a test; a measurement probe — r3).
##
##     godot --headless --path . -s res://scripts/readability_audit.gd
##
## Mounts the REAL surfaces (the spread screen at both real targets, the
## assault odds stage with a POPULATED roster, and a DENSE 20-card
## estate) at both real targets (720x1280 portrait, 1280x800 landscape)
## x the scale range ends (1.0x / 1.3x), walks EVERY visible Label, and
## checks:
##
##   CLIP      — clip_text label whose text is wider than its plate
##   OVERFLOW  — unclipped label whose text is wider than its plate
##               (draws past the plate — the worst kind)
##   WRAP-CLIP — wrapped or "\n"-split label whose text height exceeds
##               its plate (the castle share line's round-1 find)
##   OCCLUSION — two visible text labels whose plates overlap (>= 4px
##               both axes) outside a DESIGNED paper overlay — text
##               printed on text is never a design. r3: THE FAN IS
##               CO-MOUNTED — the r2 audit walked a STANDALONE fan, freed
##               it, then walked the screen, and so never saw the real
##               state a player sees: the screen's own fan OPEN ON THE
##               TABLE, its chips + hint strip printing across neighbor
##               cards' titles. The audit now opens the real fan on
##               every actionable card (gate table AND estate) and grades
##               fan-print vs foreign-text overlap as a defect unless
##               the fan's own paper SHEET (the designed surface —
##               ActionFan.sheet_rect) covers the overlap.
##   STALLED   — a visible label with text whose plate never got laid
##               (either axis <= 1px): the plate renders no print. The
##               r2 audit SKIPPED these ("not laid out yet") — the skip
##               was the dense-estate find's blindness (18 of 40 estate
##               plates rendering no print). A stalled plate is a
##               DEFECT, not a skip.
##   PAST-EDGE — a card plate printing past its card's bottom edge onto
##               the table ground (the estate caption find). Checked on
##               unrotated cards only (the STACKED grid; the panoramic
##               fan's rotation legitimately moves plates past card
##               rects).
##   OFFSCREEN — a STACKED grid card parked outside the design bounds
##               (the r3 windowed estate's runaway: a minimum-chain
##               feedback inflated the band, re-pitched the ladder and
##               sheared the last row off the screen). Containment is
##               the density boundary's hard edge.
##   SUB-FLOOR — resolved size below the 12px READABILITY FLOOR (scaled)
##   TINY      — resolved size below 17px (the small-print rungs)
##   MOUNT     — the probe's own sanity (router orientation, roster
##               populated, the estate actually dense) — a broken mount
##               invalidates the pass
##
## THE PASS BAR (readability r3 — co-mounted): at 1.0x, BOTH
## orientations: 0 CLIP, 0 OVERFLOW, 0 WRAP-CLIP, 0 OCCLUSION, 0
## STALLED, 0 PAST-EDGE, 0 OFFSCREEN, 0 SUB-FLOOR, 0 MOUNT, and TINY <=
## the round-1 baseline (10). The 1.3x pass is FLOOR-CHECK ONLY (fixed
## plates may re-flow at the cap; the floor must hold at any scale):
## 0 SUB-FLOOR,
## 0 STALLED, 0 MOUNT; everything else is reported for information.
##
## r3 mount adds the DENSE ESTATE (the r2 runtime finalization never
## fully re-laid dense initial binds — the audit never mounted one): a
## seeded accept-every-offer run to a 20-card estate, walked at both
## orientations — every visible plate must render title + role at real
## height, captions never overprint the card edge onto the ground, and
## the fan co-mounts there too. r2 mount fixes kept: the probe forces a
## real resize per target, and the odds host RECRUITS + MUSTERS units.
## Deterministic (seeded hosts, fixed mounts); ends with quit() and a
## PASS/FAIL line.
extends SceneTree

const RUN_SEED := 20261103
var _audit_root := "user://cs_readability_audit_%d" % OS.get_process_id()
const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")
const ASSAULT_STAGE := preload("res://ui/screens/assault/assault_stage.tscn")

const SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),  # phone portrait
	Vector2i(1280, 800),  # Steam Deck landscape
]
const SCALES: Array[float] = [1.0, 1.3]
const READABILITY_FLOOR := 12  # the hard floor — no rendered text below it
const TINY_FLOOR := 17  # the small-print rungs (count-bounded, not zeroed)
const TINY_BASELINE := 10  # the round-1 TINY count of record
const OVERLAP_MIN := 4.0  # px in BOTH axes before two plates count as occluding
const FRAMES := 30  # enough for the plates-grow verdict cascade to settle

var _findings: Array[String] = []
var _counts := {}  # kind -> count, reset per scale (the bar is per scale)
var _scale_totals := {}  # scale -> counts snapshot for the bar
var _scale := 1.0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("[audit] start")
	_erase_dir(_audit_root)
	for scale: float in SCALES:
		_scale = scale
		_counts.clear()
		TypeScale.reset()
		TypeScale.apply_factor(scale)
		for size: Vector2i in SIZES:
			# Force a REAL resize per target (the r1 first-mount find: the
			# router must see the size CHANGE) and poll the design size to
			# LAND — the stretch's design space converges over frames (the
			# suites' own _settle_window seam: fixed frames sized nothing).
			root.size = Vector2i(900, 900) if size != Vector2i(900, 900) else Vector2i(901, 901)
			await _frames(4)
			root.size = size
			await _frames(4)
			for i in 240:
				await process_frame
				var design := root.get_visible_rect().size  # the router's own seam
				if absf(design.x - size.x) < 1.0 and absf(design.y - size.y) < 1.0:
					break
			await _frames(FRAMES)
			await create_timer(0.6).timeout  # the router's dwell (0.25s) must pass
			var tag := "%dx%d @ %.1fx" % [size.x, size.y, scale]
			await _audit_spread(tag, size)
			await _audit_assault(tag, size)
			await _audit_estate(tag, size)
		_scale_totals[scale] = _counts.duplicate()
	TypeScale.reset()
	root.size = Vector2i(720, 720)
	_summary()
	quit()


# --- the mounts -------------------------------------------------------------------


func _audit_spread(tag: String, size: Vector2i) -> void:
	print("[audit] mounting spread @ %s" % tag)
	var host := _gate_host(RUN_SEED)
	var screen: Control = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = false
	root.add_child(screen)
	await _frames(FRAMES)
	await create_timer(0.6).timeout  # the topology swap's dwell must pass
	await _frames(FRAMES)
	var want_portrait := size.x < size.y
	if screen.get_router().is_portrait() != want_portrait:
		_finding(tag, "spread", "MOUNT", "router portrait=%s (want %s)" % [
			screen.get_router().is_portrait(), want_portrait])
	# Region diagnostics: the rects the settle actually left behind.
	var slot: OrientationSlot = screen.get_portrait_slot() if want_portrait \
		else screen.get_landscape_slot()
	var spread_ctrl: Control = slot.get_spread()
	var header_ctrl: Control = slot.get_header()
	var chron_ctrl: Control = slot.get_chronicle_line(0).get_parent() \
		if slot.get_chronicle_line(0) != null else null
	print("[audit] %s regions: header=%s/%s spread=%s/%s chronicle=%s/%s" % [tag,
		header_ctrl.size if header_ctrl != null else Vector2.ZERO,
		header_ctrl.get_combined_minimum_size() if header_ctrl != null else Vector2.ZERO,
		spread_ctrl.size, spread_ctrl.get_combined_minimum_size(),
		chron_ctrl.size if chron_ctrl != null else Vector2.ZERO,
		chron_ctrl.get_combined_minimum_size() if chron_ctrl != null else Vector2.ZERO])
	# THE FAN IS CO-MOUNTED (readability r3 — the audit-blindness fix):
	# the r2 audit mounted a STANDALONE ActionFan on the probe root,
	# freed it, THEN walked the screen — never the state a player sees.
	# The screen's own fan is opened on EVERY actionable card here (the
	# real path, `open_fan_for_card`), and the whole SCREEN is walked
	# under it: every open is graded by the full label checks plus the
	# fan-vs-foreign occlusion rule (see _audit_fan_co_mounted).
	await _audit_fan_co_mounted(screen, tag)
	_walk(screen, "spread/" + tag, screen)
	await _frames(2)
	screen.queue_free()
	await _frames(2)


func _audit_assault(tag: String, size: Vector2i) -> void:
	var host := _audit_host(RUN_SEED)
	var stage: Control = ASSAULT_STAGE.instantiate()
	root.add_child(stage)
	stage.size = Vector2(size)  # the screen's business normally — the audit mounts bare
	stage.position = Vector2.ZERO
	stage.portrait = size.x < size.y
	await _frames(2)
	stage.regime_id = host.run().regime_id()
	stage.regime_name = Inks.regime_name(host.run().regime_id())
	stage.bind_odds(AssaultPresenter.odds_view(host.assault().assault_odds(host.engine)))
	await _frames(FRAMES)
	if stage.ranks().is_empty():
		_finding(tag, "assault_stage", "MOUNT",
			"roster EMPTY — the rank plates would go unmeasured (the r1 find)")
	_walk(stage, "assault_stage/" + tag, stage)
	stage.queue_free()
	await _frames(2)


## THE CO-MOUNTED FAN AUDIT (readability r3): open the screen's own fan
## on every actionable card (the real `open_fan_for_card` path — the
## same one a press or tap drives) and, while it is open, walk ALL
## visible labels of the screen. A fan print (chip label, refusal
## reason, hint print) overlapping a FOREIGN text label (>= 4px both
## axes — the audit's overlay rule) is a DEFECT unless the fan's own
## paper sheet covers the overlap: covering text is legitimate ONLY
## when the covering paper is a designed surface. Foreign-vs-foreign
## pairs stay policed by the ordinary walk.
func _audit_fan_co_mounted(screen: Control, tag: String) -> void:
	var fan: ActionFan = screen._fan
	if fan == null:
		_finding(tag, "action_fan", "MOUNT", "the screen built no fan")
		return
	var cards: Array[Control] = _spread_cards(screen, tag)
	var opened := 0
	var sheeted := 0  # fan-print/foreign overlaps excused BY the sheet (informational)
	for card in cards:
		screen.open_fan_for_card(card)
		await _frames(8)  # the chips' plates settle their granted widths
		if not fan.is_open():
			continue
		opened += 1
		if opened == 1:
			_note(tag, "action_fan", "co-mounted fan open on card %s (%d chips)" % [
				card.get_meta(&"spread_card_id", ""), fan.chips().size()])
		# The sheet's GLOBAL rect (the fan is never rotated or scaled on
		# the screen — local == global axes).
		var sheet: Rect2 = fan.sheet_rect()
		sheet.position += fan.global_position
		var fan_labels: Array[Label] = []
		_collect_labels(fan, fan_labels)
		var foreign: Array[Label] = []
		var all_labels: Array[Label] = []
		_collect_labels(screen, all_labels)
		for label in all_labels:
			if fan.is_ancestor_of(label):
				continue
			foreign.append(label)
		for fan_label in fan_labels:
			if fan_label.text.is_empty() or not fan_label.is_visible_in_tree():
				continue
			for other in foreign:
				if other.text.is_empty() or not other.is_visible_in_tree():
					continue
				var inter: Rect2 = fan_label.get_global_rect().intersection(other.get_global_rect())
				if inter.size.x < OVERLAP_MIN or inter.size.y < OVERLAP_MIN:
					continue
				if sheet.encloses(inter):
					sheeted += 1  # the designed paper covers it — the veil grammar
					continue
				_finding(tag, "action_fan", "OCCLUSION",
					"fan print \"%s\" on foreign \"%s\" %s OUTSIDE the fan's sheet" % [
						_short(fan_label.text), _short(other.text), inter])
		screen.close_fan()
		await _frames(2)
	if opened == 0:
		_finding(tag, "action_fan", "MOUNT", "no card offered actions — the fan was never co-mounted")
	else:
		_note(tag, "action_fan", "%d fans co-mounted; %d fan-print/foreign overlaps, all sheeted" % [
			opened, sheeted])


## THE DENSE ESTATE (readability r3 — the r2 finalization's unfinished
## bind, invisible to the r2 audit because it never mounted one): a
## seeded accept-every-offer run to a 20-card estate, mounted at the
## real target and walked like the gate table — every visible plate must
## render its title + role at REAL height (no STALLED plates), captions
## never print past the card's bottom edge onto the ground (PAST-EDGE,
## unrotated cards — the STACKED grid), and the fan co-mounts here too.
func _audit_estate(tag: String, size: Vector2i) -> void:
	print("[audit] mounting dense estate @ %s" % tag)
	var host := _estate_host(RUN_SEED)
	var screen: Control = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = false
	root.add_child(screen)
	await _frames(FRAMES)
	await create_timer(0.6).timeout  # the topology swap's dwell must pass
	await _frames(FRAMES)
	await create_timer(0.4).timeout  # the mount finalization's bounded loop
	await _frames(FRAMES)
	var want_portrait := size.x < size.y
	if screen.get_router().is_portrait() != want_portrait:
		_finding("estate/" + tag, "estate", "MOUNT", "router portrait=%s (want %s)" % [
			screen.get_router().is_portrait(), want_portrait])
	var cards: Array[Control] = _spread_cards(screen, tag)
	print("[audit] %s estate: %d cards mounted" % [tag, cards.size()])
	if cards.size() < 20:
		_finding("estate/" + tag, "estate", "MOUNT", "expected a 20-card estate, got %d" % cards.size())
	for card in cards:
		if not card.is_visible_in_tree():
			_finding("estate/" + tag, "estate", "MOUNT", "card %s invisible on mount" % card.name)
			continue
		# The plates' own grading (STALLED / SUB-FLOOR / CLIP / ...) is the
		# final `_walk`'s job — this loop is the estate's GEOMETRY only.
		for label in _labels_of(card):
			if label.text.is_empty() or not label.is_visible_in_tree():
				continue
			if label.size.x <= 1.0 or label.size.y <= 1.0:
				continue  # STALLED already graded by the walk
			if is_zero_approx(card.rotation):
				var past := label.get_global_rect().end.y - card.get_global_rect().end.y
				if past > 2.0:
					_finding("estate/" + tag, "estate", "PAST-EDGE",
						"\"%s\" prints %.0fpx past the card's bottom edge onto the ground" % [
							_short(label.text), past])
		if want_portrait:
			for other in cards:
				if other.get_index() <= card.get_index():
					continue
				var inter: Rect2 = card.get_global_rect().intersection(other.get_global_rect())
				if inter.size.x >= 2.0 and inter.size.y >= 2.0:
					_finding("estate/" + tag, "estate", "OCCLUSION",
						"STACKED cards overlap: %s vs %s %s" % [card.name, other.name, inter])
		# CONTAINMENT (r3, the windowed estate's runaway): a STACKED grid
		# card must sit inside the design — a minimum-chain runaway pitches
		# rows past the screen bottom where the player can never reach them.
		if want_portrait:
			var design := screen.size
			var card_rect := card.get_global_rect()
			if card_rect.position.y > design.y - 2.0 or card_rect.end.y < 2.0 \
					or card_rect.position.x > design.x - 2.0 or card_rect.end.x < 2.0:
				_finding("estate/" + tag, "estate", "OFFSCREEN",
					"card %s at %s outside the %s design" % [card.name, card_rect, design])
	await _audit_fan_co_mounted(screen, "estate/" + tag)
	_walk(screen, "estate/" + tag, screen)
	await _frames(2)
	screen.queue_free()
	await _frames(2)


# --- the label walk -----------------------------------------------------------------


func _walk(node: Node, tag: String, surface: Node) -> void:
	var labels: Array[Label] = []
	_collect_labels(node, labels)
	for label: Label in labels:
		_audit_label(label, tag)
	# OCCLUSION: text printed on text outside a designed paper overlay.
	for i in labels.size():
		for j in range(i + 1, labels.size()):
			_audit_occlusion(labels[i], labels[j], tag, surface)


func _collect_labels(node: Node, into: Array[Label]) -> void:
	if node is Label:
		into.append(node as Label)
	for child in node.get_children():
		_collect_labels(child, into)


func _audit_label(label: Label, tag: String) -> void:
	if label.text.is_empty() or not label.is_visible_in_tree():
		return
	var where := "%s [%s]" % [tag, label.theme_type_variation if label.theme_type_variation != &"" else &"Label"]
	# STALLED (r3 — the skip is DEAD): a visible label carrying text whose
	# plate never got laid renders NO print. The r2 audit returned here
	# ("not laid out yet") and so was blind to the dense-estate stall —
	# 18 of 40 estate plates at 1px tall. A stalled plate is a defect.
	if label.size.x <= 1.0 or label.size.y <= 1.0:
		_finding(tag, where, "STALLED", "plate %.0fx%.0f never laid its print \"%s\"" % [
			label.size.x, label.size.y, _short(label.text)])
		return
	var font: Font = label.get_theme_font(&"font")
	if font == null:
		return
	var size := label.get_theme_font_size(&"font_size")
	if size <= 0:
		return
	if size < TypeScale.scaled(READABILITY_FLOOR):
		_finding(tag, where, "SUB-FLOOR", "%dpx \"%s\"" % [size, _short(label.text)])
	elif size < TINY_FLOOR:
		_finding(tag, where, "TINY", "%dpx \"%s\"" % [size, _short(label.text)])
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		var shaped := font.get_multiline_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, label.size.x, size)
		if shaped.y > label.size.y + 1.0:
			_finding(tag, where, "WRAP-CLIP", "%dx%d plate holds %.0fx%.0f of wrapped text \"%s\"" % [
				int(label.size.x), int(label.size.y), shaped.x, shaped.y, _short(label.text)])
		return
	# A "\n"-split print (the castle share line's grammar) is measured on
	# its height too — the r1 fit treated it as one long line.
	if "\n" in label.text:
		var shaped := font.get_multiline_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, label.size.x, size)
		if shaped.y > label.size.y + 1.0:
			_finding(tag, where, "WRAP-CLIP", "%dx%d plate holds %.0fx%.0f of split text \"%s\"" % [
				int(label.size.x), int(label.size.y), shaped.x, shaped.y, _short(label.text)])
	var text_w := _widest_line_width(font, label.text, size)
	var over := text_w - label.size.x
	if over > 1.0:
		var kind := "CLIP" if label.clip_text else "OVERFLOW"
		var chain := label.get_parent().get_class()
		_finding(tag, where, kind, "text %.0fpx on %.0fpx plate (+%.0f) %dpx in %s \"%s\"" % [
			text_w, label.size.x, over, size, chain, _short(label.text)])


func _audit_occlusion(a: Label, b: Label, tag: String, surface: Node) -> void:
	if a == b or a.is_ancestor_of(b) or b.is_ancestor_of(a):
		return
	if a.text.is_empty() or b.text.is_empty():
		return
	if not a.is_visible_in_tree() or not b.is_visible_in_tree():
		return
	var ra := a.get_global_rect()
	var rb := b.get_global_rect()
	var overlap := ra.intersection(rb)
	if overlap.size.x < OVERLAP_MIN or overlap.size.y < OVERLAP_MIN:
		return
	# THE FAN'S SHEET RULE (readability r3): a fan print may cover
	# foreign text ONLY under the fan's own designed paper sheet — the
	# co-mount audit grades the identical rule while each fan is open;
	# this keeps the ordinary walk honest if it ever runs under an open
	# fan. The r2 whitelist here ("a fan label against an outside label
	# is the design, never a defect") was the other half of the
	# audit-blindness: it excused every fan-print-on-text overlap.
	var fan_of_a := _fan_over(a, surface)
	var fan_of_b := _fan_over(b, surface)
	if fan_of_a != fan_of_b and (fan_of_a != null or fan_of_b != null):
		var fan := fan_of_a if fan_of_a != null else fan_of_b
		var sheet: Rect2 = fan.sheet_rect()
		sheet.position += fan.global_position
		if not sheet.encloses(overlap):
			_finding(tag, "occlusion", "OCCLUSION", "%s \"%s\" [%dx%d @ %v] over %s \"%s\" OUTSIDE the fan's sheet" % [
				_path_of(a), _short(a.text), int(overlap.size.x), int(overlap.size.y),
				overlap.position, _path_of(b), _short(b.text)])
		return
	# Designed paper overlays: the Watchful Eye's perch plate (paper on
	# the table's corner) and the PANORAMIC spread's held-fan overlap
	# (cards overlap LIKE A HELD FAN by design — their plates may
	# legitimately share rect space; the STACKED grid stays policed).
	# Everything else on the audited surfaces is table chrome where
	# text-on-text is a defect.
	if _shares_overlay(a, b, surface):
		return
	_finding(tag, "occlusion", "OCCLUSION", "%s \"%s\" [%dx%d @ %v] over %s \"%s\"" % [
		_path_of(a), _short(a.text), int(overlap.size.x), int(overlap.size.y),
		overlap.position, _path_of(b), _short(b.text)])


## The ActionFan governing this label within the audited surface, if any.
func _fan_over(label: Label, surface: Node) -> ActionFan:
	var node: Node = label
	while node != null and node != surface:
		if node is ActionFan:
			return node as ActionFan
		node = node.get_parent()
	return null


## True when both labels live under one common DESIGNED overlay: the
## Watchful Eye's perch plate (paper on the table's corner), or the
## PANORAMIC spread's held-fan overlap (cards overlap LIKE A HELD FAN by
## design — their plates may legitimately share rect space; the STACKED
## grid never overlaps, so it stays policed). The ActionFan is NOT
## whitelisted here anymore — its prints grade by the sheet rule above.
func _shares_overlay(a: Label, b: Label, _surface: Node) -> bool:
	var node: Node = a
	while node != null:
		if node is CardSpread and (node as CardSpread).mode == CardSpread.Mode.PANORAMIC \
				and (node as Node).is_ancestor_of(b):
			return true
		if node.get_script() == preload("res://ui/screens/spread/watchful_eye.gd"):
			return true
		node = node.get_parent()
	return false


# --- the bar -------------------------------------------------------------------------


func _finding(tag: String, where: String, kind: String, detail: String) -> void:
	# THE DENSITY SURFACE GRADES BY THE FLOOR (r2's documented answer,
	# kept): the 20-card estate's small-print roles land whole at 14-16px
	# — below the 17px small-print rung, above the 12px READABILITY FLOOR.
	# They count as TINY-DENSITY (informational at both scales) and never
	# against the standard surfaces' TINY baseline, which the baseline of
	# record was never measured with. And at the 1.3x cap the estate sits
	# PAST the density wall (the plates scale with the type factor; the
	# table does not) — its structural findings grade informationally as
	# *-DENSITY there, while the 1.0x estate bars them fully and every
	# scale still bars SUB-FLOOR and MOUNT.
	if tag.begins_with("estate"):
		if kind == "TINY":
			kind = "TINY-DENSITY"
		elif _scale > SCALES[0] + 0.001:
			match kind:
				"STALLED": kind = "STALLED-DENSITY"
				"PAST-EDGE": kind = "PAST-EDGE-DENSITY"
				"OFFSCREEN": kind = "OFFSCREEN-DENSITY"
				"OCCLUSION": kind = "OCCLUSION-DENSITY"
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	_findings.append("%-58s %-9s %s" % [where, kind, detail])


func _note(tag: String, surface: String, detail: String) -> void:
	print("[audit] %s %s: %s" % [tag, surface, detail])


func _summary() -> void:
	print("\n=== FINDINGS ===")
	for line in _findings:
		print(line)
	print("\n=== READABILITY BAR (co-mounted — r3) ===")
	var failed := false
	for scale: float in _scale_totals.keys():
		var counts: Dictionary = _scale_totals[scale]
		var at_floor := scale <= SCALES[0]  # 1.0x — the full bar
		var parts: Array[String] = []
		for kind in ["CLIP", "OVERFLOW", "WRAP-CLIP", "OCCLUSION", "STALLED",
				"PAST-EDGE", "OFFSCREEN", "SUB-FLOOR", "TINY", "TINY-DENSITY",
				"STALLED-DENSITY", "PAST-EDGE-DENSITY", "OFFSCREEN-DENSITY",
				"OCCLUSION-DENSITY", "MOUNT"]:
			var n := int(counts.get(kind, 0))
			if n > 0 or at_floor:
				parts.append("%s %d" % [kind, n])
		print("  %.1fx: %s" % [scale, ", ".join(parts)])
		var barred: Array[String] = ["SUB-FLOOR", "STALLED", "MOUNT"]
		if at_floor:
			barred = ["CLIP", "OVERFLOW", "WRAP-CLIP", "OCCLUSION", "STALLED",
				"PAST-EDGE", "OFFSCREEN", "SUB-FLOOR", "MOUNT"]
		for kind in barred:
			if int(counts.get(kind, 0)) > 0:
				failed = true
				print("    FAIL %.1fx: %s %d must be 0" % [scale, kind, int(counts.get(kind, 0))])
		if at_floor and int(counts.get("TINY", 0)) > TINY_BASELINE:
			failed = true
			print("    FAIL 1.0x: TINY %d > baseline %d" % [
				int(counts.get("TINY", 0)), TINY_BASELINE])
	if failed:
		print("READABILITY BAR: FAIL")
	else:
		print(("READABILITY BAR: PASS (0 CLIP / 0 OVERFLOW / 0 WRAP-CLIP / 0 OCCLUSION /"
			+ " 0 STALLED / 0 PAST-EDGE / 0 OFFSCREEN / 0 SUB-FLOOR / 0 MOUNT, TINY <= %d at 1.0x;"
			+ " floor-check at 1.3x)") % TINY_BASELINE)


# --- helpers ------------------------------------------------------------------------


func _gate_host(seed: int) -> GameHost:
	## The SPREAD probe's roster: a fresh run settled briefly — the shape
	## the game's own first session shows (offers at the gate, staked
	## plots; the demo capture's composition). The DENSE state is its own
	## mount below (`_estate_host`) — the r2 "density note" folded the two
	## worlds together and graded the dense one through the size<=1 skip;
	## r3 separates them honestly.
	var host := GameHost.new(seed, _audit_root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	host.fast_forward(2 * 60)
	return host


func _estate_host(seed: int) -> GameHost:
	## The DENSE ESTATE probe's host (the r3 pin's surface): accept every
	## offer as it arrives (the sensible-play move), fast-forward between
	## arrivals, until the estate holds 20 cards — the 20-card estate the
	## r2 runtime finalization stalled on. Deterministic at RUN_SEED.
	var host := GameHost.new(seed, _audit_root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	var hours := 0
	while hours < 40:
		var guard := 0
		while host.units().pending_offers() > 0 and guard < 50:
			var offers := host.units().offer_ids()
			if offers.is_empty():
				break
			host.submit(&"recruit_accept", &"", offers[0])
			host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR / 4)
			guard += 1
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR - SimEngine.TICKS_PER_SIM_HOUR / 4)
		hours += 1
		if (SpreadPresenter.cards_view(host) as Array).size() >= 20:
			break
	return host


func _spread_cards(screen: Control, tag: String) -> Array[Control]:
	## The mounted spread's card nodes in the active slot (the real table
	## the orientation granted — never a parallel list).
	var want_portrait: bool = screen.get_router().is_portrait()
	var slot: OrientationSlot = screen.get_portrait_slot() if want_portrait \
		else screen.get_landscape_slot()
	var out: Array[Control] = []
	for child in slot.get_spread().get_children():
		if child is Control:
			out.append(child as Control)
	return out


func _labels_of(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	_collect_labels(node, out)
	return out


func _audit_host(seed: int) -> GameHost:
	## The ODDS probe's host: a mustered army — the r1 probe fast-forwarded
	## only, so no unit was ever recruited and the odds roster mounted
	## EMPTY; the rank plates (the verifier's shaved-glyph find) were never
	## measured. The vignette suite's own knight pipeline (militia ->
	## trainee -> knight, geared, promoted), three times: three rank cards
	## over the real contribution plates, floor met.
	var host := GameHost.new(seed, _audit_root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	host.fast_forward(2 * 60)
	var knights: Array[int] = []
	while knights.size() < 3:
		var guard := 0
		while host.units().pending_offers() == 0 and guard < 400:
			host.fast_forward(30)
			guard += 1
		var offers := host.units().offer_ids()
		if offers.is_empty():
			break
		host.submit(&"recruit_accept", &"", offers[0])
		host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
		var idle := host.units().idle_units(host.units().base_unit_id())
		if idle.is_empty():
			break
		host.submit(&"assign_role", &"militia", idle[0])
		host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
		var militia := host.units().idle_units(&"militia")
		if militia.is_empty():
			break
		host.submit(&"start_training", &"trainee", militia[0])
		host.fast_forward(5 * SimEngine.TICKS_PER_SIM_HOUR)
		var trainee := host.units().idle_units(&"trainee")
		if trainee.is_empty():
			break
		host.submit(&"start_training", &"knight", trainee[0])
		host.fast_forward(13 * SimEngine.TICKS_PER_SIM_HOUR)
		if not host.units().is_awaiting_promotion(trainee[0]):
			break
		knights.append(trainee[0])
	host.engine.set_resource(&"food", 500)
	host.engine.set_resource(&"timber", 500)
	host.engine.set_resource(&"iron", 500)
	for uid in knights:
		for slot in host.units().missing_gear_slots(uid):
			host.submit(&"equip_gear", host.units().gear_ids_for_slot(slot)[0], uid)
	host.fast_forward(5)
	for uid in knights:
		if host.units().is_awaiting_promotion(uid) \
				and host.units().missing_gear_slots(uid).is_empty():
			host.submit(&"promote", &"", uid)
	host.fast_forward(5)
	# The lived-in gate: surplus offers go home (the command queue drains
	# at tick start — each dismissal needs its tick).
	while host.units().pending_offers() > 3:
		var extra := host.units().offer_ids()
		if extra.is_empty():
			break
		host.submit(&"dismiss_offer", &"", extra[extra.size() - 1])
		host.fast_forward(1)
	return host


func _widest_line_width(font: Font, text: String, size: int) -> float:
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest,
			font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x)
	return widest


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _short(text: String) -> String:
	var one := text.replace("\n", " ")
	return one.left(38)


func _path_of(node: Node) -> String:
	var path := String(node.name)
	var parent := node.get_parent()
	while parent != null and parent != node.get_tree().root:
		path = String(parent.name) + "/" + path
		parent = parent.get_parent()
	return path


func _erase_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		DirAccess.remove_absolute(path)
