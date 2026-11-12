# Relic Runners — Combat Redesign Plan (weapons, wave, elements, subclasses, traits)

*Drafted 2026-11-11 from a read-through of the current combat code. Nothing in the game was modified. Paths are relative to the repo root. Line numbers are as of commit `b0476e3` and will drift; function names are the stable reference.*

**Scope.** Normalize weapons (no stat differences), add the Wave form, add a status-effect core, give each of the 7 elements one signature mechanic expressed by all 7 forms, add the 4 missing weapons, and add per-instance Subclasses + rarity Traits through a small hook interface. Stratagem input is untouched (full tap codes, cooldown + mana gated).

**Read before coding:** `docs/master_plan.md` §3, and the memory notes on the spell preload cycle, RPC room scoping, combat stats and run-loss persistence.

---

## 0. Decisions this plan locks in

| Topic | Decision |
|---|---|
| Wave tap suffix | `[1, 2]` (up, right). Reserved for the next 7 forms: `[1,3]`, `[3,2,0..3]`, `[3,3,0..3]` (9 slots) |
| Baseline basic | 1 shot, 1.0 x Attack, 0.35 s cooldown, size 1.0, speed 4000, for every weapon (2.857 x Attack per second; 271 DPS at Attack 95) |
| Spell numbers | Unchanged per form; every weapon now casts what the Orb casts today (all multipliers 1.0) |
| Element signatures | Fire Burn, Lightning Chain, Ice Chill/Freeze, Wind Gale (displacement), Nature Bloom (healing), Water Quench (bullet erasing + Soak), Earth Sunder (interrupt + armor break) |
| First 7 subclasses | Tome Glyphscribe, Wand Trickshot, Staff Vaulter, Orb Constellation, Lantern Lamplighter, Instrument Songweaver, Totem Idolkeeper |
| Effect authority model | "Every peer simulates, the defender's authority applies." No new damage RPCs; secondary effects are local nodes that hit through `Hurtbox.take_hit` like projectiles do |
| Phase order | Suggested order with one change: the 4 new weapons move up to Phase 2 (pure data, and Wave cannot be player-tested until a weapon that holds it exists), Wave is Phase 3 |

---

## 1. Audit findings (what blocks the design today)

| # | Finding | Where | Consequence |
|---|---|---|---|
| A1 | `build_spell_data` hard-indexes `WEAPONS[weapon]` | `spell_data.gd` `build_spell_data` | Any new weapon id (staff, lantern, ...) crashes at cast, for players and for enemies that roll it |
| A2 | Per-weapon spell multipliers (damage/speed/size/lifetime) and `basic_*` keys | `spell_data.gd` `WEAPONS`, `build_spell_data`, `get_effective_range` | Violates decision 3. `damage` is already unused (damage = Attack x form mult); speed/size/lifetime are live. `crit_chance` is dead |
| A3 | Orb basic is 3.18 x Attack/s on paper (1.75 / 0.55), higher than tome and wand, yet played worst | `WEAPONS["orb"]` | Paper DPS is not felt DPS: slow heavy shots lose to overkill and misses. Shape traits need a compensating property, not just equal math (§7) |
| A4 | Elements are colour + crit matchup only | `ELEMENTS` (`damage`/`speed` 1.0 everywhere) | No per-element behaviour hook exists anywhere |
| A5 | No status-effect system at all | `player.gd`, `enemy.gd` | Closest things: enemy `_knockback`, `apply_shove` (cancels wind-up, delays `cast_timer`), `shield_up` synced bool, player `barrier`, `_iframe_timer` |
| A6 | Hit resolution is duplicated | `player.gd` `_on_hurtbox_hurt`, `enemy.gd` `_on_hurtbox_hurt` | Both must gain status application; unify first (master plan §5.8 `Combat.resolve_hit`) |
| A7 | Hitbox carries only damage, element, crit stats, caster id | `hitbox.gd` | No way to tell basic from spell, no attacker Attack reference, no per-cast payload |
| A8 | Spawn RPC chain has a fixed positional signature | `player.gd` `_spawn_cast` / `spawn_spell_local`, `world.gd` `server_request_spawn_spell` / `client_spawn_spell` | Subclass, traits and a per-cast seed cannot reach other peers. One trailing `cast: Dictionary = {}` param fixes it; all four functions and both call sites must pass it |
| A9 | One RPC per pellet | `player.gd` `cast_spell` loop | Tome sends 3 reliable RPCs per shot today; a Torrent trait would send ~7/s. Acceptable, but batch pellets with an offsets array (as `enemy.gd` `spawn_projectile` does) when the signature is touched |
| A10 | Projectiles have no events | `projectile.gd` | Hit/expire/wall are handled inline with `queue_free()`. Needs a cycle-safe dispatch (must not reference `SpellData`) |
| A11 | Enemy spell casting is switched off | `enemy.gd` `uniform_bullets := true`, `_plan_next_cast` | Enemies only fire `default` or the archetype `attack_form` (hexagon rain) plus the warder burst. "Enemy usage" of Wave needs an explicit hook, not just `_roll_forms` |
| A12 | Weapon lists are duplicated | `enemy.gd` `WEAPON_TYPES`, `WEAPON_LETTERS`; `player.gd` `STARTER_KIT_WEAPONS`; `item_data.gd` `LOOT_GROUPS["weapons"]`, `CONTAINERS`, `ENEMY_LOOT_POOLS`; `spell_data.gd` `STARTER_FORMS`; `projectile.gd` `_play_spawn_sound` | Add `SpellData.WEAPON_ORDER` as the single source |
| A13 | Capability list == max forms | `weapon.gd` `can_hold_form` | No cap on attached forms; with 6 capable forms later a weapon could hold 6. Add `SpellData.MAX_ATTACHED_FORMS := 3` |
| A14 | `Weapon` has no subclass/traits; `from_dict` constructs via `_init` (which rolls) then overwrites | `weapon.gd` | Old saves need a deterministic migration (seeded by `instance_id`) or a weapon would re-roll on every load until re-saved |
| A15 | Tooltip and name have no place for flair | `item_data.gd` `tooltip_text`, `display_name` | Add subclass + trait lines |
| A16 | No weapon sprites exist | `item_data.gd` `ITEMS` (`color` + `icon_label`), `enemy.gd` `WEAPON_LETTERS` | "Placeholder art" for the 4 new weapons = a colour and a letter. No texture work this round |
| A17 | DoT forms tick through `take_hit` | `beam_projectile.gd`, `rain_projectile.gd` `_apply_tick` | Each tick drains player gear durability (`_drain_gear_durability`) and would apply a full status dose unless buildup is scaled by damage (§4.2) |
| A18 | `get_effective_range` ignores a form's own `max_distance` | `spell_data.gd` | Wave has a short fixed reach; enemies would misjudge it |
| A19 | Kill credit reaches the killer with no payload | `world.gd` `credit_kill` / `client_credit_kill` | `on_kill` hooks need position + element; extend the RPC |
| A20 | Code input is still a full root in mode 1 | `player.gd` `move_state` (`apply_friction` while `spell_mode_1`) | Not in scope, but the Songweaver subclass and the "walking cast" trait assume the current behaviour |

Not blockers, keep as is: defender-side crit/defense resolution, `Hitbox.can_hit` friendly-fire rules, client-predicted casting, per-form `stratagem_cooldown`, `spell_cooldowns` on the caster.

---

## 2. Weapon normalization and the baseline basic

