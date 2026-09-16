# Save schema — Castle Storm (T-DATA-03)

The **authoritative field-level reference** for everything Castle Storm
persists: every field of both save domains, its type, its meaning, and the
rules that govern its encoding. Companion to `docs/save-format.md`, which
owns the *file architecture* (envelope mechanics, atomicity, ring rotation,
quarantine, checksum canonical form, migration-registry mechanics) — read
that first; this doc never repeats its proofs, only its consequences for
fields.

Sources of truth this doc mirrors (drift is a bug in THIS doc, fixed here —
see §9):

| Domain | Writer | Restorer |
|---|---|---|
| run payload | `SimEngine.to_dict()` (`sim/sim_engine.gd`) + each system's `to_dict()` | `SimEngine.apply_state_dict()` + `from_dict()` |
| meta payload | `RunMeta.to_dict()` (`sim/run_meta.gd`) | `RunMeta.apply_dict()` |
| envelope + files | `SaveManager._build_envelope_text()` (`sim/save_manager.gd`) | `SaveManager._read_envelope()` |

**This doc is machine-checked.** Every ` ```save-keys ` block below (one key
per line) is pinned against a real save generated from a real 500h full-stack
run by `tests/unit/test_save_schema_doc.gd` in `make test`. Add a field to a
`to_dict()` without updating its block — or document a field the code no
longer writes — and CI fails with the exact key diff. §9 records the
contract for extending the check.

## 1. Version axes (three, independent)

| Axis | Constant | Where it lives | Today | Refusal behavior on mismatch |
|---|---|---|---|---|
| Save (envelope) schema | `SaveManager.CURRENT_SCHEMA_VERSION` | `"schema_version"` in BOTH envelopes | 1 | old file → walked forward by the migration registry (§7); newer file → refused loudly + quarantined |
| Engine state format | `SimEngine.STATE_FORMAT_VERSION` | `"format_version"` at the top of the run payload | 1 | `apply_state_dict` refuses (no half-apply); slot is future-good, NOT quarantined; load falls back to the next slot |
| Meta state format | `RunMeta.META_FORMAT_VERSION` | `"format_version"` at the top of the meta payload | 1 | `apply_dict` refuses; corrupt-meta policy (save-format.md §8) returns a fresh bank |

The save schema versions the FILE (what a migration rewrites); the two
payload format versions version the PAYLOAD's own shape (what an apply
refuses). A breaking change normally moves an envelope version and its
payload version together — the worked example in §7 shows exactly how they
interlock. When a bump is required at all is policy, §8. Machine-checked
current values (§9 suite pins them):

```save-version
schema 1
engine-state 1
meta-state 1
```

## 2. On-disk layout (field reader's map)

```
<root>/                     default user://saves
  run_slot_0.json           run domain — rotating ring slot 0
  run_slot_1.json           run domain — rotating ring slot 1
  run_slot_2.json           run domain — rotating ring slot 2
  meta.json                 meta domain — single file
  run_slot_N.json.tmp       transient atomic-write temp (swept by the next process)
  run_slot_N.json.corrupt   quarantined unloadable file (bytes preserved, [-n] on collision)
