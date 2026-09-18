## The Spread — the game's home screen (T-UI-03).
##
## "The game IS the conspirators' card table" (design brief §3): this
## screen binds a REAL GameHost to the responsive foundation so card
## positions reflect live sim state at all layout sizes —
##   - conspirator cards: gate offers + the estate roster (workers,
##     trainees, army) + the built buildings, one composed CardFrame each,
##     state by LINE FORM;
##   - resource pips along the table edge (live values, abbreviated
##     idle-scale numerals);
##   - the Watchful Eye card creeping into the periphery as suspicion
##     rises (position + line form + dread scale — never color alone);
##   - ground tone deepening by run phase (recruiting -> training ->
##     ready-to-storm, aftermath after);
##   - the chronicle strip printing recent events in-world (offers,
##     completions, crackdowns land as printed lines — never popups);
##   - the run header (leader name + regime ink).
##
## LIVE UPDATES ARE EVENT-DRIVEN: the presenter's refresh_targets_for maps
## each event to the view sections it touches; the screen rebinds exactly
## those (stats counts every pass — tests assert no whole-state polling).
## `sim_advanced` (one signal per processed batch) is the only periodic
## hook: pips + training countdowns + the phase probe ride it, because
## production accrual and army growth settle silently (no events).
##
## Deterministic UI from sim state: every bind derives from the
## presenter's view model — same sim state -> same rendered spread
## (layout_hash pins it; focus ids are index-synced so the router's swap
## equivalence is part of the render too).
##
## Input parity (the T-UI-02 foundation): focus chains follow card order
## in both slots (the router restores place across swaps); every
## interactive card keeps the 48-unit grip. The dev accel verbs —
## `debug_fast_forward` (time scale 1x -> 60x -> 600x) and `pause` (the
## world-freeze seam) — are gated behind CS_DEBUG_CHROME=1 (the
## boot-shell fix: a table mounted from the front door runs real, no
## autopilot keys); CARD INTERACTIONS (T-UI-04) live on this table:
## pressing a focused card or tapping one fans its contextual actions
## (CardActions -> ActionFan); the PROMOTE action's command, when it
## lands, turns the trainee card over — CardFrame.play_promotion_flip,
## the signature moment — and cards that join a live table deal in with
## the slide-and-settle entrance (CardMotion).
##
## SUSPICION EVENTS (T-UI-06) live on this table too: warn-zone entries
## and telegraph armings slide a CHOICE CARD onto the table's edge
## (print-styled, focusable, skippable — offering the real quieting
## verbs, never invented ones), a landed crackdown prints as the
## chronicle BLOCKQUOTE while the Eye strikes and the ground flashes, and
## the crush plays the run-death beat (cards struck + swept, the crushing
## quote, then T-UI-05's loss-restart reveal). All of it paper on the
## table — the anti-goal is popup chrome.
##
## THE CHECK-IN (T-UI-09): a RESUMED session (anything but the fresh
## first deal) opens with the intro's SHORT unfold variant — the same
## hand's leader under the same regime, the away line from the REAL
## catch-up report, auto-opening inside the 3-second promise — and the
## resolved away window prints as a while-you-were-away BLOCKQUOTE on the
## table (CatchUpPrint's rows: elapsed/capped, per-type resources,
## arrivals/completions/promotions, suspicion, crackdowns-with-weight),
## its headline scrolling into the chronicle strip. Never a "welcome
## back" modal: the quote dwells and folds itself, the table is live
## beneath it the whole time, focus lands on the first actionable card.
##
## Dev inspection hook (not a game path): CS_SPREAD_SHOT=/path.png renders
## for a settling window and saves one capture, then quits; pair with
## CS_SPREAD_LOUD=1 for the pressured state (see _capture_hook), with
## CS_SPREAD_PROMOTE=1 to capture THE PROMOTE MOMENT mid-flip (or =2 for
## the landed flip with its flourish), with CS_SPREAD_FAN=1 to capture
## an open action fan, with CS_SPREAD_INTRO=1/2 for the leader intro at
## reveal / mid-unfold (T-UI-05), with CS_SPREAD_RESTART=win/loss for
## a full restart session's reveal captures, with
## CS_SPREAD_SUSPICION=1/2/3 for the suspicion moments (T-UI-06: the
## telegraph choice card / the landed-crackdown blockquote / the crushed
## beat's quote over the swept table), with CS_SPREAD_CHRONICLE=1/2 for
## the chronicle ledger (T-UI-08: three real hands / the 50-hand ring,
## newest + oldest pages), with CS_SPREAD_CATCHUP=1/2/4 for the
## check-in beats (T-UI-09: a mid-session away window resolved on the
## live table / a full process-restart resume through a real save — via
## =2 then =3, the short unfold + the while-you-were-away print with the
## foreground->actionable measurement printed / a crackdown landing
## INSIDE the away window: the print's STRIKE row + signed seizures),
## with CS_SPREAD_LEGACY=1/2/3 for the growing deck (L1-C: fresh locked /
## mid-run buys / the full tree), or with CS_SPREAD_ESCALATION=1/2/3 for
## the L2-C presence (the win-restart reveal over a seeded standing
## garrison / the odds table vs the cycle-2 veterans / the REAL capture
## end to end: beat, reveal, chronicle line)
## with CS_SPREAD_DAYSHEET=1/2 for the run's own page (finishing
## refinement #2: the day-sheet open over a printed history / the
## header verbs row itself), with CS_SPREAD_PRESS=1/2 for the press-room
## card (finishing refinement #5: the preferences card open / the same
## card after the 1.3x step is pressed through the real chip — the live
## re-flow), or with CS_SPREAD_FIRST=1/2/3 for the
## first-session beats (T-UI-10:
## the empty spread + the gate hint / the assignment + build hints with
## the focused plot card / the trickle print + the pacing report).
extends ResponsiveScreen

const RUN_HEADER_SCRIPT := preload("res://ui/screens/spread/run_header.gd")
const LEDGER_VERBS_ROW_SCRIPT := preload("res://ui/screens/spread/ledger_verbs_row.gd")
const WATCHFUL_EYE_SCRIPT := preload("res://ui/screens/spread/watchful_eye.gd")
const ACTION_FAN_SCRIPT := preload("res://ui/screens/spread/action_fan.gd")
const SUSPICION_EVENTS_SCRIPT := preload("res://ui/screens/spread/suspicion_events.gd")
const AssaultScreenScript := preload("res://ui/screens/assault/assault_screen.gd")
const ASSAULT_SCENE := preload("res://ui/screens/assault/assault_screen.tscn")
const IntroScreenScript := preload("res://ui/screens/intro/intro_screen.gd")
const INTRO_SCENE := preload("res://ui/screens/intro/intro_screen.tscn")
const ChronicleScreenScript := preload("res://ui/screens/chronicle/chronicle_screen.gd")
const CHRONICLE_SCENE := preload("res://ui/screens/chronicle/chronicle_screen.tscn")
const DaySheetScreenScript := preload("res://ui/screens/spread/day_sheet_screen.gd")
const HowToScreenScript := preload("res://ui/screens/howto/howto_screen.gd")
const OBJECTIVE_NOTE_SCRIPT := preload("res://ui/screens/spread/objective_note.gd")
const PressRoomScreenScript := preload("res://ui/screens/spread/press_room_screen.gd")
const LegacyScreenScript := preload("res://ui/screens/legacy/legacy_screen.gd")

## Default demo seed (deterministic identity + arrival draw; override
## with CS_SEED).
const DEFAULT_SEED := 20261103

## Demo time-scale ladder cycled by debug_fast_forward.
const TIME_SCALES: Array[float] = [1.0, 60.0, 600.0]

## Autosave cadence for the demo session (every sim hour).
const AUTOSAVE_TICKS := SimEngine.TICKS_PER_SIM_HOUR

## Chronicle rows the slot strip prints (the OrientationSlot contract).
const STRIP_LINES := 2

var host: GameHost
var presenter := SpreadPresenter.new()
var demo_policy: DemoPolicy
var time_scale_index := 0

## The platform boundary policy (T-PERF-01): OS lifecycle notifications
## forwarded from `_notification` into the host's background/foreground
## seams. Desktop focus loss keeps the world running — the decision of
## record lives in ui/host/app_lifecycle.gd.
var lifecycle: AppLifecycle

## The first-session onboarding layer (T-UI-10): guided-by-the-world
## nudges — printed strip cues + focus on the affordance card, once per
## install, never for a returning player. Inert unless this boot is the
## one true first deal (see FirstSession.arms).
var first_session: FirstSession

## Refresh instrumentation (tests assert targeted updates, no polling).
var stats := {
	&"view_builds": 0, &"card_rebinds": 0, &"card_list_renders": 0, &"pip_refreshes": 0,
	&"eye_binds": 0, &"header_binds": 0, &"phase_binds": 0, &"chronicle_prints": 0,
	&"fans_opened": 0, &"actions_submitted": 0, &"refusals_printed": 0,
	&"flips_played": 0, &"flip_replays": 0, &"entrances": 0,
	&"assaults_opened": 0, &"assaults_finished": 0,
	&"intros_opened": 0, &"intros_unfolded": 0,
	&"choice_cards": 0, &"choices_made": 0, &"quotes_printed": 0,
	&"crushes_played": 0, &"eye_strikes": 0, &"ground_flashes": 0,
	&"chronicles_opened": 0, &"chronicles_closed": 0,
	&"day_sheets_opened": 0, &"day_sheets_closed": 0,
	&"press_rooms_opened": 0, &"press_rooms_closed": 0,
	&"legacies_opened": 0, &"legacies_closed": 0,
	&"howtos_opened": 0, &"howtos_closed": 0,
	&"howto_offers": 0, &"howto_answered": 0,
	&"note_skips": 0, &"objective_advances": 0, &"hint_rows": 0,
	&"type_scale_changes": 0, &"motion_changes": 0,
	&"catch_up_prints": 0, &"quiet_lines": 0,
	&"first_nudges": 0, &"first_focuses": 0,
	&"primer_lines": 0, &"autosave_lines": 0,
}

## The leader intro / restart reveal (T-UI-05): ON at boot, from the
## assault's finished("win") seam, and off run_lost/run_aborted. Sibling
## suites that pin THE TABLE set this false at mount — the intro's own
## suite owns the opening flow both ways.
var intro_enabled := true

## How this mount ENTERS the game (the boot shell sets it BEFORE adding
## the screen to the tree; the self-hosted demo and test mounts leave it
## auto):
##   auto      — today's rule: the fresh first deal opens T-UI-05's
##               reveal, every other session opens T-UI-09's check-in;
##   new_hand  — the boot shell's NEW-RUN path (a confirmed abandon) and
##               the ended-meta BEGIN: the reveal derives from the ACTUAL
##               chronicle (win/loss restart) and the intro itself deals
##               the new hand — never a check-in re-deal of a dead hand.
const ENTRY_AUTO := &"auto"
const ENTRY_NEW_HAND := &"new_hand"
var entry_mode: StringName = ENTRY_AUTO

## Dev accel gate (the boot-shell fix): the F/P time-scale + freeze verbs
## are demo/debug chrome — available only under CS_DEBUG_CHROME=1. A
## table mounted from the boot shell runs at 1x wall pace with no
## autopilot keys; the capture drives fast_forward programmatically and
## never needs them.
var debug_accel := false

var _view := {}
var _scale_chip: Label
var _fan: ActionFan
var _suspicion: SuspicionEvents
var _assault: AssaultScreenScript
var _intro: IntroScreenScript
var _chronicle: ChronicleScreenScript
var _pre_assault_focus: Control
## THE DAY-SHEET (finishing refinement #2): the live run's own page — the
## retrieval surface for every line this hand has printed (strip rows +
## blockquote payloads). The chronicle screen's little sibling, opened
## from the header's Day-Sheet verb; run-scoped, never persisted (the
## durable record of a run is the chronicle entry it becomes).
var _day_sheet: DaySheetScreen
## THE PRESS-ROOM (finishing refinement #5): the game's settings card —
## the surface for the accessibility seams (the type scale, reduced
## motion), paper like its siblings and opened from the header's
## Press-Room verb. Its steps write preferences into the META domain
## (persisted across hands, sessions and restarts) and apply LIVE.
var _press_room: PressRoomScreen
## THE LEGACY (L1-C): the growing deck — the meta-screen where banked
## legacy points buy permanent upgrades between runs. Paper like its
## siblings, opened from the header's The-Legacy verb; buys go down the
## REAL host command (unlock_purchase) and apply at the next run start
## (the L1-A rule, printed honestly when a hand is live).
var _legacy: LegacyScreen
## THE HOW-TO PAMPHLET (the tutorial upgrade): the printed primer —
## paper like its siblings, opened from the title card's chip and the
## header's How-to-Play verb, and OFFERED once on the first fresh boot
## (a small declinable paper: "I know this table"). The offer's answer
## persists in the META domain (the first_session "howto" flag).
var _howto: HowToScreenScript
## This boot was the one true fresh first deal (the boot intro's own
## rule, snapshotted at mount) — the offer rides its intro's fold.
var _fresh_first_deal := false
## The pamphlet was opened from a chip (focus returns there when it
## folds); the offer path returns focus to the table instead.
var _howto_from_chip := false
## The line-form primer's session latch (finishing refinement #2, P2):
## one printed teaching line at the first dashed (in-progress) edge the
## session shows — once per session, the lightest honest cadence.
var _primer_printed := false
## The telegraph-armed latch (finishing refinement #3): true while the
## Watchful Eye holds the armed lane — drives the card field's reserve
## and the per-batch countdown refresh (the plate's numeral must never
## go stale while the player watches it).
var _eye_armed := false
## A run ended WHILE the vignette was open (the edge crush): the intro
## mounts after the vignette closes — paper never stacks on paper. When
## the ending was a real CRUSH, the crush beat plays first (T-UI-06) and
## the intro mounts when it resolves.
var _intro_after_assault := false
var _crush_after_assault := false
## A crush landed while the intro itself was open (an away-window death
## behind the reveal): the beat starts when the reveal folds away.
var _crush_after_intro := false
## A run_crushed event arrived in the drain that is ending the run — the
## death goes through the CRUSHED BEAT (cards struck + swept, the crushing
## blockquote), then T-UI-05's loss-restart reveal.
var _crush_seen := false
## True while the crush beat owns the table: card re-deals are FROZEN (the
## table stays cleared for the story; the intro's restart re-deals).
var _table_frozen := false
## The pre-crackdown view's card list (captured at crackdown_struck — the
## gate crowd's names for the scatter line; the sim mutates first, the
## events arrive after).
var _pre_crackdown_cards: Array = []
var _flip_queue := CardMotion.PromotionFlipQueue.new()
## The boot-resolved away window awaiting the check-in unfold's close
## (the intro's paper folds first, THEN the blockquote prints on the
## table it revealed — never stacked paper).
var _pending_catch_up := {}
## Dev-inspection wall mark (the resumed-boot capture's foreground
## reference — see _catch_up_then_capture; never a game path).
var _catchup_boot_msec := -1
## Entrance deals are armed only after the FIRST full bind — the boot deal
## is the packet unfold's business (T-UI-05); cards JOINING a live table
## (recruits arriving, offers becoming estate cards) slide-and-settle.
var _entrances_armed := false
## THE STAGED FIRST MOMENTS (the first-deal coverage fix): true while the
## once-only how-to offer paper owns the table on the fresh first deal —
## recruit deals that arrive behind it WAIT (the table shows the plots it
## was dealt before the reveal), and slide-and-settle the moment the
## paper is answered. The paper blocks the table's input anyway; without
## the hold its veil hid newly dealt offers, so dismissing it revealed a
## fan already fanned OVER the staked plots. Never set for returning
## players (no offer — deals land immediately, exactly as today).
var _deals_held := false


func _ready() -> void:
	# THE PRESS-ROOM'S BOOT SEAM (finishing refinement #5): the persisted
	# preferences apply BEFORE the type-scale boot seam and BEFORE any
	# chrome bakes sizes — a player who set 1.3x last session boots at
	# 1.3x. The host's boot already loaded the meta domain.
	_apply_boot_preferences()
	# The T-QA-05 type-scale seam FIRST: every label this screen (and the
	# paper layers below) creates reads the scaled sizes at build time.
	TypeScale.ensure_applied()
	# Tests may attach a pre-driven host BEFORE adding the scene to the
	# tree; the demo builds its own otherwise.
	if host == null:
		host = build_demo_host()
	# THE BOOT-SHELL ACCEL GATE (the F5 fix): F/P are demo/debug verbs —
	# a table mounted from the real front door runs at 1x with no
	# autopilot keys unless CS_DEBUG_CHROME=1 asks for the dev chip's
	# world (the invisible actions ride the same gate as their chip).
	debug_accel = OS.get_environment("CS_DEBUG_CHROME") == "1"
	# THE PLATFORM BOUNDARY (T-PERF-01): this screen IS the platform host —
	# `_notification` forwards the OS lifecycle moments (application
	# paused/resumed, window close) into the AppLifecycle policy:
	# background = pause pacing + take the away anchor + flush the autosave;
	# foreground = the capped catch-up resolves through the real engine and
	# pacing resumes.
	lifecycle = AppLifecycle.new()
	lifecycle.host = host
	super._ready()
	_compose_slot_chrome()
	_build_action_fan()
	_build_suspicion_layer()
	_build_assault_screen()
	_build_intro_screen()
	_build_day_sheet_screen()
	_build_press_room_screen()
	_build_legacy_screen()
	_build_howto_screen()
	_build_objective_notes()
	_build_chronicle_screen()
	host.event_observed.connect(_on_event)
	host.sim_advanced.connect(_on_ticks)
	host.run_state_changed.connect(func(_running: bool) -> void: refresh_from_state())
	host.catch_up_resolved.connect(_on_catch_up_resolved)
	get_viewport().size_changed.connect(_on_layout_changed)
	get_router().orientation_changed.connect(func(_o: int) -> void: _on_layout_changed())
	_build_debug_chip()
	# THE FIRST SESSION (T-UI-10): arm the once-only nudge layer on the
	# one true first deal — the fresh boot's "seen" flag persists here,
	# so every later boot of this install (resume, restart, new hand) is
	# nudge-free by construction. The fresh-first-deal snapshot (the
	# boot intro's own rule) is what offers the pamphlet once.
	first_session = FirstSession.new()
	first_session.begin(host)
	_fresh_first_deal = host.is_run_running() and host.meta.runs_recorded == 0 \
		and host.engine.tick_count <= 1
	# DEFERRED: the slots lay themselves out via a deferred call at their
	# own _ready (queued before this one), so the first bind must land
	# AFTER settled slot rects — column ladders and the Eye's perch read
	# the real spread geometry, never the pre-layout zero (the exact
	# stale-columns failure the layout-determinism test caught).
	_refresh_from_state_deferred()
	_capture_hook()


## The deferred first bind (see _ready), THEN the boot intro check — the
## reveal papers over an already-bound table, never a blank one. The
## finalization pass rides the mount too (readability r3): a dense
## initial bind's plates land their honest heights through the fit
## cascade, and the bounded finalization loop is what finishes it —
## the r2 pass ran only on layout CHANGED events, and a first bind that
## never resized anything stalled short of stable (the dense-estate
## find: plates rendering no print at all).
func _refresh_from_state_deferred() -> void:
	refresh_from_state.call_deferred()
	_maybe_open_boot_intro.call_deferred()
	_maybe_open_resumed_intro.call_deferred()
	_finalize_mount.call_deferred()


func _finalize_mount() -> void:
	if _view.is_empty():
		return  # the bind never landed — nothing to finalize
	_finalize_passes = 0
	_finalize_topology()


