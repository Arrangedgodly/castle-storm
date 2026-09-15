## Load-time content validation — the loud gate (T-DATA-01, town-hall q#4).
##
## Contract (docs/gdscript-conventions.md): invalid content is push_error +
## refuse to start, never silently default. validate_pack() returns precise,
## stable error strings in the grammar "<kind> '<id>': <problem>" (pack-level:
## "pack: <problem>") — asserted verbatim by tests/unit/test_content_schema.gd,
## so message wording is API: change it only with the test. load_pack() is the
## runtime entry point: it loads, validates, and returns null after
## push_error-ing every problem. Consumers: T-DATA-02 (authoring loop),
## T-SIM-02..08 (boot load), T-ARCH-03/T-DATA-03 (saves reuse the same ids).
## Full field/constraint reference: docs/content-schema.md.
class_name ContentValidator
extends RefCounted

## Content pack format versions this build understands (schema doc §6).
const SUPPORTED_FORMAT_VERSIONS: Array[int] = [1]

## Regime modifier kind registry (additive entries are forward-compatible;
## see schema doc §5 RegimeModifier).
const COMBAT_MODIFIER_KINDS: Array[StringName] = [&"garrison_multiplier", &"army_score_multiplier"]
const ECONOMY_MODIFIER_KINDS: Array[StringName] = [&"production_multiplier", &"building_cost_multiplier"]

## Identity variety floors — T-SIM-04 acceptance needs 100 visibly varied
## generated leaders; these floors keep combinatorial space honest.
const MIN_LEADER_FIRST_NAMES := 6
const MIN_LEADER_EPITHETS := 6
const MIN_PERSONALITY_TAGS := 4
const MIN_RECRUIT_NAMES := 8

## R4-derived policy floors (research/r4-idle-balance-references.md).
const OFFLINE_CAP_MIN_HOURS := 4.0
const OFFLINE_CAP_MAX_HOURS := 24.0
const MIN_TELEGRAPH_HOURS := 4.0


## Runtime entry: load + validate a pack file. Returns the pack, or null
## after push_error-ing every problem (refuse to start, never default).
static func load_pack(path: String) -> ContentPack:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("[content] failed to load content pack at '%s'" % path)
		return null
	if not res is ContentPack:
		push_error("[content] '%s' is not a ContentPack (got '%s')" % [path, res.get_class()])
		return null
	var pack := res as ContentPack
	var errors := validate_pack(pack)
	if not errors.is_empty():
		push_error("[content] pack at '%s' failed validation with %d error(s):" % [path, errors.size()])
		for e in errors:
			push_error("[content] %s" % e)
		return null
	return pack


## Pure validation: returns every problem found, empty array = valid.
## Deterministic order: pack header, art manifest, units, buildings, gear,
## regimes, identity pools, tunables.
static func validate_pack(pack: ContentPack) -> Array[String]:
	var errors: Array[String] = []
	if pack == null:
		errors.append("pack: pack resource is null")
		return errors
	_check_pack_header(pack, errors)
	_check_art_manifest(pack.art, errors)
	_check_units(pack, errors)
	_check_buildings(pack, errors)
	_check_gear(pack, errors)
	_check_regimes(pack, errors)
	_check_identity_pools(pack.identity, errors)
	_check_tunables(pack.tunables, errors)
	return errors


static func _err(errors: Array[String], message: String) -> void:
	errors.append(message)


# --- pack header -----------------------------------------------------------