```

Ring of `RUN_SLOT_COUNT = 3`, always writing the slot AFTER the newest good
one; `save_seq` (run files only) is the monotonic counter that orders them.
Full semantics — atomicity model, crash leftovers, fsync deviation,
rotation-and-fallback proofs: `docs/save-format.md` §1/§3/§6.

Every file, either domain, is one pretty-printed JSON object with this
envelope (run shown; the meta envelope omits `save_seq`):

```save-keys run-envelope
domain
schema_version
save_seq
saved_at_unix
checksum
payload
```

```save-keys meta-envelope
domain
schema_version
saved_at_unix
checksum
payload
```

| Field | Type | Meaning |
|---|---|---|
| `domain` | String | `"run"` or `"meta"`; a mismatch with the file's location is a quarantine-class failure |
| `schema_version` | int | the FILE's save-schema version (axis 1, §1) |
| `save_seq` | int | run files only: 0-based monotonic save counter; finds the newest good slot; survives process restarts (rescanned from slot headers) |
| `saved_at_unix` | int | wall-clock stamp, humans/debug only — never read back by game logic, never hashed |
| `checksum` | String | SHA-256 hex over the payload's canonical form (save-format.md §5) |
| `payload` | Dictionary | the domain state — everything below |

**Quarantine semantics, short form** (full: save-format.md §6): a file that
cannot be validated (parse error, truncation, empty, checksum mismatch,
domain mismatch, invalid or newer-than-build `schema_version`) is renamed
`<name>.corrupt[-n]` — bytes preserved forever, never deleted, never able to
take other slots or the other domain down — and load falls back. A file that
validates but is REFUSED by the engine/meta apply (typically a payload
`format_version` from another engine generation) is NOT quarantined: the
bytes are future-good and stay in place. Field readers must never assume the
newest file is the loaded one.

## 3. Encoding rules every field obeys

1. **JSON-safe scalars only** — int, String, bool, Array, Dictionary. No
   object references, no StringName (written as String), no floats in run
   state (the engine's economy is integer milli-math; the only floats in
   content cross one conversion boundary at construction and never persist).
2. **Ids, not objects.** Content defs (UnitDef, BuildingDef, GearDef,
   RegimeDef, IdentityPools, stipend amounts) are boot-injected from the
   pack and NEVER serialized. Saves carry ids; the restore resolves ids
   against the same pack. An id that left the pack is skipped or dropped
   LOUDLY (`push_warning`), never silently defaulted — each system's
   restore rules are in its table below.
3. **64-bit-exact integers.** JSON numbers are float64; every integer with
   `|v| > 2^53 = 9007199254740992` is written as
   `{"__i64__": "<decimal string>"}` and restored exactly by the codec
   (`SaveManager.encode_exact_ints`/`decode_exact_ints`). The live case is
   `rng_state` — a full 64-bit RNG state outside float range within minutes
   of play, hashed by `state_hash()`, and the reason the codec exists.
   Ints at or inside ±2^53 stay plain, diffable JSON numbers.
4. **Insertion order is load-bearing.** Files are written by the
   insertion-order-preserving writer (save-format.md §3) because parts of
   the state hash depend on dictionary order (unit gear slots mix into
   `state_hash()` in equip order). A field documented as "ordered" must be
   restored in array/document order, never sorted.
5. **Arrays are ordered state** (gate offers, pending commands, chronicle,
   roster). Order is part of the meaning; readers must not re-sort.
6. **Never persisted:** the event ring (presentation history), content
   defs (rule 2), and anything from the OTHER domain — the meta bank and
   chronicle are deliberately absent from the run payload so a run-save
   restore can neither fork nor rewind the bank, and vice versa.

## 4. Run domain payload (`SimEngine.to_dict`)

```save-keys run-payload
format_version
run_seed
tick_count
paused
rng_state
resources
pending_commands
systems
```

| Field | Type | Meaning / restore notes |
|---|---|---|
| `format_version` | int | `SimEngine.STATE_FORMAT_VERSION` (axis 2). Refused on mismatch — never half-applied |
| `run_seed` | int | the seed this engine was constructed with; restore also re-seeds before overwriting rng state (same stream) |
| `tick_count` | int | processed ticks; 1 tick = 1 sim-minute. The engine's clock |
| `paused` | bool | frozen-advancement flag (commands still queue) |
| `rng_state` | int | the single seeded RNG's full 64-bit state — determinism itself. The one field guaranteed to need the `__i64__` tag in real saves |
| `resources` | Dictionary[String, int] | whole-unit resource pool keyed by resource id (e.g. `"food"`); restore rebuilds the StringName keys |
| `pending_commands` | Array[Dictionary] | the FIFO command queue, drained at the START of the next processed tick. Array order IS drain order |
| `systems` | Dictionary[String, Dictionary] | one sub-dict per registered system, keyed by `system_name()`. The restore host must register the SAME systems first; each registered system is fed its sub-dict by name. A registered system with no saved entry warns and keeps boot state; a saved entry with no registered system is simply unread |

### 4.1 `pending_commands[*]`

```save-keys run-pending-command
kind
subject
value
```

Exactly the `SimCommand` triple: `kind` (String, the verb, e.g.
`"upgrade_building"`), `subject` (String, the target id or `""`), `value`
(int, count/uid/override). Restored as the queue tail — they drain on the
first post-load tick, exactly as if never interrupted.

### 4.2 `systems` keys (the full stack)

```save-keys run-systems
heartbeat
run
units
production
```

Keyed by `system_name()`; the four above are the full-stack registration
(heartbeat = the seam-proof placeholder; a leaner engine saves a leaner map —
the key set is whatever is registered, which is why the restore host
registers the same systems). Sub-dicts follow. NOTE (T-SIM-05): an engine
that registers the suspicion system (opt-in per docs/sim-engine.md §14 —
the marathon fixture and the future game host do; this doc's machine-checked
stack does not, yet) carries a fifth `suspicion` sub-dict, whose field-level
reference lives in sim-engine.md §14 ("Serialization + determinism") until
it joins this doc's generated stack — the same additive-optional-keys,
tolerant-reader policy as §8's `regime_quirks` precedent applies (absent
key = the system was not registered; present = restored verbatim). NOTE
(T-SIM-06): the assault resolver (opt-in per sim-engine.md §15) registers
the same way but is STATELESS BY DESIGN — its sub-dict is always `{}`
(`to_dict()` empty, constant `state_hash`, no `reset_run`): nothing
assault-shaped exists between commands, so nothing assault-shaped is ever
saved, restored, or survives a restart; the roster/meter/run state it
touches is already carried by the `units`/`suspicion`/`run` sub-dicts
above. A sixth+ key follows the identical policy.

### 4.3 `systems.heartbeat` — `HeartbeatSystem`

```save-keys system-heartbeat
ticks
pings
```

`ticks` (int): ticks this system has counted. `pings` (int): accumulated
`ping` command values. Test-role system; survives because it is registered.

### 4.4 `systems.run` — `RunLifecycleSystem`

```save-keys system-run
status
run_index
leader_first
leader_epithet
leader_tags
trait_stub
regime_id
start_tick
end_tick
outcome
last_score
stipend_run
```

| Field | Type | Meaning / restore notes |
|---|---|---|
| `status` | int | 0 UNSTARTED / 1 RUNNING / 2 ENDED |
| `run_index` | int | engine-local run number (1-based). Distinct from the meta domain's monotonic `runs_recorded` — engine-local indexes reset with a re-init |
| `leader_first` | String | drawn leader first name ("" before the first run_start) |
| `leader_epithet` | String | drawn epithet |
| `leader_tags` | Array[String] | 2 DISTINCT personality tags, draw order |
| `trait_stub` | int | index into the code-side `TRAIT_STUB_LABELS` table (T-COPY-01 owns the real traits) |
| `regime_id` | String | the drawn regime's pack id. Restore resolves the id against the boot pack; an unknown non-empty id warns and runs regime-LESS (never guesses). The economy quirk itself is NOT re-derived here — production carries its applied multipliers (§4.6), self-contained |
| `start_tick` / `end_tick` | int | the run's tick frame (end 0 while running) |
| `outcome` | int | 0 none / 1 victory / 2 defeat / 3 aborted |
| `last_score` | int | score banked by the last ended run (0 while running) |
| `stipend_run` | int | run_index that already took its starting stipend (0 = none). Serialized + hashed so a restore cannot double-pay the `grant_resources` stipend |

The meta bank and chronicle are DELIBERATELY ABSENT from this sub-dict
(rule §3.6): they live only in the meta domain (§5).

### 4.5 `systems.units` — `UnitLifecycleSystem`

```save-keys system-units
next_uid
arrivals_total
arrival_countdown_milli
offers
units
```

| Field | Type | Meaning / restore notes |
|---|---|---|
| `next_uid` | int | next unit identity to hand out (uids are engine-lifetime stable from gate arrival through knighthood) |
| `arrivals_total` | int | total gate arrivals since boot (offers created, accepted or not) |
| `arrival_countdown_milli` | int | milli-ticks until the next recruit offer; −1 = not yet scheduled (the first tick schedules it — a restored −1 redraws, preserving the boot shape) |
| `offers` | Array[int] | recruit uids waiting at the gate, arrival order (never expire) |
| `units` | Array[Dictionary] | every tracked unit in arrival order — the roster |

#### `systems.units.units[*]`

```save-keys system-units-entry
uid
def
target
progress
awaiting
gear
```

| Field | Type | Meaning / restore notes |
|---|---|---|
| `uid` | int | stable unit identity |
| `def` | String | current def id (peasant/worker/militia/trainee/knight/archer). Unknown def → unit skipped loudly |
| `target` | String | training-target def id, `""` while resting. A target that left the pack → unit kept, its in-flight training dropped loudly (never crashes on_tick) |
| `progress` | int | milli-ticks elapsed toward the target's duration |
| `awaiting` | bool | training complete, held for gear + the promote command (the stable "waiting for gear" state) |
| `gear` | Dictionary[String, String] | equipped slot id → gear id, **equip order** (rule §3.4 — feeds `state_hash()` in this order). Restore drops gear ids that left the pack, loudly |

The in-flight training list is NOT serialized — it is rebuilt from
`target != "" and not awaiting` in roster order (equivalent engine, proven
lockstep by the round-trip tests).

### 4.6 `systems.production` — `ProductionSystem`

```save-keys system-production
workers_idle
buildings
regime_quirks
```

| Field | Type | Meaning / restore notes |
|---|---|---|
| `workers_idle` | int | idle worker pool count (assigned workers are counted per building) |
| `buildings` | Array[Dictionary] | one entry per pack building, pack order |
| `regime_quirks` | Dictionary | the APPLIED regime economy multipliers — serialized state since the T-ARCH-03 verifier fix (a save made under a quirked regime resumes under it; `from_dict` has no run_start drain to re-apply them). A dict WITHOUT the key is a pre-fix save and keeps the constructed regime — the documented back-compat fallback |

#### `systems.production.buildings[*]`

```save-keys system-production-building
id
level
assigned
accum
```

`id` (String, pack building id; unknown id → entry skipped loudly), `level`
(int, 0 = not yet built), `assigned` (int, workers assigned here),
`accum` (int, the SimFixed milli-unit-seconds remainder carried toward the
next whole unit — bounded, never lost). Everything derived from content
(rate/curve tables) is reconstructed at boot and never saved.

#### `systems.production.regime_quirks`

```save-keys system-production-quirks
prod_all_milli
prod_milli
cost_all_milli
cost_milli
```

`prod_all_milli` / `cost_all_milli` (int): the all-resources production /
building-cost multipliers in milli (1000 = ×1.0 identity). `prod_milli` /
`cost_milli` (Dictionary[String, int]): per-resource overrides, resource id →
milli. Restored verbatim when the parent key is present; mixed into
`state_hash()` so a serialization gap of this class can never hide from the
determinism oracle again.

## 5. Meta domain payload (`RunMeta.to_dict`)

```save-keys meta-payload
format_version
legacy_points
runs_recorded
chronicle
last_seen_epoch
first_session
```

| Field | Type | Meaning / restore notes |
|---|---|---|
| `format_version` | int | `RunMeta.META_FORMAT_VERSION` (axis 3). Refused on mismatch |
| `legacy_points` | int | the banked-points reserve across every recorded run — failure banks FULL progress, so every ended run accrues (win, loss, abort, abandoned-on-restart). No spending exists at MVP (L1 unlock tree is post-MVP by the layer gate) |
| `runs_recorded` | int | the MONOTONIC run number the chronicle displays — unlike engine-local `run_index` it never resets, surviving engine re-inits |
| `chronicle` | Array[Dictionary] | append-only run records, oldest first. One small entry per completed run; unbounded by design |
| `last_seen_epoch` | int | UTC epoch SECONDS of the offline catch-up anchor (T-SIM-07, docs/catch-up.md): the timestamp the next foreground subtracts `now` from. META domain deliberately — away time crosses run boundaries, so the anchor must outlive any engine. `0` is the FIRST-LAUNCH SENTINEL: never marked → no catch-up fires off it. Additive-optional with a tolerant reader (absent key reads as 0): a pre-T-SIM-07 meta upgrades to first-launch semantics — exactly right — with no migration |
| `first_session` | Dictionary | the once-only onboarding flags (T-UI-10): `seen` (this install has had its first session — a returning player is never nudged), the five beat flags (`gate`/`assign`/`build`/`trickle`/`train` — each printed cue fires at most once, ever), and `done` (arc complete or the run ended). META domain because the arc must survive engine rebuilds and process restarts; the flag flip is persisted the moment it prints. Additive-optional with a tolerant reader (absent key reads as `{}` — pre-T-UI-10 metas upgrade to nudge-free, which is right) |

### 5.1 `chronicle[*]` — one entry per ended run

```save-keys meta-chronicle-entry
run
leader
tags
trait
regime
outcome
duration_ticks
army_power
army
score
```

| Field | Type | Meaning |
|---|---|---|
| `run` | int | the meta-monotonic run number (`runs_recorded` at composition time) |
| `leader` | String | full display name (`"first epithet"`) |
| `tags` | Array[String] | the 2 personality tags, draw order |
| `trait` | String | the trait's rendered label (the stub table's text at composition time — the entry is a historical document, so it carries text, not the index) |
| `regime` | String | regime pack id |
| `outcome` | String | normalized text: `"victory"`, `"defeat"`, or `"aborted"` (the event stream's numeric OUTCOME_* codes are run-payload state; the chronicle is a historical document and carries words) |
| `duration_ticks` | int | run length in ticks (start → end) |
| `army_power` | int | terminal army score (assault override or live `army_power()`) |
| `army` | Dictionary[String, int] | terminal roster snapshot, army-eligible def id → count (the chronicle screen's T-UI-08 data) |
| `score` | int | banked score (thin stub: `duration_hours + army_power + 100` victory bonus; T-SIM-08 owns the real curve) |

Meta corruption policy (single file, save-format.md §8): quarantine the
bytes, return a FRESH bank, never touch the run slots.

## 6. L2 ESCALATION SNAPSHOT — reserved, unused at MVP

**Status: reserve only.** Nothing writes or reads this at MVP. The section
exists so the post-MVP Layer 2 (enemy escalation, R5: milestone-gated at
first victory, cycles compressing 2–5× per arc) lands WITHOUT a save
migration and without a format argument later. It is a name claim plus a
binding shape sketch, not code.

**What it will hold:** when a run ends in VICTORY, the winning army becomes
the next cycle's castle — a read-only garrison snapshot the NEXT run's
assault (T-SIM-06 under L2) reads instead of a fresh-regime baseline.

**Exact shape** (a single optional top-level key added to the META payload
of §5 — `RunMeta.to_dict()` would emit it only when non-null):

```json
"escalation_garrison": {
	"regime_id": "gilded_crown",
	"captured_at_run": 7,
	"roster": {
		"knight": {"count": 12, "gear_tiers": {"weapon": {"1": 2, "3": 10}, "armor": {"2": 12}}},
		"archer": {"count": 9, "gear_tiers": {"weapon": {"1": 9}}}
	}
}
```

- `regime_id` (String) — the winning regime's pack id; the reader resolves
  its combat modifier against boot content (the pack's four regimes carry
  DISTINCT garrison modifiers ×1.2/×0.9 and army modifiers ×1.1/×0.95 by
  T-DATA-02 design — L2 reads them, never re-serializes them; rule §3.2).
- `captured_at_run` (int) — the meta-monotonic run number that produced the
  garrison; supports R5's cycle-arc display ("held since run 7").
- `roster` (Dictionary[String, Dictionary]) — army-eligible def id →
  `{"count": int, "gear_tiers": {slot id → {tier (String) → count}}}`.
  `gear_tiers` tier keys are STRINGS because JSON object keys are strings;
  counts per tier sum to `count`. This is strictly more than the chronicle
  entry's `army` (§5.1) carries: tiers per slot, not just bodies — the
  assault's odds input. The capture site composes both from the same
  terminal-roster walk.

**Where it attaches and why there:** `RunMeta` (meta domain), captured in
`RunLifecycleSystem._end_run` on victory — the exact site that already
snapshots `army_roster()` into the chronicle entry; it would additionally
walk the units system's per-unit `gear_tier()` and write the reserve into a
new `RunMeta.escalation_garrison` field. Meta domain, not run domain,
because the garrison must survive the `run_restart` that immediately follows
a victory AND engine re-inits (the run payload is emptied by the reset
contract — §4.4's sibling systems reset at the drain), and because it must
not be forkable from a run save (rule §3.6, same rule as the bank).

**Why MVP saves need NO migration when this lands (the additive-reserve
argument):**

1. *MVP file → L2 build:* the key is simply absent from every MVP meta
   payload. `RunMeta.apply_dict` reads known keys with `.get()` defaults, so
   an absent `escalation_garrison` loads as `null` = "no garrison" = L2's
   first-cycle default (play the fresh-regime baseline). No envelope
   `schema_version` bump is required because the FILE format did not change
   — only the set of optional keys a reader understands did.
2. *L2 file → MVP build (dev matrix only):* the extra key parses fine, the
   checksum covers the payload as written, and `apply_dict` ignores keys it
   does not read — it loads and the garrison is dropped at the next meta
   save. Pre-release this is acceptable; post-release, additive keys remain
   legal in both directions (§8).
3. *Precedents already shipped this way:* `regime_quirks` (added to the
   production sub-dict post-verifier, no version bump, absent-key fallback
   unit-tested) and `stipend_run` (additive run-system key). The reserve is
   the third instance of the same pattern.

The ONLY binding constraints the reserve adds TODAY: nothing else may squat
the key name `escalation_garrison` in the meta payload, and `RunMeta`
serialization must stay key-additive (a rewrite of the §5 fields would force
the §7 machinery — do not).

## 7. Worked migration example — v1 → v2 field rename

Hypothetical but realistic: schema v2 renames the per-unit roster key `def`
to `def_id` (aligning the run payload with the content-schema vocabulary) —
i.e. `payload.systems.units.units[*].def` becomes `...def_id`. Everything
below matches the ACTUAL registry code in `sim/save_manager.gd`
(`migrations`, `_migrate`, `example_migration_v1_to_v2`); only the callable
body is hypothetical.

**A rename is the one migration shape that is allowed to be destructive** —
save-format.md §7's "additive, never drop or reinterpret old fields without
an explicit, tested rewrite" — and this is the explicit, tested rewrite.

### Step 1 — write the migration callable (next to `example_migration_v1_to_v2`)

```gdscript
## v1 -> v2: rename systems.units.units[*].def -> def_id. Pure (input
## untouched), total (stamps the payload's own format_version — see note),
## tested by test_save_manager.gd + test_unit_lifecycle_system.gd.
static func _migrate_v1_to_v2(payload: Dictionary) -> Dictionary:
	var upgraded: Dictionary = payload.duplicate(true)
	var units_state: Dictionary = upgraded.get("systems", {}).get("units", {})
	var rewritten: Array = []
	for entry: Variant in units_state.get("units", []):
		if typeof(entry) == TYPE_DICTIONARY and (entry as Dictionary).has("def"):
			var row: Dictionary = (entry as Dictionary).duplicate(true)
			row["def_id"] = row["def"]
			row.erase("def")
			rewritten.append(row)
		else:
			rewritten.append(entry)
	units_state["units"] = rewritten
	# The payload's OWN version is part of the payload: the v2 engine's
	# apply_state_dict refuses format_version 1, so the migration must end
	# by stamping it or every migrated file would apply-refuse post-walk.
	if upgraded.get("format_version", 0) == 1:
		upgraded["format_version"] = 2
	return upgraded
