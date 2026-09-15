## Acceptance smoke suite — the main scene loads headless (T-QA-01).
##
## Proves the acceptance lane end to end: PackedScene load, instantiate,
## mount into the live SceneTree, structural checks, clean unmount. Real
## marathon suites (1000h fast-forward T-QA-02, save round-trip T-QA-03,
## catch-up abuse T-QA-04) follow this contract against sim/ code.
extends RefCounted

const MAIN_SCENE := "res://ui/main.tscn"


func suite_name() -> String:
	return "smoke_main_scene"


func run(harness) -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if not harness.check(packed != null, "main scene %s loads headless" % MAIN_SCENE):
		return
	var instance := packed.instantiate()
	harness.check(instance is Control, "instantiated root is a Control (ui/main.gd contract)")
	harness.mount(instance)
	harness.check(instance.is_inside_tree(), "root entered the scene tree")
	harness.unmount(instance)
