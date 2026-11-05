extends CharacterBody2D
class_name Enemy

# Multiplayer authority is left at the Godot default (peer 1 / the server) —
# unlike players, no single peer owns an enemy, so nothing calls
# set_multiplayer_authority() here.

const WEAPON_TYPES := ["tome", "orb", "wand"]
# Enemies roll a random element from the full roster (single source: SpellData).
const ELEMENT_TYPES := SpellData.ELEMENT_ORDER

const WEAPON_LETTERS := {
	"tome": "T",
	"orb": "O",
	"wand": "W",
}

var all_spell_data = SpellData.new()
var all_spell_recipes = SpellRecipes.new()

const DamageNumberScene := preload("res://scenes/effects/damage_number.tscn")

func _spawn_damage_number(amount: float, color: Color, is_crit: bool = false, effective: bool = false) -> void:
	var num = DamageNumberScene.instantiate()
	get_tree().current_scene.add_child(num)
	num.global_position = global_position + Vector2(0, -128)
	num.setup(amount, color, is_crit, effective)

@export var max_health := 1000.0

# Combat stats (stats rework). Attack = the base damage of this enemy's casts;
# Defense reduces incoming damage (Diablo-style DR); crit is 0 for now. Rolled
# server-side in _ready. Not replicated — outgoing Attack/crit ride the spawn RPC,
# and Defense is read locally on the server (the enemy is always the server-side
# defender).
var attack: float = 0.0
var defense: float = 0.0
var crit_rate: float = 0.0
var crit_damage: float = 0.0

# Loot: which pool (in ItemData.ENEMY_LOOT_POOLS) this enemy type draws from, and
# how many rarity-weighted rolls a kill yields. Different enemy types will set a
# different pool/range later; "basic" is the only pool for now.
@export var loot_pool := "basic"
@export var loot_rolls_min := 1
@export var loot_rolls_max := 3

# --- Archetype + tier (set by enemy_spawner BEFORE add_child, deterministically) ---
# archetype = a behavior/stat preset (ARCHETYPES); tier = a normal/elite strength +
# visual multiplier (TIERS). Applied in _ready via _apply_archetype() on EVERY peer —
# the spawner's seeded pick is identical across the party, so no replication is needed.
@export var archetype := "pentagon"
@export var tier := "bronze"
var attacks_per_sec_range: Array = [1.0, 1.0]
# Burst-and-cooldown: fire burst_count shots at the attacks_per_sec cadence, then wait
# a random burst_cooldown_range [min,max] seconds before the next burst. max 0 = fire forever.
var burst_count := 1
var burst_cooldown_range: Array = [0.0, 0.0]
var _burst_shots := 0

# Elemental enemies (2026-08-30): no gear / weapons / spell-casting — each SHAPE just
# does its one signature basic attack, so it's predictable and easy to add more. The
# archetype key == the body glyph drawn (see enemy_body.gd). Stats are ABSOLUTE, in the
# units you tune in: `move_speed` (world u/s), `bullet_speed` (world u/s — kept at or
# ABOVE the player's 1000 walk speed so shots can't simply be walked away from; the
# dodge roll at 2500 is how you beat them), and
# `attacks_per_sec` as a [min, max] RANGE (volleys/sec — a pentagon/triangle "attack"
# is its whole fan; rolled fresh each shot so the cadence isn't metronomic).
# `pellets` shots fan EVENLY across `spread_deg`, unless `pellet_angles_deg` gives an
# explicit per-pellet offset list (custom/asymmetric fan). `burst_count` + `burst_cooldown` ([min,max]) = fire
# N shots at that cadence then pause a random C-range seconds. See fire_spell.
# Telegraphs (Phase 1): `windup_sec` = a visible wind-up before each BURST (body pulse;
# a laser line too when `aim_lock`). `aim_lock` freezes the aim point at wind-up start
# (no lead), so reacting to the tell beats the shot. `windup_root` = stand still while
# winding. Numbers pass 2026-11-05 targets: player kills fodder in 1-2 hits, heavies in
# ~3 s; no single hit over ~22% of player HP, and never untelegraphed.
const ARCHETYPES := {
	"pentagon": {
		# 5-pellet shotgun bruiser: slow, closes in, tight fan so 3 pellets land at its
		# hold range (full volley 350 point-blank, ~210 at range). Big 0.5 s tell.
		"move_speed": 600.0, "strafe_speed": 420.0,
		"preferred_range": 800.0, "cast_range": 1100.0,
		"max_health": 800.0, "attack": 70.0, "attacks_per_sec": [0.55, 0.65],
		"burst_count": 2, "burst_cooldown": [3.0, 4.0],
		"pellets": 5, "spread_deg": 36.0, "pellet_angles_deg": [-18.0, -8.0, 0.0, 8.0, 18.0],
		"bullet_speed": 1050.0, "aim_variance_deg": 5.0,
		"windup_sec": 0.5,
		"body_size": 64.0,
	},
	"triangle": {
		# Fast, fragile 3-pellet spread; spawns in swarms (see enemy_spawner group
		# size). Dies in 1-2 basic hits; chip pressure.
		"move_speed": 700.0, "strafe_speed": 480.0,
		"preferred_range": 960.0, "cast_range": 2080.0,
		"max_health": 150.0, "attack": 45.0, "attacks_per_sec": [0.65, 0.75],
		"burst_count": 3, "burst_cooldown": [2.5, 3.0],
		"pellets": 3, "spread_deg": 24.0, "bullet_speed": 1150.0, "aim_variance_deg": 1.0,
		"windup_sec": 0.25,
		"body_size": 48.0,
	},
	"circle": {
		# Suppressor: a 7-shot stream over ~2 s, then a clear 2-2.5 s recover window.
		"move_speed": 900.0, "strafe_speed": 480.0,
		"preferred_range": 1200.0, "cast_range": 2400.0,
		"max_health": 450.0, "attack": 40.0, "attacks_per_sec": [3.5, 3.5],
		"burst_count": 7, "burst_cooldown": [2.0, 2.5],
		"pellets": 1, "spread_deg": 0.0, "bullet_speed": 1100.0, "aim_variance_deg": 7.5,
		"windup_sec": 0.3,
		"body_size": 56.0,
	},
	"square": {
		# Sniper: one heavy shot per cycle. 0.7 s laser tell with the aim LOCKED at its
		# start and the square standing still: roll (or step) when you see the line.
		"move_speed": 500.0, "strafe_speed": 300.0,
		"preferred_range": 1500.0, "cast_range": 2400.0,
		"max_health": 700.0, "attack": 200.0, "attacks_per_sec": [1.0, 1.0],
		"burst_count": 1, "burst_cooldown": [2.4, 3.2],
		"pellets": 1, "spread_deg": 0.0, "bullet_speed": 3000.0, "aim_variance_deg": 0.0,
		# The laser TRACKS you for most of the wind-up and locks lock_before s
		# before the shot, leading your movement: walk straight and you get hit;
		# change direction or roll after the lock (the laser flashes white).
		"windup_sec": 0.7, "aim_lock": true, "windup_root": true, "lock_before": 0.2,
		"body_size": 60.0,
	},
	"hexagon": {
		# Lobber / area denial (new, E2+): calls a rain zone down on you (1 s target
		# marker before it lands, see rain_projectile.gd), three in a scattered burst.
		# Can't hit what it can't see; weak up close, so close the distance.
		"move_speed": 550.0, "strafe_speed": 350.0,
		"preferred_range": 1300.0, "cast_range": 2400.0,
		"max_health": 500.0, "attack": 120.0, "attacks_per_sec": [2.5, 2.5],
		"burst_count": 3, "burst_cooldown": [3.5, 4.5],
		"pellets": 1, "spread_deg": 0.0, "bullet_speed": 1100.0, "aim_variance_deg": 0.0,
		"attack_form": "rain", "lob_scatter": 260.0,
		"windup_sec": 0.4,
		"body_size": 62.0,
	},
}
# Elite AFFIXES (Phase 3, Diablo-style): silver rolls 1, gold rolls 2, from the map's
# MapDef.affix_pool. Rolled deterministically (expedition seed ^ name) so every peer
# agrees with no networking, and drawn as marks on the body glyph.
#   fast     +30% move/strafe, +20% bullet speed
#   armored  takes 30% less damage
#   shielded an element-coloured shield soaks SHIELD_HP; a hit from an element that
#            beats it shatters it instantly (the wheel as a tactic)
#   warder   a telegraphed 0.4 s pulse (burst) when a player is within WARDER_RANGE
const AFFIXES := ["fast", "armored", "shielded", "warder"]
const SHIELD_HP := 300.0
const ARMORED_MULT := 0.7
const WARDER_RANGE := 520.0
const WARDER_INTERVAL := 4.0
const WARDER_CHARGE := 0.4
const WARDER_DAMAGE := 120.0
var affixes: Array = []
# Synced (enemy.tscn) so a late arrival sees a shield the server already broke.
var shield_up := false:
	set(value):
		shield_up = value
		if body:
			body.shield_up = value
			body.queue_redraw()
var _bullet_speed_mult := 1.0
var _shield_hp := 0.0
var _warder_timer := 0.0
var _warder_charge := 0.0

# Elites are a beefier, gold-tinted, bigger version of any archetype with better loot.
const TIERS := {
	# bronze = baseline, silver = the "elite" (tougher + better loot), gold = locked-area
	# only (not spawned yet — see enemy_spawner). Loot comes from LOOT_TABLES[archetype]
	# [tier]; these just scale stats + tint the sprite so a tier reads at a glance.
	"bronze": {"health_mult": 1.0, "attack_mult": 1.0, "scale": 1.0, "tint": Color(1, 1, 1)},
	"silver": {"health_mult": 1.6, "attack_mult": 1.5, "scale": 1.25, "tint": Color(0.8, 0.85, 0.95)},
	"gold": {"health_mult": 4.0, "attack_mult": 2.0, "scale": 1.5, "tint": Color(1.0, 0.85, 0.35)},
}
var health := max_health:
	set(value):
		health = value
		if health_bar:
			health_bar.value = health
var is_dead := false:
	set(value):
		var was_dead := is_dead
		is_dead = value
		# Death shatter + a little shake, once, on the alive->dead edge (the synced
		# setter re-runs every tick on clients). Skipped for enemies restored as
		# already-dead on room load (spawned this very moment).
		if value and !was_dead and is_inside_tree() and Engine.get_process_frames() - _spawn_frame > 5:
			Fx.shatter(get_tree(), global_position, body.fill_color if body else Color.WHITE, clampf(body.half_size / 56.0, 0.7, 1.6) if body else 1.0)
			Fx.shake_at(get_tree(), global_position, 0.22)
			Sounds.play_sfx("enemy_die", global_position)
		if value:
			_release_token()
			velocity = Vector2.ZERO
			if visual_root:
				visual_root.visible = false
			if hurtbox:
				hurtbox.is_invincible = true
			# Loot is rolled/broadcast from die() instead, not here — see its
			# comment for why. Freeing is deferred (not instant) because this
			# setter also runs on every remote peer the moment is_dead's
			# on-change sync arrives — freeing the node immediately here would
			# race against MultiplayerSynchronizer's own outgoing flush on the
			# AUTHORITY side specifically: if the server frees the node in the
			# same frame it sets is_dead = true, the synchronizer can be torn
			# down before it ever gets a chance to actually send that final
			# update, leaving remote peers permanently stuck seeing a "dead"
			# enemy that never received the is_dead flag at all.
			_defer_free()

func _defer_free() -> void:
	await get_tree().create_timer(0.3).timeout
	if is_inside_tree():
		queue_free()

@export var move_speed := 680.0

# While in range and firing, an enemy strafes sideways relative to the target
# (flipping direction at random intervals) so it's a moving target that's harder
# to line up a shot on — a light "try to avoid damage" behavior. Firing rate is
# unaffected: it keeps casting every frame it can still see the target.
@export var strafe_speed := 420.0
const STRAFE_FLIP_MIN := 0.6
const STRAFE_FLIP_MAX := 1.5
var _strafe_sign := 1.0
var _strafe_timer := 0.0
# Per-enemy sideways chase bias (set in _ready) — see FLANK_OFFSET_MAX / _flank_chase_target.
var _flank_offset := 0.0

# Casting behavior: stays put and casts while the target is within
# cast_range and in line of sight; otherwise closes the distance. Fire rate
# is no longer a flat timer — it's set per-shot from the same
# FORMS[form]["attack_cooldown"] the player uses, so the enemy can loose
# spells exactly as often as a player with the same weapon/form could.
@export var cast_range := 2560.0
# EtG-style: the enemy HOLDS around this distance and shoots — it never closes to
# melee. It only casts forms that can reach from here (short-range forms are skipped
# in favor of ranged defaults; see _plan_next_cast). Pursue if farther than
# preferred_range + RANGE_BUFFER, back off if closer than preferred_range - RANGE_BUFFER,
# hold/strafe within that band.
@export var preferred_range := 1600.0
# ELEMENTAL enemies (2026-08-30): true = an enemy NEVER casts spells, it only does
# its archetype's signature basic attack (pentagon fan / triangle spread / circle
# stream / square snipe). Default true — for lore, enemies are elemental: no gear,
# no weapons, no casting, just predictable attacks. Flip false to re-enable the
# dormant weapon-form/sequence casting (see _plan_next_cast). Element colors the
# shot + drives the crit matchup either way.
@export var uniform_bullets := true
@export var tap_interval := 0.35
var cast_timer := 0.0
# Whether we had a target last frame — lets us detect a FRESH acquisition (null ->
# target) and stagger the first shot by a random 0..ENGAGE_DELAY_MAX.
var _was_engaged := false
var tap_timer := 0.0
var spell_input_sequence: Array[int] = []
var target_recipe_sequence: Array = []
# Fire this many plain default attacks between sequence spells (re-rolled each
# time a sequence goes off) so enemies don't just spam sequences.
const MIN_DEFAULTS_BETWEEN_SEQUENCES := 3
const MAX_DEFAULTS_BETWEEN_SEQUENCES := 5
var _default_shots_remaining := 0
# The distance the cast we're about to make can actually reach (its projectile's
# real travel range, or a short-range form's declared reach). The combat movement
# closes in instead of strafing until the target is inside it, so shots always
# connect instead of fizzling short.
var _advance_range := 0.0
# The next cast is decided (planned) up front so we know how close to get, then
# only fired once we're in range — see _plan_next_cast / _execute_planned_cast.
var _planned_form := ""
var _planned_recipe: Dictionary = {}
# Stand a bit inside a cast's max reach so shots comfortably land, not right at
# the fizzle edge.
const ENGAGE_MARGIN := 0.85
# This enemy's default-attack reach (set in _ready). While closing in for a
# shorter-range sequence, it keeps firing defaults out to this range so it's
# applying pressure, not just tanking damage during the approach.
var _default_range := 0.0
# Small ± random spread on every shot's aim, so a stream of shots isn't a single
# dodge-one-dodge-them-all line — a wider cone gives the volley more variety.
var aim_variance := deg_to_rad(5.0)  # random per-shot aim spread (radians); per-archetype, set from aim_variance_deg in _apply_archetype
# Cheap first-order target leading: aim where the target will be by the time the
# shot reaches it, from a smoothed estimate of its velocity (target_velocities).
const VELOCITY_SMOOTHING := 0.25
var target_velocities: Dictionary = {}
# Bounds on that lead, so a FAST target (e.g. someone rushing us) can't shift the
# aim so far it overshoots behind us and the shot flips to point the wrong way.
# Cap the flight-time estimate, AND the final lead offset to a fraction of the gap.
const MAX_LEAD_TIME := 0.6
const MAX_LEAD_FRACTION := 0.7

