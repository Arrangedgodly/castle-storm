## Identity name pools for randomized leaders and recruits.
## T-DATA-01 schema (docs/content-schema.md). Consumed by: T-SIM-04 (leader/
## regime generation — 100-leader variety acceptance), T-COPY-01 (voice
## bible owns the shipped pools), T-UI-05 (leader intro card).
class_name IdentityPools
extends Resource

## Leader first names (variety floor enforced by the validator; T-SIM-04).
@export var leader_first_names: Array[String] = []

## Leader epithets, combinable with any first name ("Bran the Unbearable").
@export var leader_epithets: Array[String] = []

## Personality tags a generated leader may carry (chronicle voice hooks).
@export var personality_tags: Array[StringName] = []

## Given names for arriving recruits (peasant cards joining the spread).
@export var recruit_names: Array[String] = []
