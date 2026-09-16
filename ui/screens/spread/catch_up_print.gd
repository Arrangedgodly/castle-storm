## CatchUpPrint — the while-you-were-away chronicle print (T-UI-09).
##
## "STATES PRINT THEMSELVES" (design brief raise #2): the catch-up
## resolution is NEVER a modal "welcome back" popup — it is a chronicle
## BLOCKQUOTE printed on the table (the SuspicionEvents.EventQuote
## grammar: paper panel, ink rows, dwells, folds itself) plus one line in
## the rolling strip. Every number in every row is read from the REAL
## `catch_up_applied` report payload (docs/catch-up.md §7) — per-type
## resource deltas, arrivals/completions/promotions, the suspicion delta,
## crackdowns that landed inside the window, run endings — never
## re-derived or invented here.
##
## LINE BUDGET (the T-UI-06 find, honored here): ChronicleLine rows CLIP
## past the label edge; the quote panel is 560 wide and its printed label
## is 476px (560 - 2*14 panel margins - 2*8 row insets - 30 rule - 10
## separation, orientation-independent). The STANDARD is font-metric
## no-clip: every row is shaped to fit the label measured in the theme's
## real AlegreyaSans-Italic 22px face with >= 30px of margin (pinned by
## test against a live mounted EventQuote — the round-1 re-dispatch; the
## <= ROW_CHAR_BUDGET character count stays only as a secondary guard:
## wide glyphs made the char proxy leaky).
##
## Pure statics only: a report Dictionary in, {class, text} rows out —
## same report => same print (testable without a host or scene tree).
class_name CatchUpPrint
extends RefCounted

## Secondary character-count guard on the single-line budget (the PRIMARY
## pin is the font-metric no-clip test — measure the real face, assert
## <= label width - margin; T-COPY-01's variants are shaped inside it).
const ROW_CHAR_BUDGET := 60

## The copy seam: the pack's CopyTable + the window's rotor (the report's
## from_tick — same window, same lines; a different window reads
## differently). Null table = CopyDeck's code-side floor.
static func _table() -> CopyTable:
	return Inks.pack().copy


static func _rotor(report: Dictionary) -> int:
	return maxi(0, int(report.get("from_tick", 0)))


## A whole away window's seconds as the table's own phrase ("8h 37m",
## "42m", "<1m") — SIM time elapsed, i.e. the clamped window that actually
## applied (a capped 9h37m absence is honestly "8h 00m": only that played).
static func duration_phrase(clamped_seconds: int) -> String:
	if clamped_seconds < 60:
		return "<1m"
	var hours := clamped_seconds / 3600
	var minutes := (clamped_seconds % 3600) / 60
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%dm" % minutes


## The headline text (one voice source: the strip's catch_up_applied row
## AND the blockquote's first row AND the resumed reveal's away line all
## derive from these seconds — no divergent copies of the same fact).
static func headline_text(clamped_seconds: int) -> String:
	if clamped_seconds < 60:
		return "While you were away, less than a minute passed."
	return CopyDeck.line(_table(), &"catchup_headline", 0,
		{"duration": duration_phrase(clamped_seconds)})


## The strip row for the summary event ({class, text}).
static func headline_row(report: Dictionary) -> Dictionary:
	return {"class": Inks.LineClass.PLAIN,
		"text": headline_text(int(report.get("clamped_seconds", 0)))}


## The zero-tick foreground's single quiet line (nothing happened — the
## print stays one row, no panel).
static func quiet_row() -> Dictionary:
	return {"class": Inks.LineClass.PLAIN,
		"text": CopyDeck.line(_table(), &"catchup_quiet", 0)}


