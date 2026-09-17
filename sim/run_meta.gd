## Meta-progression bank reserve (T-SIM-04) — the data structure only.
##
## Owns everything that must SURVIVE a restart: the legacy-points bank
## (town-hall: failure banks FULL progress — every run, win or loss, accrues),
## the chronicle, the append-only record of past runs (leader, regime,
## outcome, duration, army stats) that T-UI-08 lists as spread history,
## the first-session onboarding flags (T-UI-10 — once-only nudges), and the
## L1 legacy unlock purchases (`unlocks` — spent through LegacySystem, the
## post-MVP layer-1 unlock tree service, which decrements the bank and
## owns every purchase rule).
##
## Save-domain contract (docs/sim-engine.md §12): this object lives in the
## META save domain, NEVER in the run save. RunLifecycleSystem composes
## entries into it but deliberately excludes it from its engine-side
## `to_dict()`/`state_hash()` — a run-save restore must not be able to fork
## or rewind the bank. T-ARCH-03 persists it separately (meta save slot);
## the host hands the SAME instance to each engine it builds, so the bank
## also survives the engine-reinit form of restart.
class_name RunMeta
extends RefCounted

## Version of the meta state dict (T-ARCH-03 bumps on change; refusal rule
## mirrors SimEngine.apply_state_dict — loud, never half-applied).
const META_FORMAT_VERSION: int = 1

## Total banked legacy points across every recorded run (win or loss).
var legacy_points := 0

## Runs recorded into the chronicle so far — the monotonic run number the
## chronicle displays (engine-local run indexes restart with each engine;
## this counter does not).
var runs_recorded := 0

## Append-only run records, oldest first. Entries are plain JSON-safe
## dictionaries composed by RunLifecycleSystem (schema in docs/sim-engine.md
## §12): leader name/tags/trait, regime id, outcome, duration, army stats,
## banked score. Unbounded by design — one small entry per completed run.
var chronicle: Array[Dictionary] = []

## UTC epoch SECONDS of the last time the host marked the session seen
## (T-SIM-07 offline catch-up): the anchor the next foreground subtracts
## `now` from. Lives in the META domain deliberately — away time elapses
## across run boundaries, so the anchor must outlive any single engine.
## 0 is the FIRST-LAUNCH SENTINEL (docs/catch-up.md): never marked → no
## catch-up ever fires off it. Additive-optional key (save-schema §5):
## pre-feature metas lack it and read back as 0 — first-launch again,
## which is exactly right.
var last_seen_epoch := 0

## First-session onboarding state (T-UI-10): beat-key -> true, once.
## "seen" marks THE one true first session (a returning player — flag
## set — is never nudged again, whatever became of the arc); the beat
## keys ("gate", "assign", "build", "trickle", "train") mark their
## printed nudges (each appears once, ever); "done" graduates the layer
## (arc complete or the run ended — nothing prints after). Lives in the
## META domain because the arc must survive engine rebuilds and process
## restarts. Additive-optional key (save-schema §5): pre-feature metas
## lack it and read back as {} — nobody is nudged, which is right.
var first_session := {}

## Player preferences (finishing refinement #5): the press-room card's
## persisted settings — `type_scale` (float, the TypeScale factor the
## boot seam applies) and `reduced_motion` (bool, mirrored into
## MotionProfile.forced). A key appears ONLY once the player sets it
## (the press card writes through the host, which saves the meta domain
## immediately); before that the project-settings defaults rule. META
## domain deliberately: preferences must survive restarts and engine
## rebuilds, and a run-save restore must never fork them. Additive-
## optional with a tolerant reader (save-schema §5): pre-feature metas
## lack the block and read back as {} — project defaults, no migration.
var preferences := {}


## The persisted type-scale factor, or -1.0 when the player never set
## one (the project setting rules; clamped to the TypeScale range on
## write AND on read — a hand-edited meta cannot smuggle in a 9.0).
func type_scale_preference() -> float:
	if not preferences.has("type_scale"):
		return -1.0
	return clampf(float(preferences["type_scale"]), TypeScale.MIN_SCALE, TypeScale.MAX_SCALE)


## Record the type-scale preference (the press card's step chips).
func set_type_scale_preference(value: float) -> void:
	preferences["type_scale"] = clampf(value, TypeScale.MIN_SCALE, TypeScale.MAX_SCALE)


## The persisted reduced-motion choice: 1 on, 0 off, -1 never set (the
## project setting rules — MotionProfile.forced's own convention).
func reduced_motion_preference() -> int:
	if not preferences.has("reduced_motion"):
		return -1
	return 1 if bool(preferences["reduced_motion"]) else 0


## Record the reduced-motion choice (the press card's steady-hand verb).
func set_reduced_motion_preference(on: bool) -> void:
	preferences["reduced_motion"] = on


## Legacy unlock tree purchases (L1): node id (String) -> true, insertion
## order = purchase order. META domain deliberately — unlocks are meta-
## progression banked across every run (R5: always-on, fed by every run win
## or lose), so they must survive restarts, engine re-inits and process
## restarts, and a run-save restore must never fork them (rule §3.6, same
## rule as the bank). The tree itself is boot-injected content and never
## serialized; ids resolve against the pack's UnlockTreeDef at boot, and an
## id that left the tree is KEPT (historical purchase) while contributing
## no effect. Additive-optional with a tolerant reader (save-schema §5):
## pre-L1 metas lack the key and read back as {} — no purchases, which is
## right. Spending decrements `legacy_points` through LegacySystem only.
var unlocks := {}

