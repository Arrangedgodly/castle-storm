## ChroniclePresenter — the chronicle screen's pure view layer (T-UI-08).
##
## THE CHRONICLE IS PAST SPREADS (design brief §3: "the chronicle is past
## spreads") — this is where the "reset is the story" principle (PRODUCT.md)
## becomes legible: every completed hand prints as a small spread card
## (leader identity, regime ink + crest, outcome seal, duration, the army
## at the end, the legacy that run banked). The roster of past hands grows
## unbounded across runs — the ring of past spreads — so the view PAGES it.
##
## DATA CONTRACT (the task's hard rule): every entry field maps
## RunMeta.chronicle EXACTLY (docs/save-schema.md §5.1 — run, leader, tags,
## trait, regime, outcome, duration_ticks, army_power, army, score). The
## presenter never reconstructs, derives, or invents history: it renders
## the historical document, resolving only display dressing (regime
## display name/ink/crest from the pack against the entry's regime id —
## the id stays the record's own). The LIVE run is deliberately ABSENT
## from the entries (it is not chronicle until it ends) and prints as its
## own distinct "live hand" strip read from the run lifecycle's query
## surfaces.
##
## OUTCOME SEALS: the seal is LINE FORM + a print mark (the world's
## colorblind-safe raise — form, never hue): victory prints the double
## rule + "WON", defeat prints struck + "CRUSHED", aborted prints dashed
## (a dream held, then dropped — nobody struck it) + "ABANDONED".
##
## LABEL BUDGETS (the T-UI-06 lesson: shape content, never clip
## mid-sentence): the longest identity-pool names and army lines exceed a
## card's plate width, so every printed line is SHAPED here (greedy
## word-wrap at a character budget the sheet owns) — the sheet's labels
## then wrap onto bounded rows instead of clipping.
##
## Copy is the clerk's voice through CopyDeck (T-COPY-01: the pack's
## CopyTable owns the variants; every NAME, SEAL, DURATION, ARMY COUNT and
## BANKED number is the meta domain's own record).
class_name ChroniclePresenter
extends RefCounted

## The empty chronicle's required line (first run: no dream has yet dared)
## — the code-side twin of the copy table's `chronicle_empty_1` variant 0
## (an empty chronicle means run 0: the rotor is always 0 here).
const EMPTY_LINE := "the chronicle is blank — no dream has yet dared"

## Secondary empty-state print (the table below still lives).
const EMPTY_LINE_2 := "The first hand is still on the table."

## The seal marks, per normalized outcome text (save-schema §5.1).
const SEAL_MARKS: Dictionary = {
	"victory": "WON",
	"defeat": "CRUSHED",
	"aborted": "ABANDONED",
}

## The seal's line-form class per outcome (form, not hue): the victory
## double rule, the struck defeat, the dashed abandonment.
const SEAL_CLASSES: Dictionary = {
	"victory": Inks.LineClass.VICTORY,
	"defeat": Inks.LineClass.STRIKE,
	"aborted": Inks.LineClass.WARN,
}

## The sheet's title letterpress.
const TITLE := "THE CHRONICLE"

## Character budgets for the shaped lines (measured against the IM Fell /
## Alegreya plates the sheet prints them on — the T-UI-06 no-clip lesson:
## the presenter shapes, the sheet wraps at these budgets, nothing clips).
const NAME_BUDGET := 26
const ROLE_BUDGET := 40
const ARMY_BUDGET := 44


# --- the view model ----------------------------------------------------------------------


## The whole sheet as data, one page at a time. `page` is 0-based over the
## NEWEST-FIRST ordering (the most recent hand leads, like the strip);
## `per_page` is the page size the sheet's height grants. Pure: reads only
## the meta domain + the run lifecycle's live query surfaces (the current
## strip) — same meta => same view (view_hash pins it).
static func view(host: GameHost, page: int, per_page: int) -> Dictionary:
	var chronicle: Array[Dictionary] = host.meta.chronicle
	var total := chronicle.size()
	var page_count := maxi(1, int(ceil(float(total) / float(maxi(1, per_page)))))
	page = clampi(page, 0, page_count - 1)
	# Newest first: the most recent hand leads the page (chronicle itself
	# is append-only oldest-first; order is part of the record, the READER
	# chooses its own direction — this view never mutates the record).
	var entries: Array[Dictionary] = []
	if total > 0:
		var newest_first: Array[Dictionary] = []
		for i in range(total - 1, -1, -1):
			newest_first.append(chronicle[i])
		var begin := page * per_page
		for i in range(begin, mini(begin + per_page, total)):
			entries.append(entry_view(newest_first[i]))
	return {
		"title": TITLE,
		"empty": total == 0,
		"empty_lines": [
			{"class": Inks.LineClass.PLAIN,
				"text": CopyDeck.line(Inks.pack().copy, &"chronicle_empty_1", 0)},
			{"class": Inks.LineClass.PLAIN,
				"text": CopyDeck.line(Inks.pack().copy, &"chronicle_empty_2", 0)},
		],
		"entries": entries,
		"page": page,
		"page_count": page_count,
		"runs_recorded": host.meta.runs_recorded,
		"runs_total": total,
		"bank": host.meta.legacy_points,
		"current": current_view(host),
		"per_page": per_page,
	}


