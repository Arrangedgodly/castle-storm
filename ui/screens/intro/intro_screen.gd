## IntroScreen — the leader intro / restart reveal's state machine +
## input (T-UI-05).
##
## Composed by the Spread as a full-rect child (like the ActionFan and
## the AssaultScreen: paper over the table while open — never modal
## chrome). The intro is THE OPENING MOMENT of every hand and the
## loading moment into the spread:
##
##   reveal   — the variant's beats print and the cards are dealt (see
##              IntroPresenter: first run = fresh copy; win restart =
##              the regime-swap beat + banked-legacy line + the chronicle
##              context read from the ACTUAL previous run; loss restart =
##              the same regime + "the regime remembers"; RESUMED
##              (T-UI-09) = the check-in beat — the SAME hand's leader
##              under the same regime + the away line from the REAL
##              catch-up report). RESTART VARIANTS DEAL THE NEW LEADER
##              THEMSELVES: the run has ended by the time this opens, so
##              the screen submits the real run_restart + grant verbs
##              through the host's one write path and drains the tick —
##              the identity the reveal prints IS the identity the sim
##              drew (a fresh leader always; a redrawn regime after
##              victory, the same regime after defeat — the sim's own
##              rules, never re-implemented here). The run_restarted
##              events flow through the host's unified feed, so the
##              spread beneath rebuilds itself;
##   unfolding— THE ONE GESTURE: any primary action (tap / pad A /
##              Enter) opens the packet onto the table beneath — the
##              authored 1–3s sweep (reduced motion: near-instant, same
##              end state); the spread is bound and live beneath the
##              whole time, so the unfold IS the load. The CHECK-IN
##              variant ALSO AUTO-OPENS after a short dwell (the
##              returning player's 3-second promise: one gesture OR
##              auto, whichever comes first — a check-in must never trap
##              a player who only wanted to glance), and its sweep is
##              the shorter RESUMED_UNFOLD_SECONDS;
##   closed   — folded away; `closed(variant)` hands the table back (the
##              Spread restores focus).
##
## FOCUS (Daredevil): the reveal opens focused on THE ONE GESTURE chip —
## the single affordance, reachable identically from touch (a tap
## anywhere on the paper or the >=48 grip chip), keyboard (Enter on the
## focused chip), and pad (A); back is accepted as the same gesture (the
## intro has nothing to dismiss INTO — proceeding is the only forward).
## `interactions` counts every player input consumed from mount to
## spread-visible; the contract is <= MAX_INTERACTIONS (the honest count
## is exactly 1 — the reveal WAITS for the gesture, it never
## auto-advances: the fast path for players who restart often is that
## nothing else is ever asked of them).
extends Control

## The intro folded away (the spread owns the table again). Carries the
## variant that played — the spread's seam data.
signal closed(variant: StringName)

const PACKET_SCRIPT := preload("res://ui/screens/intro/intro_packet.gd")

enum State { CLOSED, REVEAL, UNFOLDING }

## The interaction budget this screen contracts (tests assert against
## it; the plan's acceptance line "intro -> spread in <= 3 interactions").
const MAX_INTERACTIONS: int = IntroPresenter.MAX_INTERACTIONS

## The CHECK-IN reveal's dwell before it opens ITSELF (the auto half of
## "one gesture or auto"; MotionProfile-routed so reduced motion is
## near-instant — the reveal still flashes, then folds immediately).
const RESUMED_DWELL_SECONDS := 0.75
## Any dwell at/below this opens within the open() call (reduced motion).
const RESUMED_DWELL_SYNC := 0.05

var host: GameHost
var state: int = State.CLOSED
## The variant that played (set at open; the closed signal carries it).
var variant: StringName = &""
## Player inputs consumed from mount to spread-visible (the parity
## budget's honest counter).
var interactions := 0
## The last unfold's duration (the pacing probe; MotionProfile-routed).
var last_unfold_seconds := 0.0

var _packet: IntroPacket
var _router: LayoutRouter
var _view := {}
## Auto-open generation guard: only the NEWEST reveal's timer may fire
## (SceneTreeTimers cannot be cancelled; a stale one must not open a
## newer reveal early — the state guard alone cannot tell them apart).
var _auto_unfold_gen := 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_packet = PACKET_SCRIPT.new()
	_packet.name = "IntroPacket"
	_packet.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_packet)
	_packet._chip.pressed.connect(_on_chip)


# --- open / close -------------------------------------------------------------------------


