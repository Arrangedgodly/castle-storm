## IntroPresenter — the leader intro / restart reveal's pure view layer
## (T-UI-05).
##
## Everything the intro prints derives from ONE deterministic view model
## built from the host's read APIs + the META domain (the actual previous
## run's chronicle — never invented history): same sim state => same
## reveal (view_hash pins it). The variants:
##
##   first_run    — no chronicle yet: fresh copy, no bank line, the
##                  peasant is dealt under the drawn regime;
##   win_restart  — mounted from the assault's finished("win") seam: the
##                  REGIME-SWAP beat (the winner's ink becomes the
##                  castle's — restrained, printed), the banked-legacy
##                  line, the chronicle context read from the actual
##                  victory entry, then the NEW leader dealt under the
##                  redrawn regime (the sim's own victory-redraws rule);
##   loss_restart — mounted off run_lost/run_aborted (the crushing beat
##                  already printed in the chronicle beneath): the NEW
##                  leader dealt under the SAME regime (the sim's
##                  defeat-keeps rule) + "the regime remembers" line.
##
## Copy is placeholder clerk voice (Prof X's T-COPY-01 deepens it); every
## NAME, REGIME, DURATION and BANKED number in it is read from the run
## lifecycle's own query surfaces + RunMeta.chronicle — the reveal cannot
## lie about the previous hand.
class_name IntroPresenter
extends RefCounted

## The reveal variants (docs/sim-engine.md §12 outcome vocabulary) — plus
## the CHECK-IN variant (T-UI-09): a resumed session's short unfold, a
## returning player's paper (the chronicle cannot derive it: the session
## boundary is a host fact, so the caller's hint is AUTHORITATIVE for
## exactly this variant).
const VARIANT_FIRST_RUN := &"first_run"
const VARIANT_WIN_RESTART := &"win_restart"
const VARIANT_LOSS_RESTART := &"loss_restart"
const VARIANT_RESUMED := &"resumed"

## The one gesture's chip (every variant: unfold = open, the motion
## grammar's session-start verb; the signature double rule prints on it).
const CHIP_LABEL := "Unfold the spread"

## The unfold's authored duration (full motion) — inside the brief's
## "check-in entry in ~3 seconds" and the task's 1–3s band; rescaled by
## MotionProfile so reduced motion lands near-instant (the intro IS the
## loading moment into the spread, never a wait).
const UNFOLD_SECONDS := 1.7

## The CHECK-IN unfold's authored duration — strictly faster than the
## deal's reveal (a returning player already knows the world; the brief's
## 3-second promise is measured foreground -> actionable card, and the
## reveal dwell + this sweep + a gesture must all fit inside it).
const RESUMED_UNFOLD_SECONDS := 1.0

## Interaction budget the intro contracts to the spread (the acceptance
## line "intro -> spread in <= 3 interactions"); the reveal itself waits
## for input, so the real count is exactly 1.
const MAX_INTERACTIONS := 3


# --- the view model ----------------------------------------------------------------------


## The whole reveal as data. Pure: reads only the run lifecycle's query
## surfaces + the shared meta; for restart variants the caller has ALREADY
## restarted the run (the new identity is drawn — the spread's seam order:
## beats print first, then the new leader is dealt). `p_resumed` forces
## the CHECK-IN variant (T-UI-09 — the session boundary is a host fact
## the chronicle cannot derive) and `p_catch_up` is the resolved away
## window's REAL report payload (may be {} — the window was never resolved
## on this boot).
static func reveal_view(host: GameHost, p_resumed := false,
		p_catch_up := {}) -> Dictionary:
	var run := host.run()
	var pack := Inks.pack()
	var previous: Dictionary = {}
	if not host.meta.chronicle.is_empty():
		previous = host.meta.chronicle[host.meta.chronicle.size() - 1]
	var variant := VARIANT_RESUMED if p_resumed else variant_for(host)
	var regime_id := run.regime_id()
	# The leader's face: the run starts as a peasant — the pack's base-unit
	# face (landed art or the authored placeholder, never invented).
	var face_key := &""
	for def: UnitDef in pack.units:
		if def.id == host.units().base_unit_id():
			face_key = def.face_id
			break
	var leader := {
		"name": run.leader_name(),
		"epithet": run.leader_epithet(),
		"tags": run.leader_tags(),
		"trait": run.leader_trait_label(),
		"face_key": face_key,
	}
	var regime := {
		"id": regime_id,
		"name": Inks.regime_name(regime_id),
		"flavor": _regime_flavor(regime_id),
		"crest_key": _regime_crest(regime_id),
		"ink": Inks.regime_secondary(regime_id),
		"ground": Inks.ground_for(regime_id, Inks.Phase.RECRUITING),
	}
	return {
		"variant": variant,
		"run_number": host.meta.runs_recorded + 1,
		"leader": leader,
		"regime": regime,
		"previous": previous,
		"bank": host.meta.legacy_points,
		"lines": reveal_lines(variant, leader, regime, previous, host.meta.legacy_points,
			host.is_run_running(), p_catch_up, host.engine.sim_hours()),
		"chip": CHIP_LABEL,
	}


