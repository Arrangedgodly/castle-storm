## Fixed-point arithmetic for economy math (T-SIM-01; consumed by T-SIM-02+).
##
## The determinism rule (docs/gdscript-conventions.md): prefer int math for
## resources. This class is HOW (docs/sim-engine.md §2):
##
##   1. Content declares rates as floats ("6.0 per worker-hour",
##      regime quirk "x0.85"). A system converts each rate ONCE, at its
##      content boundary, to an integer number of MILLI-UNITS PER HOUR
##      (`milli_from_float`). IEEE-754 `x * 1000.0` + `round()` is
##      platform-stable, so 0.85 becomes 850 on every machine.
##   2. After that boundary, everything is integer accrual in
##      MILLI-UNITS x SECONDS: each tick adds
##      `rate_milli_per_hour * SimEngine.TICK_SECONDS` to the
##      accumulator. One whole unit exists in the accumulator every
##      `UNIT_ACCUM` = 1000 * 3600 milli-unit-seconds — an exact integer
##      division, so 6/hour is EXACTLY 6 units after 60 ticks (one sim
##      hour), with zero truncation drift, forever.
##   3. Whole units are settled into `SimEngine.resources` (int);
##      remainders keep accumulating toward the next unit.
##
## Non-negative rates only (production, timers). Decay/risk curves with
## negative rates (T-SIM-05 suspicion) are hour-scaled integers from
## EconomyTunables and do not go through float conversion.
class_name SimFixed
extends RefCounted

## Milli-units per whole unit (fixed-point scale).
const MILLI: int = 1000

## Milli-unit-seconds in one whole unit at a per-hour rate:
## 1000 milli-units x 3600 seconds.
const UNIT_ACCUM: int = MILLI * 3600


## The single float→int boundary: rate per hour → integer milli-units/hour.
static func milli_from_float(value: float) -> int:
	return int(round(value * float(MILLI)))


## One tick of accrual for a per-hour rate (integer, exact).
static func accrue(accum: int, rate_milli_per_hour: int) -> int:
	return accum + rate_milli_per_hour * SimEngine.TICK_SECONDS


## Whole units settledable from an accumulator (floor; accum >= 0).
## Systems subtract `units * UNIT_ACCUM` when they bank them.
static func whole_units(accum: int) -> int:
	return accum / UNIT_ACCUM
