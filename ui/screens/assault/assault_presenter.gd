## AssaultPresenter — the assault vignette's pure view layer (T-UI-07).
##
## Everything the odds screen and the beat stage print derives from the
## resolver's documented query surfaces (docs/sim-engine.md §15): the odds
## breakdown (`AssaultResolver.assault_odds`) for the PRE-COMMIT screen, the
## beat script (BeatScript) for the vignette. Same data -> same prints.
##
## The voice is the world's own print-block clerk: permille odds become
## READABLE CONFIDENCE bands (a player must feel "276 in 1000" before
## committing three days of army to it), the garrison composes as a printed
## line, the knight floor refuses in print, and each beat carries a summary
## line so reduced motion (near-instant beats) still tells the whole story.
## Prof X's T-COPY-01 deepens the voice; these lines are the honest
## placeholder in the brief's grammar.
class_name AssaultPresenter
extends RefCounted

## Blocks in the print-block odds meter (permille -> filled blocks).
const METER_BLOCKS := 20

## Confidence bands (permille upper bounds, exclusive) -> readable words.
## The band edges are content-feel decisions pinned by test.
const CONFIDENCE_BANDS: Array[Dictionary] = [
	{"to": 200, "words": "forlorn odds"},
	{"to": 350, "words": "poor odds"},
	{"to": 500, "words": "long odds"},
	{"to": 650, "words": "even odds"},
	{"to": 800, "words": "favourable odds"},
	{"to": 1001, "words": "crushing odds"},
]


# --- the odds screen -------------------------------------------------------------------


## The odds view as one dict off the resolver's breakdown: everything the
## stage prints, precomputed and hashable. `odds` is assault_odds(engine).
static func odds_view(odds: Dictionary) -> Dictionary:
	var army: Dictionary = odds["army"]
	var garrison: Dictionary = odds["garrison"]
	var per_unit: Array = army["per_unit"]
	var roster: Array[Dictionary] = []
	for entry: Dictionary in per_unit:
		roster.append({
			"uid": int(entry["uid"]),
			"name": _recruit_name(int(entry["uid"])),
			"def": entry["def"],
			"def_power": int(entry["def_power"]),
			"gear_power": int(entry["gear_power"]),
			"total": int(entry["total"]),
		})
	return {
		"win_permille": int(odds["win_permille"]),
		"floor_power": int(odds["floor_power"]),
		"floor_met": bool(odds["floor_met"]),
		"army_power": int(army["power"]),
		"army_units": int(army["units"]),
		"army_multiplier_milli": int(army["regime_multiplier_milli"]),
		"army_score_milli": int(army["score_milli"]),
		"garrison_base": int(garrison["base_power"]),
		"garrison_modifier_kind": garrison["modifier_kind"],
		"garrison_multiplier_milli": int(garrison["regime_multiplier_milli"]),
		"garrison_strength_milli": int(garrison["strength_milli"]),
		"roster": roster,
	}


## "276 in 1000 — poor odds": the permille printed AS confidence. The raw
## number stays (idle players read exact odds; the band makes it felt).
static func confidence_line(permille: int) -> String:
	return "%d in 1000 — %s" % [permille, confidence_words(permille)]


static func confidence_words(permille: int) -> String:
	for band: Dictionary in CONFIDENCE_BANDS:
		if permille < int(band["to"]):
			return String(band["words"])
	return "even odds"


## Filled blocks for the odds meter (permille -> share of METER_BLOCKS).
static func meter_blocks(permille: int, total_blocks: int = METER_BLOCKS) -> int:
	return clampi(int(round(float(permille) * float(total_blocks) / 1000.0)), 0, total_blocks)


## The garrison's composition line for the castle card: the regime's ONE
## combat modifier, printed in the world's arithmetic voice.
static func garrison_line(view: Dictionary, regime_name: String) -> String:
	var mult := _multiplier_text(int(view["garrison_multiplier_milli"]))
	if String(view["garrison_modifier_kind"]) == "garrison_multiplier":
		return "garrison %d · walls ×%s" % [int(view["garrison_base"]), mult]
	if String(view["garrison_modifier_kind"]) == "army_score_multiplier":
		return "garrison %d · our ranks ×%s" % [int(view["garrison_base"]), _multiplier_text(int(view["army_multiplier_milli"]))]
	if regime_name.is_empty():
		return "garrison %d" % int(view["garrison_base"])
	return "garrison of the %s — %d strong" % [regime_name, int(view["garrison_base"])]


## The knight floor's printed gate (the commit refusal below floor).
static func floor_line(view: Dictionary) -> String:
	if bool(view["floor_met"]):
		return "the knight floor is met — %d sworn power" % int(view["army_power"])
	return "the knight floor: %d sworn power required — %d mustered" % [
		int(view["floor_power"]), int(view["army_power"])]


