## Catch-up property/fuzz suite (T-QA-04) — the pure accrual math under
## arbitrary generated inputs.
##
## Target: `CatchUpService`'s pure statics (docs/catch-up.md §1):
##   elapsed        = now_epoch − last_seen_epoch     (operands clamped ±2^40)
##   clamped        = clamp(elapsed, 0, cap)
##   applied_ticks  = clamped ÷ TICK_SECONDS          (floor)
##
## Properties (Hulk's resilience contract), every one fuzzed with PINNED
## seeds (`fuzzer_seed` — the gdUnit4 fuzzer seeds the global RNG once per
## test case, so a failure replays exactly; the seed is echoed in the
## failure report):
##
##   P1  applied_ticks >= 0 for ANY (elapsed, cap, last_seen, now) tuple
##       bounded ±2^41, both orderings incl. now < last_seen (backwards
##       clock), degenerate caps included (0, negative).
##   P2  applied_ticks <= cap ticks for the same tuples — never uncapped.
##   P3  exactness: applied == reference_model(elapsed, cap), where the
##       model is an INDEPENDENT restatement of the spec (clampi into
##       [0, maxi(cap,0)], then floor-divide) — not a call into the code.
##   P4  monotone: e1 <= e2  =>  applied(e1) <= applied(e2), fixed cap.
##   P5  idempotence: clamping then recomputing changes nothing —
##       clamp(clamp(e)) == clamp(e) and applied(clamp(e)) == applied(e);
##       repeated evaluation of the same input returns the same output
##       (purity — no hidden state).
##   P6  backwards windows (now < last_seen) always apply exactly 0.
##   P7  exact boundary transitions: the output steps ONLY at whole ticks
##       (k*TICK−1 -> k−1, k*TICK -> k) and freezes at the cap edge
##       (cap−1 vs cap vs cap+anything).
##   P8  timezone invariance: shifting BOTH timestamps by the same offset
##       (every real zone offset ±14h, plus arbitrary same-instant shifts)
##       leaves elapsed and applied_ticks bit-identical. Inputs are bounded
##       so the ±2^40 operand clamp can never engage on the shifted pair —
##       the property tests translation, not the clamp.
##   P9  DST wall-clock simulation: pairs of UTC instants spanning the
##       REAL 2026 spring-forward / fall-back transitions of
##       America/New_York and Europe/Berlin (hardcoded UTC instants,
##       IANA-verified) — elapsed_between returns the TRUE UTC delta both
##       ways, never the local-wall delta, and the local-wall delta is
##       proven != true delta for spanning windows (non-vacuity: the pair
##       really does cross an offset change).
##
## HARNESS FINDING (measured, pinned gdUnit4 v6.2.1 on Godot 4.7.2):
## `randi_range` — global AND RandomNumberGenerator — silently corrupts
## ranges beyond int32 (rangei(0, 2^32−1) yields negatives; ±2^41 operands
## yield constant 0). Every fuzzer range below therefore stays within
## ±(2^31−1), and values in the ±2^40/±2^41 spaces are COMPOSED from two
## int32-safe draws (`_wide`, exact int64 arithmetic, both halves from the
## same seeded stream — replay stays exact).
##
## Iteration counts (documented for the production log; each iteration is
## a handful of integer ops — the whole suite is sub-100ms):
##   tuples (P1–P3, P6) 600 | monotone (P4) 500 | idempotence (P5) 400
##   boundaries (P7) 400 | tz-invariance (P8) 500 | dst pairs (P9) 400
##
## The ENGINE-level form (windows through the real fast_forward, twin
## parity per window, rewind changes nothing) is the acceptance suite
## `tests/acceptance/suites/catch_up_property_windows.gd` — marathon
## runner, no framework timeout (the T-QA-03 precedent for bounded fuzz
## cycles that drive full engines).
extends GdUnitTestSuite

## R4 default cap (8h @100% linear) — used where the property statement
## fixes a realistic cap; cap-valued properties additionally fuzz the cap.
const R4_CAP := 8 * 3600

