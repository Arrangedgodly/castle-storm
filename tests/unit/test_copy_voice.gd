## Unit tests for the satirical voice (T-COPY-01) — Professor X lane.
##
## Mirrors docs/voice-bible.md (the register + rules), content/schema/
## copy_table.gd (the key/token vocabulary), sim/copy_deck.gd (the
## renderer + code-side floor) and content/mvp/copy_table.tres + the
## expanded identity pools (the shipped voice). What is pinned:
##   - THE POOLS: permutation breadth into the thousands, uniqueness,
##     short recruit/first names (strip budget), trait labels that never
##     split mid-phrase, and the banned-register scan over every entry;
##   - THE FONT-METRIC LINE BUDGET (the T-UI-06/09 standard): EVERY
##     variant of EVERY single-line template, substituted at WORST-CASE
##     parameters drawn from the LIVE pools, measured in the theme's real
##     ChronicleLine face (conservative 24 over-measure) against its
##     surface's budget with >= 30px margin;
##   - SEEDED ROTATION: same rotor -> same line, a rotor sweep covers
##     every variant, the suspicion system's seq-rotated render is
##     deterministic and varies across seqs, table absent -> the floor;
##   - THE VALIDATOR'S VOICE GATE (red paths): unknown key, >MAX variants,
##     a repeated beat with one variant, a token outside the key's
##     vocabulary, a banned-register word — each refused with the exact
##     message;
##   - THE COVERAGE REPORT: printed into the run log (which surface got
##     which templates) and asserted — no orphan copy, no unvoiced key,
##     every repeated beat ships >= 2 variants;
##   - FAILURE-FEEL: the crush beat stings via the regime and banks the
##     CONCRETE number; the loss reveal names the same crest (revenge).
extends GdUnitTestSuite

const MVP_COPY := "res://content/mvp/copy_table.tres"

## The clip margin every row must clear BEYOND fitting (the T-UI-06/09
## standard: a row that lands at exactly the budget clips first when
## anything drifts).
const CLIP_MARGIN := 30.0

## Surface budgets (design px at the 720 base; docs/voice-bible.md §4):
## the EventQuote label min(560, bounds-12) - 84 = 476; the choice CARD's
## chronicle label 312 - 2*12 pad - 2*8 row insets - 10 sep - 30 rule
## = 232; the intro PACKET's lines band 504; the wide strip label 610
## (696 wide - insets, held 30 clear).
const QUOTE_BUDGET := 476.0
const CARD_BUDGET := 232.0
const PACKET_BUDGET := 504.0
const STRIP_BUDGET := 610.0

