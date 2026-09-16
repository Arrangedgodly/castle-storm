# Save format — Castle Storm (T-ARCH-03)

The on-disk contract of `sim/save_manager.gd` (`class_name SaveManager`,
plain `RefCounted` — **not** an autoload: headless tests construct isolated
instances with their own roots, and the game host creates exactly one per
session and hands it the live engine + meta; no global state, no autoload
ordering, no scene tree). This document is the source of truth for the
format; the class header is the map. The field-level PAYLOAD schema — every
persisted field per domain, the `__i64__` encoding rules, the L2 escalation
reserve, a worked v1→v2 migration, and the save-compatibility policy — is
`docs/save-schema.md` (T-DATA-03), which is machine-checked against real
saves by `tests/unit/test_save_schema_doc.gd`. Storage is JSON on disk —
diffable in a text editor, migration-friendly, corruption-diagnosable with
any tool.

## 1. File layout

```
<root>/                     default user://saves
  run_slot_0.json           run domain — rotating ring slot 0
  run_slot_1.json           run domain — rotating ring slot 1
  run_slot_2.json           run domain — rotating ring slot 2
  meta.json                 meta domain — single file
  run_slot_N.json.tmp       transient atomic-write temp (swept on next start)
  run_slot_N.json.corrupt   quarantined unloadable file (bytes preserved)
```

Two domains saved **independently** (one corrupting must never destroy the
other — tested both directions):

- **run** — `SimEngine.to_dict()` payload; a ring of `RUN_SLOT_COUNT = 3`
  slot files written round-robin.
- **meta** — `RunMeta.to_dict()` payload (chronicle + legacy points bank);
  a single `meta.json`. Corruption policy in §8.

## 2. Envelope

Every file is one pretty-printed (tab-indented) JSON object:

```json
{
  "domain": "run",
  "schema_version": 1,
  "save_seq": 14,
  "saved_at_unix": 1760000000,
  "checksum": "6eb13e1f...",
  "payload": { ... }
}
```

