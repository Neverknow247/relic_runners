extends Resource
class_name MapDef

# One playable map (an entry on the map ladder): which room it starts in and every
# per-map tuning number the spawners read. Edit the .tres files in
# scenes/maps/defs/ in the inspector; register new ones in MapRegistry.MAP_PATHS.
# See docs/master_plan.md §2 (styles x tiers) and §5 (MapDef).

## Stable id: what expedition doors / the map board pass around (e.g. "village").
@export var id := ""
@export var display_name := ""
## "extraction" (raid clock) or "survival" (day clock).
@export_enum("extraction", "survival") var style := "extraction"
## Ladder rung within the style (E1 = 1, E2 = 2, ...).
@export var tier := 1
## Map id you must have EXTRACTED from at least once before this one unlocks on
## the map board ("" = always open). The ladder: E2 unlocks after clearing E1.
@export var unlock_after := ""

@export_group("Entry")
@export var zone := ""
@export var room := "main"
## Spawn marker name, or "random_portal" to arrive at a seeded portal.
@export var spawn := "random_portal"

@export_group("Enemies")
## archetype -> relative weight for each pack. Empty = enemy_spawner defaults.
@export var roster: Dictionary = {}
## Per-enemy chance to be silver / gold (the rest are bronze).
@export_range(0.0, 1.0) var silver_chance := 0.15
@export_range(0.0, 1.0) var gold_chance := 0.0
## Multiplies every pack's rolled size (rounded, min 1).
@export var pack_mult := 1.0
## Multiplies each spawn marker's chance to spawn a pack at all.
@export var spawn_chance_mult := 1.0

@export_group("Containers")
@export_range(0.0, 1.0) var container_silver_chance := 0.12
@export_range(0.0, 1.0) var container_gold_chance := 0.0
## container type -> weight. Empty = container_spawner's own type_weights.
@export var container_type_weights: Dictionary = {}

@export_group("Pacing (later phases)")
## Raid timer for extraction maps in seconds (0 = none yet; Phase 4).
@export var duration_sec := 0.0
## Attack tokens per player (Phase 3 difficulty dial; unused until then).
@export var tokens_per_player := 2
