## The Conspiracy's Spread — the palette + grammar vocabulary (T-UI-01).
##
## Single source of truth for the theme grammar's TOKENS: core inks, regime
## inks (data-driven from content/mvp/regimes — a regime swap recolors the
## table by data, never by code), the phase-deepening ground tones, the
## line-form state mapping (the design brief's first kept raise: state is
## carried by line form — solid ready / dashed in progress / struck lost —
## never by hue, colorblind-safe by construction), the chronicle line
## classes (the second raise: states print themselves), and the seeded
## misprint character (deliberate registration error of a cheap press).
##
## `ui/theme/spread_theme.tres` mirrors the core tokens as theme color /
## constant palette entries (tested for equality against this file —
## drift fails in tests/unit/test_theme_grammar.gd). Components pull
## regime-dependent values through the static lookups below so content
## edits flow into the surface without touching UI code.
##
## Palette strategy (design brief §3, "Committed"): cheap-paper ground
## tones, near-black ink, revolution red carries 30-60% of accents, one
## regime secondary per flavor. Ink-on-paper light: cards are bright
## paper carrying ink; the table ground is the same world under a dim
## barn-loft candle, deepening phase by phase.
##
## Font pairing rationale (brief §7's open "exact display face" decision,
## resolved here): display = IM Fell English SC (Igino Marini, OFL — a
## digitization of the c.1667 Fell types that keeps their rough,
## unevenly-inked impressions, i.e. the "deliberate misprint" baked into
## the letterforms; small-caps titling reads as tarot caption plates);
## workhorse = Alegreya Sans (Juan Pablo del Peral, OFL — humanist sans
## from a type family designed for literature, calligraphic skeleton
## keeps the print voice at phone-scale sizes, true weights + italic for
## chronicle lines). Neither is the AI-default sans the brief's
## calibration warning exists to avoid; both are open-licensed through
## the vendor pipeline (assets/vendor/fonts/, OFL.txt beside each family).
class_name Inks
extends RefCounted

## Card edge line forms — the state carrier (never hue). Mirrors the
## sim's unit vocabulary (docs/sim-engine.md §11/§14): ready bodies print
## solid, in-flight bodies print dashed, lost bodies print struck.
enum EdgeForm {
	SOLID,   ## ready / committed
	DASHED,  ## in progress / held
	STRUCK,  ## lost / scattered / crushed
}

## Run phases — the phase-deepening ground (brief's 4th kept raise).
enum Phase {
	RECRUITING,   ## the spread opens: candle lit, papers out
	TRAINING,     ## the conspiracy thickens: ground deepens
	READY,        ## ready-to-storm: deepest hour before the assault
	AFTERMATH,    ## post-resolution beat: cold washed ash light
}

## The three idle resources (PRODUCT.md MVP: food / timber / iron). Each
## gets a pip whose CONTAINER SHAPE + inner glyph + optional label differ
## — color is redundant tertiary encoding only, never the differentiator
## (Daredevil parity: icon + shape + text).
enum ResourceKind { FOOD, TIMBER, IRON }

## Chronicle line classes — how events print themselves onto the table
## (brief's 2nd raise: chronicle lines, never popup chrome). The class
## chooses the leading rule's line form, reusing the same grammar as
## card edges.
enum LineClass {
	PLAIN,    ## ordinary event — solid rule
	WARN,     ## suspicion pressure — dashed rule
	STRIKE,   ## crackdown / seizure / crush — struck rule
	VICTORY,  ## run won — double rule (the printed flourish)
}

# --- core tokens (mirrored into spread_theme.tres, equality-tested) ------------

## Cheap paper — the card stock (bright; the world's light source).
const PAPER := Color(0.905, 0.852, 0.742)
## Recessed paper — plates and strips on a card, one shade down.
const PAPER_DIM := Color(0.836, 0.773, 0.648)
## Near-black ink, warmed to the paper's hue. Never pure gray.
const INK := Color(0.118, 0.098, 0.078)
## Ink running low — secondary text, tinted from the ink hue, never gray.
const INK_SOFT := Color(0.330, 0.273, 0.212)
## Revolution red — the accent ink ON PAPER (passes 4.5:1 on PAPER).
const RED := Color(0.565, 0.118, 0.118)
## Revolution red lifted for the dark table ground — marks and rules only
## (passes 3:1 on every phase-0..2 ground; body text stays PAPER/INK).
const RED_CANDLE := Color(0.890, 0.470, 0.360)
## Revolution red pressed deep for LIGHT grounds (aftermath) — the same
## accent ink chosen for a pale stock (passes 3:1 on the aftermath wash).
const RED_DEEP := Color(0.420, 0.080, 0.080)
## Cold ash — the aftermath wash's target tone.
const ASH := Color(0.620, 0.660, 0.720)
## The neutral table ground (regime-less default; regimes tint over it).
const NEUTRAL_GROUND := Color(0.235, 0.204, 0.167)