### 2.1 Data shape (`scenes/spells/spell_data.gd`)

```gdscript
const WEAPON_ORDER := ["tome", "wand", "staff", "orb", "lantern", "instrument", "totem"]
const MAX_ATTACHED_FORMS := 3
const EQUIPPABLE_WEAPONS = {
    "tome":       {"element": "fire", "forms": ["ball", "rain", "beam"]},
    "wand":       {"element": "fire", "forms": ["bolt", "ball", "cone"]},
    "staff":      {"element": "fire", "forms": ["bolt", "beam", "wave"]},
    "orb":        {"element": "fire", "forms": ["bolt", "rain", "burst"]},
    "lantern":    {"element": "fire", "forms": ["wave", "rain", "cone"]},
    "instrument": {"element": "fire", "forms": ["cone", "beam", "burst"]},
    "totem":      {"element": "fire", "forms": ["ball", "wave", "burst"]},
    "fishing_rod": {"element": "default", "forms": []},
}
```

- Delete `WEAPONS` entirely. `build_spell_data` and `get_effective_range` stop reading weapon multipliers; the `weapon` argument stays (it is carried for sound, mods and the tooltip).
- `forms` stays the capability list. When 7 more forms arrive each list grows to 6; nothing else changes because attach is capped by `MAX_ATTACHED_FORMS` in `Weapon.can_hold_form` (`forms.size() < SpellData.MAX_ATTACHED_FORMS`).
- Add `static func validate_roster() -> String` (called from `_static_init` in debug builds, prints on failure): every form appears on exactly 3 weapons, every weapon pair shares exactly `forms_total / 7` forms (1 now, 2 with 14 forms).
- `STARTER_FORMS`: tome ball, wand bolt, staff bolt, orb burst, lantern cone, instrument cone, totem ball.

### 2.2 Baseline basic (`FORMS["default"]`, unchanged values)

| Stat | Value | Note |
|---|---|---|
| Damage | 1.0 x Attack | Attack 90-120 by rarity roll (unchanged) |
| Cooldown | 0.35 s | 2.857 shots/s |
| Pellets / spread | 1 / 0 | Shape only changes through a trait (§7) |
| Speed / lifetime / size | 4000 / 2.0 s / 1.0 | Reach capped by `PROJECTILE_MAX_RANGE` |
| DPS | 2.857 x Attack | 271 at Attack 95, 286 at 100, 343 at 120 |

Stratagems stay far above it: bolt 4x / 12 s, cone 5x / 15 s, wave 5x / 18 s, ball 6x / 20 s, burst 8x / 25 s, beam 10x / 30 s, rain 15x / 45 s.

`build_spell_data` keeps returning `pellets`, `spread_deg`, `damage_mult`, `attack_cooldown`; they are now filled only from the form, and later rewritten by trait hooks (`modify_basic`, §6.3).

`projectile.gd` `_play_spawn_sound`: one basic-shot sound for every weapon (`shoot_wand`) until per-weapon audio exists.

---

## 3. New form: Wave

### 3.1 Tap code (`scenes/spells/spell_recipes.gd`)

Current suffix tree (4 directions, prefix-free): `[0]` bolt, `[2]` beam, `[1,0]` ball, `[1,1]` rain, `[3,0]` burst, `[3,1]` cone. `[0]` and `[2]` are leaves, so new codes must start with 1 or 3. Free two-tap slots: `[1,2]`, `[1,3]`, `[3,2]`, `[3,3]`.

- **Wave = `[1, 2]`** (up, right). Full code = element prefix + `[1,2]`, 4 taps.
- Reserve for the next 7 forms: `[1,3]` as a leaf, `[3,2]` and `[3,3]` as branches (`[3,2,0..3]`, `[3,3,0..3]`): 9 slots, longest full code 5 taps (`record_attack_direction` clears at more than 6).
- Add a comment block with this reservation and a debug prefix-free assertion in `_static_init`.

### 3.2 Form data

```gdscript
"wave": {
    "scene": preload("res://scenes/spells/wave_projectile.tscn"),
    "damage": 5.0, "stratagem_cooldown": 18.0, "mana_cost": 130.0,
    "speed": 0.3,            # 1200 u/s: faster than every enemy's move_speed (500-900)
    "lifetime": 0.75,        # x BASE_LIFETIME 2.0 = 1.5 s
    "max_distance": 1800.0,  # fixed reach, players and enemies
    "size": 1.0,             # the scene owns its rectangle; do not scale it
    "attack_cooldown": 0.5, "spawn_offset": 160.0,
    "pierce": true, "stop_on_wall": false, "auto_hit": false,
    "carry": true,
},
```

`get_effective_range`: honour `fd.get("max_distance")` when present (A18). `build_spell_data` copies `carry`.

### 3.3 `scenes/spells/wave_projectile.gd` + `.tscn`

Scene: copy `cone_projectile.tscn`; hitbox shape = `RectangleShape2D` 96 (depth, along travel) x 640 (width); visual = a `Polygon2D` crest. Script (`extends Projectile`, `class_name WaveProjectile`):

- Moves with the base `_physics_process`. `scale` stays `Vector2.ONE` (like the beam).
- **Hit once:** `_hit_ids` dictionary keyed by `hurtbox.owner_id` (same pattern as `cone_projectile.gd`), gated by `hitbox.can_hit` and a wall ray from the wave centre.
- **Wall stop:** each frame, ray from centre along `direction` for `speed * delta + 48` on mask 1; on hit, `_expire()`. The ends of the wave may clip walls; only the centre stops it.
- **Carry (enemies, server only):** for each overlapping enemy hurtbox, call `enemy.apply_carry(direction * speed * carry_factor, self)` every physics frame. `carry_factor`: 1.0 default, 0.5 for `pentagon` and silver tier, 0.25 for gold (they slide out the back of the wave). Add `ARCHETYPES[..]["carry_resist"]` rather than hard-coding shapes.
- **Carry (players, enemy-cast wave, victim peer only):** softened: `player.apply_push(direction * speed * 0.5)` for at most 0.4 s total per wave; skipped while `is_invulnerable()` (roll through it).
- **Release:** on `_expire`, each carried enemy gets a small fling (`_knockback += direction * 600`).

### 3.4 `enemy.gd` additions (server)

```gdscript
var _carry_velocity := Vector2.ZERO   # set each frame by a wave; zeroed after use
var _wall_slam_ids := {}              # wave instance ids that already slammed us
func apply_carry(v: Vector2, source: Node) -> void
```

In `_physics_process` next to the `_knockback` block: if `_carry_velocity != ZERO`, `var col = move_and_collide(_carry_velocity * delta)`; if `col` and the source has not slammed this enemy yet, deal a **wall slam** = 50% of the wave's damage through `take_damage` (after Defense) and show a number. While carried: skip AI movement for that frame, do not cancel casting (Earth does that).

### 3.5 Item, loot, UI, enemies

- `item_data.gd`: `form_stone_wave` ("Wave Gem", colour `Color(0.3, 0.75, 0.8)`, `icon_label` "w"), `DESCRIPTIONS`, `VENDOR_SELL` (18), `MATERIAL_TYPES`, `LOOT_GROUPS["form_stones"]`, the legacy `CONTAINERS` / `ENEMY_LOOT_POOLS` lists where form stones are enumerated.
- `spell_list_ui.gd`, `workbench_ui.gd`: no change (both iterate recipes / `capable_forms()`).
- `player.gd`: no change beyond FORMS (cooldown, mana and prefix checks are generic).
- **Enemy usage:** add an optional archetype key `"special_form": "wave", "special_every": 3` to `pentagon` (the bruiser that advances): every 3rd burst is replaced by one wave with a 0.6 s wind-up and a ground-rectangle ghost in `_show_windup`. Damage = the archetype's `attack` (70, x tier). Works with `uniform_bullets` on. When `uniform_bullets` is switched off later, enemies holding staff/lantern/totem pick wave up through `_roll_forms` automatically.

