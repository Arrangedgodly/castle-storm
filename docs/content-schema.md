# Content Schema — Castle Storm (T-DATA-01)

Declarative content format for units, buildings, gear, regimes, identity
pools, art references and economy tunables. This is town-hall open
question #4's answer: **the schema everything else builds on.**

- Schema classes: `content/schema/*.gd` (Godot Custom Resources)
- Validator: `content/content_validator.gd` (`ContentValidator`)
- Worked examples (seeds for T-DATA-02): `content/examples/`
- Proof tests: `tests/unit/test_content_schema.gd`
- Research inputs: R4 tunables (`docs/ultron/research/r4-idle-balance-references.md`),
  R6 art sourcing (`docs/ultron/research/r6-asset-sourcing.md`)

## 1. Format choice: Custom Resources, not JSON

Content is **Godot-native Custom Resources**: a `.gd` script with
`class_name X extends Resource` + `@export` typed fields, authored and
edited as text `.tres` files (in the Godot inspector or by hand).

Why this beats JSON here:

| Concern | Custom Resources (.tres) | JSON |
|---|---|---|
| Type safety | Engine enforces field types at load; a `timber: "lots"` in a cost dict fails at load, not at first tick | Needs a hand-written parse-and-cast layer that re-implements the schema |
| Editor integration | Inspector editing, dropdowns for nested resources, resource pickers — T-DATA-02 authors content without touching raw text | None; content authoring is raw text |
| Validation split | Only *semantic* constraints need code; structural ones are free | Everything needs code |
| Test harness | Same class constructs test fixtures in code (`UnitDef.new()`) — tests and content share one source of truth | Tests would drift from the file format |
| Determinism | `StringName` ids, `int` resource amounts (per `docs/gdscript-conventions.md`); no float parsing ambiguity | Same, but only by discipline |
| Version control | `.tres` is human-readable text, diff-friendly | Same |

JSON's advantages (external toolchains, hot-reload, non-Godot pipelines)
do not apply at MVP: the content set is bounded (town-hall), authored
in-repo, and consumed only by the game and the headless simulator. If a
balance-sweep tool ever wants spreadsheets, a thin exporter can emit
`.tres`/CSV from the same classes — the schema does not change. This
choice also satisfies PRODUCT.md principle 4 ("data over code"):
everything declarative is data; the only code is the loud gate (§5).

**Directory ownership** (per `docs/gdscript-conventions.md`):
`content/schema/` holds the declarative classes; `content/` contains no
logic beyond `content_validator.gd` (load-time validation).

## 2. ContentPack — the root manifest

Class: `content/schema/content_pack.gd`. A run loads exactly one pack
through `ContentValidator.load_pack(path)`.