## One chronicle entry as the card's data. Every key traces a §5.1 field;
## the display dressing (regime name/ink/crest) resolves against the pack
## from the entry's OWN regime id, and unknown ids degrade honestly (raw
## id as the name, the neutral ink, no crest) — the record never bends to
## the pack, the pack dresses the record.
static func entry_view(entry: Dictionary) -> Dictionary:
	var leader := String(entry.get("leader", ""))
	var first := leader
	var epithet := ""
	var split := leader.find(" ")
	if split > 0:
		first = leader.substr(0, split)
		epithet = leader.substr(split + 1)
	var outcome := String(entry.get("outcome", ""))
	var regime_id := StringName(String(entry.get("regime", "")))
	return {
		"run": int(entry.get("run", 0)),
		"leader": leader,
		"leader_first": first,
		"epithet": epithet,
		"name_lines": shaped_name(first, epithet),
		"role_line": shaped_role(entry),
		"regime": {
			"id": regime_id,
			"name": Inks.regime_name(regime_id),
			"ink": Inks.regime_secondary(regime_id),
			"crest_key": crest_key(regime_id),
		},
		"outcome": outcome,
		"seal": seal_view(outcome),
		"duration_ticks": int(entry.get("duration_ticks", 0)),
		"duration_line": duration_line(int(entry.get("duration_ticks", 0))),
		"army": (entry.get("army", {}) as Dictionary).duplicate(true),
		"army_line": army_line(entry),
		"army_power": int(entry.get("army_power", 0)),
		"score": int(entry.get("score", 0)),
	}


## The outcome seal: line-form class + print mark (+ the clerk's own word
## for the outcome, as the chronicle wrote it).
static func seal_view(outcome: String) -> Dictionary:
	return {
		"mark": String(SEAL_MARKS.get(outcome, outcome.to_upper())),
		"class": int(SEAL_CLASSES.get(outcome, Inks.LineClass.PLAIN)),
		"word": outcome,
	}


## The live hand strip (the current-run header distinction): the running
## run is NOT in the chronicle yet — it prints as its own dashed strip
## (in progress prints dashed, the edge-form grammar) read from the run
## lifecycle's live surfaces. Empty when no run is running (the brief
## moment between hands: the next deal is the intro's business).
static func current_view(host: GameHost) -> Dictionary:
	if not host.is_run_running():
		return {}
	var run := host.run()
	var regime_id := run.regime_id()
	return {
		"run_number": host.meta.runs_recorded + 1,
		"leader": run.leader_name(),
		"regime_id": regime_id,
		"regime_name": Inks.regime_name(regime_id),
		"regime_ink": Inks.regime_secondary(regime_id),
		"hours": (host.engine.tick_count - run.run_start_tick()) / SimEngine.TICKS_PER_SIM_HOUR,
		"class": Inks.LineClass.WARN,  # dashed — the hand is still in progress
	}


# --- the prints -------------------------------------------------------------------------


## Duration as the clerk prints it: hours under two days, days + hours
## above ("38h" / "3d 14h" — glanceable at phone scale).
static func duration_line(duration_ticks: int) -> String:
	var hours := duration_ticks / SimEngine.TICKS_PER_SIM_HOUR
	if hours < 48:
		return "%dh" % hours
	return "%dd %dh" % [hours / 24, hours % 24]


## The army at the end, from the entry's own terminal-roster snapshot:
## per-def counts in stored order (pack display names pluralized; ids that
## left the pack print verbatim — a historical document keeps its own
## words) + the power. An empty roster prints honestly ("no army stood").
static func army_line(entry: Dictionary) -> String:
	var army: Dictionary = entry.get("army", {})
	if army.is_empty():
		return "no army stood · power %d" % int(entry.get("army_power", 0))
	var parts: Array[String] = []
	for def_id in army.keys():
		var count := int(army[def_id])
		parts.append("%d %s" % [count, _def_display_name(def_id).to_lower() + ("s" if count != 1 else "")])
	return "%s · power %d" % [", ".join(parts), int(entry.get("army_power", 0))]


