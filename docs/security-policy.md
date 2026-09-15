# Security & Privacy Policy — Castle Storm (T-SEC-01)

The authoritative policy for clock manipulation, player data, and save
tampering. Owner: Captain America lane. Substrates: `sim/catch_up_service.gd`
(the clamps), `sim/save_manager.gd` (local saves), the determinism rules in
`docs/gdscript-conventions.md`. Companion docs: `docs/catch-up.md` (the full
catch-up contract, §4 of which this file supersedes in depth),
`docs/save-format.md` (file architecture), `docs/save-schema.md` (payloads).

**The stance, in one paragraph.** Castle Storm is a single-player, premium,
offline game. There is no server to trust, no leaderboard to defend, no
economy shared between players, and no account to protect. We therefore build
no DRM, no anti-cheat, and no telemetry — and we make the *design* robust to
clock manipulation by bounding what any clock state can yield, rather than
by detecting or punishing the player. Everything the game writes stays on
the player's machine. These are commitments, not gaps: the enforcement
section (§5) wires the testable claims into CI so future creep fails `make
test`.

## 1. Clock policy

### 1.1 Inventory: every surface that touches a clock

Every place the codebase reads, stores, or computes time, as of T-SEC-01
(each row verified against the code, not assumed):

| # | Surface | What it does with time | Verified property |
|---|---|---|---|
| 1 | **Sim tick counter** (`SimEngine.tick_count`, `TICK_SECONDS = 60`) | The ONLY time inside the simulation: 1 tick = 1 sim-minute, advanced by `tick()`/`fast_forward(n)`. No date, no wall clock, no timezone. | Deterministic from seed; the oracle (`state_hash`) covers it. |
| 2 | **Catch-up service** (`sim/catch_up_service.gd`) | Consumes INJECTED UTC epoch timestamps (`apply(engine, meta, now_epoch)`, `mark_seen(meta, now_epoch)`); the host owns the clock, sim never reads one. Elapsed is clamped to `[0, cap]` (8h default) before dividing into ticks. | Zero `Time.*`/`OS.*` reads in the file (code-scan asserted); the clamps are §1.2's envelope. |
| 3 | **Away anchor** (`RunMeta.last_seen_epoch`) | UTC epoch SECONDS, meta save domain. `0` = first-launch sentinel (never accrues off it). Refreshed to `now` on every `apply`, even rewound ones. | Tolerant read (absent key → sentinel); round-trip + pre-feature saves tested. |
| 4 | **Suspicion decay** (`sim/systems/suspicion_system.gd`) | **Sim-time only.** Decay (`−5/h`), tier-2 decay (`−2.5/h`), telegraph countdowns, relief/re-arm/decay-pause windows are all measured in TICKS via `engine.tick_count` and `SimEngine.TICK_SECONDS`. The system has no path to a wall clock. | Code-scan: zero `Time.*`/`OS.*` in the file; behavior: the meter moves exactly N ticks' worth whether those ticks were live, fast-forwarded, or catch-up-replayed (twin parity, §5). |
| 5 | **Save envelope stamp** (`saved_at_unix` in `sim/save_manager.gd`) | A UTC epoch write-only stamp for humans/debugging on every envelope. | Never read back by any game logic, never hashed — the token appears in exactly ONE line of game code (the write). Code-scan asserted. |
| 6 | **Platform host** (future T-PERF-01; today `ui/main.gd` is a stub) | The only layer permitted to read a clock: it reads the OS clock, converts to UTC epoch, and injects it into surface #2/#3. | `ui/` contains zero clock reads today (code-scan asserted); the boundary is the gdscript-conventions determinism rule ("time arrives as tick counts or injected timestamps"). |

That is the complete list. Anything else that ever wants a timestamp must
arrive as an injected UTC epoch across a host boundary, or it fails the
code-scan in §5.

### 1.2 The player's cheating envelope

What a player can and cannot extract by manipulating the device clock. The
clamps ARE the policy — there is no detection code, no hidden state, no
punishment path.