---

## 4. Status-effect core

### 4.1 Files

| File | Role |
|---|---|
| `scenes/combat/status_effects.gd` (`class_name StatusEffects`) | `const DEFS` table + bit ids. No reference to `SpellData` or any projectile class |
| `scenes/combat/status_holder.gd` (`class_name StatusHolder extends Node`) | Per-character state. Added in code by `enemy.gd` and `player.gd` `_ready` (`status = StatusHolder.new(); add_child(status)`) |
| `scenes/combat/combat.gd` (`class_name Combat`) | `static resolve_hit(...)` shared by both hurt handlers, `static apply_on_hit(...)` |
| `scenes/combat/status_visuals.gd` | Draws overlays from `status_mask` on any peer |

### 4.2 Buildup is proportional to damage

`Hitbox` gains: `attack_ref: float` (caster Attack), `is_spell: bool` (form != "default"), `cast: Dictionary` (§6). Every `take_hit(hitbox, damage)` call converts to **units**:

`units = damage / max(hitbox.attack_ref, 1.0)`

A baseline basic hit is 1.0 unit, a Torrent pellet 0.4, a fireball 6.0, one beam tick 1.67. Equal DPS therefore means equal status buildup, for any basic shape, pellet count or tick rate (fixes A17). Element advantage (attacker element beats defender element) multiplies units by 1.5; the wheel now matters for effects as well as crit.

### 4.3 `StatusHolder` API

```gdscript
var is_player := false
var owner_attack_scale := 1.0
func apply(id: String, units: float, src: Dictionary) -> void  # authority only; src = {"peer": int, "attack": float, "spell": bool}
func has(id: String) -> bool
func amount(id: String) -> float
func tick(delta: float) -> void         # called by the owner's authority _physics_process
func move_mult() -> float               # chill
func is_disabled() -> bool              # frozen or staggered (enemies only)
func outgoing_mult() -> float           # soak
func mask() -> int                      # bitfield for the synced status_mask
func clear_all() -> void                # death, revive, room change
signal dot_tick(amount: float, id: String, src_peer: int)
signal changed(mask: int)
```

Owner wiring:
- **Enemy (server):** `_physics_process` calls `status.tick(delta)`; multiply the final velocity by `status.move_mult()` before the main `move_and_slide()`; if `status.is_disabled()` call `reset_casting()` once on entry and skip AI for the frame (knockback/carry still apply). `dot_tick` -> `_status_damage(amount, id, peer)`.
- **Player (own peer):** `move_state` / `attack_state` use `max_velocity * status.move_mult()`; `cast_spell` multiplies `atk` by `status.outgoing_mult()`. `dot_tick` -> `take_damage`.
- **Sync for visuals:** `@export var status_mask := 0` on both, written from `changed`. Add it to the `SceneReplicationConfig` in `enemy.tscn` (properties/7) and `player.tscn` (properties/10), spawn = true, replication mode on-change. Late arrivals see current statuses; no RPC needed.

### 4.4 Status table (starting numbers; all in `StatusEffects.DEFS`)

| id | Element | On enemies | Basic cap | Spell | On players (softened, from enemy hits) |
|---|---|---|---|---|---|
| `burn` | Fire | Stacks; each stack ticks 6% of source Attack every 0.5 s; 4 s, refreshed on apply; on death jumps to the nearest enemy within 320 at half stacks | +0.5 stack/unit, max 2 | x2 buildup, max 6 | One stack only: 1% max HP per 0.5 s for 2 s. A dodge roll extinguishes it |
| `chill` | Ice | Meter 0-100; move slow up to 40% at 100; decays 12/s after 1.5 s without ice hits. At 100 from a spell: **Frozen** 2 s (no move, no cast, wind-up cancelled), then 4 s freeze-immune | +7/unit, max 60 (slow only) | +14/unit, can freeze | Slow 25% for 1.5 s, refreshes, never stacks, never freezes. Roll speed unaffected |
| `soak` | Water | Soaked: its bullets fly 25% slower and deal 20% less | 1.5 s/unit, max 3 s | 6 s | Soaked 3 s: your basic deals 20% less. Stratagems unaffected |
| `seed` | Nature | Marked. If it dies while seeded it drops a Bloom (§5.1) | 4 s mark | 8 s, "overgrown" (double Bloom) | None on the player. The enemy heals itself for 50% of damage dealt, max 10% of its max HP per hit |
| `sunder` | Earth | Counts units landed during a wind-up; at threshold (bronze 2, silver 4, gold 8) the attack is cancelled and the enemy is **Staggered** 1.0 s. Shield damage x3; ignores `armored` | builds only during wind-up | Instant stagger (gold: only during wind-up). 6 s re-stagger immunity | Shove 350 u away from the hit. No input loss, code entry not interrupted |
| (chain) | Lightning | Not a status: on-hit arc to nearest other enemies (§5.1) | 1 arc, 20% of the hit, 320 u | 3 arcs, 50%, 520 u | Arcs once to one other player within 400 for 40% after a 0.3 s spark tell |
| (gale) | Wind | Not a status: on-hit displacement (§5.1) | Knockback x2.5 | Per-form pull/push | Tug of 250 u, never during a roll |

### 4.5 Rules

- **DoT ticks:** no crit, no advantage crit bonus, reduced by Defense DR and affix defense, absorbed by an active elite shield and by player `barrier`, no knockback, no facing snap, no hurt i-frames, **no gear durability drain**, aggro and kill credit go to `src.peer`. Damage numbers for ticks are small and element-coloured, at most 2 per second per target.
- **Shielded elites:** no status applies while `shield_up`. Earth hits do x3 shield damage; an advantage-element hit still shatters it instantly.
- **Hard CC on enemies:** tier scaling. Silver: freeze/stagger durations x0.6. Gold and guardians: never frozen (slow capped at 20%), stagger only by interrupting a wind-up.
- **No hard CC on players, ever.** Maximum simultaneous slow on a player is 25%. Softened statuses do not stack with themselves.
- **Clears:** `clear_all()` on death, on revive, on leaving the room, on entering the hub.
- **Hub:** statuses apply to nothing (no hostile sources), as today.

### 4.6 `Combat` helpers

```gdscript
static func resolve_hit(hitbox, damage: float, defender_element: String, defense: float) -> Dictionary
    # {"damage": float, "is_crit": bool, "advantage": bool}; the code now in both _on_hurtbox_hurt
static func apply_on_hit(defender: Node, hitbox, pre_mitigation_damage: float, advantage: bool) -> void
    # units -> defender.status.apply(element status) ; then chain / gale / sunder side effects ; then mods' on_hit_resolved
```

Both hurt handlers call `resolve_hit`, keep their own extras (cloak armor, affix defense, aggro, i-frames), then call `apply_on_hit`. Arc and bloom damage enter through `defender.take_secondary_hit(amount, element, src_peer)` (Defense applies, no crit, no further on-hit effects, so nothing can loop).

---

## 5. Elements

