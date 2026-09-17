## CopyTable — the shipped event-copy templates (T-COPY-01, the voice bible's
## data half; the register + rules live in docs/voice-bible.md).
##
## One table per content pack: every repeating printed line the screens and
## the sim's chronicle render queries produce is a KEYED TEMPLATE with 1..4
## VARIANTS; the renderer (sim/copy_deck.gd, `CopyDeck`) picks a variant by a
## SEEDED ROTOR derived from data already in the view (event seq, run number,
## report ticks — never RNG: rendering stays pure and replay-deterministic).
## The table wins when a key is present; CopyDeck.DEFAULTS is the code-side
## floor so no-table environments (bare sim unit tests) still read in voice.
##
## Template grammar: `{token}` placeholders substituted from caller-supplied
## ACTUAL data (names, counts, hours — the reveal cannot lie about the hand).
## Tokens are validated at load against the per-key vocabulary below; a
## shipped pack cannot reference a token a surface never passes.
##
## LINE BUDGET (the T-UI-06/09 standard, enforced by test on EVERY variant at
## WORST-CASE parameters): the 476px blockquote label in the theme's real
## ChronicleLine face at 22px (measured conservatively at the 24 fallback),
## with >= 30px margin — see docs/voice-bible.md §4 for the worst-case table.
class_name CopyTable
extends Resource

## event-kind key -> ordered variants (variant 0 is the no-table fallback's
## twin and the rotor-0 line; authored .tres content carries the full sets).
@export var templates: Dictionary[StringName, PackedStringArray] = {}

## Hard cap on variants per key — variety without unbounded growth (the
## validator refuses more; renderers are O(1)).
const MAX_VARIANTS := 4

## Keys the sim repeats within a single run — variety is REQUIRED (>= 2
## variants; the validator enforces). Everything else may carry 1.
const ROTATING_KEYS: Array[StringName] = [
	&"suspicion_warn", &"suspicion_telegraph", &"suspicion_rose",
	&"crackdown_cancelled", &"crackdown_struck", &"crackdown_seized",
	&"crackdown_scattered", &"run_crushed",
	&"recruit_arrived", &"recruit_accepted", &"recruit_dismissed",
	&"training_started", &"training_complete", &"unit_promoted",
	&"gear_equipped", &"building_built", &"building_upgraded",
	&"building_milestone", &"run_started", &"run_restarted",
	&"catchup_headline", &"catchup_people_arrived",
	&"card_warn_line", &"card_telegraph_line",
	&"autosave_filed",
]

