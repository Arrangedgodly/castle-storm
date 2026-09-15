# GDScript Conventions — Castle Storm

Binding for all game code. Engine: Godot 4.7.2-stable, GDScript only (R1).
The deterministic simulation is the product core; every rule below exists to
keep it testable headless (R2) and predictable.

## Files and naming

- File and directory names: `snake_case.gd`, `snake_case.tscn`. One scene per
  file; scene name matches its root node's purpose (`main.tscn`, not `scene1`).
- `class_name` only for globally reusable types; skip it for scene-bound
  scripts (avoid polluting global namespace).
- Script header: `##` docstring first (purpose + owning task/area), then
  `@tool`/`@icon` if ever needed, then `class_name`, then `extends`.
- Tabs for indentation (Godot default), no trailing whitespace, LF endings.

## Static typing

- Typed signatures everywhere: `func tick(dt: float) -> void`.
- Typed members: `var food := 0` / `@export var rate: float = 1.0`.
- No untyped `var x = ...` except one-liners where the type is unmistakable;
  prefer `:=` so the compiler infers and checks.
- Arrays/dictionaries typed when element type is fixed: `Array[Worker]`.

## Determinism rules (sim/ only)

- `sim/` code never touches rendering, scene tree state, or UI nodes. Pure
  logic extends `RefCounted`; a node shell drives it with a fixed step.
- No wall-clock reads inside sim (`Time.get_unix_time`, `OS.get_system_time`
  forbidden there) — time arrives as tick counts or injected timestamps.
  Offline catch-up (T-SIM-07) does timestamp math at the boundary, not in sim.
- No unseeded randomness. `RandomNumberGenerator` instances are created from
  a run seed and passed in; identical seed => identical run (T-SIM-01).
- No floating-point ordering assumptions across platforms for economy math
  where avoidable; prefer int arithmetic for resources.

## Signals and coupling

- Signals are past-tense events: `signal worker_assigned(worker, post)`.
- `sim/` emits; `ui/` listens. UI never writes sim state directly — commands
  flow down through explicit methods, state flows up through signals.
- `content/` is declarative data validated loudly at load (T-DATA-01): invalid
  content is `push_error` + refuse to start, never silently default.

## Input

- Gameplay reads only the project actions: `primary`, `secondary`, `back`,
  `pause`, `debug_fast_forward` (all bound to Any Device per R1/E14).
- Never use `ui_*` actions for gameplay — they belong to focus navigation (R3).
- Every interactive Control keeps `focus_mode` usable so pad/kb navigation
  works (input parity matrix, T-QA-05).

## Errors and failure

- `assert()` for programmer errors (invariants); asserts stay in the file —
  they run in dev builds and CI.
- `push_error()` + explicit failure return for data/runtime failures; content
  and save failures fail loudly (saves are atomic, last-good-slot per T-ARCH-03).
- Never `print()` debug leftovers in committed sim code; `print` only for
  boot-level lifecycle lines (see `ui/main.gd`).

## Tests (tests/, per R2)

- `tests/unit/`, `tests/property/` run under gdUnit4 v6.2.1 (pin exact version);
  `tests/acceptance/` runs the custom SceneTree marathon runner.
- Test files mirror source paths: `sim/economy.gd` -> `tests/unit/test_economy.gd`.
- Sim code must be testable with a plain `SceneTree` headless run — if a sim
  change only works with a rendered window, the change is wrong.

## Layout ownership

| Dir | Owns | Never contains |
|---|---|---|
| `sim/` | Deterministic economy, run lifecycle, suspicion, catch-up math | Scene access, input, theme code |
| `ui/` | Screens, components, theme grammar, LayoutRouter | Economy rules |
| `content/` | Declarative packs (units, buildings, regimes, identity pools) | Logic beyond load-time validation |
| `saves/` | Versioned schemas, atomic write/rename, slot rotation | Game rules |
| `tests/` | unit / property / acceptance suites | Shipping code |
