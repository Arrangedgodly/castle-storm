## Unit tests for the fixed-point accrual seam (T-SIM-01; T-SIM-02's math).
## Mirrors sim/sim_fixed.gd. Locks the determinism arithmetic: exact
## integer accrual, no truncation drift, single float->milli boundary.
extends GdUnitTestSuite


func test_float_boundary_converts_to_milli_exactly() -> void:
	assert_int(SimFixed.milli_from_float(6.0)).is_equal(6000)
	assert_int(SimFixed.milli_from_float(0.85)).is_equal(850)
	assert_int(SimFixed.milli_from_float(0.1)).is_equal(100)
	assert_int(SimFixed.milli_from_float(1.08)).is_equal(1080)
	assert_int(SimFixed.milli_from_float(5.5)).is_equal(5500)


func test_production_rate_is_exact_per_hour() -> void:
	# R4-shaped example: farm 6 food/hour/worker, one worker.
	var rate := SimFixed.milli_from_float(6.0)
	var accum := 0
	for i in SimEngine.TICKS_PER_SIM_HOUR:
		accum = SimFixed.accrue(accum, rate)
	assert_int(SimFixed.whole_units(accum)).is_equal(6)
	assert_int(accum % SimFixed.UNIT_ACCUM).is_equal(0) # zero drift, exact


func test_fractional_rates_accumulate_without_truncation() -> void:
	# 0.1/hour: no whole unit for 9 hours, the 10th completes it exactly.
	var rate := SimFixed.milli_from_float(0.1)
	var accum := 0
	for i in 9 * SimEngine.TICKS_PER_SIM_HOUR:
		accum = SimFixed.accrue(accum, rate)
	assert_int(SimFixed.whole_units(accum)).is_equal(0)
	accum = SimFixed.accrue(accum, rate) # one more tick (not needed)...
	# 10 full hours:
	accum = 0
	for i in 10 * SimEngine.TICKS_PER_SIM_HOUR:
		accum = SimFixed.accrue(accum, rate)
	assert_int(SimFixed.whole_units(accum)).is_equal(1)
	assert_int(accum % SimFixed.UNIT_ACCUM).is_equal(0)


func test_multiplier_quirks_stay_rational() -> void:
	# Regime quirk x0.85 on 6/hour: 5.1/hour -> 5 whole/hour, the 0.1
	# remainder carries toward the next unit (never lost).
	var rate := SimFixed.milli_from_float(6.0 * 0.85)
	var accum := 0
	for i in SimEngine.TICKS_PER_SIM_HOUR:
		accum = SimFixed.accrue(accum, rate)
	assert_int(SimFixed.whole_units(accum)).is_equal(5)
	var remainder := accum - 5 * SimFixed.UNIT_ACCUM
	assert_int(remainder).is_equal(360_000) # exactly 0.1 unit in milli-unit-seconds
	for i in 9 * SimEngine.TICKS_PER_SIM_HOUR: # 10 hours total
		accum = SimFixed.accrue(accum, rate)
	assert_int(SimFixed.whole_units(accum)).is_equal(51) # 5.1 x 10, exact


func test_suspicion_scale_rates_are_hour_exact() -> void:
	# R4 decay magnitude as a positive accrual check: 5.0/hour -> 5 per hour.
	var rate := SimFixed.milli_from_float(5.0)
	var accum := 0
	for i in SimEngine.TICKS_PER_SIM_HOUR:
		accum = SimFixed.accrue(accum, rate)
	assert_int(SimFixed.whole_units(accum)).is_equal(5)


func test_many_workers_scale_linearly_and_exactly() -> void:
	# 7 workers x 0.85-quirked 6/hour farm for 1000 hours, one fast loop:
	# 35.7/hour x 1000h = 35,700 units exactly.
	var rate := 7 * SimFixed.milli_from_float(6.0 * 0.85)
	var accum := 0
	for i in 1000 * SimEngine.TICKS_PER_SIM_HOUR:
		accum = SimFixed.accrue(accum, rate)
	assert_int(SimFixed.whole_units(accum)).is_equal(35_700)
	assert_int(accum % SimFixed.UNIT_ACCUM).is_equal(0)