## The seeded demo session: a real save-backed host. CS_DEMO_RESET=1 (the
## Makefile default) wipes the demo save root so every `make run-game` is
## the same seeded fresh run; CS_DEMO_RESET=0 continues the session.
## CS_DEMO_NOW=<epoch> injects the platform host's "now" into boot (the
## T-UI-09 capture path: a resumed boot resolves its away window through
## the real service — timestamps injected, never read from the OS).
func build_demo_host() -> GameHost:
	var root := "user://saves"
	if OS.get_environment("CS_DEMO_RESET") != "0":
		_wipe_save_root(root)
	var seed_value := DEFAULT_SEED
	var seed_text := OS.get_environment("CS_SEED")
	if not seed_text.is_empty() and seed_text.is_valid_int():
		seed_value = int(seed_text)
	var demo := GameHost.new(seed_value, root)
	demo.autosave_interval_ticks = AUTOSAVE_TICKS
	if OS.get_environment("CS_SPREAD_CATCHUP") == "3":
		# Dev-inspection wall mark for the 3-second promise measurement
		# (see _catch_up_then_capture; not a game path).
		_catchup_boot_msec = Time.get_ticks_msec()
	demo.boot(_demo_now_epoch())
	if OS.get_environment("CS_SPREAD_LOUD") == "1":
		demo_policy = DemoPolicy.new(40, 40, true)
	else:
		demo_policy = DemoPolicy.new(16, 8, false)
	return demo


## The platform host's injected "now" for the demo (0 = none — the
## session boots without a foreground boundary; T-PERF-01 wires the real
## platform seam).
func _demo_now_epoch() -> int:
	var text := OS.get_environment("CS_DEMO_NOW")
	if not text.is_empty() and text.is_valid_int():
		return int(text)
	return 0


func _wipe_save_root(root: String) -> void:
	## Platform-host housekeeping for the demo (user:// only, never res://).
	if not root.begins_with("user://"):
		return
	for file in DirAccess.get_files_at(root):
		DirAccess.remove_absolute(root + "/" + file)


# --- full re-render (boot, run boundaries, catch-up, tests) --------------------------


## Rebuild the WHOLE view and rebind every section in both slots. The
## deterministic path: the same sim state always produces the same binds.
func refresh_from_state() -> void:
	stats[&"view_builds"] += 1
	_view = SpreadPresenter.build_view(host)
	_bind_cards_list()
	_bind_pips()
	_bind_eye()
	_bind_header()
	_bind_phase()
	_bind_chronicle()
	_bind_objective_note()
	_entrances_armed = true
	_validate_open_fan()


## Determinism oracle over one slot's RENDERED layout: card ids in order +
## their settled global rects + the Eye's position. Same sim state ->
## same hash (tests pin it).
func layout_hash(slot: OrientationSlot) -> int:
	var spread := slot.get_spread()
	var h := 0x811C9DC5
	for i in spread.get_child_count():
		var card: Control = spread.get_child(i) as Control
		if card == null:
			continue
		h = _mix(h, String(card.get_meta(&"spread_card_id", "")).hash())
		var rect: Rect2 = card.get_global_rect()
		h = _mix(h, int(rect.position.x * 100.0))
		h = _mix(h, int(rect.position.y * 100.0))
		h = _mix(h, int(rect.size.x * 100.0))
		h = _mix(h, int(rect.size.y * 100.0))
	var eye := eye_of(slot)
	if eye != null:
		h = _mix(h, int(eye.global_position.x * 100.0))
		h = _mix(h, int(eye.global_position.y * 100.0))
	return h


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF


# --- event-driven targeted refresh ----------------------------------------------------


## ONE event: map -> targeted rebinds. Never a whole-state pass here
## (only the "full" target — run boundaries, catch-up, unknown kinds).
## The suspicion-event hooks (T-UI-06) run BEFORE the targets loop — a
## "full" target RETURNS out of this function.
func _on_event(event: Dictionary) -> void:
	# THE DAY-SHEET'S PAGE TURN (finishing refinement #2): a new hand was
	# dealt — the clerk starts a fresh page BEFORE the boundary's own line
	# prints, so the new page opens with its own announcement. Ended-run
	# lines stay on the page they ended (the aftermath is still readable).
	if event["type"] == &"run_started" or event["type"] == &"run_restarted":
		presenter.begin_day_sheet_page()
	var row: Variant = presenter.chronicle_line_for(event, host)
	if row != null:
		presenter.push_row(row)
		_bind_chronicle()
	# The first-session beat (T-UI-10) runs BEFORE the targeted rebinds
	# so run-boundary events reach the layer even on the "full" path
	# (graduation); the ROW prints now (newest strip line — the row was
	# already pushed above), while the FOCUS nudge defers to the end of
	# the frame so the event's own card rebinds exist first. The arc's
	# objective triggers ride the same call; the note re-binds after.
	if first_session != null:
		var nudge: Dictionary = first_session.on_event(event, host)
		if not nudge.is_empty():
			_deliver_nudge(nudge)
	_bind_objective_note()
	# THE CONTEXTUAL FIRST-TIME HINTS (the tutorial upgrade): once-EVER
	# plain-language lines at the key moments (the first warn, the first
	# legacy bank), flag-gated in the META domain. One strip row, ever.
	var hint: Dictionary = FirstSession.hint_on_event(event, host)
	if not hint.is_empty():
		stats[&"hint_rows"] += 1
		presenter.push_row(hint["row"])
		_bind_chronicle()
	_on_suspicion_event(event)
	# A run ENDED by failure (the suspicion crush; the thin abort): the
	# CRUSHED BEAT plays first when the death was a real crush (the table
	# struck + swept, the crushing blockquote — T-UI-06), and the leader
	# intro mounts with the loss reveal when it resolves — the new leader
	# under the SAME regime + "the regime remembers". DEFERRED so the
	# aftermath's full refresh (the "full" target below RETURNS) prints
	# the beat first. Mid-vignette ends wait for the vignette's close
	# (paper on paper).
	if event["type"] == &"run_lost" or event["type"] == &"run_aborted":
		var from_crush := _crush_seen
		_crush_seen = false
		if _assault != null and _assault.is_open():
			_intro_after_assault = true
			_crush_after_assault = from_crush
		elif from_crush and _intro != null and _intro.is_open():
			# The world crushed beneath an open reveal (an away window, or
			# the dev drive): the beat waits for the paper to fold — the
			# reveal's close starts the story, never stacks on it.
			_crush_after_intro = true
		elif from_crush:
			_start_crush_beat.call_deferred()
		elif intro_enabled:
			_open_intro.call_deferred()
	var targets := SpreadPresenter.refresh_targets_for(event["type"])
	# THE SIGNATURE MOMENT (T-UI-04): an army promotion (knight/archer —
	# a terminal combat rank) turns the card over. The flip owns the card
	# rebind (plates swap at the 90-degree crossing), so the plain "card"
	# target is consumed here; phase still re-binds (the ground deepens).
	var flip_owns_card := false
	if event["type"] == &"unit_promoted" and _is_army_def(event["subject"]):
		flip_owns_card = _on_army_promoted(event)
	var uid := int(event["value"])
	for target: StringName in targets:
		if flip_owns_card and target == &"card":
			continue
		match target:
			&"full":
				refresh_from_state()
				return
			&"cards":
				# The card LIST changed: re-derive the roster cards only (a
				# section read, NOT a whole-view build — pips/eye/header
				# stay on their own channels).
				stats[&"card_list_renders"] += 1
				_view["cards"] = SpreadPresenter.cards_view(host)
				_bind_cards_list(false)
			&"card":
				_rebind_card_by_uid(uid)
			&"pips":
				_bind_pips()
			&"eye":
				_bind_eye()
			&"phase":
				_bind_phase()
			&"chronicle":
				pass  # printed above


## The suspicion vocabulary's own hooks (T-UI-06): choice cards at the
## warn/telegraph moments (live deliveries only — an away window's beats
## printed in the strip already), the Eye's strike/retreat pulses, the
## crackdown blockquote, the crush flag for the run-death beat, and the
## choice card folding whenever its moment passes.
func _on_suspicion_event(event: Dictionary) -> void:
	if _suspicion == null:
		return
	var kind: StringName = event["type"]
	var live := not host.delivering_catch_up
	match kind:
		&"suspicion_warn":
			if live:
				_open_suspicion_choice(event)
		&"suspicion_telegraph":
			if live:
				_open_suspicion_choice(event)
		&"crackdown_cancelled":
			_on_telegraph_cancelled()
		&"crackdown_struck":
			if live:
				_on_crackdown_struck(event)
			else:
				_suspicion.fold_choice()
		&"crackdown_seized":
			if live:
				_on_crackdown_seized(event)
		&"crackdown_scattered":
			if live:
				_on_crackdown_scattered(event)
		&"run_crushed":
			_crush_seen = true
			_suspicion.fold_choice()
		&"run_lost", &"run_aborted", &"run_won":
			_suspicion.fold_choice()


## Per-batch periodic hook (the ONLY polling-adjacent path, one signal
## per processed batch — not per frame): pips (production settles
## silently), training countdown plates, the phase probe (army growth is
## silent too), the demo policy cadence, and the telegraph choice card's
## live countdown (it rides the Eye's own per-batch channel).
func _on_ticks(ticks: int) -> void:
	stats[&"pip_refreshes"] += 1
	# has(), not is_empty(): an event can partially fill the view (the cards
	# section) before the deferred first bind — pips wait for the real thing.
	if not _view.has("resources"):
		return
	if _suspicion != null and _suspicion.choice_is_open() and bool(_suspicion.choice_model().get("urgent", false)):
		_suspicion.refresh_countdown(SpreadPresenter.eye_hours_left(host))
	# THE ARMED EYE'S COUNTDOWN rides the same per-batch channel as the
	# choice card's (finishing refinement #3): the plate's numeral is now
	# the loud one — a stale hour on the big mark would be worse than the
	# old small one. The eye's own targeted rebind; nothing else moves.
	if _eye_armed:
		_bind_eye()
	var view_resources: Array = _view["resources"]
	for i in view_resources.size():
		view_resources[i]["amount"] = host.engine.get_resource(view_resources[i]["id"])
	_bind_pips()
	_rebind_training_cards()
	_bind_phase()
	# The first-session per-batch beats (T-UI-10): the trickle watch
	# (production settles silently — the same channel the pips ride) and
	# the crowded-table graduation. The contextual promotion hint rides
	# the same batch (its moment is a state, not an event).
	if first_session != null:
		var nudge: Dictionary = first_session.on_ticks(host)
		if not nudge.is_empty():
			_deliver_nudge(nudge)
	var state_hint: Dictionary = FirstSession.hint_on_ticks(host)
	if not state_hint.is_empty():
		stats[&"hint_rows"] += 1
		presenter.push_row(state_hint["row"])
		_bind_chronicle()
	_bind_objective_note()
	if demo_policy != null and demo_policy.on_ticks(ticks):
		demo_policy.apply(host)


# --- the first-session nudges (T-UI-10) ----------------------------------------------------


## One first-session beat landed: the hint prints as a strip row (the
## world's own paper — it blocks nothing and scrolls away as the world
## keeps printing), and the focus nudge moves focus to the beat's
## affordance card when the table owns input — the highlight IS the
## focus ring, the same ring pad/keyboard play sees (input parity by
## construction). Paper politeness: never steal focus while a fan is
## open or story paper (choice card, vignette, reveal, quote) is up.
func _deliver_nudge(nudge: Dictionary) -> void:
	stats[&"first_nudges"] += 1
	if nudge.has("row"):
		presenter.push_row(nudge["row"])
		_bind_chronicle()
	_bind_objective_note()
	var focus_id := String(nudge.get("focus", ""))
	if focus_id.is_empty():
		return
	# DEFERRED: the beat's own card rebinds land later in this same event
	# drain (the arrival creates the offer card on the "cards" target);
	# the focus nudge lands once the paper exists.
	_apply_nudge_focus.call_deferred(focus_id)


## The focus half of a nudge (deferred past the event's rebinds): parks
## focus on the beat's affordance card when the table owns input — the
## highlight IS the focus ring, the same ring pad/keyboard play sees
## (input parity by construction). Paper politeness: never steal focus
## while a fan is open or story paper (choice card, vignette, reveal,
## quote) is up.
func _apply_nudge_focus(focus_id: String) -> void:
	if _fan != null and _fan.is_open():
		return
	if _assault != null and _assault.is_open():
		return
	if _intro != null and _intro.is_open():
		return
	if _suspicion != null and (_suspicion.choice_is_open() or _suspicion.quote_is_open()):
		return
	var node := _card_node_in(get_active_slot() as OrientationSlot, focus_id)
	if node != null:
		stats[&"first_focuses"] += 1
		node.grab_focus()


# --- the guided objective note (the tutorial upgrade) ---------------------------------------


## Build the clerk's note ONCE per slot (the Eye's rule: both slots carry
## their own, equivalence across orientation swaps). The note is paper
## pinned at the table's LEFT edge; the table makes way through
## CardSpread.left_reserve for exactly as long as the note stands.
func _build_objective_notes() -> void:
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var note := OBJECTIVE_NOTE_SCRIPT.new()
		note.name = "ObjectiveNote"
		slot.add_child(note)
		note.skip_pressed.connect(_on_note_skip)


func _note_of(slot: OrientationSlot) -> OBJECTIVE_NOTE_SCRIPT:
	for child in slot.get_children():
		if child is OBJECTIVE_NOTE_SCRIPT:
			return child as OBJECTIVE_NOTE_SCRIPT
	return null


## The note's bind + the lane's honest enforcement: when the note stands,
## the spread reserves its lane (cards never under-print it); when it
## folds, the lane lifts and the table re-centers. The bind is cheap and
## idempotent — called from the full refresh and after every event/batch
## the arc's hooks ride.
func _bind_objective_note() -> void:
	if host == null:
		return
	var objective := {}
	if first_session != null and first_session.active:
		objective = FirstSession.current_objective(host)
	var lane := 0.0
	if not objective.is_empty():
		lane = OBJECTIVE_NOTE_SCRIPT.note_lane()
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var spread := slot.get_spread() as CardSpread
		if spread != null and absf(float(spread.get("left_reserve")) - lane) > 0.01:
			# A re-sort must never strand a settling card short of its seat.
			CardMotion.snap_all(spread)
			spread.set("left_reserve", lane)
			spread.queue_sort()
		var note := _note_of(slot)
		if note == null:
			continue
		if not objective.is_empty():
			_place_note(slot, note)
		note.bind(objective)


## The note's seat: the spread band's LEFT edge, vertically centered —
## the Eye's perch mirrored (always fully inside the slot).
func _place_note(slot: OrientationSlot, note: OBJECTIVE_NOTE_SCRIPT) -> void:
	var spread_rect: Rect2 = slot.get_spread().get_global_rect()
	var rect := OBJECTIVE_NOTE_SCRIPT.note_rect(spread_rect)
	note.size = rect.size
	note.global_position = rect.position


## The skip verb ("I know this"): the current objective is struck from
## the arc, the note advances (or folds at the arc's end), and focus
## never strands on the folded paper.
func _on_note_skip() -> void:
	if first_session == null:
		return
	if first_session.skip_current(host):
		stats[&"note_skips"] += 1
	_bind_objective_note()
	_focus_first_card()


# --- the how-to pamphlet (the tutorial upgrade) ----------------------------------------------


## Build the pamphlet ONCE, beside its sibling table papers (the papers
## are mutually exclusive — whichever opens folds the others; the
## chronicle stays topmost). Paper over the table while open, never
## modal chrome.
func _build_howto_screen() -> void:
	_howto = HowToScreenScript.new()
	_howto.name = "HowToScreen"
	_howto.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_howto)
	_howto.closed.connect(_on_howto_closed)
	_howto.offer_answered.connect(_on_howto_offer_answered)


## Open the pamphlet (the header's How-to-Play verb): the other table
## papers fold first (one paper at a time owns the table). No run needs
## to be live — the primer reads just as well between hands. The read
## answers the first-boot offer too (the flag is the offer's receipt).
func open_howto() -> void:
	if _howto == null or host == null:
		return
	stats[&"howtos_opened"] += 1
	_howto_from_chip = true
	close_fan()
	if _chronicle != null and _chronicle.is_open():
		_chronicle.close()
	if _day_sheet != null and _day_sheet.is_open():
		_day_sheet.close()
	if _press_room != null and _press_room.is_open():
		_press_room.close()
	if _legacy != null and _legacy.is_open():
		_legacy.close()
	_mark_howto_answered()
	_howto.open(host)


## The pamphlet folded away: focus returns to the chip that opened it,
## else the table's first card (a screen must never strand focus). THE
## STAGED FIRST MOMENTS: on the fresh first deal this dismissal is what
## releases the held deals — the gate's paper slides in NOW (the offer
## paper is gone; nothing buries it), settling on the open table.
func _on_howto_closed() -> void:
	stats[&"howtos_closed"] += 1
	if _deals_held:
		_deals_held = false
		_bind_cards_list.call_deferred(false)
	if _howto_from_chip:
		_howto_from_chip = false
		var active := get_active_slot() as OrientationSlot
		var chip := header_chip(active, "howto_chip") if active != null else null
		if chip != null:
			chip.grab_focus()
			return
	_focus_first_card()


## The FIRST-FRESH-BOOT OFFER (once, declinable): the boot reveal's fold
## is the table's quiet moment — the clerk's small paper slides out with
## the pamphlet's two verbs. Answered exactly once; the receipt
## persists in the META domain either way.
func _maybe_offer_howto() -> void:
	if _howto == null or host == null or not _fresh_first_deal:
		return
	if host.meta.first_session_flag(&"howto"):
		return
	if not host.is_run_running():
		return
	stats[&"howto_offers"] += 1
	close_fan()
	if _chronicle != null and _chronicle.is_open():
		_chronicle.close()
	_howto.offer(host)
	# THE STAGED FIRST MOMENTS: the paper owns the table until it is
	# answered — deals arriving behind it wait for its dismissal (the
	# player reads one paper at a time; the table deals onto an open
	# table, never under a closed veil).
	_deals_held = true


## Either offer verb (and every chip-open) marks the receipt: the offer
## is answered once per install, persisted at once.
func _on_howto_offer_answered(p_read: bool) -> void:
	stats[&"howto_answered"] += 1
	_mark_howto_answered()
	if not p_read:
		_howto_from_chip = false
		# decline: the panel folds via the screen's own close -> _on_howto_closed


func _mark_howto_answered() -> void:
	if host.meta.set_first_session_flag(&"howto"):
		host.save_manager.save_meta(host.meta)


# --- the assault vignette (T-UI-07) -------------------------------------------------------

## Build the assault screen ONCE (paper over the table while open — the
## same composition rule as the fan; it is never modal chrome).
func _build_assault_screen() -> void:
	_assault = ASSAULT_SCENE.instantiate()
	_assault.name = "AssaultScreen"
	add_child(_assault)
	_assault.finished.connect(_on_assault_finished)


## Build the intro screen ONCE, ABOVE the assault screen in z-order (a
## run can end mid-vignette — the edge crush — and the reveal papers
## over everything; the vignette finishes beneath, the intro owns input).
func _build_intro_screen() -> void:
	_intro = INTRO_SCENE.instantiate()
	_intro.name = "IntroScreen"
	add_child(_intro)
	_intro.closed.connect(_on_intro_closed)


## Build the chronicle screen ONCE, TOPMOST paper (T-UI-08): the ledger
## of past spreads. It never stacks with story paper — every story
## layer (choice card, vignette, beat, reveal) closes it FIRST (the
## story outranks the ledger; the ledger reopens from the header chip).
func _build_chronicle_screen() -> void:
	_chronicle = CHRONICLE_SCENE.instantiate()
	_chronicle.name = "ChronicleScreen"
	add_child(_chronicle)
	_chronicle.closed.connect(_on_chronicle_closed)


## Build the day-sheet screen ONCE, BENEATH the chronicle in z-order
## (the two ledger papers are mutually exclusive — whichever opens folds
## the other — and both sit ABOVE the story layers' input owners only
## while open). The run's own page, the chronicle screen's little
## sibling.
func _build_day_sheet_screen() -> void:
	_day_sheet = DaySheetScreenScript.new()
	_day_sheet.name = "DaySheetScreen"
	# FULL-RECT, like every paper layer's root (the chronicle scene's own
	# anchors): the page lays out against the whole design bounds.
	_day_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_day_sheet)
	_day_sheet.closed.connect(_on_day_sheet_closed)


## Build the press-room screen ONCE, BESIDE the day-sheet in z-order
## (the three table papers — chronicle, day-sheet, press-room — are
## mutually exclusive, whichever opens folds the others; the chronicle
## stays topmost of the three). Paper over the table while open, never
## modal chrome.
func _build_press_room_screen() -> void:
	_press_room = PressRoomScreenScript.new()
	_press_room.name = "PressRoomScreen"
	_press_room.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_press_room)
	_press_room.closed.connect(_on_press_room_closed)
	_press_room.preference_changed.connect(_on_preference_changed)


