## LegacySystem — the legacy unlock tree service (L1, post-MVP layer 1).
##
## NOT a per-tick SimSystem: meta-progression is META-domain, like RunMeta
## and CatchUpService (docs/sim-engine.md §18) — a plain host service, no
## scene tree, no engine registration, no ticking. It owns the purchase
## rules over ONE UnlockTreeDef (boot-injected content) and ONE RunMeta
## (the persistence): the owned-node set and the points balance live in the
## META save domain (`RunMeta.unlocks` — node id -> true, purchase order;
## `RunMeta.legacy_points` — the bank every ended run accrues into, win or
## lose), so unlocks survive restarts, engine re-inits and process
## restarts BY DESIGN and can never be forked from a run save.
##
## Purchase rules (the loud gate): a purchase must name a node in the tree
## (1), not already be owned (2), have every prerequisite owned (3), and
## cost at most the bank (4). `purchase()` refuses LOUDLY (push_error +
## false, nothing mutated); on success it decrements the bank and records
## the id. The HOST persists the meta domain the moment a purchase lands
## (the press-card write-through precedent).
##
## Effects: `modifiers()` resolves the owned set into ONE LegacyModifiers
## bundle; RunLifecycleSystem re-resolves at every run_start/run_restart
## drain, so a purchase between runs benefits the next run (never the
## running one — the tree is a between-runs verb). Resolution skips owned
## ids that left the tree, loudly (content churn), and ignores unknown
## effect kinds (forward compatibility).
##
## Determinism: purchase decisions are pure functions of (tree, meta) —
## no RNG, no clock; the resolved bundle is exact integer milli math.
class_name LegacySystem
extends RefCounted

## Purchase-refusal reason codes (`purchase_result` / the loud errors).
const PURCHASE_OK := 0
const PURCHASE_UNKNOWN_NODE := 1
const PURCHASE_ALREADY_OWNED := 2
const PURCHASE_PREREQUISITE_MISSING := 3
const PURCHASE_INSUFFICIENT_POINTS := 4

## The persistence (meta save domain). Public: the host saves it through
## the SaveManager and hands the SAME instance to every engine.
var meta: RunMeta

var _tree: UnlockTreeDef = null
var _by_id: Dictionary = {}  # StringName node id -> UnlockNodeDef
var _node_order: Array[StringName] = []  # tree order (the UI's read)


func _init(p_tree: UnlockTreeDef = null, p_meta: RunMeta = null) -> void:
	meta = p_meta if p_meta != null else RunMeta.new()
	_set_tree(p_tree)


# --- Reads (pure queries; the UI surfaces) ---------------------------------


## The attached tree (null when the pack ships none — pre-L1 packs).
func tree() -> UnlockTreeDef:
	return _tree


## Tree version (0 when no tree is attached).
func tree_version() -> int:
	return 0 if _tree == null else _tree.version


## Every node id in tree order (the tree screen's read).
func node_ids() -> Array[StringName]:
	return _node_order.duplicate()


## One node def (null when unknown / no tree).
func node(id: StringName) -> UnlockNodeDef:
	return _by_id.get(id) as UnlockNodeDef


## A node's cost in legacy points (0 when unknown).
func cost(id: StringName) -> int:
	var def := node(id)
	return 0 if def == null else def.cost


## The banked points balance (every ended run accrues; docs/balance.md).
func bank() -> int:
	return meta.legacy_points


## Owned node ids in PURCHASE ORDER (RunMeta.unlocks insertion order — the
## historical document; ids that later left the tree are still listed).
func owned_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in meta.unlocks.keys():
		ids.append(StringName(String(key)))
	return ids


## Total owned nodes.
func owned_count() -> int:
	return meta.unlocks.size()


func is_owned(id: StringName) -> bool:
	return meta.unlocks.has(String(id))


## Nodes purchasable RIGHT NOW (unknown/owned/prereq/afford all pass), in
## tree order — the UI's "affordable" read.
func affordable_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _node_order:
		if purchase_result(id) == PURCHASE_OK:
			ids.append(id)
	return ids


# --- Purchase rules (the loud gate) -----------------------------------------


## Pure validation of one purchase: OK (0) or the first failing reason.
## Decision order is contract: unknown node, already owned, missing
## prerequisite, insufficient points.
func purchase_result(id: StringName) -> int:
	var def := node(id)
	if def == null:
		return PURCHASE_UNKNOWN_NODE
	if is_owned(id):
		return PURCHASE_ALREADY_OWNED
	for prerequisite in def.prerequisites:
		if not is_owned(prerequisite):
			return PURCHASE_PREREQUISITE_MISSING
	if def.cost > meta.legacy_points:
		return PURCHASE_INSUFFICIENT_POINTS
	return PURCHASE_OK


func can_purchase(id: StringName) -> bool:
	return purchase_result(id) == PURCHASE_OK


## THE purchase verb (the host command's logic). Validates everything,
## refuses LOUDLY (push_error + false, zero mutation), and on success
## decrements the bank + records the id in purchase order. The CALLER owns
## persisting the meta domain (GameHost saves through the SaveManager).
func purchase(id: StringName) -> bool:
	var result := purchase_result(id)
	if result != PURCHASE_OK:
		push_error(
			"legacy: purchase of '%s' refused — %s (bank %d, owned %d)"
			% [id, _reason_name(result), meta.legacy_points, owned_count()]
		)
		return false
	meta.legacy_points -= cost(id)
	meta.unlocks[String(id)] = true
	return true


# --- Effect resolution -------------------------------------------------------


## Resolve the owned set into ONE modifier bundle (see class header). Pure;
## re-resolved by the run system at every run_start/restart drain.
func modifiers() -> LegacyModifiers:
	var nodes: Array = []
	for key in meta.unlocks.keys():
		var def := _by_id.get(StringName(String(key))) as UnlockNodeDef
		if def == null:
			# The id is a historical purchase whose node left the tree
			# (content churn): keep the record, skip the effect, say so.
			push_warning("legacy: owned unlock '%s' not in tree — effect skipped" % key)
			continue
		nodes.append(def)
	return LegacyModifiers.from_nodes(nodes)


# --- Internals ----------------------------------------------------------------


func _set_tree(p_tree: UnlockTreeDef) -> void:
	_tree = p_tree
	_by_id.clear()
	_node_order.clear()
	if p_tree == null:
		return
	for def in p_tree.nodes:
		if def == null:
			continue
		if _by_id.has(def.id):
			push_warning("legacy: duplicate unlock id '%s' — keeping first" % def.id)
			continue
		_by_id[def.id] = def
		_node_order.append(def.id)


static func _reason_name(result: int) -> String:
	match result:
		PURCHASE_UNKNOWN_NODE:
			return "node not in tree"
		PURCHASE_ALREADY_OWNED:
			return "already owned"
		PURCHASE_PREREQUISITE_MISSING:
			return "prerequisite not owned"
		PURCHASE_INSUFFICIENT_POINTS:
			return "not enough legacy points"
		_:
			return "ok"
