## End-to-End Acceptance Suite for Castle Storm Redesign (T-08).
##
## Validates the entire player journey from boot to village production,
## military training, siege forecasting, and assault execution.
extends GdUnitTestSuite

const GameplayScreen := preload("res://ui/screens/gameplay/gameplay_screen.gd")
const GameplayPresenter := preload("res://ui/screens/gameplay/gameplay_presenter.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_redesign_e2e")


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


func _fresh_host(run_seed: int = 12345) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_redesign_e2e/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_end_to_end_gameplay_lifecycle() -> void:
	var host := _fresh_host()
	var screen := GameplayScreen.new()
	screen.host = host

	# 1. Verify Initial State
	var hud_data: Dictionary = GameplayPresenter.get_hud_data(host)
	assert_str(String(hud_data.get("leader_name", ""))).is_not_empty()
	assert_int(int(hud_data.get("food_count", 0))).is_greater_equal(0)

	# 2. Roster Interaction: Accept Offer if present, or assign peasant
	var roster_data: Dictionary = GameplayPresenter.get_roster_data(host)
	var offers: Array = roster_data.get("offers", [])
	if not offers.is_empty():
		var offer_uid: int = int(offers[0].get("uid", 0))
		GameplayPresenter.accept_offer(host, offer_uid)
		host.advance_ticks(1)
		screen.refresh()

	# 3. Peasant to Worker promotion
	roster_data = GameplayPresenter.get_roster_data(host)
	var idle_peasants: Array = roster_data.get("idle_peasants", [])
	if not idle_peasants.is_empty():
		var peasant_uid: int = int(idle_peasants[0].get("uid", 0))
		GameplayPresenter.assign_peasant_to_worker(host, peasant_uid)
		host.advance_ticks(1)
		screen.refresh()

	# 4. Village Assignment: Worker to Farm
	var village_data: Dictionary = GameplayPresenter.get_village_data(host)
	var idle_workers: int = int(village_data.get("idle_workers", 0))
	var buildings: Array = village_data.get("buildings", [])
	if idle_workers > 0 and not buildings.is_empty():
		var building_id: StringName = buildings[0].get("id", &"")
		GameplayPresenter.assign_worker_to_building(host, building_id)
		host.advance_ticks(1)
		screen.refresh()

	# 5. Production Tick Advancement
	var initial_food: int = host.engine.get_resource(&"food")
	host.advance_ticks(120)  # Advance 2 sim hours
	screen.refresh()
	var later_food: int = host.engine.get_resource(&"food")
	assert_int(later_food).is_greater_equal(initial_food)

	# 6. Siege Intelligence and Forecast
	var siege_data: Dictionary = GameplayPresenter.get_siege_data(host)
	assert_int(int(siege_data.get("garrison_power", 0))).is_greater(0)
	assert_object(screen.siege_panel.assault_button).is_not_null()

	# 7. Commit Assault Trigger
	GameplayPresenter.commit_assault(host)
	var pending_kinds: Array[StringName] = []
	for cmd in host.engine._pending:
		pending_kinds.append(cmd.kind)
	assert_bool(pending_kinds.has(&"commit_assault")).is_true()

	screen.free()


func test_fast_forward_simulation_controls() -> void:
	var host := _fresh_host()
	var screen := GameplayScreen.new()
	screen.host = host

	var initial_ticks: int = host.engine.tick_count
	screen._on_advance_1h()
	assert_int(host.engine.tick_count).is_equal(initial_ticks + 60)

	screen._on_advance_24h()
	assert_int(host.engine.tick_count).is_equal(initial_ticks + 60 + 1440)

	screen.free()


func test_tab_container_panels_exist_and_render() -> void:
	var screen := GameplayScreen.new()
	assert_int(screen.tab_container.get_tab_count()).is_greater_equal(1)
	assert_object(screen.village_panel).is_not_null()
	assert_object(screen.roster_panel).is_not_null()
	assert_object(screen.siege_panel).is_not_null()
	screen.free()