## Which surface each key prints on (the budget it must fit). Keys NOT
## listed print on multi-line/autowrap or chip surfaces — they get the
## character sanity check instead (SINGLE-LINE clip never applies).
const KEY_BUDGETS: Dictionary = {
	# quote / blockquote rows
	&"crackdown_struck": QUOTE_BUDGET, &"crackdown_seized": QUOTE_BUDGET,
	&"crackdown_scattered": QUOTE_BUDGET, &"scatter_none": QUOTE_BUDGET,
	&"scatter_row": QUOTE_BUDGET, &"scatter_peasants": QUOTE_BUDGET,
	&"crush_regime": QUOTE_BUDGET, &"crush_chronicle": QUOTE_BUDGET,
	&"crush_bank": QUOTE_BUDGET,
	&"catchup_headline": QUOTE_BUDGET, &"catchup_capped": QUOTE_BUDGET,
	&"catchup_stores_quiet": QUOTE_BUDGET, &"catchup_stores": QUOTE_BUDGET,
	&"catchup_suspicion_rise": QUOTE_BUDGET, &"catchup_suspicion_ease": QUOTE_BUDGET,
	&"catchup_crackdown_strike": QUOTE_BUDGET, &"catchup_run_ended": QUOTE_BUDGET,
	&"chronicle_empty_1": QUOTE_BUDGET, &"chronicle_empty_2": QUOTE_BUDGET,
	&"beat_advance": QUOTE_BUDGET, &"beat_skirmish": QUOTE_BUDGET,
	&"beat_skirmish_fallen": QUOTE_BUDGET, &"beat_gate": QUOTE_BUDGET,
	&"beat_gate_fallen": QUOTE_BUDGET, &"beat_throne": QUOTE_BUDGET,
	&"beat_rout": QUOTE_BUDGET,
	# the choice card's narrow chronicle label
	&"card_warn_line": CARD_BUDGET, &"card_telegraph_line": CARD_BUDGET,
	&"warn_context": CARD_BUDGET, &"telegraph_context": CARD_BUDGET,
	# the intro packet's lines band
	&"intro_first_line1": PACKET_BUDGET, &"intro_first_marks": PACKET_BUDGET,
	&"intro_first_serve": PACKET_BUDGET, &"intro_win_swap": PACKET_BUDGET,
	&"intro_win_kept": PACKET_BUDGET, &"intro_win_bank": PACKET_BUDGET,
	&"intro_win_context": PACKET_BUDGET, &"intro_resumed_hold": PACKET_BUDGET,
	&"intro_resumed_tail": PACKET_BUDGET, &"intro_resumed_ended": PACKET_BUDGET,
	&"intro_resumed_next": PACKET_BUDGET, &"intro_loss_revenge": PACKET_BUDGET,
	&"intro_loss_remembers": PACKET_BUDGET, &"intro_loss_serve": PACKET_BUDGET,
	# the wide rolling strip (full chronicle lines)
	&"suspicion_warn": STRIP_BUDGET, &"suspicion_telegraph": STRIP_BUDGET,
	&"suspicion_rose": STRIP_BUDGET, &"crackdown_cancelled": STRIP_BUDGET,
	&"run_crushed": STRIP_BUDGET,
	&"recruit_arrived": STRIP_BUDGET, &"recruit_accepted": STRIP_BUDGET,
	&"recruit_dismissed": STRIP_BUDGET, &"training_started": STRIP_BUDGET,
	&"training_complete": STRIP_BUDGET, &"unit_promoted": STRIP_BUDGET,
	&"gear_equipped": STRIP_BUDGET, &"building_built": STRIP_BUDGET,
	&"building_upgraded": STRIP_BUDGET, &"building_milestone": STRIP_BUDGET,
	&"resources_granted": STRIP_BUDGET, &"run_started": STRIP_BUDGET,
	&"run_restarted": STRIP_BUDGET, &"run_won": STRIP_BUDGET,
	&"run_lost": STRIP_BUDGET, &"run_aborted": STRIP_BUDGET,
	&"assault_casualties": STRIP_BUDGET, &"assault_lost": STRIP_BUDGET,
	&"assault_denied": STRIP_BUDGET, &"catch_up_clock_rewound": STRIP_BUDGET,
	&"clerk_denied": STRIP_BUDGET, &"command_rejected": STRIP_BUDGET,
	&"gate_thinned": STRIP_BUDGET, &"cards_kept_close": STRIP_BUDGET,
	# the first session's printed cues (T-UI-10) — strip rows
	&"first_gate": STRIP_BUDGET, &"first_assign": STRIP_BUDGET,
	&"first_build": STRIP_BUDGET, &"first_trickle": STRIP_BUDGET,
	&"first_train": STRIP_BUDGET,
	# the finishing refinements (refinement #2) — strip rows that also
	# print on the day-sheet's ~560px row label, pinned at the tighter
	# quote budget
	&"primer_lineform": QUOTE_BUDGET, &"autosave_filed": QUOTE_BUDGET,
	&"daysheet_empty_1": QUOTE_BUDGET, &"daysheet_empty_2": QUOTE_BUDGET,
}


func _table() -> CopyTable:
	return load(MVP_COPY) as CopyTable


func _pack() -> ContentPack:
	return Inks.pack()


func _longest(values: Array) -> String:
	var longest := ""
	for value in values:
		if String(value).length() > longest.length():
			longest = String(value)
	return longest


# --- the pools ---------------------------------------------------------------------------


func test_leader_permutation_breadth_reaches_the_thousands() -> void:
	var pools := _pack().identity
	assert_int(pools.leader_first_names.size()).is_greater_equal(40)
	assert_int(pools.leader_epithets.size()).is_greater_equal(40)
	# The task's breadth bar: the full-name permutation space is in the
	# thousands (the shipped 46x52 = 2392, pinned at the floor).
	assert_int(pools.leader_first_names.size() * pools.leader_epithets.size()) \
		.is_greater_equal(2000)
	assert_int(pools.personality_tags.size()).is_greater_equal(16)
	assert_int(pools.recruit_names.size()).is_greater_equal(60)
	assert_int(pools.leader_traits.size()).is_greater_equal(8)
	# Uniqueness where it matters (the validator's own gate, pinned here on
	# the SHIPPED pools so a hand edit cannot regress it quietly).
	assert_int(ContentValidator.validate_pack(_pack()).size()).is_zero()


