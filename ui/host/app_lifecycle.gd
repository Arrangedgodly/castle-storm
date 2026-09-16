## AppLifecycle — the platform boundary policy (T-PERF-01) — Thor lane.
##
## Maps the engine's OS lifecycle notifications onto the GameHost's
## background/foreground seams — docs/catch-up.md §2's away-time semantics,
## wired to the real notification surfaces. A plain RefCounted on the
## GameHost/SaveManager discipline: no scene tree, no clock — every
## timestamp is INJECTED by the node seam that forwards the notification
## (the game screen's `_notification`, the one permitted clock read in ui/
## per the security-policy inventory: the platform host injects "now").
##
## SURFACES (Godot 4.7 Node application-level notifications, delivered to
## every node; the screen forwards them here):
##   NOTIFICATION_APPLICATION_PAUSED  (Android/iOS/web) the OS is about to
##       suspend the process -> TRUE BACKGROUND: pause pacing, take the
##       away anchor, flush the autosave. The OS suspends the whole process
##       (main loop AND rendering stop naturally — verified against the
##       engine docs: there is nothing engine-side to stop on mobile, the
##       notification exists so the game can FLUSH first), so the flush is
##       the entire job.
##   NOTIFICATION_APPLICATION_RESUMED (Android/iOS/web) -> FOREGROUND: the
##       away window resolves through the real engine (capped 8h catch-up)
##       and pacing resumes.
##   NOTIFICATION_WM_CLOSE_REQUEST    (desktop) the window is closing ->
##       the same background flush before the process dies (mobile never
##       sends it — the OS kills a suspended process without further
##       notice; PAUSED is the mobile flush moment).
##   NOTIFICATION_APPLICATION_FOCUS_OUT / _FOCUS_IN (desktop + Android)
##       window focus — see the decision of record.
##
## DESKTOP FOCUS DECISION OF RECORD (documented in docs/catch-up.md §2):
## losing window focus on desktop does NOT background the host. This is an
## idle game — the player expects the conspiracy to keep working while
## they tab away; the session never stopped, so no catch-up window is owed.
## The pacing accumulator consumes wall-clock deltas at 1x whatever the
## frame rate, the hourly autosave keeps the away anchor fresh, and a
## focused-but-idle table costs ~nothing per frame (the UI is event-driven;
## measured in scripts/perf_probe.gd, `make perf-probe`). The engine does
## keep submitting frames while the window is unfocused — accepted: the
## compositor skips presenting an occluded window, and the Compatibility
## renderer's cost for a static unfocused scene is the frame cost the probe
## measures (negligible game-layer CPU). `low_processor_usage_mode` was
## considered and rejected — it caps the WHOLE game at ~20fps and would
## break the 60fps target (T-PERF-02's budget) to save an idle watt.
## Hosts that want focus-loss to count as backgrounding anyway (a kiosk,
## a battery-strict build) set `desktop_backgrounds_on_focus_loss = true`.
##
## IDEMPOTENT BY CONSTRUCTION: the `backgrounded` latch gates both edges —
## a second PAUSED while hidden cannot move the away anchor (the window
## must never stretch), and a second RESUMED cannot resolve twice (no
## double fast-forward, no duplicate catch-up reports; the boot path's own
## foreground() is separate and unguarded by design — it resolves from the
## SAVED anchor of the previous process).
##
## Headless-testable by construction: the unit suite calls
## handle_notification() directly with injected epochs (notification
## simulation without a windowing system).
class_name AppLifecycle
extends RefCounted

## The host whose background/foreground boundaries this policy drives.
## Assigned by the node seam before any notification is forwarded; null
## makes every notification a no-op.
var host: GameHost

## OPT-IN desktop policy: treat window focus loss as backgrounding.
## Default FALSE — the decision of record above. (Android sends FOCUS_OUT
## right before PAUSED when backgrounding; with the default, the focus
## edge is ignored there too, so PAUSED — the true suspension — is the one
## moment the anchor is taken. A FOCUS_IN while backgrounded still
## foregrounds: if the app is visible again the window is over, whatever
## edge says so.)
var desktop_backgrounds_on_focus_loss := false

## True while the host is backgrounded (the idempotency latch).
var backgrounded := false

## Boundary counters — probe/test evidence: exactly one per real cycle.
var background_count := 0
var foreground_count := 0


## One forwarded OS notification with the platform's "now" (UTC epoch
## seconds, injected — never read here). Returns the action taken:
## &"backgrounded", &"foregrounded" or &"ignored" (the seam may log it).
func handle_notification(what: int, now_epoch: int) -> StringName:
	if host == null:
		return &"ignored"
	match what:
		Node.NOTIFICATION_APPLICATION_PAUSED, \
		Node.NOTIFICATION_WM_CLOSE_REQUEST:
			# True backgrounding (the OS suspends the process) or the
			# window closing (the process is about to die): flush now.
			return _background(now_epoch)
		Node.NOTIFICATION_APPLICATION_RESUMED:
			return _foreground(now_epoch)
		Node.NOTIFICATION_APPLICATION_FOCUS_OUT:
			if desktop_backgrounds_on_focus_loss:
				return _background(now_epoch)
			return &"ignored"  # desktop: the world keeps running (the record)
		Node.NOTIFICATION_APPLICATION_FOCUS_IN:
			# Foregrounds only when a window is actually open (the latch);
			# a stray focus-in while foregrounded resolves nothing.
			return _foreground(now_epoch)
	return &"ignored"


# --- edges ---------------------------------------------------------------------------


func _background(now_epoch: int) -> StringName:
	if backgrounded:
		return &"ignored"  # already hidden: the anchor never moves twice
	backgrounded = true
	background_count += 1
	# host.background() is synchronous: mark_seen (the away anchor) lands
	# BEFORE the world stops being driven, and the anchor+save flush the
	# window's opening bookend in one boundary (docs/catch-up.md §2/§6 —
	# no tick can run between the anchor and driving=false).
	host.background(now_epoch)
	return &"backgrounded"


func _foreground(now_epoch: int) -> StringName:
	if not backgrounded:
		return &"ignored"  # never left: no window to resolve, no double tick
	backgrounded = false
	foreground_count += 1
	# Resolves exactly the away window (elapsed = now - anchor, clamped,
	# replayed through the real engine) and re-enables pacing.
	host.foreground(now_epoch)
	return &"foregrounded"