## The whole blockquote, in print order: the elapsed headline (capped
## noted when clamped), per-type resource movement, the arrivals/
## completions/promotions summary, the suspicion delta, crackdowns that
## landed while away (weight: STRIKE), and a run that ended inside the
## window (weight: STRIKE). A rewound clock leads with the wry line and
## prints nothing else — nothing else happened, and nothing was taken.
## T-COPY-01: every row reads the pack's CopyTable (rotor = the window's
## from_tick); the voice is the clerk's, the numbers the report's own.
static func rows(report: Dictionary) -> Array[Dictionary]:
	var table := _table()
	var rotor := _rotor(report)
	var out: Array[Dictionary] = []
	if bool(report.get("rewound", false)):
		out.append({"class": Inks.LineClass.PLAIN,
			"text": CopyDeck.line(table, &"catchup_rewound", rotor)})
		return out
	out.append(headline_row(report))
	var cap_seconds := int(report.get("cap_seconds", 0))
	if bool(report.get("capped", false)) and cap_seconds > 0:
		out.append({"class": Inks.LineClass.PLAIN,
			"text": CopyDeck.line(table, &"catchup_capped", rotor,
				{"hours": maxi(1, cap_seconds / 3600)})})
	out.append(_resources_row(table, rotor, report))
	var people := _people_row(table, rotor, report)
	if not people.is_empty():
		out.append(people)
	var suspicion := _suspicion_row(table, rotor, report)
	if not suspicion.is_empty():
		out.append(suspicion)
	if int(report.get("crackdowns", 0)) > 0:
		out.append({"class": Inks.LineClass.STRIKE,
			"text": CopyDeck.line(table, &"catchup_crackdown_strike", rotor)})
	if int(report.get("run_endings", 0)) > 0:
		out.append({"class": Inks.LineClass.STRIKE,
			"text": CopyDeck.line(table, &"catchup_run_ended", rotor)})
	return out


## Per-type resource movement, only the types that moved, signed (a
## crackdown's seizures print as losses here — the net truth).
static func _resources_row(table: CopyTable, rotor: int, report: Dictionary) -> Dictionary:
	var delta: Dictionary = report.get("resource_delta", {})
	var parts: Array[String] = []
	for id in delta.keys():
		var amount := int(delta[id])
		if amount != 0:
			parts.append("%+d %s" % [amount, String(id)])
	if parts.is_empty():
		return {"class": Inks.LineClass.PLAIN,
			"text": CopyDeck.line(table, &"catchup_stores_quiet", rotor)}
	return {"class": Inks.LineClass.PLAIN,
		"text": CopyDeck.line(table, &"catchup_stores", rotor,
			{"stores": ", ".join(parts)})}


static func _people_row(table: CopyTable, rotor: int, report: Dictionary) -> Dictionary:
	var parts: Array[String] = []
	var arrivals := int(report.get("arrivals", 0))
	if arrivals > 0:
		parts.append(CopyDeck.line(table, &"catchup_people_arrived", rotor,
			{"count": arrivals}))
	var completions := int(report.get("training_completions", 0))
	if completions > 0:
		parts.append(CopyDeck.line(table, &"catchup_people_drills", rotor,
			{"count": completions}))
	var promotions := int(report.get("promotions", 0))
	if promotions > 0:
		parts.append(CopyDeck.line(table, &"catchup_people_promoted", rotor,
			{"count": promotions,
				"verb": "was" if promotions == 1 else "were"}))
	if parts.is_empty():
		return {}
	return {"class": Inks.LineClass.PLAIN, "text": "%s." % ", ".join(parts)}


## The Crown's eye moved during the window (suspicion accrues away too —
## a cheater's estate gets louder, not richer; docs/catch-up.md §4).
static func _suspicion_row(table: CopyTable, rotor: int, report: Dictionary) -> Dictionary:
	if not bool(report.get("suspicion_present", false)):
		return {}
	var delta := int(report.get("suspicion_delta", 0))
	if delta == 0:
		return {}
	var before := int(report.get("suspicion_before", 0))
	var after := int(report.get("suspicion_after", 0))
	return {"class": Inks.LineClass.PLAIN,
		"text": CopyDeck.line(table,
			&"catchup_suspicion_ease" if delta < 0 else &"catchup_suspicion_rise",
			rotor, {"before": before, "after": after})}


# --- the resumed reveal's away line (IntroPresenter composes it) ----------------


## The returning-hand packet's away line: the same facts, the reveal's
## voice (variants rotated by the window's from_tick). `report` empty = a
## resumed session whose window was never resolved on this boot (no
## injected now — the platform host's call to make).
static func away_line(report: Dictionary) -> String:
	var table := _table()
	var rotor := _rotor(report)
	if report.is_empty():
		return CopyDeck.line(table, &"catchup_away_empty", 0)
	if bool(report.get("rewound", false)):
		return CopyDeck.line(table, &"catchup_rewound", rotor)
	var clamped := int(report.get("clamped_seconds", 0))
	if clamped < 60:
		return CopyDeck.line(table, &"catchup_quiet", 0)
	if bool(report.get("capped", false)):
		return CopyDeck.line(table, &"catchup_away_capped", rotor, {
			"duration": duration_phrase(clamped),
			"hours": maxi(1, int(report.get("cap_seconds", 0)) / 3600)})
	return CopyDeck.line(table, &"catchup_away_plain", rotor,
		{"duration": duration_phrase(clamped)})