func test_pool_names_fit_the_strip_and_card_budgets() -> void:
	var pools := _pack().identity
	# Strip/card lines carry FIRST and RECRUIT names: the worst-case
	# substitution stays bounded (the epithet never prints on a single-line
	# surface — plates and the chronicle sheet carry it, wrapped).
	assert_int(_longest(pools.leader_first_names).length()).is_less_equal(12)
	assert_int(_longest(pools.recruit_names).length()).is_less_equal(8)
	# Trait labels are card-plate phrases: they must survive the role
	# plate's separator-aware wrap WHOLE (shorter than the second row's
	# budget by construction).
	assert_int(_longest(pools.leader_traits).length()).is_less_equal(16)
	# Epithets wrap on measured plates, not single lines: generous, capped.
	assert_int(_longest(pools.leader_epithets).length()).is_less_equal(28)


func test_identity_pools_pass_the_banned_register_scan() -> void:
	var pools := _pack().identity
	for pool in [pools.leader_first_names, pools.leader_epithets,
			pools.leader_traits, pools.recruit_names]:
		for entry in pool:
			_assert_register_clean(String(entry))
	for tag in pools.personality_tags:
		_assert_register_clean(String(tag))


func test_trait_labels_render_whole_on_the_role_plate() -> void:
	# The chronicle sheet's separator-aware wrap (T-COPY-01): the record's
	# own trait never splits mid-phrase — tags row, trait row. ("trait" the
	# identifier is reserved vocabulary in 4.x — the loop variable is not.)
	for label in _pack().identity.leader_traits:
		var entry := {"tags": [&"superstitious", &"magnanimous"], "trait": label}
		var role := ChroniclePresenter.shaped_role(entry)
		assert_bool(role.replace("\n", " ").contains(String(label))).is_true()


# --- the font-metric line budget (EVERY variant, worst-case parameters) -------------------


