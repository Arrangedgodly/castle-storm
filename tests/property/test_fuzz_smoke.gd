## Property/fuzz smoke test — proves the gdUnit4 fuzzer lane runs headless (T-QA-01).
##
## Pattern for T-QA-04 (catch-up properties): every fuzzed test pins
## `fuzzer_iterations` and `fuzzer_seed` so a failure replays exactly (the
## seed is echoed in the failure report). The property here is a placeholder
## for T-SIM-07's catch-up math — linear accrual clamped to [0, 8h] @100%
## (R4 tunables): never negative, never uncapped, for any elapsed time
## including a backwards clock.
extends GdUnitTestSuite

## R4: offline catch-up caps at 8h @100% linear accrual.
const CATCHUP_CAP_H := 8

## Placeholder for T-SIM-07's sim/ implementation — clamps elapsed hours to
## the R4 catch-up window at 100% linear accrual.
func _accrued_hours(elapsed_hours: int) -> int:
	return clampi(elapsed_hours, 0, CATCHUP_CAP_H)


## gdUnit4 fuzz contract: the parameter receives the Fuzzer instance and the
## suite runs once per `fuzzer_iterations`, drawing `fuzzer.next_value()`
## each run (per the addon's own docstring examples). The pinned seed makes
## every generated input replayable.
func test_accrual_is_bounded_for_any_elapsed_time(
	fuzzer := Fuzzers.rangei(-48, 24 * 30),
	fuzzer_iterations := 64,
	fuzzer_seed := 20260915
) -> void:
	var elapsed_hours: int = fuzzer.next_value()
	var accrued := _accrued_hours(elapsed_hours)
	assert_int(accrued).is_greater_equal(0)
	assert_int(accrued).is_less_equal(CATCHUP_CAP_H)
	if elapsed_hours >= 0:
		assert_int(accrued).is_less_equal(elapsed_hours)