## Build the legacy deck screen ONCE, BESIDE its sibling table papers in
## z-order (the papers are mutually exclusive — whichever opens folds
## the others; the chronicle stays topmost). Paper over the table while
## open, never modal chrome.
func _build_legacy_screen() -> void:
	_legacy = LegacyScreenScript.new()
	_legacy.name = "LegacyScreen"
	_legacy.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_legacy)
	_legacy.closed.connect(_on_legacy_closed)


## Open the chronicle ledger (the header chip's verb): the run header's
## chronicle affordance, in world grammar. Focus is remembered so
## closing returns the pad player to the chip that opened it. The table
## papers never stack: the run's page and the press-room fold first.
func open_chronicle() -> void:
	if _chronicle == null:
		return
	stats[&"chronicles_opened"] += 1
	close_fan()
	if _day_sheet != null and _day_sheet.is_open():
		_day_sheet.close()
	if _press_room != null and _press_room.is_open():
		_press_room.close()
	if _legacy != null and _legacy.is_open():
		_legacy.close()
	if _howto != null and _howto.is_open():
		_howto.close()
	_chronicle.open(host, get_router())


## Open the run's own page (the header's Day-Sheet verb): every line
## this hand has printed, newest first. The same paper discipline as
## the chronicle — focus is remembered so closing returns the pad
## player to the chip that opened it, and the other table papers fold
## first (the papers never stack).
func open_day_sheet() -> void:
	if _day_sheet == null or host == null:
		return
	stats[&"day_sheets_opened"] += 1
	close_fan()
	if _chronicle != null and _chronicle.is_open():
		_chronicle.close()
	if _press_room != null and _press_room.is_open():
		_press_room.close()
	if _legacy != null and _legacy.is_open():
		_legacy.close()
	if _howto != null and _howto.is_open():
		_howto.close()
	_day_sheet.open(host, get_router(), presenter)


## The run's page folded away: focus returns to the Day-Sheet chip on
## the active slot's header verbs row (the affordance that opened it).
func _on_day_sheet_closed() -> void:
	stats[&"day_sheets_closed"] += 1
	var active := get_active_slot() as OrientationSlot
	var chip := header_chip(active, "day_sheet_chip") if active != null else null
	if chip != null:
		chip.grab_focus()
		return
	_focus_first_card()


## Open the press-room card (the header's Press-Room verb): the settings
## surface for the accessibility seams — the type scale and reduced
## motion, persisted in the meta domain, applied live. The same paper
## discipline as its siblings: the other table papers fold first (one
## paper at a time owns the table), and NO run needs to be live — a
## player can set their hand in the aftermath too.
func open_press_room() -> void:
	if _press_room == null or host == null:
		return
	stats[&"press_rooms_opened"] += 1
	close_fan()
	if _chronicle != null and _chronicle.is_open():
		_chronicle.close()
	if _day_sheet != null and _day_sheet.is_open():
		_day_sheet.close()
	if _legacy != null and _legacy.is_open():
		_legacy.close()
	if _howto != null and _howto.is_open():
		_howto.close()
	_press_room.open(host, get_router())


## The press-room folded away: focus returns to the Press-Room chip on
## the active slot's header verbs row (the affordance that opened it).
func _on_press_room_closed() -> void:
	stats[&"press_rooms_closed"] += 1
	var active := get_active_slot() as OrientationSlot
	var chip := header_chip(active, "press_room_chip") if active != null else null
	if chip != null:
		chip.grab_focus()
		return
	_focus_first_card()


## Open the legacy deck (the header's The-Legacy verb, L1-C): the
## growing deck where banked legacy buys permanent upgrades between
## runs. The same paper discipline as its siblings — the other table
## papers fold first (one paper at a time owns the table) — and NO run
## needs to be live: the bank is a between-runs surface by design (the
## fresh install reads the deck locked under its "earn your first
## legacy" line).
func open_legacy() -> void:
	if _legacy == null or host == null:
		return
	stats[&"legacies_opened"] += 1
	close_fan()
	if _chronicle != null and _chronicle.is_open():
		_chronicle.close()
	if _day_sheet != null and _day_sheet.is_open():
		_day_sheet.close()
	if _press_room != null and _press_room.is_open():
		_press_room.close()
	if _howto != null and _howto.is_open():
		_howto.close()
	_legacy.open(host)


## The deck folded away: focus returns to The-Legacy chip on the active
## slot's header verbs row (the affordance that opened it).
func _on_legacy_closed() -> void:
	stats[&"legacies_closed"] += 1
	var active := get_active_slot() as OrientationSlot
	var chip := header_chip(active, "legacy_chip") if active != null else null
	if chip != null:
		chip.grab_focus()
		return
	_focus_first_card()


# --- the press-room's verbs (finishing refinement #5) --------------------------------------


## THE BOOT SEAM: the persisted preferences apply before any chrome
## bakes sizes (see _ready). A player who never touched the card has no
## keys in the meta — the project settings rule, untouched.
func _apply_boot_preferences() -> void:
	if host == null:
		return
	var scale_pref := host.meta.type_scale_preference()
	if scale_pref > 0.0:
		TypeScale.apply_preference(scale_pref)
	var motion_pref := host.meta.reduced_motion_preference()
	if motion_pref >= 0:
		MotionProfile.forced = motion_pref


## A press-room step landed (not the one already in force). The spread
## owns the verb's three halves, in order: APPLY (live), PERSIST (the
## meta domain), SAVE (the meta file, at once — the choice survives a
## crash before the next autosave by construction; the run ring is not
## touched, preferences are not run state).
func _on_preference_changed(kind: StringName, value: Variant) -> void:
	if kind == &"type_scale":
		stats[&"type_scale_changes"] += 1
		host.meta.set_type_scale_preference(float(value))
		_apply_type_scale_live(float(value))
	elif kind == &"motion":
		stats[&"motion_changes"] += 1
		host.meta.set_reduced_motion_preference(bool(value))
		# LIVE by construction: every motion owner asks MotionProfile at
		# motion time — flips still fire their signals and land on the
		# same end state, entrance slides simply stop; no restart.
		MotionProfile.forced = 1 if bool(value) else 0
	host.save_manager.save_meta(host.meta)


## THE LIVE RE-FLOW (the whole-view rebind the recorded deviation
## deferred): the theme rewrite carries every theme-driven label the
## moment the factor lands; the chrome that BAKES a size at build — the
## letterhead (its name-plate size + the regime/time plates' minimums)
## and the Eye plates — is rebuilt; the full refresh re-derives the
## columns and rebinds the table. The paper layers rebuild their plates
## on their next open (their bind re-applies the few baked sizes — the
## countdown plate's own pattern). The paper layers never rebuild under
## the open card: the papers are mutually exclusive, so the rebind is
## race-free by construction.
func _apply_type_scale_live(new_factor: float) -> void:
	TypeScale.apply_factor(new_factor)
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var strip := slot.get_header()
		if strip != null:
			# Remove NOW (not queue_free's deferred release): the rebuild
			# below re-creates the header + verbs row through _bind_header,
			# which must not find the dying children.
			for child in strip.get_children():
				strip.remove_child(child)
				child.queue_free()
		var old_eye := eye_of(slot)
		if old_eye != null:
			slot.remove_child(old_eye)
			old_eye.queue_free()
		var eye := WATCHFUL_EYE_SCRIPT.new()
		eye.name = "WatchfulEye"
		slot.add_child(eye)
	refresh_from_state()


## The ledger chip with this focus id on a slot's header verbs row (the
## chronicle chip, the day-sheet chip) — the shared lookup for the focus
## returns and the tests (the verbs row nests the chips; the header's
## child(1) is the ROW).
static func header_chip(slot: OrientationSlot, focus_id: String) -> Control:
	if slot == null:
		return null
	var strip := slot.get_header()
	if strip == null or strip.get_child_count() < 2:
		return null
	for child in (strip.get_child(1) as Control).get_children():
		if child is Control and String((child as Control).get_meta(&"focus_id", "")) == focus_id:
			return child
	return null


## The ledger folded away: focus returns to the chronicle chip on the
## active slot's header verbs row (the affordance that opened it).
func _on_chronicle_closed() -> void:
	stats[&"chronicles_closed"] += 1
	var active := get_active_slot() as OrientationSlot
	var chip := header_chip(active, "chronicle_chip") if active != null else null
	if chip != null:
		chip.grab_focus()
		return
	_focus_first_card()


## Story paper outranks EVERY table paper: fold the chronicle, the run's
## page and the press-room before a story layer opens over them (choice
## card, vignette, crush beat, reveal). The documented rule, one shape:
## the story never waits on the table's papers, and the papers never
## stack on the story — the player returns to each from its header chip.
func _close_chronicle() -> void:
	if _chronicle != null and _chronicle.is_open():
		_chronicle.close()
	if _day_sheet != null and _day_sheet.is_open():
		_day_sheet.close()
	if _press_room != null and _press_room.is_open():
		_press_room.close()
	if _legacy != null and _legacy.is_open():
		_legacy.close()
	if _howto != null and _howto.is_open():
		_howto.close()


## Open the assault odds table (the army card's storm action, or the
## capture hook). Focus is remembered so closing returns the pad player
## to the card that raised the standard.
func open_assault() -> void:
	if _assault == null or not host.is_run_running():
		return
	stats[&"assaults_opened"] += 1
	_pre_assault_focus = get_viewport().gui_get_focus_owner()
	close_fan()
	_close_chronicle()
	# THE FIRST ODDS HINT (the tutorial upgrade): the odds table's first
	# opening prints one plain-language line (commit storms, retreat is
	# free) — strip row, once per install, budget-pinned.
	var hint: Dictionary = FirstSession.hint_odds_if_first(host)
	if not hint.is_empty():
		stats[&"hint_rows"] += 1
		presenter.push_row(hint["row"])
		_bind_chronicle()
	# The storm objective performed: opening the odds completes the arc
	# (the farewell nudge — note folded, one printed line — delivers now).
	if first_session != null:
		var storm_nudge: Dictionary = first_session.complete_storm(host)
		if not storm_nudge.is_empty():
			_deliver_nudge(storm_nudge)
		_bind_objective_note()
	_assault.open(host, get_router())


## THE VICTORY-HANDOFF SEAM (T-UI-05 mounted it): the win's "deal the
## next hand" — the leader intro opens over the aftermath with the
## regime-swap beat, the banked-legacy line, and the NEW leader dealt
## (the intro submits the real restart through the host's one write
## path). A run that ended mid-vignette (the edge crush) mounts the
## LOSS reveal here instead. Without the intro (sibling suites pinning
## the bare table), the original behavior stands: focus returns and the
## outcome events' refreshes (plus the loss blockquote in the rolling
## chronicle) are already on the table.
func _on_assault_finished(outcome: StringName, _script: Dictionary) -> void:
	stats[&"assaults_finished"] += 1
	if intro_enabled and _intro != null:
		if String(outcome) == "win":
			_open_intro()
			return
		if _intro_after_assault:
			_intro_after_assault = false
			if _crush_after_assault:
				# The edge crush (the meter's assault spike ended the run
				# mid-vignette): the beat tells the death first, the reveal
				# is dealt when it resolves.
				_crush_after_assault = false
				_start_crush_beat()
				return
			_open_intro()
			return
	var restore := _pre_assault_focus
	_pre_assault_focus = null
	if restore != null and is_instance_valid(restore) and restore.is_visible_in_tree():
		restore.grab_focus()
		return
	var active := get_active_slot() as OrientationSlot
	if active != null:
		for child in active.get_spread().get_children():
			if child is Control and child.has_meta(&"spread_card_id"):
				child.grab_focus()
				return


# --- the leader intro / restart reveal (T-UI-05) ------------------------------------------


## The BOOT reveal: a FRESH first run (no chronicle yet, zero sim time —
## a resumed session is T-UI-09's check-in beat, never a re-deal). The
## intro owns everything from here: identity reveal, the one-gesture
## unfold, the spread live beneath the whole time.
func _maybe_open_boot_intro() -> void:
	if not intro_enabled or _intro == null or _intro.is_open():
		return
	if not host.is_run_running() or host.meta.runs_recorded != 0:
		return
	if host.engine.tick_count > 1:
		return  # a resumed first run — the check-in owns its entry beat
	stats[&"intros_opened"] += 1
	_intro.open(host, get_router())


## THE CHECK-IN BEAT (T-UI-09): any session that is NOT the fresh first
## deal — hours into the first hand, or any later hand — opens with the
## intro's SHORT unfold variant instead: the SAME hand's leader under the
## same regime (never a re-deal), the away line from the window the host
## resolved at boot (`last_catch_up_report` — the boot seam: the signal
## fired before this screen could connect), auto-opening inside the
## 3-second promise. The away print follows the fold (see
## _on_intro_closed); a mid-session foreground (screen already mounted)
## prints without papering over the live table.
func _maybe_open_resumed_intro() -> void:
	if not intro_enabled or _intro == null or _intro.is_open():
		return
	if host.meta.runs_recorded == 0 and host.engine.tick_count <= 1:
		return  # the fresh first deal — T-UI-05's reveal owns this entry
	if entry_mode == ENTRY_NEW_HAND and not host.is_run_running():
		# THE BOOT SHELL'S NEW HAND (a confirmed abandon, or an ended meta
		# behind BEGIN): the reveal derives from the ACTUAL chronicle and
		# the intro restarts the run itself — a dead hand is never
		# "resumed" (the check-in variant would refuse the restart).
		_open_intro()
		return
	_pending_catch_up = host.last_catch_up_report
	stats[&"intros_opened"] += 1
	_intro.open(host, get_router(), IntroPresenter.VARIANT_RESUMED, _pending_catch_up)


## Mount the intro (deferred by the run-loss path so the aftermath's full
## refresh lands first — the crushing beat prints, THEN the reveal papers
## over it). `p_variant` is a hint; the presenter re-derives the truth
## from the actual chronicle.
func _open_intro(p_variant: StringName = &"") -> void:
	if _intro == null or _intro.is_open():
		return
	if _suspicion != null:
		_suspicion.fold_quote()  # the reveal is the paper now
	_close_chronicle()  # the reveal papers over the ledger too
	stats[&"intros_opened"] += 1
	_intro.open(host, get_router(), p_variant)


## The reveal folded away (its one gesture — or its auto timer — landed):
## the table takes focus back — first card, else the slot's first
## focusable (an empty first-run table has no cards yet; a screen must
## seed itself, the router's rule). The CHECK-IN variant's fold also
## releases the while-you-were-away print onto the now-visible table.
func _on_intro_closed(variant: StringName) -> void:
	stats[&"intros_unfolded"] += 1
	if _crush_after_intro:
		# The run died behind the reveal: the table tells the story now.
		_crush_after_intro = false
		_start_crush_beat()
		return
	# THE FIRST-BOOT OFFER (the tutorial upgrade): the reveal folded on
	# the one true fresh deal — the pamphlet's offer papers out now, once.
	_maybe_offer_howto()
	if variant == IntroPresenter.VARIANT_RESUMED:
		var report := _pending_catch_up
		_pending_catch_up = {}
		if not report.is_empty():
			# The boot-resolved window: its events drained before this
			# screen connected, so the strip never printed them — the
			# print pushes its own headline row (the mid-session path's
			# drain already did).
			_deliver_catch_up(report, true)
		if not host.is_run_running() and intro_enabled:
			# The hand ENDED inside the away window (a crush behind the
			# reveal): the blockquote tells it, then the loss-restart
			# reveal deals the next hand once the quote has had its read.
			get_tree().create_timer(SuspicionEvents.QUOTE_DWELL) \
				.timeout.connect(_open_intro)
	var active := get_active_slot() as OrientationSlot
	if active == null:
		return
	for child in active.get_spread().get_children():
		if child is Control and child.has_meta(&"spread_card_id"):
			child.grab_focus()
			return
	for focusable in active.focusables():
		focusable.grab_focus()
		return


## THE WHILE-YOU-WERE-AWAY PRINT (T-UI-09): the resolved window as paper
## on the table — the blockquote (dwell, self-folding, never blocking)
## when the window ticked or the clock was wound backwards, else a single
## quiet strip line. `p_push_strip` is true only on the boot path (the
## mid-session foreground's unified drain already printed the headline
## into the strip). The print's DETAIL rows (stores, people, the Crown's
## eye — everything past the headline) also land on the day-sheet
## (finishing refinement #2): the blockquote folds, the page remembers.
func _deliver_catch_up(report: Dictionary, p_push_strip: bool) -> void:
	if int(report.get("applied_ticks", 0)) > 0 or bool(report.get("rewound", false)):
		stats[&"catch_up_prints"] += 1
		var quote_rows := CatchUpPrint.rows(report)
		_suspicion.open_quote_rows(quote_rows,
			_design_bounds().size, _quote_floor(), SuspicionEvents.QUOTE_DWELL * 2.0)
		# The rewound window is one line (already the strip's rewound row);
		# every other window's headline already printed through the strip —
		# only the DETAIL past it is blockquote-only paper.
		if not bool(report.get("rewound", false)) and quote_rows.size() > 1:
			presenter.push_rows(quote_rows.slice(1))
			_sync_open_day_sheet()
		if p_push_strip:
			presenter.push_row(CatchUpPrint.headline_row(report))
			_bind_chronicle()
	elif p_push_strip:
		stats[&"quiet_lines"] += 1
		presenter.push_row(CatchUpPrint.quiet_row())
		_bind_chronicle()


# --- card interactions (T-UI-04) -------------------------------------------------------


## True for terminal combat ranks (knight/archer): the promotion into them
## is THE flip. Gear-free hops (worker/militia/trainee) re-print their
## plates through the ordinary card rebind — the flip stays special.
func _is_army_def(def_id: StringName) -> bool:
	for def: UnitDef in Inks.pack().units:
		if def.id == def_id:
			return def.combat_power > 0 and def.promotion_paths.is_empty()
	return false


## An army promotion landed. LIVE: the card turns now. OFFLINE (delivered
## inside a foreground catch-up drain): queue a capped replay instead —
## returning to a table of simultaneous card turns is noise. Returns true
## when the flip path owns the card rebind.
func _on_army_promoted(event: Dictionary) -> bool:
	var uid := int(event["value"])
	var card_id := "unit_%d" % uid
	if host.delivering_catch_up:
		_flip_queue.push(card_id)
		return true
	_play_promotion_flip(card_id, uid)
	return true


## Turn one card over: the ACTIVE slot's node plays the authored flip (the
## hidden slot re-prints instantly — only the table the player sees turns),
## and the view model's card entry updates with the fresh plates so later
## targeted refreshes read the same state the paper shows.
func _play_promotion_flip(card_id: String, uid: int) -> void:
	var fresh := SpreadPresenter.unit_card_view(host, Inks.pack(), uid)
	if fresh.is_empty():
		return  # the unit is gone (casualties can outrun the event) — nothing to reveal
	var view_card := _view_card(card_id)
	if not view_card.is_empty():
		for key in ["name", "role", "face_key", "edge_state"]:
			view_card[key] = fresh[key]
	stats[&"flips_played"] += 1
	var active := get_active_slot() as OrientationSlot
	var active_node: Control = null
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var node := _card_node_in(slot, card_id)
		if node == null:
			continue
		if slot == active:
			active_node = node
		else:
			SpreadCards.rebind_card(node, fresh)
	if active_node == null:
		return
	var node_ref := active_node
	var fresh_ref := fresh
	node_ref.play_promotion_flip(func() -> void:
		SpreadCards.rebind_card(node_ref, fresh_ref))


## The foreground boundary resolved a catch-up window (MID-SESSION: the
## screen is mounted, the table live): replay the queued offline flips,
## staggered (latest capped set — see PromotionFlipQueue), and print the
## while-you-were-away blockquote onto the live table. The strip's
## headline already printed through this drain's own event.
func _on_catch_up_resolved(report: Dictionary) -> void:
	var replay := _flip_queue.take_all()
	for i in replay.size():
		var card_id := replay[i]
		var uid := int(card_id.trim_prefix("unit_"))
		var do_flip := func() -> void:
			stats[&"flip_replays"] += 1
			_play_promotion_flip(card_id, uid)
		get_tree().create_timer(0.25 * float(i)).timeout.connect(do_flip)
	_deliver_catch_up(report, false)


