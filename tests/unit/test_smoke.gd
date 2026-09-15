## Unit smoke test — proves the gdUnit4 lane runs headless (T-QA-01).
##
## Real unit suites mirror sim/ sources (sim/economy.gd ->
## tests/unit/test_economy.gd, per docs/gdscript-conventions.md); sim/ is
## empty until T-SIM-01, so this suite only proves the harness and the
## seeded-RNG determinism rule every later sim test relies on.
extends GdUnitTestSuite


func test_harness_boots_and_asserts() -> void:
	assert_int(1 + 1).is_equal(2)


func test_seeded_rng_is_reproducible() -> void:
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 20260915
	second.seed = 20260915
	var first_rolls: Array[int] = []
	var second_rolls: Array[int] = []
	for i in 8:
		first_rolls.append(first.randi_range(0, 999))
		second_rolls.append(second.randi_range(0, 999))
	assert_array(first_rolls).is_equal(second_rolls)
