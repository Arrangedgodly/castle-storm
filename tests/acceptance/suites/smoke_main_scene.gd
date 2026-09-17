## Acceptance smoke suite — the main scene IS the front door (the
## post-acceptance boot fix; was the T-QA-01 stub probe).
##
## Two lanes:
##   1. IN-PROCESS: PackedScene load, instantiate (scratch save root),
##      mount, structural checks — the boot shell booted a REAL host,
##      the title card (paper + primary chip + seeded focus) mounted,
##      and a scratch-root save survives a remount as CONTINUE.
##   2. THE USER'S WAY: a fresh child engine runs the PROJECT exactly
##      as Play/F5 does — `--headless --path <repo>` with NO scene
##      argument and a sandboxed user dir (HOME redirected; the
##      platform's user:// resolves under it) — and the suite asserts
##      the TITLE CARD mounted from that cold boot (the boot print),
##      not the old stub's print.
extends RefCounted

const MAIN_SCENE := "res://ui/main.tscn"
const STUB_PRINT := "[castle-storm] main scene ready"
const BOOT_PRINT := "[boot] title card mounted"
## Frames the child engine runs before quitting (the title mounts on
## frame 1; one margin frame).
const CHILD_FRAMES := "2"


func suite_name() -> String:
	return "smoke_main_scene"


func run(harness) -> void:
	_erase_dir("user://cs_boot_smoke")
	var packed := load(MAIN_SCENE) as PackedScene
	if not harness.check(packed != null, "main scene %s loads headless" % MAIN_SCENE):
		return
	var instance := packed.instantiate()
	instance.set("save_root", "user://cs_boot_smoke")
	harness.check(instance is Control, "instantiated root is a Control (ui/main.gd contract)")
	harness.mount(instance)
	harness.check(instance.is_inside_tree(), "root entered the scene tree")
	harness.check(instance.host != null, "the boot shell constructed the REAL GameHost")
	harness.check(String(instance.route) == "begin_fresh",
		"a fresh save root routes BEGIN_FRESH (got %s)" % String(instance.route))
	harness.check(instance._title_layer != null, "the title card mounted (paper on the table ground)")
	harness.check(instance.primary_chip() is BaseButton,
		"the route's primary affordance is a chip (one gesture)")
	var chip: Control = instance.primary_chip()
	harness.check(chip.custom_minimum_size.y >= 48.0, "the primary chip keeps the 48-unit grip")
	# A RUNNING hand saved behind the same root flips the NEXT boot to
	# CONTINUE (the title reads the run save, honestly).
	instance.host.save_all()
	harness.unmount(instance)
	var second := packed.instantiate()
	second.set("save_root", "user://cs_boot_smoke")
	harness.mount(second)
	harness.check(String(second.route) == "continue",
		"a saved live hand boots CONTINUE (got %s)" % String(second.route))
	harness.unmount(second)
	_erase_dir("user://cs_boot_smoke")
	_user_way_smoke(harness)


## The player's launch, verified end to end: a fresh child engine, the
## project with NO scene argument, a sandboxed user dir (Godot resolves
## user:// under $HOME on desktop platforms; the sandbox is wiped first
## and removed after). The boot print is the title card's, never the
## stub's. Skipped (with a printed note) on platforms without the HOME
## seam — CI runs macOS/Linux.
func _user_way_smoke(harness) -> void:
	if not (OS.get_name() == "macOS" or OS.get_name() == "Linux"):
		print("[smoke_main_scene] user-way check skipped on %s (no HOME seam)" % OS.get_name())
		return
	var sandbox := ProjectSettings.globalize_path("res://tmp/cs_boot_userway")
	_remove_tree(sandbox)
	DirAccess.make_dir_recursive_absolute(sandbox)
	var real_home := OS.get_environment("HOME")
	OS.set_environment("HOME", sandbox)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--quit-after", CHILD_FRAMES,
	], output)
	OS.set_environment("HOME", real_home)
	_remove_tree(sandbox)
	var text := "\n".join(PackedStringArray(output))
	harness.check(code == 0, "the project runs headless the user's way (exit %d)" % code)
	harness.check(text.contains(BOOT_PRINT),
		"the cold boot mounted the TITLE CARD (expected '%s...')" % BOOT_PRINT)
	harness.check(not text.contains(STUB_PRINT), "the stub print is gone")
	harness.check(text.contains("mode=begin_fresh"),
		"a fresh sandboxed user dir routes BEGIN_FRESH")


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return
	if DirAccess.dir_exists_absolute(path):
		_erase_dir(path)


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
	for file_name in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
		DirAccess.remove_absolute(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
