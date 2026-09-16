## responsive_lab — the responsive demo scene (T-UI-02).
##
## Runnable via `make run-responsive`: a ResponsiveScreen instancing the
## SAME theme-grammar components in BOTH orientation slots (the whole
## point of the hybrid topology — one codebase, two arrangements), plus a
## DEBUG PANEL that forces the orientation and cycles the common test
## sizes (720x1280 phone portrait, 1280x800 Deck, 1920x1080 desktop,
## 800x1280 tablet portrait). The lab is also loaded headless by the test
## suites at all four sizes.
##
## Dev inspection hook (not a game path): CS_RESPONSIVE_SHOT=/path.png
## renders each test size for a few frames and saves
## <path>.<WxH>.png screenshots, then quits.
extends ResponsiveScreen

const FRAME_SCENE := preload("res://ui/theme/card_frame.tscn")
const FACE_SCENE := preload("res://ui/theme/card_face.tscn")

## The four common test sizes (window pixels; the design rect under the
## 720 square base + expand becomes 720x1280 / 1152x720 / 1280x720 /
## 720x1152 — R3's QA checkpoints).
const TEST_SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),  # phone portrait
	Vector2i(1280, 800),  # Steam Deck
	Vector2i(1920, 1080),  # desktop
	Vector2i(800, 1280),  # tablet portrait
]

const DEMO_CARDS: Array[Dictionary] = [
	{"name": "Brann", "role": "peasant, unremarkable", "face": &"face_peasant", "edge": Inks.EdgeForm.SOLID, "regime": &"", "seed": 101},
	{"name": "Marga", "role": "works the timber yard", "face": &"face_worker", "edge": Inks.EdgeForm.SOLID, "regime": &"", "seed": 202},
	{"name": "Wilmot", "role": "training, quietly", "face": &"face_trainee", "edge": Inks.EdgeForm.DASHED, "regime": &"", "seed": 303},
	{"name": "Ser Adela", "role": "knight of the ash camp", "face": &"", "edge": Inks.EdgeForm.SOLID, "regime": &"velvet_fist", "seed": 0},
	{"name": "Odd Hart", "role": "struck from the ledger", "face": &"", "edge": Inks.EdgeForm.STRUCK, "regime": &"", "seed": 404},
]

const DEMO_CHRONICLE: Array[Dictionary] = [
	{"class": Inks.LineClass.PLAIN, "text": "The conspiracy grows by one hungry mouth."},
	{"class": Inks.LineClass.WARN, "text": "A rider was seen counting the granary twice."},
]

var _info_label: Label
var _orientation_button: Button
var _size_button: Button
var _size_index := 0
var _orientation_mode := 0  # 0 auto, 1 portrait, 2 landscape


func _ready() -> void:
	super._ready()
	_populate_slots()
	_build_debug_panel()
	get_router().orientation_changed.connect(func(_o: int) -> void: _refresh_debug_labels())
	_refresh_debug_labels()
	_maybe_capture()


func _populate_slots() -> void:
	for slot: OrientationSlot in [get_portrait_slot(), get_landscape_slot()]:
		for card_def: Dictionary in DEMO_CARDS:
			slot.add_card(_demo_card(card_def))
		for i in DEMO_CHRONICLE.size():
			var line := slot.get_chronicle_line(i)
			line.set("line_class", DEMO_CHRONICLE[i]["class"])
			line.set("text", DEMO_CHRONICLE[i]["text"])
		for i in 3:
			slot.get_pip(i).set("amount", [1327, 15400, 2312][i])


## A composed demo specimen — the gallery's _sample_card pattern:
## CardFrame (focusable, state edge, regime hairline) + inset CardFace.
func _demo_card(def: Dictionary) -> Control:
	var frame := FRAME_SCENE.instantiate() as Control
	frame.set("edge_form", def["edge"])
	frame.set("regime_id", def["regime"])
	frame.set("misprint_seed", def["seed"])
	frame.focus_mode = Control.FOCUS_ALL
	var inset := MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	inset.offset_left = 14.0
	inset.offset_top = 16.0
	inset.offset_right = -14.0
	inset.offset_bottom = -14.0
	var face := FACE_SCENE.instantiate() as BoxContainer
	face.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	face.size_flags_vertical = Control.SIZE_EXPAND_FILL
	face.set("card_name", def["name"])
	face.set("role_line", def["role"])
	face.set("face_key", def["face"])
	inset.add_child(face)
	frame.add_child(inset)
	return frame


# --- debug panel (demo chrome — lives OUTSIDE the slots, so swaps keep it) ---------


func _build_debug_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.set_meta(&"focus_id", "debug_panel")
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var title := Label.new()
	title.theme_type_variation = &"CardTitle"
	title.text = "Responsive Lab"
	column.add_child(title)

	_info_label = Label.new()
	_info_label.theme_type_variation = &"PipLabel"
	column.add_child(_info_label)

	_orientation_button = Button.new()
	_orientation_button.text = "orientation: auto"
	_orientation_button.set_meta(&"focus_id", "debug_orientation")
	_orientation_button.pressed.connect(_cycle_orientation)
	column.add_child(_orientation_button)

	_size_button = Button.new()
	_size_button.text = "size: 720x1280"
	_size_button.set_meta(&"focus_id", "debug_size")
	_size_button.pressed.connect(_cycle_size)
	column.add_child(_size_button)


func _cycle_orientation() -> void:
	_orientation_mode = (_orientation_mode + 1) % 3
	match _orientation_mode:
		0:
			get_router().clear_forced()
		1:
			get_router().force_orientation(LayoutRouter.ScreenOrientation.PORTRAIT)
		2:
			get_router().force_orientation(LayoutRouter.ScreenOrientation.LANDSCAPE)
	_refresh_debug_labels()


func _cycle_size() -> void:
	_size_index = (_size_index + 1) % TEST_SIZES.size()
	get_window().size = TEST_SIZES[_size_index]
	_refresh_debug_labels()


func _refresh_debug_labels() -> void:
	if _info_label == null:
		return
	var size := get_router().design_size()
	var orientation := "portrait" if get_router().is_portrait() else "landscape"
	var mode: String = ["auto", "portrait", "landscape"][_orientation_mode]
	_info_label.text = "design %dx%d - %s (%s)" % [int(size.x), int(size.y), orientation, mode]
	var forced := get_router().is_forced()
	_orientation_button.text = "orientation: %s" % ("forced" if forced else "auto")
	_size_button.text = "size: %dx%d" % [TEST_SIZES[_size_index].x, TEST_SIZES[_size_index].y]


# --- dev inspection hook -------------------------------------------------------------


func _maybe_capture() -> void:
	var shot := OS.get_environment("CS_RESPONSIVE_SHOT")
	if shot.is_empty():
		return
	_capture_all_sizes.call_deferred(shot)


func _capture_all_sizes(path: String) -> void:
	for size in TEST_SIZES:
		get_router().clear_forced()
		_orientation_mode = 0
		get_window().size = size
		# Wait for the resize + the router's dwell to land the swap.
		for i in 60:
			await get_tree().process_frame
			var design := get_router().design_size()
			var want_portrait := size.x < size.y
			if get_router().is_portrait() == want_portrait and design.x > 1.0:
				break
		for i in 3:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		var out := "%s.%dx%d.png" % [path, size.x, size.y]
		var err := image.save_png(out)
		print("[responsive-lab] screenshot %s (%s)" % [out, "ok" if err == OK else "FAILED %d" % err])
	get_tree().quit(0)
