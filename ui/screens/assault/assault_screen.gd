## AssaultScreen — the assault vignette's state machine + input (T-UI-07).
##
## Composed by the Spread as a full-rect child (like the ActionFan: paper
## over the table while open — the ANTI-GOAL is modal chrome, and this is
## not chrome, it is the table RE-LAID as a siege). States:
##
##   odds      — the pre-commit screen: odds bound live from the
##               resolver's pure query (per batch — training and gear
##               settle silently), COMMIT bold, RETREAT free (player
##               choice honored: retreating costs nothing and returns to
##               the spread untouched);
##   resolving — COMMIT went down the host's one write path; the screen
##               drains EXACTLY the one tick the command needs
##               (advance_ticks(1) — the commit is tick-aligned by
##               contract, §5/§15; draining it synchronously means the
##               vignette replays from a SETTLED event stream, never
##               mid-resolution), capturing the battle's events;
##   vignette  — the beats replay ON THE TABLE at authored pacing
##               (AssaultStage.BEAT_SECONDS, 1.5–2.5s per beat through
##               MotionProfile), skippable with ONE input (accessibility
##               + replay value), driven entirely by the BeatScript
##               folded from the captured events;
##   outcome   — the loss lands as the printed chronicle BLOCKQUOTE +
##               the aftermath wash; the win lands as the castle's fall
##               (the card-turn grammar) + the victory double rule, and
##               hands off through `finished` (T-UI-05's restart flow
##               mounts on that seam — this screen never restarts).
##
## FOCUS PATH (Daredevil): odds opens focused on COMMIT (the bold verb),
## the chips are a cyclic trap, back retreats from odds at no cost, the
## vignette needs no focus (one input skips), outcome focuses the close
## chip. Reduced motion collapses the beats to near-instant while the
## printed summaries carry the whole story.
##
## AUDIO HOOKS (the documented sound-shape, no assets yet):
##   beat_landed(beat, index) — per settled beat: advance = the march
##     stride loop begins; skirmish = impact hits as cards strike; gate =
##     the ram's woodblock crack; throne = one resolved chord; rout =
##     scattered drums. A future audio director connects HERE, never to
##     the stage (pacing and drama land in one place).
##   outcome_printed(outcome, script) — the wash + blockquote moment.
extends Control

## A settled beat landed on the table (the AUDIO HOOK — see class docs).
signal beat_landed(beat: Dictionary, index: int)
## The outcome printed (the second AUDIO HOOK).
signal outcome_printed(outcome: StringName, script: Dictionary)
## THE VICTORY-HANDOFF SEAM (T-UI-05 mounts the restart flow here):
## emitted once when the vignette closes, carrying the outcome + script.
signal finished(outcome: StringName, script: Dictionary)

const STAGE_SCENE := preload("res://ui/screens/assault/assault_stage.tscn")

## Authored pacing multiplier: motion settles inside each beat, then the
## beat holds its print for the remainder.
const MOTION_SHARE := 0.55
## The aftermath wash's full-motion duration.
const WASH_SECONDS := 1.6

enum State { CLOSED, ODDS, RESOLVING, VIGNETTE, OUTCOME }

var host: GameHost
var state: int = State.CLOSED

var _stage: AssaultStage
var _router: LayoutRouter
var _view := {}
var _roster_snapshot: Array[Dictionary] = []
var _battle_events: Array[Dictionary] = []
var _script := {}
var _banked_points := 0
## Generation counter: skip() bumps it; stale async loops exit.
var _generation := 0
var _drain_tries := 0
## Live march tweens (killed on skip so a stale tween cannot drag a
## landed card back toward an outdated target).
var _march_tweens: Array[Tween] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_stage = STAGE_SCENE.instantiate() as AssaultStage
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)


# --- open / close -----------------------------------------------------------------------