## The L2 escalation garrison snapshot (docs/save-schema.md §6 — the
## T-DATA-03 reserve, live since L2-A): the WINNING army of the last
## victorious run, captured by RunLifecycleSystem at the victory resolution
## and read by the next run's assault resolver INSTEAD of the static
## garrison base. {} = no snapshot = the static baseline (every pre-L2
## save). META domain deliberately: the garrison must survive the
## run_restart that immediately follows a victory AND engine re-inits, and
## must never be forkable from a run save (rule §3.6, same rule as the
## bank). Loss/abort/crush NEVER clears it — the regime that beat you
## stays until beaten (town-hall L2 fantasy). Emit-when-non-null in
## `to_dict()`; a pre-L2 meta reads back as {} = first-cycle default.
var escalation_garrison := {}

## Escalation cycle count (L2): how many snapshots have been captured —
## incremented ONLY by a victory that captures one (an empty-roster
## victory captures nothing). Cycle 1 is the first snapshot's ladder rung
## (the snapshot itself is the first escalation); the curve compounds from
## cycle 2. Emit-when-non-zero in `to_dict()` (the escalation_garrison
## discipline — a pre-L2 meta reads back 0).
var escalation_cycle := 0


## True when the beat's flag is set (never-printed beats read false).
func first_session_flag(key: StringName) -> bool:
	return bool(first_session.get(String(key), false))


## Sets a beat flag. Returns true when it FLIPPED false→true — the
## once-only edge callers gate their single print on.
func set_first_session_flag(key: StringName) -> bool:
	var k := String(key)
	if bool(first_session.get(k, false)):
		return false
	first_session[k] = true
	return true


func to_dict() -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry in chronicle:
		entries.append(entry.duplicate(true))
	var session := {}
	for key in first_session.keys():
		session[key] = first_session[key]
	var state := {
		"format_version": META_FORMAT_VERSION,
		"legacy_points": legacy_points,
		"runs_recorded": runs_recorded,
		"chronicle": entries,
		"last_seen_epoch": last_seen_epoch,
		"first_session": session,
		"preferences": preferences.duplicate(true),
		"unlocks": unlocks.duplicate(true),
	}
	# The L2 escalation keys ride along ONLY when there is something to say
	# (the emit-when-non-null discipline, save-schema §6): a pre-first-
	# victory meta serializes byte-identically to the pre-L2 build, and a
	# pre-L2 save reads back as no-snapshot/0 — the additive-reserve
	# argument's tolerant-reader premise.
	if not escalation_garrison.is_empty():
		state["escalation_garrison"] = escalation_garrison.duplicate(true)
	if escalation_cycle > 0:
		state["escalation_cycle"] = escalation_cycle
	return state


## Restores a to_dict() payload. Returns false (and refuses, state
## untouched) on a format_version mismatch — same refusal discipline as the
## engine's apply_state_dict.
func apply_dict(state: Dictionary) -> bool:
	var version := int(state.get("format_version", -1))
	if version != META_FORMAT_VERSION:
		push_error(
			"run-meta: state format %d is not supported (expected %d) — refusing"
			% [version, META_FORMAT_VERSION]
		)
		return false
	legacy_points = int(state.get("legacy_points", 0))
	runs_recorded = int(state.get("runs_recorded", 0))
	# Tolerant read (additive-optional, docs/save-schema.md §5): a pre-T-SIM-07
	# meta has no anchor — the first-launch sentinel, never a refusal.
	last_seen_epoch = int(state.get("last_seen_epoch", 0))
	# Same discipline for the T-UI-10 first-session state: a pre-feature
	# meta has no block — {} is the honest read (no beat ever printed).
	first_session = {}
	for key in state.get("first_session", {}).keys():
		first_session[key] = bool(state["first_session"][key])
	# Same discipline for the press-room preferences (finishing
	# refinement #5): absent block -> {} -> project defaults rule; each
	# present key is re-validated through its own accessor discipline
	# (the scale re-clamped, the flag boolified) so a tampered meta
	# degrades to a legal preference, never a crash or a 9.0x hand.
	preferences = {}
	var stored_prefs: Dictionary = state.get("preferences", {})
	if stored_prefs.has("type_scale"):
		set_type_scale_preference(float(stored_prefs["type_scale"]))
	if stored_prefs.has("reduced_motion"):
		set_reduced_motion_preference(bool(stored_prefs["reduced_motion"]))
	chronicle.clear()
	for entry in state.get("chronicle", []):
		chronicle.append(entry)
	# Same discipline for the L1 unlock purchases: absent block -> {} (a
	# pre-L1 meta owns nothing — the honest read); a present key counts as
	# owned only when truthy, so a hand-edited meta degrades to the legal
	# purchase set, never a crash.
	unlocks = {}
	var stored_unlocks: Dictionary = state.get("unlocks", {})
	for key in stored_unlocks.keys():
		if bool(stored_unlocks[key]):
			unlocks[String(key)] = true
	# Same discipline for the L2 escalation snapshot (save-schema §6): an
	# absent key is a pre-L2 (or pre-first-victory) meta -> no garrison ->
	# the static baseline. Read verbatim (the chronicle rule): ids resolve
	# against boot content at derivation time, where unknowns warn loudly —
	# a non-dict value degrades to the no-snapshot default, never a crash.
	escalation_garrison = {}
	var stored_garrison: Variant = state.get("escalation_garrison", {})
	if typeof(stored_garrison) == TYPE_DICTIONARY:
		escalation_garrison = (stored_garrison as Dictionary).duplicate(true)
	escalation_cycle = maxi(0, int(state.get("escalation_cycle", 0)))
	return true