# Facing/vision cone: LOS is only granted within fov_degrees of the
# direction the enemy is currently facing, and facing turns toward whatever
# it's tracking (the point it's aiming at while casting, or its travel
# direction while chasing) at a limited rate rather than snapping — so a
# target directly behind it is genuinely out of view until it turns.
@export var fov_degrees := 160.0
@export var turn_speed := 6.0
var facing_direction := Vector2.DOWN
var current_visible_point := Vector2.ZERO
@onready var facing_indicator: Node2D = $visual_root/facing_indicator
const FACING_INDICATOR_DISTANCE := 192.0

# This enemy's own weapon/element identity — used both when it casts spells
# (as the attacker) and when a player's spell hits it (as the defender),
# same as a player's equipped Weapon serves both roles. Replicated so every
# peer shows the same color/letter and applies the same matchups regardless
# of who detects a given hit.
var attacker_weapon: String = "tome":
	set(value):
		attacker_weapon = value
		_update_visual()
var attacker_element: String = "fire":
	set(value):
		attacker_element = value
		_update_visual()
# The forms this enemy's weapon actually holds — rolled 1-3 at spawn (see
# _ready()) from the type's capable list, exactly like a real weapon now
# carries a subset of Form Stones rather than all three. Drives which
# sequences it can cast AND, if its weapon drops, which forms the dropped
# weapon comes with (see die()). Server-rolled and only ever read
# server-side (AI casting runs on the authority; the fire_spell RPC carries
# the chosen form string to peers), so it needs no replication — just
# persistence across room revisits (see enemy_spawner.gd).
var attacker_forms: Array = []

@onready var hurtbox: Hurtbox = $hurtbox
@onready var detection_area: Area2D = $detection_area
@onready var visual_root: Node2D = $visual_root
@onready var body: EnemyBody = $visual_root/body
@onready var health_bar: ProgressBar = $visual_root/health_bar
@onready var nav_agent: NavigationAgent2D = $nav_agent

var targets_in_range: Array[Hurtbox] = []
var current_target: Hurtbox = null

# --- Aggro ---------------------------------------------------------------
# Recent damage each player has dealt to this enemy (peer_id -> tally), decaying
# over time. The top-aggro player becomes/steals the target so whoever deals the
# most damage pulls the enemy onto themselves — see _apply_aggro_target(). Lives
# server-side only (all damage/AI handling is authority-gated).
var _aggro: Dictionary = {}
const AGGRO_DECAY := 12.0          # tally points shed per second
const AGGRO_MIN := 1.0             # ignore trivial tallies
const AGGRO_SWITCH_RATIO := 1.5    # must out-aggro the current target by this to steal

# EtG "approach then hold": pursue to preferred_range, then hold within a small
# deadzone around it (±RANGE_BUFFER) rather than twitching in/out to sit on the exact
# distance. Only re-close if we've drifted more than the buffer beyond it, only back
# off if the target has crowded more than the buffer inside it.
const RANGE_BUFFER := 80.0
# Each enemy's hold distance is jittered ±this fraction of its archetype preferred_range
# (rolled once in _apply_archetype) so a pack doesn't all freeze at the exact same ring.
const PREFERRED_RANGE_VARIANCE := 0.15
# Combat velocity is EASED toward its target each frame (units/sec^2) instead of snapped,
# so pursue<->strafe flips and the separation/flank nudges read as smooth motion, not
# the frame-to-frame jitter of instantly reassigning velocity.
const COMBAT_ACCEL := 6000.0
# When an enemy first spots the player it waits a random 0..this before its FIRST shot,
# so a group that all acquires the target at once doesn't fire one synchronized volley
# (and their burst cycles start out of phase). Re-rolled on each fresh acquisition.
const ENGAGE_DELAY_MAX := 1.0
# Move faster while OUTSIDE our hold range (catching up / closing the gap) so enemies
# don't feel sluggish on the approach, then settle to normal speed once in range.
const PURSUE_SPEED_MULT := 1.25
# Flank-chase: while chasing a target we can't yet shoot, aim at a point offset to one
# side of the direct line (per-enemy signed `_flank_offset`, so packmates take DIFFERENT
# nav routes and approach from spread bearings instead of single-filing behind you), plus
# a lead ahead of the target's motion (so a faster fleeing player gets cut off, not just
# tailed). Only affects the out-of-shooting-range chase branch.
const FLANK_OFFSET_MAX := 700.0   # max sideways offset (world units), signed per enemy
const CHASE_LEAD_TIME := 0.6      # seconds of the target's velocity to aim ahead
const CHASE_LEAD_MAX := 700.0     # cap on that lead so it never overshoots wildly
# Flanking: packmates whose bearing to the target is within this angle of ours push
# each other sideways (tangentially, around the target) so the group fans out and
# shots arrive from a spread of angles instead of one cluster. Emergent + local (per
# group), so it copes with any pack size and walls. Push magnitude is strafe_speed.
const FLANK_SPREAD_ANGLE := deg_to_rad(50.0)

# Only updated while we can actually see the target — this is where we
# path to once LOS breaks, not their live position. If we arrive there
# without re-spotting them, we give up (current_target = null) instead of
# omnisciently continuing to track wherever they currently are.
var last_known_position: Vector2 = Vector2.ZERO

# Corner-easing: if we're barely moving over a short window while trying to
# chase (jammed against a corner), stop pushing straight at the next
# waypoint and instead slide along the wall we're stuck on. Checked over a
# window rather than per-frame, since normal per-frame movement is already
# smaller than a naive single-frame threshold would allow for.
var last_stuck_check_position: Vector2 = Vector2.ZERO
var stuck_check_timer := 0.0
var is_easing_around_corner := false
const STUCK_CHECK_INTERVAL := 0.2
const STUCK_DISTANCE := 128.0

# Enemies now collide with each other (see enemy.tscn's collision_mask), so
# hard collision alone would otherwise just shove them into each other's
# blocked-path handling and feel jerky. A soft steering push away from
# anyone crowding closer than min_enemy_separation, blended continuously
# into the movement velocity, keeps a little personal space without them
# ever having to hard-stop against one another.
@export var min_enemy_separation := 112.0
# Matches the actual physics CircleShape2D_body radius (enemy.tscn) — it was 28
# here while the body was really 10px, which over-spread groups (desired_min was
# 84px) and disagreed with the navmesh clearance. Kept in sync now.
const BODY_RADIUS := 48.0
# Extra half-width added to BODY_RADIUS when deciding an ally is "in our firing lane"
# (see _ally_in_firing_lane) — roughly the bullet's own half-width plus a little slack
# so we hold fire a touch before a shot would actually graze them.
const ENEMY_LANE_CLEARANCE := 40.0
const SEPARATION_CHECK_RADIUS := 640.0
const SEPARATION_RESPONSE := 6.0

# --- Performance ----------------------------------------------------------
# Distance LOD: an enemy with no target and no player within SLEEP_RANGE does no
# per-frame work at all (no LOS/separation physics queries, no pathing) until a
# player comes near. SLEEP_RANGE is comfortably beyond the detection radius, so
# an enemy always wakes well before it could ever need to notice anyone.
const SLEEP_RANGE := 4800.0
var _world: Node = null
# Separation runs a physics query; recompute it only every few frames and reuse
# the cached push in between (positions barely change frame-to-frame).
const SEPARATION_RECALC_FRAMES := 3
var _separation_cache := Vector2.ZERO
var _separation_countdown := 0
# Preallocated query objects, reused every frame — building a Shape2D + query
# params on every call was needless per-frame garbage across every enemy.
var _sep_shape: CircleShape2D
var _sep_query: PhysicsShapeQueryParameters2D
var _los_shape: CircleShape2D
var _los_query: PhysicsShapeQueryParameters2D
# A plain ray alongside the swept circle. cast_motion IGNORES any wall the swept
# circle already overlaps at its origin — so an enemy standing within the circle's
# radius of a wall (extremely common) would see straight through that exact wall.
# The ray's origin is the enemy's center, which is always in open space (the body
# collides with walls, so it can't be inside one), so the ray never ignores the
# blocking wall. Requiring BOTH clear keeps the circle's corner-pinhole guard
# while closing that see-through-the-wall-you're-touching leak.
var _los_ray: PhysicsRayQueryParameters2D

# When we give up on a target (arrived at their last known position without
# re-spotting them), that same target is ineligible for re-acquisition for a
# brief moment — otherwise a single flickering frame of LOS right where we
# just stood (very plausible, since give-up happens right at/near the
# corner they were last seen at) would re-lock on with no real gap at all.
# Short enough that it's just an anti-flicker guard, not a real delay.
var recently_lost_target: Hurtbox = null
var lost_target_cooldown := 0.0
const LOST_TARGET_COOLDOWN := 0.5

# Even with zero LOS, a target close enough to hear is still "known" —
# footsteps/casting noise don't care about walls or the vision cone the way
# sight does, so this check is pure distance, no shape-cast or FOV test.
# But a perfectly still player makes no noise to hear in the first place, so
# hearing-based ACQUISITION (not ongoing awareness of an already-known
# target — see the separate can_hear check in _physics_process) additionally
# requires them to have actually moved since last physics frame.
@export var hearing_radius := 1024.0
var last_target_positions: Dictionary = {}
var target_is_moving: Dictionary = {}
const MOVEMENT_THRESHOLD := 8.0

# Getting hit from outside our vision/hearing range (a shot from off-screen
# or from behind, out of the cone) has no current_target to chase — but it
# shouldn't be a total non-event either. We pick a random reachable point
# roughly where the shot direction points and go investigate. If nothing
# navigable turns up near that guess (e.g. it's inside/behind a wall), we
# still walk toward the edge of our own vision range in that direction
# instead of just standing there.
@export var investigate_distance := 2240.0
@export var investigate_jitter := 640.0
const INVESTIGATE_ATTEMPTS := 8
const MIN_INVESTIGATE_DISTANCE := 384.0
var is_investigating := false
var investigate_target := Vector2.ZERO

# When there's nothing to chase, react to, or investigate, the enemy
# alternates between wandering to a random reachable point near its spawn
# and pausing to "look around" (search) before picking the next wander
# point. Each search has a small chance of relocating "home" (spawn_position)
# to right where the enemy is standing, so a wandering enemy can gradually
# drift to a new area over time instead of being tied to its original spot
# forever.
enum IdleState { WANDER, SEARCH }
@export var wander_radius := 3840.0
@export var wander_radius_variance := 320.0
@export var search_duration := 16.0
@export var search_duration_variance := 2.0
@export var search_turn_speed := 1.0
@export var search_turn_speed_variance := 0.3
@export var new_spawn_chance := 0.05
# A follower wanders within THIS radius of its (moving) leader instead of the full
# wander_radius, so a spawned pack stays a visible clump while patrolling rather
# than scattering across the map into apparent lone enemies. Only a leaderless
# enemy roams the full wander_radius around its own spawn.
@export var follower_wander_radius := 1024.0
const WANDER_SNAP_TOLERANCE := 640.0
var spawn_position := Vector2.ZERO
var idle_state: int = IdleState.WANDER
var wander_target := Vector2.ZERO
var wander_target_valid := false
var search_timer := 0.0
# Rolled once per enemy at spawn so it stays consistent for that enemy's
# whole lifetime, rather than being different every single search — the
# goal is desyncing different enemies from each other, not variety within
# one enemy's own repeated cycles.
var actual_search_turn_speed := 0.0

# Region RIDs existing on the nav map doesn't guarantee their polygon data
# has actually finished syncing into it yet — map_get_iteration_id() > 0
# wasn't a reliable signal for this (see _physics_process's guard), so
# this counts consecutive frames of "the map reports regions" and only
# trusts it once that's held for a few frames running, not just once.
var nav_ready_frames := 0
const NAV_READY_FRAME_MARGIN := 3

# If we're stuck fighting a corner (is_easing_around_corner staying true)
# for too long while wandering, the picked point is unreachable in practice
# — abandon it and roll a new one rather than grinding against the wall
# forever.
var wander_stuck_time := 0.0
const WANDER_STUCK_TIMEOUT := 1.0

# Hard backstop independent of the above: wander_stuck_time resets to 0 the
# instant any single 0.2s window shows enough movement, which incidental
# jitter (a nearby enemy's separation push, a glancing bounce off the wall)
# can trigger repeatedly without ever adding up to real progress — letting
# an enemy stay wedged against a wall indefinitely instead of the ~1 second
# that mechanism is supposed to guarantee. This timer can't be reset by
# anything short of actually finishing or abandoning the leg, so it's a
# real ceiling on how long any single wander leg can run.
var wander_leg_timer := 0.0
var wander_leg_max_duration := 0.0
const WANDER_LEG_TIMEOUT_MULTIPLIER := 4.0
const WANDER_LEG_MIN_TIMEOUT := 6.0

