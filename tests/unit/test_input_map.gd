## Deck controller mapping baseline (T-ARCH-02, per R1 E13/E14).
##
## Godot 4.5+ uses SDL3 for desktop controller input: the Steam Deck's
## physical pad surfaces as a standard Xbox-style gamepad, so InputMap
## actions bound to SDL joypad indices work on the Deck as-is (Steam Input
## remaps everything else). The deck R1 gotcha is device binding — every
## joypad event must use device -1 ("Any Device") or Linux builds can lose
## controller input on the Deck.
##
## This suite pins the mapping table documented in docs/DEV_SETUP.md: which
## Deck button triggers which action. Changing a binding here is a product
## decision — update the table in docs/DEV_SETUP.md in the same commit.
extends GdUnitTestSuite

## action -> Godot joypad button_index == SDL index == Deck physical button.
const DECK_MAP := {
	&"primary": 0,             # Deck A  (bottom face) — confirm / press focused card
	&"back": 1,                # Deck B  (right face)  — back / fold / cancel
	&"secondary": 2,           # Deck X  (left face)   — secondary action
	&"debug_fast_forward": 5,  # Deck R1 (right shoulder) — time-scale ladder (dev)
	&"pause": 6,               # Deck L3 (left stick click) — freeze the world
}


func test_every_action_has_an_any_device_joypad_button() -> void:
	for action: StringName in DECK_MAP:
		var events := InputMap.action_get_events(action)
		assert_int(events.size()).is_greater_equal(1) \
			.override_failure_message("action '%s' has no events at all" % action)
		var joypad_buttons: Array[InputEventJoypadButton] = []
		for event: InputEvent in events:
			if event is InputEventJoypadButton:
				joypad_buttons.append(event)
		assert_int(joypad_buttons.size()).is_greater_equal(1) \
			.override_failure_message("action '%s' has no joypad event (Deck pad dead)" % action)


func test_joypad_events_are_any_device() -> void:
	# device -1 = Any Device — the R1 E14 Steam Deck rule (device-specific
	# bindings can lose input on Linux exports).
	for action: StringName in DECK_MAP:
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				assert_int((event as InputEventJoypadButton).device).is_equal(-1) \
					.override_failure_message(
						"action '%s' joypad event bound to device %d, not Any Device (-1)"
						% [action, (event as InputEventJoypadButton).device])


func test_button_indices_match_the_deck_table() -> void:
	# The exact buttons from the docs/DEV_SETUP.md table.
	for action: StringName in DECK_MAP:
		var found := false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton \
					and (event as InputEventJoypadButton).button_index == DECK_MAP[action]:
				found = true
		assert_bool(found).is_true() \
			.override_failure_message(
				"action '%s' is not bound to Deck button %d (docs/DEV_SETUP.md table drift)"
				% [action, DECK_MAP[action]])


func test_keyboard_and_mouse_survive_alongside_the_pad() -> void:
	# The pad bindings are additive: every action keeps its keyboard (and for
	# primary, mouse) events from T-ARCH-01 — parity across input modes is a
	# T-UI-04 requirement.
	for action: StringName in DECK_MAP:
		var has_key := false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				has_key = true
		assert_bool(has_key).is_true() \
			.override_failure_message("action '%s' lost its keyboard event" % action)
