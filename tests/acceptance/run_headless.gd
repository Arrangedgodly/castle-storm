## Headless acceptance marathon runner — Castle Storm (T-QA-01, per R2).
##
## Usage:
##     godot --headless --path . -s res://tests/acceptance/run_headless.gd
## Optional environment:
##     CS_ACCEPTANCE_SEED=<int>  seeds the global RNG before the first suite
##
## Suite contract — every script in res://tests/acceptance/suites/*.gd:
##     extends RefCounted
##     func suite_name() -> String
##     func run(harness) -> void
## The harness handed to run() provides:
##     harness.check(condition: bool, label: String) -> bool
##     harness.fail(label: String) -> void
##     harness.mount(node: Node) -> void   # adds to root; _ready runs now
##     harness.unmount(node: Node) -> void # queue_free; flushed before next suite
## A suite may be synchronous or a coroutine (the runner awaits run()).
##
## Marathon properties (this is why acceptance does not run under gdUnit4):
## no framework timeout — the 1000h fast-forward (T-QA-02) and save
## round-trip / kill-during-save (T-QA-03) suites may take as long as they
## need. One suite runs per engine frame so unmounted (queue_free'd) nodes
## flush before the next suite starts. Exit code: 0 all green, 1 any failure.
extends SceneTree


func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	const SUITE_DIR := "res://tests/acceptance/suites"

	var _suites: Array[String] = []
	var _failures: Array[String] = []
	var _checks := 0
	var _suite_checks := 0
	var _current := "<none>"
	var _busy := false

	func _ready() -> void:
		TypeScale.ensure_applied()  # the T-QA-05 type-scale seam (boot-time)
		var env_seed := OS.get_environment("CS_ACCEPTANCE_SEED")
		if not env_seed.is_empty():
			seed(env_seed.to_int())
			print("[acceptance] global seed %d (CS_ACCEPTANCE_SEED)" % env_seed.to_int())
		_suites = _discover()
		var names: Array[String] = []
		for path in _suites:
			names.append(path.get_file().get_basename())
		print("[acceptance] %d suite(s): %s" % [_suites.size(), ", ".join(names)])


	func _process(_delta: float) -> void:
		# RE-ENTRY GUARD (T-PERF-02's async suites exposed the hole): a
		# suspended `await _run(path)` leaves _process callable again next
		# frame, which popped the NEXT suite while the first still ran
		# (interleaved checks, and _finish() could quit the process under a
		# live coroutine). One suite in flight at a time — synchronous
		# suites (all of the originals) still complete within their frame,
		# so the per-suite cadence is unchanged for them.
		if _busy:
			return
		if not _suites.is_empty():
			var path: String = _suites.pop_front()
			_busy = true
			await _run(path)
			_busy = false
			return
		set_process(false)
		_finish()


	func _discover() -> Array[String]:
		var found: Array[String] = []
		var dir := DirAccess.open(SUITE_DIR)
		if dir == null:
			push_error("[acceptance] cannot open %s" % SUITE_DIR)
			return found
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			if entry.ends_with(".gd") and not entry.begins_with("_"):
				found.append("%s/%s" % [SUITE_DIR, entry])
			entry = dir.get_next()
		dir.list_dir_end()
		found.sort()
		return found


	func _run(path: String) -> void:
		_current = path.get_file().get_basename()
		_suite_checks = 0
		var failures_before := _failures.size()
		print("[acceptance] run %s" % _current)
		var script := load(path)
		if script == null or not script.can_instantiate():
			fail("suite script cannot be loaded/instantiated: %s" % path)
			return
		var suite: Variant = script.new()
		if not (suite is RefCounted) or not suite.has_method("suite_name") or not suite.has_method("run"):
			fail("suite %s breaks the contract (extends RefCounted; suite_name(); run(harness))" % path)
			return
		await suite.run(self)
		if _failures.size() == failures_before:
			print("[acceptance] PASS %s (%d checks)" % [_current, _suite_checks])


	func check(condition: bool, label: String) -> bool:
		_checks += 1
		_suite_checks += 1
		if condition:
			return true
		_failures.append("%s: %s" % [_current, label])
		printerr("  FAIL %s" % label)
		return false


	func fail(label: String) -> void:
		check(false, label)


	func mount(node: Node) -> void:
		get_tree().root.add_child(node)


	func unmount(node: Node) -> void:
		node.queue_free()


	func _finish() -> void:
		var code := 0
		if not _failures.is_empty():
			code = 1
			printerr("[acceptance] failed check(s):")
			for entry in _failures:
				printerr("  - %s" % entry)
		print(
			"[acceptance] %d check(s), %d failure(s) -> exit %d"
			% [_checks, _failures.size(), code]
		)
		get_tree().quit(code)