static func _check_pack_header(pack: ContentPack, errors: Array[String]) -> void:
	if not SUPPORTED_FORMAT_VERSIONS.has(pack.format_version):
		_err(errors, "pack: format_version %d is not supported (supported: %s) — see docs/content-schema.md §6" % [
			pack.format_version, ", ".join(SUPPORTED_FORMAT_VERSIONS.map(func(v: int) -> String: return str(v)))])
	if pack.pack_id == &"":
		_err(errors, "pack: pack_id must not be empty")
	if pack.display_name.is_empty():
		_err(errors, "pack: display_name must not be empty")
	if pack.resources.is_empty():
		_err(errors, "pack: at least one resource must be declared (e.g. food, timber, iron)")
	_check_unique(errors, "pack: duplicate resource '%s'", pack.resources.map(func(r: StringName) -> String: return String(r)))
	for r in pack.resources:
		if r == &"":
			_err(errors, "pack: resource name must not be empty")
	if pack.gear_slots.is_empty():
		_err(errors, "pack: at least one gear slot must be declared (MVP: weapon, armor)")
	_check_unique(errors, "pack: duplicate gear slot '%s'", pack.gear_slots.map(func(s: StringName) -> String: return String(s)))
	if pack.units.is_empty():
		_err(errors, "pack: units must not be empty")
	if pack.buildings.is_empty():
		_err(errors, "pack: buildings must not be empty")
	if pack.regimes.is_empty():
		_err(errors, "pack: regimes must not be empty (MVP: 4 flavors)")
	if pack.identity == null:
		_err(errors, "pack: identity pools must be set")
	if pack.tunables == null:
		_err(errors, "pack: tunables must be set")
	if pack.art == null:
		_err(errors, "pack: art manifest must be set")
	for resource in pack.starting_grants:
		if not pack.resources.has(resource):
			_err(errors, "pack: starting_grants references undeclared resource '%s'" % resource)
		if int(pack.starting_grants[resource]) <= 0:
			_err(errors, "pack: starting_grants['%s'] must be > 0 (got %d)" % [resource, int(pack.starting_grants[resource])])


static func _check_unique(errors: Array[String], message_format: String, names: Array) -> void:
	var seen := {}
	for n in names:
		if seen.has(n):
			_err(errors, message_format % n)
		seen[n] = true


# --- art manifest ----------------------------------------------------------

static func _check_art_manifest(manifest: ArtManifest, errors: Array[String]) -> void:
	if manifest == null:
		return
	var keys := {}
	for asset: ArtAssetDef in manifest.assets:
		if asset == null:
			_err(errors, "art-manifest: asset entry must not be null")
			continue
		if asset.id == &"":
			_err(errors, "art-asset '': id must not be empty")
		elif keys.has(asset.id):
			_err(errors, "art-manifest: duplicate asset id '%s'" % asset.id)
		else:
			keys[asset.id] = true
		if asset.source_path.is_empty():
			_err(errors, "art-asset '%s': source_path must not be empty" % asset.id)
		if asset.license.is_empty():
			_err(errors, "art-asset '%s': license must not be empty (R6 license hygiene)" % asset.id)
		elif asset.license.to_upper().contains("BY") and asset.attribution.is_empty():
			_err(errors, "art-asset '%s': license '%s' requires attribution (CC-BY family)" % [asset.id, asset.license])


## Membership scan against the manifest; a missing manifest is already
## reported by the header check, so key checks are skipped silently there.
static func _check_art_key(errors: Array[String], kind: String, id: StringName, key: StringName, manifest: ArtManifest, label: String) -> void:
	if manifest == null:
		return
	if key == &"":
		_err(errors, "%s '%s': %s must not be empty (art manifest key required)" % [kind, id, label])
		return
	for asset: ArtAssetDef in manifest.assets:
		if asset != null and asset.id == key:
			return
	_err(errors, "%s '%s': %s '%s' missing from art manifest" % [kind, id, label, key])


# --- units -----------------------------------------------------------------