## Build the one screen-level action fan (outside the slots: it is paper
## laid over the table while open, and orientation swaps must not move it).
func _build_action_fan() -> void:
	_fan = ACTION_FAN_SCRIPT.new()
	_fan.name = "ActionFan"
	add_child(_fan)
	_fan.action_chosen.connect(_on_action_chosen)
	_fan.action_refused.connect(_on_action_refused)


# --- the suspicion event layer (T-UI-06) --------------------------------------------------


## Build the suspicion layer ONCE (paper over the table, under the
## assault vignette + intro: a mid-vignette crackdown prints beneath the
## storm; the crush beat papers over everything when it plays).
func _build_suspicion_layer() -> void:
	_suspicion = SUSPICION_EVENTS_SCRIPT.new()
	_suspicion.name = "SuspicionEvents"
	add_child(_suspicion)
	_suspicion.choice_made.connect(_on_suspicion_choice)
	_suspicion.beat_finished.connect(_on_crush_beat_finished)


## The live design bounds (the suspicion layer's paper places within it).
func _design_bounds() -> Rect2:
	var router := get_router()
	if router == null:
		return Rect2(Vector2.ZERO, size)
	return Rect2(Vector2.ZERO, router.design_size())


## The blockquote's floor: the lowest paper edge a quote must clear
## (SuspicionEvents.quote_rect parks the panel 8px above it). Portrait:
## the BOTTOM chronicle strip's top. Landscape: the table's bottom edge —
## the strip is at the TOP there, so passing its top would clamp the
## quote to the screen's top (the round-1 verifier's secondary find);
## the table's floor parks it center-bottom, clear of the bottom pips
## rail — the documented bottom/center-bottom intent in BOTH topologies.
func _quote_floor() -> float:
	var active := get_active_slot() as OrientationSlot
	if active == null:
		return _design_bounds().size.y
	if active.portrait_topology:
		var line := active.get_chronicle_line(0)
		if line == null:
			return _design_bounds().size.y
		return line.get_global_rect().position.y
	var spread := active.get_spread()
	if spread == null:
		return _design_bounds().size.y
	return spread.get_global_rect().end.y


## Open a suspicion choice card (warn / telegraph) — live moments only:
## an away window's beats printed in the chronicle strip already; sliding
## a card for a warn eight hours stale would be noise, not news.
func _open_suspicion_choice(event: Dictionary) -> void:
	if _suspicion == null or not host.is_run_running():
		return
	stats[&"choice_cards"] += 1
	_close_chronicle()  # the choice card is live story — the ledger folds
	_suspicion.open_choice(SuspicionEvents.choice_card_for(host, event), _design_bounds().size)
	# Focus seeding is polite: never steal from an open fan or over paper
	# (the vignette/intro own input while they are up).
	if not _fan.is_open() and (_assault == null or not _assault.is_open()) \
			and (_intro == null or not _intro.is_open()):
		_suspicion.seed_choice_focus()


## One chosen suspicion chip: the REAL commands down the host's one write
## path (the thin-the-gate chip submits one dismiss_offer per offer), a
## printed acknowledgment, and the card folds (focus returns to the table).
func _on_suspicion_choice(action: Dictionary) -> void:
	stats[&"choices_made"] += 1
	var held_focus := _suspicion.choice_holds_focus()
	if action.has("multi_command"):
		var command: StringName = action["multi_command"]
		for uid in action.get("subjects", []):
			host.submit(command, &"", int(uid))
		presenter.push_row({
			"class": Inks.LineClass.WARN,
			"text": CopyDeck.line(Inks.pack().copy, &"gate_thinned",
				int(stats.get(&"choices_made", 1)),
				{"count": (action.get("subjects", []) as Array).size()}),
		})
	elif String(action["id"]) == "keep_close":
		presenter.push_row({
			"class": Inks.LineClass.WARN,
			"text": CopyDeck.line(Inks.pack().copy, &"cards_kept_close",
				int(stats.get(&"choices_made", 1))),
		})
	_bind_chronicle()
	_suspicion.fold_choice()
	if held_focus:
		_focus_first_card()


## Focus the table's first card (post-choice fallback — a screen must
## never strand focus on folded paper).
func _focus_first_card() -> void:
	var active := get_active_slot() as OrientationSlot
	if active == null:
		return
	for child in active.get_spread().get_children():
		if child is Control and child.has_meta(&"spread_card_id"):
			child.grab_focus()
			return


## THE CRACKDOWN LANDING: the Eye strikes (both slots), the ground flashes
## aftermath ink, the choice card folds (the telegraph is no longer a
## choice), and the blockquote begins from the struck headline. The
## pre-crackdown view is captured HERE — the world's own record of the
## gate crowd the riders are about to sweep.
func _on_crackdown_struck(event: Dictionary) -> void:
	_pre_crackdown_cards = (_view.get("cards", []) as Array).duplicate(true)
	_suspicion.fold_choice()
	stats[&"eye_strikes"] += 1
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var eye := eye_of(slot)
		if eye != null:
			eye.play_strike()
	_flash_grounds()
	stats[&"quotes_printed"] += 1
	_suspicion.begin_quote(event, host, _design_bounds().size, _quote_floor())


## One seized-resource row into the open blockquote (the system's own
## voice, the event's real payload).
func _on_crackdown_seized(event: Dictionary) -> void:
	if not _suspicion.quote_is_open():
		return
	var line: String = host.suspicion().chronicle_line(SuspicionEvents._as_sim_event(event))
	if not line.is_empty():
		_suspicion.append_quote_row({
			"class": Inks.line_class_for_event(event["type"]), "text": line})


## The scatter row with the NAMES of the swept gate crowd. The named rows
## also land on the day-sheet (finishing refinement #2): they are
## blockquote-only payloads — the strip's own scattered line counts
## recruits, the QUOTE names them, and the page keeps what the player
## SAW print.
func _on_crackdown_scattered(event: Dictionary) -> void:
	if not _suspicion.quote_is_open():
		return
	var named_rows := SuspicionEvents.scatter_line(_pre_crackdown_cards, event)
	_suspicion.append_scatter_row(_pre_crackdown_cards, event)
	presenter.push_rows(named_rows)
	_sync_open_day_sheet()


## An open day-sheet page is live paper: rows that landed OUTSIDE the
## strip's bind (blockquote-only payloads) sync it here.
func _sync_open_day_sheet() -> void:
	if _day_sheet != null and _day_sheet.is_open():
		_day_sheet.sync_rows(host, presenter)