## Which variant this reveal is — derived from the ACTUAL chronicle (an
## empty chronicle is a first run by definition; the last entry's outcome
## decides win vs loss restart; abort counts with the losses — the regime
## survived you either way).
static func variant_for(host: GameHost) -> StringName:
	if host.meta.chronicle.is_empty():
		return VARIANT_FIRST_RUN
	var outcome := String(host.meta.chronicle[host.meta.chronicle.size() - 1].get("outcome", ""))
	match outcome:
		"victory":
			return VARIANT_WIN_RESTART
		_:
			return VARIANT_LOSS_RESTART


## The reveal's printed lines, in order (class + text). Pure copy builder
## — testable without a host; every %s is caller-supplied ACTUAL data. The
## CHECK-IN variant's away line is CatchUpPrint's (one voice source for
## the window's facts; the blockquote carries the detail after the sweep).
static func reveal_lines(variant: StringName, leader: Dictionary, regime: Dictionary,
		previous: Dictionary, bank: int, run_alive := true,
		p_catch_up := {}, p_sim_hours := 0) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var regime_name := String(regime["name"])
	match variant:
		VARIANT_RESUMED:
			# The returning hand: the leader's FIRST name (the loss-restart
			# precedent — the full plate is on the leader card beside it),
			# the away line from the REAL report, then the table beneath.
			if run_alive:
				lines.append(_row(Inks.LineClass.PLAIN,
					"%s keeps the standard — hour %d of the hand."
					% [String(leader["name"]).split(" ")[0], p_sim_hours]))
				lines.append(_row(Inks.LineClass.PLAIN, CatchUpPrint.away_line(p_catch_up)))
				lines.append(_row(Inks.LineClass.PLAIN,
					"The spread waits beneath — the chronicle has the rest."))
			else:
				lines.append(_row(Inks.LineClass.STRIKE,
					"The hand ended while you were away."))
				lines.append(_row(Inks.LineClass.PLAIN, CatchUpPrint.away_line(p_catch_up)))
				lines.append(_row(Inks.LineClass.PLAIN, "The next hand waits beneath."))
			return lines
	match variant:
		VARIANT_FIRST_RUN:
			lines.append(_row(Inks.LineClass.PLAIN,
				"A blank chronicle, a warm press. One peasant steps forward."))
			lines.append(_row(Inks.LineClass.PLAIN,
				"Marked by the press: %s." % _tags_phrase(leader)))
			lines.append(_row(Inks.LineClass.PLAIN,
				"You serve %s, as every peasant does. For now." % _article(regime_name)))
		VARIANT_WIN_RESTART:
			# The regime-swap beat — the winner's ink becomes the castle's.
			var old_name := Inks.regime_name(StringName(String(previous.get("regime", ""))))
			if old_name.is_empty():
				old_name = "Crown"
			if old_name == regime_name:
				lines.append(_row(Inks.LineClass.VICTORY,
					"The banner never left: %s keeps the ink your army won it." % _article(regime_name)))
			else:
				lines.append(_row(Inks.LineClass.VICTORY,
					"Your army's ink is the castle's ink now — %s struck from the doors, %s printed over it."
					% [_article(old_name), _article(regime_name)]))
			lines.append(_row(Inks.LineClass.PLAIN,
				"The bank remembers: %d legacy points across %s."
				% [bank, ("one hand" if int(previous.get("run", 1)) <= 1
					else "%d hands" % int(previous.get("run", 1)))]))
			lines.append(_row(Inks.LineClass.PLAIN,
				"%s took the castle at %dh; you serve %s now. You were not at the feast."
				% [String(previous.get("leader", "")), _duration_hours(previous), _article(regime_name)]))
		VARIANT_LOSS_RESTART:
			lines.append(_row(Inks.LineClass.STRIKE,
				"%s crushed %s's dream: same crest, same walls."
				% [_article(regime_name), String(previous.get("leader", "")).split(" ")[0]]))
			lines.append(_row(Inks.LineClass.PLAIN,
				"The regime remembers. The bank does too: %d legacy points kept safe." % bank))
			lines.append(_row(Inks.LineClass.PLAIN,
				"You serve %s — the regime that crushed the last dream. Try to be quieter."
				% _article(regime_name)))
	return lines