# After losing an actively-chased player (not just giving up on an
# investigation), the enemy wanders 0-3 times before deliberately heading
# back to spawn_position once, then resumes free wandering from there.
# -1 means "not in that countdown" (normal free-roaming).
var post_chase_wanders_remaining := -1

# Group behavior: a follower has no wander/search logic of its own — it just
# treats its leader's current position as if it were its own spawn_position,
# so it drifts along with wherever the leader wanders instead of sitting at
# a fixed point. Combat (LOS/hearing/casting/investigating) is entirely
# independent per enemy either way; this only changes the wander anchor.
# null means "no leader" — either always solo, or the leader has died and
# this enemy already got promoted (or fell back) to being its own leader.
var leader: Enemy = null

# All members of this enemy's spawn group (including the leader), the SAME
# Array object shared by reference across every member — set once by
# enemy_spawner.gd. Never pruned in place (see promote_new_leader(), which
# filters into a local copy instead) so every member's view of "who's still
# around" stays consistent within a frame regardless of processing order.
var group: Array[Enemy] = []

# The 1-2 element types this whole spawn group draws from, so a pack reads as
# cohesive instead of a rainbow of all 7 elements. Set by the spawner BEFORE
# add_child (same Array shared across the group); each member then rolls its own
# element from just this palette in _ready. Empty = fall back to the full roster.
var group_elements: Array = []

# Pick the 1-2 distinct element types for one spawn group off a seeded rng, so
# every peer derives the same palette. The per-member element is then rolled
# from this subset (see _ready).
static func pick_group_elements(rng: RandomNumberGenerator) -> Array:
	var pool: Array = ELEMENT_TYPES.duplicate()
	var count: int = rng.randi_range(1, 2)
	var result: Array = []
	for i in count:
		var idx: int = rng.randi_range(0, pool.size() - 1)
		result.append(pool[idx])
		pool.remove_at(idx)
	return result

func get_wander_anchor() -> Vector2:
	if leader != null and is_instance_valid(leader) and !leader.is_dead:
		return leader.global_position
	return spawn_position

# Runs on every surviving follower once their leader is confirmed gone.
# Rather than each one independently going solo, the group promotes its
# most-senior surviving member (deterministic: first non-dead entry in the
# shared, never-mutated group list) to be the new leader, and everyone else
# just follows them instead. Safe to call redundantly from multiple
# members in the same frame regardless of _physics_process order — see the
# comment on `group` above.
func promote_new_leader() -> void:
	var survivors: Array = group.filter(func(m): return is_instance_valid(m) and !m.is_dead)
	if survivors.is_empty():
		spawn_position = global_position
		leader = null
		return
	var new_leader: Enemy = null
	for m in survivors:
		if m.leader == null:
			new_leader = m
			break
	if new_leader == null:
		new_leader = survivors[0]
	if new_leader == self:
		spawn_position = global_position
		leader = null
	else:
		leader = new_leader

# Groupmates within earshot of whatever just happened (spotting the player,
# or getting hit by them) react too, instead of only the one enemy that
# actually noticed anything. known_target null means we only have a rough
# direction (e.g. a blind hit), so nearby idle groupmates go investigate
# that point rather than being handed a definite lock they didn't earn.
func alert_nearby_group(known_target: Hurtbox, known_point: Vector2) -> void:
	for member in group:
		if member == self or !is_instance_valid(member) or member.is_dead:
			continue
		if member.current_target != null:
			continue
		if global_position.distance_to(member.global_position) > hearing_radius:
			continue
		if known_target != null:
			member.current_target = known_target
			member.last_known_position = known_point
		else:
			member.start_investigating(member.global_position.direction_to(known_point))

# Frame this enemy entered the tree (see is_dead's death-FX guard).
var _spawn_frame := 0
# Server-side knockback impulse (u/s), decays fast; see KNOCKBACK_*.
var _knockback := Vector2.ZERO
const KNOCKBACK_SPEED := 1400.0
const KNOCKBACK_DECAY := 9000.0
const SHOVE_SPEED := 4200.0
const SHOVE_STAGGER := 0.8

# Server: a player's melee shove. Big knockback plus a stagger that cancels any
# wind-up in progress and delays the next attack.
func apply_shove(dir: Vector2) -> void:
	if !is_multiplayer_authority() or is_dead:
		return
	_knockback += dir.normalized() * SHOVE_SPEED
	_cancel_windup()
	_warder_charge = 0.0
	cast_timer = maxf(cast_timer, SHOVE_STAGGER)

func _ready() -> void:
	_spawn_frame = Engine.get_process_frames()
	hurtbox.hurt.connect(_on_hurtbox_hurt)
	detection_area.area_entered.connect(_on_detection_area_entered)
	detection_area.area_exited.connect(_on_detection_area_exited)
	# Vision radius and the projectile travel cap are the same number by design
	# (SpellData.ENGAGEMENT_RANGE) so you can't hit an enemy from beyond where it
	# could ever spot you. Drive it from the constant here — duplicate the shape
	# first so we're not mutating the shared resource every other enemy uses.
	var det_shape := detection_area.get_node("collision_shape_2d") as CollisionShape2D
	if det_shape != null and det_shape.shape is CircleShape2D:
		det_shape.shape = det_shape.shape.duplicate()
		(det_shape.shape as CircleShape2D).radius = SpellData.ENGAGEMENT_RANGE
	# name.hash() (not get_instance_id()) so this identifier is identical on
	# every peer's local copy of this same static, room-baked enemy —
	# get_instance_id() is process-local and would differ per peer, silently
	# breaking self-hit exclusion on whichever clients don't match.
	hurtbox.owner_id = name.hash()
	# In the "enemies" group on every peer so a beam this enemy casts can resolve
	# it as its caster (by matching name.hash()) the same way a player beam finds
	# its caster in world.players — see beam_projectile.gd.
	add_to_group("enemies")
	# Archetype/tier preset (stats, fire rate, health, visual) — runs on every peer.
	_apply_archetype()
	health_bar.max_value = max_health
	health_bar.value = health
	if is_multiplayer_authority():
		attacker_weapon = WEAPON_TYPES.pick_random()
		# Draw from this group's cohesive 1-2 element palette if the spawner set
		# one; otherwise (e.g. a stray/solo enemy) roll from the full roster.
		attacker_element = group_elements.pick_random() if not group_elements.is_empty() else ELEMENT_TYPES.pick_random()
		attacker_forms = _roll_forms(attacker_weapon)
		# Attack/Defense/crit: Attack comes from _apply_archetype (archetype base ×
		# tier multiplier); Defense/crit stay 0 for now.
		# How far this enemy's plain default attack reaches — used to keep up
		# default-attack pressure while closing in for a shorter-range sequence.
		_default_range = SpellData.get_effective_range(attacker_weapon, attacker_element, "default", true) * ENGAGE_MARGIN
		spawn_position = global_position
		# Face a random direction to start (rolled per-enemy) so a freshly spawned
		# group isn't all staring the same way.
		facing_direction = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		# Which side (and how far) this enemy biases its chase toward, so a pack fans out
		# and flanks rather than stacking single-file on the target (see _flank_chase_target).
		_flank_offset = randf_range(-FLANK_OFFSET_MAX, FLANK_OFFSET_MAX)
		# Rolled once and kept for this enemy's life — magnitude varies, and the
		# sign randomly flips so some search by sweeping clockwise and others
		# counter-clockwise instead of every enemy spinning the same way.
		actual_search_turn_speed = max(0.1, search_turn_speed + randf_range(-search_turn_speed_variance, search_turn_speed_variance))
		if randf() < 0.5:
			actual_search_turn_speed = -actual_search_turn_speed
		# Start idle by looking around rather than immediately wandering off.
		idle_state = IdleState.SEARCH
		search_timer = search_duration + randf_range(-search_duration_variance, search_duration_variance)
		# Open an engagement with a run of default attacks before the first
		# sequence, rather than possibly leading with a sequence.
		_default_shots_remaining = randi_range(MIN_DEFAULTS_BETWEEN_SEQUENCES, MAX_DEFAULTS_BETWEEN_SEQUENCES)
		# Build the reusable physics-query objects once (only the authority runs
		# the queries that use them — see _physics_process's early-out above).
		_sep_shape = CircleShape2D.new()
		_sep_shape.radius = SEPARATION_CHECK_RADIUS
		_sep_query = PhysicsShapeQueryParameters2D.new()
		_sep_query.shape = _sep_shape
		_sep_query.collision_mask = 32
		_sep_query.exclude = [get_rid()]
		_los_shape = CircleShape2D.new()
		_los_shape.radius = 64.0
		_los_query = PhysicsShapeQueryParameters2D.new()
		_los_query.shape = _los_shape
		_los_query.collision_mask = 1
		_los_query.exclude = [get_rid()]
		_los_ray = PhysicsRayQueryParameters2D.new()
		_los_ray.collision_mask = 1
		_los_ray.exclude = [get_rid()]
		_los_ray.hit_from_inside = true
	_update_visual()

# 1-3 distinct forms from the weapon type's capable list, shuffled so it's a
# random subset (not always the first N). Mirrors how a looted weapon carries
# an arbitrary handful of Form Stones rather than the full set.
func _roll_forms(weapon_type: String) -> Array:
	var pool: Array = SpellData.get_capable_forms(weapon_type).duplicate()
	pool.shuffle()
	var count: int = clampi(randi_range(1, 3), 1, pool.size())
	return pool.slice(0, count)

# Body glyph: shape = archetype (pentagon/triangle/circle/square — the archetype key
# IS the shape drawn), fill = element color, border = tier color. Re-run whenever
# element/archetype/tier is known/changes.
func _update_visual() -> void:
	if !body:
		return
	var element_data: Dictionary = SpellData.ELEMENTS.get(attacker_element, SpellData.ELEMENTS["default"])
	var half: float = ARCHETYPES.get(archetype, ARCHETYPES["pentagon"]).get("body_size", 64.0)
	body.configure(archetype, element_data["color"], _tier_border(), half)

const TIER_BORDERS := {
	"bronze": Color(0.72, 0.45, 0.2),
	"silver": Color(0.82, 0.84, 0.9),
	"gold": Color(1.0, 0.82, 0.25),
}
func _tier_border() -> Color:
	return TIER_BORDERS.get(tier, TIER_BORDERS["bronze"])

# facing_direction itself is only ever simulated on the authority (see
# _physics_process's early return above), but the indicator's on-screen
# position needs to update for every peer — this runs unconditionally so
# remote viewers, who only ever receive facing_direction via replication,
# still see the dot move instead of sitting frozen at its spawn position.
# Networked position: the server (authority) writes its true global_position here
# each frame; remote copies buffer + interpolate it (see NetInterpolator) instead
# of snapping to raw replicated values, which is what made remote enemies jitter.
@export var net_position := Vector2.ZERO
var _pos_interp := NetInterpolator.new()
var _last_net_pos := Vector2(INF, INF)