**Backwards clock (`now < anchor`).** `elapsed` is negative → clamped to
**0**: no accrual, no resource loss, no state change (`state_hash`
bit-identical). The rewind is *announced*, not punished: one
`catch_up_clock_rewound` event plus a wry chronicle line ("The castle clock
was found wound backwards. The steward said nothing, and the stores kept
their count."). The anchor follows `now` anyway — the service consumes
timestamps, never extrapolates them. A rewind gains the player nothing and
costs them nothing.

**Forward jump (any size).** Capped at 8h (480 ticks). A 100-year jump
awards exactly what one overnight-away awards. The capped gap replays
through the REAL engine (`fast_forward`), so the award is bounded not just
in quantity but in *shape*: resources by the real curves, arrivals stacking
as gate offers, training completing, and **suspicion accruing by the real
heat profile** — a cheater's estate gets louder, not just richer.

**Rewind-then-forward (the classic idle-cheat cycle).** The anchor followed
the rewound time, so when the clock normalizes the measured "elapsed"
includes the rewind span — still clamped to one 8h window per
foreground-to-foreground gap. Repeating the cycle is linear in effort: N
cycles yield at most N × 8h. There is no compounding, no carry, no way to
bank windows: `applied_ticks_for(elapsed, cap) ≤ cap ÷ 60` for every
representable `elapsed`, including int64 extremes (operands are clamped to
±2^40 before subtraction, so even fuzzed-crazy timestamps cannot overflow
into an uncapped result).

**The envelope, stated once:** per away window, the maximum yield of any
clock manipulation is exactly one capped window — the same award as leaving
the game closed overnight. Every accruable quantity is bounded per window by
the engine's own curves (which T-SIM-08 tunes as the balance surface);
suspicion pressure accrues under the same rules, so the fastest
clock-cheater arrives at the crackdown telegraph sooner. We consider a
bounded nuisance in a single-player premium game acceptable by design.

Sub-tick honesty detail: remainders are discarded (a 59-second window
applies 0 ticks; the anchor snaps to `now`), so the error is bounded below
one sim-minute per window and never accumulates — this protects honest
players from drift; cheaters gain nothing from it either.

### 1.3 Why we accept the envelope (and reject the theater)

The town hall decided this (town-hall.md: "Clock policy: single-player
game; clock manipulation treated as design nuisance (clamp backwards time,
cap catch-up), no DRM/anti-cheat"; Cap's risk row: "Offline, no accounts,
no telemetry = privacy by default"). The reasoning, on record:

1. **No shared surface to defend.** No multiplayer, no accounts, no cloud
   sync, no backend, no leaderboards (explicit non-goals). A clock cheat
   harms only the cheater's own experience.
2. **DRM/anti-cheat is theater here.** Client-side detection in an offline
   game is a puzzle for the determined and a false accusation risk for the
   unlucky (a dead CMOS battery, a timezone trip, an NTP correction are all
   indistinguishable from manipulation). Since we cannot punish, detection
   would only add code, secrets to keep, and UI hostility for zero gain.
3. **Premium, not metered.** The 8h cap at 100% accrual with no rate term
   (validator-pinned `offline_rate = 1.0`) exists so the away loop is
   generous to honest players; a stingier cap to spite cheaters would tax
   the honest. Diminishing offline curves pair with ad-watching — rejected
   (docs/catch-up.md §1).
4. **The bounds are cheap and total.** Two integer clamps (plus overflow
   guards) bound every clock state representable on a 64-bit machine, are
   property-fuzzable as pure functions, and carry zero privacy or
   false-positive cost. Detection cannot beat that economics.

## 2. Privacy — data inventory

**Everything the game writes stays on the player's machine.** The complete
inventory of player data:

| Data | Where | Leaves the device? |
|---|---|---|
| Run saves (engine state, resources, roster, RNG state) | `user://saves/` ring of 3 slots, JSON | Never |
| Meta save (chronicle, legacy bank, away anchor) | `user://saves/meta.json`, JSON | Never |
| Quarantined corrupt saves | renamed `.corrupt[-n]` alongside the above | Never |
| Settings (future) | `user://` (Godot's per-user dir) | Never |

That is all of it. There are:

- **No accounts** — nothing to log into, no identity, no email.
- **No network calls of any kind** — no HTTP, no sockets, no telemetry, no
  analytics, no crash reporting, no push notifications (explicit non-goal).
- **No identifiers** — no device IDs, no ad IDs, no session IDs, not even
  an anonymous install GUID. The RNG seed is a game concept, not a tracker.
- **No personal information** — the game does not know the player's name,
  locale beyond engine defaults, or anything about them.

**Verification (grep evidence, 2026-09-15):** a case-sensitive scan over
the 28 `.gd` files in the game trees (`sim/` 15, `ui/` 1, `content/` 11,
`scripts/` 1; `tools/` holds only the vendored engine binary, no scripts)
for network APIs and process escapes — `HTTPClient`, `HTTPRequest`,
`StreamPeer*`, `PacketPeer*`, `WebSocket*`, `MultiplayerPeer`,
`ENetConnection`, `ENetMultiplayerPeer`, `UDPServer`, `TLSOptions`,
`JavaScriptBridge`, `OS.shell_open`, `OS.execute`, `OS.create_process`,
`Engine.get_singleton`, `.create_client`, `.create_server`,
`.connect_to_host`, `.open_url` — returned **zero hits**. A second scan for
telemetry vocabulary (`telemetry`, `analytics`, `crashlytics`,
`gamecenter`, `gameservices`, any case) also returned **zero hits**. A
naive case-insensitive grep for `http|unix|socket|enet` produces three
false positives worth documenting so nobody re-trips on them:
`"saved_at_unix"` (a field NAME about UTC epoch seconds — no Unix socket
involved) and two occurrences of `SceneTree` (contains the letters
"enet"; it is Godot's scene-tree class, present in the acceptance runner
via `extends SceneTree`). The precise patterns above and in §5 are the
authoritative form of the claim.

This scan is not a one-time audit: it is wired into CI as a test (§5), so
a future "quick analytics call" or cloud-save experiment fails `make test`
until this document and the town-hall stance are revisited first.

## 3. Save tampering stance

**Players may edit their saves. It is their game, on their machine, for
their own single-player experience.** Hand-editing `user://saves/*.json`
to give yourself ten thousand food is the same moral category as using a
board game's pieces as toys: outside the designed game, harming no one
else. We do not obfuscate, encrypt, or sign saves, and we will not.

What the save architecture DOES protect against is **corruption, not
tampering** — the distinction is intent-independence (town-hall.md:
"saves: local only, versioned schema with migrations, atomic writes,
rotating slots"):

- **Accidental corruption** (truncated write, disk rot, kill-during-save,
  a JSON typo from a curious player): caught by the checksum and version
  bounds; the file is quarantined (renamed, bytes preserved, never
  deleted) and the ring falls back to the newest good slot.
- **Version refusal** (a save from a newer build): refused loudly — never
  silently mis-parsed. This protects the player's data from OUR code, not
  our code from the player.
- **Deliberate tampering with a consistent envelope** (payload edited,
  checksum recomputed, versions valid): loads and plays. That is the
  stance, not an oversight. The consequence is bounded by the same
  single-player logic as §1: a tampered run is still governed by the
  engine's curves and the suspicion meter on every subsequent tick.

One honest note on consequences: a tampered save that violates invariants
the engine assumes (e.g., a unit def id that no longer exists) is handled
the same way bad content is — loud skips/refusals per system, never silent
garbage (the T-SIM-03/T-ARCH-03 discipline).

## 4. What we would revisit if multiplayer/cloud ever lands

Explicit non-goals today (town-hall.md): no multiplayer, no accounts, no
cloud sync, no backend. If ANY of those ever lands, this policy expires in
part and must be re-argued at a town hall, because its premises die:

- **Cloud sync / accounts** → the privacy inventory (§2) gains a
  transmission surface; the no-network CI tripwire must be re-scoped from
  "zero network code" to an allowlisted endpoint contract, and a data
  inventory for what syncs becomes mandatory.
- **Multiplayer or shared leaderboards** → the clock envelope (§1.2)
  stops being a private nuisance and becomes an unfairness vector; the
  right shape would be server-authoritative time for the SHARED surface
  only, never client-side detection — and the town-hall rejection of
  client-side anti-cheat theater (§1.3) should still hold for the
  single-player content.
- **Competitive/meta progression across players** → save tampering (§3)
  gains a victim; signed saves or server-side progression for the shared
  layer would need their own task and policy. Until then, adding crypto to
  local saves would be pure inconvenience theater.

Until such a town hall happens, the enforcement below is the contract.

## 5. Verification — the policy is testable, and tested

`tests/unit/test_security_policy.gd` (gdUnit4, runs in `make test`)
asserts the testable claims of this document. The code-scan tests are
TRIPWIRES wired into CI: future creep — a network class, a wall-clock read
in `sim/`, a second use of the save stamp — fails the suite with the
offending file and line. (They scan comment-stripped code so documentation
comments stay free; they are tripwires, not sandboxes — code review
remains the second layer.)

| Policy claim | Test |
|---|---|
| Clamp envelope holds under adversarial elapsed (int64 extremes, ±2^62 composed through `elapsed_between` → `applied_ticks_for`, degenerate caps) | `test_clamp_envelope_holds_under_adversarial_elapsed` |
| Repeated manipulation cycles on a real engine: every window ≤ 480 ticks, total exactly N × 480, backwards cycles cost nothing (hash-identical) | `test_cheating_envelope_bounded_per_away_window` |
| Repeated capped windows accrue suspicion by the real heat profile — the cheater's estate gets louder | `test_repeated_capped_windows_raise_suspicion_loud_estate` |
| Quiet-estate away windows move the meter by the exact sim rule (−5/h), live-tick twin parity | `test_away_window_suspicion_is_engine_ruled_exact` |
| Suspicion system has no `Time.*`/`OS.*` reads (sim-time-only decay, by code-scan) | `test_suspicion_system_reads_no_wall_clock` |
| Whole `sim/` tree: the ONLY wall-clock read is the single allowlisted UTC `saved_at_unix` write line in save_manager.gd | `test_sim_tree_wall_clock_reads_are_the_documented_set` |
| `saved_at_unix` never read back (exactly one occurrence in game code) | `test_save_stamp_is_write_only` |
| Zero network APIs / process escapes across sim, ui, content, scripts (non-vacuous: 20+ files, anchor files present) | `test_zero_network_apis_in_game_code` |
| Tampering stance: broken checksum → refused loudly; deliberate edit with recomputed checksum → loads (player's prerogative); future version → refused loudly | `test_tampering_stance_checksig_refuses_recompute_loads_future_refuses` |

The behavioral clamp/rewind/cap tests also live in
`tests/unit/test_catch_up_service.gd` (17 cases) and
`tests/acceptance/suites/marathon_catch_up_gap.gd` (25 checks) — this
suite adds the adversarial extremes, the multi-cycle envelope, and the
structural scans on top.