# --- grammar constants (mirrored into spread_theme.tres, equality-tested) ------

## Minimum touch target in design units (720 square base, R3: short edge
## maps to 720 on every target — PRODUCT.md accessibility: >= 48dp).
const TOUCH_GRIP_MIN := 48
## Card border weight (print-block frame).
const EDGE_WIDTH := 4.0
## Dash length for the in-progress edge form.
const EDGE_DASH := 10.0
## Gap between dashes.
const EDGE_DASH_GAP := 7.0
## Strike line weight (the struck form's diagonal).
const STRIKE_WIDTH := 5.0
## Frame inset from the control rect (misprint margin).
const FRAME_INSET := 8.0
## Corner chamfer (cut paper, not rounded luxe).
const FRAME_CHAMFER := 9.0
## Misprint bounds: max rotation (degrees) and offset (design units).
const MISPRINT_MAX_DEG := 0.9
const MISPRINT_MAX_OFFSET := 2.0

## Phase deepening: how far phases 0->2 pull the ground toward ink-dark
## (monotone; tested). Aftermath washes cold + light instead — far enough
## that near-black ink text passes 4.5:1 on it (the print rule's light
## branch; the dark phases never enter that luminance band).
const PHASE_DEPTHS: Array[float] = [0.0, 0.28, 0.52]
## How far aftermath pulls toward ASH (cool, light — the morning after).
const AFTERMATH_WASH := 0.75

## Ground luminance threshold for the print rule "ink on light stock,
## paper-ink on dark stock" (chronicle text picks its ink by ground).
## Sits in the empty band between the darkest aftermath (~0.25) and the
## lightest dark-phase ground (~0.06) — both channels pass 4.5:1 on their
## own side (tested), neither would in the middle.
const GROUND_LIGHT_LUMA := 0.19

## Core color palette entries mirrored into the theme (name -> color).
const CORE_TOKENS: Dictionary = {
	"paper": PAPER,
	"paper_dim": PAPER_DIM,
	"ink": INK,
	"ink_soft": INK_SOFT,
	"red": RED,
	"red_candle": RED_CANDLE,
	"red_deep": RED_DEEP,
	"ash": ASH,
	"ground_neutral": NEUTRAL_GROUND,
}

## Grammar constants mirrored into the theme (name -> int value; theme
## constants are integers, so the float misprint bounds below stay
## code-side only — components read them from this class directly).
const GRAMMAR_TOKENS: Dictionary = {
	"touch_grip_min": TOUCH_GRIP_MIN,
	"edge_width": int(EDGE_WIDTH),
	"edge_dash": int(EDGE_DASH),
	"edge_dash_gap": int(EDGE_DASH_GAP),
	"strike_width": int(STRIKE_WIDTH),
	"frame_inset": int(FRAME_INSET),
	"frame_chamfer": int(FRAME_CHAMFER),
}

## The MVP content pack (regime inks are content, not UI constants).
const PACK_PATH := "res://content/mvp/pack.tres"

static var _pack_cache: ContentPack


static func pack() -> ContentPack:
	## The MVP content pack, loaded once per process through the loud gate.
	if _pack_cache == null:
		_pack_cache = ContentValidator.load_pack(PACK_PATH)
	return _pack_cache


static func regime_ids() -> Array[StringName]:
	## Regime flavor ids in pack order (empty when content is missing —
	## callers fall back to the neutral ground).
	var ids: Array[StringName] = []
	var p := pack()
	if p == null:
		return ids
	for regime: RegimeDef in p.regimes:
		ids.append(regime.id)
	return ids


static func regime_name(id: StringName) -> String:
	## Display name for a regime flavor ("" when unknown).
	var p := pack()
	if p == null:
		return ""
	for regime: RegimeDef in p.regimes:
		if regime.id == id:
			return regime.display_name
	return ""


## THE ARTICLE RULE (the closing critique's P2, fixed at the root): regime
## display names CARRY their own article — every shipped flavor begins with
## "The " ("The Paper Crown"). A template that wants the regime mid-sentence
## composes through THIS seam, never by prepending a literal "the" (that is
## how "Against the The Paper Crown" happened). Empty falls back to "the
## Crown"; a name already carrying "The" ships as-is; anything else takes a
## lowercase article.
static func regime_with_article(regime_name: String) -> String:
	if regime_name.is_empty():
		return "the Crown"
	if regime_name.begins_with("The "):
		return regime_name
	return "the " + regime_name


