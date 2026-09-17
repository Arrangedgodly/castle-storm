## LegacyPresenter — the legacy deck screen's pure view layer (L1-C).
##
## THE FUTURE LEGACY TREE IS A GROWING DECK (design brief §3: "the future
## legacy tree is a growing deck") — the meta-screen where banked legacy
## points buy permanent upgrades BETWEEN runs. This presenter maps the
## host's legacy query surfaces (GameHost.unlock_* — the LegacySystem's
## documented reads over the pack's UnlockTreeDef + the meta domain's
## bank/owned set) into the deck-spread view model: the 4 branches as
## FAMILIES of cards, every node one card in the world's grammar.
##
## DATA CONTRACT (the chronicle's discipline): every card field maps the
## tree EXACTLY — id, display name, branch, cost, prerequisites, effect
## (docs/content-schema.md §5). The presenter derives only display
## dressing: the CopyDeck branch name (`unlock_branch_<id>`) and flavor
## line (`unlock_flavor_<id>`, shipped in L1-B), and the EFFECT LINE —
## the effect payload templated into plain readable terms ("walls cost
## 5% less"), one template per registered kind, never an invented
## mechanic. The BANK arithmetic is the meta domain's own: bank, spent
## (the sum of owned in-tree costs) and total earned (bank + spent).
##
## CARD STATES in LINE FORM (the world's raise — form, never hue):
##   owned        SOLID edge + ink-filled crest — pressed into the deck;
##   affordable   DASHED edge (dashed-ready, the deck's in-hand form),
##                the enabled purchase verb + seeded focus;
##   locked       STRUCK edge + the "requires <node>" line (the first
##                missing prerequisite, by name);
##   unaffordable DASHED edge + the shortfall note ("N more legacy").
## State order is contract (the LegacySystem's own decision order:
## owned, then prerequisites, then the bank) so the card never claims a
## shortfall a prerequisite also explains.
##
## MOUNT DISCIPLINE (the L1-A rule): purchases apply at the NEXT run
## start — the view carries `live_run` so the sheet can print that
## honestly when the deck is opened mid-hand.
##
## Pure: reads only the host's legacy/meta/run-liveness query surfaces —
## same tree + meta => same view (view_hash pins it).
class_name LegacyPresenter
extends RefCounted

## The deck's letterpress (code-side, like the chronicle's own title).
const TITLE := "THE LEGACY"

## The card-state vocabulary (the sheet's edge-form carrier).
const STATE_OWNED := &"owned"
const STATE_AFFORDABLE := &"affordable"
const STATE_LOCKED := &"locked"
const STATE_UNAFFORDABLE := &"unaffordable"

## State -> edge line form (THE raise: form, not hue). Owned prints
## SOLID (settled, pressed into the deck); both not-yet-owned purchasable
## paths print DASHED (the deck's in-hand form — the ink runs out until
## the card is pressed); prereq-locked prints STRUCK (barred).
const STATE_EDGE_FORMS: Dictionary = {
	STATE_OWNED: Inks.EdgeForm.SOLID,
	STATE_AFFORDABLE: Inks.EdgeForm.DASHED,
	STATE_LOCKED: Inks.EdgeForm.STRUCK,
	STATE_UNAFFORDABLE: Inks.EdgeForm.DASHED,
}

## Card note vocabulary (code-side functional labels, the seal-mark
## precedent; the VOICED lines print through CopyDeck).
const NOTE_OWNED := "kept in the deck"
const NOTE_AFFORDABLE := "ready"

## Flavor shaping budget (chars): the longest shipped flavor is 47; the
## greedy wrap holds a hypothetical longer content edit to two rows
## instead of clipping (the T-UI-06 lesson: shape, never clip).
const FLAVOR_BUDGET := 46


# --- the view model ------------------------------------------------------------------------


