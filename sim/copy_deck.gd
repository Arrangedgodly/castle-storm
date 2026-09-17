## CopyDeck — the voice renderer (T-COPY-01, Professor X lane).
##
## THE ONE SEAM between content copy and every printing surface: a keyed
## template + a SEEDED ROTOR + caller-supplied ACTUAL data -> one line.
## The pack's CopyTable wins when it carries the key; CopyDeck.DEFAULTS is
## the code-side floor (one variant per key, the same voice) so no-table
## environments — bare sim unit tests, the examples pack — read identically.
## The register itself (pompous-officious regimes, earthy-underdog rebels,
## the ironic-clerk chronicle narrator), the rules and the banned list live
## in docs/voice-bible.md; this file is the mechanics.
##
## DETERMINISM CONTRACT: rotors are derived from data already in the view
## (event seq, run number, report ticks, the beat script's own hash) — never
## RNG, never wall time. Same state -> same lines (the view-hash oracles pin
## it); different events -> different variants (repeats vary). Rendering is
## pure: no engine access, no state, O(1) per line.
##
## LINE BUDGET (docs/voice-bible.md §4, the T-UI-06/09 font-metric standard):
## every variant of every template, substituted at WORST-CASE parameters,
## fits the 476px blockquote label in the theme's ChronicleLine 22px face
## (measured at the conservative 24 fallback) with >= 30px margin — pinned
## by tests/unit/test_copy_voice.gd against the live theme font.
class_name CopyDeck
extends RefCounted