static func regime_ground(id: StringName) -> Color:
	## First ink: the table ground tone this regime tints (RegimeDef.ink_ground).
	var p := pack()
	if p != null:
		for regime: RegimeDef in p.regimes:
			if regime.id == id:
				return regime.ink_ground
	return NEUTRAL_GROUND


static func regime_secondary(id: StringName) -> Color:
	## Second ink: the regime secondary accent (RegimeDef.ink_secondary).
	var p := pack()
	if p != null:
		for regime: RegimeDef in p.regimes:
			if regime.id == id:
				return regime.ink_secondary
	return INK


static func ground_for(id: StringName, phase: Phase) -> Color:
	## The table ground for a regime at a phase — the phase-deepening
	## raise: recruiting -> training -> ready-to-storm pulls the ground
	## monotonically toward ink-dark (ambient progress before any number
	## is read); aftermath washes cold and light (the morning after).
	var base := regime_ground(id) if id != &"" else NEUTRAL_GROUND
	if phase == Phase.AFTERMATH:
		return base.lerp(ASH, AFTERMATH_WASH)
	var depth := 0.0
	if phase >= 0 and phase < PHASE_DEPTHS.size():
		depth = PHASE_DEPTHS[phase]
	return base.lerp(INK, depth)


static func ground_is_light(ground: Color) -> bool:
	## Print rule: which ink prints on this ground. Dark grounds take
	## paper-bright text; light grounds (aftermath) take near-black ink —
	## exactly how a press chooses ink per stock.
	return relative_luminance(ground) > GROUND_LIGHT_LUMA


static func ground_text_ink(ground: Color) -> Color:
	return PAPER if not ground_is_light(ground) else INK


static func ground_accent_ink(ground: Color) -> Color:
	## The red accent adapted to the ground beneath it (candle-lift red on
	## dark grounds, deep red on the pale aftermath stock).
	return RED_CANDLE if not ground_is_light(ground) else RED_DEEP


# --- state -> line form (THE raise: form, not hue) -------------------------------


## Sim/read-API state vocabulary -> edge line form. (THE raise: form, not hue.)
const EDGE_FORM_STATES: Dictionary = {
	&"ready": EdgeForm.SOLID, &"idle": EdgeForm.SOLID, &"working": EdgeForm.SOLID,
	&"assigned": EdgeForm.SOLID, &"army": EdgeForm.SOLID, &"promoted": EdgeForm.SOLID,
	&"in_progress": EdgeForm.DASHED, &"training": EdgeForm.DASHED, &"awaiting_gear": EdgeForm.DASHED,
	&"held": EdgeForm.DASHED, &"queued": EdgeForm.DASHED,
	&"lost": EdgeForm.STRUCK, &"scattered": EdgeForm.STRUCK, &"casualty": EdgeForm.STRUCK,
	&"crushed": EdgeForm.STRUCK, &"seized": EdgeForm.STRUCK,
}

## Sim event vocabulary (docs/sim-engine.md §11/§14/§15/§16) -> chronicle class.
## T-UI-03 extension: the real recorded kinds the Spread prints (the
## T-UI-01 map was authored against the design's event names — the
## historical keys stay, the sim's actual kind ids join them additively).
const EVENT_LINE_CLASSES: Dictionary = {
	&"suspicion_warn": LineClass.WARN, &"suspicion_telegraph": LineClass.WARN,
	&"crackdown_struck": LineClass.STRIKE, &"crackdown_seized": LineClass.STRIKE,
	&"crackdown_scattered": LineClass.STRIKE, &"run_crushed": LineClass.STRIKE,
	&"run_won": LineClass.VICTORY, &"assault_won": LineClass.VICTORY,
	&"suspicion_rose": LineClass.PLAIN, &"crackdown_cancelled": LineClass.PLAIN,
	&"catch_up_applied": LineClass.PLAIN, &"catch_up_clock_rewound": LineClass.PLAIN,
	&"assault_beat": LineClass.PLAIN, &"assault_denied": LineClass.PLAIN,
	&"training_started": LineClass.PLAIN, &"training_complete": LineClass.PLAIN,
	&"unit_promoted": LineClass.PLAIN, &"building_built": LineClass.PLAIN,
	&"building_upgraded": LineClass.PLAIN, &"gate_offer": LineClass.PLAIN,
	&"grant_paid": LineClass.PLAIN,
	# T-UI-03: the sim's actual kind ids (tests/acceptance event records).
	&"recruit_arrived": LineClass.PLAIN, &"recruit_accepted": LineClass.PLAIN,
	&"recruit_dismissed": LineClass.PLAIN, &"gear_equipped": LineClass.PLAIN,
	&"building_milestone": LineClass.PLAIN, &"resources_granted": LineClass.PLAIN,
	&"run_started": LineClass.PLAIN, &"run_restarted": LineClass.PLAIN,
	&"run_lost": LineClass.STRIKE, &"run_aborted": LineClass.STRIKE,
	&"run_denied": LineClass.PLAIN, &"lifecycle_denied": LineClass.PLAIN,
	&"upgrade_denied": LineClass.PLAIN, &"assault_lost": LineClass.STRIKE,
	&"assault_casualties": LineClass.STRIKE,
}