```

The format-version stamp is the interlock that's easy to miss: the envelope
migration rewrites the payload, but `SimEngine.apply_state_dict` checks the
payload's internal `format_version` against the (also bumped, step 3)
`STATE_FORMAT_VERSION` — a walked file that still says 1 is refused with no
quarantine and the load falls back to nothing.

### Step 2 — register it and bump, in the SAME change

```gdscript
# sim/save_manager.gd
const CURRENT_SCHEMA_VERSION := 2   # was 1 — with the migration above, same change

# game-host construction (once per session; tests register locally):
var manager := SaveManager.new("user://saves")
manager.migrations = {
	1: Callable(SaveManager, "_migrate_v1_to_v2"),
}
```

### Step 3 — the engine side bumps with it

`UnitLifecycleSystem.to_dict()`/`from_dict()` swap to `def_id` in the same
change, and `SimEngine.STATE_FORMAT_VERSION` goes to 2 (the run payload's
shape changed meaningfully). Meta is untouched (`META_FORMAT_VERSION` stays
1) — the two payload versions move independently, only with their own
domains.

### Step 4 — load path, end to end

v1 slot file → `_read_envelope` (valid, `schema_version` 1 ≤ 2) →
`_migrate(1, payload)`: registry has step 1, callable runs, payload now
carries `def_id` + `format_version` 2 → `engine.apply_state_dict` accepts →
identical `state_hash()`. A missing registry entry (someone bumps without
registering) refuses loudly ("no migration registered for step v1 -> v2")
and falls back; a v3 file on a v2 build refuses before any step runs.

### Step 5 — test pattern (all mirroring REAL cases in test_save_manager.gd)

| Test | Existing pattern to copy |
|---|---|
| callable is pure + exactly rewrites (input untouched, old key gone, values preserved, count stamped) | `test_example_migration_stub_is_additive` |
| old v1 file written by a REAL v1 engine loads into the v2 build, hash-identical | `test_migration_chain_walks_registered_steps` |
| bump-without-register refuses loudly, falls back | `test_missing_migration_step_refuses` |
| newer-than-build file quarantined | `test_future_schema_version_quarantined` |
| the system's own reader accepts only the new shape | the `from_dict` cases in `test_unit_lifecycle_system.gd` |

## 8. Save-compatibility policy — when a bump is required

The default is **additive with tolerant readers, no bump**. The registry
exists for rewrites, not for growth.

| Change | Bump? | Mechanism | Shipped precedent |
|---|---|---|---|
| Add an optional payload key; readers use `.get()` defaults (absent key = documented fallback) | **no** | nothing — old files load with the fallback, new files load everywhere | `regime_quirks` (§4.6), `stipend_run` (§4.4); `escalation_garrison` when L2 lands (§6) |
| Add an envelope field | **no** | envelope readers use `.get()` | — |
| Change `state_hash()` composition (mix more state) | **no** (disk untouched) | recorded hash VALUES migrate; every reproducibility assertion stays twin-based, never absolute-hash-pinned | the quirks-hash fix (T-ARCH-03 re-dispatch) |
| Rename / move / retype / remove an existing payload field | **envelope `schema_version` + registered migration** (and the payload's own `format_version` when the run/meta payload's shape changed — §7's interlock) | migration rewrites old files on load | none yet — §7 is the template for the first one |
| Change a field's MEANING with no possible transform (e.g. redefining the tick) | **payload `format_version` only** — apply-refusal by design; effectively a new save generation | old slots fall back (future-good, not corrupt); no migration can exist | — |
| Bump `CURRENT_SCHEMA_VERSION` | **never without registering the migration for the previous version in the same change** | `save_manager.gd`'s const contract | — |

Two asymmetries worth restating (they surprise field authors):

- **Backwards NEWER refusal is intentional:** a file stamped above the
  build's `CURRENT_SCHEMA_VERSION` is quarantined, never approximately
  upgraded. Downgrades are out of scope by design.
- **Pre-release vs post-release:** pre-release, all of this is engineering
  hygiene (no shipped players, no compat matrix). Post-release, the table
  becomes binding — which is why the additive pattern and the §6 reserve
  are being locked NOW: the cheap moment to promise "L2 lands without a
  migration" is before anyone has a save.

## 9. Doc-accuracy contract (how this doc stays true)

`tests/unit/test_save_schema_doc.gd` (runs in `make test`):

1. Builds a REAL full-stack save — the MVP pack through the loud gate, 500
   managed sim-hours (the marathon script: recruits, both promotion
   branches, every gear tier, upgrades, a banked victory), one queued
   command so `pending_commands` is non-empty — then writes both domains
   through `SaveManager` to a scratch root and parses the bytes back.
2. Extracts every `save-keys` block above by id and asserts set-equality
   against the corresponding live key set (envelope, payloads, per-system
   sub-dicts, per-entry shapes, chronicle entry). Drift in EITHER direction
   — code grew a field the doc misses, or the doc lists one the code no
   longer writes — fails with the exact diff.
3. Asserts the §6 reserve holds: the reserved `escalation_garrison` key is
   documented AND absent from the real meta payload on disk (a reserve that
   leaked into MVP writes would break the additivity argument's premise).
4. Asserts the doc's stated save-schema version matches
   `SaveManager.CURRENT_SCHEMA_VERSION`.

When you add a payload field: update the writer, the reader, the table
here, the `save-keys` block, and — if the field is required rather than
optional-with-fallback — reread §8, because you probably owe a bump + a
migration. When you add a new keyed shape: add a block, extend the test's
extraction map.

## 10. Field quick-reference (all `save-keys` ids)

| Block id | Describes |
|---|---|
| `run-envelope` / `meta-envelope` | file envelope fields (§2) |
| `run-payload` | run domain payload top level (§4) |
| `run-pending-command` | one queued command (§4.1) |
| `run-systems` | the systems map's keys for the full stack (§4.2) |
| `system-heartbeat` / `system-run` / `system-units` / `system-production` | per-system sub-dicts (§4.3–4.6) |
| `system-units-entry` / `system-production-building` / `system-production-quirks` | nested entry shapes (§4.5–4.6) |
| `meta-payload` | meta domain payload top level (§5) |
| `meta-chronicle-entry` | one chronicle record (§5.1) |