## The code-side floor: key -> variant 0 (the no-table fallback and the
## rotor-0 line). Authored .tres content carries the full 1..4 variant sets;
## these singles keep every surface voiced when the table is absent.
const DEFAULTS: Dictionary = {
	# --- the suspicion beats (SuspicionSystem.chronicle_line) ---
	&"suspicion_warn": [
		"Somewhere in the capital, a clerk underlines your name. Twice.",
	],
	&"suspicion_telegraph": [
		"The Eye turns: riders count your barns. Crackdown in {hours}h.",
	],
	&"suspicion_rose": [
		"The Crown's clerks note +{points} from {source}.",
	],
	&"crackdown_cancelled": [
		"The riders turn back. Whoever paid them lost their nerve.",
	],
	&"crackdown_struck": [
		"CRACKDOWN #{count}: ledgers seized, gate kicked.",
	],
	&"crackdown_seized": [
		"…{count} {resource} marched off under royal seal.",
	],
	&"crackdown_scattered": [
		"…{count} recruits take up farming, urgently.",
	],
	&"run_crushed": [
		"The revolution is crushed. The chronicle remembers.",
	],
	# --- the spread's rolling chronicle (SpreadPresenter) ---
	&"recruit_arrived": [
		"{name} arrives at the gate, hat in hand.",
	],
	&"recruit_accepted": [
		"{name} joins the conspiracy.",
	],
	&"recruit_dismissed": [
		"{name} is sent home with kind words and no bread.",
	],
	&"training_started": [
		"{name} begins training as {rank}.",
	],
	&"training_complete": [
		"{name} finishes the {rank} drills.",
	],
	&"unit_promoted": [
		"{name} is struck off the rolls as {rank} — {count} now.",
	],
	&"gear_equipped": [
		"{name} takes up the {gear}.",
	],
	&"building_built": [
		"The {building} rises — level 1.",
	],
	&"building_upgraded": [
		"The {building} grows to level {level}.",
	],
	&"building_milestone": [
		"The {building} hits a milestone — the rates double.",
	],
	&"resources_granted": [
		"The stipend arrives: {count} {resource}.",
	],
	&"run_started": [
		"{first} raises the standard under {regime}.",
	],
	&"run_restarted": [
		"A new hand is dealt: {first} under {regime}.",
	],
	&"run_won": [
		"The castle falls. {points} legacy points banked.",
	],
	&"run_lost": [
		"The hand collapses. The bank keeps {points} points.",
	],
	&"run_aborted": [
		"The standard is folded up and buried. {points} banked.",
	],
	&"assault_casualties": [
		"{count} of the vanguard fall at the walls.",
	],
	&"assault_lost": [
		"The assault breaks against {regime}'s walls.",
	],
	&"assault_denied": [
		"Refused — the knight floor stands ({power} power).",
	],
	&"catch_up_clock_rewound": [
		"The castle clock was found wound backwards.",
	],
	&"clerk_denied": [
		"The clerk refuses the paperwork (reason {reason}).",
	],
	&"command_rejected": [
		"A command falls on deaf ears: {command}.",
	],
	&"gate_thinned": [
		"The gate thins: {count} sent home, thanked, unpaid.",
	],
	&"cards_kept_close": [
		"The conspirators keep the cards close, the lamps low.",
	],
	# --- the suspicion choice cards + crushed beat (SuspicionEvents) ---
	&"card_warn_line": [
		"Underlined. Twice.",
	],
	&"card_telegraph_line": [
		"Riders count barns.",
	],
	&"warn_context": [
		"Keep hands quiet.",
	],
	&"telegraph_context": [
		"Thin the crowd.",
	],
	&"chip_dismiss": [
		"Send the {count} loiterers home",
	],
	&"chip_keep": [
		"Keep the cards close",
	],
	&"scatter_none": [
		"The gate was already thin; the riders find only mud.",
	],
	&"scatter_row": [
		"Swept from the gate: {who} and {count} more board carts.",
	],
	&"scatter_peasants": [
		"…{count} loitering peasants follow them.",
	],
	&"crush_regime": [
		"{regime} closes its hand. The barns burn.",
	],
	&"crush_chronicle": [
		"The revolution is crushed. The chronicle remembers.",
	],
	&"crush_bank": [
		"The bank keeps what fire cannot: {points} points.",
	],
	# --- the leader intro / restart reveal (IntroPresenter) ---
	&"intro_first_line1": [
		"A blank chronicle, a warm press. One peasant steps up.",
	],
	&"intro_first_marks": [
		"Marked by the press: {tags}.",
	],
	&"intro_first_serve": [
		"You serve {regime}, as peasants do. For now.",
	],
	&"intro_win_swap": [
		"Your ink is the castle's ink now — {new} over {old}.",
	],
	&"intro_win_kept": [
		"The banner never left: {regime} keeps your ink.",
	],
	&"intro_win_bank": [
		"The bank remembers: {points} points across {hands}.",
	],
	&"intro_win_context": [
		"{leader} took the castle at {hours}h. You were not at the feast.",
	],
	&"intro_resumed_hold": [
		"{first} keeps the standard — hour {hours}.",
	],
	&"intro_resumed_tail": [
		"The spread waits beneath — the chronicle has the rest.",
	],
	&"intro_resumed_ended": [
		"The hand ended while you were away.",
	],
	&"intro_resumed_next": [
		"The next hand waits beneath.",
	],
	&"intro_loss_revenge": [
		"{regime} crushed {first}'s dream.",
	],
	&"intro_loss_remembers": [
		"The regime remembers; the bank too: {points} points safe.",
	],
	&"intro_loss_serve": [
		"You serve {regime} — the crest that did it. Be quieter.",
	],
	# --- the while-you-were-away print (CatchUpPrint) ---
	&"catchup_headline": [
		"While you were away, {duration} passed at the table.",
	],
	&"catchup_capped": [
		"The crown's clock stops at {hours} hours; the rest is lost.",
	],
	&"catchup_stores_quiet": [
		"The stores kept their count.",
	],
	&"catchup_stores": [
		"The stores: {stores}.",
	],
	&"catchup_people_arrived": [
		"{count} came to the gate",
	],
	&"catchup_people_drills": [
		"{count} finished drills",
	],
	&"catchup_people_promoted": [
		"{count} {verb} promoted",
	],
	&"catchup_suspicion_rise": [
		"The Crown's eye: {before} to {after} — it draws closer.",
	],
	&"catchup_suspicion_ease": [
		"The Crown's eye: {before} to {after} — it eased.",
	],
	&"catchup_crackdown_strike": [
		"A crackdown landed while you were away.",
	],
	&"catchup_run_ended": [
		"The hand itself ended while you were away.",
	],
	&"catchup_rewound": [
		"The clock was wound backwards. Nothing was lost.",
	],
	&"catchup_quiet": [
		"You were away a moment; the table kept still.",
	],
	&"catchup_away_empty": [
		"The table kept its counsel while you were gone.",
	],
	&"catchup_away_capped": [
		"You were away {duration} — the clock stops at {hours} hours.",
	],
	&"catchup_away_plain": [
		"You were away {duration}; the press kept printing.",
	],
	# --- the assault vignette (AssaultPresenter) ---
	&"beat_advance": [
		"The army advances through the mud to the walls.",
	],
	&"beat_skirmish": [
		"Skirmish beneath the walls; both ledgers bleed.",
	],
	&"beat_skirmish_fallen": [
		"Skirmish beneath the walls — {count} of ours fall.",
	],
	&"beat_gate": [
		"The gate is reached. The ram does its arithmetic.",
	],
	&"beat_gate_fallen": [
		"The gate holds; the ram insists — {count} more fall.",
	],
	&"beat_throne": [
		"The throne room is taken. The seal changes hands.",
	],
	&"beat_rout": [
		"The army breaks and runs for the tree line.",
	],
	&"assault_win_block": [
		"THE CASTLE FALLS. {regime} is undone.",
	],
	&"assault_win_bank": [
		"{points} legacy points pass to the next hand.",
	],
	&"assault_loss_block": [
		"THE ASSAULT IS BROKEN under {regime}.",
	],
	&"assault_loss_note": [
		"{count} of the vanguard lie where they fell. The plot survives.",
	],
	# --- the chronicle screen's empty page (ChroniclePresenter) ---
	&"chronicle_empty_1": [
		"the chronicle is blank — no dream has yet dared",
	],
	&"chronicle_empty_2": [
		"The first hand is still on the table.",
	],
	# --- the first session's printed cues (FirstSession, T-UI-10) ---
	&"first_gate": [
		"New paper at the gate — touch {name}'s card to answer.",
	],
	&"first_assign": [
		"Idle hands, honest work — touch {name}'s card: chores or drills.",
	],
	&"first_build": [
		"The stipend buys foundations — raise the {building}.",
	],
	&"first_trickle": [
		"The stores tally the first {resource}: +{amount}.",
	],
	&"first_train": [
		"{name} joins the drill line — the conspiracy counts soldiers.",
	],
	# --- the finishing refinements (refinement #2) ---
	&"primer_lineform": [
		"Dashed: work in hand. Solid: settled. Struck: lost.",
	],
	&"autosave_filed": [
		"The hour is filed at {hours}h — the hand is kept safe.",
		"The clerk blots the hour at {hours}h — nothing is lost.",
	],
	&"daysheet_empty_1": [
		"the day-sheet is blank — no print this hand yet",
	],
	&"daysheet_empty_2": [
		"The first print of the hand will head the page.",
	],
	# --- the finishing refinements (refinement #5) ---
	&"prefs_kept": [
		"The clerk keeps these across hands.",
	],
	&"prefs_type_note": [
		"The size of the hand, for tired eyes.",
	],
	&"prefs_motion_note": [
		"Steady: the papers move less, and nothing is lost.",
	],
	&"prefs_motion_full": [
		"Full turn",
	],
	&"prefs_motion_steady": [
		"Steady hand",
	],
	# --- the boot title card (the front door) ---
	&"title_flavor": [
		"One press, one conspiracy. The castle will not storm itself.",
		"The press is warm; the table is bare. Someone goes first.",
	],
	&"title_flavor_return": [
		"The table is cleared. The next hand waits.",
		"The press remembers every hand. Deal another.",
	],
	&"title_hold": [
		"{first} keeps the standard — hour {hours}.",
	],
	&"title_begin": [
		"Deal the first hand",
	],
	&"title_next": [
		"Deal the next hand",
	],
	&"title_continue": [
		"Continue the hand",
	],
	&"title_new_run": [
		"Deal a new hand",
	],
	&"title_new_run_armed": [
		"Bury the live hand",
	],
	&"title_new_run_caution": [
		"The hand ends where it stands; the bank keeps its points.",
	],
	# --- the legacy tree's voice (L1-B, the shipped tree content; the L1-C
	# tree UI's pending surface reads these) ---
	&"unlock_branch_old_guard": [
		"The Old Guard",
	],
	&"unlock_branch_workshop": [
		"The Workshop",
	],
	&"unlock_branch_yard": [
		"The Yard",
	],
	&"unlock_branch_survivors": [
		"The Survivors",
	],
	&"unlock_flavor_grandmas_recipes": [
		"Boots march on pickled eggs, banners or no.",
	],
	&"unlock_flavor_the_seed_drawer": [
		"Grain hidden from three crowns, now lent out.",
	],
	&"unlock_flavor_the_emergency_cheese": [
		"One wheel, shield-sized, older than the crest.",
	],
	&"unlock_flavor_unpaid_artisans": [
		"Dues are waived. Nails, regrettably, are not.",
	],
	&"unlock_flavor_cousin_ironmonger": [
		"The family price is a threat and a discount.",
	],
	&"unlock_flavor_the_masons_secret": [
		"Walls go up crooked, on purpose, for less.",
	],
	&"unlock_flavor_the_smiths_signature": [
		"Half the invoice. Twice the embossing.",
	],
	&"unlock_flavor_the_salvage_charter": [
		"Every burned barn is a discount, in writing.",
	],
	&"unlock_flavor_the_sergeants_primer": [
		"Shouting is free; brevity has to be drilled.",
	],
	&"unlock_flavor_the_drill_song_book": [
		"The verses keep the step; the step keeps men.",
	],
	&"unlock_flavor_the_sand_yard": [
		"Falls in sand teach what falls in mud cost.",
	],
	&"unlock_flavor_war_games_on_sundays": [
		"The crown rests on Sundays. The drills do not.",
	],
	&"unlock_flavor_quiet_boots": [
		"Soft soles, short memories, fewer questions.",
	],
	&"unlock_flavor_scarred_banners": [
		"Patched cloth; the hands under it are not.",
	],
	&"unlock_flavor_the_night_watch": [
		"They watch the roads till the roads forget.",
	],
	# --- the L2 escalation presence (L2-B): the odds castle-card line when a
	# captured garrison stands, the victory beat that captures, and the
	# chronicle entry's escalation line ---
	&"garrison_escalation": [
		"garrison {power} · {leader}'s veterans — cycle {cycle}",
	],
	&"escalation_captured": [
		"{leader}'s veterans take the wall — cycle {cycle}.",
		"The victors file in as the garrison — cycle {cycle}.",
	],
	&"chronicle_escalation": [
		"this army holds the castle — cycle {cycle} opens",
		"the castle garrisons this army — cycle {cycle}",
	],
	# --- the L2-C surface keys: the win-restart reveal's veterans line
	# (run-number-rotated like every reveal beat), the regime face card's
	# veterans role line (rotor 0 — one voice on the card), and the odds
	# table's tier-mix detail row (rotor 0 — a static composition). ---
	&"intro_win_veterans": [
		"{leader}'s veterans hold the walls — cycle {cycle}.",
		"Cycle {cycle}: the walls are {leader}'s veterans.",
	],
	&"intro_regime_veterans": [
		"the regime of {leader}'s veterans — cycle {cycle}",
	],
	&"garrison_detail": [
		"the wall: {mix} — cycle {cycle}",
	],
	# --- the legacy deck screen (L1-C, the tree UI) ---
	&"legacy_empty_1": [
		"the deck is still wrapped — no legacy earned yet",
	],
	&"legacy_empty_2": [
		"Finish a hand, any hand. The bank keeps the points.",
	],
	&"legacy_midrun_note": [
		"A hand is live — new cards join the next hand.",
	],
	&"legacy_purchase_line": [
		"The Survivors remember {node}.",
	],
	&"legacy_refusal_prereq": [
		"The deck has an order — {node} first.",
	],
	&"legacy_refusal_short": [
		"The bank is short — {short} more legacy.",
	],
	&"legacy_refusal_owned": [
		"Already pressed into the deck.",
	],
}


