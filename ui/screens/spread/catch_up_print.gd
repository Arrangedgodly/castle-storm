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
## past the label edge; the quote panel is 560 wide and the reveal's
## packet rows are narrower still, so every builder keeps its rows inside
## the budget (pinned by test at <= ROW_CHAR_BUDGET characters).
##
## Pure statics only: a report Dictionary in, {class, text} rows out —
## same report => same print (testable without a host or scene tree).
class_name CatchUpPrint
extends RefCounted

## The single-line budget every row must fit (the quote panel's label
## edge; pinned by test — T-COPY-01 deepens the voice inside it).
const ROW_CHAR_BUDGET := 66


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
	return "While you were away, %s passed at the table." % duration_phrase(clamped_seconds)


## The strip row for the summary event ({class, text}).
static func headline_row(report: Dictionary) -> Dictionary:
	return {"class": Inks.LineClass.PLAIN,
		"text": headline_text(int(report.get("clamped_seconds", 0)))}


## The zero-tick foreground's single quiet line (nothing happened — the
## print stays one row, no panel).
static func quiet_row() -> Dictionary:
	return {"class": Inks.LineClass.PLAIN,
		"text": "You were away a moment; the table kept still."}


## The whole blockquote, in print order: the elapsed headline (capped
## noted when clamped), per-type resource movement, the arrivals/
## completions/promotions summary, the suspicion delta, crackdowns that
## landed while away (weight: STRIKE), and a run that ended inside the
## window (weight: STRIKE). A rewound clock leads with the wry line (the
## service's own voice) and prints nothing else — nothing else happened.
static func rows(report: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if bool(report.get("rewound", false)):
		out.append({"class": Inks.LineClass.PLAIN,
			"text": "The castle clock was found wound backwards. The stores kept count."})
		return out
	out.append(headline_row(report))
	var cap_seconds := int(report.get("cap_seconds", 0))
	if bool(report.get("capped", false)) and cap_seconds > 0:
		out.append({"class": Inks.LineClass.PLAIN,
			"text": "The crown's clock stops at %d hours; the rest is not remembered."
				% maxi(1, cap_seconds / 3600)})
	out.append(_resources_row(report))
	var people := _people_row(report)
	if not people.is_empty():
		out.append(people)
	var suspicion := _suspicion_row(report)
	if not suspicion.is_empty():
		out.append(suspicion)
	if int(report.get("crackdowns", 0)) > 0:
		out.append({"class": Inks.LineClass.STRIKE,
			"text": "A crackdown landed while you were away — the riders were paid."})
	if int(report.get("run_endings", 0)) > 0:
		out.append({"class": Inks.LineClass.STRIKE,
			"text": "The hand itself ended while you were away."})
	return out


## Per-type resource movement, only the types that moved, signed (a
## crackdown's seizures print as losses here — the net truth).
static func _resources_row(report: Dictionary) -> Dictionary:
	var delta: Dictionary = report.get("resource_delta", {})
	var parts: Array[String] = []
	for id in delta.keys():
		var amount := int(delta[id])
		if amount != 0:
			parts.append("%+d %s" % [amount, String(id)])
	if parts.is_empty():
		return {"class": Inks.LineClass.PLAIN, "text": "The stores kept their count."}
	return {"class": Inks.LineClass.PLAIN, "text": "The stores: %s." % ", ".join(parts)}


static func _people_row(report: Dictionary) -> Dictionary:
	var parts: Array[String] = []
	var arrivals := int(report.get("arrivals", 0))
	if arrivals > 0:
		parts.append("%d came to the gate" % arrivals)
	var completions := int(report.get("training_completions", 0))
	if completions > 0:
		parts.append("%d finished their drills" % completions)
	var promotions := int(report.get("promotions", 0))
	if promotions > 0:
		parts.append("%d %s promoted" % [promotions, "was" if promotions == 1 else "were"])
	if parts.is_empty():
		return {}
	return {"class": Inks.LineClass.PLAIN, "text": "%s." % ", ".join(parts)}


## The Crown's eye moved during the window (suspicion accrues away too —
## a cheater's estate gets louder, not richer; docs/catch-up.md §4).
static func _suspicion_row(report: Dictionary) -> Dictionary:
	if not bool(report.get("suspicion_present", false)):
		return {}
	var delta := int(report.get("suspicion_delta", 0))
	if delta == 0:
		return {}
	var before := int(report.get("suspicion_before", 0))
	var after := int(report.get("suspicion_after", 0))
	var tail := "it eased." if delta < 0 else "it draws closer."
	return {"class": Inks.LineClass.PLAIN,
		"text": "The Crown's eye: %d to %d — %s" % [before, after, tail]}


# --- the resumed reveal's away line (IntroPresenter composes it) ----------------


## The returning-hand packet's away line: the same facts, the reveal's
## voice. `report` empty = a resumed session whose window was never
## resolved on this boot (no injected now — the platform host's call to
## make).
static func away_line(report: Dictionary) -> String:
	if report.is_empty():
		return "The table kept its counsel while you were gone."
	if bool(report.get("rewound", false)):
		return "The clock was found wound backwards; the stores kept count."
	var clamped := int(report.get("clamped_seconds", 0))
	if clamped < 60:
		return quiet_row()["text"]
	if bool(report.get("capped", false)):
		return "You were away %s — the crown's clock stops at %d hours." % [
			duration_phrase(clamped), maxi(1, int(report.get("cap_seconds", 0)) / 3600)]
	return "You were away %s; the press kept printing." % duration_phrase(clamped)