### 5.1 The seven signatures

| Element | Signature | Role | Weak version on basic |
|---|---|---|---|
| Fire | **Burn**: damage over time that jumps to a neighbour when its host dies | Sustained damage | Up to 2 stacks (about +4% of basic DPS) |
| Lightning | **Chain**: hits arc to nearby enemies | Pack damage | 1 arc for 20% within 320 u |
| Ice | **Chill**: slows, and spells freeze | Control | Slow up to 24%, never freezes |
| Wind | **Gale**: moves enemies (and their bullets) | Positioning | Knockback x2.5 on each hit |
| Nature | **Bloom**: marked enemies die into healing blooms | Sustain | Seeded kills drop a Bloom healing 10 HP to players within 300 |
| Water | **Quench**: erases enemy bullets, soaks shooters | Defense | A basic shot is consumed to cancel one enemy bullet it touches; hits soak briefly |
| Earth | **Sunder**: interrupts wind-ups, cracks armor and shields | Counterplay | Hits during a wind-up build toward cancelling it; x3 shield damage |

No two overlap: damage over time, multi-target, immobilise, reposition, heal, bullet defense, interrupt.

Implementation notes:
- **Chain arcs** resolve in `Combat.apply_on_hit` on the server: pick nearest enemies in the `enemies` group within radius, `take_secondary_hit`, and show a `Line2D` zap through a room-scoped RPC (`_show_arc(points: PackedVector2Array)`, unreliable, same targeting as `_emit_damage_number`).
- **Bloom** is spawned in the enemy `is_dead` setter on every peer (it already runs everywhere on the alive -> dead edge) when `status_mask` has the seed bit. `scenes/combat/bloom.gd`: a 0.6 s expanding ring; each player's own peer heals itself if inside (`player.heal(amount)`, new, authority only). No RPC. Guardrail: Bloom healing per player is capped at 150 HP per 60 s (tracked on the player).
- **Quench** runs on each peer's own copies, exactly like the existing burst bullet clear (`burst_projectile.gd`): the victim's copy of the bullet is the one that matters. Add a shared `Projectile.erase_enemy_bullets(center, radius)` helper.
- **Gale** uses the enemy `_knockback` vector on the server; pulls set it toward the anchor point, capped so an enemy never overshoots the anchor.
- **Sunder** reads the existing wind-up state (`_windup_left > 0.0`) and reuses `_cancel_windup()` + `cast_timer = maxf(cast_timer, 1.0)` (what `apply_shove` does).

### 5.2 Element x form table (player casts; ★ = bespoke, built by hand)

| | Bolt | Ball | Rain | Beam | Burst | Cone | Wave |
|---|---|---|---|---|---|---|---|
| **Fire** | Leaves a short burning streak on the ground along its last 400 u | Explosion leaves a scorch patch (3 s) that burns whoever stands in it | Fire zone: every tick adds a burn stack, max stacks fast | Burn ramps: stacks added per tick double after 0.6 s on the same target | Ring of fire stays at the blast edge for 2 s; crossing it burns | Flame breath: applies 3 stacks at once | ★ **Wildfire**: the wave leaves a burning trail the full length of its path for 4 s |
| **Lightning** | Chains 3 times from the first enemy hit | Explosion arcs from every enemy it hit to one more outside the blast | ★ **Thunderstorm**: no ground ticks; 8 seeded lightning strikes hit random enemies in the zone, each chaining once | Forks: at the first enemy the beam splits into 2 short side beams toward the nearest others | Each enemy hit becomes a node that arcs to the next (a ring of arcs) | Arcs jump outward from the far edge of the cone to enemies behind it | Enemies carried together arc to each other every 0.3 s |
| **Ice** | Pierces a frozen enemy and shatters it for a 240 u shard burst | Flash-freezes everything in the blast for 1 s | Blizzard: chill builds each tick; an ice floor slows 30% while inside | Freeze ray: holds a target 1 s then freezes it | Frost nova: instant freeze 1.5 s around you | Frost breath: full chill meter on everything hit | Enemies released by the wave are frozen where it ends |
| **Wind** | Skewers the first enemy and carries it along until a wall (wall slam) | ★ **Tornado**: instead of exploding, becomes a vortex that drifts forward 3 s, pulling enemies in and spinning their bullets away | Cyclone zone: constant pull toward the centre | Wind tunnel: pushes enemies along the beam direction | Blasts enemies far outward and reflects enemy bullets instead of deleting them | Gust: heavy knockback and pushes enemy bullets back along their path | Carries 50% farther and flings enemies at the end |
| **Nature** | Seeds the target; if the bolt kills, the Bloom is double size | Thorn burst: seeds everything hit; brambles (2 s) slow enemies leaving the blast | ★ **Sanctuary Grove**: the zone also heals players inside for 8 HP per tick | Lifelink: heals the caster for 3% of beam damage dealt | Seeds everything; each enemy that dies within 4 s blooms | Spore cloud lingers 3 s, seeding whatever walks in | Leaves a grass strip (4 s): seeded enemies on it are rooted in place |
| **Water** | Erases every enemy bullet within 96 u of its path | Splash erases bullets in 1.5x the blast radius and soaks | Rain shelter: enemy bullets entering the zone fizzle | Hose: erases bullets along the beam and pushes soaked enemies back slightly | Tidal ring: double the usual bullet-clear radius, soaks all | Splash: erases bullets in the wedge, soaks | ★ **Tidal Wave**: 50% wider, erases every enemy bullet it crosses, soaks everything carried |
| **Earth** | Staggers the first enemy hit and stops (never pierces) | Quake: staggers all in the blast and strips `armored` for 6 s | ★ **Boulderfall**: 5 seeded boulders drop in sequence (impact damage + stagger) and remain 6 s as rubble that blocks enemy bullets | Drill: shield damage x6, strips `armored` while held on a target | Shockwave: staggers and knocks down everything hit | Rubble spray: staggers and leaves a low rubble line (3 s) that blocks enemy bullets | Rockslide: wall slam damage is 100% instead of 50% and staggers on slam |

Rules for this table:
- The generic status from §4 always applies in addition (through the normal hit). The table is the form's extra expression.
- 43 generic cells are written as small functions; 6 bespoke cells replace the form's behaviour (flag in the form script, e.g. `rain_projectile.gd` checks `spell_data["bespoke"] == "thunderstorm"`).
- Rubble (`scenes/combat/rubble.gd`): an `Area2D` that frees enemy bullets on contact (group `enemy_bullets`). It is **not** a physics body, so navmesh and enemy movement are untouched.
- Random placement (thunderstorm, boulderfall) uses `cast["seed"]` with a local `RandomNumberGenerator`, so all peers agree.

### 5.3 Where expressions live

`scenes/combat/element_forms.gd` (`class_name ElementForms`): `const TABLE := {"fire:bolt": "_fire_bolt", ...}` and one static function per cell with the signature `(event: String, proj: Node, arg) -> void`. Dispatched by `CastFx` (§6.2). Must not reference `SpellData` or projectile class names (duck-type on `proj.spell_data`).

### 5.4 Enemy casts

- Enemy **basic bullets** carry the element's softened status (§4.4 last column) and nothing else.
- Enemy **form casts** (hexagon rain, warder burst, pentagon wave) apply the softened status only; table expressions are skipped (`spell_data["from_enemy"]`), so the player never faces a tornado or a freeze.
- Enemy chain/gale on players use the softened rows in §4.4.

---