## The coverage map — every key -> the surface that consumes it. THE AUDIT
## TABLE: tests/unit/test_copy_voice.gd prints it as the copy coverage
## report and asserts it against DEFAULTS + the shipped table (no orphan
## copy, no unvoiced surface key).
const CONSUMERS: Dictionary = {
	&"suspicion_warn": "strip + choice card — SuspicionSystem.chronicle_line",
	&"suspicion_telegraph": "strip + choice card — SuspicionSystem.chronicle_line",
	&"suspicion_rose": "strip — SuspicionSystem.chronicle_line",
	&"crackdown_cancelled": "strip — SuspicionSystem.chronicle_line",
	&"crackdown_struck": "crackdown blockquote headline — SuspicionSystem.chronicle_line",
	&"crackdown_seized": "crackdown blockquote rows — SuspicionSystem.chronicle_line",
	&"crackdown_scattered": "crackdown blockquote rows — SuspicionSystem.chronicle_line",
	&"run_crushed": "strip (crush beat's own row) — SuspicionSystem.chronicle_line",
	&"recruit_arrived": "spread strip — SpreadPresenter.chronicle_line_for",
	&"recruit_accepted": "spread strip — SpreadPresenter.chronicle_line_for",
	&"recruit_dismissed": "spread strip — SpreadPresenter.chronicle_line_for",
	&"training_started": "spread strip — SpreadPresenter.chronicle_line_for",
	&"training_complete": "spread strip — SpreadPresenter.chronicle_line_for",
	&"unit_promoted": "spread strip — SpreadPresenter.chronicle_line_for",
	&"gear_equipped": "spread strip — SpreadPresenter.chronicle_line_for",
	&"building_built": "spread strip — SpreadPresenter.chronicle_line_for",
	&"building_upgraded": "spread strip — SpreadPresenter.chronicle_line_for",
	&"building_milestone": "spread strip — SpreadPresenter.chronicle_line_for",
	&"resources_granted": "spread strip — SpreadPresenter.chronicle_line_for",
	&"run_started": "spread strip — SpreadPresenter.chronicle_line_for",
	&"run_restarted": "spread strip — SpreadPresenter.chronicle_line_for",
	&"run_won": "spread strip — SpreadPresenter.chronicle_line_for",
	&"run_lost": "spread strip — SpreadPresenter.chronicle_line_for",
	&"run_aborted": "spread strip — SpreadPresenter.chronicle_line_for",
	&"assault_casualties": "spread strip — SpreadPresenter.chronicle_line_for",
	&"assault_lost": "spread strip — SpreadPresenter.chronicle_line_for",
	&"assault_denied": "spread strip — SpreadPresenter.chronicle_line_for",
	&"catch_up_clock_rewound": "spread strip — SpreadPresenter.chronicle_line_for",
	&"clerk_denied": "spread strip (all denial kinds) — SpreadPresenter.chronicle_line_for",
	&"command_rejected": "spread strip — SpreadPresenter.chronicle_line_for",
	&"gate_thinned": "strip row after the dismiss chip — SpreadScreen",
	&"cards_kept_close": "strip row after the keep chip — SpreadScreen",
	&"card_warn_line": "warn choice card beat phrase — SuspicionEvents",
	&"card_telegraph_line": "telegraph choice card beat phrase — SuspicionEvents",
	&"warn_context": "warn choice card context line — SuspicionEvents",
	&"telegraph_context": "telegraph choice card context line — SuspicionEvents",
	&"chip_dismiss": "the thin-the-gate chip label — SuspicionEvents",
	&"chip_keep": "the acknowledge chip label — SuspicionEvents",
	&"scatter_none": "zero-scatter blockquote row — SuspicionEvents.scatter_line",
	&"scatter_row": "scatter blockquote row (names) — SuspicionEvents.scatter_line",
	&"scatter_peasants": "scatter blockquote row (peasants) — SuspicionEvents.scatter_line",
	&"crush_regime": "crushed beat blockquote — SuspicionEvents.crush_lines",
	&"crush_chronicle": "crushed beat blockquote — SuspicionEvents.crush_lines",
	&"crush_bank": "crushed beat blockquote (the banked number) — SuspicionEvents.crush_lines",
	&"intro_first_line1": "first-run reveal — IntroPresenter.reveal_lines",
	&"intro_first_marks": "first-run reveal (tags) — IntroPresenter.reveal_lines",
	&"intro_first_serve": "first-run reveal (regime) — IntroPresenter.reveal_lines",
	&"intro_win_swap": "win-restart reveal (the ink swap) — IntroPresenter.reveal_lines",
	&"intro_win_kept": "win-restart reveal (redraw held) — IntroPresenter.reveal_lines",
	&"intro_win_bank": "win-restart reveal (bank) — IntroPresenter.reveal_lines",
	&"intro_win_context": "win-restart reveal (previous hand) — IntroPresenter.reveal_lines",
	&"intro_resumed_hold": "check-in reveal — IntroPresenter.reveal_lines",
	&"intro_resumed_tail": "check-in reveal — IntroPresenter.reveal_lines",
	&"intro_resumed_ended": "check-in reveal (dead hand) — IntroPresenter.reveal_lines",
	&"intro_resumed_next": "check-in reveal (dead hand) — IntroPresenter.reveal_lines",
	&"intro_loss_revenge": "loss-restart reveal (same crest) — IntroPresenter.reveal_lines",
	&"intro_loss_remembers": "loss-restart reveal (regime + bank) — IntroPresenter.reveal_lines",
	&"intro_loss_serve": "loss-restart reveal (serve line) — IntroPresenter.reveal_lines",
	&"catchup_headline": "catch-up strip row + blockquote lead — CatchUpPrint",
	&"catchup_capped": "catch-up blockquote (cap clause) — CatchUpPrint",
	&"catchup_stores_quiet": "catch-up blockquote — CatchUpPrint",
	&"catchup_stores": "catch-up blockquote (movement) — CatchUpPrint",
	&"catchup_people_arrived": "catch-up people summary — CatchUpPrint",
	&"catchup_people_drills": "catch-up people summary — CatchUpPrint",
	&"catchup_people_promoted": "catch-up people summary — CatchUpPrint",
	&"catchup_suspicion_rise": "catch-up suspicion row — CatchUpPrint",
	&"catchup_suspicion_ease": "catch-up suspicion row — CatchUpPrint",
	&"catchup_crackdown_strike": "catch-up STRIKE row — CatchUpPrint",
	&"catchup_run_ended": "catch-up STRIKE row — CatchUpPrint",
	&"catchup_rewound": "catch-up rewound row — CatchUpPrint",
	&"catchup_quiet": "catch-up zero-tick strip row — CatchUpPrint",
	&"catchup_away_empty": "check-in away line (no window) — CatchUpPrint.away_line",
	&"catchup_away_capped": "check-in away line — CatchUpPrint.away_line",
	&"catchup_away_plain": "check-in away line — CatchUpPrint.away_line",
	&"beat_advance": "assault vignette beat summary — AssaultPresenter",
	&"beat_skirmish": "assault vignette beat summary — AssaultPresenter",
	&"beat_skirmish_fallen": "assault vignette beat summary — AssaultPresenter",
	&"beat_gate": "assault vignette beat summary — AssaultPresenter",
	&"beat_gate_fallen": "assault vignette beat summary — AssaultPresenter",
	&"beat_throne": "assault vignette beat summary — AssaultPresenter",
	&"beat_rout": "assault vignette beat summary — AssaultPresenter",
	&"assault_win_block": "assault outcome block — AssaultPresenter.outcome_rows",
	&"assault_win_bank": "assault outcome block — AssaultPresenter.outcome_rows",
	&"assault_loss_block": "assault outcome block — AssaultPresenter.outcome_rows",
	&"assault_loss_note": "assault outcome block — AssaultPresenter.outcome_rows",
	&"chronicle_empty_1": "chronicle empty page — ChroniclePresenter",
	&"chronicle_empty_2": "chronicle empty page — ChroniclePresenter",
	&"first_gate": "first-session strip hint (the gate) — FirstSession",
	&"first_assign": "first-session strip hint (the role fan) — FirstSession",
	&"first_build": "first-session strip hint (the build order) — FirstSession",
	&"first_trickle": "first-session strip line (the first produce) — FirstSession",
	&"first_train": "first-session strip line (the drill line) — FirstSession",
	&"primer_lineform": "line-form primer strip row (first dashed edge of a session) — SpreadScreen",
	&"autosave_filed": "autosave strip row (the background flush) — SpreadScreen",
	&"daysheet_empty_1": "day-sheet empty page — DaySheetScreen.view_for",
	&"daysheet_empty_2": "day-sheet empty page — DaySheetScreen.view_for",
	&"prefs_kept": "press-room kept line (persistence) — PressRoomScreen.view_for",
	&"prefs_type_note": "press-room hand-row note — PressRoomScreen.view_for",
	&"prefs_motion_note": "press-room presswork-row note — PressRoomScreen.view_for",
	&"prefs_motion_full": "press-room presswork step (full motion) — PressRoomScreen",
	&"prefs_motion_steady": "press-room presswork step (reduced motion) — PressRoomScreen",
	&"title_flavor": "title card flavor line (fresh install) — MainShell title card",
	&"title_flavor_return": "title card flavor line (a hand ended last session) — MainShell title card",
	&"title_hold": "title card live-hand line — MainShell title card",
	&"title_begin": "title card primary chip (fresh install) — MainShell title card",
	&"title_next": "title card primary chip (ended meta) — MainShell title card",
	&"title_continue": "title card primary chip (live run) — MainShell title card",
	&"title_new_run": "title card secondary chip (live run) — MainShell title card",
	&"title_new_run_armed": "title card secondary chip armed (the two-step confirm) — MainShell title card",
	&"title_new_run_caution": "title card caution line (the two-step confirm) — MainShell title card",
	&"garrison_escalation": "assault odds castle card (a captured garrison stands) — AssaultPresenter.garrison_line",
	&"escalation_captured": "strip victory beat (the capture) — SpreadPresenter.chronicle_line_for",
	&"chronicle_escalation": "chronicle entry's escalation line — ChroniclePresenter.entry_view",
	&"intro_win_veterans": "win-restart reveal's veterans line (a garrison stands) — IntroPresenter.reveal_lines",
	&"intro_regime_veterans": "regime face card's veterans role line (a garrison stands) — IntroPresenter.reveal_view",
	&"garrison_detail": "odds table's tier-mix detail row (a captured garrison stands) — AssaultPresenter.garrison_detail_line",
	&"unlock_branch_old_guard": "legacy tree branch plate — the L1-C tree UI (content ships in L1-B)",
	&"unlock_branch_workshop": "legacy tree branch plate — the L1-C tree UI (content ships in L1-B)",
	&"unlock_branch_yard": "legacy tree branch plate — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_grandmas_recipes": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_the_seed_drawer": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_the_emergency_cheese": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_unpaid_artisans": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_cousin_ironmonger": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_the_masons_secret": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_the_smiths_signature": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_the_salvage_charter": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_the_sergeants_primer": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_the_drill_song_book": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_the_sand_yard": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_flavor_war_games_on_sundays": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B)",
	&"unlock_branch_survivors": "legacy tree branch plate — the L1-C tree UI (content ships in L1-B2)",
	&"unlock_flavor_quiet_boots": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B2)",
	&"unlock_flavor_scarred_banners": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B2)",
	&"unlock_flavor_the_night_watch": "legacy tree node card flavor row — the L1-C tree UI (content ships in L1-B2)",
	&"legacy_empty_1": "legacy deck empty page (first run unfinished) — LegacyScreen.view",
	&"legacy_empty_2": "legacy deck empty page (second line) — LegacyScreen.view",
	&"legacy_midrun_note": "legacy deck mid-run honesty line (mount discipline) — LegacyScreen.view",
	&"legacy_purchase_line": "legacy deck purchase confirmation — LegacyScreen.purchase",
	&"legacy_refusal_prereq": "legacy deck refusal (prerequisite missing) — LegacyScreen.purchase",
	&"legacy_refusal_short": "legacy deck refusal (bank shortfall) — LegacyScreen.purchase",
	&"legacy_refusal_owned": "legacy deck refusal (already owned) — LegacyScreen.purchase",
}