## Widest real timezone offset: UTC+14 (Kiribati) to UTC−12 — ±14h covers
## every zone the platform host could ever hand us.
const MAX_ZONE_OFFSET := 14 * 3600

## 100 years of seconds (the task's fuzz ceiling for forward jumps).
const HUNDRED_YEARS := 3153600000

## The four 2026 DST transition instants, in UTC epoch seconds (verified
## against the IANA tz database at authoring time — the offsets below are
## the zone's utcoffset strictly before/strictly after each instant).
const NY_SPRING_EPOCH := 1772953200  # 2026-03-08 07:00Z  America/New_York EST(-5) -> EDT(-4)
const NY_FALL_EPOCH := 1793512800    # 2026-11-01 06:00Z  America/New_York EDT(-4) -> EST(-5)
const BLN_SPRING_EPOCH := 1774746000 # 2026-03-29 01:00Z  Europe/Berlin    CET(+1) -> CEST(+2)
const BLN_FALL_EPOCH := 1792890000   # 2026-10-25 01:00Z  Europe/Berlin    CEST(+2) -> CET(+1)

const HOUR := 3600
const TICK := SimEngine.TICK_SECONDS  # 60
const WIDE_LOW_BITS := 21  # composition split for _wide()


## Composes a value in ±(2^bits − 1) from TWO int32-safe draws, exact in
## int64: high = draw1 % 2^(bits−21), low = draw2 % 2^21 (GDScript % is
## truncated — sign follows the dividend — so both parts stay within
## bounds and |high·2^21 + low| <= 2^bits − 1). Both halves come from the
## fuzzer's seeded stream: replay under the pinned fuzzer_seed is exact.
func _wide(fuzzer: IntFuzzer, bits: int) -> int:
	var high: int = fuzzer.next_value() % (1 << (bits - WIDE_LOW_BITS))
	var low: int = fuzzer.next_value() % (1 << WIDE_LOW_BITS)
	return high * (1 << WIDE_LOW_BITS) + low


## A non-negative span in [0, HUNDRED_YEARS] from two int32-safe draws
## (100y > 2^31 cannot be drawn directly — see the harness finding above).
func _span(fuzzer: IntFuzzer) -> int:
	var big: int = fuzzer.next_value() % 31536    # up to 100y in 1e5s units
	var small: int = fuzzer.next_value() % 100000
	return big * 100000 + small


# --- P1/P2/P3/P6: bounded tuples, both orderings, exact reference model ---


## For arbitrary (elapsed, cap, last_seen, now) with operands bounded
## ±2^40 (the service's own operand clamp) and elapsed drawn over the full
## ±2^41 composed space: never negative (P1), never uncapped (P2), exactly
## the reference model (P3), and every backwards window is exactly zero
## (P6). Both orderings of (last_seen, now) occur naturally in the draw.
func test_tuple_bounds_and_exact_reference_model(
	fuzzer_elapsed := Fuzzers.rangei(-1073741824, 1073741824),
	fuzzer_cap := Fuzzers.rangei(-7200, 172800),
	fuzzer_anchor := Fuzzers.rangei(-1073741824, 1073741824),
	fuzzer_now := Fuzzers.rangei(-1073741824, 1073741824),
	fuzzer_iterations := 600,
	fuzzer_seed := 20261001
) -> void:
	var elapsed: int = _wide(fuzzer_elapsed, 41)
	var cap: int = fuzzer_cap.next_value()
	var anchor: int = _wide(fuzzer_anchor, 40)
	var now_epoch: int = _wide(fuzzer_now, 40)

	# The COMPOSED rule (the only path the service ever takes).
	var raw := CatchUpService.elapsed_between(anchor, now_epoch)
	var applied := CatchUpService.applied_ticks_for(raw, cap)
	var cap_effective: int = maxi(cap, 0)

	# P3 — exactness against an independent restatement of the spec.
	assert_int(applied).is_equal(clampi(raw, 0, cap_effective) / TICK)
	# P1 — never negative.
	assert_int(applied).is_greater_equal(0)
	# P2 — never uncapped (a degenerate cap yields cap ticks 0).
	assert_int(applied).is_less_equal(cap_effective / TICK)
	# P6 — a backwards window (now < anchor, post-overflow-clamp) applies
	# exactly zero, whatever the magnitudes involved.
	if raw < 0:
		assert_int(applied).is_equal(0)
		assert_int(CatchUpService.clamp_elapsed_seconds(raw, cap)).is_equal(0)