func _process(_delta: float) -> void:
	if is_multiplayer_authority():
		# Publish our authoritative position for remote copies to interpolate.
		net_position = global_position
	else:
		# Remote copy: interpolate toward buffered snapshots (no raw snapping).
		# Adopt the first observed value without pushing it — before the first
		# sync, net_position is still (0,0); pushing that would yank the enemy
		# (which is already at its deterministic spawn spot) to the origin.
		if _last_net_pos == Vector2(INF, INF):
			_last_net_pos = net_position
		elif net_position != _last_net_pos:
			_pos_interp.push(net_position)
			_last_net_pos = net_position
		if _pos_interp.has_data():
			global_position = _pos_interp.sample()
	if facing_indicator:
		facing_indicator.position = facing_direction * FACING_INDICATOR_DISTANCE
	_update_tracking_laser()

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		return
	if is_dead:
		return
	if _knockback.length_squared() > 1.0:
		move_and_collide(_knockback * delta)
		_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	if NavigationServer2D.map_get_regions(nav_agent.get_navigation_map()).is_empty():
		# The nav map hasn't finished its first sync yet (region registration
		# happens a frame or so after scene load) — every NavigationServer2D
		# query against an empty map returns Vector2.ZERO instead of a real
		# snapped point, which is exactly (0, 0), i.e. this room's own
		# player spawn point. Querying it this early was making every
		# freshly-spawned enemy's very first wander target resolve to the
		# player's spawn, making it look like they'd all beelined straight
		# there the instant the room loaded. Just wait for it to sync
		# instead of trusting a bogus result.
		nav_ready_frames = 0
		velocity = Vector2.ZERO
		move_and_slide()
		return
	nav_ready_frames += 1
	if nav_ready_frames <= NAV_READY_FRAME_MARGIN:
		# Regions existing doesn't guarantee their polygon data has fully
		# synced into the map yet either — a few frames of margin past
		# that first sign of life is cheap insurance against the exact
		# same bug recurring.
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if leader != null and (!is_instance_valid(leader) or leader.is_dead):
		promote_new_leader()
	cast_timer = max(cast_timer - delta, 0.0)
	lost_target_cooldown = max(lost_target_cooldown - delta, 0.0)
	# Distance LOD: with nothing to fight and no player anywhere near, skip the
	# whole expensive frame (target scan, LOS/separation queries, pathing). The
	# enemy just holds still until a player closes to SLEEP_RANGE — which is well
	# outside its detection radius, so it never sleeps through a real encounter.
	if current_target == null and _nearest_player_distance() > SLEEP_RANGE:
		velocity = Vector2.ZERO
		return
	update_current_target()
	# Fresh acquisition (was targetless, now have one): delay the first shot a random
	# 0..ENGAGE_DELAY_MAX so a whole pack spotting you at once doesn't volley in unison
	# and their burst cycles start out of phase. maxf so it never shortens a real cooldown.
	if current_target != null and not _was_engaged:
		cast_timer = maxf(cast_timer, randf_range(0.0, ENGAGE_DELAY_MAX))
	_was_engaged = current_target != null
	if current_target != null:
		is_investigating = false
	if current_target == null:
		if is_investigating:
			if follow_nav_path(delta, investigate_target):
				is_investigating = false
		else:
			update_idle(delta)
		reset_casting()
		move_and_slide()
		if facing_indicator:
			facing_indicator.position = facing_direction * FACING_INDICATOR_DISTANCE
		return
	var visible_point = get_visible_point(current_target)
	# Stillness stealth (cloak_unseen_still) only prevents an enemy from SPOTTING
	# you in the first place (see the acquisition check in update_current_target) —
	# it does NOT hide you from an enemy already locked onto you. Once it's in
	# combat with you, freezing won't break its line of sight; you have to actually
	# break LOS / range and let it give up. Hearing-silence still gates can_hear.
	var can_see := visible_point != null
	var distance := global_position.distance_to(current_target.global_position)
	var can_hear := distance <= hearing_radius and not _target_silent(current_target)
	# Hearing reveals location the same as sight would (no wall/FOV check),
	# but only sight lets us aim — you can't snipe someone you only hear
	# through a wall, so current_visible_point stays sight-only.
	var aware := can_see or can_hear
	if aware:
		last_known_position = current_target.global_position
	if can_see:
		current_visible_point = visible_point

	var on_screen := _target_on_screen(current_target)
	_update_warder(delta, distance)
	if can_see and distance <= cast_range and on_screen and _center_shot_clear(current_target):
		var to_target := current_visible_point - global_position
		var dir := to_target.normalized()
		# Clean lane to their center — hold at a FIXED comfortable range and shoot;
		# never close to melee (this game has no melee). preferred_range is independent
		# of the spell's reach; short-range forms are simply never planned.
		_update_stuck_state(delta)
		var move_intent := Vector2.ZERO
		var hold_range := _effective_preferred_range(current_target)
		if distance > hold_range + RANGE_BUFFER:
			# PURSUE — we've drifted past the hold band; close the gap back to it, a bit
			# faster than normal (we're outside our range, catching up).
			move_intent = dir * move_speed * PURSUE_SPEED_MULT
		elif distance < hold_range - RANGE_BUFFER:
			# TOO CLOSE — back off to keep our distance (still facing + firing).
			move_intent = -dir * move_speed
		else:
			# HOLD — inside the ±RANGE_BUFFER band. Strafe sideways so we're a moving
			# target, flipping direction at random intervals so it isn't a predictable
			# pendulum. Firing continues regardless (update_casting below), so movement
			# never slows our shots.
			_strafe_timer -= delta
			if _strafe_timer <= 0.0:
				_strafe_sign = 1.0 if randf() < 0.5 else -1.0
				_strafe_timer = randf_range(STRAFE_FLIP_MIN, STRAFE_FLIP_MAX)
			var perp := Vector2(-to_target.y, to_target.x).normalized()
			move_intent = perp * _strafe_sign * strafe_speed
		# Glide along a wall if our movement is grinding into one, so strafing or
		# pursuing beside cover slides around the corner instead of jamming on it. Plus a
		# tangential fan-out so packmates don't stack onto one bearing (see _flank_spread).
		var target_velocity := _deflect_around_walls(move_intent) + compute_separation() \
			+ _flank_spread(current_target.global_position)
		# Ease toward the target velocity rather than snapping to it every frame, so the
		# pursue<->strafe flips and separation/flank nudges glide instead of jittering.
		if _windup_root and _windup_left > 0.0:
			target_velocity = Vector2.ZERO
		velocity = velocity.move_toward(target_velocity, COMBAT_ACCEL * delta)
		update_facing(delta, current_visible_point - global_position)
		# Hold fire if an ally sits in our line to the target — we'd shoot them in the
		# back (enemies CAN hurt each other again; see Hitbox.can_hit). We keep strafing
		# (above) so our angle shifts to a clean lane, and cast_timer keeps counting in
		# the main loop, so we loose the shot the instant the lane clears.
		if not _ally_in_firing_lane(current_visible_point):
			update_casting(delta, distance)
		elif _windup_left > 0.0:
			# Lane blocked mid-tell: drop the wind-up (and its root) so we can move to
			# a clean lane, and wind up fresh (with a fresh tell) once it's clear.
			_cancel_windup()
	elif can_see and distance <= cast_range and on_screen:
		# We can SEE them (an edge peeking past cover) but a wall blocks a real shot at
		# their center — planting here just plinks the corner (the bug where an enemy
		# sat and shot the wall for free). Path AROUND the cover via the navmesh to earn
		# a clean line, and hold fire until we have one.
		follow_nav_path(delta, current_target.global_position)
		update_facing(delta, current_visible_point - global_position)
		reset_casting()
	else:
		# Chase the live position while we're still aware of them (in sight
		# or in earshot) — otherwise head for their last-known spot and give
		# up once we get there without re-spotting/re-hearing them.
		var chase_target := _flank_chase_target(current_target) if aware else last_known_position
		# Chasing means we're outside our range — close in a bit faster (PURSUE_SPEED_MULT).
		if follow_nav_path(delta, chase_target, move_speed * PURSUE_SPEED_MULT) and !aware:
			recently_lost_target = current_target
			lost_target_cooldown = LOST_TARGET_COOLDOWN
			current_target = null
			# Just lost an actively-chased player — start the wander/return
			# cycle fresh rather than resuming whatever idle state we were
			# in before we ever spotted them.
			post_chase_wanders_remaining = randi_range(0, 3)
			idle_state = IdleState.WANDER
			wander_target_valid = false
		reset_casting()
	move_and_slide()
	if facing_indicator:
		facing_indicator.position = facing_direction * FACING_INDICATOR_DISTANCE

# A per-enemy chase aim-point used while chasing (out of shooting range): offset to one
# side of the direct line (so packmates path apart and flank rather than single-file) and
# led ahead of the target's motion (so a faster fleeing player gets cut off, not tailed).
func _flank_chase_target(target: Node2D) -> Vector2:
	var base: Vector2 = target.global_position
	var to_target := base - global_position
	if to_target.length() < 1.0:
		return base
	var perp := Vector2(-to_target.y, to_target.x).normalized()
	var lead: Vector2 = target_velocities.get(target, Vector2.ZERO) * CHASE_LEAD_TIME
	if lead.length() > CHASE_LEAD_MAX:
		lead = lead.normalized() * CHASE_LEAD_MAX
	return base + lead + perp * _flank_offset

# Steps one physics frame toward target_position along the nav mesh,
# gliding around corners we're jammed against. Returns true once arrived
# (navigation finished) so callers can decide what "arrived" means for them
# (give up on a target, stop investigating, etc). speed defaults to move_speed;
# combat chase/pursue passes a boosted one (PURSUE_SPEED_MULT).
# PERF: NavigationAgent2D re-queries the WHOLE path every time target_position is
# set (Godot deliberately skips the equality check), and the navmesh is thousands
# of per-cell regions, so setting it every physics frame for every enemy was the
# main source of the chug with ~12+ enemies. Only re-target when the goal moved
# meaningfully (or periodically, in case the world changed).
const REPATH_MIN_DISTANCE := 128.0
const REPATH_DISTANCE_FRACTION := 0.15
const REPATH_INTERVAL := 0.5
var _repath_timer := 0.0

func follow_nav_path(delta: float, target_position: Vector2, speed: float = -1.0) -> bool:
	if speed < 0.0:
		speed = move_speed
	_repath_timer -= delta
	var threshold := maxf(REPATH_MIN_DISTANCE, global_position.distance_to(target_position) * REPATH_DISTANCE_FRACTION)
	if _repath_timer <= 0.0 or nav_agent.target_position.distance_to(target_position) > threshold:
		nav_agent.target_position = target_position
		_repath_timer = REPATH_INTERVAL
	_update_stuck_state(delta)
	if nav_agent.is_navigation_finished():
		velocity = compute_separation()
		return true
	var next_point: Vector2 = nav_agent.get_next_path_position()
	var desired_velocity := global_position.direction_to(next_point) * speed
	desired_velocity = _deflect_around_walls(desired_velocity)
	velocity = desired_velocity + compute_separation()
	update_facing(delta, velocity)
	return false

# Every STUCK_CHECK_INTERVAL, flag whether we've barely moved (jammed against
# geometry) so the wall-gliding below only kicks in when we're actually stuck,
# not while walking a clear path. Runs in BOTH nav-pathing and combat movement so
# an enemy holding/strafing beside a wall gets the same corner rescue.
func _update_stuck_state(delta: float) -> void:
	stuck_check_timer -= delta
	if stuck_check_timer <= 0.0:
		var moved := global_position.distance_to(last_stuck_check_position)
		is_easing_around_corner = moved < STUCK_DISTANCE
		last_stuck_check_position = global_position
		stuck_check_timer = STUCK_CHECK_INTERVAL

# If we're grinding against wall(s) instead of making progress, redirect the desired
# movement ALONG the wall so we glide around the corner rather than push straight into
# it. Averages every simultaneous WALL collision normal — at a concave (inside) corner
# two walls collide the same frame, and a tangent from only one often points into the
# other, keeping us stuck; the averaged normal points out of the corner vertex so its
# tangent clears both. Other enemies are skipped (they move, so their normal is jittery
# — separation spaces them). Only active while is_easing_around_corner, so clear-path
# movement is untouched; preserves the desired speed magnitude.
func _deflect_around_walls(desired: Vector2) -> Vector2:
	if not is_easing_around_corner or get_slide_collision_count() == 0:
		return desired
	var normal_sum := Vector2.ZERO
	var wall_hits := 0
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() is Enemy:
			continue
		normal_sum += collision.get_normal()
		wall_hits += 1
	if wall_hits == 0:
		return desired
	var normal: Vector2 = normal_sum.normalized()
	var tangent := Vector2(-normal.y, normal.x)
	if tangent.dot(desired) < 0.0:
		tangent = -tangent
	return tangent * desired.length()

# True only with a clean firing lane to the target's CENTER — a ray plus a swept
# circle (real width, closes the diagonal-corner pinhole) from us to their middle,
# both clear of walls. A mere edge-peek (center blocked) keeps us AWARE of them but is
# NOT enough to plant and shoot: our shots would just clip the corner. On a blocked
# center the combat branch repositions around cover instead of plinking it.
func _center_shot_clear(target: Hurtbox) -> bool:
	if target == null or !is_instance_valid(target):
		return false
	var frame := Engine.get_physics_frames()
	var tid := target.get_instance_id()
	var cached = _center_cache.get(tid)
	if cached != null and frame - int(cached["frame"]) < LOS_CACHE_FRAMES and (frame + _los_stagger()) % LOS_CACHE_FRAMES != 0:
		return cached["clear"]
	var clear := _center_shot_clear_uncached(target)
	_center_cache[tid] = {"frame": frame, "clear": clear}
	return clear

func _center_shot_clear_uncached(target: Hurtbox) -> bool:
	var space_state := get_world_2d().direct_space_state
	var to_center := target.global_position - global_position
	_los_ray.from = global_position
	_los_ray.to = target.global_position
	if not space_state.intersect_ray(_los_ray).is_empty():
		return false
	_los_query.transform = Transform2D(0.0, global_position)
	_los_query.motion = to_center
	var result := space_state.cast_motion(_los_query)
	return result.is_empty() or result[0] >= 1.0

# True if a living ally enemy sits close enough to our line of fire (from us toward
# aim_point) that a shot would pass through — and now damage — them. Only allies IN
# FRONT of us and BEFORE the aim point count: our shots are single-hit and die on the
# first body, so nobody past the target is ever at risk. Pure geometry (point-to-
# segment), no physics query — cheap enough to run per firing enemy each frame.
func _ally_in_firing_lane(aim_point: Vector2) -> bool:
	var origin := global_position
	var lane: Vector2 = aim_point - origin
	var lane_len := lane.length()
	if lane_len < 1.0:
		return false
	var lane_dir := lane / lane_len
	# An ally clips the shot if its body center is within its radius + the bullet's
	# half-width of the line.
	var clearance := BODY_RADIUS + ENEMY_LANE_CLEARANCE
	# Only enemies in OUR room can be in our lane: room spawns and portal waves are
	# both children of the room's `enemies` node, so scan siblings instead of the
	# global group (which also held every enemy in every held room, per shot).
	var parent_node := get_parent()
	if parent_node == null:
		return false
	for other in parent_node.get_children():
		if other == self or not (other is Enemy) or other.is_dead:
			continue
		var to_other: Vector2 = other.global_position - origin
		var along := to_other.dot(lane_dir)
		# Ahead of us (a BODY_RADIUS lead-in so an ally right on top of us doesn't
		# perma-block) and short of where our shot lands.
		if along <= BODY_RADIUS or along >= lane_len:
			continue
		var perp := (to_other - lane_dir * along).length()
		if perp <= clearance:
			return true
	return false

# Soft push away from any other enemy crowding closer than
# min_enemy_separation, scaled by how much that gap is being violated.
# Continuous and additive rather than a hard stop, so a group moving
# together drifts apart smoothly instead of jamming against each other.
func compute_separation() -> Vector2:
	# Throttled: the shape query is the single most-run physics cost across a
	# crowd of enemies, and the push barely changes frame-to-frame. Recompute
	# every few frames and reuse the cached value in between.
	_separation_countdown -= 1
	if _separation_countdown > 0:
		return _separation_cache
	_separation_countdown = SEPARATION_RECALC_FRAMES
	var space_state := get_world_2d().direct_space_state
	_sep_query.transform = Transform2D(0.0, global_position)
	var results := space_state.intersect_shape(_sep_query, 8)
	var desired_min := BODY_RADIUS * 2.0 + min_enemy_separation
	var push := Vector2.ZERO
	for result in results:
		var other = result.get("collider")
		if other == self or not other is Enemy:
			continue
		var offset: Vector2 = global_position - other.global_position
		var dist := offset.length()
		if dist >= desired_min:
			continue
		# When exactly overlapping, offset.normalized() is undefined — pick
		# a direction from the two instance IDs rather than randf(), so
		# it's the same every frame instead of re-rolling and making them
		# jitter in a new random direction each tick while never actually
		# separating.
		var dir := offset.normalized() if dist > 0.001 \
			else Vector2.RIGHT.rotated(float(get_instance_id() - other.get_instance_id()))
		push += dir * (desired_min - dist)
	_separation_cache = push * SEPARATION_RESPONSE
	return _separation_cache