static func _check_units(pack: ContentPack, errors: Array[String]) -> void:
	var ids: Array[String] = []
	for unit: UnitDef in pack.units:
		if unit == null:
			_err(errors, "unit <null>: unit entry must not be null")
			continue
		ids.append(String(unit.id))
		if unit.id == &"":
			_err(errors, "unit '': id must not be empty")
		if unit.display_name.is_empty():
			_err(errors, "unit '%s': display_name must not be empty" % unit.id)
		if unit.training_time_hours < 0.0:
			_err(errors, "unit '%s': training_time_hours must be >= 0 (got %s)" % [unit.id, unit.training_time_hours])
		if unit.combat_power < 0:
			_err(errors, "unit '%s': combat_power must be >= 0 (got %d)" % [unit.id, unit.combat_power])
		if unit.suspicion_on_train < 0:
			_err(errors, "unit '%s': suspicion_on_train must be >= 0 (got %d)" % [unit.id, unit.suspicion_on_train])
		_check_art_key(errors, "unit", unit.id, unit.face_id, pack.art, "face_id")
	_check_unique(errors, "pack: duplicate unit id '%s'", ids)

	# Cross-checks that need the full id set.
	var id_set := {}
	for id in ids:
		id_set[id] = true
	var gear_slots := {}
	for slot in pack.gear_slots:
		gear_slots[slot] = false
	for gear: GearDef in pack.gear:
		if gear != null and pack.gear_slots.has(gear.slot):
			gear_slots[gear.slot] = true
	for unit: UnitDef in pack.units:
		if unit == null:
			continue
		for target in unit.promotion_paths:
			if not id_set.has(String(target)):
				_err(errors, "unit '%s': promotion target '%s' does not match any unit in pack" % [unit.id, target])
		for slot in unit.required_gear_slots:
			if not pack.gear_slots.has(slot):
				_err(errors, "unit '%s': required gear slot '%s' is not a declared gear slot" % [unit.id, slot])
			elif not gear_slots[slot]:
				_err(errors, "unit '%s': required gear slot '%s' has no gear in pack" % [unit.id, slot])
	_check_promotion_graph(pack.units, errors)


static func _check_promotion_graph(units: Array[UnitDef], errors: Array[String]) -> void:
	var by_id := {}
	for unit: UnitDef in units:
		if unit != null and unit.id != &"":
			by_id[unit.id] = unit
	var state := {}  # id -> 1 visiting, 2 done
	var stack: Array[String] = []
	for unit: UnitDef in units:
		if unit != null:
			_visit_promotion(unit, by_id, state, stack, errors)


static func _visit_promotion(unit: UnitDef, by_id: Dictionary, state: Dictionary, stack: Array[String], errors: Array[String]) -> void:
	if state.get(unit.id) == 2:
		return
	if state.get(unit.id) == 1:
		var cycle: Array[String] = stack.slice(stack.find(String(unit.id)))
		cycle.append(String(unit.id))
		_err(errors, "unit '%s': promotion cycle detected: %s" % [unit.id, " -> ".join(cycle)])
		return
	state[unit.id] = 1
	stack.push_back(String(unit.id))
	for target in unit.promotion_paths:
		if by_id.has(target):
			_visit_promotion(by_id[target], by_id, state, stack, errors)
	state[unit.id] = 2
	stack.pop_back()


# --- buildings -------------------------------------------------------------

static func _check_buildings(pack: ContentPack, errors: Array[String]) -> void:
	var ids: Array[String] = []
	for building: BuildingDef in pack.buildings:
		if building == null:
			_err(errors, "building <null>: building entry must not be null")
			continue
		ids.append(String(building.id))
		if building.id == &"":
			_err(errors, "building '': id must not be empty")
		if building.display_name.is_empty():
			_err(errors, "building '%s': display_name must not be empty" % building.id)
		if building.resource_produced != &"" and not pack.resources.has(building.resource_produced):
			_err(errors, "building '%s': resource_produced '%s' is not a declared resource (use empty for non-producing)" % [building.id, building.resource_produced])
		if building.resource_produced != &"":
			if building.base_production_per_worker_hour <= 0.0:
				_err(errors, "building '%s': base_production_per_worker_hour must be > 0 for a producing building (got %s)" % [building.id, building.base_production_per_worker_hour])
			if building.worker_slots_base < 1:
				_err(errors, "building '%s': worker_slots_base must be >= 1 for a producing building (got %d)" % [building.id, building.worker_slots_base])
		if building.base_cost.is_empty():
			_err(errors, "building '%s': base_cost must not be empty" % building.id)
		for resource in building.base_cost:
			if not pack.resources.has(resource):
				_err(errors, "building '%s': base_cost references undeclared resource '%s'" % [building.id, resource])
			if building.base_cost[resource] <= 0:
				_err(errors, "building '%s': base_cost['%s'] must be > 0 (got %d)" % [building.id, resource, building.base_cost[resource]])
		if pack.tunables != null:
			var band_min: float = pack.tunables.cost_growth_band_min
			var band_max: float = pack.tunables.cost_growth_band_max
			if building.cost_growth < band_min or building.cost_growth > band_max:
				_err(errors, "building '%s': cost_growth %s outside tunables band [%s, %s] (R4: 1.08-1.12)" % [building.id, building.cost_growth, band_min, band_max])
		if building.milestone_levels.is_empty():
			_err(errors, "building '%s': milestone_levels must not be empty (R4 curve: [10, 20])" % building.id)
		else:
			for i in building.milestone_levels.size():
				var level: int = building.milestone_levels[i]
				if level < 2 or (i > 0 and level <= building.milestone_levels[i - 1]):
					_err(errors, "building '%s': milestone_levels must be >= 2 and strictly increasing" % building.id)
					break
				if building.max_level >= 1 and level > building.max_level:
					_err(errors, "building '%s': milestone level %d exceeds max_level %d" % [building.id, level, building.max_level])
		if building.max_level < 1:
			_err(errors, "building '%s': max_level must be >= 1 (got %d)" % [building.id, building.max_level])
	_check_unique(errors, "pack: duplicate building id '%s'", ids)