| Field | Type | Constraint | Meaning | Consumed by |
|---|---|---|---|---|
| `format_version` | `int` | must be in the build's supported set (§6) | Schema version; recorded in save headers | T-DATA-03, T-ARCH-03 |
| `pack_id` | `StringName` | non-empty | Stable pack identity for saves | T-DATA-03 |
| `display_name` | `String` | non-empty | Human-readable pack name | editor/chronicle |
| `resources` | `Array[StringName]` | ≥1, unique, non-empty | Resource vocabulary (MVP: food, timber, iron); every cost/recipe/production target must reference one | T-SIM-02, T-SIM-05 |
| `gear_slots` | `Array[StringName]` | ≥1, unique | Gear slot vocabulary (MVP: weapon, armor — 2 slots × 3 tiers) | T-SIM-03 |
| `units` | `Array[UnitDef]` | ≥1, unique ids | Unit cards | T-SIM-03/04/06 |
| `buildings` | `Array[BuildingDef]` | ≥1, unique ids | Building cards | T-SIM-02 |
| `gear` | `Array[GearDef]` | unique ids; every unit-required slot covered | Smithy items | T-SIM-03/06 |
| `regimes` | `Array[RegimeDef]` | ≥1, unique ids (MVP breadth of 4 is T-DATA-02's acceptance) | Regime flavors | T-SIM-04/06, T-UI-01/05 |
| `identity` | `IdentityPools` | set, valid | Leader/recruit name pools | T-SIM-04, T-COPY-01 |
| `tunables` | `EconomyTunables` | set, valid | R4 vocabulary as data (§4) | T-SIM-05/07/08 |
| `art` | `ArtManifest` | set, valid; covers every referenced key | Asset keys → vendored sources + licenses (§3) | T-ARCH-04, T-UI-01 |
| `starting_grants` | `Dictionary[StringName, int]` | keys ⊆ `resources`; values > 0 (additive, T-DATA-02) | Run-start stipend paid by the `grant_resources` command (M1 finding F1); empty = no stipend, the verb is refused | T-DATA-02, T-SIM-04, T-UI-05 |
| `copy` | `CopyTable` | set, valid (additive-optional, T-COPY-01) | Event-copy template table — keyed variants for every repeating printed line, read through `CopyDeck` with seeded rotation (docs/voice-bible.md); absent = the code-side floor | T-COPY-01, all printing surfaces |
| `unlock_tree` | `UnlockTreeDef` | valid when attached (additive-optional, L1) | The legacy unlock tree — purchasable meta-progression nodes fed by the banked legacy points of every run (R5: always-on, Rogue Legacy manor pattern). Absent/null = the pack ships no tree and the whole L1 layer runs empty (the pre-L1-B MVP shape) — no format bump | L1 LegacySystem/Modifiers, the tree UI |

Cross-refs between defs use **`StringName` ids, never file paths or
ExtResource chains**: `peasant.promotion_paths = [&"worker", &"militia"]`,
not resource references. One mechanism everywhere — saves (T-DATA-03)
and the L2 snapshot (§7) reference content exactly the same way, and
files can be renamed/reorganized without touching content or saves.

## 3. Art references (R6)

R6's rule: *content never hardcodes file paths*. Every visual-facing def
carries an **asset key**:

- `UnitDef.face_id`, `BuildingDef.icon_id`, `GearDef.icon_id`,
  `RegimeDef.crest_id` — `StringName` keys, all validated non-empty and
  resolved against the pack's `ArtManifest`.
- `ArtAssetDef` (`content/schema/art_asset_def.gd`) is the **only** place
  a vendor path appears: `id`, `source_path`
  (`assets/vendor/<pack>/...`), `license` (`CC0`, `CC-BY-3.0`,
  `commercial`, ...), `attribution`, `pending`, `atlas_region`. **CC-BY-family licenses
  require a non-empty attribution** — the validator enforces R6's license
  hygiene (game-icons.net credits).
- **Path existence is validated** (T-ARCH-04): every non-pending entry's
  `source_path` must exist at validation time — staged bytes come from
  the vendor pipeline (`make vendor-assets`; the authoritative pipeline doc is
  docs/vendor-assets.md) and are sha256-pinned by
  `assets/vendor/manifest.json`. `pending = true` is the explicit hatch for
  packs not yet vendored so art can land incrementally without red CI;
  every pending entry MUST flip to a real staged file before ship.
- `atlas_region` (T-UI-01 round-2, additive-optional): sub-rectangle of
  the RENDERED `@2x` PNG that is the whole asset, for multi-pose source
  sheets — the UI composes an `AtlasTexture` over exactly this region so
  one staged sheet serves many faces and the crop is content data. The
  validator checks well-formedness when declared (origin >= 0, size
  positive on both axes). Grid math of record for the Kenney Toon
  Character sheets: 864x640 px = a uniform 9x5 grid of 96x128 cells; cell
  (0,0) is the neutral front-facing standing pose on all three staged
  sheets, so the MVP faces declare `Rect2(0, 0, 96, 128)` (pixel-probe
  verified 2026-09-15; pinned by test_theme_grammar's tiling assertion).
- `RegimeDef` carries the two ink colors (`ink_ground`,
  `ink_secondary`, must differ) that T-UI-01's theme applies to authored
  frames and recolored pack art; the crest key resolves through the same
  manifest.

Unreferenced manifest entries are allowed (art can land before content
uses it); *referenced but missing* keys are errors.

## 4. The defs and the R4 vocabulary as data

Every field below lives in a `.tres` file, never in code constants. R4
seed values are the **class defaults** of `EconomyTunables` — a bare
`EconomyTunables.new()` validates clean and equals the research
recommendation (proven by test).

### UnitDef (`content/schema/unit_def.gd`) — T-SIM-03/04/06, T-COPY-01

| Field | Type | Constraint | Meaning |
|---|---|---|---|
| `id` | `StringName` | non-empty, unique | Stable content id |
| `display_name` | `String` | non-empty | Localization-ready name |
| `can_work` | `bool` | — | May be assigned to a producing building (worker) |
| `training_time_hours` | `float` | ≥ 0 | Sim-hours to promote INTO this unit |
| `promotion_paths` | `Array[StringName]` | resolve to unit ids; acyclic | Branch structure (peasant→worker/militia→trainee→knight/archer) |
| `required_gear_slots` | `Array[StringName]` | ⊆ pack `gear_slots`; each slot has gear | Slots that must be filled (any tier) to count as geared |
| `combat_power` | `int` | ≥ 0 | Army-score contribution (T-SIM-06 odds) |
| `suspicion_on_train` | `int` | ≥ 0 | Suspicion added when training completes (R4 loud acts) |
| `face_id` | `StringName` | resolves in art manifest | Face asset key |

### BuildingDef (`content/schema/building_def.gd`) — T-SIM-02/05/08

| Field | Type | Constraint | Meaning |
|---|---|---|---|
| `id`, `display_name` | | non-empty, id unique | |
| `resource_produced` | `StringName` | declared resource, or empty = non-producing (training grounds) | What workers produce |
| `base_production_per_worker_hour` | `float` | > 0 when producing | Rate per worker at level 1 |
| `worker_slots_base` | `int` | ≥ 1 when producing | Slots at level 1 |
| `base_cost` | `Dictionary[StringName, int]` | non-empty; declared keys; values > 0 | First-level cost |
| `cost_growth` | `float` | within tunables band **[1.08, 1.12]** (R4 r per building; validated cross-pack) | `cost_next = base × r^level` |
| `milestone_levels` | `Array[int]` | non-empty, ≥ 2, strictly increasing, ≤ max_level | Levels firing the ×2 milestone multiplier (R4: [10, 20], then every +10) |
| `max_level` | `int` | ≥ 1 | Hard level cap |
| `icon_id` | `StringName` | resolves in art manifest | Table icon key |

### GearDef (`content/schema/gear_def.gd`) — T-SIM-03/05/06

| Field | Type | Constraint | Meaning |
|---|---|---|---|
| `id`, `display_name` | | non-empty, id unique | |
| `slot` | `StringName` | declared gear slot | weapon / armor |
| `tier` | `int` | ≥ 1 | 1..3 at MVP; top tier NOT required for knights |
| `recipe` | `Dictionary[StringName, int]` | non-empty; declared keys; values > 0 | Smithy crafting cost (timber+iron) |
| `combat_power` | `int` | ≥ 0 | Army-score contribution while equipped |
| `craft_time_hours` | `float` | ≥ 0 | Smithy craft timer |
| `icon_id` | `StringName` | resolves in art manifest | |

### RegimeDef + RegimeModifier (`content/schema/regime_*.gd`) — T-SIM-02/04/06, T-UI-01/05

| Field | Type | Constraint | Meaning |
|---|---|---|---|
| `id`, `display_name` | | non-empty, id unique | |
| `combat_modifier` | `RegimeModifier` | exactly one (non-null), kind in combat registry, value > 0 | The flavor's 1 combat modifier |
| `economy_quirk` | `RegimeModifier` | exactly one (non-null), kind in economy registry, target = resource or `all`, value > 0 | The flavor's 1 economy quirk |
| `crest_id` | `StringName` | resolves in art manifest | Heraldry key (Armorial) |
| `ink_ground` / `ink_secondary` | `Color` | must differ | R6 two-ink pair for theme recolor |
| `flavor_text` | `String` | — | Reveal-card line (T-COPY-01 refines) |

`RegimeModifier` = `{kind: StringName, target: StringName, value: float}`.
Kind registry (validator-enforced; **additive entries are
forward-compatible** — append to the registry, no format bump):

- Combat: `garrison_multiplier` (castle defense), `army_score_multiplier`
- Economy: `production_multiplier` (target resource or `all`),
  `building_cost_multiplier`

Town-hall's example flavor is expressible in one line each:
garrison ×1.2 (archers on the walls) + timber ×0.85 (timber tax).

### UnlockNodeDef + UnlockEffect + UnlockTreeDef (`content/schema/unlock_*.gd`) — L1, the legacy unlock tree

The persistent meta-progression layer (post-MVP Layer 1; R5's Rogue
Legacy manor pattern — always-on, fed by every run win or lose). The tree
attaches to the pack **additively-optional** (`unlock_tree`); the MVP pack
ships none until L1-B authors one, and its absence is legal everywhere.

| Field | Type | Constraint | Meaning |
|---|---|---|---|
| `UnlockNodeDef.id` | `StringName` | non-empty, unique in tree | Stable content id (`RunMeta.unlocks` persists it — ids are the purchase contract) |
| `UnlockNodeDef.display_name` | `String` | non-empty | Localization-ready name |
| `UnlockNodeDef.branch` | `StringName` | non-empty | Tree-UI grouping label (R5: 2–4 node families per layer — e.g. economy, people) |
| `UnlockNodeDef.cost` | `int` | > 0 | Purchase price in banked legacy points (earn rates per docs/balance.md: ~150–260 lp/run) |
| `UnlockNodeDef.prerequisites` | `Array[StringName]` | resolve to node ids in the SAME tree; the graph is ACYCLIC (validator DFS, the promotion-graph pattern — a cycle is unpurchasable and fails the load) | Node ids that must be owned first |
| `UnlockNodeDef.effect` | `UnlockEffect` | exactly one per node (the RegimeModifier discipline) | The node's single typed effect |
| `UnlockEffect.kind` | `StringName` | in the L1 registry (below) | Operator kind |
| `UnlockEffect.value` | `float` | > 0 | Multiplier value |
| `UnlockTreeDef.version` | `int` | ≥ 1 | Tree-shape version for humans/tools; ADDITIVE nodes never bump it (node ids are the contract — same rule as §6) |
| `UnlockTreeDef.nodes` | `Array[UnlockNodeDef]` | non-empty when attached | Every purchasable node |

Effect kind registry (`ContentValidator.LEGACY_EFFECT_KINDS`, mirroring
`LegacyModifiers.EFFECT_KINDS` — the resolution engine owns the
vocabulary; additive entries are forward-compatible exactly like the
regime kinds):

- `recruit_arrival_interval_multiplier` — the WHOLE arrival cadence
  scales together (normal interval, jitter, the opening-rush ramp; < 1.0
  = a busier road)
- `building_cost_multiplier` — construction/upgrade costs (composes with
  regime cost quirks at the same run-start drain)
- `training_time_multiplier` — training durations (< 1.0 = faster drills;
  zero-hour trainings stay zero-hour)
- `gear_cost_multiplier` — gear recipe payments (floored lines, min 1)
- `stipend_bonus` — the run-start `grant_resources` stipend (1.25 = +25%)

Validator: `ContentValidator.validate_unlock_tree(tree)` (pure, also
called by `validate_pack` for an attached tree; error grammar
`"unlock '<id>': <problem>"` / `"unlock-tree: <problem>"`, wording is API
— asserted verbatim by `tests/unit/test_legacy_system.gd`). Resolution +
purchase rules + persistence: `sim/legacy_system.gd` +
`sim/legacy_modifiers.gd` and docs/sim-engine.md §18. Worked example:
`content/examples/unlock_tree.tres` (4 nodes, 2 branches, 1 gated edge —
attached to `pack_example.tres`, validated on the §5 green path).

### IdentityPools (`content/schema/identity_pools.gd`) — T-SIM-04, T-COPY-01

| Field | Constraint (variety floors for the 100-leader acceptance) |
|---|---|
| `leader_first_names: Array[String]` | ≥ 6, unique, non-empty |
| `leader_epithets: Array[String]` | ≥ 6, unique, non-empty |
| `personality_tags: Array[StringName]` | ≥ 4, unique, non-empty |
| `recruit_names: Array[String]` | ≥ 8, unique, non-empty |
| `leader_traits: Array[String]` | additive-optional (T-COPY-01); when non-empty: ≥ 4, unique, non-empty — the run lifecycle's trait draw uses it (one draw, same slot; `TRAIT_STUB_LABELS` is the code-side floor when absent) |

### CopyTable (`content/schema/copy_table.gd`) — T-COPY-01 (docs/voice-bible.md)

| Field | Constraint |
|---|---|
| `templates: Dictionary[StringName, PackedStringArray]` | every key in `CopyTable.KEY_TOKENS` (87 — content cannot invent keys no surface reads); 1..`MAX_VARIANTS` (4) variants per key; every `{token}` from the key's vocabulary; keys in `ROTATING_KEYS` (repeated beats) need ≥ 2 variants; every variant passes the banned-register word scan (word-boundary, case-insensitive — `BANNED_FRAGMENTS`) |

The renderer (`sim/copy_deck.gd`, `CopyDeck`) picks variants by a rotor
derived from view data (event seq / run number / report ticks / the beat
script's hash — never RNG: rendering is pure and replay-deterministic);
`CopyDeck.DEFAULTS` is the code-side one-variant floor so no-table
environments read the same voice. Line budgets are enforced by test in
real font metrics (docs/voice-bible.md §4).

### EconomyTunables (`content/schema/economy_tunables.gd`) — the R4 vocabulary, T-SIM-08 tuned

Defaults started as R4 seeds and were tuned by the T-SIM-08 balance pass in
the simulator (docs/balance.md — the sweep tables and the reasoning). The
MVP pack `.tres` sets nothing; class defaults flow through (pinned by
`test_mvp_pack.test_tunables_equal_the_tuned_class_defaults`). Consumed by
T-SIM-07 (offline), T-SIM-02 (band), T-SIM-03 (recruit arrival cadence),
T-SIM-05 (suspicion), T-SIM-06 (assault block), T-SIM-08 (all),
T-SEC-01 (cap/clamp policy).

| Field (default) | R4 row | Validator constraint |
|---|---|---|
| `offline_cap_hours` (8) | A: premium floor, range 4–24 | within [4, 24] |
| `offline_rate` (1.0) | A: 100% linear | within (0, 1] — sub-1.0 is an F2P lever |
| `cost_growth_band_min/max` (1.08/1.12) | B: r per building | 1.0 < min ≤ max < 2.0; buildings checked against it |
| `milestone_multiplier` (2.0) | B: ×2 at 10/20 | ≥ 1.0 |
| `knight_cost_step` (1.6) | B: ~1.6× per knight | within (1.0, 3.0) — declared-but-unconsumed at MVP (docs/balance.md §2: gear recipes + training time ARE the knight cost curve; no system models per-copy scaling) |
| `recruit_arrival_interval_hours` (2.0) | T-SIM-03: base interval between peasant arrivals (additive field, no format bump) | > 0 |
| `recruit_arrival_jitter_hours` (0.25) | T-SIM-03: ± jitter per interval, drawn from the engine's seeded RNG (0 = metronome, no draws) | within [0, interval) |
| `recruit_arrival_early_count` (6) | T-SIM-08: the opening rush — the run's FIRST N arrivals on a metronome ramp (additive field; 0 = disabled; reset_run re-opens it every run) | ≥ 0 |
| `recruit_arrival_early_interval_hours` (0.1) | T-SIM-08: the first early interval — 6 sim-min, inside journey 1's 10–15 min window | within (0, interval] when count > 0 |
| `recruit_arrival_early_step` (2.0) | T-SIM-08: multiplicative ramp per early arrival, capped at the base interval (1.0 = uniform fast cadence) | ≥ 1.0 when count > 0 |
| `recruit_gate_capacity` (6) | T-SIM-08: max concurrent gate offers — a full gate PAUSES arrivals (online or offline, one rule; docs/catch-up.md §8). 0 = uncapped (pre-T-SIM-08) | ≥ 0 |
| `suspicion_max` (100) | C: range | ordering input |
| `suspicion_warn_threshold` (35) | C: tier 1 | 0 < warn < crackdown < max |
| `suspicion_crackdown_threshold` (70) | C: tier 2 | (same ordering) |
| `suspicion_decay_per_hour` (5.0) | C: −5/h below tier 2 | ≥ 0 |
| `suspicion_decay_high_tier_per_hour` (2.5) | C: −2.5/h "compromised" | ≤ low-tier decay |
| `suspicion_rise_loud` (8) / `suspicion_rise_medium` (4) | C: +8/+4 per act | 0 ≤ medium ≤ loud |
| `crackdown_seize_fraction` (0.4) | C: seize 40% | within (0, 1) |
| `crackdown_telegraph_hours` (4.0) | C: ≥ 4h telegraph | ≥ 4.0 (R4 commitment) |
| `post_crackdown_suspicion` (45) | C: drop to 45 | < crackdown threshold |
| `post_crackdown_rise_multiplier` (0.5) | C: ×0.5 | within (0, 1] |
| `post_crackdown_relief_hours` (24) | C: 24h window | > 0 |
| `suspicion_presence_army_per_hour` (**0.3**, R4 seed 0.5) | T-SIM-05 heat profile; T-SIM-08 tuned — the measured estate must sit below the tier-2 decay or laying low can never cancel a telegraph (docs/balance.md §2) | ≥ 0 |
| `suspicion_presence_follower_per_hour` (**0.05**, R4-derived 0.1) | T-SIM-05: presence per non-army tracked unit (tuned with the army weight) | ≥ 0 |
| `suspicion_presence_building_per_hour` (0.0) | T-SIM-05: continuous presence per building level — DEFAULT 0, re-affirmed CONSCIOUSLY by T-SIM-08 (buildings are loud when they GROW, via the medium act; always-on estate heat would make the tier-2 decay dip unreachable = an un-cancellable telegraph, which R4's tension mechanic forbids) | ≥ 0 |
| `suspicion_presence_offer_per_hour` (0.25) | T-SIM-05: presence per recruit offer waiting at the gate (bounded structurally by `recruit_gate_capacity`) | ≥ 0 |
| `suspicion_recruit_tolerance` (3) | T-SIM-05: arrivals while offers EXCEED this are loud acts (+rise_loud); the gate capacity bounds the crowd | ≥ 0 |
| `suspicion_decay_pause_hours` (1.0) | T-SIM-05: a loud act above warn freezes decay this long (R4 decay_reset_rule) | ≥ 0 |
| `crackdown_scatter_fraction` (0.5) | T-SIM-05: fraction of the unassigned pool (offers + idle peasants) a crackdown scatters; rounds UP; never touches army/workers/buildings | within (0, 1] |
| `crackdown_rearm_hours` (4.0) | T-SIM-05: minimum hours after a crackdown before the next telegraph may arm (recur gate) | ≥ 0 |
| `assault_knight_floor_power` (23) | T-SIM-06: minimum army POWER to commit an assault — the knight FLOOR (a floor, not a trigger; 23 = the M1-measured 1 knight t1 + 1 archer t1 line, m1-findings) | > 0 |
| `assault_garrison_base_power` (**50**, derived seed 60) | T-SIM-06: base castle garrison strength before the regime combat modifier; T-SIM-08 tuned for the first-win band (floor ≈ 277–338 permille by flavor, 2x floor ≈ 44–49%, 100 power ≈ 63–69%; docs/balance.md §2) | > 0 |
| `assault_loss_fraction` (0.5) | T-SIM-06: fraction of ARMY UNITS that fall when an assault FAILS; rounds UP; newest first, gear and all; the run continues (set-back, not death) | within (0, 1] — never annihilation |
| `assault_failure_suspicion` (20) | T-SIM-06: suspicion spike on a failed assault (the Crown watched the whole army break); relief-damped, clamped; CAN crush at the meter's edge | within [0, `suspicion_max`] |

R4 rows not carried as fields (`first_session_budget`,
`per_session_visible_delta`, `run_arc_shape`) are acceptance targets for
T-SIM-08/T-UI-10, not sim inputs — they are candidates for additive
fields if the simulator wants them data-driven.

## 5. Validation contract (fails loudly)

`content/content_validator.gd` is the loud gate required by
`docs/gdscript-conventions.md` ("invalid content is push_error + refuse
to start, never silently default"):

- `ContentValidator.validate_pack(pack) -> Array[String]` — pure,
  deterministic, ordered (header → art → units → buildings → gear →
  regimes → identity → tunables). Empty array = valid.
- `ContentValidator.load_pack(path) -> ContentPack` — the runtime entry:
  loads, validates, and on any problem push_error's **every** error and
  returns `null`. Boot code (T-SIM tasks) treats `null` as refuse-to-
  start. `ContentValidator.validate_tunables(t)` validates a lone
  tunables draft (T-SIM-08 sweeps).
- **Error grammar**: `"<kind> '<id>': <problem>"` for def-scoped errors
  (`unit 'knight': face_id 'face_ghost' missing from art manifest`),
  `"pack: <problem>"` for pack-scoped ones. **Message wording is API**:
  `tests/unit/test_content_schema.gd` asserts messages verbatim; change
  a message only in the same commit as its test.
- Wired into `make test`:
  - *Green path*: `content/examples/pack_example.tres` + all its files
    validate with zero errors.
  - *Green path 2 (T-DATA-02)*: `content/mvp/pack.tres` — the shipped MVP
    pack — loads through `load_pack` and validates with zero errors
    (`tests/unit/test_mvp_pack.gd` also pins its id contract, economy
    self-consistency, regime quirk-shape coverage, no-orphan art, no
    duplicate display names, and a zero-backdoor grant-verb boot).
  - *Red path*: `tests/unit/fixtures/pack_invalid.tres` (a real broken
    pack on disk) — `load_pack` must return `null`; plus 12 in-code
    mutation tests asserting exact messages (empty id, unknown promotion
    target, promotion cycle, duplicate id, cost growth outside the R4
    band, threshold ordering, telegraph floor, missing art key, CC-BY
    without attribution, art source path missing on disk / `pending`
    hatch, undeclared slot, required-slot-without-gear).
    A deliberate-break check (wrong expected message → gdUnit4 exit 100)
    confirmed the assertions bite.

## 6. Versioning and forward compatibility

- `ContentPack.format_version` is the versioning field. Build supports
  `{1}` (`ContentValidator.SUPPORTED_FORMAT_VERSIONS`); a pack outside
  the set is refused loudly — **newer content never silently
  half-loads** into an older game.
- **Additive fields do not bump the version**: a new *optional* field
  with a valid default loads fine everywhere (Godot omits
  default-valued properties from `.tres`, and older builds ignore
  unknown properties). A new *constraint* or *required* field bumps the
  version; during migration the validator may accept both versions
  explicitly, and the bump is documented here with a migration note.
- Renaming or repurposing an existing field's meaning is forbidden
  without a version bump — ids and field semantics are the contract
  saves depend on.

## 7. Saves and the future L2 escalation snapshot

- Run saves (T-ARCH-03/T-DATA-03) reference content **only by stable
  `StringName` ids** — `unit_id`, `gear_id`, `regime_id`, `pack_id` +
  `format_version` in the save header. No file paths, no resource
  references. A save therefore survives content file reorganization,
  and a missing id is a loud, diagnosable event, not corruption.
- **L2 escalation preview** (post-MVP, reserved): the winning-army
  snapshot stores counts keyed by content id, e.g.
  `{"format_version": 2, "regime_id": "gilded_crown", "garrison":
  [{"unit_id": "knight", "count": 7}, {"unit_id": "archer", "count": 12}]}`.
  MVP needs no code for this — the *id stability rule above* is the whole
  MVP-side cost of keeping it possible (Mr. Fantastic's town-hall
  concern: escalation as a derived save snapshot, not new systems).
- Unknown-id policy at L2 (documented now, coded later): fall back to
  the nearest known def of the same role and print a chronicle line —
  never crash, never silently invent.

## 8. Worked examples (T-DATA-02 seeds)

`content/examples/` — a complete, validating pack:

```
pack_example.tres            root manifest (references the files below)
units/peasant.tres           → worker | militia
units/worker.tres            can_work
units/militia.tres           suspicion_on_train 8 (R4 loud)
units/trainee.tres           → knight | archer
units/knight.tres            12h, combat 10, requires weapon+armor
units/archer.tres            6h, combat 6, requires weapon (cheaper/faster/weaker)
buildings/farm.tres          food 6/h/worker, timber 15, r=1.08, milestones [10,20]
gear/gear_weapon_t1.tres     weapon t1: 5 timber + 10 iron, combat 2
gear/gear_armor_t1.tres      armor t1: 15 iron, combat 3
regimes/gilded_crown.tres    garrison ×1.2 + timber ×0.85, inks, crest
unlock_tree.tres             L1 seeds: 4 nodes, 2 branches, 1 gated edge
identity_pools.tres          8× first, 8× epithet, 6× tags, 12× recruit
economy_tunables.tres        R4 seeds (== class defaults)
art_manifest.tres            10 assets: Kenney/tzunghaor CC0, Armorial
                             commercial, game-icons CC-BY-3.0 (attributed)
```

Numeric values beyond the R4-anchored ones (production rates, recipe
costs, training hours) are placeholders for T-SIM-08 to tune — the
schema's job is that they are *data*, swappable without code changes.
`tests/unit/fixtures/pack_invalid.tres` is the permanent red-path
fixture (a pack whose first unit has an empty id, among other faults).

## 9. The MVP pack (T-DATA-02) — the game's shipped content

`content/mvp/pack.tres` is the full MVP content set; every acceptance
suite and `scripts/save_debug.gd` loads it through the loud gate via the
shared fixture `tests/acceptance/suites/_mvp_pack.gd` (one source of
truth — no suite carries its own content copy):

- **Resources**: food, timber, iron. **Gear slots**: weapon, armor × 3 tiers.
- **Units**: the 6-unit chain peasant→worker/militia→trainee→knight|archer
  (worker 0h — zero-hour chores, the 2026-09-17 journey-1 trickle retune;
  militia 2h, trainee 4h, knight 12h combat 10, archer 6h combat 6 — the
  M1-measured drill ladder stands; t1 knight kit = 25 iron +
  5 timber ≈ 2.8h of fully-staffed L1 smithy — M1 finding F3's healthy
  parity, pinned by test).
- **Buildings** (the M1 watch-item reconciliation): farm (food 24/h —
  the journey-1 trickle retune; 2
  slots, timber 15, r=1.08), lumber_camp (timber 6/h, 2 slots, food 10,
  r=1.10), smithy (iron 3/h, 3 slots, timber 40 + food 20, r=1.12) and
  training_grounds (non-producing flavor card — training needs no
  building per T-SIM-03; the smithy doubles as the bog-iron smelter so
  gear crafting has its flavor home). Producer numbers are byte-identical
  to the M1-measured trio.
- **Regimes**: gilded_crown (garrison ×1.2 + timber prod ×0.85),
  iron_rotunda (army score ×1.1 + all costs ×1.2), velvet_fist
  (garrison ×0.9 + all production ×1.15), paper_crown (army score ×0.95 +
  timber costs ×0.75) — distinct combat modifiers and all four economy
  quirk shapes (per-resource prod, prod-all, cost-all, per-resource
  cost), with inks, crests and satirical flavor text.
- **Identity pools** (T-COPY-01's expanded breadth): 46 leader first
  names × 52 epithets (2,392 full-name permutations — thousands), 20
  personality tags, 72 recruit names, 10 leader trait labels — medieval
  farce, no anachronisms (banned-register scanned by test).
- **Copy table** (T-COPY-01, additive): 87 template keys × 1–4 variants
  each — the shipped voice for every repeating printed line, sized to
  the 476px/22px line-budget standard with seeded variant rotation
  (docs/voice-bible.md).
- **starting_grants**: `{food 50, timber 80}` — affords building all four
  buildings at identity costs with a thin spare buffer; paid once per run
  by the `grant_resources` command (docs/sim-engine.md §12, F1).
- **Art manifest**: 20 assets — every unit face, building icon, gear icon
  and regime crest keyed; ids only, paths are forward declarations of the
  vendored layout until T-ARCH-04.

Editing workflow: open the project in the Godot editor
(`tools/godot/godot -e`), select a `.tres`, edit fields in the inspector
— the validator and tests guard the result. New files: create the
resource from its class in the inspector, or duplicate an example.
Run `make import` once after cloning or adding schema scripts (the
editor builds the global class cache; see `docs/DEV_SETUP.md`).