## Open onto the odds screen. Pure binding off the resolver's query.
func open(p_host: GameHost, p_router: LayoutRouter) -> void:
	host = p_host
	_router = p_router
	_generation += 1
	_battle_events.clear()
	_script = {}
	_banked_points = 0
	_drain_tries = 0
	if host.event_observed.is_connected(_on_event):
		host.event_observed.disconnect(_on_event)
	host.event_observed.connect(_on_event)
	if host.run_state_changed.is_connected(_on_run_state):
		host.run_state_changed.disconnect(_on_run_state)
	host.run_state_changed.connect(_on_run_state)
	if host.sim_advanced.is_connected(_on_ticks):
		host.sim_advanced.disconnect(_on_ticks)
	host.sim_advanced.connect(_on_ticks)
	_stage.regime_id = host.run().regime_id()
	_stage.regime_name = Inks.regime_name(host.run().regime_id())
	_stage.portrait = _router.is_portrait() if _router != null else true
	_stage.wash = 0.0
	if _router != null and not _router.orientation_changed.is_connected(_on_orientation):
		_router.orientation_changed.connect(_on_orientation)
	state = State.ODDS
	visible = true
	_bind_odds()
	# The strip opens with the composition line — the table is set, and
	# the print says what stands against what (an empty strip reads
	# unfinished, the capture find).
	_stage.print_line(Inks.LineClass.PLAIN, _composition_line())
	_focus_commit()


## The odds screen's opening print: the two sides of the fight in one
## line (regime, garrison composition, our number).
func _composition_line() -> String:
	var regime_name := Inks.regime_name(host.run().regime_id())
	if regime_name.is_empty():
		regime_name = "Crown"
	var garrison := AssaultPresenter.garrison_line(_view, regime_name)
	return "Against the %s — %s; our sworn number %d." % [
		regime_name, garrison.to_lower(), int(_view["army_power"])]


func close() -> void:
	if state == State.CLOSED:
		return
	_generation += 1
	var outcome: StringName = _script.get("outcome", &"") as StringName
	state = State.CLOSED
	visible = false
	finished.emit(outcome, _script)


func is_open() -> bool:
	return state != State.CLOSED


func current_beat_index() -> int:
	return _stage.sequence_hashes().size() - 1 if _stage.sequence_hashes().size() > 0 else -1


## The authored visual sequence so far (tests pin the replay contract).
func visual_sequence_hashes() -> Array[int]:
	return _stage.sequence_hashes()


# --- the odds screen --------------------------------------------------------------------


func _bind_odds() -> void:
	_view = AssaultPresenter.odds_view(host.assault().assault_odds(host.engine))
	_stage.bind_odds(_view)
	_stage.set_chips(_odds_chip_actions())
	_wire_chips()


func _odds_chip_actions() -> Array[Dictionary]:
	var commit_enabled: bool = bool(_view["floor_met"]) and int(_view["army_units"]) > 0
	var reason := ""
	if _view["army_units"] <= 0:
		reason = "no army mustered"
	elif not bool(_view["floor_met"]):
		reason = AssaultPresenter.floor_line(_view)
	return [
		{
			"id": "commit", "label": "COMMIT THE STORM", "command": &"commit_assault",
			"subject": &"", "value": 0, "enabled": commit_enabled, "reason": reason,
			"signature": true,
		},
		{
			"id": "retreat", "label": "Fall back", "command": &"",
			"subject": &"", "value": 0, "enabled": true, "reason": "",
			"signature": false,
		},
	]


func _refresh_odds_meters() -> void:
	## Silent drift (training/gear settle without events): the meters
	## re-print per batch; the RANKS rebuild only when the roster itself
	## changed (no churn on every batch).
	var fresh := AssaultPresenter.odds_view(host.assault().assault_odds(host.engine))
	if _roster_signature(fresh) != _roster_signature(_view):
		_view = fresh
		_stage.bind_odds(_view)
		_stage.set_chips(_odds_chip_actions())
		_wire_chips()
		_focus_commit()
		return
	_view = fresh
	_stage.refresh_odds(fresh)


static func _roster_signature(view: Dictionary) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in view["roster"]:
		parts.append("%d:%d" % [int(entry["uid"]), int(entry["total"])])
	return ",".join(parts)


func _wire_chips() -> void:
	for chip in _stage.chips():
		if chip.pressed.is_connected(_on_chip):
			chip.pressed.disconnect(_on_chip)
		chip.pressed.connect(_on_chip.bind(chip.action))


func _on_chip(action: Dictionary) -> void:
	match String(action["id"]):
		"commit":
			commit()
		"retreat":
			retreat()
		"close":
			close()