## One roster card's role line: where this unit's power comes from.
static func contribution_line(entry: Dictionary) -> String:
	var def_name := _def_display_name(entry["def"])
	if int(entry["gear_power"]) > 0:
		return "%d sword · %d gear" % [int(entry["def_power"]), int(entry["gear_power"])]
	return "%d sword" % int(entry["def_power"])


# --- the vignette's prints ----------------------------------------------------------------


## Each beat's summary line — the printed spine of the vignette. In full
## motion they accompany the march; in reduced motion (near-instant beats)
## they ARE the vignette. `beat_index` is the beat's place in the chain;
## `roster` (optional, the commit-time odds view's roster) sharpens the
## casualty counts — the lines work from events alone without it. T-COPY-01:
## the copy reads the pack's CopyTable, the rotor the battle's own visual
## sequence hash (same battle -> same lines; no two battles read alike).
static func beat_summary(script: Dictionary, beat_index: int, roster: Array = []) -> String:
	var beats: Array = script["beats"]
	if beat_index < 0 or beat_index >= beats.size():
		return ""
	var table: CopyTable = Inks.pack().copy
	var rotor := BeatScript.visual_sequence_hash(script) + beat_index
	var beat: Dictionary = beats[beat_index]
	var fallen := _fallen_units(script, beat_index, roster)
	match beat["phase"]:
		&"advance":
			return CopyDeck.line(table, &"beat_advance", rotor)
		&"skirmish":
			if fallen > 0:
				return CopyDeck.line(table, &"beat_skirmish_fallen", rotor, {"count": fallen})
			return CopyDeck.line(table, &"beat_skirmish", rotor)
		&"gate":
			if fallen > 0:
				return CopyDeck.line(table, &"beat_gate_fallen", rotor, {"count": fallen})
			return CopyDeck.line(table, &"beat_gate", rotor)
		&"throne":
			return CopyDeck.line(table, &"beat_throne", rotor)
		&"rout":
			return CopyDeck.line(table, &"beat_rout", rotor)
	return ""


## The outcome's printed block: the loss lands as a chronicle BLOCKQUOTE
## (struck rule, the wider print the strip never carries); the win lands as
## the victory double rule. Both stay on the table — never popup chrome.
## T-COPY-01: composed from the outcome templates (the label AUTOWRAPS —
## the block may run two sentences; the spine sentence carries the seal).
static func outcome_block(script: Dictionary, regime_name: String, banked_points: int) -> String:
	var table: CopyTable = Inks.pack().copy
	var rotor := BeatScript.visual_sequence_hash(script)
	if script["outcome"] == &"win":
		var head := CopyDeck.line(table, &"assault_win_block", rotor, {"regime": regime_name})
		if banked_points <= 0:
			return head
		return "%s %s" % [head, CopyDeck.line(table, &"assault_win_bank", rotor,
			{"points": banked_points})]
	return "%s %s" % [
		CopyDeck.line(table, &"assault_loss_block", rotor, {"regime": regime_name}),
		CopyDeck.line(table, &"assault_loss_note", rotor,
			{"count": int(script["casualties"])})]


## Units that fell AT a beat (roster-power share of the milli drop between
## the previous beat and this one, newest-first like the sim's own rule —
## the vignette strikes cards in the same order the roster lost them).
## Needs the commit-time roster (the odds view); without one the answer is
## 0 (meter-only replay still works — events alone always suffice).
static func _fallen_units(script: Dictionary, beat_index: int, roster: Array = []) -> int:
	if roster.is_empty():
		return 0
	var beats: Array = script["beats"]
	var initial_power := 0
	for entry: Dictionary in roster:
		initial_power += int(entry["total"])
	if initial_power <= 0:
		return 0
	var beat: Dictionary = beats[beat_index]
	var prev_army := int(script["initial_army_milli"]) if beat_index == 0 \
			else int(beats[beat_index - 1]["army_milli"])
	var lost_share := float(prev_army - int(beat["army_milli"])) / float(maxi(1, int(script["initial_army_milli"])))
	return int(round(float(initial_power) * lost_share))


# --- helpers -----------------------------------------------------------------------------


static func _recruit_name(uid: int) -> String:
	var pool: Array = Inks.pack().identity.recruit_names
	if pool.is_empty():
		return "Recruit %d" % uid
	return String(pool[(uid - 1) % pool.size()])


static func _def_display_name(id: StringName) -> String:
	for def: UnitDef in Inks.pack().units:
		if def.id == id:
			return def.display_name
	return String(id)


static func _multiplier_text(multiplier_milli: int) -> String:
	## "1.2" from 1200 milli (trimming trailing zeros: 900 -> "0.9", 1000 -> "1").
	var text := "%.3f" % (float(multiplier_milli) / 1000.0)
	return text.trim_suffix("0").trim_suffix(".")