# A tangential push (around target_pos) away from packmates whose bearing to the
# target is within FLANK_SPREAD_ANGLE of ours, so a group fans OUT around the player
# instead of piling onto one arc — shots then arrive from a spread of angles (flanking)
# rather than all from the same direction. Purely angular (distance-keeping stays with
# the pursue/hold/backoff logic), local to the pack, and bounded, so it plays nicely
# with separation + wall-gliding and copes with any pack size.
func _flank_spread(target_pos: Vector2) -> Vector2:
	var my_offset := global_position - target_pos
	var my_dist := my_offset.length()
	if my_dist < 1.0 or group.size() <= 1:
		return Vector2.ZERO
	var my_angle := my_offset.angle()
	var push := 0.0
	for other in group:
		if other == self or not is_instance_valid(other) or other.is_dead:
			continue
		var od: Vector2 = other.global_position - target_pos
		if od.length_squared() < 1.0:
			continue
		# How far around the target this ally sits from us, signed (+ = CCW of us).
		var diff := wrapf(od.angle() - my_angle, -PI, PI)
		var adiff := absf(diff)
		if adiff >= FLANK_SPREAD_ANGLE or adiff < 0.0001:
			continue
		# Slide to the side AWAY from them; nearer bearings push harder.
		push -= signf(diff) * (1.0 - adiff / FLANK_SPREAD_ANGLE)
	if absf(push) < 0.001:
		return Vector2.ZERO
	# Unit CCW tangent around the target, scaled by the (clamped) crowding and our
	# strafe speed so the fan-out never overpowers the pursue/hold movement.
	var tangent := Vector2(-my_offset.y, my_offset.x) / my_dist
	return tangent * clampf(push, -1.0, 1.0) * strafe_speed

# Distance to the closest player (INF if none / world not ready). Cheap loop over
# the handful of players — used by the frame's distance-LOD early-out.
func _nearest_player_distance() -> float:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world")
	if _world == null or _world.players == null:
		return INF
	var nearest := INF
	for p in _world.players.get_children():
		if p is Node2D:
			var d := global_position.distance_to(p.global_position)
			if d < nearest:
				nearest = d
	return nearest

# Every living player's hurtbox (for LOS checks that must ignore the detection
# ring, e.g. reacting to a shot from beyond our vision radius).
func _players_hurtboxes() -> Array:
	var out: Array = []
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world")
	if _world == null or _world.players == null:
		return out
	for p in _world.players.get_children():
		if "hurtbox" in p and p.hurtbox != null and is_instance_valid(p.hurtbox):
			out.append(p.hurtbox)
	return out

# Getting shot spins us toward the threat and lets us scan for the shooter with
# NO radius limit (but still real line of sight — never through walls, and
# ignoring our facing cone since a hit makes us whip around): returns the nearest
# player we can actually see, or null. This is what lets an enemy shot from open
# ground just outside its normal vision radius still spot and lock onto the
# shooter, instead of only trudging over to investigate the shot.
func _spot_shooter_any_range() -> Hurtbox:
	var best: Hurtbox = null
	var best_dist := INF
	for h in _players_hurtboxes():
		if h.is_invincible:
			continue
		if not has_line_of_sight_any_direction(h):
			continue
		var d := global_position.distance_to(h.global_position)
		if d < best_dist:
			best_dist = d
			best = h
	return best

func start_investigating(direction: Vector2) -> void:
	# 95% of the time head roughly toward the shot (the original behavior);
	# 5% of the time flee roughly away from it instead — keeps a
	# blindsided enemy from being 100% predictable.
	var chosen_direction := direction if randf() < 0.95 else -direction
	var map_rid := nav_agent.get_navigation_map()
	var guess := global_position + chosen_direction * investigate_distance
	for i in INVESTIGATE_ATTEMPTS:
		var candidate := guess + Vector2(
			randf_range(-investigate_jitter, investigate_jitter),
			randf_range(-investigate_jitter, investigate_jitter)
		)
		var snapped := NavigationServer2D.map_get_closest_point(map_rid, candidate)
		# map_get_closest_point always returns *some* point on the mesh, even
		# if the candidate was far off it (e.g. inside a wall) — only trust
		# it as "near where the shot came from" if it didn't have to move
		# the candidate more than our own jitter radius to get there. Also
		# reject anything too close to where we're already standing — that
		# would count as "arrived" on the very first frame, making the
		# enemy appear to not react to the hit at all.
		if snapped.distance_to(candidate) <= investigate_jitter \
				and snapped.distance_to(global_position) >= MIN_INVESTIGATE_DISTANCE:
			investigate_target = snapped
			is_investigating = true
			return
	# No usable point near the guess — at least head toward the edge of our
	# own vision range in that direction instead of not reacting at all.
	var edge_point := global_position + chosen_direction * cast_range
	investigate_target = safe_snap_to_nav(edge_point, investigate_jitter * 1.5)
	is_investigating = true

# A loud world noise (the exit portal charging — see exit_portal.gd's noise
# pulses) draws idle enemies toward its source. Heard through walls like other
# hearing, but it only sends them to INVESTIGATE the point — no free target lock,
# and it never overrides an enemy already fighting a real target. Server-only
# (AI runs on the authority alone). Re-fired periodically by the portal, so a
# crowd steadily converges on and mills around it while it charges.
func hear_world_noise(point: Vector2) -> void:
	if !is_multiplayer_authority() or is_dead:
		return
	if current_target != null:
		return
	var snapped := NavigationServer2D.map_get_closest_point(nav_agent.get_navigation_map(), point)
	# Already essentially there — don't thrash a fresh path every pulse; let it
	# wander/hold around the portal instead.
	if global_position.distance_to(snapped) <= MIN_INVESTIGATE_DISTANCE:
		return
	investigate_target = snapped
	is_investigating = true

func update_idle(delta: float) -> void:
	match idle_state:
		IdleState.WANDER:
			if !wander_target_valid:
				pick_next_wander_target()
			if wander_target_valid:
				wander_leg_timer += delta
				var arrived := follow_nav_path(delta, wander_target)
				if is_easing_around_corner:
					wander_stuck_time += delta
					if wander_stuck_time >= WANDER_STUCK_TIMEOUT:
						# Stuck fighting this corner too long — this point
						# isn't practically reachable, so give up on it and
						# roll a fresh one next frame instead of grinding here.
						wander_target_valid = false
						wander_stuck_time = 0.0
				else:
					wander_stuck_time = 0.0
				if wander_target_valid and wander_leg_timer >= wander_leg_max_duration:
					# Absolute backstop: the check above can keep getting
					# reset by incidental jitter that never amounts to real
					# progress, so this timer — which nothing but finishing
					# or abandoning the leg can reset — guarantees a real
					# ceiling on how long any single wander leg can run.
					wander_target_valid = false
					wander_stuck_time = 0.0
				if arrived:
					idle_state = IdleState.SEARCH
					search_timer = search_duration + randf_range(-search_duration_variance, search_duration_variance)
					wander_stuck_time = 0.0
		IdleState.SEARCH:
			velocity = compute_separation()
			# No fixed "desired" direction here (that's what update_facing
			# eases toward) — searching is a continuous sweep, so just spin
			# facing_direction directly at a steady rate.
			facing_direction = facing_direction.rotated(actual_search_turn_speed * delta)
			search_timer -= delta
			if search_timer <= 0.0:
				if randf() < new_spawn_chance:
					spawn_position = global_position
				wander_target_valid = false
				# Fresh baseline so the corner-stuck check doesn't compare
				# against a stale pre-search position and immediately think
				# we're jammed the instant we start moving again.
				last_stuck_check_position = global_position
				stuck_check_timer = STUCK_CHECK_INTERVAL
				idle_state = IdleState.WANDER

func pick_next_wander_target() -> void:
	# Varying the radius per-leg (on top of pick_random_point_near's own
	# random angle/distance within it) gives each leg a slightly different
	# reach — and therefore a slightly different travel time — so a whole
	# group of enemies doesn't visibly settle into the same wander rhythm.
	# Followers stay tight around their (moving) leader so the pack travels as a
	# clump; only a leaderless enemy roams the full wander_radius around its spawn.
	var base_radius := wander_radius
	if leader != null and is_instance_valid(leader) and not leader.is_dead:
		base_radius = follower_wander_radius
	var radius = max(1.0, base_radius + randf_range(-wander_radius_variance, wander_radius_variance))
	var anchor := get_wander_anchor()
	if post_chase_wanders_remaining > 0:
		post_chase_wanders_remaining -= 1
		wander_target = pick_random_point_near(anchor, radius)
	elif post_chase_wanders_remaining == 0:
		# Countdown's up — head deliberately back toward our anchor (the
		# leader, if we still have one, otherwise our own spawn) once, then
		# go back to free-roaming wander/search from there.
		post_chase_wanders_remaining = -1
		wander_target = safe_snap_to_nav(anchor, radius * 1.5)
	else:
		wander_target = pick_random_point_near(anchor, radius)
	wander_target_valid = true
	wander_leg_timer = 0.0
	wander_leg_max_duration = max(
		WANDER_LEG_MIN_TIMEOUT,
		global_position.distance_to(wander_target) / move_speed * WANDER_LEG_TIMEOUT_MULTIPLIER
	)

func pick_random_point_near(center: Vector2, radius: float) -> Vector2:
	var map_rid := nav_agent.get_navigation_map()
	for i in INVESTIGATE_ATTEMPTS:
		var candidate := center + Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * randf_range(0.0, radius)
		var snapped := NavigationServer2D.map_get_closest_point(map_rid, candidate)
		if snapped.distance_to(candidate) <= WANDER_SNAP_TOLERANCE:
			return snapped
	return safe_snap_to_nav(center, radius * 1.5)

# map_get_closest_point always returns *some* point on the mesh — if center
# itself isn't actually near any navigable tile (e.g. an enemy_spawn marker
# sitting outside the baked navigation area), that "closest point anywhere
# on the whole map" can be clear across the level. Rather than let that drag
# an enemy off toward some unrelated part of the map, only trust it within
# max_distance of what we asked for; otherwise just stay where we are.
func safe_snap_to_nav(point: Vector2, max_distance: float) -> Vector2:
	var snapped := NavigationServer2D.map_get_closest_point(nav_agent.get_navigation_map(), point)
	if snapped.distance_to(point) <= max_distance:
		return snapped
	return point

func update_facing(delta: float, desired: Vector2) -> void:
	if desired.length_squared() < 0.0001:
		return
	var target_angle := desired.angle()
	var new_angle := rotate_toward(facing_direction.angle(), target_angle, turn_speed * delta)
	facing_direction = Vector2.RIGHT.rotated(new_angle)

const LOS_PEEK_RADIUS := 96.0
const LOS_PEEK_OFFSETS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2(LOS_PEEK_RADIUS, 0), Vector2(-LOS_PEEK_RADIUS, 0),
	Vector2(0, LOS_PEEK_RADIUS), Vector2(0, -LOS_PEEK_RADIUS),
]

# --- Cloak stealth: a target player's replicated flags gate our perception ---
# The target Hurtbox's parent is the player node, which carries the two
# replicated stealth bits (see player.gd). "in" guards keep this safe for any
# non-player hurtbox.
func _target_silent(target: Hurtbox) -> bool:
	var p = target.get_parent()
	return p != null and "stealth_silent" in p and p.stealth_silent

func _hidden_by_stillness(target: Hurtbox) -> bool:
	var p = target.get_parent()
	if p == null or not ("stealth_unseen_still" in p) or not p.stealth_unseen_still:
		return false
	# Only hidden while actually standing still (default true = assume moving, so
	# we never wrongly hide a target whose movement we aren't tracking yet).
	return not target_is_moving.get(target, true)

func has_line_of_sight(target: Hurtbox) -> bool:
	return get_visible_point(target) != null

# LOS regardless of which way we're facing — used when a shot spins us around to
# check for the shooter (getting hit makes us look everywhere, not just our cone).
func has_line_of_sight_any_direction(target: Hurtbox) -> bool:
	return get_visible_point(target, false) != null

# Returns the world-space point we can actually see on target (so callers
# can aim at what's really exposed instead of a possibly-blocked dead
# center), or null if no part of them is both within our fov_degrees vision
# cone and unobstructed.
# PERF: line of sight is up to 5 rays + 5 swept-circle casts per call, run every
# physics frame per enemy. Cache each result for LOS_CACHE_FRAMES (staggered per
# enemy so they don't all refresh on the same frame). The visible point is kept
# RELATIVE to the target, so aiming still follows a moving player between refreshes.
const LOS_CACHE_FRAMES := 4
var _los_cache := {}
var _center_cache := {}

func _los_stagger() -> int:
	return absi(String(name).hash()) % LOS_CACHE_FRAMES

func get_visible_point(target: Hurtbox, check_fov := true) -> Variant:
	if target == null or !is_instance_valid(target):
		return null
	var key := "%d:%s" % [target.get_instance_id(), check_fov]
	var frame := Engine.get_physics_frames()
	var cached = _los_cache.get(key)
	if cached != null and frame - int(cached["frame"]) < LOS_CACHE_FRAMES and (frame + _los_stagger()) % LOS_CACHE_FRAMES != 0:
		return null if cached["offset"] == null else target.global_position + cached["offset"]
	var result = _get_visible_point_uncached(target, check_fov)
	_los_cache[key] = {"frame": frame, "offset": null if result == null else result - target.global_position}
	return result

func _get_visible_point_uncached(target: Hurtbox, check_fov := true) -> Variant:
	# A zero-width ray (or even a few parallel rays) can still slip through
	# the single-point diagonal gap where two wall tiles meet corner-to-
	# corner. Sweeping an actual circle shape along the path has real width
	# the whole way, so it can't pass through a gap smaller than its
	# diameter — geometrically closes off the pinhole case entirely.
	var space_state := get_world_2d().direct_space_state
	var half_fov := deg_to_rad(fov_degrees * 0.5)
	# Reuses the preallocated _los_query/_los_shape (mask + exclude set once in
	# _ready) instead of building new ones each of the up-to-5 peek casts.
	_los_query.transform = Transform2D(0.0, global_position)
	# Check center-to-center first, then a few points around the target's
	# body (peek offsets) rather than just its dead center — someone peeking
	# out from behind a corner has their center still hidden but an edge of
	# them already exposed, and that should count as spotted just like it
	# would for a person actually looking.
	for offset in LOS_PEEK_OFFSETS:
		var point := target.global_position + offset
		var to_point := point - global_position
		if check_fov and to_point.length_squared() > 0.0001 and absf(facing_direction.angle_to(to_point)) > half_fov:
			continue
		# Ray from our center: catches any wall between us and the point,
		# including one the swept circle would ignore for overlapping it at the
		# origin (see _los_ray). A hit means blocked.
		_los_ray.from = global_position
		_los_ray.to = point
		if not space_state.intersect_ray(_los_ray).is_empty():
			continue
		# Swept circle: real width the whole way, so it can't thread the
		# single-point diagonal gap where two wall tiles meet corner-to-corner.
		_los_query.motion = to_point
		var result := space_state.cast_motion(_los_query)
		if result.is_empty() or result[0] >= 1.0:
			return point
	return null