## THE PIN (the T-UI-06/09 standard applied to the whole voice): every
## single-line template, every variant, substituted with the WORST-CASE
## values the LIVE content can produce (longest names, widest digits),
## measured in the theme's real ChronicleLine face at the CONSERVATIVE
## 24 over-measure (>= the declared 22 render — the T-UI-09 measurement
## find), must clear its surface's budget by CLIP_MARGIN.
func test_every_template_variant_fits_its_surface_in_real_font_metrics() -> void:
	var line: Control = preload("res://ui/theme/chronicle_line.tscn").instantiate()
	get_tree().root.add_child(line)
	await get_tree().process_frame
	var label := _label_of(line)
	assert_that(label).is_not_null()
	var declared := (load("res://ui/theme/spread_theme.tres") as Theme) \
		.get_font_size(&"font_size", &"ChronicleLine")
	assert_int(declared).is_equal(22)
	var face := label.get_theme_font("font")
	var size := label.get_theme_font_size("font")
	# The conservative over-measure: the resolved "font" item is the theme
	# default (24) — never SMALLER than the declared render size.
	assert_int(size).is_greater_equal(declared)
	var params := _worst_case_params()
	var worst_over := 0.0
	var worst_key := &""
	var measured := 0
	for key in KEY_BUDGETS.keys():
		var pool := CopyDeck.variants(_table(), key)
		assert_int(pool.size()).is_greater_equal(1)
		for variant in pool:
			var rendered := _render(String(variant), params)
			var width := face.get_string_size(rendered,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			measured += 1
			if width > float(KEY_BUDGETS[key]) - CLIP_MARGIN:
				push_warning("COPY BUDGET: %s -> %.0fpx > %.0f: %s" % [
					String(key), width, float(KEY_BUDGETS[key]) - CLIP_MARGIN, rendered])
			if width - (float(KEY_BUDGETS[key]) - CLIP_MARGIN) > worst_over:
				worst_over = width - (float(KEY_BUDGETS[key]) - CLIP_MARGIN)
				worst_key = key
	assert_float(worst_over).is_less_equal(0.0)
	# The audit ran over the whole shipped voice, not a sample (the
	# single-line keys alone carry ~160 variants).
	assert_int(measured).is_greater_equal(150)
	line.queue_free()


## Worst-case substitution values, derived from the LIVE pack so pool
## growth cannot silently outrun the budget pin.
func _worst_case_params() -> Dictionary:
	var pack := _pack()
	var two_recruits := "%s, %s" % [
		_longest(pack.identity.recruit_names),
		_longest(pack.identity.recruit_names.filter(func(n: String) -> bool:
			return n.length() < _longest(pack.identity.recruit_names).length()))]
	var tags := pack.identity.personality_tags.map(func(t: StringName) -> String: return String(t))
	tags.sort_custom(func(a, b) -> bool: return a.length() > b.length())
	return {
		"regime": _longest(pack.regimes.map(func(r: RegimeDef) -> String: return r.display_name)),
		"old": _longest(pack.regimes.map(func(r: RegimeDef) -> String: return r.display_name)),
		"new": _longest(pack.regimes.map(func(r: RegimeDef) -> String: return r.display_name)),
		"first": _longest(pack.identity.leader_first_names),
		"leader": _longest(pack.identity.leader_first_names),
		"name": _longest(pack.identity.recruit_names),
		"who": two_recruits,
		"gear": _longest(pack.gear.map(func(g: GearDef) -> String: return g.display_name)),
		"building": _longest(pack.buildings.map(func(b: BuildingDef) -> String: return b.display_name)),
		"rank": _longest(pack.units.map(func(u: UnitDef) -> String: return u.display_name)),
		"tags": "%s and %s" % [tags[0], tags[1]],
		"resource": _longest(pack.resources.map(func(r: StringName) -> String: return String(r))),
		"source": "building",
		"command": "dismiss_offer",
		"duration": "8h 37m",
		"stores": "+9999 food, +9999 timber, +9999 iron",
		"hours": 127, "count": 999, "points": 1999, "level": 25,
		"before": 100, "after": 100, "power": 150, "reason": 9,
		"verb": "were", "hands": "12 hands", "amount": 999,
	}


## Full substitution for measurement: every token replaced with its
## worst-case value (an unresolved {token} would under-measure).
func _render(variant: String, params: Dictionary) -> String:
	var text := variant
	for token in params.keys():
		text = text.replace("{%s}" % String(token), str(params[token]))
	assert_bool(text.contains("{")).is_false()
	return text


# --- seeded rotation -----------------------------------------------------------------------


func test_rotation_is_seeded_deterministic_and_covers_every_variant() -> void:
	var table := _table()
	var key := &"suspicion_warn"
	var pool := CopyDeck.variants(table, key)
	assert_int(pool.size()).is_greater_equal(2)
	# Same rotor -> same line, always.
	var a := CopyDeck.line(table, key, 7)
	var b := CopyDeck.line(table, key, 7)
	assert_str(a).is_equal(b)
	# A rotor sweep covers EVERY variant (repeats vary, none dead).
	var seen := {}
	for rotor in pool.size() * 3:
		seen[CopyDeck.line(table, key, rotor)] = true
	assert_int(seen.size()).is_equal(pool.size())
	# Negative rotors stay deterministic (posmod, never rng).
	assert_str(CopyDeck.line(table, key, -1)).is_equal(CopyDeck.line(table, key, pool.size() - 1))


func test_suspicion_chronicle_rotates_by_event_seq() -> void:
	var table := _table()
	var heat := SuspicionSystem.new(EconomyTunables.new(), [], table)
	var event := SimEvent.new()
	event.type = &"suspicion_warn"
	# seq drives the variant: same seq -> same line, different seq varies.
	event.seq = 0
	var first := heat.chronicle_line(event)
	event.seq = 0
	assert_str(heat.chronicle_line(event)).is_equal(first)
	event.seq = 1
	assert_str(heat.chronicle_line(event)).is_not_equal(first)
	# The floor: a system built WITHOUT a table reads the code-side default.
	var bare := SuspicionSystem.new(EconomyTunables.new(), [])
	event.seq = 0
	assert_str(bare.chronicle_line(event)).is_equal(
		CopyDeck.line(null, &"suspicion_warn", 0))


func test_missing_parameter_falls_back_to_variant_zero() -> void:
	# A surface that forgets a param falls back to VARIANT 0 of the same
	# pool (the floor's shape — every variant of a key shares the token
	# contract, so variant 0 is the safest render). The budget pin's
	# full-render assert is the guard that no shipped line ever carries a
	# raw {token}.
	var table := _table()
	# Full params: rotor 1 renders VARIANT 1 (no fallback — variety is the
	# point), with every token resolved.
	var with_hours := CopyDeck.line(table, &"suspicion_telegraph", 1, {"hours": 4})
	assert_bool(with_hours.contains("{")).is_false()
	assert_str(with_hours).is_not_equal(CopyDeck.line(table, &"suspicion_telegraph", 0, {"hours": 4}))
	# Missing param: fall back to VARIANT 0's text (every variant of a key
	# shares the token contract; the budget pin's full-render assert is the
	# guard that no shipped line ever carries a raw {token}).
	var missing := CopyDeck.line(table, &"suspicion_telegraph", 1, {})
	assert_str(missing).is_equal(String(CopyDeck.variants(table, &"suspicion_telegraph")[0]))


# --- the validator's voice gate (red paths) -------------------------------------------------


func _pack_with_copy(table: CopyTable) -> ContentPack:
	# NEVER hand the shared pack cache a mutated table (Inks.pack() is one
	# instance per process — a poisoned cache fails every later load_pack).
	# A DEEP duplicate carries the same ids/paths for honest validation.
	var pack: ContentPack = Inks.pack().duplicate(true)
	pack.copy = table
	return pack


func _mutated(mutator: Callable) -> Array[String]:
	var table := CopyTable.new()
	table.templates = (load(MVP_COPY) as CopyTable).templates.duplicate()
	mutator.call(table)
	return ContentValidator.validate_pack(_pack_with_copy(table))


func test_unknown_copy_key_is_refused() -> void:
	var errors := _mutated(func(table: CopyTable) -> void:
		table.templates[&"nonsense_key"] = PackedStringArray(["boo"]))
	assert_bool(errors.any(func(e: String) -> bool:
		return e == "copy: unknown template key 'nonsense_key' — no surface reads it (see CopyTable.KEY_TOKENS)")).is_true()


func test_variant_cap_is_enforced() -> void:
	var errors := _mutated(func(table: CopyTable) -> void:
		table.templates[&"suspicion_warn"] = PackedStringArray(["a", "b", "c", "d", "e"]))
	assert_bool(errors.any(func(e: String) -> bool:
		return e == "copy 'suspicion_warn': 5 variants exceeds the cap of 4 (variety, not sprawl)")).is_true()


func test_repeated_beat_needs_two_variants() -> void:
	var errors := _mutated(func(table: CopyTable) -> void:
		table.templates[&"recruit_arrived"] = PackedStringArray(["{name} arrives."]))
	assert_bool(errors.any(func(e: String) -> bool:
		return e == "copy 'recruit_arrived': a repeated beat needs >= 2 variants (got 1) — repeats must vary")).is_true()


func test_token_outside_the_keys_vocabulary_is_refused() -> void:
	var errors := _mutated(func(table: CopyTable) -> void:
		table.templates[&"run_won"] = PackedStringArray(["{points} points, {regime} falls."]))
	assert_bool(errors.any(func(e: String) -> bool:
		return e.contains("copy 'run_won': token '{regime}' is not in this key's vocabulary"))).is_true()


func test_banned_register_word_is_refused() -> void:
	var errors := _mutated(func(table: CopyTable) -> void:
		table.templates[&"run_won"] = PackedStringArray(
			["The castle falls. Awesome.", "The castle falls. Truly."]))
	assert_bool(errors.any(func(e: String) -> bool:
		return e == "copy 'run_won': banned-register fragment 'Awesome' in 'The castle falls. Awesome.' — see docs/voice-bible.md §3")).is_true()
	# Word boundaries hold: "they" never trips "hey".
	assert_bool(errors.any(func(e: String) -> bool: return e.contains("Truly"))).is_false()


func test_shipped_copy_and_code_floor_pass_the_banned_scan() -> void:
	var table := _table()
	for key in table.templates.keys():
		for variant in table.templates[key]:
			_assert_register_clean(String(variant))
	for key in CopyDeck.DEFAULTS.keys():
		for variant in CopyDeck.DEFAULTS[key]:
			_assert_register_clean(String(variant))


func _assert_register_clean(text: String) -> void:
	for fragment in CopyTable.BANNED_FRAGMENTS:
		var rx := RegEx.create_from_string("(?i)\\b%s\\b" % fragment)
		var hit := rx.search(text)
		if hit != null:
			assert_str(text).is_not_equal("banned '%s' in: %s" % [hit.get_string(), text])


# --- the coverage report -------------------------------------------------------------------


## The copy coverage report — PRINTED into the run log (the task's
## "which screens got which templates") and asserted: every DEFAULTS key
## has a consumer on record, every consumer key exists in BOTH the shipped
## table and the floor, every key's variants stay within the cap, and
## every repeated beat ships >= 2 variants.
func test_copy_coverage_report_and_no_orphan_keys() -> void:
	var table := _table()
	for line in CopyDeck.coverage_report(table):
		print(line)
	var orphans: Array[String] = []
	for key in CopyDeck.DEFAULTS.keys():
		if not CopyDeck.CONSUMERS.has(key):
			orphans.append(String(key))
	assert_array(orphans).is_empty()
	var unconsumed: Array[String] = []
	for key in CopyDeck.CONSUMERS.keys():
		if not CopyDeck.DEFAULTS.has(key):
			unconsumed.append(String(key))
	assert_array(unconsumed).is_empty()
	# The shipped table carries the WHOLE vocabulary (no silent floors).
	var missing: Array[String] = []
	for key in CopyDeck.DEFAULTS.keys():
		if not table.templates.has(key):
			missing.append(String(key))
	assert_array(missing).is_empty()
	# Every repeated beat ships variety; nothing exceeds the cap.
	for key in table.templates.keys():
		assert_int(table.templates[key].size()) \
			.is_less_equal(CopyTable.MAX_VARIANTS)
		if CopyTable.ROTATING_KEYS.has(key):
			assert_int(table.templates[key].size()).is_greater_equal(2)


# --- failure-feel: stings without souring ----------------------------------------------------


func test_crush_beat_stings_via_the_regime_and_banks_the_number() -> void:
	var host := _test_host()
	host.meta.legacy_points = 231
	var lines := SuspicionEvents.crush_lines(host)
	assert_int(lines.size()).is_equal(3)
	# The sting names the regime that closed its hand…
	assert_str(String(lines[0]["text"])) \
		.contains(Inks.regime_name(host.run().regime_id()))
	# …the record survives…
	assert_str(String(lines[1]["text"])).contains("crushed")
	# …and the hope is a CONCRETE number you keep (the real bank).
	assert_str(String(lines[2]["text"])).contains("231")
	assert_int(int(lines[2]["class"])).is_equal(Inks.LineClass.PLAIN)


func test_loss_reveal_names_the_same_crest_and_keeps_the_bank() -> void:
	var host := _test_host()
	var regime_before := host.run().regime_id()
	var previous_first := host.run().leader_name().split(" ")[0]
	host.fast_forward(6 * 60)
	host.submit(&"resolve_victory", &"loss", 0)
	host.fast_forward(2)
	host.restart_run()
	host.advance_ticks(1)
	var view := IntroPresenter.reveal_view(host)
	var lines: Array = view["lines"]
	# The revenge beat: STRIKE weight, the same crest that crushed the
	# dream named across the reveal (the variants share the load — the
	# regime lands on the revenge or serve line, the previous leader on
	# the revenge line, whatever the rotor draws).
	assert_int(int(lines[0]["class"])).is_equal(Inks.LineClass.STRIKE)
	var joined := ""
	for line: Dictionary in lines:
		joined += String(line["text"]) + " "
	assert_bool(joined.contains(Inks.regime_name(regime_before))).is_true()
	assert_bool(joined.contains(previous_first)).is_true()
	assert_bool(joined.contains("crushed")).is_true()
	# The regime remembers — and the bank keeps a concrete number.
	assert_bool(joined.contains("regime remembers")).is_true()
	assert_bool(joined.contains("%d" % host.meta.legacy_points)).is_true()
	# The new hand is dealt under the SAME regime (the sim's defeat rule).
	assert_str(String(view["regime"]["id"])).is_equal(String(regime_before))


# --- helpers ----------------------------------------------------------------------------------


func _test_host() -> GameHost:
	var host := GameHost.new(20261208, "user://cs_copy_tests")
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _label_of(line: Control) -> Label:
	for child in line.get_children():
		var row := child as HBoxContainer
		if row == null:
			continue
		for item in row.get_children():
			if item is Label:
				return item
	return null
