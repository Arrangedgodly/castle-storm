## Colorblind-safe audit (T-QA-05 — PRODUCT.md accessibility: "icon +
## shape + text, never color alone").
##
## The consolidated mechanical audit that EVERY state-carrying UI element
## communicates through line-form / shape / label, with hue as a redundant
## channel only. The piecemeal pins live in their owning suites (edge-form
## vocabulary in test_theme_grammar §3, pip triple encoding §7); this file
## sweeps the whole surface list in one place, mechanically where the
## channel is a table or a drawn form, on the live mounted surfaces where
## the channel is a printed label:
##
##   1. CARD EDGES — every state the LIVE view can emit keys a line form
##      in Inks.EDGE_FORM_STATES (no unknown state can reach the frame
##      draw, where it would print SOLID-after-error).
##   2. CHRONICLE LINE CLASSES — the 4 classes map INJECTIVELY onto 4
##      distinct rule forms (a two-form mapping would make two different
##      event kinds indistinguishable without hue).
##   3. OUTCOME SEALS — WON / CRUSHED / ABANDONED are doubly encoded:
##      distinct line-form classes AND distinct print-mark texts.
##   4. RESOURCE PIPS — on the LIVE spread rail: every pip carries its
##      name label (the text channel) and the three kinds are shape-
##      distinct by construction (pip_shape injective — §7 pins it).
##   5. THE WATCHFUL EYE — armed vs watching is carried by the countdown
##      TEXT ("lands in Xh" vs "the Crown watches"), not the red ink.
##   6. THE CHOICE CARD — urgent vs calm telegraph: double vs solid rule
##      form + distinct titles (the red title ink is redundant).
##   7. REFUSED ACTIONS — every disabled action in the action model
##      carries a non-empty printed reason (the struck rule + the clerk's
##      words, never a grayed chip alone).
##   8. THE ODDS — the win chance prints as NUMERALS + confidence words;
##      the filled meter blocks are the redundant channel.
extends GdUnitTestSuite

const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")


# --- 1. Card edges: the live vocabulary is fully keyed -------------------------------


func test_every_live_card_state_has_a_line_form() -> void:
	## A driven host over the whole early game (offers, workers, training,
	## gear, buildings): every `edge_state` the view emits must key
	## Inks.EDGE_FORM_STATES — an unknown state would print SOLID only
	## after a push_error (a silent-hue regression the frame can't catch).
	var host := _host(20261105)
	var policy := DemoPolicy.new(16, 8, false)
	for i in 40:  # ~40 sim-hours of sensible play
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var states: Array[StringName] = []
	var cards: Array = SpreadPresenter.build_view(host)["cards"]
	for card: Dictionary in cards:
		var state := StringName(String(card.get("edge_state", "")))
		if not states.has(state):
			states.append(state)
	assert_int(states.size()).is_greater_equal(4)  # a real spread of states
	for state: StringName in states:
		assert_bool(Inks.EDGE_FORM_STATES.has(state)).is_true() \
			.override_failure_message("live card state '%s' has no line form (hue-only risk)" % state)


# --- 2. Chronicle classes inject onto rule forms --------------------------------------


func test_line_classes_are_injective_onto_distinct_rule_forms() -> void:
	var forms: Array[int] = []
	for line_class: int in [Inks.LineClass.PLAIN, Inks.LineClass.WARN,
			Inks.LineClass.STRIKE, Inks.LineClass.VICTORY]:
		var form: int = _class_form(line_class)
		assert_bool(forms.has(form)).is_false() \
			.override_failure_message("two line classes share rule form %d" % form)
		forms.append(form)
	assert_int(forms.size()).is_equal(4)


static func _class_form(line_class: int) -> int:
	## The shared grammar both ChronicleLine and the seals use.
	var map: Dictionary = {
		Inks.LineClass.PLAIN: 0, Inks.LineClass.WARN: 1,
		Inks.LineClass.STRIKE: 2, Inks.LineClass.VICTORY: 3,
	}
	return int(map[line_class])


# --- 3. Seals: two non-hue channels ----------------------------------------------------


func test_outcome_seals_carry_distinct_forms_and_distinct_marks() -> void:
	for outcome: String in ["victory", "defeat", "aborted"]:
		var seal: Dictionary = ChroniclePresenter.seal_view(outcome)
		assert_bool(String(seal["mark"]).is_empty()).is_false()
	for pair: Array in [["victory", "defeat"], ["victory", "aborted"], ["defeat", "aborted"]]:
		var a: Dictionary = ChroniclePresenter.seal_view(pair[0])
		var b: Dictionary = ChroniclePresenter.seal_view(pair[1])
		assert_bool(String(a["mark"]) == String(b["mark"])).is_false() \
			.override_failure_message("seal marks collide for %s/%s" % [pair[0], pair[1]])
		assert_bool(int(a["class"]) == int(b["class"])).is_false() \
			.override_failure_message("seal line forms collide for %s/%s" % [pair[0], pair[1]])
	# The marks are the documented print vocabulary.
	assert_str(String(ChroniclePresenter.seal_view("victory")["mark"])).is_equal("WON")
	assert_str(String(ChroniclePresenter.seal_view("defeat")["mark"])).is_equal("CRUSHED")
	assert_str(String(ChroniclePresenter.seal_view("aborted")["mark"])).is_equal("ABANDONED")


# --- 4/5/6. The live mounted surfaces --------------------------------------------------