# Updates one target's "moved since last frame" flag + smoothed velocity (for
# shot leading). Smoothing rides out single-frame jitter.
func _track_target_motion(h: Hurtbox, pdelta: float) -> void:
	var last: Vector2 = last_target_positions.get(h, h.global_position)
	target_is_moving[h] = h.global_position.distance_to(last) >= MOVEMENT_THRESHOLD
	var inst_vel: Vector2 = (h.global_position - last) / pdelta
	target_velocities[h] = target_velocities.get(h, Vector2.ZERO).lerp(inst_vel, VELOCITY_SMOOTHING)
	last_target_positions[h] = h.global_position

func update_current_target() -> void:
	targets_in_range = targets_in_range.filter(func(h): return is_instance_valid(h))
	# Track "moved since last physics frame" for every target in range,
	# every frame, regardless of whether we end up needing it below — doing
	# this unconditionally (rather than only inside the filter lambda) keeps
	# it measuring "since last frame" instead of "since we last happened to
	# check", which would misreport a player who just walked up and stopped
	# as still moving.
	var pdelta := get_physics_process_delta_time()
	_decay_aggro(pdelta)
	for h in targets_in_range:
		_track_target_motion(h, pdelta)
	# We can now stay locked on a target via LOS well beyond the detection ring
	# (see the sticky-sight comment below), so keep tracking our current target's
	# motion even once it's left that ring — otherwise its shot-leading velocity
	# would go stale the moment it stepped outside our vision radius.
	if current_target != null and is_instance_valid(current_target) and not targets_in_range.has(current_target):
		_track_target_motion(current_target, pdelta)
	# Leaving detection_area's radius must NOT clear current_target — that's
	# exactly the "walked around a corner" case we want to keep chasing the
	# last known position through. Only drop it here if the hurtbox itself
	# is gone; actually losing an active chase is the give-up logic's job
	# (arriving at last_known_position without re-spotting them).
	if current_target and !is_instance_valid(current_target):
		current_target = null
	# A downed player reads as invincible on every peer (player.gd sets
	# hurtbox.is_invincible while prone/dead — and the server's copy gets it via
	# the replicated "prone" anim proxy), so treat them as effectively dead:
	# drop them as a target and don't re-acquire them below. They stop being
	# shot at until they're revived.
	if current_target and current_target.is_invincible:
		current_target = null
		reset_casting()
	# Acquiring a NEW target requires either line of sight or being within
	# earshot AND actually moving (a perfectly still player makes no noise
	# to hear) — sight alone would mean no detecting through walls just by
	# proximity, but close enough to hear a moving target bypasses that
	# entirely. Once engaged, losing both mid-chase doesn't drop the target
	# immediately either (see the give-up logic in _physics_process), so the
	# enemy can still pursue your last known position instead of forgetting
	# you the instant you turn a corner.
	if current_target == null and !targets_in_range.is_empty():
		var detectable: Array = targets_in_range.filter(func(h):
			# Downed/dead players (invincible hurtbox) are never acquired.
			if h.is_invincible:
				return false
			if h == recently_lost_target and lost_target_cooldown > 0.0:
				return false
			# cloak_silent skips the hearing branch entirely (fall through to
			# sight); cloak_unseen_still blocks sight while the target is still.
			if global_position.distance_to(h.global_position) <= hearing_radius and not _target_silent(h):
				return target_is_moving.get(h, false)
			return has_line_of_sight(h) and not _hidden_by_stillness(h)
		)
		if !detectable.is_empty():
			current_target = _closest_target(detectable)
			alert_nearby_group(current_target, current_target.global_position)
	# Damage aggro can override the geometric choice above (and STEAL an already-
	# engaged target), so it runs every frame regardless of the null check.
	_apply_aggro_target()

# Sheds each attacker's damage tally over time so old damage stops mattering.
func _decay_aggro(delta: float) -> void:
	if _aggro.is_empty():
		return
	for peer in _aggro.keys():
		var v: float = _aggro[peer] - AGGRO_DECAY * delta
		if v <= 0.0:
			_aggro.erase(peer)
		else:
			_aggro[peer] = v

# The player who's dealt the most recent damage becomes the target, and can STEAL
# an already-engaged target if it out-aggros the current one by AGGRO_SWITCH_RATIO
# (hysteresis so it doesn't flip-flop). With no meaningful aggro this is a no-op and
# the geometric acquisition stands. Aggro can target through walls ("you shot me,
# I'm coming") — the enemy then paths toward them.
func _apply_aggro_target() -> void:
	if _aggro.is_empty():
		return
	var world = _get_world()
	if world == null or world.players == null:
		return
	var top_peer := 0
	var top_val := 0.0
	for peer in _aggro:
		if _aggro[peer] < AGGRO_MIN:
			continue
		if !world.players.has_node(str(peer)):
			continue
		var hb = world.players.get_node(str(peer)).hurtbox
		if hb == null or hb.is_invincible:
			continue
		if _aggro[peer] > top_val:
			top_val = _aggro[peer]
			top_peer = peer
	if top_peer == 0:
		return
	var top_hb: Hurtbox = world.players.get_node(str(top_peer)).hurtbox
	if current_target == top_hb:
		return
	if current_target == null:
		current_target = top_hb
		last_known_position = top_hb.global_position
		alert_nearby_group(current_target, current_target.global_position)
		return
	# Already engaged: steal only if the aggro leader clearly out-damages them.
	var cur_peer: int = current_target.owner_id if "owner_id" in current_target else 0
	var cur_val: float = _aggro.get(cur_peer, 0.0)
	if top_val > cur_val and top_val >= cur_val * AGGRO_SWITCH_RATIO:
		current_target = top_hb
		last_known_position = top_hb.global_position

func _get_world() -> Node:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world")
	return _world