## The ground's aftermath flash: cold ink pays across the table for a
## beat, then the phase tone returns. Reduced motion skips it (the
## blockquote carries the event).
func _flash_grounds() -> void:
	stats[&"ground_flashes"] += 1
	var duration := MotionProfile.duration(0.75)
	if duration <= 0.05:
		return
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var ground := slot.get_ground()
		if ground == null:
			continue
		var tween := ground.create_tween()
		tween.tween_property(ground, "flash", 1.0, duration * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(ground, "flash", 0.0, duration * 0.65) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## RELIEF: the telegraph cancelled (the meter dropped below the threshold
## — laying low worked). A calmer line prints in the strip (the system's
## own voice, via the chronicle path above) and the Eye retreats.
func _on_telegraph_cancelled() -> void:
	_suspicion.fold_choice()
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var eye := eye_of(slot)
		if eye != null:
			eye.play_retreat()


# --- the crushed beat (the run-death story, T-UI-06) ---------------------------------------


## A run ended through the crush: the beat plays BEFORE the loss-restart
## reveal (deferred past this drain's full refresh — the aftermath binds
## first, then the table tells the story).
func _start_crush_beat() -> void:
	if _suspicion == null or _suspicion.beat_active():
		if intro_enabled:
			_open_intro()
		return
	stats[&"crushes_played"] += 1
	close_fan()
	_close_chronicle()  # the beat owns the table
	_table_frozen = true
	var cards: Array[Control] = []
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var spread := slot.get_spread()
		if spread == null:
			continue
		CardMotion.snap_all(spread)
		for child in spread.get_children():
			if child is Control and child.has_meta(&"spread_card_id"):
				cards.append(child)
	_suspicion.play_crush(cards, SuspicionEvents.crush_lines(host), _on_crush_strike_fx,
		_design_bounds().size, _quote_floor())


## The beat's strike moment: the Eye strikes hard and the ground flashes.
func _on_crush_strike_fx() -> void:
	stats[&"eye_strikes"] += 1
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var eye := eye_of(slot)
		if eye != null:
			eye.play_strike()
	_flash_grounds()


## The beat resolved (pacing, dwell or skip): the table unfreezes and the
## loss-restart reveal is dealt over the cleared table (the intro's own
## restart re-deals the new hand beneath its paper). Without the intro
## (sibling suites pinning the bare table), the cleared table STAYS
## cleared — the hand is over; the next world event re-binds honestly.
func _on_crush_beat_finished() -> void:
	_table_frozen = false
	if intro_enabled:
		_open_intro()


## Fan a card's contextual actions out at its edge.
func open_fan_for_card(card: Control) -> void:
	if _view.is_empty() or card == null or not is_instance_valid(card):
		return
	var view_card := _view_card(String(card.get_meta(&"spread_card_id", "")))
	if view_card.is_empty():
		return
	var actions := CardActions.actions_for(host, view_card)
	if actions.is_empty():
		return  # state cards (training, army) carry no choices
	stats[&"fans_opened"] += 1
	_fan.open(String(view_card["id"]), actions)
	_place_fan(card)
	# THE SHEET EDGE-SNAP (readability r4): after placement the fan gets
	# the table's card footprints, so its paper snaps outward to card
	# bounds — every card the sheet touches it covers whole or not at all,
	# and no foreign label is ever sliced by a sheet edge.
	_fan.snap_sheet_to(_table_card_footprints())


## Fold the fan away; focus returns to the card that opened it.
func close_fan() -> void:
	if _fan == null or not _fan.is_open():
		return
	var card := _fan_card_node()
	_fan.close()
	if card != null and is_instance_valid(card):
		card.grab_focus()


## The fan's card node in the ACTIVE slot.
func _fan_card_node() -> Control:
	if _fan == null or _fan.card_id.is_empty():
		return null
	return _card_node_in(get_active_slot() as OrientationSlot, _fan.card_id)


func _card_node_in(slot: OrientationSlot, card_id: String) -> Control:
	if slot == null:
		return null
	for child in slot.get_spread().get_children():
		if child is Control and String(child.get_meta(&"spread_card_id", "")) == card_id:
			return child
	return null


## At the card's edge: to its right where the table has room, mirrored to
## its left where it does not, always fully inside THE TABLE BAND (the
## fan is paper ON the table — it never clips off it, and it never rides
## up onto the header, the chronicle strip or the pips rail: the first-
## deal coverage fix — a fan paper that reached past the band crossed
## foreign chrome, the audit's straddle finds).
func _place_fan(card: Control) -> void:
	var fan_size: Vector2 = _fan.get_combined_minimum_size()
	_fan.size = fan_size
	var bounds := get_global_rect()
	var band := _table_band_rect()
	var card_rect := card.get_global_rect()
	var x := card_rect.end.x + 10.0
	if x + fan_size.x > band.end.x - 8.0:
		x = card_rect.position.x - fan_size.x - 10.0
	x = clampf(x, band.position.x + 8.0,
		maxf(band.position.x + 8.0, band.end.x - fan_size.x - 8.0))
	var y := clampf(card_rect.get_center().y - fan_size.y * 0.5,
		band.position.y + 8.0,
		maxf(band.position.y + 8.0, band.end.y - fan_size.y - 8.0))
	_fan.global_position = Vector2(x, y)


## The active slot's table band in global coords (the fan's placement
## bounds; falls back to the whole screen before the slots exist).
func _table_band_rect() -> Rect2:
	var active := get_active_slot() as OrientationSlot
	if active != null and active.get_spread() != null:
		return (active.get_spread() as Control).get_global_rect()
	return get_global_rect()


## Every mounted card's GLOBAL footprint on the ACTIVE table — the r4
## sheet edge-snap set (ActionFan.snap_sheet_to): the fan's paper may
## cover a card WHOLE or not at all, so its edges must know where every
## card actually sits. The footprint is the card's global-transform
## footprint (the rotated AABB in the panoramic arc — the axis-aligned
## sheet must cover a rotated card's corners too); for the STACKED grid's
## unrotated cards it is exactly the card rect.
func _table_card_footprints() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var slot := get_active_slot() as OrientationSlot
	if slot == null:
		return out
	for child in slot.get_spread().get_children():
		if child is Control:
			var card := child as Control
			var xform := card.get_global_transform()
			var corners: Array[Vector2] = [
				xform * Vector2.ZERO,
				xform * Vector2(card.size.x, 0.0),
				xform * Vector2(0.0, card.size.y),
				xform * card.size,
			]
			var lo := corners[0]
			var hi := corners[0]
			for corner: Vector2 in corners:
				lo = lo.min(corner)
				hi = hi.max(corner)
			out.append(Rect2(lo, hi - lo))
	return out


## A whole-state re-render can retire the fanned card (restart, scatter):
## fold the fan rather than fan a card that is no longer on the table.
func _validate_open_fan() -> void:
	if _fan == null or not _fan.is_open():
		return
	if _fan_card_node() == null:
		_fan.close()


## One chosen action: one real command down the host's write path, then
## the fan folds and focus returns to the card (the promote command's
## landing — the flip — arrives later, as the event it is). The storm
## action is the one intercept: it opens the assault odds table instead
## of submitting (the sim's verb there is commit_assault, on COMMIT).
func _on_action_chosen(action: Dictionary) -> void:
	stats[&"actions_submitted"] += 1
	if String(action["id"]) == "storm":
		open_assault()
		return
	CardActions.submit(host, action)
	close_fan()


## A refused action prints its hint in the chronicle (never popup chrome).
func _on_action_refused(action: Dictionary) -> void:
	stats[&"refusals_printed"] += 1
	presenter.push_row({
		"class": Inks.LineClass.WARN,
		"text": "The clerk strikes it through: %s." % String(action["reason"]),
	})
	_bind_chronicle()


## Touch path: a tap on a card focuses it and fans its actions.
func _on_card_gui_input(event: InputEvent, card: Control) -> void:
	var tapped := false
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true
	if tapped and is_instance_valid(card):
		card.grab_focus()
		open_fan_for_card(card)


# --- section binds ---------------------------------------------------------------------


## Cards for BOTH slots: diff the view's card list against each slot's
## spread (ids in order) — remove gone, add new, re-order moved, rebind
## the rest in place — then re-sync focus ids by index (the router's
## equivalence keys are part of the render). `count_render` bumps the
## instrumentation when called as a section render (not from full).
func _bind_cards_list(count_render := true) -> void:
	if _table_frozen:
		return  # the crush beat owns the table (T-UI-06): the cleared paper
			# stays cleared until the beat resolves; the intro's restart
			# re-deals beneath its own full refresh
	if _deals_held:
		return  # THE STAGED FIRST MOMENTS (the first-deal coverage fix):
			# the how-to offer paper owns the table — the deals it would
			# bury wait for its dismissal, then slide-and-settle (see
			# _on_howto_closed). The plots bound before the reveal stay
			# dealt; nothing else joins the table under the paper.
	if count_render:
		stats[&"card_list_renders"] += 1
	var cards: Array = _view["cards"]
	var gate_on := _gate_lane_on(cards)
	# The column ladder counts the ESTATE's cards only when the gate lane
	# stands (the offers have left the grid); with the lane off the ladder
	# reads the whole table — every offer-free bind is laid exactly as
	# always (the byte-identical rule).
	var columns := SpreadCards.adaptive_columns(
		_estate_count(cards) if gate_on else cards.size(),
		_portrait_spread_height(), 20.0, _spread_budget().x)
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var spread := slot.get_spread() as Container
		# The table is about to re-deal: any entrance slides still in flight
		# land on their seats NOW (a re-sort must never strand a card short).
		CardMotion.snap_all(spread)
		var by_id := {}
		for child in spread.get_children():
			if child is Control:
				by_id[String(child.get_meta(&"spread_card_id", ""))] = child
		var view_ids := {}
		for card in cards:
			view_ids[String(card["id"])] = card
		for id in by_id.keys():
			if not view_ids.has(id):
				var gone: Node = by_id[id]
				spread.remove_child(gone)
				gone.queue_free()
		var index := 0
		for card: Dictionary in cards:
			var id := String(card["id"])
			if not by_id.has(id):
				var node := SpreadCards.conspirator_card(card)
				slot.add_card(node)
				node.gui_input.connect(_on_card_gui_input.bind(node))
				if _entrances_armed:
					# Cards JOINING a live table deal in (slide-and-settle,
					# deferred so the container's sort sets the seat first).
					stats[&"entrances"] += 1
					CardMotion.settle_in.call_deferred(node)
			else:
				var node: Control = by_id[id]
				SpreadCards.rebind_card(node, card)
				if node.get_index() != index:
					spread.move_child(node, index)
			index += 1
		spread.set("columns", columns)
		_apply_gate_lane(spread, gate_on)
		spread.queue_sort()
		_sync_focus_ids(slot)
	_maybe_print_edge_primer()
	_validate_open_fan()


## True when the gate lane stands: offers at the gate AND a table small
## enough for the split to keep both bands honest (the FIRST DEAL's
## grammar — past CardSpread.GATE_SPLIT_MAX_CARDS the designed held-fan
## overlap resumes, the r4-audited dense state).
func _gate_lane_on(cards: Array) -> bool:
	if cards.size() > CardSpread.GATE_SPLIT_MAX_CARDS:
		return false
	for card: Dictionary in cards:
		if card["kind"] == &"offer":
			return true
	return false


## The estate's card count (everything but the gate offers) — the column
## ladder's input once the gate lane takes the offers out of the grid.
func _estate_count(cards: Array) -> int:
	var n := 0
	for card: Dictionary in cards:
		if card["kind"] != &"offer":
			n += 1
	return n


## The gate lane's honest application (the reserves' pattern): setting it
## only on change, and snapping settling cards first — a re-sort must
## never strand a card short of its seat.
func _apply_gate_lane(spread: Container, gate_on: bool) -> void:
	var lane := 1.0 if gate_on else 0.0
	if absf(float(spread.get("gate_lane")) - lane) > 0.01:
		CardMotion.snap_all(spread)
		spread.set("gate_lane", lane)


# --- the line-form primer (finishing refinement #2, P2) ----------------------------------


## ONE teaching line the first time a dashed (in-progress) edge appears
## in a SESSION (the closing critique's P2: the line-form vocabulary
## carries state on every card and row, but no surface ever said so).
## Once-only per session — a session-local latch, deliberately lighter
## than the first-session layer's persisted flags: each session teaches
## the grammar once at its first dashed edge (a staked plot's queued
## paper, a training card, the Eye closing), and the line scrolls away
## as the world keeps printing (it also lands on the day-sheet, where it
## stays retrievable for the rest of the hand).
func _maybe_print_edge_primer() -> void:
	if _primer_printed or _view.is_empty():
		return
	for card: Dictionary in _view["cards"]:
		if Inks.edge_form_for_state(card["edge_state"]) == Inks.EdgeForm.DASHED:
			_primer_printed = true
			stats[&"primer_lines"] += 1
			presenter.push_row({
				"class": Inks.LineClass.PLAIN,
				"text": CopyDeck.line(Inks.pack().copy, &"primer_lineform",
					host.engine.tick_count),
			})
			_bind_chronicle()
			return


## One card's plates re-print in place (both slots) — the targeted path.
func _rebind_card_by_uid(uid: int) -> void:
	if uid <= 0:
		return
	for candidate_id in ["offer_%d" % uid, "unit_%d" % uid]:
		var card := _view_card(String(candidate_id))
		if card.is_empty():
			continue
		stats[&"card_rebinds"] += 1
		_rebind_card_nodes(String(candidate_id), card)


## Training countdowns tick silently: refresh only training/awaiting
## cards' role plates (a handful at roster scale — targeted, not a roster
## pass; the CARD LIST is untouched).
func _rebind_training_cards() -> void:
	var units := host.units()
	for card: Dictionary in _view["cards"]:
		if card["kind"] != &"unit":
			continue
		var uid := int(card["uid"])
		if units.training_target(uid) == &"" and not units.is_awaiting_promotion(uid):
			continue
		var fresh := SpreadPresenter.unit_card_view(host, Inks.pack(), uid)
		if fresh.is_empty():
			continue
		if String(fresh["role"]) != String(card["role"]) \
				or fresh["edge_state"] != card["edge_state"]:
			card["role"] = fresh["role"]
			card["edge_state"] = fresh["edge_state"]
			stats[&"card_rebinds"] += 1
			_rebind_card_nodes(String(card["id"]), card)


func _rebind_card_nodes(id: String, card: Dictionary) -> void:
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		for child in slot.get_spread().get_children():
			if child is Control and String(child.get_meta(&"spread_card_id", "")) == id:
				SpreadCards.rebind_card(child, card)


## Pips: live values into both rails (shape + glyph + numeral pips; rail
## order = pack resource order — the slot rail is FOOD/TIMBER/IRON).
## Reads ONLY the three resource ints (the pip section's own state).
func _bind_pips() -> void:
	if _view.is_empty():
		return
	var view_resources: Array = _view["resources"]
	for i in view_resources.size():
		view_resources[i]["amount"] = host.engine.get_resource(view_resources[i]["id"])
	var ground := Inks.ground_for(_view["leader"]["regime_id"], _view["phase"])
	# THE PIP LABEL'S INK (the readability pass): the rail prints on the
	# TABLE GROUND, so its labels follow the print rule — the theme's
	# INK_SOFT default is the paper-plate value and washed out on the
	# dark ground (the triple encoding's textual channel was the game's
	# least-readable text). Paper-bright on dark grounds, ink on
	# aftermath.
	var text_ink := Inks.ground_text_ink(ground)
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		for i in mini(3, view_resources.size()):
			var pip := slot.get_pip(i)
			if pip != null:
				pip.set("label_ink", text_ink)
				pip.set("amount", int(view_resources[i]["amount"]))


## The Eye: fresh metrics from the suspicion system (the eye section's
## own state — three ints and a countdown) bound in both slots, placed
## inside each slot's spread band (periphery = the right edge). ARMED
## (finishing refinement #3): the plate grows to the armed card and takes
## the reserved lane seat (see _apply_eye_reserve).
func _bind_eye() -> void:
	stats[&"eye_binds"] += 1
	var suspicion := host.suspicion()
	var tunables: EconomyTunables = Inks.pack().tunables
	var eye := SpreadPresenter.eye_metrics(
		suspicion.suspicion_points(), suspicion.max_points(),
		tunables.suspicion_warn_threshold, tunables.suspicion_crackdown_threshold,
		suspicion.crackdown_land_tick != -1, host.is_run_running())
	var hours_left := SpreadPresenter.eye_hours_left(host)
	# THE ARMED LANE: the reserve rides the eye's own channel — arming
	# narrows the card field, relief or a dead run lifts it.
	_eye_armed = bool(eye["armed"]) and hours_left >= 0
	_apply_eye_reserve()
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var node := eye_of(slot)
		if node == null:
			continue
		node.bind(eye, hours_left)
		_place_eye(slot, node, eye, hours_left)


## THE ARMED LANE RESERVE (finishing refinement #3, layout-level): while
## the telegraph is armed, each slot's spread narrows — CardSpread's
## right_reserve keeps every card (and the fan's rotated end-card corners)
## clear of the armed Eye's seat. The perch must not crowd the fan's end
## card; the table itself makes way. Pure placement math on the eye's own
## constants (WatchfulEye.armed_lane), applied to both slots.
func _apply_eye_reserve() -> void:
	if host == null:
		return
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var spread := slot.get_spread() as CardSpread
		if spread == null:
			continue
		var reserve := 0.0
		if _eye_armed:
			# The lane is measured against the SLOT's right edge, the
			# reserve against the spread's — convert across the margin.
			reserve = WATCHFUL_EYE_SCRIPT.armed_lane(slot.portrait_topology) \
				- (slot.get_global_rect().end.x - spread.get_global_rect().end.x)
		if absf(float(spread.get("right_reserve")) - reserve) > 0.01:
			# A re-sort must never strand a settling card short of its seat.
			CardMotion.snap_all(spread)
			spread.set("right_reserve", reserve)
			spread.queue_sort()


func _place_eye(slot: OrientationSlot, node: Control, metrics: Dictionary,
		hours_left: int) -> void:
	## The perch hugs the table's right edge, vertically centered in the
	## spread band; inset slides the card toward the table's heart. Always
	## fully inside the slot rect (nothing may clip outside the design).
	## ARMED (finishing refinement #3): the committed seat in the reserved
	## lane — deeper than the perch, never crowding the card field.
	var spread_rect: Rect2 = slot.get_spread().get_global_rect()
	var slot_rect := slot.get_global_rect()
	var card_size: Vector2 = node.get_combined_minimum_size()
	node.size = card_size
	if bool(metrics["armed"]) and hours_left >= 0:
		node.global_position = WATCHFUL_EYE_SCRIPT.armed_seat(
			slot_rect, spread_rect, card_size, slot.portrait_topology)
		return
	var inset: float = metrics["inset"]
	var max_inset: float = maxf(0.0, spread_rect.size.x * 0.5 - card_size.x)
	node.global_position = Vector2(
		slot_rect.end.x - card_size.x - 8.0 - inset * max_inset,
		clampf(spread_rect.get_center().y - card_size.y * 0.5,
			slot_rect.position.y + 4.0, slot_rect.end.y - card_size.y - 4.0))


## The header strip (leader + regime ink + clock) in both slots.
## SCREENSHOT-INSPECTION FIND (T-UI-04's promote capture): the slot lays
## its topology out once at its own deferred _ready — BEFORE this bind
## adds the header, so the landscape chronicle printed ON the header
## strip's rect (identical rects, pre-existing since T-UI-03's
## composition; the quiet-state captures never crowded the strip enough
## to read as a collision). Re-running the pure topology after the bind
## places the strip and shifts everything below it, both orientations.
## FINISHING REFINEMENT #2: the strip is a COLUMN — row 0 the letterhead
## at the table's full width, row 1 THE LEDGER VERBS (the Chronicle,
## Day-Sheet and Press-Room chips, right-aligned). The letterhead row
## measured 666-of-672 fixed units at the 720 portrait base: a second verb
## beside it would stub the leader's name, and the column WIDENS the
## letterhead instead (the name plate takes what the verbs vacate).
func _bind_header() -> void:
	stats[&"header_binds"] += 1
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var strip := slot.get_header()
		if strip == null:
			continue
		var header: Control = strip.get_child(0) if strip.get_child_count() > 0 else null
		if header == null:
			header = RUN_HEADER_SCRIPT.new()
			header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			strip.add_child(header)
		header.bind(_view["leader"], _view["sim_hours"], _view["army_power"],
			Inks.ground_for(_view["leader"]["regime_id"], _view["phase"]),
			_view.get("escalation", {}))
		# FINISHING #6: the letterhead's name wraps when the pools deal a
		# long one — the row's height can change BIND TO BIND (a new leader,
		# a type-scale step), so the topology re-lays on every bind; a
		# taller letterhead shifts the rail/spread/chronicle down honestly
		# instead of drawing over them.
		slot.layout_topology()
		# THE LEDGER VERBS ROW (T-UI-08 + refinements #2/#5 + L1-C): the
		# chronicle chip, the day-sheet chip, the press-room chip and the
		# legacy chip at the row's right end — the same ActionChip grammar
		# as every verb, one of each per slot (the router's focus_id
		# equivalence carries the pad player's place across orientation
		# swaps).
		var verbs := strip.get_child(1) if strip.get_child_count() > 1 else null
		if verbs == null:
			verbs = _build_ledger_verbs()
			strip.add_child(verbs)
			slot.layout_topology()


## The header's verbs row: a right-aligned FLOW of the four table-paper
## chips (the readability pass — the row was a fixed HBox whose chips
## clipped their labels: "The Press-Room" +38px at 1.3x portrait). Each
## chip grows to its own measured print (ActionChip._grow_to_text); when
## the grown row exceeds the strip the flow WRAPS to a second line — the
## row's height is its own refit(strip_w) (LedgerVerbsRow), called by the
## slot's topology exactly like the letterhead's, so the header's height
## stays a pure function of text + factor + width. Built once per slot by
## _bind_header.
func _build_ledger_verbs() -> Control:
	var row := LEDGER_VERBS_ROW_SCRIPT.new()
	row.add_child(_ledger_chip("chronicle_chip", "The Chronicle", open_chronicle))
	row.add_child(_ledger_chip("day_sheet_chip", "The Day-Sheet", open_day_sheet))
	row.add_child(_ledger_chip("press_room_chip", "The Press-Room", open_press_room))
	row.add_child(_ledger_chip("legacy_chip", "The Legacy", open_legacy))
	# THE HOW-TO CHIP (the tutorial upgrade): the pamphlet one verb away,
	# in-run, for the player who missed the first-boot offer — or wants
	# the edges legend again. The flow wraps; the row's refit carries it.
	row.add_child(_ledger_chip("howto_chip", "How to Play", open_howto))
	return row


## One header ledger chip (the world's own verb grammar, full grip). The
## width is the ActionChip's measured-print floor (152) — the chip grows
## with its label in _ready.
func _ledger_chip(focus_id: String, label: String, handler: Callable) -> Control:
	var chip := ActionFan.ActionChip.new()
	chip.action = {
		"id": focus_id, "label": label, "command": &"",
		"subject": &"", "value": 0, "enabled": true, "reason": "",
		"signature": false,
	}
	chip.set_meta(&"focus_id", focus_id)
	chip.pressed.connect(handler)
	return chip


## Ground tone by run phase (regime ink + phase depth) in both slots.
func _bind_phase() -> void:
	stats[&"phase_binds"] += 1
	var regime_id: StringName = _view["leader"]["regime_id"]
	var phase: int = _view["phase"]
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var ground := slot.get_ground()
		if ground != null:
			ground.set("regime_id", regime_id)
			ground.set("phase", phase)


## The chronicle strip: newest prints at the top, both slots, inks chosen
## by the ground beneath (the print rule). Every print also reaches the
## day-sheet: an OPEN page is live paper — the new line lands on top of
## it in the same breath (finishing refinement #2).
func _bind_chronicle() -> void:
	stats[&"chronicle_prints"] += 1
	var rows := presenter.chronicle_strip()
	var ground := Inks.ground_for(_view["leader"]["regime_id"], _view["phase"])
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		for i in STRIP_LINES:
			var line := slot.get_chronicle_line(i)
			if line == null:
				continue
			if i < rows.size():
				line.set("line_class", int(rows[i]["class"]))
				line.set("text", String(rows[i]["text"]))
				line.set("ground", ground)
			else:
				line.set("text", "")
	if _day_sheet != null and _day_sheet.is_open():
		_day_sheet.sync_rows(host, presenter)


# --- helpers ----------------------------------------------------------------------------


## Viewport/orientation changed: re-place the periphery chrome the slot's
## own relayout cannot know about (the Eye card) and re-run the column
## ladder against the settled spread height (cards must never sink below
## the grip when the table changes shape). DEFERRED: size_changed fires
## before the layout pass settles the new rects — placing against
## half-settled rects would strand the Eye at the old edge (the exact
## failure the layout-determinism test caught).
func _on_layout_changed() -> void:
	if host == null or _view.is_empty():
		return
	_apply_columns.call_deferred()
	_bind_eye.call_deferred()
	_finalize_passes = 0  # a fresh layout event gets a fresh bounded budget
	# THE FINALIZATION PASS, AT RUNTIME (readability r2 — the r1 seam was
	# test-only): a slot's last topology pass can have run at a TRANSIENT
	# header budget (mid-bind plates, an async name wrap) and the steady
	# minimum that follows fires no sort of its own — the round-1 audit's
	# mounts starved the spread band by the transient's height (the
	# letterhead stranding ~150px of table). Both slots finish every
	# layout change the way the determinism test finishes its settle: one
	# explicit topology pass per slot at the steady minimums. Converges:
	# the steady pass reproduces its own budget and fires nothing further.
	_finalize_topology.call_deferred()
	if _suspicion != null:
		var bounds := _design_bounds().size
		_suspicion.replace_choice.call_deferred(bounds)
		_suspicion.replace_quote.call_deferred(bounds, _quote_floor())


## The finalization loop's bounded re-queue (see _finalize_topology).
const FINALIZE_MAX_PASSES := 8
var _finalize_passes := 0


func _finalize_topology() -> void:
	# BOUNDED CONVERGENCE (readability r3): one pass can still change a
	# slot's honest minimum — the plates' held heights (the r3
	# plate-minimum rule) land through the fit cascade AFTER the sort that
	# granted their widths — and a changed minimum must be laid AGAIN
	# before the table is stable. The pass re-queues (deferred) while
	# either spread's combined minimum moved, bounded: a settled tree
	# reproduces its own minimum and the loop stops; the bound exists so
	# a pathological never-converging plate cannot spin the mount.
	var spreads: Array[Control] = [
		get_portrait_slot().get_spread(), get_landscape_slot().get_spread()]
	var before: Array[Vector2] = []
	for spread in spreads:
		before.append(spread.get_combined_minimum_size())
	get_portrait_slot().layout_topology()
	get_landscape_slot().layout_topology()
	var moved := false
	for i in spreads.size():
		if before[i] != spreads[i].get_combined_minimum_size():
			moved = true
	if moved and _finalize_passes < FINALIZE_MAX_PASSES:
		_finalize_passes += 1
		_finalize_topology.call_deferred()
	else:
		_finalize_passes = 0


## The adaptive column ladder, re-derived from the CURRENT spread height
## and applied to both slots' spreads (a re-sort costs one sort pass).
## A column change re-lays the table — entrance slides land first. The
## ladder counts the ESTATE's cards only: the gate lane has taken the
## offers out of the grid (the gate row lays its own single row).
func _apply_columns() -> void:
	if _view.is_empty():
		return
	var columns := SpreadCards.adaptive_columns(
		_estate_count(_view["cards"]), _portrait_spread_height(), 20.0, _spread_budget().x)
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var spread := slot.get_spread() as Container
		if spread != null:
			CardMotion.snap_all(spread)
			spread.set("columns", columns)
			spread.queue_sort()


## Compose the per-slot chrome the foundation doesn't own: the Watchful
## Eye card in each slot (equivalence across orientation swaps). The
## spreads' `resized` signals drive the column ladder + Eye re-placement:
## a spread's final rect settles AFTER the slot's own deferred layout
## pass (and again on every window resize), and both the ladder and the
## perch must read the SETTLED geometry (the stale-columns failure the
## layout-determinism test caught).
func _compose_slot_chrome() -> void:
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		var eye := WATCHFUL_EYE_SCRIPT.new()
		eye.name = "WatchfulEye"
		slot.add_child(eye)
		var spread := slot.get_spread()
		if spread != null:
			spread.resized.connect(_on_layout_changed)


func eye_of(slot: Control) -> Control:
	for child in slot.get_children():
		if child.name == &"WatchfulEye":
			return child
	return null


func _view_card(id: String) -> Dictionary:
	for card: Dictionary in _view["cards"]:
		if String(card["id"]) == id:
			return card
	return {}


func _portrait_spread_height() -> float:
	## The stacked spread's height budget (the portrait column ladder's
	## input); degenerates safely to the grip floor before layout.
	var spread := get_portrait_slot().get_spread() as Control
	return maxf(spread.size.y, float(Inks.TOUCH_GRIP_MIN * 3))


func _spread_budget() -> Vector2:
	## The stacked spread's granted size (the ladder's width clamp — the
	## readability ladder grants the widest cell-honest card); the height
	## half is _portrait_spread_height's contract. The objective note's
	## reserved lane is subtracted — the ladder picks columns for the
	## cards' REAL width, never for width the pinned note owns.
	var spread := get_portrait_slot().get_spread() as Control
	var lane := 0.0
	if spread is CardSpread:
		lane = float((spread as CardSpread).get("left_reserve"))
	return Vector2(maxf(spread.size.x - lane, float(Inks.TOUCH_GRIP_MIN)),
		maxf(spread.size.y, float(Inks.TOUCH_GRIP_MIN * 3)))


func _sync_focus_ids(slot: OrientationSlot) -> void:
	## focus_id == index in BOTH slots: the router's swap equivalence and
	## the layout hash both key on it.
	var spread := slot.get_spread()
	for i in spread.get_child_count():
		var child := spread.get_child(i)
		if child is Control:
			child.set_meta(&"focus_id", "spread_card_%d" % i)


# --- debug chip (demo chrome — outside the slots, swaps never touch it) ------------------


func _build_debug_chip() -> void:
	## DEV CHROME, OPT-IN (the closing critique's non-diegetic find: the
	## "x600 — running" chip was the only mark in any capture that belongs
	## to no world): built only when CS_DEBUG_CHROME=1 asks for it — a
	## player's table and every capture show the diegetic surface alone.
	## The accel/pause INPUT ACTIONS stay available either way (they are
	## invisible; the chip is their only chrome).
	if OS.get_environment("CS_DEBUG_CHROME") != "1":
		return
	## Bottom-RIGHT: the landscape rail's pips start from the left edge —
	## the chip must never sit on a pip (screenshot-inspection find).
	_scale_chip = Label.new()
	_scale_chip.theme_type_variation = &"PipLabel"
	_scale_chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# The plate grows with the type scale (T-QA-05: "running" clipped to
	# "runn…" at 1.3x — the windowed spot-check's find).
	_scale_chip.offset_left = -150.0 * TypeScale.factor()
	_scale_chip.offset_top = -34.0 * TypeScale.factor()
	_scale_chip.offset_right = -16.0
	_scale_chip.offset_bottom = -10.0
	_scale_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scale_chip.add_theme_color_override("font_color", Inks.ground_text_ink(Inks.NEUTRAL_GROUND))
	_scale_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scale_chip)
	_refresh_chip()


func _refresh_chip() -> void:
	if _scale_chip == null:
		return
	_scale_chip.text = "x%d — %dh — %s" % [
		int(TIME_SCALES[time_scale_index]), int(host.engine.sim_hours()),
		"paused" if not host.driving else "running"]


func _unhandled_input(event: InputEvent) -> void:
	## Project actions only (never ui_* — focus owns those): the demo's
	## time-scale toggle, the world-freeze pause seam, T-UI-04's card
	## interaction verbs (back folds the fan; primary on a focused card
	## fans its actions — the pad/keyboard mirror of the touch tap.
	## Positional presses are EXCLUDED: touch/mouse act through the card's
	## own gui_input, so a tap on bare table never fans the focused card),
	## and T-UI-06's suspicion paper: back folds a choice card, primary
	## activates its focused chip, and ANY input skips the crush beat (a
	## player who has read the beat deals the next hand — positional
	## included, the beat's whole surface is its affordance).
	if _suspicion != null and _suspicion.beat_active() \
			and (event.is_action_pressed(&"back") or event.is_action_pressed(&"primary")):
		_suspicion.skip_beat()
		get_viewport().set_input_as_handled()
		return
	# TOUCH PARITY (T-QA-05): a POSITIONAL press that reaches unhandled
	# input landed on the bare table (cards and chips consume their own
	# gui_input; the paper layers sit above and stop theirs) — for a touch
	# player that press is the only "fold it without acting" gesture the
	# mode has (keyboard has back, pad has B). Fold the open paper: the
	# fan first, else a choice card — mirroring the back branch below.
	if (event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		if _fan != null and _fan.is_open():
			close_fan()
			get_viewport().set_input_as_handled()
			return
		if _suspicion != null and _suspicion.choice_is_open():
			_suspicion.fold_choice()
			_focus_first_card()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"back"):
		if _fan != null and _fan.is_open():
			close_fan()
			get_viewport().set_input_as_handled()
		elif _suspicion != null and _suspicion.choice_is_open():
			_suspicion.fold_choice()
			_focus_first_card()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"primary") and not (event is InputEventMouseButton) \
			and not (event is InputEventScreenTouch):
		if _fan != null and _fan.is_open():
			_fan.activate_focused()
			get_viewport().set_input_as_handled()
			return
		if _suspicion != null and _suspicion.choice_is_open():
			_suspicion.activate_focused_choice()
			get_viewport().set_input_as_handled()
			return
		var focus := get_viewport().gui_get_focus_owner()
		# PAD PARITY (T-PERF-02's Deck sweep find): the pad's A button is
		# NOT ui_accept (the project's own primary action — the engine fact
		# every screen's pad fallback exists for), so a focused BUTTON on
		# the table itself (the header's chronicle chip) was pressable only
		# from keyboard Enter and touch — the ledger was unreachable by
		# pad. Activate any focused BaseButton here, exactly once (the
		# natively-routed Enter never reaches unhandled input; positional
		# presses were already excluded above).
		if focus is BaseButton:
			(focus as BaseButton).pressed.emit()
			get_viewport().set_input_as_handled()
			return
		if focus != null and focus.has_meta(&"spread_card_id"):
			open_fan_for_card(focus)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"debug_fast_forward") and debug_accel:
		time_scale_index = (time_scale_index + 1) % TIME_SCALES.size()
		host.time_scale = TIME_SCALES[time_scale_index]
		_refresh_chip()
	elif event.is_action_pressed(&"pause") and debug_accel:
		host.set_driving(not host.driving)
		_refresh_chip()


