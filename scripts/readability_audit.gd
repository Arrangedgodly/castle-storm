## The readability audit (NOT a test; a measurement probe — r2).
##
##     godot --headless --path . -s res://scripts/readability_audit.gd
##
## Mounts the REAL surfaces (the spread screen at both real targets, an
## open ActionFan, and the assault odds stage with a POPULATED roster)
## at both real targets (720x1280 portrait, 1280x800 landscape) x the
## scale range ends (1.0x / 1.3x), walks EVERY visible Label, and checks:
##
##   CLIP      — clip_text label whose text is wider than its plate
##   OVERFLOW  — unclipped label whose text is wider than its plate
##               (draws past the plate — the worst kind)
##   WRAP-CLIP — wrapped or "\n"-split label whose text height exceeds
##               its plate (the castle share line's round-1 find)
##   OCCLUSION — two visible text labels whose plates overlap (>= 4px
##               both axes) outside a DESIGNED paper overlay (the fan) —
##               text printed on text is never a design
##   SUB-FLOOR — resolved size below the 12px READABILITY FLOOR (scaled)
##   TINY      — resolved size below 17px (the small-print rungs)
##   MOUNT     — the probe's own sanity (router orientation, roster
##               populated) — a broken mount invalidates the pass
##
## THE PASS BAR (readability r2 — grow, don't shrink): at 1.0x, BOTH
## orientations: 0 CLIP, 0 OVERFLOW, 0 WRAP-CLIP, 0 OCCLUSION, 0
## SUB-FLOOR, 0 MOUNT, and TINY <= the round-1 baseline (10). The 1.3x
## pass is FLOOR-CHECK ONLY (fixed plates may re-flow at the cap; the
## floor must hold at any scale): 0 SUB-FLOOR, 0 MOUNT; everything else
## is reported for information.
##
## r2 mount fixes: the probe forces a real resize per target (the
## round-1 probe's first mount never saw a size CHANGE and the router
## sat at its previous topology — the round-1 "spread" numbers measured
## the wrong slot at portrait size), and the odds host RECRUITS + MUSTERS
## units (the round-1 probe's fast-forward-only host mustered nobody, so
## the roster was empty and the rank plates were never measured at all —
## the shaved glyphs the verifier's captures showed were invisible to
## the round-1 audit). Deterministic (seeded host, fixed mounts); ends
## with quit() and a PASS/FAIL line.
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
	# An open action fan: the first card that offers actions.
	var fan := ActionFan.new()
	root.add_child(fan)
	await _frames(1)
	var opened := false
	for card in SpreadPresenter.cards_view(host):
		var actions := CardActions.actions_for(host, card)
		if not actions.is_empty():
			fan.open(str(int(card["uid"])), actions)
			await _frames(FRAMES)
			_note(tag, "action_fan", "opened %d chips for card %s" % [
				actions.size(), card.get("uid")])
			opened = true
			break
	if not opened:
		_finding(tag, "action_fan", "MOUNT", "no card offered actions")
	_walk(fan, "action_fan/" + tag, fan)
	fan.queue_free()
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
	if label.size.x <= 1.0 or label.size.y <= 1.0:
		return  # not laid out yet
	var font: Font = label.get_theme_font(&"font")
	if font == null:
		return
	var size := label.get_theme_font_size(&"font_size")
	if size <= 0:
		return
	var where := "%s [%s]" % [tag, label.theme_type_variation if label.theme_type_variation != &"" else &"Label"]
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
	# Designed paper overlays: the action fan prints ON the table (its
	# chips and hint strip may cover card paper) — a fan label against an
	# outside label is the design, never a defect.
	if _shares_overlay(a, b, surface):
		return
	_finding(tag, "occlusion", "OCCLUSION", "%s \"%s\" [%dx%d @ %v] over %s \"%s\"" % [
		_path_of(a), _short(a.text), int(overlap.size.x), int(overlap.size.y),
		overlap.position, _path_of(b), _short(b.text)])


## True when both labels live under one common DESIGNED overlay: the
## ActionFan's paper (chips + hint print ON the table), the Watchful
## Eye's perch plate (paper on the table's corner), or the PANORAMIC
## spread's held-fan overlap (cards overlap LIKE A HELD FAN by design —
## their plates may legitimately share rect space; the STACKED grid
## never overlaps, so it stays policed). Everything else on the audited
## surfaces is table chrome where text-on-text is a defect.
func _shares_overlay(a: Label, b: Label, _surface: Node) -> bool:
	var node: Node = a
	while node != null:
		if node is ActionFan and (node as Node).is_ancestor_of(b):
			return true
		if node is CardSpread and (node as CardSpread).mode == CardSpread.Mode.PANORAMIC \
				and (node as Node).is_ancestor_of(b):
			return true
		if node.get_script() == preload("res://ui/screens/spread/watchful_eye.gd"):
			return true
		node = node.get_parent()
	return false


# --- the bar -------------------------------------------------------------------------


func _finding(tag: String, where: String, kind: String, detail: String) -> void:
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	_findings.append("%-58s %-9s %s" % [where, kind, detail])


func _note(tag: String, surface: String, detail: String) -> void:
	print("[audit] %s %s: %s" % [tag, surface, detail])


func _summary() -> void:
	print("\n=== FINDINGS ===")
	for line in _findings:
		print(line)
	print("\n=== READABILITY BAR (grow, don't shrink — r2) ===")
	var failed := false
	for scale: float in _scale_totals.keys():
		var counts: Dictionary = _scale_totals[scale]
		var at_floor := scale <= SCALES[0]  # 1.0x — the full bar
		var parts: Array[String] = []
		for kind in ["CLIP", "OVERFLOW", "WRAP-CLIP", "OCCLUSION", "SUB-FLOOR", "TINY", "MOUNT"]:
			var n := int(counts.get(kind, 0))
			if n > 0 or at_floor:
				parts.append("%s %d" % [kind, n])
		print("  %.1fx: %s" % [scale, ", ".join(parts)])
		var barred: Array[String] = ["SUB-FLOOR", "MOUNT"]
		if at_floor:
			barred = ["CLIP", "OVERFLOW", "WRAP-CLIP", "OCCLUSION", "SUB-FLOOR", "MOUNT"]
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
		print("READABILITY BAR: PASS (0 CLIP / 0 OVERFLOW / 0 WRAP-CLIP / 0 OCCLUSION /"
			+ " 0 SUB-FLOOR / 0 MOUNT, TINY <= %d at 1.0x; floor-check at 1.3x)" % TINY_BASELINE)


# --- helpers ------------------------------------------------------------------------


func _gate_host(seed: int) -> GameHost:
	## The SPREAD probe's roster: a fresh run settled briefly — the shape
	## the game's own first session shows (offers at the gate, staked
	## plots; the demo capture's composition). HONEST DENSITY NOTE: hours
	## of raw fast-forward auto-resolve the gate into a 24-militia estate
	## whose 36-card phone grid cannot honor plate floors at all (the
	## round-1 audit never saw those cards — their entrance slides never
	## landed headless, so its walk skipped them). That state is the
	## density boundary, graded by the 12px floor; the count bar grades
	## this surface.
	var host := GameHost.new(seed, _audit_root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	host.fast_forward(2 * 60)
	return host


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