# --- P4: monotonicity in elapsed, fixed cap ------------------------------------


## e1 <= e2  =>  applied(e1) <= applied(e2). Drawn as e1 plus a fuzzed
## non-negative delta (composed to the full 2^41 span) so EVERY iteration
## is an ordered pair — random independent pairs would only sometimes
## order, and adjacent-tick pairs would only exercise the flat regions.
func test_applied_ticks_monotone_in_elapsed(
	fuzzer_base := Fuzzers.rangei(-1073741824, 1073741824),
	fuzzer_gap := Fuzzers.rangei(0, 1073741824),
	fuzzer_cap := Fuzzers.rangei(-7200, 172800),
	fuzzer_iterations := 500,
	fuzzer_seed := 20261001
) -> void:
	var e1: int = _wide(fuzzer_base, 41)
	var gap: int = fuzzer_gap.next_value() % (1 << 30) * (1 << 11) + (fuzzer_gap.next_value() % (1 << 11))
	var e2: int = e1 + gap
	var cap: int = fuzzer_cap.next_value()

	var a1 := CatchUpService.applied_ticks_for(e1, cap)
	var a2 := CatchUpService.applied_ticks_for(e2, cap)
	assert_int(a1).is_less_equal(a2)
	# The step can never jump by more than the elapsed step's own ticks.
	assert_int(a2 - a1).is_less_equal((gap + TICK - 1) / TICK)


# --- P5: idempotence + purity -----------------------------------------------------


## Applying the clamp then recomputing changes nothing: the clamp is
## idempotent, the divide-through-the-clamp composition equals the direct
## call, and repeated evaluation of identical inputs returns identical
## outputs (no hidden state — the basis for the engine-level "re-apply
## the same foreground is a no-op" property in the acceptance suite).
func test_clamp_and_divide_are_idempotent(
	fuzzer_elapsed := Fuzzers.rangei(-1073741824, 1073741824),
	fuzzer_cap := Fuzzers.rangei(-7200, 172800),
	fuzzer_iterations := 400,
	fuzzer_seed := 20261001
) -> void:
	var elapsed: int = _wide(fuzzer_elapsed, 41)
	var cap: int = fuzzer_cap.next_value()

	var once := CatchUpService.clamp_elapsed_seconds(elapsed, cap)
	var twice := CatchUpService.clamp_elapsed_seconds(once, cap)
	assert_int(twice).is_equal(once)

	# Composing divide-after-clamp equals the direct rule; clamping the
	# clamped value divides to the same ticks.
	assert_int(CatchUpService.applied_ticks_for(once, cap)).is_equal(
		CatchUpService.applied_ticks_for(elapsed, cap)
	)
	assert_int(CatchUpService.applied_ticks_for(twice, cap)).is_equal(
		CatchUpService.applied_ticks_for(elapsed, cap)
	)
	# Purity: same input, same output, on a third evaluation.
	assert_int(CatchUpService.applied_ticks_for(twice, cap)).is_equal(
		CatchUpService.applied_ticks_for(once, cap)
	)


# --- P7: exact boundary transitions ----------------------------------------------