## The whole deck as data. Pure: the branch families print in TREE ORDER
## (first-seen), the nodes in tree order within their branch — the
## content author's deal, never re-sorted here.
static func view(host: GameHost) -> Dictionary:
	var tree := host.legacy.tree()
	var bank := host.unlock_bank()
	var affordable := {}
	for id in host.unlock_affordable():
		affordable[id] = true
	var branch_order: Array[StringName] = []
	var branch_nodes := {}
	var node_count := 0
	for id in host.unlock_tree_nodes():
		var def := host.unlock_node(id)
		if def == null:
			continue
		node_count += 1
		if not branch_nodes.has(def.branch):
			branch_nodes[def.branch] = []
			branch_order.append(def.branch)
		(branch_nodes[def.branch] as Array).append(node_view(host, def, bank, affordable))
	var branches: Array[Dictionary] = []
	for branch_id in branch_order:
		branches.append({
			"id": branch_id,
			"name": branch_name(branch_id),
			"crest_key": crest_key(tree, branch_id),
			"nodes": branch_nodes[branch_id],
		})
	var owned := host.unlock_owned()
	var spent := 0
	for id in owned:
		var def := host.unlock_node(id)
		if def != null:
			spent += def.cost
	var owned_count := owned.size()
	return {
		"title": TITLE,
		"branches": branches,
		"bank": bank,
		"spent": spent,
		"total_earned": bank + spent,
		"runs_recorded": host.meta.runs_recorded,
		"owned_count": owned_count,
		"node_count": node_count,
		# The fresh state: no run has finished — the deck still opens, all
		# locked/unaffordable, the CopyDeck "earn your first legacy" line.
		"empty": bank <= 0 and owned_count == 0,
		"empty_lines": [
			{"class": Inks.LineClass.WARN,
				"text": CopyDeck.line(Inks.pack().copy, &"legacy_empty_1", 0)},
			{"class": Inks.LineClass.PLAIN,
				"text": CopyDeck.line(Inks.pack().copy, &"legacy_empty_2", 0)},
		],
		# The L1-A mount rule, printed honestly by the sheet when a hand
		# is live on the table beneath the paper.
		"live_run": host.is_run_running(),
	}


## One node as the card's data. Every key traces an UnlockNodeDef field
## (or a CopyDeck key shipped for it); the state decision order is the
## LegacySystem's own contract.
static func node_view(host: GameHost, def: UnlockNodeDef, bank: int,
		affordable: Dictionary) -> Dictionary:
	var state := STATE_UNAFFORDABLE
	var requires_id := &""
	if host.legacy.is_owned(def.id):
		state = STATE_OWNED
	elif affordable.has(def.id):
		state = STATE_AFFORDABLE
	else:
		# Which rule refused: a missing prerequisite outranks the bank
		# (the system's own decision order) — the note names the FIRST
		# missing prerequisite by its own display name.
		for prerequisite in def.prerequisites:
			if not host.legacy.is_owned(prerequisite):
				state = STATE_LOCKED
				requires_id = prerequisite
				break
		if state == STATE_UNAFFORDABLE and def.cost <= bank:
			# Not affordable by the system yet not refused by prereq or
			# bank either (an unknown node state — the loud-gate twin);
			# print the honest shortfall of zero.
			state = STATE_AFFORDABLE
	var shortfall := maxi(0, def.cost - bank)
	return {
		"id": def.id,
		"name": def.display_name,
		"flavor": shaped_flavor(flavor_line(def.id)),
		"flavor_plain": flavor_line(def.id),
		"cost": def.cost,
		"cost_line": "%d legacy" % def.cost,
		"effect_line": effect_line(def.effect),
		"state": state,
		"edge_form": int(STATE_EDGE_FORMS[state]),
		"purchasable": state == STATE_AFFORDABLE,
		"requires_id": requires_id,
		"requires_name": node_display_name(host, requires_id),
		"shortfall": shortfall,
		"note": note_for(state, requires_id, node_display_name(host, requires_id), shortfall),
	}


## The card's state note (plain functional print, the seal-mark
## precedent): locked names its prerequisite, unaffordable counts the
## shortfall, owned/affordable state their standing.
static func note_for(state: StringName, requires_id: StringName,
		requires_name: String, shortfall: int) -> String:
	match state:
		STATE_OWNED:
			return NOTE_OWNED
		STATE_AFFORDABLE:
			return NOTE_AFFORDABLE
		STATE_LOCKED:
			return "requires %s" % (requires_name if not requires_name.is_empty()
				else String(requires_id))
		_:
			return "%d more legacy needed" % shortfall


# --- the prints ---------------------------------------------------------------------------