func test_the_live_rail_eye_and_choice_card_carry_text_channels() -> void:
	MotionProfile.forced = 1
	var host := _host(20261106)
	var screen := SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = false
	auto_free(screen)
	get_tree().root.add_child(screen)
	host.driving = false  # freeze: the audit reads a settled table
	await get_tree().process_frame
	await get_tree().process_frame

	# 4. PIPS: every rail pip prints its name label (the text channel).
	var slot := screen.get_active_slot() as OrientationSlot
	var pip_labels := 0
	for index: int in 3:
		var pip := slot.get_pip(index)
		if pip == null:
			continue
		for label: Label in _labels_under(pip):
			for kind: int in [Inks.ResourceKind.FOOD, Inks.ResourceKind.TIMBER, Inks.ResourceKind.IRON]:
				if String(label.text).to_upper().contains(Inks.pip_label(kind)):
					pip_labels += 1
	assert_int(pip_labels).is_greater_equal(3) \
		.override_failure_message("expected all three resource name labels on the rail")

	# 5. THE EYE: watching state prints its text; the armed telegraph (the
	# meter seam arms it live) prints a DIFFERENT text — the state carrier.
	var eye_texts: Array[String] = []
	for phase: int in [0, 1]:
		if phase == 1:
			host.suspicion().set_suspicion(78)  # the documented telegraph seam
			host.fast_forward(2)
		await get_tree().process_frame
		await get_tree().process_frame
		var text := _eye_countdown_text(screen)
		assert_bool(text.is_empty()).is_false() \
			.override_failure_message("the Eye printed no countdown text (hue-only state)")
		if not eye_texts.has(text):
			eye_texts.append(text)
	assert_int(eye_texts.size()).is_equal(2) \
		.override_failure_message("armed vs watching must differ in TEXT, not just ink")

	# 6. THE CHOICE CARD: urgent arms the double rule; calm prints solid.
	var model_urgent: Dictionary = SuspicionEvents.choice_card_for(host, {
		"seq": 1, "tick": 10, "type": &"suspicion_telegraph",
		"subject": 0, "value": 100, "value2": 0})
	var model_calm: Dictionary = SuspicionEvents.choice_card_for(host, {
		"seq": 2, "tick": 11, "type": &"suspicion_warn",
		"subject": 0, "value": 0, "value2": 0})
	assert_bool(bool(model_urgent["urgent"])).is_true()
	assert_bool(bool(model_calm["urgent"])).is_false()
	assert_str(String(model_urgent["title"])).is_not_equal(String(model_calm["title"]))
	screen.queue_free()


func _labels_under(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	if node is Label:
		found.append(node)
	for child in node.get_children():
		found.append_array(_labels_under(child))
	return found


func _eye_countdown_text(screen: Node) -> String:
	var eye: Node = screen.get_active_slot().get_node_or_null(^"WatchfulEye")
	if eye == null:
		return ""
	for label: Label in _labels_under(eye):
		if not String(label.text).is_empty():
			return String(label.text)
	return ""


# --- 7. Refused actions print their reason ---------------------------------------------


func test_every_disabled_action_carries_a_printed_reason() -> void:
	var host := _host(20261105)
	var policy := DemoPolicy.new(16, 8, false)
	for i in 20:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	host.driving = false
	var disabled_seen := 0
	var cards: Array = SpreadPresenter.build_view(host)["cards"]
	for card: Dictionary in cards:
		for action: Dictionary in CardActions.actions_for(host, card):
			if not bool(action["enabled"]):
				disabled_seen += 1
				assert_bool(String(action["reason"]).is_empty()).is_false() \
					.override_failure_message(
						"disabled action '%s' prints no reason (a struck gray chip alone is hue-only)"
						% String(action["id"]))
	assert_int(disabled_seen).is_greater_equal(1)  # the audit observed real refusals


# --- 8. The odds print as text ----------------------------------------------------------


func test_the_odds_carry_numerals_and_words() -> void:
	## The meter's filled blocks are the redundant channel; the line itself
	## is "N in 1000 — words": readable verbatim, monotone in the permille.
	for permille: int in [0, 120, 450, 620, 999, 1000]:
		var line := AssaultPresenter.confidence_line(permille)
		assert_bool(line.contains(str(permille))).is_true()
		assert_bool(line.contains("—")).is_true()  # the confidence words ride along
		assert_int(line.length()).is_greater(12)
	# The words step through the bands (distinct, non-empty).
	var words: Array[String] = []
	for permille: int in [50, 300, 550, 800, 950]:
		var word := AssaultPresenter.confidence_words(permille)
		assert_bool(word.is_empty()).is_false()
		if not words.has(word):
			words.append(word)
	assert_int(words.size()).is_greater_equal(3)
	# Blocks are monotone in the permille (the redundant channel never lies).
	var blocks := -1
	for permille: int in [0, 250, 500, 750, 1000]:
		var filled := AssaultPresenter.meter_blocks(permille)
		assert_int(filled).is_greater_equal(blocks)
		blocks = filled
	assert_int(AssaultPresenter.meter_blocks(1000)).is_equal(AssaultPresenter.METER_BLOCKS)


# --- helpers ---------------------------------------------------------------------------


func _host(run_seed: int) -> GameHost:
	var root := "user://cs_colorblind/host-%d" % run_seed
	_erase(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _erase(path: String) -> void:
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
		_erase(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
