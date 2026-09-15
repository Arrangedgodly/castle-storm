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
  `commercial`, ...), `attribution`. **CC-BY-family licenses require a
  non-empty attribution** — the validator enforces R6's license hygiene
  (game-icons.net credits).
- Path *existence* is deliberately not checked until T-ARCH-04 lands (the
  packs are not vendored yet); the example manifest's paths are forward
  declarations of the vendored layout.
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

### IdentityPools (`content/schema/identity_pools.gd`) — T-SIM-04, T-COPY-01

| Field | Constraint (variety floors for the 100-leader acceptance) |
|---|---|
| `leader_first_names: Array[String]` | ≥ 6, unique, non-empty |
| `leader_epithets: Array[String]` | ≥ 6, unique, non-empty |
| `personality_tags: Array[StringName]` | ≥ 4, unique, non-empty |
| `recruit_names: Array[String]` | ≥ 8, unique, non-empty |

### EconomyTunables (`content/schema/economy_tunables.gd`) — the R4 vocabulary

Defaults = R4 seeds. Consumed by T-SIM-07 (offline), T-SIM-02 (band),
T-SIM-05 (suspicion), T-SIM-08 (all; tuned in the simulator),
T-SEC-01 (cap/clamp policy).

| Field (default) | R4 row | Validator constraint |
|---|---|---|
| `offline_cap_hours` (8) | A: premium floor, range 4–24 | within [4, 24] |
| `offline_rate` (1.0) | A: 100% linear | within (0, 1] — sub-1.0 is an F2P lever |
| `cost_growth_band_min/max` (1.08/1.12) | B: r per building | 1.0 < min ≤ max < 2.0; buildings checked against it |
| `milestone_multiplier` (2.0) | B: ×2 at 10/20 | ≥ 1.0 |
| `knight_cost_step` (1.6) | B: ~1.6× per knight | within (1.0, 3.0) |
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
  - *Red path*: `tests/unit/fixtures/pack_invalid.tres` (a real broken
    pack on disk) — `load_pack` must return `null`; plus 11 in-code
    mutation tests asserting exact messages (empty id, unknown promotion
    target, promotion cycle, duplicate id, cost growth outside the R4
    band, threshold ordering, telegraph floor, missing art key, CC-BY
    without attribution, undeclared slot, required-slot-without-gear).
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

Editing workflow: open the project in the Godot editor
(`tools/godot/godot -e`), select a `.tres`, edit fields in the inspector
— the validator and tests guard the result. New files: create the
resource from its class in the inspector, or duplicate an example.
Run `make import` once after cloning or adding schema scripts (the
editor builds the global class cache; see `docs/DEV_SETUP.md`).