## 6. Cast pipeline, hooks and networking

### 6.1 The `cast` dictionary (the only new RPC parameter)

Append `cast: Dictionary = {}` to: `player.gd` `_spawn_cast`, `spawn_spell_local`; `world.gd` `server_request_spawn_spell`, `client_spawn_spell`. Every caller passes it.

| Key | Type | Meaning |
|---|---|---|
| `sub` | String | Subclass id of the casting weapon ("" for enemies and broken weapons) |
| `tr` | Array[String] | Trait ids |
| `seed` | int | Per-cast seed (`randi()` on the caster) for anything random |
| `off` | PackedFloat32Array | Pellet angle offsets; one RPC per volley (replaces the per-pellet loop in `cast_spell`) |
| `dm`, `sz`, `lt` | float | Damage / size / lifetime multipliers for derived casts (echo, idol repeat, ripple). Default 1.0 |
| `tag` | String | Derived-cast marker ("echo", "idol", "ripple", "glyph") so hooks do not recurse |
| `x` | Dictionary | Small per-subclass payload (note id, eclipse phase, mirror flag) |

`spawn_spell_local` writes into `spell_data`: `cast`, `attack_ref`, `is_spell`, `_fx = Callable(CastFx, "dispatch")`. `projectile.gd` `setup_spell` copies `attack_ref`, `is_spell`, `cast` onto the hitbox. Trust model is unchanged (friends-only; the server relays the dict without validating it).

### 6.2 Projectile events (cycle-safe)

`projectile.gd` gains one private helper and no new references:

```gdscript
func _fx(event: String, arg = null) -> void:
    var cb = spell_data.get("_fx")
    if cb is Callable and cb.is_valid():
        cb.call(event, self, arg)
```

Called at: end of `setup_spell` (`"spawn"`), every place a hit is delivered (`"hit"`, arg = hurtbox: `_on_hitbox_area_entered`, cone/beam/rain/wave loops), `_on_hitbox_body_entered` (`"wall"`), `_expire` and the consume-on-hit free (`"expire"`, arg = position). Derived projectiles (`ball_projectile.gd` `_explode` duplicates `spell_data`) inherit the callable and the cast dict automatically.

`scenes/combat/cast_fx.gd` (`class_name CastFx`): `static func dispatch(event, proj, arg)` routes to (1) `ElementForms`, (2) each mod from `proj.spell_data["cast"]`. Skips mods when `from_enemy`. **`CastFx`, `ElementForms`, `WeaponMods` and every mod script must never name `SpellData`** (compile cycle through the preloaded projectile scenes); pass colours and numbers through `spell_data`.

### 6.3 Mod hook interface

`scenes/combat/weapon_mod.gd`:

```gdscript
class_name WeaponMod extends RefCounted
# caster's own peer
func modify_basic(_player, _weapon, _sd: Dictionary) -> void: pass       # rewrite pellets/spread/cooldown/damage_mult/size
func on_basic_fire(_player, _weapon, _sd: Dictionary, _cast: Dictionary) -> void: pass
func on_spell_cast(_player, _weapon, _sd: Dictionary, _cast: Dictionary) -> void: pass
func on_roll(_player, _weapon, _phase: String) -> void: pass             # "start" / "end"
func on_kill(_player, _weapon, _info: Dictionary) -> void: pass          # {"pos", "element", "archetype", "status_mask"}
func tick(_player, _weapon, _delta: float) -> void: pass
# every peer that simulates the projectile
func on_projectile_spawn(_proj, _cast: Dictionary) -> void: pass
func on_projectile_hit(_proj, _hurtbox, _cast: Dictionary) -> void: pass
func on_projectile_wall(_proj, _cast: Dictionary) -> void: pass
func on_projectile_expire(_proj, _pos: Vector2, _cast: Dictionary) -> void: pass
# defender's authority
func on_hit_resolved(_defender, _hitbox, _damage: float, _is_crit: bool) -> void: pass
```

- `scenes/combat/weapon_mods.gd` (`class_name WeaponMods`): `static func get_mod(id) -> WeaponMod` (lazy singleton cache over `preload`ed scripts in `scenes/combat/mods/*.gd`), `static func for_weapon(weapon) -> Array`, `static func for_cast(cast) -> Array`.
- Mods are **stateless**. Caster state lives in `player.mod_state: Dictionary` keyed by `weapon.instance_id` (cleared on weapon swap/unequip); projectile state lives on the projectile.
- Call sites in `player.gd`: `get_spell_data()` / `get_default_spell_data()` end with `modify_basic` (basic only); `cast_spell` builds `cast`, calls `on_basic_fire` or `on_spell_cast` before spawning; `_start_roll` and the end of `roll_state` call `on_roll`; `_physics_process` calls `tick`; `world.gd` `client_credit_kill(info)` (extended, A19) calls `on_kill`.
- Derived casts go through `player.spawn_derived_cast(origin, dir, form, cast_overrides)` which wraps `_spawn_cast`, costs no mana, starts no cooldown and sets `tag`.
- **Authority rule for mods:** anything that damages goes through a hitbox/zone node (`take_hit`); anything that changes the caster (mana, cooldown, heal, buffs) happens only in caster-side hooks; visuals may run anywhere.

### 6.4 Shared zone node

`scenes/combat/ground_zone.gd` + `.tscn` (`class_name GroundZone`, Area2D + Hitbox child): `setup(radius, lifetime, colour, opts)` with `opts`: `tick_damage`, `tick_interval`, `status_units`, `element`, `blocks_bullets`, `heal_per_tick`, `slow`, `group`. Used by fire scorch/trail, ice floor, grove, spore cloud, glyphs, light zones. One implementation, many callers. Server-side checks ("is this enemy inside a light zone") use the zone's group.

---

## 7. Subclasses and traits

### 7.1 Data model

`scenes/spells/weapon.gd`:

```gdscript
var subclass: String = ""        # one id from WeaponSubclasses.BY_WEAPON[type]
var traits: Array = []           # trait ids, count by rarity
var relic_id: String = ""        # future named uniques; "" = none
const SAVE_VERSION := 2
func mod_ids() -> Array          # [subclass] + traits (+ relic mods later); [] at 0 durability
static func roll_subclass(type: String, rng: RandomNumberGenerator) -> String
static func roll_traits(type: String, rarity: String, rng: RandomNumberGenerator) -> Array
```

- `_init` rolls both with a fresh RNG. `to_dict` adds `"subclass"`, `"traits"`, `"relic_id"`, `"v": 2`.
- **Migration in `from_dict`:** if `"subclass"` is missing or not a known id, roll with an RNG seeded by `hash(instance_id)`; same for a missing `"traits"` key. Deterministic, so the weapon is stable even before the next save. Unknown trait ids are dropped silently.
- `fishing_rod`: never rolls either.
- A weapon at 0 durability casts as `default`/`default` today; it also loses its mods (`mod_ids()` returns `[]`).

`scenes/spells/weapon_subclasses.gd` (`class_name WeaponSubclasses`):

```gdscript
const SUBCLASSES := {
    "glyphscribe": {"weapon": "tome", "name": "Glyphscribe", "desc": "...", "built": true},
    ...
}
static var BY_WEAPON: Dictionary   # built in _static_init; roll only from built == true
```

`scenes/spells/weapon_traits.gd` (`class_name WeaponTraits`):

