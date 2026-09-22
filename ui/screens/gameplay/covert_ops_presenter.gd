## CovertOpsPresenter — UI telemetry and view-model adapter for covert operations (CO-02).
##
## Converts CovertOpsSystem simulation state into structured UI models,
## formatting resource costs, risk indicators, operation states, and debriefs.
class_name CovertOpsPresenter
extends RefCounted

const CovertOpsSystem := preload("res://sim/systems/covert_ops_system.gd")


## Formats complete espionage state into view model for the UI panel.
static func format_operations_view(covert: CovertOpsSystem, engine: SimEngine) -> Dictionary:
	if covert == null:
		return {
			"network_active": false,
			"active_perks_count": 0,
			"operations": [],
			"history": []
		}

	var ops_raw: Array[Dictionary] = covert.get_all_operations()
	var ops_formatted: Array[Dictionary] = []
	var active_count: int = 0

	for op in ops_raw:
		var op_id: StringName = op.get("id", &"")
		var is_active: bool = covert.is_operation_active(op_id)
		var affordable: bool = covert.can_afford(op_id, engine) if engine != null else false
		var cost_dict: Dictionary = op.get("cost", {})
		var cost_strs: Array[String] = []
		for res_id in cost_dict.keys():
			cost_strs.append("%d %s" % [int(cost_dict[res_id]), String(res_id).capitalize()])
		var cost_text: String = ", ".join(cost_strs)

		var status_text: String = "READY TO LAUNCH"
		if is_active:
			status_text = "ESTABLISHED"
			active_count += 1
		elif not affordable:
			status_text = "INSUFFICIENT RESOURCES"

		ops_formatted.append({
			"id": op_id,
			"title": op.get("title", ""),
			"desc": op.get("desc", ""),
			"perk": op.get("perk", ""),
			"cost_text": cost_text,
			"chance_text": "%d%% Success Rate" % int(op.get("base_success_chance", 70)),
			"risk_text": "+%d Suspicion if Exposed" % int(op.get("suspicion_on_fail", 10)),
			"is_active": is_active,
			"can_afford": affordable,
			"can_launch": affordable and not is_active,
			"status_label": status_text
		})

	return {
		"network_active": active_count > 0,
		"active_perks_count": active_count,
		"operations": ops_formatted,
		"history": covert.operation_history.duplicate()
	}


## Dispatches an operation launch through the simulation engine.
static func launch_operation(covert: CovertOpsSystem, engine: SimEngine, op_id: StringName) -> Dictionary:
	if covert == null or engine == null:
		return {"success": false, "error": "Invalid covert system or engine"}
	return covert.execute_operation(op_id, engine)