| Field | Meaning |
|---|---|
| `domain` | `"run"` or `"meta"`; a file in the wrong place (meta bytes in a run slot) is a domain mismatch → quarantine |
| `schema_version` | the SAVE schema version (this file's format), independent of the engine's internal `STATE_FORMAT_VERSION`; migration contract in §7 |
| `save_seq` | run files only: monotonic save counter (0-based), used to find the newest good slot; strictly increases per successful save, survives process restarts (rescanned from slot headers) |
| `saved_at_unix` | wall-clock stamp for humans/debugging only — never read back by game logic, never hashed |
| `checksum` | SHA-256 hex of the canonical payload form (§5) |
| `payload` | the domain state, 64-bit-safe encoded (§4) |

Field order in the file is the writer's insertion order; parsers must not
rely on it (JSON semantics).

## 3. Atomicity, crash model, and write ordering

Writes go through **temp + rename**: the full text is written to
`<path>.tmp` in the same directory, then renamed over the final path
(POSIX `rename(2)` / `MoveFileEx` with replace on Windows — the final path
is never a partial file). Properties:

- A process killed **mid-write** leaves at most an orphan `.tmp`. The next
  process sweeps every `*.tmp` in the root on its first operation (any
  temp present when a fresh process starts is by definition abandoned —
  writes are synchronous and the game is single-writer; concurrent writers
  are out of scope).
- A failed save **never advances the ring or the sequence** and never
  touches the previous good slot: `save_run`/`save_meta` return `false`
  with `last_error` set, and the newest loadable state remains exactly what
  it was.
- The ring always writes the slot **after** the newest good one — i.e. it
  overwrites the oldest position; the newest good save is never the victim.
  Quarantined slots keep their ring position; the next rotation through
  their position reclaims it.

**fsync caveat (documented deviation):** Godot's `FileAccess` exposes
`flush()` (userspace `fflush`) but no `fsync()`; `SaveManager` calls flush
and relies on the atomic rename for the never-a-partial-final-file
guarantee. A post-rename OS crash can therefore lose the most recent save
(but not corrupt it) — an accepted durability bound for a single-player
game, and the property the kill-during-save tests actually prove.

**Key order is load-bearing:** Godot's `JSON.stringify` SORTS dictionary
keys, and engine state can legitimately depend on dictionary insertion
order (unit gear slots feed `state_hash()` in equip order). SaveManager
therefore serializes with its own insertion-order-preserving writer
(`_stringify_ordered`); Godot's `JSON.parse` rebuilds dictionaries in
document order, so a load reconstructs the engine's order exactly. Found
the hard way: the 500h marathon round-trip diverged until this was fixed
(regression test: `test_disk_json_preserves_dictionary_insertion_order`).

## 4. 64-bit-exact integer encoding (the T-SIM-03 verifier note)

JSON numbers are IEEE-754 float64: every integer with
`|v| <= 2^53 = 9007199254740992` round-trips exactly, and **nothing above
it does**. `rng.state` — part of the determinism contract and hashed by
`state_hash()` — is a full 64-bit value, so a naive `JSON.stringify` of the
engine dict silently corrupts it and breaks seed reproducibility.

Encoding rule (applied recursively over the payload by
`encode_exact_ints` / restored by `decode_exact_ints`):

- `|v| <= 2^53` → plain JSON number (diffable, human-readable)
- `|v| > 2^53` → `{"__i64__": "<decimal string>"}` (signed 64-bit decimal,
  exact through any JSON implementation)

The decode side only converts dictionaries with **exactly one key** named
`__i64__` holding a String — ordinary payloads that merely contain the key
alongside others pass through untouched. Tested up to int64 max
(±9223372036854775807) and negative magnitudes, both directions, and at
marathon scale in `save_marathon_roundtrip` (the drawn `rng_state` at 500h
is far outside the float-exact range and round-trips bit-exact).

## 5. Canonical form + checksum

`checksum` covers the payload in a canonical, formatter-independent form
(`SaveManager.canonical_form`):

- dictionaries: keys **sorted** (order is a serialization concern — §3 —
  and must not weaken the checksum); entries `key:value`
- arrays: element order preserved
- ints and integral floats: one token `i<decimal>` (JSON parse erases the
  int/float distinction, so both sides of a round-trip canonicalize
  identically — otherwise every save would fail its own checksum on
  reload)
- non-integral floats: `f%.17g`; strings: JSON-quoted; bool/null: `b1`/`b0`/`n`

The checksum is computed over the canonical form (not the raw file text),
so pretty-printing and key order never affect it. It catches the class of
corruption that still parses as JSON: truncation that happens to land
cleanly, edited values, tool-mangled files.

## 6. Load: latest-good, fallback, quarantine

`load_run` validates every slot (parse → domain → version bounds →
checksum), orders the valid ones by `save_seq` descending, and applies the
newest that the engine accepts. Failure handling:

- **Quarantine** (file is unloadable: parse error, empty file, truncation,
  checksum mismatch, domain mismatch, invalid/newer-than-build
  `schema_version`): renamed to `<name>.corrupt[-n]` — bytes preserved for
  postmortem, never deleted, never able to take other slots or the other
  domain down — and load falls back to the next candidate.
- **Apply refusal, no quarantine** (file parses, checksums and migrates
  fine, but the engine refuses it — e.g. a newer engine
  `STATE_FORMAT_VERSION`, or the host registered different systems): the
  slot is future-good, not corrupt; its bytes stay in place and the next
  candidate is tried. A downgrade path is intentionally NOT provided.
- **Refusal to guess**: a file whose `schema_version` is newer than the
  running build, or whose migration chain has a missing step, is refused
  loudly (`last_error`, `push_error`) — never approximately upgraded.

`load_meta` mirrors this for the single meta file (§8). When nothing is
loadable, `load_run` returns `false` with all corrupt slots quarantined.

## 7. Migration registry contract

The payload schema evolves; `schema_version` + a registry of per-step
callables walk old files forward. To bump the schema:

1. Write a migration: `static func _migrate_vN_to_vN1(payload: Dictionary)
   -> Dictionary` next to `SaveManager.example_migration_v1_to_v2` — pure
   (input untouched), additive (never drop or reinterpret old fields
   without an explicit, tested rewrite), JSON-safe in/out.
2. Register it in the manager's `migrations` dictionary keyed by the
   FROM-version (`1: Callable(SaveManager, "_migrate_v1_to_v2")`) at
   construction (the game host does this once; tests register locally).
3. Bump `CURRENT_SCHEMA_VERSION` to N+1 **in the same change** and add
   tests: chain walk (old file → new engine applies), missing-step
   refusal, future-version refusal.

The registry walks one step per registered callable from the file's
version up to the manager's `schema_version` (an instance field so tests
can exercise future chains). Any missing step, non-Dictionary return, or
file-newer-than-build → refuse loudly. The shipped
`example_migration_v1_to_v2` is the reference implementation of the
callable contract (additive stamp, unit-tested for purity and additivity)
— it is NOT registered by default because the current schema is v1; it
demonstrates the shape for the first real bump.