## Open the reveal. `p_router` is the spread's router (kept for the
## orientation seam; the packet's statics decide stacked vs pair from the
## live bounds aspect, so square windows follow the pair like the
## CardFace hysteresis). `p_variant` is a CALLER HINT only — the
## presenter re-derives the truth from the actual chronicle — EXCEPT the
## CHECK-IN variant (the session boundary is a host fact the chronicle
## cannot derive; see IntroPresenter.VARIANT_RESUMED), and `p_catch_up`
## is that window's REAL report payload ({} = unresolved on this boot).
##
## Restart variants (the run has ENDED): the intro deals the new hand
## itself — run_restart + grant_resources down the host's one write path,
## then the ONE synchronous tick that drains them (tick-aligned by
## contract §5/§12). A still-running run is left untouched (the boot
## path: the host already started the first run — and the resumed
## check-in, whose run is live by definition).
func open(p_host: GameHost, p_router: LayoutRouter, p_variant: StringName = &"",
		p_catch_up: Dictionary = {}) -> void:
	host = p_host
	_router = p_router
	variant = p_variant
	if variant != IntroPresenter.VARIANT_FIRST_RUN \
			and variant != IntroPresenter.VARIANT_RESUMED \
			and not host.is_run_running():
		host.restart_run()
		host.advance_ticks(1)
	_view = IntroPresenter.reveal_view(
		host, variant == IntroPresenter.VARIANT_RESUMED, p_catch_up)
	variant = _view["variant"]
	state = State.REVEAL
	visible = true
	interactions = 0
	_packet.bind(_view)
	_seed_chip_focus.call_deferred()
	if variant == IntroPresenter.VARIANT_RESUMED:
		_arm_auto_unfold()


## Focus lands on THE gesture only while the reveal still owns the paper:
## the seeding is deferred (chips need a frame in the tree), and the
## check-in's AUTO path can close the whole reveal inside open() — a
## stale deferred grab would strand focus on the folded chip (the T-UI-09
## sync-path find, caught by the focus-landing test).
func _seed_chip_focus() -> void:
	if state == State.REVEAL and is_inside_tree():
		_packet._chip.grab_focus()


func is_open() -> bool:
	return state != State.CLOSED


## The bound view model (tests + the capture hook read the reveal data).
func view() -> Dictionary:
	return _view


## The reveal's render oracle (same view => same render).
func snapshot_hash() -> int:
	return _packet.snapshot_hash()


# --- the one gesture ------------------------------------------------------------------------


## THE ONE GESTURE: open the packet onto the table beneath. Idempotent
## per reveal — only the first input counts (the state flip guards);
## inputs arriving mid-sweep are the pacing's business, not new gestures.
func unfold() -> void:
	if state != State.REVEAL:
		return
	state = State.UNFOLDING
	last_unfold_seconds = IntroPresenter.unfold_seconds(variant)
	_packet.play_unfold(last_unfold_seconds, _on_unfolded)


## The auto half of the check-in's "one gesture or auto": the reveal
## opens ITSELF after the dwell. NOT a player input — the honest
## interaction count for a check-in the player never touched is 0.
func _arm_auto_unfold() -> void:
	var dwell := MotionProfile.duration(RESUMED_DWELL_SECONDS)
	_auto_unfold_gen += 1
	var generation := _auto_unfold_gen
	if dwell <= RESUMED_DWELL_SYNC:
		_auto_unfold_now(generation)
		return
	get_tree().create_timer(dwell).timeout.connect(_auto_unfold_now.bind(generation))


func _auto_unfold_now(generation: int) -> void:
	if generation != _auto_unfold_gen or state != State.REVEAL:
		return  # a newer reveal owns the paper, or the player's gesture won
	unfold()


func is_unfolding() -> bool:
	return state == State.UNFOLDING and _packet.is_unfolding()


## The authored sweep's progress 0..1 (the capture hook's mid-probe).
func unfold_progress() -> float:
	return _packet.unfold_progress()


func _on_unfolded() -> void:
	state = State.CLOSED
	visible = false
	if _packet._chip.has_focus():
		_packet._chip.release_focus()  # the table takes focus (never the folded chip)
	closed.emit(variant)


# --- input (all three modes, one gesture) ----------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if state != State.REVEAL:
		return
	# Non-positional primary that focus did not route to the chip, and
	# back — one gesture, every mode, counted once (the state guard makes
	# double-routing a no-op, not a double count).
	if (event.is_action_pressed(&"primary") and not (event is InputEventMouseButton) \
			and not (event is InputEventScreenTouch)) or event.is_action_pressed(&"back"):
		_count_gesture()
		unfold()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if state != State.REVEAL:
		return
	# Positional presses anywhere on the intro paper (touch/mouse that did
	# not land on the chip): the whole reveal is the affordance.
	var pressed_here := false
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed_here = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed_here = true
	if pressed_here:
		_count_gesture()
		unfold()
	accept_event()


func _on_chip() -> void:
	## The routed form (Enter on focus / pad A / a chip tap): the chip's
	## own press IS the gesture.
	if state != State.REVEAL:
		return
	_count_gesture()
	unfold()


func _count_gesture() -> void:
	interactions += 1