static func edge_form_for_state(state: StringName) -> EdgeForm:
	## Maps sim/read-API state vocabulary to the edge line form.
	## Unknown states fail loudly (push_error) and print solid — a wrong
	## guess must be visible in review, never a silent crash of the draw.
	if EDGE_FORM_STATES.has(state):
		return EDGE_FORM_STATES[state]
	push_error("Inks.edge_form_for_state: unknown state '%s' — printing SOLID; extend the vocabulary map" % state)
	return EdgeForm.SOLID


static func line_class_for_event(kind: StringName) -> LineClass:
	## Chronicle class per sim event kind. Unknown kinds print PLAIN (the
	## chronicle's default paper trail), loudly.
	if EVENT_LINE_CLASSES.has(kind):
		return EVENT_LINE_CLASSES[kind]
	push_error("Inks.line_class_for_event: unknown event kind '%s' — printing PLAIN; extend the vocabulary map" % kind)
	return LineClass.PLAIN


# --- resource pips (colorblind-safe: shape + glyph + label, color redundant) -----


static func pip_shape(kind: ResourceKind) -> int:
	## Container shape id per resource (distinct by construction — tested).
	return kind  # enum ids ARE the shape contract; see pip_glyph.gd


static func pip_label(kind: ResourceKind) -> String:
	match kind:
		ResourceKind.FOOD:
			return "FOOD"
		ResourceKind.TIMBER:
			return "TIMBER"
		ResourceKind.IRON:
			return "IRON"
	return "?"


static func abbreviate_amount(value: int) -> String:
	## Idle-scale numeral notation (PRODUCT.md: 1 -> 10^5+ with abbreviated
	## numerals): 999 -> "999", 1234 -> "1.2K", 1250000 -> "1.3M", 15400 ->
	## "15K" (one decimal under 10, integers above — the rail stays narrow).
	if value < 0:
		push_error("Inks.abbreviate_amount: negative amount %d" % value)
		return "0"
	if value < 1000:
		return str(value)
	var units := ["K", "M", "B", "T"]
	var amount := float(value)
	var ui := -1
	while amount >= 1000.0 and ui < units.size() - 1:
		amount /= 1000.0
		ui += 1
	if amount < 10.0:
		## Round half-away-from-zero at the decimal, then trim trailing
		## zeros by construction (1000 -> "1K", not "1.0K").
		var tenths := int(round(amount * 10.0))
		if tenths % 10 == 0:
			return str(tenths / 10) + units[ui]
		return "%d.%d%s" % [tenths / 10, tenths % 10, units[ui]]
	return str(int(round(amount))) + units[ui]


# --- misprint character (seeded, deterministic) ----------------------------------


static func misprint_params(seed: int) -> Dictionary:
	## Deliberate registration error of a cheap press: a small rotation and
	## offset, deterministic per seed (FNV-1a hash — stable across
	## processes and platforms, unlike nothing-in-particular). Returns
	## {"rotation_deg": float, "offset": Vector2}.
	var h := _fnv1a(seed & 0xFFFFFFFF)
	var rot := ((h % 2001) / 2000.0 - 0.5) * 2.0 * MISPRINT_MAX_DEG
	var ox := (((h >> 11) % 2001) / 2000.0 - 0.5) * 2.0 * MISPRINT_MAX_OFFSET
	var oy := (((h >> 23) % 2001) / 2000.0 - 0.5) * 2.0 * MISPRINT_MAX_OFFSET
	return {"rotation_deg": rot, "offset": Vector2(ox, oy)}


static func _fnv1a(seed: int) -> int:
	var hash := 2166136261
	var s := seed
	for i in 4:
		hash = hash ^ (s & 0xFF)
		hash = (hash * 16777619) & 0xFFFFFFFF
		s = s >> 8
	return hash


# --- contrast (WCAG relative luminance; the Daredevil floor) ---------------------


static func relative_luminance(c: Color) -> float:
	## WCAG 2.x relative luminance (sRGB linearization).
	return 0.2126 * _lin_channel(c.r) + 0.7152 * _lin_channel(c.g) + 0.0722 * _lin_channel(c.b)


static func _lin_channel(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


static func contrast_ratio(a: Color, b: Color) -> float:
	## WCAG contrast ratio between two inks (>= 4.5 body, >= 3 large/accent).
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	var lighter := maxf(la, lb)
	var darker := minf(la, lb)
	return (lighter + 0.05) / (darker + 0.05)