```gdscript
const COUNT_BY_RARITY := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 3, "mythic": 4}
const TRAITS := {
    "split": {"name": "Split", "desc": "...", "group": "shape", "min_rarity": "uncommon", "weight": 10, "built": true},
    "cluster": {..., "group": "form", "requires_form": "ball", "min_rarity": "rare"},
}
```

Roll rules: at most one trait per `group`; `requires_form` must be in the weapon type's capability list; `excludes_subclass` honoured; legendary+ guarantees one `min_rarity: rare` trait. Only common/uncommon/rare drop today (`RARITY_DROP_WEIGHTS`), so live weapons carry 0-2 traits.

**Relic hook (do not build):** `scenes/spells/weapon_relics.gd` with an empty `const RELICS := {}` of `{id: {"type", "name", "subclass", "traits", "mods": [..]}}`; `Weapon.mod_ids()` appends `RELICS[relic_id]["mods"]`; `ItemData.display_name` prefers the relic name. Nothing rolls a relic.

### 7.2 UI

- `ItemData.tooltip_text` (weapons): after the forms line, add the subclass name in gold with its description in small italics, then one bullet per trait (`• Split: ...`), using the existing font sizes for gear attributes.
- `ItemData.display_name`: unchanged ("Rare Fire Instrument"); the subclass is the tooltip's second line, so grid names stay short.
- `workbench_ui.gd`: show subclass + traits read-only under the weapon header.
- HUD: `spell_list_ui.gd` gets one line under the recipes with the subclass name. Subclass-specific HUD (Songweaver notes, Constellation motes) is drawn by the mod on the player node, not in shared UI.

### 7.3 Subclasses (21; **bold = built in Phase 6**)

**Tome** (ball, rain, beam)
- **Glyphscribe.** Every spell leaves a glyph where it ends (4 s, radius 260). Your basic shots that hit an enemy standing on a glyph apply your element's signature at spell strength. Every 6th basic hit stamps a small 1.5 s glyph at the impact.
- Annotator. Basic hits write a mark on the enemy (max 5 marks). A spell that hits a marked enemy consumes the marks, each popping as a small blast on that enemy.
- Pagewarden. Casting a spell tears out 3 pages that orbit you; each page blocks one enemy bullet. While pages remain, every 3rd basic also flings a page as a slow homing shot.

**Wand** (bolt, ball, cone)
- **Trickshot.** Basic shots ricochet once off walls. Spells do too: bolt bounces, ball bounces once before detonating, cone reflects a second half-size wedge off a wall within reach. A ricocheted hit applies the element signature at double units.
- Duelist. Rolling through an enemy bullet (i-frame graze) loads a Riposte: your next basic is a fast piercing counter-shot at whoever fired it. A spell cast with Riposte loaded fires instantly and consumes it for a stagger.
- Overflow. For 3 s after a spell, your basic takes that spell's shape in miniature (mini-balls that pop, mini-cones, piercing mini-bolts) at basic damage.

**Staff** (bolt, beam, wave)
- **Vaulter.** Landing a dodge roll sends a ground ripple forward (a half-width mini-wave at basic damage that shoves). The first basic within 0.6 s of a roll is a Sweep: a short wide arc hitting everything in front. Every spell ends in a ripple ring that pushes enemies outward.
- Janus. The staff has two ends: every 3rd basic also fires backward, and every spell casts a half-strength mirrored copy behind you.
- Leywalker. Spells draw a ley line along their path for 5 s. Basic shots that cross a line fork along it in both directions.

**Orb** (bolt, rain, burst)
- **Constellation.** Each basic hit lights a mote that orbits you (max 5, visible). Casting a spell launches every mote as a homing dart at enemies near the spell's impact, each carrying the weak element signature. Getting hit knocks one mote loose.
- Eclipse. Each spell cast flips the orb between Sun and Moon. Sun: basics pop in a small splash, spells end in a flare. Moon: basics pierce, spells pass through the first wall they meet.
- Refractor. Basic shots refract on hit into 2 weak shards at +/-30 degrees. Spells refract when they end, throwing 3 shards outward.

**Lantern** (wave, rain, cone)
- **Lamplighter.** Spells leave a light zone where they end (5 s, radius 320). Enemies in light are Dazzled (their aim wobbles widely). Basics fired by anyone standing in light pierce. Each basic impact leaves a 1.5 s ember of light.
- Darklantern. A hooded lantern: spells leave shadow zones in which players cannot be seen (reuses the `stealth_unseen_still` path). Your basic makes no gunfire noise.
- Flarekeeper. Spells plant a flare at the cast point that enemies target for 2.5 s. Every 8th basic sticks a mini-flare to what it hits.

**Instrument** (cone, beam, burst)
- **Songweaver.** Every basic shot plays a note chosen by your movement direction when it fires (still = Rest). Three notes make a bar; a bar that matches a song grants a buff to you and allies within 900 (§7.4). Casting a spell while a song is active plays its Finale (the song's effect pulses once at the spell's impact) and ends the song.
- Echo. Every spell echoes: 1.2 s later a ghost repeats it from the same spot at 40%. Every 4th basic echoes a second ghost shot 0.25 s later.
- Dissonant. Basics mark enemies with Dissonance. A spell that hits a marked enemy makes it shriek, damaging other enemies around it.

**Totem** (ball, wave, burst)
- **Idolkeeper.** Casting a spell plants a spirit idol at your feet (one at a time, 8 s). While it stands, each of your basics is repeated from the idol toward your cursor at 25% damage (crossfire). Casting again moves the idol and it pulses your element signature where it lands.
- Three-Faced. The totem shows one of three faces, rotating on each spell cast. Wrath: basics pop in small blasts. Guard: basic hits grant 2 barrier (cap 30). Trick: every 5th basic swaps places with a short-lived decoy of you.
- Hexbinder. The first enemy your basic hits becomes the Effigy for 6 s: 30% of damage you deal to other enemies is also dealt to it, and spells that hit it splash their signature to everything near it.

Fallback: if Songweaver slips, ship **Echo** as the Instrument's first subclass (about an hour of work on top of `spawn_derived_cast`) and move Songweaver to Phase 7.

### 7.4 Songweaver spec

- **Notes:** L, U, R, D from absolute movement input at fire time (same directions as the tap codes), N (Rest) when not moving. Diagonals count as their horizontal component.
- **Bars:** non-overlapping groups of 3 notes. A gap of more than 0.8 s between shots clears the bar (release the trigger to realign). Three pips above the player show the current bar; a matched bar chimes, a miss thuds.
- **Encore:** playing the active song again upgrades it to tier II (longer, stronger). There is no tier III.
- **Songs** (party-wide within 900, one song active at a time; a new song replaces the old):

| Bar | Song | Effect (tier I / II) | Finale on spell cast |
|---|---|---|---|
| U U U | Anthem of Ascent | +20% / +30% move speed, 8 / 12 s | Allies in range get a free instant roll charge |
| D D U | Ballad of Mending | Heal 3 / 5 HP per second, 6 / 8 s | 40 HP heal burst at the impact |
| L R L | Dirge | Enemies within 700 of the singer: 20% / 30% slow, 5 / 7 s | Staggers everything the spell hits |
| R R L | Staccato | Basics pierce one enemy, 8 / 12 s | The spell's hits erase enemy bullets around each target |
| U D U | Quickstep | Roll cooldown -40% / -60%, 8 / 12 s | Resets roll cooldown for allies in range |
| N N N | Fermata | Restore 40 / 60 mana to the wielded weapon (30 s lockout per player) | None |