## The output steps ONLY at whole ticks and freezes at the cap edge. For
## a fuzzed cap and a fuzzed tick index k (1..cap ticks): k ticks minus
## one second applies k−1, exactly k seconds applies k; at the cap edge
## the value freezes — cap−1, cap, and cap+anything all land where the
## reference model says (the +anything case drawn over a full 100 years).
func test_boundary_transitions_are_exact(
	fuzzer_cap := Fuzzers.rangei(-7200, 172800),
	fuzzer_k := Fuzzers.rangei(0, 1000000),
	fuzzer_over := Fuzzers.rangei(0, 1073741824),
	fuzzer_iterations := 400,
	fuzzer_seed := 20261001
) -> void:
	var cap: int = fuzzer_cap.next_value()
	var cap_effective: int = maxi(cap, 0)
	var cap_ticks: int = cap_effective / TICK
	var k: int = clampi(fuzzer_k.next_value(), 1, maxi(cap_ticks, 1))
	var over: int = _span(fuzzer_over)

	if cap_ticks >= 1:
		# Tick edges: the value changes ONLY at multiples of TICK.
		assert_int(CatchUpService.applied_ticks_for(k * TICK - 1, cap)).is_equal(k - 1)
		assert_int(CatchUpService.applied_ticks_for(k * TICK, cap)).is_equal(k)
		# Unit-step property at an arbitrary interior point.
		var at: int = clampi(k * TICK + 17, 0, cap_effective)
		var step: int = CatchUpService.applied_ticks_for(at + 1, cap) - CatchUpService.applied_ticks_for(at, cap)
		assert_int(step).is_greater_equal(0)
		assert_int(step).is_less_equal(1)

	# Cap edge: freeze at cap ticks for cap and everything past it —
	# exactly-cap, +1s, +a fuzzed span up to 100 years.
	assert_int(CatchUpService.applied_ticks_for(cap_effective, cap)).is_equal(cap_ticks)
	if cap_effective > 0:
		assert_int(CatchUpService.applied_ticks_for(cap_effective + 1, cap)).is_equal(cap_ticks)
		assert_int(CatchUpService.applied_ticks_for(cap_effective + over, cap)).is_equal(cap_ticks)
		# One second SHORT of the cap is still one whole tick short of it
		# when the cap is tick-aligned (the R4 8h default is).
		if cap_effective % TICK == 0:
			assert_int(CatchUpService.applied_ticks_for(cap_effective - 1, cap)).is_equal(cap_ticks - 1)
	# The R4 default, pinned dead-on: 8h−1s -> 479, 8h -> 480, 8h+100y -> 480.
	assert_int(CatchUpService.applied_ticks_for(R4_CAP - 1, R4_CAP)).is_equal(479)
	assert_int(CatchUpService.applied_ticks_for(R4_CAP, R4_CAP)).is_equal(480)
	assert_int(CatchUpService.applied_ticks_for(R4_CAP + over, R4_CAP)).is_equal(480)


# --- P8: timezone-offset invariance -------------------------------------------------


## Shifting both timestamps by the SAME offset — every real zone offset
## (±14h, second-granular) and, separately, arbitrary same-instant shifts
## up to ±2^38 — leaves elapsed_between and the composed applied_ticks
## bit-identical. Operands are bounded to ±2^39 so |shifted| stays under
## the ±2^40 operand clamp: the property measures translation invariance
## of the UTC arithmetic, not the defensive clamp. This is the structural
## proof behind "DST/timezone are invisible" (docs/catch-up.md §5): a
## timezone is exactly a same-instant relabeling of both readings.
func test_timezone_offset_shifts_change_nothing(
	fuzzer_anchor := Fuzzers.rangei(-1073741824, 1073741824),
	fuzzer_now := Fuzzers.rangei(-1073741824, 1073741824),
	fuzzer_shift := Fuzzers.rangei(-1073741824, 1073741824),
	fuzzer_cap := Fuzzers.rangei(-7200, 172800),
	fuzzer_iterations := 500,
	fuzzer_seed := 20261001
) -> void:
	var anchor: int = _wide(fuzzer_anchor, 39)
	var now_epoch: int = _wide(fuzzer_now, 39)
	var shift: int = _wide(fuzzer_shift, 38)
	var cap: int = fuzzer_cap.next_value()

	var plain_elapsed := CatchUpService.elapsed_between(anchor, now_epoch)
	var plain_ticks := CatchUpService.applied_ticks_for(plain_elapsed, cap)

	# Arbitrary same-instant shift (the general translation property).
	var shifted_elapsed := CatchUpService.elapsed_between(anchor + shift, now_epoch + shift)
	assert_int(shifted_elapsed).is_equal(plain_elapsed)
	assert_int(CatchUpService.applied_ticks_for(shifted_elapsed, cap)).is_equal(plain_ticks)

	# The realistic timezone form: a real zone offset (±14h), both
	# readings relabeled to the same zone (drawn deterministically from
	# the shift stream; % is truncated, so negative shifts give negative
	# offsets — the western-hemisphere zones).
	var zone_offset: int = shift % (MAX_ZONE_OFFSET + 1)
	var zone_elapsed := CatchUpService.elapsed_between(anchor + zone_offset, now_epoch + zone_offset)
	assert_int(zone_elapsed).is_equal(plain_elapsed)
	assert_int(CatchUpService.applied_ticks_for(zone_elapsed, cap)).is_equal(plain_ticks)