## The platform seam (T-PERF-01): OS lifecycle notifications forwarded
## into the AppLifecycle policy with the platform's now — the ONE game-side
## clock read (the platform host's privilege per the security-policy
## inventory; every layer below this seam receives injected timestamps).
## Headless tests never fire these; the unit suite drives the policy
## directly with injected epochs (tests/unit/test_app_lifecycle.gd).
## THE AUTOSAVE LINE (finishing refinement #2, P3): the BACKGROUND flush
## prints one quiet strip row — "the clerk files the hour" — so the save
## the boundary just made is visible (and retrievable on the day-sheet
## when the player returns). Only the background flush: the periodic
## hourly autosave stays silent by choice (a line per sim hour is spam,
## not status).
func _notification(what: int) -> void:
	if lifecycle == null or host == null:
		return
	var action := lifecycle.handle_notification(what, int(Time.get_unix_time_from_system()))
	if action == &"backgrounded":
		_print_autosave_line()


## The background flush's one quiet print (CopyDeck's clerk, the real
## sim hour). Class PLAIN — filing the hour is routine business.
func _print_autosave_line() -> void:
	stats[&"autosave_lines"] += 1
	presenter.push_row({
		"class": Inks.LineClass.PLAIN,
		"text": CopyDeck.line(Inks.pack().copy, &"autosave_filed",
			host.engine.tick_count, {"hours": int(host.engine.sim_hours())}),
	})
	if not _view.is_empty():
		_bind_chronicle()


func _process(delta: float) -> void:
	host.advance(delta)
	if Engine.get_process_frames() % 15 == 0:
		_refresh_chip()


# --- dev inspection hook -----------------------------------------------------------------


## CS_SPREAD_SHOT=/path.png: settle the demo at 600x for
## CS_SPREAD_SETTLE_SECONDS (default 2.5), then save ONE capture and quit.
## With CS_SPREAD_LOUD=1 the demo runs the greed policy and the harness
## keeps fast-forwarding until a crackdown telegraph is armed (or 40h) —
## the pressured screenshot state (it prints what it reached).
func _capture_hook() -> void:
	var shot := OS.get_environment("CS_SPREAD_SHOT")
	if shot.is_empty():
		return
	# Let the DEFERRED first bind land before any capture drive: the drives
	# fast-forward the host, whose events would otherwise rebind sections
	# against a not-yet-built view (the capture hook runs inside _ready).
	await get_tree().process_frame
	await get_tree().process_frame
	host.time_scale = TIME_SCALES[TIME_SCALES.size() - 1]
	time_scale_index = TIME_SCALES.size() - 1
	var settle := OS.get_environment("CS_SPREAD_SETTLE_SECONDS").to_float()
	settle = settle if settle > 0.0 else 2.5
	var promote_mode := OS.get_environment("CS_SPREAD_PROMOTE")
	if promote_mode == "1" or promote_mode == "2":
		_promote_then_capture()
	elif OS.get_environment("CS_SPREAD_FAN") == "1":
		_fan_then_capture(settle)
	elif not OS.get_environment("CS_SPREAD_RESTART").is_empty():
		_restart_then_capture(String(OS.get_environment("CS_SPREAD_RESTART")).to_lower())
	elif not OS.get_environment("CS_SPREAD_INTRO").is_empty():
		_intro_then_capture(int(OS.get_environment("CS_SPREAD_INTRO")))
	elif not OS.get_environment("CS_SPREAD_ASSAULT").is_empty():
		_assault_then_capture(int(OS.get_environment("CS_SPREAD_ASSAULT")), settle)
	elif not OS.get_environment("CS_SPREAD_SUSPICION").is_empty():
		_suspicion_then_capture(int(OS.get_environment("CS_SPREAD_SUSPICION")), settle)
	elif not OS.get_environment("CS_SPREAD_CHRONICLE").is_empty():
		_chronicle_then_capture(int(OS.get_environment("CS_SPREAD_CHRONICLE")), settle)
	elif not OS.get_environment("CS_SPREAD_FIRST").is_empty():
		_first_session_then_capture(int(OS.get_environment("CS_SPREAD_FIRST")), settle)
	elif not OS.get_environment("CS_SPREAD_CATCHUP").is_empty():
		_catch_up_then_capture(int(OS.get_environment("CS_SPREAD_CATCHUP")), settle)
	elif not OS.get_environment("CS_SPREAD_DAYSHEET").is_empty():
		_day_sheet_then_capture(int(OS.get_environment("CS_SPREAD_DAYSHEET")), settle)
	elif not OS.get_environment("CS_SPREAD_PRESS").is_empty():
		_press_room_then_capture(int(OS.get_environment("CS_SPREAD_PRESS")), settle)
	elif not OS.get_environment("CS_SPREAD_LEGACY").is_empty():
		_legacy_then_capture(int(OS.get_environment("CS_SPREAD_LEGACY")), settle)
	elif not OS.get_environment("CS_SPREAD_ESCALATION").is_empty():
		_escalation_then_capture(int(OS.get_environment("CS_SPREAD_ESCALATION")), settle)
	elif not OS.get_environment("CS_SPREAD_HOWTO").is_empty():
		_howto_then_capture(int(OS.get_environment("CS_SPREAD_HOWTO")), settle)
	elif OS.get_environment("CS_SPREAD_LOUD") == "1":
		# The loud/pressure drive owns its prelude (see _unfold_boot_intro):
		# its captures were among the four veil-contaminated finds.
		_pressure_then_capture()
	else:
		# Plain settle: same rule — the boot reveal folds before the
		# capture, or the shot dims through the veil.
		await _unfold_boot_intro()
		_settle_then_capture(settle)


## THE CAPTURE DRIVES' SHARED PRELUDE — the consistency rule (the closing
## critique's find, reproduced 4x: the suspicion/first-session/catch-up
## drives unfolded the boot intro; the assault, loud and plain-settle
## drives did not, so those captures shot through the reveal veil and
## misrepresented the surface to every future inspection): a fresh boot's
## reveal mounts DEFERRED over the table, so EVERY drive that captures
## the table first waits for the paper and unfolds it — a player opens
## the game before they play it, and the harness plays the player.
## Documented exceptions, which capture the paper ITSELF: _intro_then_
## capture, and _catch_up_then_capture mode 3 (the resumed check-in
## reveal IS the capture). `mount_frames` bounds the deferred-mount wait
## (the intro opens within a few frames of _ready; the bound only spends
## itself when no reveal ever mounts — a resumed or silenced boot).
func _unfold_boot_intro(mount_frames := 90) -> void:
	for i in mount_frames:
		await get_tree().process_frame
		if _intro != null and _intro.is_open():
			break
	if _intro != null and _intro.is_open():
		_intro.unfold()
		for i in 300:
			await get_tree().process_frame
			if not _intro.is_open():
				break