func _closest_target(hurtboxes: Array) -> Hurtbox:
	var closest: Hurtbox = null
	var closest_dist := INF
	for h in hurtboxes:
		var dist := global_position.distance_to(h.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = h
	return closest

# --- Attack telegraphs (Phase 1.6) -----------------------------------------
# Visible world: 3840x2160 viewport at zoom 0.75 = 5120x2880, so a player sees
# +-2560 x +-1440 around themselves. Enemies only fire at a target that is inside
# that target's screen (minus a margin), so nothing ever shoots you from off-screen.
const TARGET_SCREEN_HALF := Vector2(2560.0, 1440.0)
# 140 of edge slack plus the camera's max look-ahead lean (camera_shake.gd
# LOOK_AHEAD_MAX), since the target's view can be shifted that far off-centre.
const SCREEN_FIRE_MARGIN := 140.0 + 320.0
var windup_sec := 0.0
var _windup_aim_lock := false
var _windup_root := false
var _windup_left := 0.0
var _windup_ready := false
var _aim_locked := false
var _aim_lock_point := Vector2.ZERO
var _laser: Line2D = null
var _windup_tween: Tween = null
# Tracking-laser wind-up (sniper): aim follows the target until _lock_before s
# remain, then freezes on a led point. Server-side state:
var _lock_before := 0.0
var _windup_tracking := false
# Client-side: which player the laser is following (peer id), until the lock RPC.
var _laser_target_id := 0

# --- Attack tokens (the difficulty dial) ---------------------------------------
# Only N enemies may be winding up / firing a burst at the same player at once
# (MapDef.tokens_per_player; E1 = 2, E2 = 3). The rest keep moving and flanking
# until a token frees up, so a big pack is dangerous through pressure and
# positioning, not a wall of simultaneous volleys. Server-only (AI is). The pool
# lives on the room's `enemies` node as metadata: target instance id -> holders.
const DEFAULT_TOKENS_PER_PLAYER := 2
var _token_target_id := 0

func _tokens_per_player() -> int:
	var map := Stats.current_map()
	return map.tokens_per_player if map != null else DEFAULT_TOKENS_PER_PLAYER

func _token_pool() -> Dictionary:
	var p := get_parent()
	if p == null:
		return {}
	if !p.has_meta("attack_tokens"):
		p.set_meta("attack_tokens", {})
	return p.get_meta("attack_tokens")

func _try_acquire_token() -> bool:
	if current_target == null:
		return false
	var tid := current_target.get_instance_id()
	if _token_target_id == tid:
		return true
	_release_token()
	var pool := _token_pool()
	var holders: Array = pool.get(tid, [])
	# Drop holders that died, were freed, or moved their token to someone else.
	holders = holders.filter(func(h): return is_instance_valid(h) and !h.is_dead and h._token_target_id == tid)
	if holders.size() >= _tokens_per_player():
		pool[tid] = holders
		return false
	holders.append(self)
	pool[tid] = holders
	_token_target_id = tid
	return true

func _release_token() -> void:
	if _token_target_id == 0:
		return
	var pool := _token_pool()
	var holders: Array = pool.get(_token_target_id, [])
	holders.erase(self)
	pool[_token_target_id] = holders
	_token_target_id = 0

# How far from `t` we may hold and still be inside its fire box along our current
# bearing: keeps long-range shapes (square/hexagon/circle) from parking just
# off-screen above/below and flip-flopping between chase and back-off.
func _effective_preferred_range(t: Node2D) -> float:
	var d := (global_position - t.global_position).normalized()
	var hx := TARGET_SCREEN_HALF.x - SCREEN_FIRE_MARGIN
	var hy := TARGET_SCREEN_HALF.y - SCREEN_FIRE_MARGIN
	var tx := INF if absf(d.x) < 0.0001 else hx / absf(d.x)
	var ty := INF if absf(d.y) < 0.0001 else hy / absf(d.y)
	return minf(preferred_range, minf(tx, ty) * 0.9)

func _target_on_screen(t: Node2D) -> bool:
	var d := t.global_position - global_position
	return absf(d.x) <= TARGET_SCREEN_HALF.x - SCREEN_FIRE_MARGIN \
		and absf(d.y) <= TARGET_SCREEN_HALF.y - SCREEN_FIRE_MARGIN

# Where the target will be after `extra_time` + the bullet's flight, assuming it
# keeps its current velocity; capped like fire_spell's lead so a rushing target
# can't flip the aim behind us.
func _led_point(point: Vector2, extra_time: float) -> Vector2:
	var a: Dictionary = ARCHETYPES.get(archetype, ARCHETYPES["pentagon"])
	var speed: float = float(a.get("bullet_speed", 1100.0)) * _bullet_speed_mult
	var gap := global_position.distance_to(point)
	var t := minf(extra_time + gap / maxf(speed, 1.0), MAX_LEAD_TIME + extra_time)
	var lead: Vector2 = target_velocities.get(current_target, Vector2.ZERO) * t
	if lead.length() > gap * MAX_LEAD_FRACTION:
		lead = lead.normalized() * gap * MAX_LEAD_FRACTION
	return point + lead

func _emit_laser_lock(point: Vector2) -> void:
	var targets := _room_rpc_targets()
	if targets.is_empty():
		_lock_laser.rpc(point)
		return
	var server_id := multiplayer.get_unique_id()
	for pid in targets:
		if pid == server_id:
			_lock_laser(point)
		else:
			_lock_laser.rpc_id(pid, point)

# Every peer: the laser stops following and snaps (white flash) onto the locked
# aim. That flash is the "dodge NOW" cue.
@rpc("authority", "call_local", "reliable")
func _lock_laser(point: Vector2) -> void:
	_laser_target_id = 0
	if _laser == null or !is_instance_valid(_laser):
		return
	var dir := (point - global_position).normalized()
	_laser.points = PackedVector2Array([global_position, global_position + dir * 3600.0])
	_laser.default_color = Color(1.0, 1.0, 1.0, 1.0)
	_laser.width = 9.0

func _update_tracking_laser() -> void:
	# Tracking laser (all peers): follow the targeted player until the lock RPC.
	if _laser_target_id == 0 or _laser == null or !is_instance_valid(_laser):
		return
	var world = _get_world()
	if world == null or !world.players.has_node(str(_laser_target_id)):
		return
	var tp: Vector2 = world.players.get_node(str(_laser_target_id)).global_position
	var dir := (tp - global_position).normalized()
	_laser.points = PackedVector2Array([global_position, global_position + dir * 3600.0])

func _cancel_windup() -> void:
	var was_active := _windup_left > 0.0 or _windup_ready
	_windup_left = 0.0
	_windup_ready = false
	_aim_locked = false
	_windup_tracking = false
	if was_active:
		_emit_windup(0.0, Vector2.ZERO, false, 0)

func _emit_windup(duration: float, lock_point: Vector2, laser: bool, target_id: int = 0) -> void:
	var targets := _room_rpc_targets()
	if targets.is_empty():
		_show_windup.rpc(duration, lock_point, laser, target_id)
		return
	var server_id := multiplayer.get_unique_id()
	for pid in targets:
		if pid == server_id:
			_show_windup(duration, lock_point, laser, target_id)
		else:
			_show_windup.rpc_id(pid, duration, lock_point, laser, target_id)

# The tell, on every peer in the room: the body swells over the wind-up (and the
# sniper draws a laser to its locked aim point). duration 0 = cancel.
@rpc("authority", "call_local", "reliable")
func _show_windup(duration: float, lock_point: Vector2, laser: bool, target_id: int) -> void:
	# target_id != 0: the laser follows that player until _lock_laser.
	_laser_target_id = target_id
	if _windup_tween != null and _windup_tween.is_valid():
		_windup_tween.kill()
	if _laser != null and is_instance_valid(_laser):
		_laser.queue_free()
	_laser = null
	if body == null:
		return
	if duration <= 0.0:
		body.scale = Vector2.ONE
		_laser_target_id = 0
		return
	if laser:
		Sounds.play_sfx("sniper_windup", global_position, 0.0, 0.0)
	else:
		Sounds.play_sfx("windup", global_position, -4.0, 0.0)
	_windup_tween = create_tween()
	_windup_tween.tween_property(body, "scale", Vector2.ONE * 1.3, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_windup_tween.tween_property(body, "scale", Vector2.ONE, 0.08)
	if laser:
		var dir := (lock_point - global_position).normalized()
		_laser = Line2D.new()
		_laser.top_level = true
		_laser.width = 10.0
		_laser.z_index = 40
		_laser.default_color = Color(1.0, 0.15, 0.15, 0.15)
		_laser.points = PackedVector2Array([global_position, global_position + dir * 3600.0])
		get_tree().current_scene.add_child(_laser)
		var lt := _laser.create_tween()
		lt.tween_property(_laser, "default_color", Color(1.0, 0.2, 0.2, 0.9), duration)
		lt.parallel().tween_property(_laser, "width", 4.0, duration)
		lt.tween_callback(_laser.queue_free)

# RECOVER: after a burst, show the cooldown as a visible vulnerable window (dimmed,
# slightly shrunk) on every peer in the room, so "it just fired, punish it" reads.
func _emit_recover(duration: float) -> void:
	var targets := _room_rpc_targets()
	if targets.is_empty():
		_show_recover.rpc(duration)
		return
	var server_id := multiplayer.get_unique_id()
	for pid in targets:
		if pid == server_id:
			_show_recover(duration)
		else:
			_show_recover.rpc_id(pid, duration)

@rpc("authority", "call_local", "unreliable")
func _show_recover(duration: float) -> void:
	if body == null or duration <= 0.0:
		return
	var t := body.create_tween()
	t.tween_property(body, "self_modulate", Color(0.55, 0.55, 0.6), 0.12)
	t.parallel().tween_property(body, "scale", Vector2.ONE * 0.9, 0.12)
	t.tween_interval(maxf(duration - 0.35, 0.0))
	t.tween_property(body, "self_modulate", Color.WHITE, 0.2)
	t.parallel().tween_property(body, "scale", Vector2.ONE, 0.2)

func reset_casting() -> void:
	_cancel_windup()
	_release_token()
	# An interrupted burst starts over (token + wind-up), never resumes mid-way.
	_burst_shots = 0
	spell_input_sequence.clear()
	target_recipe_sequence.clear()
	tap_timer = 0.0
	_advance_range = 0.0
	_planned_form = ""
	_planned_recipe = {}

func update_casting(delta: float, distance: float) -> void:
	# Mid-sequence: keep tapping it out.
	if !target_recipe_sequence.is_empty():
		tap_timer -= delta
		if tap_timer <= 0.0:
			enter_next_tap()
		return
	if cast_timer > 0.0:
		return
	# A new burst needs one of the target's attack tokens; without one, hold fire
	# (movement continues) until a packmate finishes its burst.
	if _burst_shots == 0 and not _windup_ready and _windup_left <= 0.0 and not _try_acquire_token():
		return
	# Telegraph: before the FIRST shot of a burst, wind up (visible to the room).
	if windup_sec > 0.0 and _burst_shots == 0 and not _windup_ready:
		if _windup_left <= 0.0:
			_windup_left = windup_sec
			_aim_locked = _windup_aim_lock
			_aim_lock_point = current_visible_point
			_windup_tracking = _windup_aim_lock and _lock_before > 0.0
			var target_id := int(current_target.owner_id) if current_target != null and _windup_tracking else 0
			_emit_windup(windup_sec, _aim_lock_point, _windup_aim_lock, target_id)
		_windup_left -= delta
		if _windup_tracking:
			if _windup_left > _lock_before:
				# Still tracking: keep re-aiming at where we can see them.
				_aim_lock_point = current_visible_point
			else:
				# LOCK: freeze on where they'll be when the shot arrives (bounded
				# lead), and tell the room so the laser freezes + flashes.
				_windup_tracking = false
				_aim_lock_point = _led_point(current_visible_point, _windup_left)
				_emit_laser_lock(_aim_lock_point)
		if _windup_left > 0.0:
			return
		_windup_left = 0.0
		_windup_ready = true
	# Decide the next cast first (so we know its reach).
	if _planned_form == "":
		_plan_next_cast()
	if distance <= _advance_range:
		# In range for the planned cast — fire it (or start warming up a sequence).
		_execute_planned_cast()
	elif _planned_form != "default" and distance <= _default_range:
		# Still closing in for a shorter-range sequence but the target is within
		# plain-default reach — keep peppering them with default attacks so we're
		# not just eating shots during the approach. Doesn't consume the planned
		# sequence; it fires once we've closed the rest of the gap.
		cast_default()

# Choose what to cast next (a run of default attacks between sequences) and record
# how close we need to be for it to land, WITHOUT firing yet.
func _plan_next_cast() -> void:
	# Balancing pass (uniform_bullets): fire only the plain default form so every
	# enemy shot is the same flat projectile. Skips the whole form/sequence picker.
	if uniform_bullets:
		_planned_form = "default"
		_planned_recipe = {}
		_advance_range = _default_range
		return
	# Only the forms this enemy's weapon actually holds — so its repertoire matches
	# the weapon that drops — AND only ones that can land from our hold distance, so
	# the enemy stays ranged (EtG style) instead of closing into melee for a
	# short-range form (burst/cone/beam). Unreachable forms fall back to defaults.
	var recipes: Array = all_spell_recipes.get_available_recipes(attacker_element, attacker_forms)
	recipes = recipes.filter(func(r):
		var reach := SpellData.get_effective_range(attacker_weapon, attacker_element, r.get("form", "default"), true)
		return reach * ENGAGE_MARGIN >= preferred_range
	)
	if recipes.is_empty() or _default_shots_remaining > 0:
		_planned_form = "default"
		_planned_recipe = {}
	else:
		_planned_recipe = recipes.pick_random()
		_planned_form = _planned_recipe.get("form", "default")
	_advance_range = SpellData.get_effective_range(attacker_weapon, attacker_element, _planned_form, true) * ENGAGE_MARGIN

func _execute_planned_cast() -> void:
	if _planned_recipe.is_empty():
		_default_shots_remaining = max(_default_shots_remaining - 1, 0)
		cast_default()
	else:
		_default_shots_remaining = randi_range(MIN_DEFAULTS_BETWEEN_SEQUENCES, MAX_DEFAULTS_BETWEEN_SEQUENCES)
		target_recipe_sequence = _planned_recipe["sequence"].duplicate()
		tap_timer = tap_interval
	_planned_form = ""
	_planned_recipe = {}

func enter_next_tap() -> void:
	var next_index := spell_input_sequence.size()
	if next_index >= target_recipe_sequence.size():
		reset_casting()
		return
	spell_input_sequence.append(target_recipe_sequence[next_index])
	tap_timer = tap_interval
	if spell_input_sequence.size() >= target_recipe_sequence.size():
		cast_sequence()

func cast_sequence() -> void:
	var recipe := all_spell_recipes.get_spell_recipe_from_sequence(spell_input_sequence)
	if recipe.is_empty():
		cast_default()
	else:
		fire_spell(attacker_weapon, recipe["element"], recipe["form"])
	reset_casting()

func cast_default() -> void:
	# An archetype can swap its basic attack for another form (hexagon lobs rain).
	var form: String = ARCHETYPES.get(archetype, {}).get("attack_form", "default")
	fire_spell(attacker_weapon, attacker_element, form)

# Applies the archetype's stat preset + the tier's multipliers/visual. Runs on every
# peer in _ready (deterministic spawner pick → all peers agree), overriding the
# enemy.tscn export defaults. See ARCHETYPES / TIERS.
func _apply_archetype() -> void:
	var a: Dictionary = ARCHETYPES.get(archetype, ARCHETYPES["pentagon"])
	var t: Dictionary = TIERS.get(tier, TIERS["bronze"])
	move_speed = a["move_speed"]
	strafe_speed = a["strafe_speed"]
	# Jitter each enemy's hold distance ±PREFERRED_RANGE_VARIANCE so a pack settles at a
	# spread of rings instead of all freezing on the exact same one. Server-only-used
	# (AI is authority-only), so a non-deterministic roll here can't desync anything.
	preferred_range = a["preferred_range"] * randf_range(1.0 - PREFERRED_RANGE_VARIANCE, 1.0 + PREFERRED_RANGE_VARIANCE)
	cast_range = a["cast_range"]
	windup_sec = float(a.get("windup_sec", 0.0))
	_windup_aim_lock = bool(a.get("aim_lock", false))
	_lock_before = float(a.get("lock_before", 0.0))
	_windup_root = bool(a.get("windup_root", false))
	attacks_per_sec_range = a.get("attacks_per_sec", [1.0, 1.0])
	burst_count = a.get("burst_count", 1)
	burst_cooldown_range = a.get("burst_cooldown", [0.0, 0.0])
	_burst_shots = 0
	aim_variance = deg_to_rad(a.get("aim_variance_deg", 5.0))
	attack = a["attack"] * t["attack_mult"]
	max_health = a["max_health"] * t["health_mult"]
	health = max_health
	_roll_affixes()
	# Identity now reads off the body glyph: shape = archetype, fill = element, border =
	# tier (see _update_visual). visual_root stays neutral (no tier scale/tint).
	_update_visual()

func _roll_affixes() -> void:
	affixes = []
	_bullet_speed_mult = 1.0
	_shield_hp = 0.0
	var count := 2 if tier == "gold" else (1 if tier == "silver" else 0)
	if count > 0:
		var map := Stats.current_map()
		var pool: Array = (map.affix_pool if map != null and !map.affix_pool.is_empty() else ["fast", "armored"]).duplicate()
		var rng := RandomNumberGenerator.new()
		rng.seed = Stats.expedition_seed ^ hash("affix:" + String(name))
		while affixes.size() < count and !pool.is_empty():
			affixes.append(pool.pop_at(rng.randi() % pool.size()))
	if affixes.has("fast"):
		move_speed *= 1.3
		strafe_speed *= 1.3
		_bullet_speed_mult = 1.2
	if affixes.has("shielded"):
		_shield_hp = SHIELD_HP
	_warder_timer = WARDER_INTERVAL * 0.5
	if body:
		body.affixes = affixes
	shield_up = _shield_hp > 0.0

# Server, from _on_hurtbox_hurt: armor and shield between a hit and our health.
func _apply_affix_defense(dmg: float, advantage: bool) -> float:
	if affixes.has("armored"):
		dmg *= ARMORED_MULT
	if _shield_hp > 0.0:
		if advantage:
			# The right element shatters the shield outright; the hit passes through.
			_shield_hp = 0.0
		else:
			var absorbed := minf(_shield_hp, dmg)
			_shield_hp -= absorbed
			dmg -= absorbed
		if _shield_hp <= 0.0:
			_emit_shield_break()
	return dmg

func _emit_shield_break() -> void:
	var targets := _room_rpc_targets()
	if targets.is_empty():
		_show_shield_break.rpc()
		return
	var server_id := multiplayer.get_unique_id()
	for pid in targets:
		if pid == server_id:
			_show_shield_break()
		else:
			_show_shield_break.rpc_id(pid)

# The warder's own tell (a red flash on the body), separate from the attack
# wind-up's tween/laser so the two never cancel each other's warning.
func _emit_warder_tell() -> void:
	var targets := _room_rpc_targets()
	if targets.is_empty():
		_show_warder_tell.rpc()
		return
	var server_id := multiplayer.get_unique_id()
	for pid in targets:
		if pid == server_id:
			_show_warder_tell()
		else:
			_show_warder_tell.rpc_id(pid)

@rpc("authority", "call_local", "reliable")
func _show_warder_tell() -> void:
	if body == null:
		return
	body.modulate = Color(1.6, 0.4, 0.35)
	var t := body.create_tween()
	t.tween_property(body, "modulate", Color.WHITE, WARDER_CHARGE)
	Sounds.play_sfx("windup", global_position, -2.0, 0.0)

@rpc("authority", "call_local", "reliable")
func _show_shield_break() -> void:
	shield_up = false
	if body == null:
		return
	Fx.shatter(get_tree(), global_position, body.fill_color.lightened(0.45), 1.2)
	Sounds.play_sfx("enemy_die", global_position, -4.0)

# Server, each combat frame: a warder pulses when a player gets close.
func _update_warder(delta: float, distance: float) -> void:
	if !affixes.has("warder"):
		return
	if _warder_charge > 0.0:
		_warder_charge -= delta
		if _warder_charge <= 0.0:
			_broadcast_spawn_projectile(attacker_weapon, attacker_element, "burst", Vector2.RIGHT, WARDER_DAMAGE, 0.0, 0.0, 0.0)
		return
	_warder_timer -= delta
	if _warder_timer <= 0.0 and distance <= WARDER_RANGE:
		_warder_timer = WARDER_INTERVAL
		_warder_charge = WARDER_CHARGE
		_emit_warder_tell()

func fire_spell(weapon: String, element: String, form: String) -> void:
	if current_target == null:
		return
	var spell_data := all_spell_data.build_spell_data(weapon, element, form, "common", true)
	# Aim at the actual point of them we can see (may be an edge peeking past a
	# corner) rather than their dead center, which could still be behind cover.
	var aim_point := _aim_lock_point if _aim_locked else current_visible_point
	# Damage = this enemy's Attack (per pellet); the attacker's crit stats travel
	# to the defender (crit resolved at hit time). Nothing rolled here.
	if spell_data.get("targeted", false):
		# Targeted forms (rain) land ON the target's spot, clamped to the form's
		# range — no lead, spread, or fan. rain_projectile.gd LOS-clamps to a wall.
		# Later shots in a lobber's burst scatter around the target, so a burst
		# covers ground instead of stacking on one spot.
		var scatter: float = ARCHETYPES.get(archetype, {}).get("lob_scatter", 0.0)
		if scatter > 0.0 and _burst_shots > 0:
			aim_point += Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * randf_range(scatter * 0.4, scatter)
		var to_target := aim_point - global_position
		var spawn_dist := minf(to_target.length(), spell_data["spawn_offset"])
		_broadcast_spawn_projectile(weapon, element, form, to_target.normalized(), attack, crit_rate, crit_damage, spawn_dist, PackedFloat32Array([0.0]))
	else:
		var a: Dictionary = ARCHETYPES.get(archetype, ARCHETYPES["pentagon"])
		# Each archetype sets its shot speed ABSOLUTELY (bullet_speed); convert to a
		# multiplier on the flat enemy base speed so the fan spawner can apply it.
		var base_speed: float = spell_data["speed"]
		# Predictive leading: shift the aim to where the target will be by the time
		# the shot reaches it (time ≈ distance / real shot speed). Cheap first-order
		# lead. Skipped for speed-0 AoE forms (they don't travel).
		var proj_speed: float = float(a.get("bullet_speed", base_speed)) * _bullet_speed_mult
		var speed_mult: float = proj_speed / base_speed if base_speed > 0.0 else 1.0
		if proj_speed > 0.0 and not _aim_locked:
			# Bounded lead: cap the flight-time estimate, AND cap the resulting offset to
			# a fraction of the gap, so a fast/rushing target can never push the aim past
			# us (which used to flip the shot to fire the wrong way — "shots off track").
			var gap := global_position.distance_to(aim_point)
			var lead_time := minf(gap / proj_speed, MAX_LEAD_TIME)
			var lead: Vector2 = target_velocities.get(current_target, Vector2.ZERO) * lead_time
			if lead.length() > gap * MAX_LEAD_FRACTION:
				lead = lead.normalized() * gap * MAX_LEAD_FRACTION
			aim_point += lead
		# Small random wobble on the whole shot; the fan (pellets/spread) provides the
		# real spread for the shotgun/spread archetypes. spawn_projectile builds the
		# fan from this one aimed direction so it matches on every peer.
		var direction := global_position.direction_to(aim_point).rotated(randf_range(-aim_variance, aim_variance))
		# The pellet fan is the archetype's BASIC attack (pentagon 5 / triangle 3;
		# circle & square fire a single shot). Guarded on "default" so a re-enabled
		# spell cast would still fire its own single-projectile pattern. The per-pellet
		# angle offsets are computed HERE (server) and sent, so the whole volley is
		# identical on every peer (see _pellet_offsets_for).
		var offsets := PackedFloat32Array([0.0])
		if form == "default":
			offsets = _pellet_offsets_for(a)
		_broadcast_spawn_projectile(weapon, element, form, direction, attack, crit_rate, crit_damage, -1.0, offsets, speed_mult)
	# Cadence is rolled fresh each shot from the archetype's attacks_per_sec [min,max]
	# range (volleys/sec) so the barrage isn't perfectly metronomic. Enemy AI timing is
	# authority-only, so this randf is server-side and never desyncs.
	var aps := randf_range(attacks_per_sec_range[0], attacks_per_sec_range[1])
	cast_timer = 1.0 / maxf(aps, 0.01)
	# Burst-and-cooldown: after burst_count shots at that cadence, wait a random
	# burst_cooldown_range [min,max] instead before the next burst (max 0 = continuous).
	if burst_count >= 1 and burst_cooldown_range[1] > 0.0:
		_burst_shots += 1
		if _burst_shots >= burst_count:
			_burst_shots = 0
			cast_timer = randf_range(burst_cooldown_range[0], burst_cooldown_range[1])
			_emit_recover(cast_timer)
	# Burst finished: the next one needs a fresh wind-up (and a fresh aim lock),
	# and the attack token goes back to the pool for a packmate.
	if _burst_shots == 0:
		_windup_ready = false
		_aim_locked = false
		_release_token()

# Per-shot angle offsets (radians, relative to the aimed direction) for one volley.
# An archetype may specify an explicit `pellet_angles_deg` list (custom/asymmetric
# fan — e.g. the pentagon's tight inner pair ±14 + wide outer pair ±30); otherwise
# `pellets` shots are fanned EVENLY across `spread_deg`. A lone pellet fires straight.
# Computed server-side and sent, so every peer's volley matches.
func _pellet_offsets_for(a: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if a.has("pellet_angles_deg"):
		for deg in a["pellet_angles_deg"]:
			out.append(deg_to_rad(float(deg)))
		return out
	var n: int = maxi(1, int(a.get("pellets", 1)))
	var spread := deg_to_rad(float(a.get("spread_deg", 0.0)))
	for i in n:
		var frac := 0.0 if n <= 1 else float(i) / float(n - 1) - 0.5
		out.append(frac * spread)
	return out

# --- Room-scoped RPC dispatch --------------------------------------------
# Every peer that has this enemy's room loaded simulates its own copy of the
# enemy, so its RPCs must go ONLY to those peers. A blanket .rpc() also hits peers
# in other rooms who've already freed this enemy: each logs a "get_cached_object
# ... node is null" error, and — for the frequent, reliable projectile spawns —
# the extra traffic floods the reliable channel enough to stall real messages
# (players' own spell spawns arriving seconds late). Scope them exactly like
# exit_portal / loot_container. Only ever called on the server (enemy AI + hurt
# handling are authority-only).
func _my_room_key() -> String:
	var world = get_tree().get_first_node_in_group("world")
	if world == null or world.world_rooms == null:
		return ""
	for key in world.world_rooms.loaded_rooms:
		var scene = world.world_rooms.loaded_rooms[key].get("scene")
		if scene != null and is_instance_valid(scene) and scene.is_ancestor_of(self):
			return key
	return ""

# Server id + every peer currently in this enemy's room, or [] if the room can't
# be resolved (callers then fall back to a plain broadcast).
func _room_rpc_targets() -> Array:
	var world = get_tree().get_first_node_in_group("world")
	var room_key := _my_room_key()
	if world == null or room_key == "":
		return []
	var ids := {multiplayer.get_unique_id(): true}
	for pid in world.peers_in_room(room_key):
		ids[pid] = true
	return ids.keys()

func _broadcast_spawn_projectile(weapon: String, element: String, form: String, direction: Vector2, attack: float, crit_rate: float, crit_damage: float, spawn_dist: float, offsets: PackedFloat32Array = PackedFloat32Array(), speed_mult: float = 1.0) -> void:
	var targets := _room_rpc_targets()
	if targets.is_empty():
		spawn_projectile.rpc(weapon, element, form, direction, attack, crit_rate, crit_damage, spawn_dist, offsets, speed_mult)
		return
	var server_id := multiplayer.get_unique_id()
	for pid in targets:
		if pid == server_id:
			spawn_projectile(weapon, element, form, direction, attack, crit_rate, crit_damage, spawn_dist, offsets, speed_mult)
		else:
			spawn_projectile.rpc_id(pid, weapon, element, form, direction, attack, crit_rate, crit_damage, spawn_dist, offsets, speed_mult)

@rpc("authority", "call_local", "reliable")
func spawn_projectile(weapon: String, element: String, form: String, direction: Vector2, attack: float = 0.0, crit_rate: float = 0.0, crit_damage: float = 0.0, spawn_dist: float = -1.0, offsets: PackedFloat32Array = PackedFloat32Array(), speed_mult: float = 1.0) -> void:
	# Fire one pellet per angle in `offsets` (radians, relative to the sent
	# `direction`) — an empty list / a single 0.0 fires one straight shot. The server
	# computes the offsets (even fan OR custom per-pellet, see _pellet_offsets_for)
	# and sends the same list to every peer, so the whole volley matches across the
	# party. Each pellet gets its OWN spell_data: the projectile keeps a reference to
	# that dict (setup_spell), so sharing one would let them stomp each other.
	var pellet_offsets := offsets
	if pellet_offsets.is_empty():
		pellet_offsets = PackedFloat32Array([0.0])
	var base_angle := direction.angle()
	for off in pellet_offsets:
		var dir := Vector2.from_angle(base_angle + off)
		var spell_data := all_spell_data.build_spell_data(weapon, element, form, "common", true)
		# Damage = the enemy's Attack (per pellet); attacker crit stats ride on the
		# hitbox so the defender resolves crit at hit time (single-hit and DoT alike).
		spell_data["damage"] = attack
		spell_data["attacker_crit_rate"] = crit_rate
		spell_data["attacker_crit_damage"] = crit_damage
		# Sniper etc. fire faster shots — scale only the velocity, not max_distance,
		# so the shot reaches the same range but gets there quicker.
		spell_data["speed"] = spell_data["speed"] * speed_mult
		# spawn_dist is set for targeted forms (rain lands on the player, clamped to
		# range); otherwise fall back to the form's fixed spawn_offset.
		var dist: float = spawn_dist if spawn_dist >= 0.0 else spell_data["spawn_offset"]
		var projectile = spell_data["scene"].instantiate()
		get_tree().current_scene.add_child(projectile)
		projectile.global_position = global_position + dir * dist
		projectile.setup_spell(dir, spell_data, name.hash(), false)

func _on_detection_area_entered(area: Area2D) -> void:
	if area is Hurtbox:
		targets_in_range.append(area)

func _on_detection_area_exited(area: Area2D) -> void:
	if area is Hurtbox:
		targets_in_range.erase(area)

func _on_hurtbox_hurt(hitbox, damage) -> void:
	# Authoritative damage number: only the enemy's authority (the server, which
	# has this enemy's real attacker_weapon/element) computes it, then broadcasts
	# so every peer shows the same value instead of recomputing from data clients
	# may not have.
	if !is_multiplayer_authority():
		return
	# Resolve the hit from stats (server authority): base = attacker Attack
	# (hitbox.damage), crit from the attacker's crit stats + a +50/+50 bonus if their
	# element beats ours, then our Defense reduces it (Diablo-style DR).
	var final_damage: float = damage
	var is_crit := false
	var advantage := false
	if hitbox != null and "attacker_element" in hitbox:
		advantage = SpellData.has_advantage(hitbox.attacker_element, attacker_element)
		var atk_crit_rate: float = hitbox.attacker_crit_rate + (50.0 if advantage else 0.0)
		var atk_crit_damage: float = hitbox.attacker_crit_damage + (50.0 if advantage else 0.0)
		is_crit = randf() * 100.0 < atk_crit_rate
		if is_crit:
			final_damage *= 1.0 + atk_crit_damage / 100.0
	final_damage *= 1.0 - SpellData.damage_reduction(defense)
	final_damage = _apply_affix_defense(final_damage, advantage)
	# Aggro: credit this damage to the attacking PLAYER. hitbox.caster_id is the
	# player's peer id directly (enemy casts use name.hash(), so guard on it being a
	# real player node). Whoever out-damages the current target pulls aggro — see
	# _apply_aggro_target() in update_current_target().
	if hitbox != null and "caster_id" in hitbox:
		var aggro_world = _get_world()
		if aggro_world != null and aggro_world.players != null and aggro_world.players.has_node(str(hitbox.caster_id)):
			_aggro[hitbox.caster_id] = _aggro.get(hitbox.caster_id, 0.0) + final_damage
			_last_attacker_peer = hitbox.caster_id
	_emit_damage_number(final_damage, is_crit, advantage)
	# Small shove away from the hit (direct hits only; DoT ticks would jitter).
	if hitbox != null and is_instance_valid(hitbox) and hitbox.auto_hit:
		var away: Vector2 = global_position - hitbox.global_position
		if away.length_squared() > 0.0001:
			_knockback += away.normalized() * KNOCKBACK_SPEED * (1.5 if is_crit else 1.0)
	# Getting hit is an instant, unmissable cue of where the attack came
	# from — snap facing straight there instead of easing over with
	# turn_speed like normal tracking does.
	if hitbox != null and is_instance_valid(hitbox):
		var to_attacker = hitbox.global_position - global_position
		if to_attacker.length_squared() > 0.0001:
			facing_direction = to_attacker.normalized()
			# Only react to acquire if we're not already tracking someone — a hit
			# that lands while we're engaged doesn't need this. With no target,
			# first do a radius-ignoring LOS scan for the shooter: if we can
			# actually see a player (open ground, even well past our vision ring),
			# lock straight onto them; otherwise fall back to just investigating
			# the shot like before.
			if current_target == null:
				var shooter := _spot_shooter_any_range()
				if shooter != null:
					current_target = shooter
					last_known_position = shooter.global_position
				else:
					start_investigating(facing_direction)
			# Getting attacked alerts nearby groupmates too — use our actual
			# current_target's live position if we have one (more accurate
			# than the hit itself), otherwise just the point we were hit
			# from, same as what we just used to start our own investigation.
			var alert_point = current_target.global_position if current_target != null else hitbox.global_position
			alert_nearby_group(current_target, alert_point)
	take_damage(final_damage)

# Room-scoped like the projectile spawn above (same "don't spam other rooms'
# peers with node-null errors" reasoning) — the damage number only matters to
# peers who actually have this enemy.
func _emit_damage_number(amount: float, is_crit: bool, effective: bool = false) -> void:
	var targets := _room_rpc_targets()
	if targets.is_empty():
		_broadcast_damage_number.rpc(amount, is_crit, effective)
		return
	var server_id := multiplayer.get_unique_id()
	for pid in targets:
		if pid == server_id:
			_broadcast_damage_number(amount, is_crit, effective)
		else:
			_broadcast_damage_number.rpc_id(pid, amount, is_crit, effective)

# Shows the authoritative damage number on every peer (call_local so the server
# shows it too) — the single place an enemy's damage number is spawned now.
@rpc("authority", "call_local", "unreliable")
func _broadcast_damage_number(amount: float, is_crit: bool, effective: bool) -> void:
	_spawn_damage_number(amount, Color(1, 0.9, 0.3), is_crit, effective)
	Fx.flash(body)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	health = clamp(health - amount, 0.0, max_health)
	if health <= 0.0:
		die()

# Peer id of the player who last damaged us (server), credited with the kill.
var _last_attacker_peer := 0

func die() -> void:
	# Rolled/broadcast here rather than in the is_dead setter below (despite
	# the TODO comment sitting right there) — that setter body runs once
	# server-side directly and once more per client every time replication
	# applies the incoming synced value, so rolling loot there would have
	# every client uselessly (and separately) roll RNG too. die() is only
	# ever reachable server-side (take_damage() <- _on_hurtbox_hurt(), which
	# early-returns for non-authority), so this is the one place it actually
	# only runs once.
	var world = get_tree().get_first_node_in_group("world")
	if world:
		# Per-entry loot from this archetype+tier's table (ItemData.get_loot_table).
		# Elemental enemies drop NO weapons/gear, so their tables carry no @weapon/
		# @gear tokens — the context only needs the element to resolve @crystal
		# (crystal_<element>), which fits the elemental theme.
		var context := {"element": attacker_element, "tier": tier}
		world.spawn_loot(global_position, ItemData.get_loot_table(archetype, tier), context)
		world.credit_kill(_last_attacker_peer)
	is_dead = true