## The leader's plate: first name + epithet, shaped to the name budget
## (the longest pool names wrap to their own line, never clip).
static func shaped_name(first: String, epithet: String) -> Array[String]:
	var lines: Array[String] = []
	if first.length() + epithet.length() + 1 <= NAME_BUDGET:
		lines.append("%s %s" % [first, epithet] if not epithet.is_empty() else first)
	else:
		lines.append(first)
		lines.append(epithet)
	return lines


## The role plate: personality tags + trait (the entry's own words),
## wrapped at the role budget to at most two rows. The wrap prefers the
## " · " SEPARATOR (tags row, trait row) so a multi-word trait never
## splits mid-phrase — the record's own words stay whole (T-COPY-01's
## longer content traits exposed the greedy wrap).
static func shaped_role(entry: Dictionary) -> String:
	var tags: Array = entry.get("tags", [])
	var parts: Array[String] = []
	for tag in tags:
		parts.append(String(tag).replace("_", " "))
	var role := " and ".join(parts)
	var trait_text := String(entry.get("trait", ""))
	if not trait_text.is_empty():
		role = "%s · %s" % [role, trait_text] if not role.is_empty() else trait_text
	if role.length() <= ROLE_BUDGET:
		return role
	var sep := role.find(" · ")
	if sep > 0 and role.length() - sep - 3 <= ROLE_BUDGET:
		return "%s\n%s" % [role.substr(0, sep), role.substr(sep + 3)]
	return _wrap(role, ROLE_BUDGET, 2)


## Wrap the army line at its budget (a 4-def roster with long names can
## exceed the plate; it wraps to a second row, never clips).
static func wrap_army_line(text: String) -> String:
	return _wrap(text, ARMY_BUDGET, 2)


## Regime crest key from the pack ("" when the regime id left the pack —
## the crest slot prints its authored placeholder mark, honestly generic).
static func crest_key(regime_id: StringName) -> StringName:
	var pack := Inks.pack()
	if pack == null:
		return &""
	for regime: RegimeDef in pack.regimes:
		if regime.id == regime_id:
			return regime.crest_id
	return &""


static func _def_display_name(def_id: StringName) -> String:
	var pack := Inks.pack()
	if pack != null:
		for def: UnitDef in pack.units:
			if def.id == def_id:
				return def.display_name
	return String(def_id)


## Greedy word-wrap at a character width, capped at max_lines (the trailing
## fragment keeps its overflow rather than growing a third row past the
## card — the sheet's labels autowrap at the same budget, so a long tail
## wraps on the plate instead of clipping).
static func _wrap(text: String, width: int, max_lines: int) -> String:
	if text.length() <= width or max_lines <= 1:
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


# --- determinism ---------------------------------------------------------------------------


## Determinism oracle over the view's CONTENT: same meta (+ live run) =>
## same hash — the sheet is a function of the record, never of UI history.
static func view_hash(view: Dictionary) -> int:
	var h := 0x811C9DC5
	h = _mix(h, String(view["title"]).hash())
	h = _mix(h, int(view["empty"]))
	h = _mix(h, int(view["page"]))
	h = _mix(h, int(view["page_count"]))
	h = _mix(h, int(view["runs_recorded"]))
	h = _mix(h, int(view["bank"]))
	for entry: Dictionary in view["entries"]:
		h = _mix(h, int(entry["run"]))
		h = _mix(h, String(entry["leader"]).hash())
		h = _mix(h, String(entry["role_line"]).hash())
		h = _mix(h, String(entry["outcome"]).hash())
		h = _mix(h, int(entry["seal"]["class"]))
		h = _mix(h, String(entry["seal"]["mark"]).hash())
		h = _mix(h, int(entry["duration_ticks"]))
		h = _mix(h, String(entry["army_line"]).hash())
		h = _mix(h, int(entry["army_power"]))
		h = _mix(h, int(entry["score"]))
		var regime: Dictionary = entry["regime"]
		h = _mix(h, String(regime["id"]).hash())
	var current: Dictionary = view["current"]
	if not current.is_empty():
		h = _mix(h, String(current["leader"]).hash())
		h = _mix(h, String(current["regime_id"]).hash())
		h = _mix(h, int(current["hours"]))
	return h


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
