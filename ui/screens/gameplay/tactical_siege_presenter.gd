## TacticalSiegePresenter — Presenter and telemetry adapter for tactical siege combat (TS-02).
##
## Translates TacticalSiegeResolver simulation state and combat round outcomes
## into structured view models for the tactical siege UI.
class_name TacticalSiegePresenter
extends RefCounted

const TacticalSiegeResolver := preload("res://sim/systems/tactical_siege_resolver.gd")

const PHASE_LABELS: Array[String] = [
	"1. Outer Gate",
	"2. Courtyard",
	"3. The Keep"
]


## Formats the live siege state into a clean UI view-model.
static func format_siege_view(siege: TacticalSiegeResolver) -> Dictionary:
	if siege == null:
		return {
			"is_active": false,
			"status": TacticalSiegeResolver.SiegeStatus.NOT_STARTED,
			"status_label": "Not Started",
			"phase_index": 0,
			"phase_name": "",
			"phase_progress_pct": 0.0,
			"defender_hp": 0,
			"defender_max_hp": 0,
			"defender_hp_pct": 0.0,
			"army_power": 0,
			"initial_army_power": 0,
			"casualties_suffered": 0,
			"available_tactics": [],
			"can_retreat": false,
			"combat_log": [],
			"phase_steps": _build_phase_steps(0, false)
		}

	var is_active: bool = siege.status == TacticalSiegeResolver.SiegeStatus.IN_PROGRESS
	var hp_pct: float = 0.0
	if siege.phase_defender_max_hp > 0:
		hp_pct = clampf(float(siege.phase_defender_hp) / float(siege.phase_defender_max_hp), 0.0, 1.0)

	var phase_idx: int = int(siege.current_phase)
	var phase_prog: float = clampf(float(phase_idx) / 3.0, 0.0, 1.0)

	var status_text: String = "In Progress"
	match siege.status:
		TacticalSiegeResolver.SiegeStatus.NOT_STARTED:
			status_text = "Ready to Siege"
		TacticalSiegeResolver.SiegeStatus.IN_PROGRESS:
			status_text = "Breach in Progress"
		TacticalSiegeResolver.SiegeStatus.VICTORY:
			status_text = "Castle Conquered!"
		TacticalSiegeResolver.SiegeStatus.REPELLED:
			status_text = "Assault Repelled"
		TacticalSiegeResolver.SiegeStatus.RETREATED:
			status_text = "Orderly Retreat"

	return {
		"is_active": is_active,
		"status": siege.status,
		"status_label": status_text,
		"phase_index": phase_idx,
		"phase_name": TacticalSiegeResolver.PHASE_NAMES.get(siege.current_phase, ""),
		"phase_progress_pct": phase_prog,
		"defender_hp": siege.phase_defender_hp,
		"defender_max_hp": siege.phase_defender_max_hp,
		"defender_hp_pct": hp_pct,
		"army_power": siege.current_army_power,
		"initial_army_power": siege.initial_army_power,
		"casualties_suffered": siege.casualties_suffered,
		"available_tactics": siege.get_available_tactics(),
		"can_retreat": is_active,
		"combat_log": siege.combat_log.duplicate(),
		"phase_steps": _build_phase_steps(phase_idx, is_active)
	}


static func _build_phase_steps(current_phase_idx: int, is_active: bool) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for i in range(3):
		var step_state := "upcoming"
		if i < current_phase_idx:
			step_state = "completed"
		elif i == current_phase_idx:
			step_state = "active" if is_active else "completed"

		steps.append({
			"index": i,
			"label": PHASE_LABELS[i],
			"state": step_state
		})
	return steps


## Dispatches a tactical stance selection.
static func execute_tactic(siege: TacticalSiegeResolver, tactic_id: StringName) -> Dictionary:
	if siege == null:
		return {"success": false, "error": "No siege instance"}
	return siege.execute_tactic(tactic_id)


## Dispatches an orderly retreat command.
static func order_retreat(siege: TacticalSiegeResolver) -> Dictionary:
	if siege == null:
		return {"success": false, "error": "No siege instance"}
	return siege.order_retreat()