# --- gear ------------------------------------------------------------------

static func _check_gear(pack: ContentPack, errors: Array[String]) -> void:
	var ids: Array[String] = []
	for gear: GearDef in pack.gear:
		if gear == null:
			_err(errors, "gear <null>: gear entry must not be null")
			continue
		ids.append(String(gear.id))
		if gear.id == &"":
			_err(errors, "gear '': id must not be empty")
		if gear.display_name.is_empty():
			_err(errors, "gear '%s': display_name must not be empty" % gear.id)
		if not pack.gear_slots.has(gear.slot):
			_err(errors, "gear '%s': slot '%s' is not a declared gear slot" % [gear.id, gear.slot])
		if gear.tier < 1:
			_err(errors, "gear '%s': tier must be >= 1 (got %d)" % [gear.id, gear.tier])
		if gear.recipe.is_empty():
			_err(errors, "gear '%s': recipe must not be empty" % gear.id)
		for resource in gear.recipe:
			if not pack.resources.has(resource):
				_err(errors, "gear '%s': recipe references undeclared resource '%s'" % [gear.id, resource])
			if gear.recipe[resource] <= 0:
				_err(errors, "gear '%s': recipe['%s'] must be > 0 (got %d)" % [gear.id, resource, gear.recipe[resource]])
		if gear.combat_power < 0:
			_err(errors, "gear '%s': combat_power must be >= 0 (got %d)" % [gear.id, gear.combat_power])
		if gear.craft_time_hours < 0.0:
			_err(errors, "gear '%s': craft_time_hours must be >= 0 (got %s)" % [gear.id, gear.craft_time_hours])
	_check_unique(errors, "pack: duplicate gear id '%s'", ids)
	for gear: GearDef in pack.gear:
		if gear != null:
			_check_art_key(errors, "gear", gear.id, gear.icon_id, pack.art, "icon_id")


# --- regimes ---------------------------------------------------------------

static func _check_regimes(pack: ContentPack, errors: Array[String]) -> void:
	var ids: Array[String] = []
	for regime: RegimeDef in pack.regimes:
		if regime == null:
			_err(errors, "regime <null>: regime entry must not be null")
			continue
		ids.append(String(regime.id))
		if regime.id == &"":
			_err(errors, "regime '': id must not be empty")
		if regime.display_name.is_empty():
			_err(errors, "regime '%s': display_name must not be empty" % regime.id)
		if regime.combat_modifier == null:
			_err(errors, "regime '%s': combat_modifier must be set (exactly one per flavor)" % regime.id)
		else:
			_check_modifier(pack, regime, regime.combat_modifier, COMBAT_MODIFIER_KINDS, "combat_modifier", errors)
		if regime.economy_quirk == null:
			_err(errors, "regime '%s': economy_quirk must be set (exactly one per flavor)" % regime.id)
		else:
			_check_modifier(pack, regime, regime.economy_quirk, ECONOMY_MODIFIER_KINDS, "economy_quirk", errors)
		_check_art_key(errors, "regime", regime.id, regime.crest_id, pack.art, "crest_id")
		if regime.ink_ground == regime.ink_secondary:
			_err(errors, "regime '%s': ink_ground and ink_secondary must differ (R6 two-ink rule)" % regime.id)
	_check_unique(errors, "pack: duplicate regime id '%s'", ids)


