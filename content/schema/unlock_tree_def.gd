## Declarative legacy-unlock tree (L1) — the full set of purchasable nodes,
## attached to a ContentPack additively-optional (`unlock_tree`; absent =
## the pack ships no tree and the LegacySystem runs empty — the MVP pack
## pre-L1-B). The tree is boot-injected content, NEVER serialized: saves
## carry purchased node ids only (RunMeta.unlocks), resolved against the
## same tree at boot — the same ids-not-objects rule every def follows
## (docs/save-schema.md §3.2).
##
## `version` versions the TREE SHAPE for humans/tools (content iterations);
## node ids are the purchase contract, so a tree that only ADDS nodes needs
## no bump (same forward-compatibility rule as the pack, docs/
## content-schema.md §6).
class_name UnlockTreeDef
extends Resource

## Tree shape version (>= 1, validator-enforced). Bump when the meaning of
## existing node ids changes; additive nodes never require it.
@export var version: int = 1

## Every purchasable node (non-empty, unique ids, acyclic prerequisites —
## ContentValidator.validate_unlock_tree is the loud gate).
@export var nodes: Array[UnlockNodeDef] = []

## Branch -> art-manifest crest key (additive-optional, L1-B: the branch
## plates of the tree UI are content-art, exactly like RegimeDef.crest_id).
## Empty = the tree ships no branch crests (the example tree's shape; the
## tree UI falls back to a plain plate) — no format bump either way. When
## non-empty the validator requires EVERY branch carried by `nodes` to be
## keyed, every value non-empty, and (when a pack art manifest is in scope)
## every crest to resolve to an ArtAssetDef — pending art entries are legal
## (the T-ARCH-04 hatch), staged files are checked for real.
@export var branch_crests: Dictionary[StringName, StringName] = {}
