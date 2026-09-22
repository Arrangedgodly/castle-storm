## Unit tests for TacticalSiegePresenter (TS-02).
extends GdUnitTestSuite

const TacticalSiegeResolver := preload("res://sim/systems/tactical_siege_resolver.gd")
const TacticalSiegePresenter := preload("res://ui/screens/gameplay/tactical_siege_presenter.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_siege_presenter_tests")


func _erase_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var dirs: Array[String] = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				dirs.append(entry)
			else:
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for file_name: String in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())


func _fresh_host(run_seed: int = 5050) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_siege_presenter_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_format_null_siege_returns_safe_defaults() -> void:
	var view := TacticalSiegePresenter.format_siege_view(null)
	assert_bool(view["is_active"]).is_false()
	assert_int(view["status"]).is_equal(TacticalSiegeResolver.SiegeStatus.NOT_STARTED)
	assert_str(view["status_label"]).is_equal("Not Started")
	assert_int(view["available_tactics"].size()).is_equal(0)


func test_format_active_siege_view_model() -> void:
	var host := _fresh_host()
	var siege := TacticalSiegeResolver.new(host.engine)
	siege.start_siege(host.engine)

	var view := TacticalSiegePresenter.format_siege_view(siege)
	assert_bool(view["is_active"]).is_true()
	assert_str(view["status_label"]).is_equal("Breach in Progress")
	assert_int(view["phase_index"]).is_equal(0)
	assert_str(view["phase_name"]).is_equal("Outer Gate")
	assert_int(view["defender_hp"]).is_greater(0)
	assert_float(view["defender_hp_pct"]).is_greater(0.0)
	assert_bool(view["can_retreat"]).is_true()

	var steps: Array = view["phase_steps"]
	assert_int(steps.size()).is_equal(3)
	assert_str(steps[0]["state"]).is_equal("active")
	assert_str(steps[1]["state"]).is_equal("upcoming")
	assert_str(steps[2]["state"]).is_equal("upcoming")


func test_presenter_actions_dispatch() -> void:
	var host := _fresh_host()
	var siege := TacticalSiegeResolver.new(host.engine)
	siege.start_siege(host.engine)

	var result := TacticalSiegePresenter.execute_tactic(siege, &"archer_suppression")
	assert_bool(result.has("damage_dealt")).is_true()

	var retreat := TacticalSiegePresenter.order_retreat(siege)
	assert_bool(retreat.get("casualties_avoided", false)).is_true()

	var post_retreat_view := TacticalSiegePresenter.format_siege_view(siege)
	assert_bool(post_retreat_view["is_active"]).is_false()
	assert_str(post_retreat_view["status_label"]).is_equal("Orderly Retreat")