## RETREAT: player choice honored — back to the spread, no cost, nothing
## submitted, nothing rolled.
func retreat() -> void:
	if state != State.ODDS:
		return
	close()


## COMMIT: the floor gate first (the printed refusal — the sim's own
## denial stays the last-line defense), then the real command down the
## host's one write path, then the synchronous one-tick drain.
func commit() -> void:
	if state != State.ODDS:
		return
	_view = AssaultPresenter.odds_view(host.assault().assault_odds(host.engine))
	if not bool(_view["floor_met"]) or _view["army_units"] <= 0:
		_stage.print_line(Inks.LineClass.WARN,
			"The clerk refuses the paperwork: %s." % AssaultPresenter.floor_line(_view))
		return
	_roster_snapshot = []
	for entry: Dictionary in _view["roster"]:
		_roster_snapshot.append((entry as Dictionary).duplicate(true))
	_battle_events.clear()
	_script = {}
	state = State.RESOLVING
	_stage.set_chips([])
	_wire_chips()
	_stage.print_line(Inks.LineClass.PLAIN, "The standard is raised. The storm is committed.")
	host.submit(&"commit_assault")
	_try_drain()


## Drains EXACTLY the one tick the commit needs (live semantics; the
## events arrive synchronously through the unified feed inside the
## call). Retried from _process while the world is paused.
func _try_drain() -> void:
	if state != State.RESOLVING:
		return
	_drain_tries += 1
	host.advance_ticks(1)
	if state == State.RESOLVING and _drain_tries > 120:
		push_error("assault: commit never resolved after %d drains — closing" % _drain_tries)
		close()


func _process(_delta: float) -> void:
	if state == State.RESOLVING:
		_try_drain()


# --- the event feed ---------------------------------------------------------------------


func _on_event(event: Dictionary) -> void:
	match state:
		State.RESOLVING, State.VIGNETTE:
			_battle_events.append(event)
		_:
			return
	match event["type"]:
		&"assault_beat":
			pass  # the vignette replays these at authored pacing
		&"assault_won", &"assault_lost":
			_begin_vignette()
		&"run_won":
			_banked_points = int(event["value"])
		&"assault_denied":
			# The sim's own last-line defense (e.g. the run died between
			# open and commit): print it and fall back to the odds.
			state = State.ODDS
			_stage.print_line(Inks.LineClass.WARN,
				"The assault is refused — the army is not yet an army (power %d)." % int(event["value2"]))
			_bind_odds()
			_focus_commit()


func _on_run_state(running: bool) -> void:
	## The world moved on from under the odds screen (crush, abort).
	if not running and (state == State.ODDS or state == State.RESOLVING):
		close()


func _on_orientation(portrait_orientation: int) -> void:
	_stage.portrait = portrait_orientation == LayoutRouter.ScreenOrientation.PORTRAIT \
		if _router != null else true


func _on_ticks(_ticks: int) -> void:
	if state == State.ODDS:
		_refresh_odds_meters()


# --- the vignette -----------------------------------------------------------------------


## Fold the captured events into the staged script and play it. The
## script is the WHOLE input: same events -> same beats, same outcome,
## same authored sequence (the replay contract).
func _begin_vignette() -> void:
	_script = BeatScript.build(_battle_events)
	if not BeatScript.holds(_script):
		push_error("assault: malformed beat stream (resolver regression?) — refusing to stage")
		close()
		return
	state = State.VIGNETTE
	_stage.begin_battle(_script, _roster_snapshot)
	_play_beats()


## The authored pacing: apply the beat's settled state, tween the motion
## toward it, print the summary, hold, next. Skip (or reduced motion)
## lands the exact same settled states without the hold.
func _play_beats() -> void:
	var generation := _generation
	var beats: Array = _script["beats"]
	for i in beats.size():
		if generation != _generation:
			return  # skipped or closed mid-play
		var beat: Dictionary = _stage.apply_beat(i)
		var duration := _beat_seconds(beat["phase"])
		_tween_ranks(duration * MOTION_SHARE)
		_stage.print_line(Inks.LineClass.PLAIN,
			AssaultPresenter.beat_summary(_script, i, _roster_snapshot))
		beat_landed.emit(beat, i)  # the AUDIO HOOK
		await get_tree().create_timer(duration).timeout
		if generation != _generation:
			return
	_finish_outcome(false)