## CS_SPREAD_HOWTO=1: the FIRST-FRESH-BOOT OFFER — the reveal folds and
## the clerk's small paper slides out with its two verbs (the capture
## waits for it; the offer line is printed for the log).
## =2: the PAMPHLET open via the header verb, captured in BOTH
## orientations (720x1280 portrait, 1280x800 landscape).
## =3: the PINNED OBJECTIVE NOTE mid-arc — the offer is declined through
## its real verb, the first arrival pins the gate objective at the
## table's reserved left lane, and the capture shows note + lane + the
## focused offer card.
func _howto_then_capture(mode: int, settle: float) -> void:
	host.time_scale = 1.0
	time_scale_index = 0
	demo_policy = null  # the player's session — no autopilot
	get_window().size = Vector2i(720, 1280)
	await _frames_for(0.4)
	if mode == 1:
		for i in 240:
			await get_tree().process_frame
			if _intro != null and _intro.is_open():
				break
		if _intro != null and _intro.is_open():
			_intro.unfold()
			for i in 300:
				await get_tree().process_frame
				if not _intro.is_open():
					break
		for i in 90:
			await get_tree().process_frame
			if _howto != null and _howto.is_open():
				break
		print("[spread] howto capture (offer): state %d, line '%s'" % [
			_howto.state, String(_howto.offer_panel().line_label().text)])
		_settle_then_capture(settle if settle > 0.0 else 0.4)
		return
	await _unfold_boot_intro(240)
	if mode == 2:
		open_howto()
		for i in 90:
			await get_tree().process_frame
			if get_viewport().gui_get_focus_owner() != null:
				break
		print("[spread] howto capture (pamphlet): sections %d, legend rows %d, hash %d" % [
			_howto.sheet().headings().size(), _howto.sheet().legend_rows().size(),
			_howto.sheet().snapshot_hash()])
		await _frames_for(0.5)
		var portrait := get_viewport().get_texture().get_image()
		portrait.save_png(_capture_path())
		print("[spread] screenshot %s — pamphlet portrait" % _capture_path())
		get_window().size = Vector2i(1280, 800)
		await _frames_for(1.2)
		var landscape := get_viewport().get_texture().get_image()
		var path := _capture_path()
		path = path.substr(0, path.length() - 4) + ".landscape" + path.substr(path.length() - 4)
		landscape.save_png(path)
		print("[spread] screenshot %s — pamphlet landscape" % path)
		get_tree().quit(0)
		return
	# mode 3: the note mid-arc. Decline the offer through its real verb
	# (the capture shows the NOTE, not the paper that answered it).
	if _howto != null and _howto.is_open() and _howto.state == HowToScreenScript.State.OFFER:
		_howto.offer_panel().decline_chip().pressed.emit()
		for i in 30:
			await get_tree().process_frame
	while int(host.units().pending_offers()) == 0 and host.engine.tick_count < 1200:
		host.fast_forward(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var note := _note_of(get_active_slot() as OrientationSlot)
	print("[spread] howto capture (note): visible %s, objective '%s' — lane %.0f" % [
		str(note != null and note.visible),
		String(note.objective_label().text) if note != null else "-",
		float((get_active_slot().get_spread() as CardSpread).get("left_reserve"))])
	var focus := get_viewport().gui_get_focus_owner()
	print("[spread]   focus on an offer card: %s" % str(
		focus != null and focus.has_meta(&"spread_card_id")
		and String(focus.get_meta(&"spread_card_id")).begins_with("offer_")))
	_settle_then_capture(settle if settle > 0.0 else 0.4)


## The capture drives' frame wait (wall frames at the driven pace).
func _frames_for(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await get_tree().process_frame


## CS_SPREAD_SUSPICION=1: the telegraph CHOICE CARD as it slides onto the
## table's edge (the loud drive until the telegraph arms, then settle).
## =2: the CRACKDOWN LANDED — the drive continues past the land tick and
## the capture waits for the blockquote (headline + seized + scattered).
## =3: the CRUSHED BEAT — the drive continues to the run's death and the
## capture waits for the crushing blockquote over the swept table, then
## skips to the loss-restart reveal (state printed in the log).
func _suspicion_then_capture(mode: int, settle: float) -> void:
	# The shared prelude: the boot reveal folds before the drive acts.
	await _unfold_boot_intro()
	demo_policy = DemoPolicy.new(40, 40, true)  # greed: gets watched
	var suspicion := host.suspicion()
	var waited_hours := 0.0
	var done := func() -> bool:
		if mode == 1:
			return _suspicion.choice_is_open() and bool(_suspicion.choice_model().get("urgent", false))
		if mode == 2:
			return suspicion.crackdown_land_tick != -1
		return not host.is_run_running()
	while not done.call() and waited_hours < 160.0:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		if demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
			demo_policy.apply(host)
		waited_hours += 1.0
	if mode == 2 and suspicion.crackdown_land_tick != -1:
		# HOLD THE BAND so the riders actually arrive: raw greed's act
		# bumps can outrun the 4h countdown to the crush WITHIN one hour
		# step (measured twice: 100/100, zero crackdowns). The capture
		# hook constructs the band through the documented meter seam,
		# pinned per tick — the arming, the landing tick, the seizure
		# payloads and the blockquote are all the real rules.
		var held := 0.0
		while suspicion.crackdowns_total == 0 and held < 10.0 and host.is_run_running():
			for i in SimEngine.TICKS_PER_SIM_HOUR:
				host.fast_forward(1)
				suspicion.set_suspicion(75)
			if demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
				demo_policy.apply(host)
			held += 1.0
			waited_hours += 1.0
	refresh_from_state()
	if mode == 3:
		# The beat starts DEFERRED (after the aftermath's full refresh) and
		# its quote opens after the authored strike+sweep — wait it out.
		for i in 600:
			await get_tree().process_frame
			if _suspicion.beat_phase == SuspicionEvents.BeatPhase.QUOTE:
				break
	print("[spread] suspicion capture mode %d after %.0fh: suspicion %d/%d, telegraph %s, crackdowns %d, run %s, beat phase %d"
		% [mode, waited_hours, suspicion.suspicion_points(), suspicion.max_points(),
			"armed" if suspicion.crackdown_land_tick != -1 else "unarmed", suspicion.crackdowns_total,
			"alive" if host.is_run_running() else "ended", _suspicion.beat_phase])
	if mode == 1 and not _suspicion.choice_is_open():
		print("[spread] suspicion capture: the choice card never opened — capturing the table as-is")
		_settle_then_capture(0.3)
		return
	for row: Dictionary in _suspicion.quote_rows():
		print("[spread]   quote: %s" % String(row["text"]))
	if mode == 3:
		# The crushed beat's quote over the swept table; then skip to the
		# reveal (which mounts over it) and report the seam.
		for i in maxi(2, int(0.4 * 60.0)):
			await get_tree().process_frame
		_capture_now("crushed")
		_suspicion.skip_beat()
		for i in 300:
			await get_tree().process_frame
			if _intro != null and _intro.is_open():
				break
		print("[spread] suspicion capture: after the beat the intro is %s (variant '%s')"
			% ["open" if _intro != null and _intro.is_open() else "closed",
				String(_intro.view()["variant"]) if _intro != null and _intro.is_open() else "-"])
		get_tree().quit(0)
		return
	_settle_then_capture(settle if settle > 0.0 else 0.4)


## CS_SPREAD_FIRST=1/2/3 (T-UI-10): the first session played as the
## PLAYER would (the demo policy is disabled for the drive — the hook
## submits the sensible first moves itself, through the host's write
## path). The world idles at 1x (the wall clock barely moves the sim)
## while the drive steps the session with fast_forward — the honest
## accel: every beat's tick is printed as its 1x wall-minute projection.
## =1 the EMPTY SPREAD + the first gate hint at the arrival;
## =2 the assignment + build-order hints (focus parked on the plot
## card); =3 the full arc through the TRICKLE print and on to the
## trainee hop, with the honest pacing report printed for the log.
func _first_session_then_capture(mode: int, settle: float) -> void:
	host.time_scale = 1.0  # the wall clock is scenery here; ffwd drives
	time_scale_index = 0
	demo_policy = null  # the player's session — no autopilot
	# The shared prelude (240-frame mount bound, this drive's precedent):
	# the boot reveal folds before the drive acts.
	await _unfold_boot_intro(240)
	var beat := {"empty_spread_cards": (_view.get("cards", []) as Array).size()}
	# Moment 1: the first arrival — the gate hint prints, focus parks on
	# the offer card (the highlight is the focus ring, never a mascot).
	while int(stats[&"first_nudges"]) < 1 and host.engine.tick_count < 60:
		host.fast_forward(1)
	await get_tree().process_frame
	beat["gate_tick"] = host.engine.tick_count
	_print_first_session_state("gate hint", beat["gate_tick"])
	if mode == 1:
		_settle_then_capture(settle if settle > 0.0 else 0.4)
		return
	# The player answers the gate; the role choice prints, and the
	# build-order hint lands on the next batch (affordability check).
	host.submit(&"recruit_accept", &"", int(host.units().offer_ids()[0]))
	while int(stats[&"first_nudges"]) < 3 and host.engine.tick_count < 80:
		host.fast_forward(1)
	await get_tree().process_frame
	beat["assign_tick"] = beat["gate_tick"] + 1
	beat["build_tick"] = host.engine.tick_count
	_print_first_session_state("assign + build hints", beat["build_tick"])
	var focus := get_viewport().gui_get_focus_owner()
	print("[spread] first-session focus after the build hint: %s (plot card: %s)"
		% [str(focus != null), str(focus != null
			and focus.has_meta(&"spread_card_id")
			and String(focus.get_meta(&"spread_card_id")).begins_with("bld_"))])
	if mode == 2:
		_settle_then_capture(settle if settle > 0.0 else 0.4)
		return
	# The sensible path continues: put them to work, raise the farm,
	# lend the hand the moment the pool has one, and wait for the
	# trickle — MOMENT 3, captured as the print lands.
	var idle: Array = host.units().idle_units(host.units().base_unit_id())
	if not idle.is_empty():
		host.submit(&"assign_role", &"worker", int(idle[0]))
	host.submit(&"upgrade_building", &"farm", 1)
	var waited := 0
	while int(stats[&"first_nudges"]) < 4 and waited < 120:
		waited += 1
		if host.production().idle_workers() > 0:
			host.submit(&"assign_worker", &"farm", 1)
		host.fast_forward(1)
	await get_tree().process_frame
	beat["trickle_tick"] = host.engine.tick_count if int(stats[&"first_nudges"]) >= 4 else -1
	_print_first_session_state("trickle print", beat["trickle_tick"])
	_capture_now("trickle")
	# The session plays on to the arc's end: the second body drills the
	# moment it stands idle, and the trainee hop is queued when the
	# drills complete (2h — the idle cadence, reported honestly).
	var worked_uid := -1
	if not idle.is_empty():
		worked_uid = int(idle[0])
	var queued := false
	while not queued and host.engine.tick_count < 600:
		host.fast_forward(1)
		for uid in host.units().offer_ids():
			host.submit(&"recruit_accept", &"", int(uid))
		for body in host.units().idle_units(host.units().base_unit_id()):
			if int(body) == worked_uid:
				continue
			host.submit(&"assign_role", &"militia", int(body))
		for body in host.units().idle_units(&"militia"):
			host.submit(&"start_training", &"trainee", int(body))
			queued = true
	beat["trainee_tick"] = host.engine.tick_count
	host.fast_forward(1)  # drain the queued hop so the report sees its print
	await get_tree().process_frame
	_print_first_session_state("trainee queued", beat["trainee_tick"])
	print("[spread] FIRST-SESSION PACING (sim ticks == wall minutes at 1x): %s"
		% str(beat))
	print("[spread]   choice arc (gate answered, role chosen, plot raised) done by minute %d"
		% int(beat["build_tick"]))
	for row: Dictionary in presenter.chronicle_strip():
		print("[spread]   strip: %s" % String(row["text"]))
	get_tree().quit(0)


func _print_first_session_state(label: String, tick: int) -> void:
	print("[spread] first-session %s at tick %d (minute %d at 1x) — nudges %d, flags %s"
		% [label, tick, tick, int(stats[&"first_nudges"]),
			str(host.meta.first_session)])


## CS_SPREAD_CATCHUP=1 (T-UI-09): the MID-SESSION print — the demo runs
## a few hours live, then the app backgrounds (anchor + save, injected
## epoch T0), and a 9h37m foreground resolves the CAPPED window on the
## LIVE table; the capture waits for the while-you-were-away blockquote
## and prints the foreground->print wall time. =2 (SEED): the drive ends
## AT the background boundary (anchor + run saved, no foreground) — run
## again with =3 to resume. =3 (RESUME): expects CS_DEMO_RESET=0 +
## CS_DEMO_NOW=<T0+gap> — the process boots RESUMED through the real
## save: the check-in unfold plays over the caught-up table, auto-opens,
## the print lands, and the capture reports the honest
## foreground->actionable-card wall time (the 3-second promise).
## =4 (CRACKDOWN-IN-WINDOW, the round-1 re-dispatch): the meter seam at
## 78 arms the telegraph before the app hides; the 4h land tick falls
## inside the 5h away window, so the capture shows the print's STRIKE
## row + the signed seizure losses from a REAL resolved window.
## Timestamps are injected constants; no OS clock is read by the game.
func _catch_up_then_capture(mode: int, settle: float) -> void:
	const T0 := 1_800_000_000  # synthetic platform epoch (printed for the =3 chaining)
	host.time_scale = TIME_SCALES[TIME_SCALES.size() - 1]
	time_scale_index = TIME_SCALES.size() - 1
	if mode != 3:
		# The shared prelude: the FIRST-HAND boot reveal folds before the
		# fresh-seed drives act (mode 3 boots RESUMED — its check-in
		# reveal IS the capture, never pre-folded).
		await _unfold_boot_intro()
	if mode == 2:
		# SEED: a few live hours, then the app hides — anchor + save, quit.
		var seeded := 0.0
		while seeded < 6.0:
			host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
			if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
				demo_policy.apply(host)
			seeded += 1.0
		refresh_from_state()
		host.background(T0)
		print("[spread] catch-up seed: %dh live, anchor saved at T0=%d, sim %dh, cards %d — now run =3 with CS_DEMO_RESET=0 CS_DEMO_NOW=%d"
			% [int(seeded), T0, int(host.engine.sim_hours()),
				host.units().total_units() + host.units().pending_offers(),
				T0 + 9 * 3600 + 37 * 60])
		_capture_now("pre-away table")
		get_tree().quit(0)
		return
	if mode == 1:
		# MID-SESSION: the window resolves on the LIVE table.
		var lived := 0.0
		while lived < 5.0:
			host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
			if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
				demo_policy.apply(host)
			lived += 1.0
		refresh_from_state()
		host.background(T0)
		var started := Time.get_ticks_msec()
		var report := host.foreground(T0 + 9 * 3600 + 37 * 60)  # 9h37m -> capped 8h
		for i in 300:
			await get_tree().process_frame
			if int(stats[&"catch_up_prints"]) > 0:
				break
		var focus := get_viewport().gui_get_focus_owner()
		print("[spread] catch-up print (mid-session): applied %d ticks (capped %s), rows %d, printed %dms after foreground, focus on table: %s"
			% [int(report["applied_ticks"]), str(report["capped"]),
				_suspicion.quote_rows().size(), Time.get_ticks_msec() - started,
				str(focus != null and focus.has_meta(&"spread_card_id"))])
		for row: Dictionary in _suspicion.quote_rows():
			print("[spread]   away: %s" % String(row["text"]))
		_settle_then_capture(settle if settle > 0.0 else 0.4)
		return
	if mode == 4:
		# CRACKDOWN-IN-WINDOW (the round-1 re-dispatch's capture): the
		# documented meter seam at 78 arms the telegraph BEFORE the app
		# hides — a player who left with the Crown's eye on them — and the
		# 4h land tick falls INSIDE the 5h away window, so the STRIKE row
		# and the signed seizures print from the REAL resolved window.
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		host.suspicion().set_suspicion(78)
		host.fast_forward(2)
		refresh_from_state()
		var armed := host.suspicion().crackdown_land_tick != -1
		host.background(T0)
		var started := Time.get_ticks_msec()
		var report := host.foreground(T0 + 5 * 3600)
		for i in 300:
			await get_tree().process_frame
			if int(stats[&"catch_up_prints"]) > 0:
				break
		print("[spread] catch-up print (crackdown-in-window): telegraph armed %s, applied %d ticks, crackdowns %d, rows %d, printed %dms after foreground"
			% [str(armed), int(report["applied_ticks"]),
				int(report.get("crackdowns", 0)), _suspicion.quote_rows().size(),
				Time.get_ticks_msec() - started])
		for row: Dictionary in _suspicion.quote_rows():
			print("[spread]   away: %s" % String(row["text"]))
		_settle_then_capture(settle if settle > 0.0 else 0.4)
		return
	# MODE 3 — RESUME: this process booted through CS_DEMO_NOW (see
	# build_demo_host); the check-in beat owns the entry.
	for i in 90:
		await get_tree().process_frame
		if _intro != null and _intro.is_open():
			break
	if _intro == null or not _intro.is_open():
		print("[spread] catch-up resume: the check-in reveal never opened (fresh boot? CS_DEMO_RESET=0 + CS_DEMO_NOW required) — capturing as-is")
		_settle_then_capture(0.3)
		return
	var view := _intro.view()
	print("[spread] catch-up resume: variant '%s', leader '%s' under '%s', report ticks %d (capped %s)"
		% [String(view["variant"]), String(view["leader"]["name"]),
			String(view["regime"]["name"]), int(host.last_catch_up_report.get("applied_ticks", 0)),
			str(host.last_catch_up_report.get("capped", false))])
	for line: Dictionary in view["lines"]:
		print("[spread]   print: %s" % String(line["text"]))
	_capture_now("check-in reveal")
	# The auto-unfold (0.75s dwell + 1.0s sweep), then the print on the
	# revealed table — the honest foreground->actionable measurement.
	for i in 600:
		await get_tree().process_frame
		if not _intro.is_open():
			break
	for i in 300:
		await get_tree().process_frame
		if int(stats[&"catch_up_prints"]) > 0:
			break
	var focus := get_viewport().gui_get_focus_owner()
	var actionable := focus != null and focus.has_meta(&"spread_card_id")
	var elapsed := Time.get_ticks_msec() - _catchup_boot_msec if _catchup_boot_msec >= 0 else -1
	print("[spread] catch-up resume: unfold closed + print landed, interactions %d (auto), focus on a card: %s — FOREGROUND -> ACTIONABLE %dms (the 3s promise)"
		% [_intro.interactions, str(actionable), elapsed])
	for row: Dictionary in _suspicion.quote_rows():
		print("[spread]   away: %s" % String(row["text"]))
	_capture_now("resumed spread + while-you-were-away", ".away")
	get_tree().quit(0)


## CS_SPREAD_DAYSHEET=1 (finishing refinement #2): the run's own page —
## the quiet demo policy runs ~14h so the hand has a real print history
## (arrivals, drills, buildings, suspicion drift, the primer line), then
## the day-sheet opens from the header verb and captures at CS_SPREAD_
## SHOT (newest line first, the dashed count rule, the back verb).
## =2: the page mid-run with the table visible beneath a CLOSED page
## (the verbs row itself is the capture — the letterhead + both chips).
func _day_sheet_then_capture(mode: int, settle: float) -> void:
	await _unfold_boot_intro()
	var lived := 0.0
	while lived < 14.0:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
			demo_policy.apply(host)
		lived += 1.0
	refresh_from_state()
	if mode == 2:
		print("[spread] day-sheet capture: the header verbs row (chronicle + day-sheet chips), %d lines on the page"
			% presenter.day_sheet.size())
		_settle_then_capture(settle if settle > 0.0 else 0.4)
		return
	# Freeze the table and fold any story paper: the capture is THE PAGE —
	# a choice card arriving mid-settle would close it (the story outranks
	# the ledger, by design) and the shot would show the table instead.
	host.driving = false
	if _suspicion != null:
		_suspicion.fold_choice()
		_suspicion.fold_quote()
	open_day_sheet()
	for i in 90:
		await get_tree().process_frame
		if get_viewport().gui_get_focus_owner() != null:
			break
	print("[spread] day-sheet capture: %dh in, %d lines, newest: '%s' — primer %s, strip rows %d"
		% [int(host.engine.sim_hours()), presenter.day_sheet.size(),
			String((presenter.day_sheet_newest_first()[0]["text"]) if not presenter.day_sheet.is_empty() else ""),
			"printed" if _primer_printed else "unprinted", presenter.chronicle.size()])
	_settle_then_capture(settle if settle > 0.0 else 0.4)


## CS_SPREAD_PRESS=1 (finishing refinement #5): the press-room card —
## the settings surface — open on the quiet table via the header verb,
## captured at CS_SPREAD_SHOT (the letterpress card, the kept rule, both
## preference rails, the back verb). =2: the LIVE re-flow — the 1.3x step
## is pressed through the REAL chip first, so the capture shows the card
## AND the re-typed table beneath the veil (letterhead, strip, pips at
## the larger hand), with the preference persisted to the meta domain.
func _press_room_then_capture(mode: int, settle: float) -> void:
	await _unfold_boot_intro()
	if mode == 2:
		# Reach the card through the player's own verb, press the 1.3x
		# step through the real chip, and let the re-flow settle.
		open_press_room()
		for i in 90:
			await get_tree().process_frame
			if get_viewport().gui_get_focus_owner() != null:
				break
		var pressed := false
		for chip in _press_room.sheet().type_steps():
			if is_equal_approx(float(chip.step_value), 1.3):
				chip.pressed.emit()
				pressed = true
		for i in 30:
			await get_tree().process_frame
		print("[spread] press-room capture: 1.3x step pressed %s — factor %.2f, meta %.2f, motion reduced %s"
			% [str(pressed), TypeScale.factor(), host.meta.type_scale_preference(),
				str(MotionProfile.reduced())])
	else:
		open_press_room()
		for i in 90:
			await get_tree().process_frame
			if get_viewport().gui_get_focus_owner() != null:
				break
	print("[spread] press-room capture: factor %.2f, reduced %s, steps %d"
		% [TypeScale.factor(), str(MotionProfile.reduced()),
			_press_room.sheet().type_steps().size()])
	_settle_then_capture(settle if settle > 0.0 else 0.4)


## CS_SPREAD_LEGACY=1/2/3 (L1-C): the growing deck's honest captures.
## =1 FRESH BANK — the first run still live, nothing earned: the deck
## opens over the veiled table ALL locked/dashed under the "earn your
## first legacy" line. =2 MID-RUN WITH SOME OWNED — three real hands end
## through the real verbs (banking their scores), the new hand plays on,
## then the player's own path buys a few cards through the real card
## presses BEFORE the capture (the mid-run mount note prints honestly).
## =3 FULL TREE — the whole deck kept: the meta bank is seeded through
## the fixture seam (the suspicion-meter precedent), then every node is
## bought through the REAL host command until nothing is affordable; the
## capture shows the deck fully solid + ink-filled crests.
func _legacy_then_capture(mode: int, settle: float) -> void:
	await _unfold_boot_intro()
	if mode == 1:
		host.driving = false
		open_legacy()
		for i in 90:
			await get_tree().process_frame
			if get_viewport().gui_get_focus_owner() != null:
				break
		var fresh_view: Dictionary = _legacy.view()
		print("[spread] legacy capture (fresh): bank %d, owned %d/%d, empty %s, live run %s — every card locked or short"
			% [int(fresh_view["bank"]), int(fresh_view["owned_count"]), int(fresh_view["node_count"]),
				str(bool(fresh_view["empty"])), str(bool(fresh_view["live_run"]))])
		_settle_then_capture(settle if settle > 0.0 else 0.4)
		return
	if mode == 2:
		var intro_was_enabled := intro_enabled
		intro_enabled = false
		for i in 3:
			var hours := 14.0 + float((i * 7) % 23)
			var waited := 0.0
			while waited < hours and host.is_run_running():
				host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
				if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
					demo_policy.apply(host)
				waited += 1.0
			match i % 3:
				0:
					host.submit(&"run_abort")
				1:
					host.submit(&"resolve_victory", &"loss", -1)
				_:
					host.submit(&"resolve_victory", &"win", host.units().army_power())
			host.fast_forward(2)
			if not host.is_run_running():
				host.restart_run()
				host.advance_ticks(1)
		intro_enabled = intro_was_enabled
		host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
		refresh_from_state()
		host.driving = false
		open_legacy()
		for i in 90:
			await get_tree().process_frame
			if get_viewport().gui_get_focus_owner() != null:
				break
		# The player's own path: buy through the real card presses — walk
		# focus onto the next affordable card (the deck's own seed rule),
		# then press it. Three cards kept, each through the real verb.
		var bought: Array[String] = []
		for i in 3:
			var target: LegacySheet.LegacyCard = null
			for card in _legacy.sheet().cards():
				if bool(card.model()["purchasable"]):
					target = card
					break
			if target == null:
				break
			target.grab_focus()
			await get_tree().process_frame
			bought.append(String(StringName(String(target.model()["id"]))))
			(target as BaseButton).pressed.emit()
			for f in 30:
				await get_tree().process_frame
		var mid_view: Dictionary = _legacy.view()
		print("[spread] legacy capture (mid-run): %d hands earned %d legacy in all; spent %d on [%s] through the real presses — bank now %d, owned %d/%d, live run %s (the mount note prints)"
			% [int(mid_view["runs_recorded"]), int(mid_view["total_earned"]), int(mid_view["spent"]),
				", ".join(bought), int(mid_view["bank"]),
				int(mid_view["owned_count"]), int(mid_view["node_count"]), str(bool(mid_view["live_run"]))])
		print("[spread]   print: %s" % _legacy.sheet().print_text())
		_settle_then_capture(settle if settle > 0.0 else 0.4)
		return
	# mode 3: the full tree, bought through the real command. One real
	# hand ends first so the count line reads honestly (a kept deck with
	# no hands recorded would be a fixture's tell).
	host.submit(&"run_abort")
	host.fast_forward(2)
	host.meta.legacy_points = 99999  # the fixture seam (the meter precedent)
	var guard := 0
	while true:
		var affordable := host.unlock_affordable()
		if affordable.is_empty() or guard > 64:
			break
		for id in affordable:
			host.unlock_purchase(id)
		guard += 1
	host.fast_forward(2)
	refresh_from_state()
	host.driving = false
	open_legacy()
	for i in 90:
		await get_tree().process_frame
		if get_viewport().gui_get_focus_owner() != null:
			break
	var full_view: Dictionary = _legacy.view()
	print("[spread] legacy capture (full tree): owned %d/%d, bank %d (residual), runs %d — every card SOLID + ink-filled crest; seed focus: %s"
		% [int(full_view["owned_count"]), int(full_view["node_count"]), int(full_view["bank"]),
			int(full_view["runs_recorded"]),
			"back chip (nothing left to buy)" if get_viewport().gui_get_focus_owner() == _legacy.sheet().back_chip() else "a card"])
	_settle_then_capture(settle if settle > 0.0 else 0.4)


## CS_SPREAD_ESCALATION=1 (L2-C): the WIN-RESTART REVEAL with a standing
## garrison — a cycle-2 snapshot is seeded through the fixture seam (the
## bank precedent; the CAPTURE itself is the engine suite's pin, the
## PRESENCE is this hook's), the hand ends through the real resolve verb
## (an empty roster captures nothing, so the seeded garrison stands exactly
## as the ladder's own rule promises), and the intro deals the next hand:
## the regime face card re-faces to the victor's line, the third print is
## the escalation voice.
## =2: the ODDS TABLE against the cycle-2 garrison — the same seeded
## standing snapshot, the demo driven to the knight floor, the odds open:
## the veterans' crest + cycle numeral on the castle card, the tier-mix
## detail row beneath the composition line.
## =3: THE REAL CAPTURE END TO END — the win through the assault's
## two-step commit (re-attempting the die), the vignette skipped to its
## outcome where the CAPTURE BEAT printed beside the seal, then the win
## reveal the close chip deals, then the chronicle's entry line.
func _escalation_then_capture(mode: int, settle: float) -> void:
	host.time_scale = TIME_SCALES[TIME_SCALES.size() - 1]
	time_scale_index = TIME_SCALES.size() - 1
	await _unfold_boot_intro()
	if mode <= 2:
		_seed_standing_garrison()
	if mode == 1:
		host.fast_forward(6 * SimEngine.TICKS_PER_SIM_HOUR)
		host.submit(&"resolve_victory", &"win", 12)
		host.fast_forward(2)
		# The win seam's mount (the assault's close normally owns this; the
		# resolve verb skipped the vignette, so the drive presses it).
		_open_intro()
		for i in 300:
			await get_tree().process_frame
			if _intro != null and _intro.is_open():
				break
		if _intro == null or not _intro.is_open():
			print("[spread] escalation capture: the reveal never mounted — capturing as-is")
			_settle_then_capture(0.3)
			return
		var view := _intro.view()
		var escalation: Dictionary = view.get("escalation", {})
		print("[spread] escalation capture (reveal): variant '%s', cycle %s under crest '%s', line 3: %s"
			% [String(view["variant"]), str(escalation.get("cycle", "-")),
				str(view["regime"].get("veterans_crest", "-")),
				String((view["lines"] as Array)[2]["text"])])
		for line: Dictionary in view["lines"]:
			print("[spread]   print: %s" % String(line["text"]))
		for i in 60:
			await get_tree().process_frame
		_capture_now("win reveal with standing garrison")
		get_tree().quit(0)
		return
	if mode == 2:
		var assault := host.assault()
		var waited_hours := 0.0
		while not assault.floor_met(host.engine) and waited_hours < 220.0:
			host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
			if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
				demo_policy.apply(host)
			waited_hours += 1.0
		refresh_from_state()
		var odds := assault.assault_odds(host.engine)
		print("[spread] escalation capture (odds): floor met after %.0fh — garrison %d in 1000 against; castle card: %s"
			% [waited_hours, int(odds["win_permille"]),
				AssaultPresenter.garrison_line(AssaultPresenter.odds_view(odds),
					Inks.regime_name(host.run().regime_id()))])
		print("[spread]   detail: %s" % AssaultPresenter.garrison_detail_line(
			AssaultPresenter.odds_view(odds)))
		_assault.open(host, get_router())
		for i in 30:
			await get_tree().process_frame
		for row: Dictionary in _assault.stage().printed_lines():
			print("[spread]   strip: %s" % String(row["text"]))
		_settle_then_capture(settle if settle > 0.0 else 0.4)
		return
	# MODE 3 — the real capture end to end (the restart drive's win loop).
	var tries := 0
	while tries < 5 and host.is_run_running():
		tries += 1
		var waited_hours := 0.0
		while not host.assault().floor_met(host.engine) and waited_hours < 220.0:
			host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
			if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
				demo_policy.apply(host)
			waited_hours += 1.0
		refresh_from_state()
		_assault.open(host, get_router())
		await get_tree().process_frame
		_assault.commit()
		await get_tree().process_frame
		_assault.commit()
		for i in 60:
			await get_tree().process_frame
			if _assault.state != AssaultScreenScript.State.ODDS:
				break
		if _assault.state == AssaultScreenScript.State.VIGNETTE:
			_assault.skip()
		for i in 1200:
			await get_tree().process_frame
			if _assault.state == AssaultScreenScript.State.OUTCOME:
				break
		print("[spread] escalation capture (storm): try %d after %.0fh — outcome '%s', cycle %d, snapshot leader '%s'"
			% [tries, waited_hours, String(_assault._script.get("outcome", &"")),
				host.meta.escalation_cycle, String(host.meta.escalation_garrison.get("leader", ""))])
		if not host.is_run_running():
			break
		_assault.close()
		for i in 20:
			await get_tree().process_frame
	for row: Dictionary in _assault.stage().printed_lines():
		print("[spread]   strip: %s" % String(row["text"]))
	for i in 30:
		await get_tree().process_frame
	_capture_now("victory capture beat")
	# The close chip deals the next hand: the reveal carries the REAL
	# capture's presence (the veterans' line from this very hand).
	var chips := _assault.stage().chips()
	if chips.size() > 0:
		(chips[0] as BaseButton).pressed.emit()
	for i in 300:
		await get_tree().process_frame
		if _intro != null and _intro.is_open():
			break
	if _intro != null and _intro.is_open():
		var view := _intro.view()
		print("[spread] escalation capture (reveal): variant '%s', cycle %s, line 3: %s"
			% [String(view["variant"]), str((view.get("escalation", {}) as Dictionary).get("cycle", "-")),
				String((view["lines"] as Array)[2]["text"])])
		_capture_now("win reveal of the real capture", ".reveal")
		_intro.unfold()
		for i in 400:
			await get_tree().process_frame
			if not _intro.is_open():
				break
	# The chronicle: the victory entry's escalation line, rendered.
	_chronicle.open(host, get_router())
	await get_tree().process_frame
	await get_tree().process_frame
	for entry: Dictionary in _chronicle.view()["entries"]:
		print("[spread]   hand %d %s — escalation: '%s'" % [int(entry["run"]),
			String(entry["seal"]["mark"]), String(entry["escalation_line"])])
	for i in 30:
		await get_tree().process_frame
	_capture_now("chronicle escalation line", ".chronicle")
	get_tree().quit(0)


## The fixture seam (the legacy full-tree precedent): a realistic cycle-2
## standing garrison in the shared meta — a 12-knight take with a mixed
## kit — for the PRESENCE captures (modes 1-2). The engine's own suites
## pin the real capture; this seeds the state the surfaces read.
func _seed_standing_garrison() -> void:
	host.meta.escalation_garrison = {
		"regime_id": String(host.run().regime_id()),
		"captured_at_run": 1, "cycle": 2,
		"leader": "Bartholomew the Unbearable",
		"crest_id": String(_regime_crest(host.run().regime_id())),
		"roster": {
			"knight": {"count": 9, "gear_tiers": {"weapon": {"1": 4, "2": 5}}},
			"archer": {"count": 3, "gear_tiers": {"weapon": {"1": 3}}},
		},
	}
	host.meta.escalation_cycle = 2


func _regime_crest(regime_id: StringName) -> StringName:
	for regime: RegimeDef in Inks.pack().regimes:
		if regime.id == regime_id:
			return regime.crest_id
	return &""


## CS_SPREAD_CHRONICLE=1: the ledger (T-UI-08) over a FEW real hands —
## three policy-driven runs end through the REAL verbs (win / loss /
## abort), the new hand is dealt, and the chronicle opens from the header
## chip's verb; capture at CS_SPREAD_SHOT (the newest page, the live-hand
## strip, the seals). =2: the ring after MANY hands — 50 real runs with
## varied durations and all three outcomes, captured at the newest page,
## the MID-RING TALL PAGE exactly one turn in (.turn.png — the round-1
## verifier repro shape: a full band-exceeding page after ONE turn), AND
## the ring's far end (.old.png) with the page chips' states.
func _chronicle_then_capture(mode: int, settle: float) -> void:
	# The drive ends runs; the spread would mount the loss reveal on each
	# ending (its documented role) — disabled for the drive (sibling-suite
	# pattern), restored after: the capture shows the LEDGER, not paper
	# stacking on paper. The BOOT reveal still folds first (the shared
	# prelude) — the silenced mounts cannot reopen later.
	var intro_was_enabled := intro_enabled
	intro_enabled = false
	await _unfold_boot_intro()
	var hands := 3 if mode == 1 else 50
	for i in hands:
		var hours := 14.0 + float((i * 7) % 23)
		var waited := 0.0
		while waited < hours and host.is_run_running():
			host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
			if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
				demo_policy.apply(host)
			waited += 1.0
		match i % 3:
			0:
				# The early hand aborts (short, no army yet — honest), the
				# later hands lose and win with the army the policy built.
				host.submit(&"run_abort")
			1:
				# -1 = the LIVE army power (the real failure paths' shape —
				# a forced 0 would print "power 0" beside a real roster).
				host.submit(&"resolve_victory", &"loss", -1)
			_:
				host.submit(&"resolve_victory", &"win", host.units().army_power())
		host.fast_forward(2)
		if not host.is_run_running():
			host.restart_run()
			host.advance_ticks(1)
	intro_enabled = intro_was_enabled
	# The live hand plays on a few hours (a 0h live strip reads as a
	# placeholder; the real check-in is mid-hand).
	host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
	refresh_from_state()
	var chronicle := host.meta.chronicle
	var last: Dictionary = chronicle[chronicle.size() - 1] if not chronicle.is_empty() else {}
	_chronicle.open(host, get_router())
	print("[spread] chronicle capture mode %d: %d hands recorded, bank %d, per-page %d, last hand %s (%s)"
		% [mode, host.meta.runs_recorded, host.meta.legacy_points, int(_chronicle.view()["per_page"]),
			String(last.get("leader", "-")), String(last.get("outcome", "-"))])
	for entry: Dictionary in _chronicle.view()["entries"]:
		print("[spread]   hand %d %s — %s %s, %s, %s"
			% [int(entry["run"]), String(entry["leader"]), String(entry["seal"]["mark"]),
				String(entry["duration_line"]), String(entry["army_line"]),
				"banked %d" % int(entry["score"])])
	for i in maxi(3, int(settle * 60.0)):
		await get_tree().process_frame
	_capture_now("chronicle newest page")
	if mode == 2:
		# THE MID-RING TALL PAGE after ONE turn (the round-1 verifier
		# repro shape): a full 6-card page that exceeds its band, exactly
		# one turn in — the capture the original walk could never show
		# (it ended on the fitting 2-entry oldest page, so the stale-scroll
		# defect was invisible to it).
		_chronicle.turn_page(1)
		for i in 20:
			await get_tree().process_frame
		var tall_scroll := _chronicle.sheet().scroll()
		print("[spread] chronicle capture: mid-ring page %d/%d after ONE turn — entries %d, scroll %d/%d (at top: %s)"
			% [_chronicle.page + 1, int(_chronicle.view()["page_count"]),
				(_chronicle.view()["entries"] as Array).size(),
				tall_scroll.scroll_vertical, int(tall_scroll.get_v_scroll_bar().max_value),
				str(tall_scroll.scroll_vertical == 0)])
		_capture_now("chronicle mid-ring tall page", ".turn")
		while _chronicle.page + 1 < int(_chronicle.view()["page_count"]):
			_chronicle.turn_page(1)
		for i in 20:
			await get_tree().process_frame
		print("[spread] chronicle capture: oldest page %d/%d, entries %d"
			% [_chronicle.page + 1, int(_chronicle.view()["page_count"]),
				(_chronicle.view()["entries"] as Array).size()])
		_capture_now("chronicle oldest page", ".old")
	get_tree().quit(0)


## CS_SPREAD_ASSAULT=1: the odds table's honest capture — the demo is
## driven (the screen's own policy cadence, fast) until the knight floor
## is met, then the assault odds screen opens and settles.
## CS_SPREAD_ASSAULT=2: COMMIT goes down the real write path and the
## capture waits for a landed beat mid-vignette (the watchable storm).
func _assault_then_capture(mode: int, settle: float) -> void:
	# The shared prelude: this drive was among the veil-contaminated
	# captures (the odds table shot through the un-folded boot reveal).
	await _unfold_boot_intro()
	var assault := host.assault()
	var waited_hours := 0.0
	while not assault.floor_met(host.engine) and waited_hours < 220.0:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
			demo_policy.apply(host)
		waited_hours += 1.0
	refresh_from_state()
	print("[spread] assault capture: floor met after %.0fh (power %d, odds %d in 1000)"
		% [waited_hours, host.units().army_power(),
			assault.assault_odds(host.engine)["win_permille"]])
	_assault.open(host, get_router())
	await get_tree().process_frame
	if mode >= 2:
		# The TWO-STEP raise, exactly as the player presses it: the first
		# commit arms (the clerk's caution prints), the second casts.
		_assault.commit()
		await get_tree().process_frame
		_assault.commit()
		if mode == 2:
			# A landed beat mid-vignette (the watchable storm).
			for i in 900:
				await get_tree().process_frame
				if _assault.current_beat_index() >= 1:
					break
			print("[spread] assault capture: beat %d mid-vignette (state %d)"
				% [_assault.current_beat_index(), _assault.state])
			for i in 20:
				await get_tree().process_frame
		else:
			# The settled outcome (rout + aftermath wash, or the fall).
			for i in 2400:
				await get_tree().process_frame
				if _assault.state == 4:  # OUTCOME
					break
			for i in 90:
				await get_tree().process_frame
			print("[spread] assault capture: outcome '%s' (script %s)"
				% [String(_assault._script.get("outcome", &"")), _assault.state])
	_settle_then_capture(0.3)


## CS_SPREAD_INTRO=1: the FIRST-HAND reveal as the player meets it (the
## fresh demo boots straight into the intro) — capture at CS_SPREAD_SHOT.
## =2: the reveal capture, then the one gesture goes down and a second
## capture waits for the MID-SWEEP (progress past 0.2, the packet open,
## the spread showing through the lifting veil) at <shot>.mid.png — the
## unfold's honest look, not a pose.
func _intro_then_capture(mode: int) -> void:
	for i in 240:
		await get_tree().process_frame
		if _intro != null and _intro.is_open():
			break
	for i in 60:
		await get_tree().process_frame
	if _intro == null or not _intro.is_open():
		print("[spread] intro capture: the intro never opened (fresh boot?) — capturing as-is")
		_settle_then_capture(0.3)
		return
	print("[spread] intro capture: variant '%s', leader '%s' under '%s', %d lines"
		% [String(_intro.view()["variant"]), String(_intro.view()["leader"]["name"]),
			String(_intro.view()["regime"]["name"]), (_intro.view()["lines"] as Array).size()])
	for line: Dictionary in _intro.view()["lines"]:
		print("[spread]   print: %s" % String(line["text"]))
	_capture_now("reveal")
	if mode == 1:
		get_tree().quit(0)
		return
	_intro.unfold()
	var mid := 0.0
	for i in 240:
		await get_tree().process_frame
		mid = _intro.unfold_progress()
		if mid > 0.2:
			break
	print("[spread] intro capture: mid-unfold at %.2f (%.2fs pacing), interactions %d"
		% [mid, _intro.last_unfold_seconds, _intro.interactions])
	_capture_now("mid-unfold", ".mid")
	for i in 240:
		await get_tree().process_frame
		if not _intro.is_open():
			break
	print("[spread] intro capture: closed after %d interaction(s), spread focused: %s"
		% [_intro.interactions, get_viewport().gui_get_focus_owner() != null])
	get_tree().quit(0)


## CS_SPREAD_RESTART=win: the FULL victory restart through the real seams
## at accel — the demo policy drives to the knight floor, COMMIT goes
## down the write path (re-attempting if the die loses — the designed
## variance), the vignette is skipped to its outcome, "Deal the next
## hand" closes it, and the intro's WIN reveal (regime-swap beat + bank +
## the new leader) is captured at reveal + mid-unfold.
## CS_SPREAD_RESTART=loss: the greed policy until the CRUSH lands
## (run_lost through the real suspicion rules), then the LOSS reveal
## (same regime + "the regime remembers") captured the same way.
func _restart_then_capture(kind: String) -> void:
	host.time_scale = TIME_SCALES[TIME_SCALES.size() - 1]
	time_scale_index = TIME_SCALES.size() - 1
	# The shared prelude: the boot deal unfolds before the drive acts
	# (the drive cannot commit under paper — the intro owns input).
	await _unfold_boot_intro()
	if kind == "win":
		var tries := 0
		while tries < 5 and host.is_run_running():
			tries += 1
			var waited_hours := 0.0
			while not host.assault().floor_met(host.engine) and waited_hours < 220.0:
				host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
				if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
					demo_policy.apply(host)
				waited_hours += 1.0
			refresh_from_state()
			_assault.open(host, get_router())
			await get_tree().process_frame
			# The TWO-STEP raise (the player's presses, in order).
			_assault.commit()
			await get_tree().process_frame
			_assault.commit()
			for i in 60:
				await get_tree().process_frame
				if _assault.state != AssaultScreenScript.State.ODDS:
					break
			if _assault.state == AssaultScreenScript.State.VIGNETTE:
				_assault.skip()
			for i in 1200:
				await get_tree().process_frame
				if _assault.state == AssaultScreenScript.State.OUTCOME:
					break
			print("[spread] restart drive: assault try %d after %.0fh — outcome '%s', run %s"
				% [tries, waited_hours, String(_assault._script.get("outcome", &"")),
					"ended" if not host.is_run_running() else "alive (the die lost)"])
			if not host.is_run_running():
				break  # the hand ended (win, or the edge spike's crush)
			_assault.close()
			for i in 20:
				await get_tree().process_frame
		_assault.close()
	else:
		demo_policy = DemoPolicy.new(24, 40, true)  # greed: never lay low
		var greed_hours := 0.0
		while host.is_run_running() and greed_hours < 120.0:
			host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
			if demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
				demo_policy.apply(host)
			greed_hours += 1.0
		print("[spread] restart drive: after %.0fh the run is %s"
			% [greed_hours, "alive (crush not reached)" if host.is_run_running() else "ended"])
	# The loss reveal mounts AFTER the crush beat (T-UI-06: cards struck +
	# swept, the crushing blockquote, THEN the new hand) — the wait covers
	# the beat's authored pacing plus the reveal's defer.
	for i in 900:
		await get_tree().process_frame
		if _intro != null and _intro.is_open():
			break
	if _intro == null or not _intro.is_open():
		print("[spread] restart capture: the intro never mounted — capturing the table as-is")
		_settle_then_capture(0.3)
		return
	var view := _intro.view()
	print("[spread] restart capture: variant '%s', run %d, leader '%s' under '%s', bank %d"
		% [String(view["variant"]), int(view["run_number"]), String(view["leader"]["name"]),
			String(view["regime"]["name"]), int(view["bank"])])
	for line: Dictionary in view["lines"]:
		print("[spread]   print: %s" % String(line["text"]))
	for i in 60:
		await get_tree().process_frame
	_capture_now("reveal")
	_intro.unfold()
	var mid := 0.0
	for i in 240:
		await get_tree().process_frame
		mid = _intro.unfold_progress()
		if mid > 0.2:
			break
	print("[spread] restart capture: mid-unfold at %.2f, interactions %d"
		% [mid, _intro.interactions])
	_capture_now("mid-unfold", ".mid")
	get_tree().quit(0)


## One capture, now (the capture hooks' shared save — no settle loop).
func _capture_now(label: String, suffix := "") -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _capture_path()
	if not suffix.is_empty():
		path = path.substr(0, path.length() - 4) + suffix + path.substr(path.length() - 4)
	var err := image.save_png(path)
	print("[spread] screenshot %s (%s) — %s" % [
		path, "ok" if err == OK else "FAILED %d" % err, label])


func _pressure_then_capture() -> void:
	# The shared prelude: this drive was among the veil-contaminated
	# captures (the pressured table shot through the un-folded reveal).
	await _unfold_boot_intro()
	var suspicion := host.suspicion()
	var waited_hours := 0.0
	while suspicion.crackdown_land_tick == -1 and suspicion.crackdowns_total == 0 \
			and waited_hours < 40.0:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		if demo_policy != null and demo_policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
			demo_policy.apply(host)
		waited_hours += 1.0
	refresh_from_state()
	print("[spread] pressured state: suspicion %d/%d, telegraph %s, after %.0fh"
		% [suspicion.suspicion_points(), suspicion.max_points(),
			"armed" if suspicion.crackdown_land_tick != -1 else "unarmed", waited_hours])
	_settle_then_capture(0.5)


func _settle_then_capture(settle: float) -> void:
	for i in maxi(2, int(settle * 60.0)):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_capture_path())
	print("[spread] screenshot %s (%s) — settled %.1fs wall, sim %dh, cards %d"
		% [_capture_path(), "ok" if err == OK else "FAILED %d" % err, settle,
			int(host.engine.sim_hours()), host.units().total_units() + host.units().pending_offers()])
	get_tree().quit(0)


func _capture_path() -> String:
	return OS.get_environment("CS_SPREAD_SHOT")


## CS_SPREAD_PROMOTE=1: the SIGNATURE MOMENT's honest capture. Phase 1
## drives the demo (the screen's own per-batch policy cadence) until a
## trainee is HELD awaiting gear the pool could not yet pay for. Phase 2
## finishes the kit by hand (cheapest tier per missing slot, only what
## the pool pays, hours of production between attempts — the held policy
## would otherwise promote them itself). Then the REAL promote command
## goes down the host's write path, and the capture waits for the card to
## be PAST its 90-degree crossing and readable (scale.x settled into its
## reveal sweep) — the knight face half-turned: what the flip actually
## looks like, not a pose.
func _promote_then_capture() -> void:
	# The shared prelude: the flip captures on the revealed table, never
	# through the boot reveal's veil.
	await _unfold_boot_intro()
	var waited_hours := 0.0
	while host.units().awaiting_promotion_ids().is_empty() and waited_hours < 90.0:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)  # _on_ticks applies the policy
		waited_hours += 1.0
	while _promotion_candidate() == 0 and waited_hours < 150.0:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		waited_hours += 1.0
		_equip_missing_cheapest()
	refresh_from_state()
	var candidate := _promotion_candidate()
	if candidate == 0:
		print("[spread] promote capture: no fully-geared trainee reached in %.0fh — capturing state as-is" % waited_hours)
		_settle_then_capture(0.5)
		return
	host.time_scale = 60.0  # the command drains within a frame; the flip itself is real-time
	host.submit(&"promote", &"", candidate)
	var landed := OS.get_environment("CS_SPREAD_PROMOTE") == "2"
	var revealed := 0.0
	for i in 240:
		await get_tree().process_frame
		var mid := _mid_flip_node()
		if mid != null:
			revealed = mid.scale.x
			if revealed > 0.25 and not landed:
				break
		elif landed and revealed > 0.0:
			break  # the flip finished; the flourish is fresh off the press
	print("[spread] promote capture: uid %d, %s at scale.x %.2f, after %.0fh of demo" % [
		candidate, "landed" if landed else "caught past the crossing", revealed, waited_hours])
	_settle_then_capture(0.0)