## The variant pool for a key: the table's when it carries the key, else the
## DEFAULTS floor. Empty when the key is unknown to both (callers decide how
## to degrade — the known-key surfaces never hit this in shipped content).
static func variants(table: CopyTable, key: StringName) -> PackedStringArray:
	if table != null and table.templates.has(key):
		return table.templates[key]
	return PackedStringArray(DEFAULTS.get(key, []))


## Render one line: variant = pool[rotor mod size], `{tokens}` substituted
## from `params`. Missing parameter -> fall back to variant 0 of the SAME
## pool (both sources share the token contract); still missing -> the raw
## variant ships (dev-visible, and the validator keeps content from ever
## referencing tokens a surface does not pass).
static func line(table: CopyTable, key: StringName, rotor: int,
		params: Dictionary = {}) -> String:
	var pool := variants(table, key)
	if pool.is_empty():
		return ""
	var text := pool[posmod(rotor, pool.size())]
	if not _renderable(text, params):
		text = pool[0]
	return _substitute(text, params)


## The coverage report (tests print it into the run log; the doc mirrors it):
## every key, its shipped + fallback variant counts, and its consumer.
static func coverage_report(table: CopyTable) -> Array[String]:
	var lines: Array[String] = []
	var keys: Array = DEFAULTS.keys()
	keys.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	lines.append("COPY COVERAGE (T-COPY-01) — %d keys, table %s" % [
		keys.size(), "present" if table != null else "ABSENT (defaults)"])
	for key in keys:
		var shipped := 0
		if table != null and table.templates.has(key):
			shipped = table.templates[key].size()
		lines.append("  %s — %d shipped / %d fallback — %s" % [
			String(key), shipped, variants(table, key).size(),
			String(CONSUMERS.get(key, "NO CONSUMER ON RECORD"))])
	return lines


static func _renderable(text: String, params: Dictionary) -> bool:
	var open := text.find("{")
	while open >= 0:
		var close := text.find("}", open + 1)
		if close < 0:
			return false
		if not params.has(text.substr(open + 1, close - open - 1)):
			return false
		open = text.find("{", close + 1)
	return true


static func _substitute(text: String, params: Dictionary) -> String:
	var out := text
	for token in params.keys():
		out = out.replace("{%s}" % String(token), str(params[token]))
	return out