## Regime display names carry their own article ("The Paper Crown") —
## the clerk's lines read it as a proper name, never "the The Paper Crown".
static func _article(regime_name: String) -> String:
	if regime_name.begins_with("The "):
		return regime_name
	return "the " + regime_name


## The unfold duration under the current motion profile (full = authored
## 1–3s; reduced = near-instant / synchronous). The CHECK-IN variant is
## deliberately FASTER than the deal's reveal (RESUMED_UNFOLD_SECONDS) —
## a returning player's 3-second promise, never a re-wait.
static func unfold_seconds(p_variant: StringName = VARIANT_FIRST_RUN) -> float:
	var full := RESUMED_UNFOLD_SECONDS if p_variant == VARIANT_RESUMED else UNFOLD_SECONDS
	return MotionProfile.duration(full)


## Determinism oracle over the view's CONTENT: two hosts in the same run
## + meta state build the same hash (the reveal is a function of the sim,
## never of UI history).
static func view_hash(view: Dictionary) -> int:
	var h := 0x811C9DC5
	h = _mix(h, String(view["variant"]).hash())
	h = _mix(h, int(view["run_number"]))
	h = _mix(h, int(view["bank"]))
	var leader: Dictionary = view["leader"]
	h = _mix(h, String(leader["name"]).hash())
	h = _mix(h, String(leader["trait"]).hash())
	h = _mix(h, String(leader["face_key"]).hash())
	for tag in leader["tags"]:
		h = _mix(h, String(tag).hash())
	var regime: Dictionary = view["regime"]
	h = _mix(h, String(regime["id"]).hash())
	h = _mix(h, String(regime["name"]).hash())
	for line: Dictionary in view["lines"]:
		h = _mix(h, int(line["class"]))
		h = _mix(h, String(line["text"]).hash())
	return h


static func _tags_phrase(leader: Dictionary) -> String:
	var tags: Array = leader["tags"]
	if tags.is_empty():
		return "no marks at all"
	var parts: Array[String] = []
	for tag in tags:
		parts.append(String(tag))
	if parts.size() == 1:
		return parts[0]
	return "%s and %s" % [" and ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]


static func _duration_hours(previous: Dictionary) -> int:
	return int(previous.get("duration_ticks", 0)) / SimEngine.TICKS_PER_SIM_HOUR


static func _regime_flavor(id: StringName) -> String:
	var pack := Inks.pack()
	if pack == null:
		return ""
	for regime: RegimeDef in pack.regimes:
		if regime.id == id:
			return regime.flavor_text
	return ""


static func _regime_crest(id: StringName) -> StringName:
	var pack := Inks.pack()
	if pack == null:
		return &""
	for regime: RegimeDef in pack.regimes:
		if regime.id == id:
			return regime.crest_id
	return &""


static func _row(line_class: int, text: String) -> Dictionary:
	return {"class": line_class, "text": text}


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