## CS_SPREAD_FAN=1: capture an open action fan (the in-world affordance)
## on the first card that has choices.
func _fan_then_capture(settle: float) -> void:
	# The shared prelude: the fan captures on the revealed table.
	await _unfold_boot_intro()
	for i in maxi(2, int(settle * 60.0)):
		await get_tree().process_frame
	var active := get_active_slot() as OrientationSlot
	for i in active.get_spread().get_child_count():
		var card := active.get_spread().get_child(i) as Control
		if card == null:
			continue
		card.grab_focus()
		open_fan_for_card(card)
		if _fan.is_open():
			break
	print("[spread] fan capture: card '%s', %d chips" % [_fan.card_id, _fan.chips().size()])
	for i in 20:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_capture_path())
	print("[spread] screenshot %s (%s) — fan state" % [
		_capture_path(), "ok" if err == OK else "FAILED %d" % err])
	get_tree().quit(0)


## A fully-geared trainee awaiting the promote command (the capture
## candidate), 0 when none stands by.
func _promotion_candidate() -> int:
	var units := host.units()
	for uid in units.awaiting_promotion_ids():
		if units.missing_gear_slots(uid).is_empty() and _is_army_def(units.training_target(uid)):
			return uid
	return 0


## The capture drive's kit-finisher: cheapest affordable tier per missing
## slot for every held trainee, through the real command (returns whether
## anything was submitted — production accrues between attempts).
func _equip_missing_cheapest() -> bool:
	var units := host.units()
	var submitted := false
	for uid in units.awaiting_promotion_ids():
		for slot in units.missing_gear_slots(uid):
			for gear_id in units.gear_ids_for_slot(slot):
				var affordable := true
				var gear: GearDef = null
				for candidate: GearDef in Inks.pack().gear:
					if candidate.id == gear_id:
						gear = candidate
						break
				if gear == null:
					continue
				for resource in gear.recipe:
					if host.engine.get_resource(resource) < int(gear.recipe[resource]):
						affordable = false
						break
				if affordable:
					host.submit(&"equip_gear", gear_id, uid)
					submitted = true
					break
	return submitted


## The active slot's card currently caught PAST its 90-degree crossing
## (the new face revealing), or null — the capture hook's mid-turn probe.
func _mid_flip_node() -> Control:
	var active := get_active_slot() as OrientationSlot
	if active == null:
		return null
	for child in active.get_spread().get_children():
		var card := child as Control
		if card != null and card.flip_crossed() and card.is_flipping():
			return card
	return null
