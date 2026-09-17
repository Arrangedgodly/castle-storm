## MotionProfile — the motion grammar's pacing + the reduced-motion seam
## (T-UI-04).
##
## The design brief names a motion GRAMMAR (flip = promotion, unfold =
## open, slide-and-settle = cards joining the spread); this class owns its
## PACING in one place so every screen inherits the same world-consistent
## feel:
##
##   - FLIP: the promotion turn, ~0.65s — a deliberate beat in the brief's
##     0.5–0.8s band ("this is the one the game is remembered by");
##   - SETTLE: the entrance slide, ~0.28s with exactly one overshoot
##     damping (the card slides past its registration and settles back —
##     the misprint character in motion);
##   - FLOURISH: the flip's landing ink (a printed double rule that fades
##     like a press impression lifting), ~0.40s.
##
## REDUCED MOTION (the required seam, documented): the project setting
## `castle_storm/motion/reduced_motion` (bool, default false — declared in
## project.godot so it is discoverable under Advanced Project Settings)
## shortens every motion to NEAR-INSTANT: flips still fire their signals,
## still call the content swap in contract order, and still land on the
## same end state — the reveal is CONTENT, not animation — while entrance
## slides are skipped entirely. `MotionProfile.forced` is the hook the
## PRESS-ROOM CARD (finishing refinement #5) writes: -1 unset (the
## project setting rules — a player who never touched the card), 0 full
## motion, 1 reduced. The card's write is persisted in RunMeta.preferences
## and re-applied at boot; the change itself is LIVE by construction
## (every motion owner asks this class at motion time — no restart).
## Tests drive `forced` because ProjectSettings are process-global and
## cannot be flipped per-case.
class_name MotionProfile
extends RefCounted

const SETTING_KEY := "castle_storm/motion/reduced_motion"

## The promotion flip's full-motion duration (brief §3: 0.5–0.8s band).
const FLIP_SECONDS := 0.65
## The entrance slide's duration.
const SETTLE_SECONDS := 0.28
## The landing flourish's fade.
const FLOURISH_SECONDS := 0.40
## Near-instant floor: a reduced flip still reads as a turn (one squeezed
## frame pair), never a hard cut; the motion owners treat any duration
## <= 0.05s as "go synchronous" (same signals, same order, same end state).
const REDUCED_FRACTION := 0.05

## The press-room card's hook (-1 unset, 0 full motion, 1 reduced).
static var forced := -1


## True when the world must keep its motions near-instant.
static func reduced() -> bool:
	if forced >= 0:
		return forced == 1
	var value: Variant = false
	if ProjectSettings.has_setting(SETTING_KEY):
		value = ProjectSettings.get_setting(SETTING_KEY)
	return bool(value)


## A full-motion length rescaled for the current profile (near-instant
## when reduced; values <= ~0.03 mean "synchronous" to the callers).
static func duration(full_seconds: float) -> float:
	if reduced():
		return maxf(0.02, full_seconds * REDUCED_FRACTION)
	return full_seconds


## Entrance slides are pure flourish — reduced motion skips them outright.
static func entrances_enabled() -> bool:
	return not reduced()