## The effect payload in plain readable terms — the task's hard rule:
## derive from the effect, never invent mechanics. One template per
## registered kind (LegacyModifiers.EFFECT_KINDS); the percent is the
## node's OWN effect (the deck compounds across cards, the card says
## what THIS card does); unknown kinds degrade honestly (forward
## compatibility's print-side twin).
static func effect_line(effect: UnlockEffect) -> String:
	if effect == null:
		return "an effect the press has not set"
	var pct := roundi(absf(effect.value - 1.0) * 100.0)
	if pct == 0:
		return "an effect too fine for the press to print"
	var less := effect.value < 1.0
	match effect.kind:
		&"building_cost_multiplier":
			return "buildings cost %d%% less" % pct if less else "buildings cost %d%% more" % pct
		&"gear_cost_multiplier":
			return "gear costs %d%% less" % pct if less else "gear costs %d%% more" % pct
		&"training_time_multiplier":
			return "training runs %d%% faster" % pct if less else "training runs %d%% slower" % pct
		&"stipend_bonus":
			return "the starting stipend pays %d%% more" % pct if not less \
				else "the starting stipend pays %d%% less" % pct
		&"suspicion_decay":
			return "suspicion cools %d%% faster" % pct if not less \
				else "suspicion cools %d%% slower" % pct
		&"veterans":
			return "the army fights %d%% above its power" % pct if not less \
				else "the army fights %d%% below its power" % pct
		&"recruit_arrival_interval_multiplier":
			return "the road runs %d%% busier" % pct if less else "the road runs %d%% quieter" % pct
		_:
			return "an effect the press does not yet print (%s)" % String(effect.kind)


## The branch's CopyDeck name (`unlock_branch_<id>`; the raw id degrades
## honestly when content has not keyed the branch).
static func branch_name(branch_id: StringName) -> String:
	var line := CopyDeck.line(Inks.pack().copy,
		StringName("unlock_branch_" + String(branch_id)), 0)
	return line if not line.is_empty() else String(branch_id)


## The node's CopyDeck flavor line (`unlock_flavor_<id>`; empty when the
## content edit has not landed — the card prints without a flavor row).
static func flavor_line(node_id: StringName) -> String:
	return CopyDeck.line(Inks.pack().copy,
		StringName("unlock_flavor_" + String(node_id)), 0)


## Branch crest key from the tree's own map ("" when unkeyed — the crest
## slot prints its authored placeholder mark, honestly generic).
static func crest_key(tree: UnlockTreeDef, branch_id: StringName) -> StringName:
	if tree == null:
		return &""
	return StringName(String(tree.branch_crests.get(branch_id, &"")))


## A node display name by id (raw id when unknown — the historical
## document keeps its own words).
static func node_display_name(host: GameHost, id: StringName) -> String:
	if id == &"":
		return ""
	var def := host.unlock_node(id)
	return def.display_name if def != null else String(id)


## Shape the flavor to the card's plate (greedy wrap at the budget, at
## most two rows — the chronicle's shaping rule).
static func shaped_flavor(text: String) -> String:
	if text.length() <= FLAVOR_BUDGET:
		return text
	var lines: Array[String] = []
	var remaining := text
	while remaining.length() > FLAVOR_BUDGET and lines.size() < 1:
		var cut := remaining.rfind(" ", FLAVOR_BUDGET)
		if cut <= 0:
			cut = FLAVOR_BUDGET
		lines.append(remaining.substr(0, cut))
		remaining = remaining.substr(cut + 1)
	lines.append(remaining)
	return "\n".join(lines)


# --- determinism --------------------------------------------------------------------------


## Determinism oracle over the view's CONTENT: same tree + meta (+ run
## liveness) => same hash — the sheet is a function of the record, never
## of UI history.
static func view_hash(view: Dictionary) -> int:
	var h := 0x811C9DC5
	h = _mix(h, String(view["title"]).hash())
	h = _mix(h, int(view["bank"]))
	h = _mix(h, int(view["total_earned"]))
	h = _mix(h, int(view["runs_recorded"]))
	h = _mix(h, int(view["owned_count"]))
	h = _mix(h, int(view["node_count"]))
	h = _mix(h, int(view["live_run"]))
	for branch: Dictionary in view["branches"]:
		h = _mix(h, String(branch["id"]).hash())
		h = _mix(h, String(branch["name"]).hash())
		h = _mix(h, String(StringName(String(branch["crest_key"]))).hash())
		for node: Dictionary in branch["nodes"]:
			h = _mix(h, String(node["id"]).hash())
			h = _mix(h, String(node["name"]).hash())
			h = _mix(h, String(node["flavor_plain"]).hash())
			h = _mix(h, int(node["cost"]))
			h = _mix(h, String(node["effect_line"]).hash())
			h = _mix(h, String(node["state"]).hash())
			h = _mix(h, int(node["edge_form"]))
			h = _mix(h, String(node["note"]).hash())
	return h


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