## 8. Dual domains + meta corruption policy

Run state (engine dict) and meta (bank + chronicle) are separate files
with separate envelopes. A corrupt run slot never touches `meta.json` and
vice versa (tested both directions). Because the spec fixes meta to a
single file (vs. the run ring), its corruption policy is: quarantine the
bytes, return a FRESH `RunMeta` (empty bank), set `last_error` — the run
slots remain loadable so the player resumes the run with a reset bank.
Meta saves are atomic like everything else, so the realistic loss window
is the same post-rename OS-crash window as §3. (If this ever becomes
unacceptable, the fix is a second meta generation file — the envelope
already carries everything needed.)

The host wiring contract (see `sim/run_meta.gd`): the host hands the SAME
`RunMeta` instance to each engine it builds; after `load_meta()` the
loaded instance is assigned to the continued engine's run system
(demonstrated in `tests/acceptance/suites/save_marathon_roundtrip.gd`).

## 9. Deliberate corruption probes (and where they are proven)

All probes live in `tests/unit/test_save_manager.gd` (34 cases) unless
noted; each asserts the invariant: **the previous good slot survives,
load falls back, corrupt bytes are preserved in quarantine.**

| Probe | Test |
|---|---|
| Process killed mid-temp-write (truncated `.tmp` left) | `test_failed_save_leaves_previous_good_slot_loadable` |
| Process killed after temp write, before rename | `test_killed_before_rename_recovers_identically` |
| Orphan `.tmp` from a previous process | `test_stale_temp_from_killed_process_is_swept` |
| Truncated slot file | `test_truncated_file_quarantined_and_falls_back` |
| Empty slot file | `test_empty_file_quarantined_and_falls_back` |
| Non-JSON garbage | `test_corrupt_json_quarantined_and_falls_back` |
| Tampered-but-parseable payload | `test_tampered_but_parseable_payload_caught_by_checksum` |
| Future save schema version | `test_future_schema_version_quarantined` |
| Newer ENGINE format version (apply refusal) | `test_engine_format_skew_falls_back_without_destroying` |
| Missing migration step | `test_missing_migration_step_refuses` |
| Migration chain walk (2 steps) + example stub | `test_migration_chain_walks_registered_steps`, `test_example_migration_stub_is_additive` |
| Meta bytes planted in a run slot | `test_domain_mismatch_quarantined` |
| Ring wraparound (5 saves) | `test_slot_ring_wraps_after_three_saves` |
| All run slots corrupt, meta intact | `test_all_run_slots_corrupt_meta_intact` |
| Meta corrupt, run intact | `test_meta_corrupt_run_intact` |
| 64-bit exactness (rng_state beyond 2^53, int64 max, negative) | `test_rng_state_survives_exact_beyond_float_precision`, `test_rng_state_max_int64_survives_exact`, `test_negative_big_int_survives_exact` |
| Insertion-order preservation (stringify-sort regression) | `test_disk_json_preserves_dictionary_insertion_order` |