- **Implementation:** note id rides in `cast["x"]["note"]` so other peers can play the right pitch. Buffs are entries in the player `StatusHolder` (`is_player` buffs: `haste`, `mend`, `pierce_basic`, `quickstep`); the singer's peer sends a room-scoped `player.receive_song(song_id, tier)` RPC and each receiving player applies it on its own authority if within 900. Dirge is applied by the server to enemies.
- Accidental songs: a random bar matches about 5% of the time (6 of 125), roughly one stray song per 20 s of continuous fire. Acceptable, and it teaches the system.

### 7.5 Traits (**bold = built in Phase 6**)

Shape group (one per weapon, any weapon type; theoretical DPS equals baseline 2.857 x Attack):

| Trait | Basic becomes | Math | Compensation |
|---|---|---|---|
| **Split** | 3-shot fan, 14 degrees | 3 x 0.42 / 0.44 s | Covers a lane; loses at range |
| **Torrent** | Light fast stream, +/-3 degree jitter, size 0.75 | 0.40 / 0.14 s | Forgiving; weak per-hit knockback |
| **Heavy** | Slow fat shot, size 1.4 | 2.0 / 0.70 s | Pierces 1 enemy and knocks back hard (answers A3) |
| **Twin** | Two parallel shots 48 u apart | 2 x 0.5 / 0.35 s | Wider hit line |

Other traits:

| Trait | Group | Min rarity | Effect |
|---|---|---|---|
| **Piercing** | basic | uncommon | Basic passes through one enemy; the second hit deals 50% |
| **Rebound** | basic | uncommon | Basic bounces once off walls (excluded on Trickshot) |
| **Lingering** | basic | uncommon | A basic that hits a wall leaves a spark mine for 1.5 s |
| Seeking | basic | rare | Basic bends up to 25 degrees toward the nearest enemy in its path |
| **Overture** | spell | uncommon | The first basic after a spell cast is a triple-size shot at 3x damage |
| **Aftershock** | spell | rare | Spells pulse a second time at their end point for 25% |
| **Conduit** | spell | rare | Killing an enemy with a spell refunds 15% of its mana cost, once per cast |
| **Catalyst** | element | rare | Enemies that die affected by your element's signature spread it to neighbours within 300 |
| Attuned | element | rare | Your basic builds its element signature 50% faster |
| **Rollcaster** | utility | rare | Rolling through an enemy bullet takes 1 s off your longest stratagem cooldown |
| Walking Cast | utility | rare | Walk at 40% speed while entering a code instead of standing still |
| Cluster | form (ball) | rare | The detonation throws 3 bomblets |
| Forked | form (bolt) | rare | Splits in two on its first hit |
| Undertow | form (wave) | rare | The wave rolls back to you at half damage |
| Downpour | form (rain) | rare | Call-down delay 0.5 s instead of 1.0 s |
| Prism Beam | form (beam) | rare | The beam is not cut off by the first enemy |
| Afterimage | form (burst) | rare | A second burst fires where you stood 1 s earlier |
| Backdraft | form (cone) | rare | Also fires a half-size cone behind you |

10 built in Phase 6 (4 shape + 6 others); 9 designed for later. Shape traits are implemented in `modify_basic`; everything else through the projectile and caster hooks.

### 7.6 Loot and economy

- Weapons roll subclass + traits in `Weapon._init`, so every source (`world_loot.gd` `_make_loot_item`, `Item.create`, vendor, pauper kit) gets them with no extra code. The pauper kit (`apply_starter_kit`) keeps its subclass but forces `traits = []`.
- `LOOT_GROUPS["weapons"] = SpellData.WEAPON_ORDER`; equal weights for the 7 types.
- No rerolling at the workbench this round (open question 3). Forms and element remain changeable as today; subclass and traits are the loot chase.

---

## 8. Phases for the implementer

Each phase: headless check from the verification-workflow memory after every batch (capture errors, commit only when the grep is empty), then the listed live test, then one commit. Do not start a phase on top of an unverified one.

### Phase 1 — Weapon normalization + plumbing (small)
| Task | Files |
|---|---|
| Delete `WEAPONS`; `build_spell_data` / `get_effective_range` stop reading weapon multipliers and `basic_*`; guard unknown weapon ids | `spell_data.gd` |
| `WEAPON_ORDER`, `MAX_ATTACHED_FORMS`, `validate_roster()`; cap in `can_hold_form` | `spell_data.gd`, `weapon.gd` |
| One basic-shot sound | `projectile.gd` |
| Point duplicated weapon lists at `WEAPON_ORDER` where a const reference works | `enemy.gd`, `player.gd`, `item_data.gd` |
| Add the `cast: Dictionary = {}` param end to end (no behaviour yet); batch pellets into one RPC with `cast["off"]` | `player.gd`, `world.gd` |

Test (1p + 2p): tome, orb, wand basics look and time identically; each spell form is the same size/speed on all three; a second peer sees the shots; enemy damage still lands when the host is in the hub.

### Phase 2 — Four new weapons (data + loot)
| Task | Files |
|---|---|
| `EQUIPPABLE_WEAPONS` + `STARTER_FORMS` for staff, lantern, instrument, totem | `spell_data.gd` |
| Item defs (placeholder colour + letter), descriptions, vendor price by rarity (already generic) | `item_data.gd` |
| Enemy `WEAPON_LETTERS`; starter kit list | `enemy.gd`, `player.gd` |

Placeholder art: Staff `Color(0.45, 0.6, 0.35)` "St" 1x3, Lantern `Color(0.95, 0.8, 0.35)` "La" 1x2, Instrument `Color(0.75, 0.4, 0.6)` "In" 2x2, Totem `Color(0.55, 0.35, 0.3)` "To" 1x2.
Until Phase 3, staff/lantern/totem list `wave` as a capability with no stone, recipe or `FORMS` entry: the workbench row shows it as unattachable and nothing else reads it (enemy `_roll_forms` results are unused while `uniform_bullets` is on). Guard `FORMS.get(form, {})` wherever a form id is looked up.
Test: all 7 drop from a weapon case; each accepts its existing stones at the workbench and refuses others; all 7 basics are identical; `validate_roster()` is silent; old saves load.

### Phase 3 — Wave form
Tasks: §3 in full (`spell_recipes.gd`, `spell_data.gd`, `wave_projectile.gd/.tscn`, `enemy.gd` carry + pentagon special, `item_data.gd` stone).
Test: code `prefix + up,right` arms and casts; wave hits each enemy once; carries a triangle pack into a wall for slam damage; pentagon slips out the back; wave stops at walls; client-cast wave carries enemies on the host; pentagon's wave pushes but never locks the player and can be rolled through.

### Phase 4 — Status core + basic signatures + softened player rules
Tasks: §4 in full; `Combat.resolve_hit` / `apply_on_hit`; hitbox fields; `status_mask` sync + overlays; the 7 basic-strength signatures (§5.1 right column); softened player rows; Bloom; chain arc RPC; `take_secondary_hit`; no durability drain on DoT ticks.
Test: one weapon per element in the hub-adjacent E1 run: burn ticks and jumps on death; lightning arcs only when a second enemy is near; ice slows but never freezes from basic; wind doubles knockback; seeded kill heals 10; a water shot deletes one enemy bullet; earth cancels a square's laser wind-up after 2 hits. 2p: a client's burn kills credit the client; statuses show on both screens; a late room-joiner sees a burning enemy. Enemy fire bullets burn the player lightly and a roll clears it; no enemy hit ever stops the player moving.

