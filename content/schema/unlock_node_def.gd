## Declarative legacy-unlock node (L1, the post-MVP unlock tree) — one
## purchasable Manor-style upgrade (R5: the Rogue Legacy manor pattern —
## always-on, fed by every run win or lose). T-DATA schema (docs/
## content-schema.md). Consumed by: LegacySystem (purchase validation +
## cost), LegacyModifiers (effect resolution), the L1 tree UI (display/
## branch/prerequisite grouping).
##
## Exactly ONE effect per node (UnlockEffect — the RegimeModifier
## discipline: a node says one thing). Prerequisites reference sibling node
## ids, never paths; the validator proves the graph acyclic so a purchase
## order always exists.
class_name UnlockNodeDef
extends Resource

## Stable content id (RunMeta.unlocks persists it, never paths).
@export var id: StringName = &""

## Localization-ready display name.
@export var display_name: String = ""

## Branch grouping label for the tree UI (e.g. &"economy", &"military",
## &"people" — R5: 2-4 node families per layer). Free-form, non-empty.
@export var branch: StringName = &""

## Purchase price in banked legacy points (must be > 0 — validator-
## enforced; earn rates per docs/balance.md, ~150-260 lp per run).
@export var cost: int = 0

## Node ids that must be owned before this one (must resolve within the
## tree and form a DAG — validator-enforced, cycle message includes the
## path).
@export var prerequisites: Array[StringName] = []

## The node's ONE typed effect (must be set; kind in the registry).
@export var effect: UnlockEffect