static func _check_modifier(pack: ContentPack, regime: RegimeDef, modifier: RegimeModifier, allowed_kinds: Array[StringName], label: String, errors: Array[String]) -> void:
	if not allowed_kinds.has(modifier.kind):
		var kind_names := ", ".join(PackedStringArray(allowed_kinds.map(func(k: StringName) -> String: return String(k))))
		_err(errors, "regime '%s': %s kind '%s' not recognized (expected one of: %s)" % [regime.id, label, modifier.kind, kind_names])
	if modifier.value <= 0.0:
		_err(errors, "regime '%s': %s value must be > 0 (got %s)" % [regime.id, label, modifier.value])
	if label == "economy_quirk" and modifier.target != &"all" and not pack.resources.has(modifier.target):
		_err(errors, "regime '%s': economy_quirk target '%s' is not a declared resource or 'all'" % [regime.id, modifier.target])


# --- identity pools ----------------------------------------------------------

static func _check_identity_pools(pools: IdentityPools, errors: Array[String]) -> void:
	if pools == null:
		return
	_check_name_pool(errors, "leader_first_names", pools.leader_first_names, MIN_LEADER_FIRST_NAMES)
	_check_name_pool(errors, "leader_epithets", pools.leader_epithets, MIN_LEADER_EPITHETS)
	_check_name_pool(errors, "personality_tags", pools.personality_tags, MIN_PERSONALITY_TAGS)
	_check_name_pool(errors, "recruit_names", pools.recruit_names, MIN_RECRUIT_NAMES)


static func _check_name_pool(errors: Array[String], label: String, pool: Array, min_count: int) -> void:
	if pool.size() < min_count:
		_err(errors, "identity: %s needs at least %d entries (got %d)" % [label, min_count, pool.size()])
	var seen := {}
	for entry in pool:
		var key := str(entry)
		if key.is_empty():
			_err(errors, "identity: %s entry must not be empty" % label)
		elif seen.has(key):
			_err(errors, "identity: %s duplicate '%s'" % [label, key])
		seen[key] = true


# --- tunables ----------------------------------------------------------------

## Single-scope check so T-SIM-08 balance sweeps can validate candidate
## tunables without assembling a full pack.
static func validate_tunables(t: EconomyTunables) -> Array[String]:
	var errors: Array[String] = []
	_check_tunables(t, errors)
	return errors