### Phase 5 — Element x form expressions + bespoke combos
Tasks: `_fx` events in `projectile.gd` and the five form scripts; `CastFx`; `ElementForms` with 43 generic cells; `GroundZone`; `rubble.gd`; the 6 bespoke combos (Wildfire, Thunderstorm, Tornado, Sanctuary Grove, Tidal Wave, Boulderfall; Wildfire is the cheapest, Tornado the costliest and the one to drop if the phase runs long). Spell-strength statuses (freeze, instant stagger).
Order inside the phase: fire row, ice row, lightning row (commit), wind + earth rows (commit), nature + water rows (commit), bespoke (commit).
Test: per row, cast every form once at a pack; verify the cell's line in §5.2. 2p: thunderstorm strikes and boulders land in the same places on both screens; a client-cast freeze stops enemies on the host; gold elite cannot be frozen.

### Phase 6 — Subclass + trait framework, 7 subclasses, 10 traits
Tasks: §6.3 hooks and call sites; `Weapon` fields, roll, save migration; `WeaponSubclasses`, `WeaponTraits`, empty `WeaponRelics`; tooltip/workbench/HUD lines; extended `client_credit_kill`; `spawn_derived_cast`; the 7 bold subclasses; the 10 bold traits.
Build order (cheapest first, commit after each): framework + shape traits, Idolkeeper, Trickshot, Glyphscribe, Lamplighter, Vaulter, Constellation, other traits, Songweaver.
Test: a pre-phase save loads and every old weapon shows a stable subclass across two restarts; tooltips show subclass + traits; each subclass's basic and spell touch is visible; 2p: the other peer sees derived casts (idol shots, ripples, echo), and song buffs reach an ally in range but not one in another room; DPS check on a dummy pack (§9).

### Phase 7 — Remaining 14 subclasses + 9 traits (later round)
Order by cost: Echo, Janus, Refractor, Annotator, Dissonant, Overflow, Flarekeeper, Eclipse, Hexbinder, Pagewarden, Duelist, Darklantern, Three-Faced, Leywalker. Flip `built: true` as each lands; nothing else changes for loot.

---

## 9. Balance guardrails

1. **Weapon type never changes a number.** Any per-type stat key reintroduced into `spell_data.gd` is a bug.
2. **Basic DPS parity:** every shape trait's all-pellets-hit DPS is within 3% of 2.857 x Attack. Verify with a stationary pentagon (800 HP): time to kill within 10% across baseline/Split/Torrent/Heavy/Twin at point-blank.
3. **Basic signature budget:** an element's weak version is worth at most ~10% of basic DPS in direct damage (burn 4%, chain 20% only with a second target in 320 u) or an equivalent utility.
4. **Subclass budget:** sustained damage added by a subclass is at most 10% of basic DPS averaged over a fight, and is conditional (positioning, timing or a spell cast). Idol repeat is 25% for 8 s per stratagem.
5. **Stratagems stay stratagems:** no trait or subclass reduces a form cooldown below 60% of its base, and nothing casts a full-power spell without its cooldown and mana. Derived casts are at most 50% power.
6. **Players are never hard-CC'd.** Max 25% slow, no freeze, no stun, no input cancel; pushes at most 350 u and never during a roll.
7. **Enemy CC scales by tier:** silver x0.6 duration, gold/guardian immune to freeze and to stagger outside a wind-up; 4 s freeze immunity and 6 s stagger immunity after each.
8. **Healing cap:** Bloom + Grove + Lifelink + Mending together at most 150 HP per player per 60 s.
9. **Network budget:** at most one reliable RPC per basic volley; status visuals ride the synchronizer; arcs are unreliable RPCs.
10. **Hit cap from the master plan still holds:** no single enemy hit over 250 before Defense; softened DoTs never exceed 4% max HP total per application.

---

## 10. Open questions for the designer

1. **Songweaver note source:** absolute screen direction (default here, matches the tap-code directions) or relative to aim (advance/retreat/strafe)? Relative is more of a "dance" but harder to read.
2. **Nature heals in a scarce-healing game.** Bloom is nature's whole identity here, capped at 150 HP/min. Acceptable, or should Bloom grant temporary barrier instead of health?
3. **Rerolling:** should the workbench ever reroll a weapon's subclass or traits (for a crystal/keystone cost), or is it strictly "find a better drop"? Default: no reroll.
4. **Enemy weapons:** enemies roll one of 7 weapon types but it only affects the letter on their label and (later) their form list. Keep, or drop the enemy weapon letter entirely?
5. **Earth rubble:** blocks enemy bullets only (default: enemies walk through it, navmesh untouched). Should it also block player shots?
6. **Fermata (mana song):** in-run mana regeneration is otherwise zero by design. Is a skill-gated 40 mana per 30 s acceptable, or should the Rest song do something else?

## 11. Cut / defer

**Cut from this round:** element-reaction matrix (wet + lightning etc.); per-weapon audio; real weapon sprites; enemy subclasses or traits; enemies using table expressions; trait rerolling; Relic content (hook only); charged basic.

**Defer:** the 14 remaining subclasses and 9 remaining traits (Phase 7); the next 7 forms (suffix slots and `MAX_ATTACHED_FORMS` are ready); turning `uniform_bullets` off so enemies cast their rolled forms; a hub training dummy that reports DPS (would make guardrails 2-4 a 30-second check; worth doing early in Phase 6 if cheap); moving statuses and mods into the planned `PlayerCombat` / `EnemyBrain` components when the master plan Phase 2 split happens.

---

## 12. Implementation status (2026-11-12)

All phases are built and verified headlessly (parse check + the probes below), **not yet play-tested live or in co-op**.

| Phase | Commit | Notes |
|---|---|---|
| 1 Normalization + plumbing | `eb69745` | |
| 2 Four new weapons | `045b872` | |
| 3 Wave | `c1ec060` | |
| 4 Status core + basic signatures | `3d1f3d4` | `scenes/combat/` |
| 5 Element x form + bespoke | `ab5bd2a` | all 49 cells, 6 bespoke |
| 6+7 Subclasses + traits | `676e58c` | all 21 subclasses and all 22 traits built (Phase 7 folded in) |

Deviations from the plan text:
- Projectile events reach the router through `spell_data["_fx"]` (a Callable to `CastFx.dispatch`), as planned; mods additionally get `on_projectile_tick`, `on_graze` and `draw`.
- A basic's final numbers after `modify_basic` travel in `cast["b"]` (not re-derived on each peer), because state-driven basics (Overture, Riposte, Overflow, Eclipse) can't be recomputed remotely.
- Forks, shards, echoes and undertow are **local copies** on every peer (no RPC); things that change the caster or need the cursor (idol repeats, motes, ripples, sweeps, Janus) go through `spawn_derived_cast`.
- Catalyst is resolved in `enemy.gd` on death, Attuned in `Combat.apply_on_hit`, Walking Cast in `player.gd` `move_state` (no mod script).
- Annotator / Dissonant marks show the shared "marked" overlay bit.
- Trickshot cones reflect a half-size wedge (double-strength element) off a wall within reach; Pagewarden pages are a `PageOrbit` node on the caster on every peer (visible to all, each peer blocks its own bullet copies).

Headless probes (`delete_before_export/`): `probe_spells`, `wave_probe`, `status_probe`, `fx_probe` (`ELEM=fire` limits it), `flair_probe`, `caster_probe`.