## The complete key vocabulary + each key's allowed `{tokens}` (empty list =
## literal lines only). Keys not listed here are refused at load — content
## cannot invent surfaces the code never reads (no orphan copy).
const KEY_TOKENS: Dictionary = {
	# --- the suspicion beats (SuspicionSystem.chronicle_line) ---
	&"suspicion_warn": [],
	&"suspicion_telegraph": [&"hours"],
	&"suspicion_rose": [&"points", &"source"],
	&"crackdown_cancelled": [],
	&"crackdown_struck": [&"count"],
	&"crackdown_seized": [&"count", &"resource"],
	&"crackdown_scattered": [&"count"],
	&"run_crushed": [],
	# --- the spread's rolling chronicle (SpreadPresenter) ---
	&"recruit_arrived": [&"name"],
	&"recruit_accepted": [&"name"],
	&"recruit_dismissed": [&"name"],
	&"training_started": [&"name", &"rank"],
	&"training_complete": [&"name", &"rank"],
	&"unit_promoted": [&"name", &"rank", &"count"],
	&"gear_equipped": [&"name", &"gear"],
	&"building_built": [&"building"],
	&"building_upgraded": [&"building", &"level"],
	&"building_milestone": [&"building"],
	&"resources_granted": [&"count", &"resource"],
	&"run_started": [&"first", &"regime"],
	&"run_restarted": [&"first", &"regime"],
	&"run_won": [&"points"],
	&"run_lost": [&"points"],
	&"run_aborted": [&"points"],
	&"assault_casualties": [&"count"],
	&"assault_lost": [&"regime"],
	&"assault_denied": [&"power"],
	&"catch_up_clock_rewound": [],
	&"clerk_denied": [&"reason"],
	&"command_rejected": [&"command"],
	&"gate_thinned": [&"count"],
	&"cards_kept_close": [],
	# --- the suspicion choice cards + crushed beat (SuspicionEvents) ---
	&"card_warn_line": [],
	&"card_telegraph_line": [],
	&"warn_context": [],
	&"telegraph_context": [],
	&"chip_dismiss": [&"count"],
	&"chip_keep": [],
	&"scatter_none": [],
	&"scatter_row": [&"who", &"count"],
	&"scatter_peasants": [&"count"],
	&"crush_regime": [&"regime"],
	&"crush_chronicle": [],
	&"crush_bank": [&"points"],
	# --- the leader intro / restart reveal (IntroPresenter) ---
	&"intro_first_line1": [],
	&"intro_first_marks": [&"tags"],
	&"intro_first_serve": [&"regime"],
	&"intro_win_swap": [&"old", &"new"],
	&"intro_win_kept": [&"regime"],
	&"intro_win_bank": [&"points", &"hands"],
	&"intro_win_context": [&"leader", &"hours", &"regime"],
	&"intro_resumed_hold": [&"first", &"hours"],
	&"intro_resumed_tail": [],
	&"intro_resumed_ended": [],
	&"intro_resumed_next": [],
	&"intro_loss_revenge": [&"regime", &"first"],
	&"intro_loss_remembers": [&"points"],
	&"intro_loss_serve": [&"regime"],
	# --- the while-you-were-away print (CatchUpPrint) ---
	&"catchup_headline": [&"duration"],
	&"catchup_capped": [&"hours"],
	&"catchup_stores_quiet": [],
	&"catchup_stores": [&"stores"],
	&"catchup_people_arrived": [&"count"],
	&"catchup_people_drills": [&"count"],
	&"catchup_people_promoted": [&"count", &"verb"],
	&"catchup_suspicion_rise": [&"before", &"after"],
	&"catchup_suspicion_ease": [&"before", &"after"],
	&"catchup_crackdown_strike": [],
	&"catchup_run_ended": [],
	&"catchup_rewound": [],
	&"catchup_quiet": [],
	&"catchup_away_empty": [],
	&"catchup_away_capped": [&"duration", &"hours"],
	&"catchup_away_plain": [&"duration"],
	# --- the assault vignette (AssaultPresenter) ---
	&"beat_advance": [],
	&"beat_skirmish": [],
	&"beat_skirmish_fallen": [&"count"],
	&"beat_gate": [],
	&"beat_gate_fallen": [&"count"],
	&"beat_throne": [],
	&"beat_rout": [],
	&"assault_win_block": [&"points", &"regime"],
	&"assault_win_bank": [&"points"],
	&"assault_loss_block": [&"regime", &"count"],
	&"assault_loss_note": [&"count"],
	# --- the chronicle screen's empty page (ChroniclePresenter) ---
	&"chronicle_empty_1": [],
	&"chronicle_empty_2": [],
	# --- the first session's printed cues (FirstSession, T-UI-10) ---
	&"first_gate": [&"name"],
	&"first_assign": [&"name"],
	&"first_build": [&"building"],
	&"first_trickle": [&"amount", &"resource"],
	&"first_train": [&"name"],
	# --- the finishing refinements (refinement #2) ---
	&"primer_lineform": [],
	&"autosave_filed": [&"hours"],
	&"daysheet_empty_1": [],
	&"daysheet_empty_2": [],
	# --- the finishing refinements (refinement #5, the press-room) ---
	&"prefs_kept": [],
	&"prefs_type_note": [],
	&"prefs_motion_note": [],
	&"prefs_motion_full": [],
	&"prefs_motion_steady": [],
}

## Automated register floor: whole WORDS that BREAK the voice (modern
## anachronisms, casual slang, meta/game-y words — the reasoning and the
## full hand-checked list live in docs/voice-bible.md §3). The validator
## scans every shipped variant; tests/unit/test_copy_voice.gd scans the
## code-side DEFAULTS + every identity pool with the same list. Matching
## is case-insensitive on WORD BOUNDARIES ("hey" never trips "they",
## "xp" never trips "expires") — entries must stay single words or
## exact short phrases.
const BANNED_FRAGMENTS: Array[String] = [
	"okay", "ok", "cool", "awesome", "yeet", "lol", "omg",
	"email", "internet", "phone", "wifi", "bluetooth", "battery",
	"caffeine", "coffee", "pizza", "burger", "taxi",
	"dude", "bro", "guys", "hey", "hello", "welcome",
	"congrats", "sorry", "please", "git", "commit",
	"push", "merge", "hack", "startup", "marketing",
	"level up", "xp", "loot", "quest", "boss", "respawn", "rekt",
	"pwned", "noob", "grind", "buff", "nerf", "speedrun", "tutorial",
]
