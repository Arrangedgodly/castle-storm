## PipMark — one resource's rail notation (T-UI-01).
##
## The table-edge resource notation from the design brief ("resources
## are pip marks along the table edge"): drawn glyph (shape + icon),
## abbreviated idle-scale amount (Inks.abbreviate_amount), and an
## optional name label — the textual channel of the colorblind-safe
## triple encoding. Rail orientation (top rail portrait / bottom edge
## landscape, R3) is the parent's business; the pip is the same
## component everywhere. Minimum size honors the touch grip.
extends HBoxContainer

## Which resource this pip counts.
@export var kind: Inks.ResourceKind = Inks.ResourceKind.FOOD:
	set(value):
		kind = value
		_rebuild()

## Current amount (idle scale; rendered abbreviated).
@export var amount: int = 0:
	set(value):
		if amount != value:
			amount = value
			_refresh()

## Name label on/off — the accessibility text channel (default ON; a
## tight rail may drop it, leaving shape + glyph + numerals).
@export var show_label: bool = true:
	set(value):
		if show_label != value:
			show_label = value
			_rebuild()

## Glyph redundant color channel per resource (never the sole encoder).
@export var glyph_ink: Color = Inks.RED:
	set(value):
		glyph_ink = value
		_sync_glyph()

const GLYPH_SCENE := preload("res://ui/theme/pip_glyph.tscn")

var _glyph: Control
var _amount_label: Label
var _name_label: Label


func _ready() -> void:
	_rebuild()


func _init() -> void:
	## Touch grip floor via custom_minimum_size (NOT a _get_minimum_size
	## override — that would shadow BoxContainer's child accounting): a
	## pip is a collectable target (>= 48x48 + label room).
	custom_minimum_size = Vector2(Inks.TOUCH_GRIP_MIN + 24.0, Inks.TOUCH_GRIP_MIN)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_glyph = GLYPH_SCENE.instantiate()
	_glyph.custom_minimum_size = Vector2(38, 38)
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_glyph.set("kind", kind)
	_glyph.set("glyph_ink", glyph_ink)
	add_child(_glyph)
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_amount_label = Label.new()
	_amount_label.theme_type_variation = &"Numerals"
	_amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_amount_label)
	_name_label = Label.new()
	_name_label.theme_type_variation = &"PipLabel"
	_name_label.text = Inks.pip_label(kind) if show_label else ""
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_name_label)
	add_child(column)
	_refresh()


func _refresh() -> void:
	if _amount_label != null:
		_amount_label.text = Inks.abbreviate_amount(amount)
	if _name_label != null:
		_name_label.text = Inks.pip_label(kind) if show_label else ""


func _sync_glyph() -> void:
	if _glyph != null:
		_glyph.set("glyph_ink", glyph_ink)
