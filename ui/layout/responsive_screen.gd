## ResponsiveScreen — the mandatory base for every screen (T-UI-02, per R3).
##
## ScreenRoot -> SlotHost (custom Container: margin + safe-area insets)
## -> PortraitSlot / LandscapeSlot, plus the LayoutRouter that swaps them.
## This script is that template in one place: add it (or the
## responsive_lab.tscn pattern) as a screen root, and the screen is
## responsive by construction. Children compose into the ACTIVE slot via
## get_active_slot(); presenters rebind state to whichever slot the
## router made visible (R3's dumb-view/presenter split — single source
## of truth, two thin views).
##
## The SlotHost (not a MarginContainer, not bare anchors) holds the slots
## because they are ALTERNATES: a container that force-fits both into the
## same rect is the only arrangement 4.7 resizes without a fight — the
## measured failure modes are documented at slot_host.gd.
##
## Safe-area groundwork (R3 §4): insets from
## DisplayServer.get_display_safe_area(), CLAMPED to a quarter of each
## axis (never trust the report blindly — the Android-milestone caveat).
## Desktop/Deck/headless report a safe area equal to the screen: margins
## zero out.
extends Control
class_name ResponsiveScreen

const PORTRAIT_SLOT_SCENE := preload("res://ui/layout/portrait_slot.tscn")
const LANDSCAPE_SLOT_SCENE := preload("res://ui/layout/landscape_slot.tscn")
const ROUTER_SCRIPT := preload("res://ui/layout/layout_router.gd")

## Slot scenes to instance (T-UI-03, additive): screens may substitute thin
## variants of the SAME OrientationSlot script (e.g. the Spread's
## header-enabled slots) without forking any component. Defaults keep the
## T-UI-02 lab composition exactly.
@export var portrait_slot_scene: PackedScene = PORTRAIT_SLOT_SCENE
@export var landscape_slot_scene: PackedScene = LANDSCAPE_SLOT_SCENE

## Design margin inside the window (safe-area insets add on top).
@export var margin: float = 12.0

var _host: SlotHost
var _portrait_slot: Control
var _landscape_slot: Control
var _router: LayoutRouter


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_host = SlotHost.new()
	_host.name = "SlotHost"
	_host.margin = margin
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_host)

	_portrait_slot = portrait_slot_scene.instantiate() as Control
	_portrait_slot.name = "PortraitSlot"
	_host.add_child(_portrait_slot)
	_landscape_slot = landscape_slot_scene.instantiate() as Control
	_landscape_slot.name = "LandscapeSlot"
	_host.add_child(_landscape_slot)

	_router = ROUTER_SCRIPT.new() as LayoutRouter
	_router.name = "LayoutRouter"
	add_child(_router)
	_router.bind_slots(_portrait_slot, _landscape_slot)

	if is_inside_tree():
		get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()


func _on_viewport_resized() -> void:
	if _host != null:
		_host.update_safe_insets()


## The router (force/query orientation, orientation_changed signal).
func get_router() -> LayoutRouter:
	return _router


## The slot host (margin / safe insets).
func get_slot_host() -> SlotHost:
	return _host


## The slot currently visible (bind state here).
func get_active_slot() -> Control:
	if _router != null and _router.is_portrait():
		return _portrait_slot
	return _landscape_slot


func get_portrait_slot() -> Control:
	return _portrait_slot


func get_landscape_slot() -> Control:
	return _landscape_slot