Marathon scale (`tests/acceptance/suites/save_marathon_roundtrip.gd`, 41
checks): 500h full-stack state → save both domains → fresh engine + fresh
manager (the "process restart" seam — no state shared but disk) → load →
`state_hash()` and `rng_state` identical → both timelines fast-forward
50h in lockstep → second save rotates the ring → newest slot truncated on
disk → next "process" falls back to the prior generation. Replay of the
whole script reproduces the final hash. A REGIME SWEEP then repeats
save → restart → restore for EVERY pack regime flavor (production-target,
production-all, cost-all, cost-target — each forced through a single-regime
`run_start` draw, no seed luck): the restored economy's production rates and
upgrade costs must equal the pre-save quirked values, and a +10h
continuation (with an `upgrade_building` in flight, so the cost quirk is
queried) locks against the never-saved twin; distinct-value guards prove
the sweep ran non-identity production AND cost multipliers (the T-ARCH-03
verifier re-dispatch: the production system's applied regime multipliers
are serialized payload — `regime_quirks` in the production sub-dict — and
hashed state, so a quirked regime can no longer silently drop on restore).

Full-stack integrity suite (`tests/acceptance/suites/save_integrity_full.gd`,
T-QA-03, 384 checks) — the definitive zero-corruption proof on the canonical
five-system host (`_full_stack.gd`, suspicion active, catch-up anchor live):
(1) SIX milestone round-trips on one honest deterministic session — 10h,
mid-training (a specific timer captured mid-countdown), mid-telegraph (armed
countdown, lockstep carries it THROUGH the landing tick), post-crackdown
(live relief window), pre-assault (floor + odds restored, a commit whose
verdict lands identically on both timelines), 250h (chronicle grown across
restarts, final continuation = a REAL catch-up foreground window on the
restored engine, twin-parity) — each through the full process shape (fresh
SaveManager + fresh engine + loaded meta re-pointed into the run system),
asserting `state_hash`, 64-bit rng, and meta canonical equality; (2) a REAL
simulated format bump: the on-disk payload surgically renamed backward
(`rng_state`→`rng_stream`, `legacy_points`→`points`) with the checksum
honestly recomputed, loaded by a schema-v2 manager whose registered v1→v2
migration renames forward — hash equality proves the walk; plus future-version
refusal both as a lone slot (loud refusal, bytes quarantined) and as the
newest of a ring (quarantine + fallback to a real prior generation); (3)
kill-during-save chaos — 120 interleaved cycles (96 good saves + 24
kill-mid-write crash saves, ring never advancing on a failure) against a
rotating rogue (truncation/garbage/empty/double-truncation/future-version
on the newest slot, orphan-temp probes): 120/120 post-rogue loads landed on
a recorded good generation, 80 quarantines each preserving the exact corrupt
bytes, orphan temps always swept, the meta domain never touched.

Manual probes: `make save-debug` (see Makefile / `scripts/save_debug.gd`)
— run it twice to watch a continuation from disk; truncate/empty/mangle a
slot file under the save root and run again to watch quarantine + fallback
live (the tool prints the slot table and says which generation it loaded).

## 10. Debug tooling

- `make save-debug` — full-stack session, saves both domains every 10h
  (ring rotates live), prints slot table/meta/hashes, then verifies by
  reloading. Env: `CS_SAVE_HOURS` (default 100), `CS_SAVE_SEED`
  (default 20260915), `CS_SAVE_ROOT` (default `user://saves`).
- Acceptance suite above runs in `make test`.
