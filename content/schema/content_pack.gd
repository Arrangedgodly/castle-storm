## Content pack manifest — the root resource a run loads and validates
## (T-DATA-01, docs/content-schema.md). format_version is the versioning
## field: the game supports a known set and refuses packs outside it;
## additive optional fields do not bump it (schema doc §6). Consumed by:
## T-DATA-02 (MVP pack), T-SIM-02..08 (all read defs through the pack),
## T-ARCH-03 / T-DATA-03 (saves record pack id + format_version).
class_name ContentPack
extends Resource

## Schema format version (1 = MVP). See docs/content-schema.md §6.
@export var format_version: int = 1

## Stable pack identity recorded in save headers (T-DATA-03).
@export var pack_id: StringName = &""

## Human-readable pack name (editor/chronicle use).
@export var display_name: String = ""

## The resource vocabulary (MVP: food, timber, iron). Every cost, recipe and
## production target must reference one of these (validator cross-check).
@export var resources: Array[StringName] = []

## The gear slot vocabulary (MVP: weapon, armor; 2 slots x 3 tiers).
@export var gear_slots: Array[StringName] = []

## All unit cards (MVP: peasant, worker, militia, trainee, knight, archer).
@export var units: Array[UnitDef] = []

## All buildings (MVP: farm, lumber camp, smithy, training grounds).
@export var buildings: Array[BuildingDef] = []

## All gear items across slots and tiers.
@export var gear: Array[GearDef] = []

## All regime flavors (MVP: 4; each exactly 1 combat modifier + 1 economy
## quirk).
@export var regimes: Array[RegimeDef] = []

## Leader/recruit identity pools.
@export var identity: IdentityPools

## Economy tunables (R4 vocabulary as data).
@export var tunables: EconomyTunables

## Art key -> vendored source + license manifest (R6).
@export var art: ArtManifest