static func _check_tunables(t: EconomyTunables, errors: Array[String]) -> void:
	if t == null:
		return
	if t.offline_cap_hours < OFFLINE_CAP_MIN_HOURS or t.offline_cap_hours > OFFLINE_CAP_MAX_HOURS:
		_err(errors, "tunables: offline_cap_hours must be within [%s, %s] — R4 tunable range (got %s)" % [OFFLINE_CAP_MIN_HOURS, OFFLINE_CAP_MAX_HOURS, t.offline_cap_hours])
	if t.offline_rate <= 0.0 or t.offline_rate > 1.0:
		_err(errors, "tunables: offline_rate must be within (0, 1] — premium full-rate; sub-1.0 is an F2P lever (got %s)" % t.offline_rate)
	if t.cost_growth_band_min <= 1.0 or t.cost_growth_band_max <= t.cost_growth_band_min or t.cost_growth_band_max >= 2.0:
		_err(errors, "tunables: cost_growth band must satisfy 1.0 < min <= max < 2.0 (got [%s, %s])" % [t.cost_growth_band_min, t.cost_growth_band_max])
	if t.milestone_multiplier < 1.0:
		_err(errors, "tunables: milestone_multiplier must be >= 1.0 (got %s)" % t.milestone_multiplier)
	if t.knight_cost_step <= 1.0 or t.knight_cost_step >= 3.0:
		_err(errors, "tunables: knight_cost_step must be within (1.0, 3.0) (got %s)" % t.knight_cost_step)
	if t.recruit_arrival_interval_hours <= 0.0:
		_err(errors, "tunables: recruit_arrival_interval_hours must be > 0 (got %s)" % t.recruit_arrival_interval_hours)
	elif t.recruit_arrival_jitter_hours < 0.0 or t.recruit_arrival_jitter_hours >= t.recruit_arrival_interval_hours:
		_err(errors, "tunables: recruit_arrival_jitter_hours must be within [0, recruit_arrival_interval_hours) (got %s vs interval %s)" % [t.recruit_arrival_jitter_hours, t.recruit_arrival_interval_hours])
	if not (0 < t.suspicion_warn_threshold and t.suspicion_warn_threshold < t.suspicion_crackdown_threshold and t.suspicion_crackdown_threshold < t.suspicion_max):
		_err(errors, "tunables: suspicion thresholds must satisfy 0 < warn < crackdown < max (got warn=%d crackdown=%d max=%d)" % [t.suspicion_warn_threshold, t.suspicion_crackdown_threshold, t.suspicion_max])
	if t.suspicion_decay_per_hour < 0.0 or t.suspicion_decay_high_tier_per_hour < 0.0:
		_err(errors, "tunables: suspicion decay must be >= 0 (got %s/h, high-tier %s/h)" % [t.suspicion_decay_per_hour, t.suspicion_decay_high_tier_per_hour])
	elif t.suspicion_decay_high_tier_per_hour > t.suspicion_decay_per_hour:
		_err(errors, "tunables: suspicion_decay_high_tier_per_hour must be <= suspicion_decay_per_hour (compromised state decays slower)")
	if t.suspicion_rise_medium < 0 or t.suspicion_rise_loud < t.suspicion_rise_medium:
		_err(errors, "tunables: suspicion rise must satisfy 0 <= medium <= loud (got medium=%d loud=%d)" % [t.suspicion_rise_medium, t.suspicion_rise_loud])
	if t.crackdown_seize_fraction <= 0.0 or t.crackdown_seize_fraction >= 1.0:
		_err(errors, "tunables: crackdown_seize_fraction must be within (0, 1) (got %s)" % t.crackdown_seize_fraction)
	if t.crackdown_telegraph_hours < MIN_TELEGRAPH_HOURS:
		_err(errors, "tunables: crackdown_telegraph_hours must be >= %s — R4 commitment (got %s)" % [MIN_TELEGRAPH_HOURS, t.crackdown_telegraph_hours])
	if t.post_crackdown_suspicion >= t.suspicion_crackdown_threshold:
		_err(errors, "tunables: post_crackdown_suspicion must be < crackdown threshold %d (got %d)" % [t.suspicion_crackdown_threshold, t.post_crackdown_suspicion])
	if t.post_crackdown_rise_multiplier <= 0.0 or t.post_crackdown_rise_multiplier > 1.0:
		_err(errors, "tunables: post_crackdown_rise_multiplier must be within (0, 1] (got %s)" % t.post_crackdown_rise_multiplier)
	if t.post_crackdown_relief_hours <= 0.0:
		_err(errors, "tunables: post_crackdown_relief_hours must be > 0 (got %s)" % t.post_crackdown_relief_hours)
	# --- Suspicion heat profile (T-SIM-05 additive fields) ---
	if t.suspicion_presence_army_per_hour < 0.0 or t.suspicion_presence_follower_per_hour < 0.0 \
			or t.suspicion_presence_building_per_hour < 0.0 or t.suspicion_presence_offer_per_hour < 0.0:
		_err(errors, "tunables: suspicion presence weights must be >= 0 (got army=%s follower=%s building=%s offer=%s)" % [
			t.suspicion_presence_army_per_hour, t.suspicion_presence_follower_per_hour,
			t.suspicion_presence_building_per_hour, t.suspicion_presence_offer_per_hour,
		])
	if t.suspicion_recruit_tolerance < 0:
		_err(errors, "tunables: suspicion_recruit_tolerance must be >= 0 (got %d)" % t.suspicion_recruit_tolerance)
	if t.suspicion_decay_pause_hours < 0.0:
		_err(errors, "tunables: suspicion_decay_pause_hours must be >= 0 (got %s)" % t.suspicion_decay_pause_hours)
	if t.crackdown_scatter_fraction <= 0.0 or t.crackdown_scatter_fraction > 1.0:
		_err(errors, "tunables: crackdown_scatter_fraction must be within (0, 1] (got %s)" % t.crackdown_scatter_fraction)
	if t.crackdown_rearm_hours < 0.0:
		_err(errors, "tunables: crackdown_rearm_hours must be >= 0 (got %s)" % t.crackdown_rearm_hours)