# --- P9: DST wall-clock simulation ---------------------------------------------------


## UTC instants (A, B) spanning the four real 2026 DST transitions:
## elapsed_between returns the TRUE UTC delta in both directions — never
## the local-wall-clock delta. Non-vacuity is proven per window: the
## local-wall delta (computed from the zone's before/after offsets, the
## same fixed-offset model a wall clock in that zone shows) DIFFERS from
## the true delta exactly when the window spans the transition, so a
## regression that made elapsed wall-sensitive could not pass.
func test_dst_spanning_pairs_see_only_true_utc_deltas(
	fuzzer_back := Fuzzers.rangei(1, 1073741824),
	fuzzer_fwd := Fuzzers.rangei(1, 1073741824),
	fuzzer_iterations := 400,
	fuzzer_seed := 20261001
) -> void:
	# 50 years in seconds (1.5768e9 < 2^31: directly drawable, verified).
	var back: int = fuzzer_back.next_value() % 1576800000 + 1   # seconds before the instant
	var fwd: int = fuzzer_fwd.next_value() % 1576800000 + 1     # seconds after the instant

	# All four transitions: (instant, offset before, offset after).
	var transitions: Array = [
		[NY_SPRING_EPOCH, -5 * HOUR, -4 * HOUR],
		[NY_FALL_EPOCH, -4 * HOUR, -5 * HOUR],
		[BLN_SPRING_EPOCH, 1 * HOUR, 2 * HOUR],
		[BLN_FALL_EPOCH, 2 * HOUR, 1 * HOUR],
	]
	for t in transitions:
		var instant: int = t[0]
		var off_before: int = t[1]
		var off_after: int = t[2]

		# SPANNING window: A < instant <= B, strictly both sides.
		var a := instant - back
		var b := instant + fwd
		var true_delta := b - a
		var wall_delta := (b + off_after) - (a + off_before)
		# Non-vacuity: this pair really crosses an offset change (a wall
		# clock in the zone would show a different elapsed time).
		assert_int(wall_delta).is_not_equal(true_delta)
		assert_int(wall_delta - true_delta).is_equal(off_after - off_before)  # exactly ±1h
		# The property: the service sees ONLY the true UTC delta, both ways.
		assert_int(CatchUpService.elapsed_between(a, b)).is_equal(true_delta)
		assert_int(CatchUpService.elapsed_between(b, a)).is_equal(-true_delta)
		assert_int(CatchUpService.applied_ticks_for(CatchUpService.elapsed_between(a, b), R4_CAP)).is_equal(
			clampi(true_delta, 0, R4_CAP) / TICK
		)

		# Windows ENTIRELY on one side: wall delta == true delta there
		# (model sanity — no phantom offset inside a quiet stretch).
		var a_quiet := instant - back - fwd
		var b_quiet := instant - back
		assert_int((b_quiet + off_before) - (a_quiet + off_before)).is_equal(b_quiet - a_quiet)
		assert_int(CatchUpService.elapsed_between(a_quiet, b_quiet)).is_equal(b_quiet - a_quiet)
		var a_after := instant + fwd
		var b_after := instant + fwd + back
		assert_int((b_after + off_after) - (a_after + off_after)).is_equal(b_after - a_after)
		assert_int(CatchUpService.elapsed_between(a_after, b_after)).is_equal(b_after - a_after)
