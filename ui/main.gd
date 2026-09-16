## Main scene stub — Castle Storm (T-ARCH-01).
##
## Root entry point only. Real screen topology (ScreenRoot -> SafeMargin ->
## PortraitSlot/LandscapeSlot per R3) lands with T-UI-02; The Spread home
## screen lands with T-UI-03. Gameplay code must never use [code]ui_*[/code]
## actions — use the project actions: primary, secondary, back, pause,
## debug_fast_forward.
extends Control


func _ready() -> void:
	TypeScale.ensure_applied()  # the T-QA-05 type-scale seam (boot-time)
	print("[castle-storm] main scene ready")