## The outcome: aftermath wash settles, the castle's fate lands, the
## BLOCKQUOTE prints, the close chip appears (the player reads at their
## own pace). The sequence is SEALED only after the wash settles, so the
## paced play and the skipped play seal the SAME final state (the replay
## contract). `instant` is the skip path (and reduced motion collapses
## the wash to nothing).
func _finish_outcome(instant: bool) -> void:
	state = State.OUTCOME
	var victory: bool = _script["outcome"] == &"win"
	_stage.apply_outcome(instant)
	var generation := _generation
	if instant or not MotionProfile.entrances_enabled():
		_stage.wash = 1.0
	else:
		var tween := create_tween()
		tween.tween_property(_stage, "wash", 1.0, WASH_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(WASH_SECONDS + 0.05).timeout
		if generation != _generation:
			return  # closed (or re-opened) mid-wash
		_stage.wash = 1.0
	var regime_name := Inks.regime_name(host.run().regime_id())
	_stage.print_outcome(
		AssaultPresenter.outcome_block(_script, regime_name, _banked_points), victory)
	_stage.set_chips([{
		"id": "close",
		"label": "Deal the next hand" if victory else "Return to the table",
		"command": &"", "subject": &"", "value": 0, "enabled": true,
		"reason": "", "signature": victory,
	}])
	_wire_chips()
	_stage.seal_sequence()
	outcome_printed.emit(_script["outcome"], _script)  # the AUDIO HOOK
	for chip in _stage.chips():
		chip.grab_focus.call_deferred()
		break


## SKIP — one input, the whole vignette: every remaining beat's settled
## state lands in order (the strike sequence accumulates exactly as the
## pacing would have applied it), then the outcome prints instantly.
func skip() -> void:
	if state != State.VIGNETTE:
		return
	_generation += 1
	_kill_march_tweens()
	var beats: Array = _script["beats"]
	var played := _stage.sequence_hashes().size()
	for i in range(played, beats.size()):
		_stage.apply_beat(i)
		_stage.print_line(Inks.LineClass.PLAIN,
			AssaultPresenter.beat_summary(_script, i, _roster_snapshot))
	_stage.snap_ranks()
	_finish_outcome(true)


func _beat_seconds(phase: StringName) -> float:
	return MotionProfile.duration(float(AssaultStage.BEAT_SECONDS.get(phase, 1.8)))


## March motion: each surviving card tweens toward its authored target.
## The fallen keep where they fell (their target never moves again).
## Tweens are tracked so skip() can kill them mid-flight (a landed skip
## must never be dragged back by a stale tween).
func _tween_ranks(duration: float) -> void:
	_kill_march_tweens()
	if duration <= 0.05:
		_stage.snap_ranks()
		return
	for rank in _stage.ranks():
		var tween := rank.create_tween()
		_march_tweens.append(tween)
		tween.set_parallel(true)
		tween.tween_property(rank, "position", rank.target, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(rank, "size", rank.target_size, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _kill_march_tweens() -> void:
	for tween in _march_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_march_tweens.clear()


# --- input ------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if state == State.CLOSED:
		return
	if event.is_action_pressed(&"back"):
		match state:
			State.ODDS:
				retreat()
			State.VIGNETTE:
				skip()
			State.OUTCOME:
				close()
		get_viewport().set_input_as_handled()
		return
	if state == State.VIGNETTE:
		# ONE INPUT SKIPS, every mode: the project primary (keyboard/pad,
		# non-positional) and any unhandled press (touch/mouse that did
		# not land on a chip — there are none mid-vignette).
		if event.is_action_pressed(&"primary") and not (event is InputEventMouseButton) \
				and not (event is InputEventScreenTouch):
			skip()
			get_viewport().set_input_as_handled()
		elif (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed):
			skip()
			get_viewport().set_input_as_handled()


func _focus_commit() -> void:
	for chip in _stage.chips():
		if String(chip.action.get("id", "")) == "commit":
			chip.grab_focus.call_deferred()
			return


## Test/inspection seam: the composed stage.
func stage() -> AssaultStage:
	return _stage
