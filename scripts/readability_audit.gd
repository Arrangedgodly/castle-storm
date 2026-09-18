## The readability pass's clip inventory (NOT a test; a measurement probe).
##
##     godot --headless --path . -s res://scripts/readability_audit.gd
##
## Mounts the REAL screens at the two real targets (720x1280 portrait,
## 1280x800 landscape) x the scale range ends (1.0x / 1.3x), walks EVERY
## Label, and measures its text width (real font metrics, the resolved
## applied size) against its granted plate — reporting, per surface:
##
##   CLIP      — clip_text label whose text is wider than its plate
##   OVERFLOW  — unclipped label whose text is wider than its plate
##               (draws past the plate — the worst kind)
##   WRAP-CLIP — autowrap label whose wrapped height exceeds its plate
##   TINY      — resolved size below the readability floor (the small
##               ladder rungs the pass is here to raise)
##
## Output: one line per finding + a per-surface summary. Deterministic
## (seeded host, fixed mounts); the same probe ran BEFORE and AFTER the
## readability pass so the inventory numbers are comparable.
extends SceneTree

const RUN_SEED := 20261103
const AUDIT_ROOT := "user://cs_readability_audit"
const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")
const ASSAULT_STAGE := preload("res://ui/screens/assault/assault_stage.tscn")

const SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),  # phone portrait
	Vector2i(1280, 800),  # Steam Deck landscape
]
const SCALES: Array[float] = [1.0, 1.3]
const TINY_FLOOR := 17  # the readability bar for the smallest rungs
const FRAMES := 30  # enough for the plates-grow verdict cascade to settle

var _findings: Array[String] = []
var _counts := {}


func _initialize() -> void:
	_run()


func _run() -> void:
	print("[audit] start")
	_erase_dir(AUDIT_ROOT)
	for scale: float in SCALES:
		TypeScale.reset()
		TypeScale.apply_factor(scale)
		for size: Vector2i in SIZES:
			root.size = size
			await _frames(FRAMES)
			await create_timer(0.6).timeout  # the router's dwell (0.25s) must pass
			var tag := "%dx%d @ %.1fx" % [size.x, size.y, scale]
			await _audit_spread(tag, size)
			await _audit_assault(tag, size)
	TypeScale.reset()
	root.size = Vector2i(720, 720)
	_summary()


# --- the mounts -------------------------------------------------------------------


func _audit_spread(tag: String, size: Vector2i) -> void:
	print("[audit] mounting spread @ %s" % tag)
	var host := _populated_host(RUN_SEED, 30.0)
	var screen: Control = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = false
	root.add_child(screen)
	await _frames(FRAMES)
	await create_timer(0.6).timeout  # the topology swap's dwell must pass
	await _frames(FRAMES)
	var want_portrait := size.x < size.y
	_note(tag, "spread", "router portrait=%s (want %s)" % [
		screen.get_router().is_portrait(), want_portrait])
	# An open action fan: the first card that offers actions.
	var fan := ActionFan.new()
	root.add_child(fan)
	await _frames(1)
	for card in SpreadPresenter.cards_view(host):
		var actions := CardActions.actions_for(host, card)
		if not actions.is_empty():
			fan.open(str(int(card["uid"])), actions)
			await _frames(FRAMES)
			_note(tag, "action_fan", "opened %d chips for card %s" % [
				actions.size(), card.get("uid")])
			break
	_walk(fan, "action_fan/" + tag)
	fan.queue_free()
	_walk(screen, "spread/" + tag)
	await _frames(2)
	screen.queue_free()
	await _frames(2)


func _audit_assault(tag: String, size: Vector2i) -> void:
	var host := _populated_host(RUN_SEED, 30.0)
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
	_walk(stage, "assault_stage/" + tag)
	stage.queue_free()
	await _frames(2)


# --- the label walk -----------------------------------------------------------------


func _walk(node: Node, tag: String) -> void:
	if node is Label:
		_audit_label(node as Label, tag)
	for child in node.get_children():
		_walk(child, tag)


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
	if size < TINY_FLOOR:
		_finding(where, "TINY", "%dpx \"%s\"" % [size, _short(label.text)])
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		var shaped := font.get_multiline_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, label.size.x, size)
		if shaped.y > label.size.y + 1.0:
			_finding(where, "WRAP-CLIP", "%dx%d plate holds %.0fx%.0f of wrapped text \"%s\"" % [
				int(label.size.x), int(label.size.y), shaped.x, shaped.y, _short(label.text)])
		return
	var text_w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var over := text_w - label.size.x
	if over > 1.0:
		var kind := "CLIP" if label.clip_text else "OVERFLOW"
		var chain := label.get_parent().get_class()
		_finding(where, kind, "text %.0fpx on %.0fpx plate (+%.0f) %dpx in %s \"%s\"" % [
			text_w, label.size.x, over, size, chain, _short(label.text)])


# --- bookkeeping --------------------------------------------------------------------


func _finding(where: String, kind: String, detail: String) -> void:
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	_findings.append("%-58s %-9s %s" % [where, kind, detail])


func _note(tag: String, surface: String, detail: String) -> void:
	print("[audit] %s %s: %s" % [tag, surface, detail])


func _summary() -> void:
	print("\n=== READABILITY INVENTORY ===")
	for line in _findings:
		print(line)
	var parts: Array[String] = []
	for kind in ["CLIP", "OVERFLOW", "WRAP-CLIP", "TINY"]:
		parts.append("%s %d" % [kind, int(_counts.get(kind, 0))])
	print("TOTALS: " + ", ".join(parts))


# --- helpers ------------------------------------------------------------------------


func _populated_host(seed: int, hours: float) -> GameHost:
	var host := GameHost.new(seed, AUDIT_ROOT)
	host.boot(0)
	host.fast_forward(int(hours * 60.0))
	return host


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _short(text: String) -> String:
	var one := text.replace("\n", " ")
	return one.left(38)


func _erase_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		DirAccess.remove_absolute(path)
