# Relic Runners — Master Plan

*Drafted 2026-11-05 from five independent code audits (feel/UX, world/progression, economy/persistence, combat/AI, architecture/netcode) plus the project memory notes. Paths are relative to `C:\dev\gamedev\godot4\relic_runners\`. Nothing in the project was modified.*

**The one-paragraph diagnosis.** The plumbing is unusually good for a solo project: deterministic seeded spawning, server-owned AI, room-scoped RPCs, a real grid inventory, a generated 7-element paradox wheel, a 6-rarity item model. What is missing is everything a player *feels*: there is no dodge, no audio, no hit feedback, every enemy is the same "hold a ring and shoot" turret, three of four archetypes do 8-33 DPS while the fourth one-shots you for 30% HP from off-screen with no warning. Gold never drops, gear is a +10% number, the free starter kit removes death stakes, and ~4 months of work is sitting uncommitted. The plan below is ordered so the designer feels improvement within the first week, then builds the data-driven foundation that map styles and tiers need, and only then adds modes, economy and survival.

---

## 1. Design pillars & identity

### What Relic Runners takes from each influence (and refuses to take)

| Influence | Take | Leave |
|---|---|---|
| Enter the Gungeon | Dodge roll with i-frames; bullets slower than you, dangerous through *density and pattern*; wind-up before every attack; enemy bullets look different from yours | Gun collecting (our "guns" are weave recipes); per-floor room-clear locks |
| Hotline Miami | Short time-to-kill in *both* directions; kills as punctuation (hitstop, shake, sound); gunfire makes noise that pulls enemies | Instant restart (we have a party and a hub); one-hit player death |
| Binding of Isaac | A roster of *legible* movement rules (charger, orbiter, lobber, splitter); champion variants with visible affixes; items that change how your shot behaves | Floor descent / item-synergy roguelike structure |
| Diablo | Paper-doll gear, rarity colours, area-level → item-level, elite affix packs ("Fast, Shielded, Splitter") | Loot firehose; stat soup |
| ARC Raiders / Tarkov | Kit in, loot out; raid timer; keyed/gold rooms; recycle junk into components; bench upgrade gated by keystone items; post-raid summary | PvP; weight/encumbrance; insurance complexity |
| Don't Starve | Day/night pressure; "days 1-10 vs 11-20" ramp as separate *maps*; renewable nodes; campfire as a safe anchor | Sanity, seasons, base-building sprawl |
| Project Zomboid | Noise → investigate; needs that bite slowly; long sessions that can be *saved and resumed* | Skills grind; zombie-count simulation |

### What is distinctively Relic Runners (protect these)

1. **The Paradox Wheel.** Seven elements, each beats exactly three (+1/+2/+4 on the circle) — no element is "best". This is already generated in `SpellData._static_init` and nobody else has it. Every system below should make the wheel *visible and tactical*: enemy fill colour tells you the matchup, elite shields require the right element, map tiers bias the roster so your kit choice is a real bet.
2. **Spells are stratagems (Helldivers model).** Casting by directional-tap codes is the signature verb and is *deliberately* an input commitment: you must find a safe moment to punch in the code. Spells are rare, big, screen-changing special attacks gated by cooldowns, never the filler. The moment-to-moment fight comes from the basic weapon, the dodge roll and positioning (§3); spells are the punctuation that turns a losing fight.
3. **Geometry as a language.** Shape = role, fill = element, border = tier, affix = glyph marks. Enemies that read instantly at 0.75 zoom from across the screen. We keep vector enemies as *the* art direction and polish them (glow, outlines, death shatter) rather than replacing them with sprites.
4. **Two clocks, one world.** Map choice is tempo choice. Extraction maps run on a *raid clock* (timer + portal pressure); Survival maps run on a *day clock* (night + hunger). Same hub, same stash, same wheel, same enemies — different pressure.
5. **The run is the bet.** You choose what to bring; what you carry out is yours; what you die with is on the floor for your team to recover (this already works *except* the re-sync bug that makes death bags invisible — Phase 0).

### Core loop (one run, 20-120 min)
Hub → **Map board**: pick style × tier → **Kit**: pauper kit or a preset from stash → run: fight / loot / craft-in-field (survival) / open keyed rooms (extraction) → **extract** (portal, under wave pressure) or **die** (death bag) → hub: **post-run summary** → stash, recycle, repair, craft, upgrade bench → repeat.

### Meta loop (across runs)
- **Tier sigils** (keystone relics) carried out of tier N unlock tier N+1 on the map board.
- **Bench levels** (crafting bench, weapon workbench) gated by keystone junk + gold unlock recipes, stash tabs, kit-preset slots.
- **Gear that changes verbs** (roll leaves a trail, bolt pierces, first weave tap is free) is the Diablo/Isaac payoff and only rolls at rare+ which only exists in gold-tier (keyed) sources — so the gold tier finally has a reason to exist.
- **Cross-feed**: Extraction produces *arcane* goods (crystals, stones, gear, keys). Survival produces *bulk/processed* goods (planks, rope, cloth, rations, wards). Higher tiers of each style consume the other's output (see §2).

---

## 2. The mode / tier structure

### Principles
- **Start with 2 + 2.** E1, E2 (Extraction) and S1, S2 (Survival). E3 and S3 are defined on paper so the data model is right, but not built until the first four are fun.
- **Tier is a `MapDef` Resource, not a global constant.** Enemy roster, affix pool, pack size, attack-token budget, loot-table tier shift, resource whitelist, timer, hazards — all per map (see §5). Nothing in `enemy_spawner.gd`, `container_spawner.gd` or `exit_portal.gd` keeps its own tuning consts.
- **Two tier axes, kept separate.** *Map tier* (E1/E2/S1/S2) is difficulty and resource profile. *Source tier* (bronze/silver/gold) is the quality of one spawner/container and already exists in `LOOT_TABLES[type][tier]`. The map tier shifts the odds of source tiers and whitelists which groups can appear. Don't collapse these.

### The ladder

| | **E1 — Outskirts** | **E2 — Deep Ruins** | **E3 — Vault** (paper only) | **S1 — Homestead** | **S2 — Long Dark** | **S3** (paper only) |
|---|---|---|---|---|---|---|
| Scene | `village_main` (fixed: 2+ portals) | `dungeon_main` (fixed: hub door) | new | `village_main` reused with a survival `MapDef` (different spawn/resource profile), later its own scene | new "wilds" scene | new |
| Length | 25 min raid timer | 30 min | 35 min | ~75 min = 5 days of 15 min (10 day / 5 night) | ~120 min = 6 days of 20 min (11 / 9) | 150 min |
| Entry requirement | none | Tier Sigil I (from E1) | Tier Sigil II | none | Survivor's Mark (from S1) **and** a kit with ≥ 3 "camp" tagged items | Mark II + full kit |
| Kit | pauper kit allowed | pauper allowed (weak) | preset only | pauper allowed | **preset only, no pauper** | preset only |
| Enemy roster | triangle, circle, pentagon; square only as a named "anchor" at 2 fixed spots | all 4 + hexagon lobber; square free-roaming | all + support crescent + guardian | triangle, circle at day; pentagon packs at night | all shapes; night waves scale per day | guardian each 2nd night |
| Tier mix (bronze/silver/gold) | 90/10/0 (gold only inside 1 keyed room) | 70/25/5 (keyed rooms: 0/50/50) | 50/35/15 | 95/5/0 day; 80/20/0 night | 70/25/5; night 50/40/10 | — |
| Affixes on silver+ | 1 affix, pool: Fast, Shielded | 1-2, + Splitter, Vampiric | 2, + Teleporter, Warder | 1, pool: Fast, Shielded | 1-2 + Burning Trail | — |
| Attack tokens per player | 2 | 3 | 4 | 2 day / 3 night | 3 day / 4 night | — |
| Pack size (×spawner base) | 1.0 | 1.3 | 1.6 | 0.7 day, night waves 1.0→2.0 by day 5 | 1.0 day, night 1.5→3.0 | — |
| Resource whitelist (tags) | arcane, junk, consumable, T1 raw (sparse) | arcane, junk, keys, T3 components; **no T1 raw** | arcane, keys, relic | **T1 raw abundant** (wood, fiber, stone, berries, fish), T2 recipes | T1 raw **scarce** (×0.25 node count, no berries), T2/T3 nodes, relic shards | T3 only |
| Loot-table tier shift | 0 | +1 (silver containers common) | +2 | 0 | +1 | +2 |
| Exit | 3 portals, each 90s charge + waves, one-use | 2 portals + 1 keyed "quiet" portal (no waves, needs a key) | 1 portal + guardian | portal opens only during **day** of day 3+ ; night = sealed | portal opens day 4+; guardian wave at night before | — |
| Hazards | none | darkness pockets (CanvasModulate zones), one "storm" at T-5 min that closes all but one portal | — | night: vision radius halved, enemy hearing doubled; cold (warmth drains ×2 outside campfire) | night + cold + "hunt" (a named elite pack tracks the loudest player each night) | — |
| Unique carry-outs | Tier Sigil I (1 per run, in the keyed room) | Tier Sigil II, keys for E3, relic shards | — | Survivor's Mark (crafted in-field from 3 T2 items: rope + bandage + cooked meal), S2 keys | Relic cores | — |

### The "bring a kit" mechanic
- A **kit** is a saved preset: weapon slots, body, backpack, belt + quick slots, bag contents — built from stash contents in the hub via the existing `expedition_kit_ui.gd` "Custom" path, saved under `save_data.kits[]`.
- The existing **Starter Kit** becomes the **Pauper Kit**: common wand (lowest attack roll, 1 form), 2×2 bag, 1 health potion, no belt, no body. It is always available on tiers that allow it and costs nothing — but it is bad, so bringing your own is a real decision. (The audit is right that a free random weapon + backpack + 2 potions + 2 mana crystals every run deletes death stakes.)
- **Kit gates** are tag counts, not item lists: S2 requires ≥3 items tagged `camp` (bedroll, fire kit, rations, water skin, axe…), E3 requires ≥1 `key` and a rare+ weapon. The `MapDef` holds `kit_requirements: {tag: min_count}` and the kit popup refuses "Confirm" until met. This is cheap, data-driven, and the player sees exactly why.
- Kits are validated only client-side (friends-only trust model, same as everything else).

### How the two styles feed each other
- **Survival → Extraction**: cooked rations (the only healing that doesn't cost a potion slot), wards (consumable that suppresses enemy hearing for 30 s — the stealth tool extraction wants), cloth/rope/planks for repair and bench upgrades. E2+ has no T1 raw and no herbs, so potions and wards must come from survival runs or the vendor at a steep price.
- **Extraction → Survival**: crystals (element change), form stones, gear, keys. S2 has almost no arcane drops; its nights are tuned assuming a 2-form weapon and one piece of uncommon gear — so you *want* an E1/E2 haul before an S2 attempt.
- Both produce **gold** (E more) and **scrap** (S more). Both sinks (§4) accept either.

### Unlock/gating
- `save_data.unlocks = {tiers: ["E1","S1"], bench_levels: {...}}`. A sigil is consumed on the map board to add a tier. Gating is per-player; the host's unlocks decide what the party can open (any member can join a tier they haven't unlocked — carrying friends is a feature).
- Map board replaces the three `expedition_door` instances in `hub_main.tscn` with a single board that opens a UI: style tabs → tier cards (locked cards show the requirement) → launches the existing `begin_kit_selection(id)` flow unchanged.

---

## 3. Combat & AI redesign

### Target feel numbers
Player stays at 1000 HP. Everything below assumes the dodge roll exists; do not re-tune bullets before it does.

| Metric | Target | Today |
|---|---|---|
| Player move / roll speed | 1000 / 2500 for 0.35 s (≈875 u travelled) | 1000 / none |
| Roll i-frames / cooldown | 0.20 s / 0.70 s | — |
| Hurt i-frames after any hit | 0.40 s (player only) | 0 |
| Enemy basic bullet speed | 700-1100 (below roll, around walk) | 1250-1350 |
| Enemy per-hit damage (basic) | 60-120 (6-12% HP) | 15-50 |
| Enemy per-hit damage (heavy, telegraphed ≥0.6 s) | 180-220 (≤22% HP) | 300 sniper (×1.5 on advantage = 450) |
| Hard cap on any single hit | 250 before Defense, and never from off-screen | — |
| Player TTK vs fodder (triangle) | 0.4-0.7 s (1-2 basic hits) | 1.2 s |
| Player TTK vs mid (circle/hexagon) | 1.5-2 s | 2.4 s |
| Player TTK vs heavy (pentagon/square) | 2.5-3.5 s; silver ×1.6 not ×2 | 3-3.7 s; silver ×2 |
| Time-to-death, 1 standard pack (3-4 enemies) | unskilled standing still ≈ 10 s; skilled rolling ≈ 45 s+ | 25-60 s or 3-8 s depending on sniper |
| Advantage bonus | +50 crit rate / +50 crit damage **but shown** (element burst + "EFFECTIVE" tag) | invisible |

Implement TTK via `max_health` in the archetype data: triangle 330→150, circle 650→450, pentagon 1000→800, square 800→700. Player basic DPS stays ≈271.

### Player verbs (new)
1. **Dodge roll** (Space; `jump` is already bound in `project.godot`; `has_dash` exists at `player.gd:214`). Direction = movement input, else aim. Cancels nothing: a weave in progress survives a roll — rolling mid-weave *is* the skill ceiling.
2. **Hurt i-frames** 0.4 s via `hurtbox.is_invincible` + a flicker.
3. **Weave** (spell input, see below).
4. Later (Phase 3): **Blank rune** — a carried consumable (crafted/looted) used from a quick slot: a 0.3 s ring that deletes enemy bullets in a 400 u radius. Cheap because projectiles are local on every peer: broadcast a `clear_bullets(pos, r)` room RPC.

### Spells as stratagems (designer decision, 2026-11-05)
The designer is modelling spells on **Helldivers 2 stratagems**: the multi-tap code input is intentional, spells are meant to be *big and powerful*, and **must not be spammable**. So the job is not to make casting cheaper; it's to make each cast **worth the commitment** and to make combat fun *between* casts.

**Input (keep as-is, small fidelity tweaks):**
- Keep the full code: element prefix + form suffix (3-4 taps). The length is the cost. Codes stay per-element so a 2-element loadout means memorising more codes, like a stratagem loadout.
- **Calling in = slowed walk, not a root** (Helldivers lets you walk while inputting but not sprint or shoot): while the mode is held, move at ~40% speed, no basic fire, no roll. Today's mode-1 friction branch (`player.gd:2292-2298`, `:2743`) becomes a speed cap. Tunable; set to 0% to keep today's full root.
- A completed code is "armed" and delivered with the next LMB (as today). Getting hit while inputting does **not** cancel the code (Helldivers doesn't either), but a wrong tap resets it.
- Feedback: per-tap tick (pitch rising), code-complete chime + the spell icon lighting up on the HUD, wrong-tap buzz + red flash. The HUD spell list (`ui/spell_list_ui.gd`) becomes a **stratagem panel**: icon, code arrows, live-highlighted matched taps, and a cooldown sweep.

**Gating = cooldowns, not a mana pool you spam from:**
- Each form gets its own cooldown (starting values): bolt 12 s, cone 15 s, ball 20 s, burst 25 s, beam 30 s, rain 45 s. Cooldown is per spell, so a loadout of 3 spells gives ~3 big moments per fight, not 7 in a row.
- **Mana stays as a per-run resource, re-tuned so it's scarce:** cost ≈ 30-40% of the bar per cast and *no passive regen during a run* (regen only in the hub). Mana crystals / mana_eel / refined crystals become meaningful loot you carry in. Recommend both gates (cooldown = can't spam in a fight; mana = can't spam across a run). Open decision 1.
- Cooldowns sit with the caster (client-predicted like casting today) and are mirrored on the server for the RPC check.

**Make every cast hit like a stratagem:**
- Damage ×4-8 today's multipliers (basic ≈ 95; a bolt should one-shot fodder and take ~40% of a heavy; a rain/ball should clear a pack).
- Every spell gets a **delivery moment**: a brief world telegraph (marker / beam line / falling rune) then impact with big shake, hitstop, knockback, element-coloured burst and a sound layer. Rain becomes a "call-down" you throw to a spot (like an orbital): a 1 s marker then the strike.
- **Utility, not just damage**: some forms clear enemy bullets in their area (burst), some stagger/knock down (ball), some leave a zone (rain puddle). Stratagems are tools for specific problems.
- Element still matters: hitting a weak element doubles knockdown/stagger and shows "EFFECTIVE".

**Combat that's fun without spells (the 90% of the fight):**
1. **Dodge roll + hurt i-frames** (1.1). The core skill verb.
2. **Weapons that play differently on basic attack** (new, Phase 1): wand = fast low-damage stream; orb = slower heavy shot with slight pierce; tome = 3-shot spread. Weapon choice is the moment-to-moment build; spells are the loadout's ultimates. Data on `SpellData.WEAPONS`.
3. **Charged basic / alt-fire**: hold LMB on a full bar to charge a stronger shot (orb), or a short burst (wand). Cheap extra depth, no mana.
4. **Melee shove** (F or middle-mouse): a short-range push that knocks enemies back, cancels a rusher's dash, 3 s cooldown. Hotline Miami's up-close option.
5. **Environment**: explosive/elemental barrels and destructible cover from the existing *Destructible Objects* pack (`assets/art/pixel_quest/`); knockback into walls deals bonus damage.
6. **The "blank"** becomes a consumable (a ward/rune you carry, crafted or looted) rather than a spell, so it doesn't compete with stratagem input.
7. Kill feedback (shake, hitstop, shatter, sound) and readable, dodgeable enemy patterns (§3 telegraphs) make basic fighting satisfying on its own.

### Weapon roster (designer decision, 2026-11-11)

Seven weapons. Each can hold **3 forms**, and each form appears on **exactly 3 weapons** (7 x 3 = 21 slots). This is the capability list (`SpellData.EQUIPPABLE_WEAPONS[...]["forms"]`); actual forms are attached with Form Stones at the workbench.

| Weapon | Forms | In code? |
|---|---|---|
| Tome | Ball, Rain, Beam | yes |
| Wand | Bolt, Ball, Cone | yes |
| Staff | Bolt, Beam, Wave | no |
| Orb | Bolt, Rain, Burst | yes |
| Lantern | Wave, Rain, Cone | no |
| Instrument | Cone, Beam, Burst | no |
| Totem | Ball, Wave, Burst | no |

Form coverage: Ball (Tome, Wand, Totem), Rain (Tome, Orb, Lantern), Beam (Tome, Staff, Instrument), Bolt (Wand, Staff, Orb), Cone (Wand, Lantern, Instrument), Wave (Staff, Lantern, Totem), Burst (Orb, Instrument, Totem).

The assignment is a Fano plane: **every pair of weapons shares exactly one form**, so no two weapons are near-duplicates. Keep this property when adding the next 7 forms.

- **Wave** is a new form; it does not exist in `SpellData.FORMS` yet (needs its projectile + Form Stone item).
- Each weapon also needs its own **basic attack profile** (`basic_*` keys in the weapon stats table), so weapon choice is the moment-to-moment feel. Tome = 3-shot spread, Orb = heavy single shot, Wand = fast stream; Staff/Lantern/Instrument/Totem still need one.
- **Later:** 7 more forms, following the same rule (3 per weapon, each on 3 weapons).

### Enemy role roster
Keep the four shapes, give each a *movement* identity. Add two. All of this lives in `EnemyDef` Resources (§5), not in `enemy.gd` consts.

| Shape | Role | Movement identity | Attack | Telegraph | Weak to tactic |
|---|---|---|---|---|---|
| **Triangle** | Rusher / swarm | Fast (1100), comes in packs of 4-6, *charges*: 0.3 s wind-up then a 1600-speed dash for 0.4 s, contact 80 dmg, then 1 s recover | contact dash; no bullets | body stretches toward you, flashes | roll through the dash; AoE forms |
| **Circle** | Suppressor | Orbits at 900-1100, never stops moving, strafes around cover | stream of 7 slow (800) bullets over 2 s, 40 each | 0.25 s pulse + hum | wait for the stream to end — 2 s recover window |
| **Pentagon** | Bruiser | Slow (550), *advances* toward you, never backs off | 5-pellet fan at 700 speed, 70 each, pellet angles ±8°/±18° so 3 land at 700 range; fires only ≤ 900 | 0.5 s charge: glyph scales up 1.3×, fan ghost lines | kite + burst; it is a damage sponge for AoE |
| **Square** | Sniper / anchor | Holds 1400-1600, repositions after every shot (0.8 s), must be *on-screen* of its target | 1 shot, 200 dmg, 3000 speed, aim locked at wind-up start | **0.7 s laser line** + rising tone; stops moving while winding | roll on the tone; closing to <600 makes it flee instead of fire |
| **Hexagon** (new) | Lobber / area denial | Mid range 1200, slow | rain form: 3 ground circles (r 220) land 0.9 s after being marked, 120 dmg + element puddle 3 s | ground rings appear and fill | step out; it cannot hit you up close |
| **Crescent** (new, E3/S2) | Support | Stays behind packmates | pulses a Shield affix onto 2 allies every 6 s | expanding ring | kill first; element matters (shield takes the crescent's element) |
| **Prism** (guardian) | Boss | Big (body 180), 3 phases, 6000 HP | cycles 3 elements; ring pattern → spiral → aimed fans; spawns 2 triangles per phase | per-phase colour swap, 1 s ring telegraph | matchup swaps — bring two elements |

### Telegraph rules (hard rules, enforced in the FSM)
1. No damage without a **WINDUP** state first. Min 0.25 s (basic), 0.5 s (fans/charges), 0.7 s (anything ≥150 dmg).
2. Wind-up **locks aim** at its start for any shot ≥150 dmg. Reaction beats precision.
3. Every wind-up has three channels: scale/flash on the body glyph (`enemy_body.gd`), a sound, and for lines/areas a world-space shape (laser line, fan ghost, ground ring).
4. An enemy only fires if its target is **inside the target's screen rect** (viewport 3840×2160 at zoom 0.75 → ±2560 × ±1440 around the target). Replace the `cast_range` radius check with a rect check against the target's position. This single rule kills the off-screen sniper.
5. After every attack an explicit **RECOVER** state (0.8-2 s) where the enemy is visibly vulnerable (desaturated, slight shrink). Volley cooldown stops being invisible.

### Bullet-pattern library (data, Phase 3)
`BulletPattern` Resource: `kind` ∈ {aimed, fan, ring, spiral, wave, delayed_sweep, stop_go, bounce}, `count`, `spread_deg`, `speed`, `speed_variance`, `per_pellet_delay`, `stop_after`, `resume_after`, `bounces`. Build on the existing per-pellet offsets RPC (`enemy.gd:1673-1714`), extending the payload with per-pellet `delay` and `speed`. Each `EnemyDef` references one base pattern; affixes may swap it (Splitter → ring on death).

### Attack tokens / aggression budget
Per player, the room's `EnemyDirector` (one node per room, server-only) hands out N **attack tokens** (E1: 2, E2: 3, S night: +1). An enemy must hold a token to enter WINDUP; without one it repositions, flanks or suppresses with a non-damaging feint (circle "fake-pulses"). Elites cost 2 tokens, guardians ignore tokens. Tokens are released on RECOVER. Density of *enemies* can then go up for spectacle without the damage intake going up linearly — this is the difficulty dial map tiers turn, and it is how Doom/EtG make 12 enemies feel fair.

### Affixes (silver and gold)
Visible as 1-2 glyph marks on the border. `Fast` (+30% move, pattern speed +20%), `Shielded` (a coloured ring of *one element* absorbs 400; only the element that beats it breaks it in one hit — wheel made tactical), `Splitter` (dies into 2 bronze triangles), `Vampiric` (heals 20% of damage dealt), `Burning trail` (leaves element puddles while moving), `Teleporter` (blinks 600 u every 5 s with a 0.4 s shimmer), `Warder` (pulses a 150 dmg ring at r 300 every 4 s — anti-melee). Silver gets 1, gold gets 2, from the map's affix pool.

### Bosses / guardians
One guardian (Prism) first. It appears (a) as the final extraction wave on E2+ keyed portals, (b) at the night-before-extraction on S2, (c) as the E3 exit. Phases are three `EnemyDef`s chained by a `GuardianBrain`. Loot: guaranteed sigil + gold-table roll.

### AI architecture
- **`EnemyDef` Resource** (`scenes/enemies/defs/*.tres`): stats, role script (`EnemyRole` subclass), base pattern, perception numbers, telegraph timings, affix pool, loot table key, body glyph. The `ARCHETYPES` and `TIERS` dicts in `enemy.gd:71-125` migrate here; `enemy_spawner.gd` weights become `MapDef.roster: {def: weight}`.
- **`EnemyBrain` FSM** in a child node with `match state:` over `ASLEEP, IDLE, INVESTIGATE, ENGAGE, REPOSITION, WINDUP, ATTACK, RECOVER, FLEE, DEAD`. `_physics_process` in `enemy.gd:702-847` becomes a dispatcher. Role scripts override `engage()` (how to move while holding a token) and `attack()`; everything else is shared.
- **`Perception` component**: LOS + hearing + aggro, time-sliced at 10 Hz with per-enemy stagger; `_ally_in_firing_lane` scoped to the room's enemy list (cached on the `EnemyDirector`).
- **`EnemyDirector`** (server-only per room): token pool, cached enemy list, wave telegraphs, noise events. This is also where player gunfire noise enters (`hear_world_noise` already exists on enemies — call it from the spell-spawn RPC with a per-form radius: basic 900, ball/burst 1600).
- Keep: nav/steering, the deterministic seeded spawn, room-scoped RPCs, position sync.

### Friendly fire — decision
**Off between players.** Add a faction check in `Hitbox.can_hit` (`scenes/characters/hitbox.gd`): a player-owned hitbox never hits a player hurtbox. Enemy-on-enemy stays as-is (AI avoids it; accidental clips are fine and fun). Rationale: 4000-speed basic shots in 3-player co-op at 0.75 zoom are unreadable, and nothing in the design wants the tension. Revisit only if a "chaos" affix wants it.

---

## 4. Economy & progression

### Material taxonomy (tags + tiers on every `ItemData.ITEMS` def)
Add `"mat_tier": 1-4` and `"tags": [...]` to every def; loot groups and `MapDef.resource_whitelist` filter by tag; recipes consume by tag where sensible (`"@fuel"` like the existing `"@element_crystal"` wildcard).

| Tier | Name | Examples | Source | Tags |
|---|---|---|---|---|
| T1 | Raw | wood, stone, fiber, flint, berries, raw fish (existing minnow/bass), raw meat, herbs, water_flask, cloth | S1 nodes, E1 sparse | `raw`, `food`, `fuel`, `fiber`, `metal` |
| T2 | Processed | planks, rope, bandage, cooked meal, ration, torch, ward, campfire kit, bedroll | field/hub crafting from T1 | `camp`, `food`, `consumable` |
| T3 | Arcane | element dusts (7, finally used), crystals, form stones, mana_dust, pure_mana_shard, scrap, components (from recycling) | E1-E2 enemies/containers, recycling | `arcane`, `component` |
| T4 | Relic | Tier Sigils, Survivor's Mark, keys, relic shards/cores, golden_koi/river_pearl (reclassified as keystone junk) | keyed rooms, guardians, S2 nights, fishing | `keystone`, `key`, `relic` |

Every material gets at least one recipe use (the 7 dusts: `dust ×3 + mana_dust → crystal` of that element; `dust + cloth → elemental ward`).

### Sinks (gold and scrap currently have none)
1. **Vendor** (hub NPC/board): buys `junk` and fish at listed value (add `"value"` to defs, shown in tooltips); sells pauper-tier consumables, T1 raw at a premium (so E-only players *can* play survival, expensively), kit-preset slots.
2. **Repair station**: durability back at scrap + gold; rare+ gear also needs a `component`. Replaces the "break and discard" dead end; durability already exists (`player.gd:1299`, `:2396`).
3. **Recycler**: gear/weapons → scrap + a dust of their element + (rare+) a `component`. Junk → scrap. This is the ARC loop and gives bad drops a purpose.
4. **Bench upgrades**: Crafting Bench L1→L3 and Workbench L1→L3 gated by keystone junk (koi, pearls, relic shards) + gold. Unlocks: recipe tiers, 3rd form slot on weapons, stash tab 4, 2nd kit preset, the Recycler itself (L2).
5. **Insurance slot** (optional, E-only): one bag cell marked "insured" for 50 gold before launch — its item survives death. Deliberately tiny.
6. **Kit purchase**: a pauper kit is free; buying a *better* starter (uncommon wand, belt) costs gold — a soft sink for players who hate stash management.

### Kit system & starter-kit stakes
As in §2: Pauper Kit (free, bad), kit presets (saved from stash), tag-based kit requirements per map. Death drops everything carried including rings and the extra slots (bug fix in `_drop_death_bag_and_reset_gear`, `player.gd:2106-2148`). Carried-out loot is yours. Leaving the hub wipes the `run` sub-dict (see §5) so a crash equals death on Extraction; on Survival the host run snapshot can be resumed (Phase 6).

### Gear that changes play
Populate hat/necklace/pants/boots (empty slots exist, `player.gd:202`) and rings with items whose `is_gear` is derived from `equip_slot`. Trait pool additions (rare+ only, so gold tier matters): `bolt_pierce`, `ball_split` (2 smaller balls on detonation), `roll_trail` (element puddle on roll), `weave_free_tap` (first tap of each weave free), `roll_iframes_plus` (+0.1 s), `quiet_boots` (gunfire noise −50%), `night_eyes` (survival night vision −penalty), `second_wind` (once per run auto-revive at 20% — consumes a phoenix_ash from the bag). Numeric stats stay small; traits are the build.

### Survival needs (scoped)
- **Hunger** only at S1 (100 → 0 over ~25 min; below 25 → −25% move speed and no natural mana regen; 0 → 10 HP/s drain). Food: berries (+15), cooked meal (+50), ration (+35, no spoilage). Hunger meter in the HUD only on survival maps.
- **Warmth** added at S2: drains at night outside a campfire radius (800 u); 0 → −30% move + weave taps have a 20% fizzle chance (cold hands — mechanically ties to the identity verb).
- **No thirst, no sanity.** Two meters is the ceiling for a solo project.
- **Day/night**: server-ticked `world_time` (float seconds) broadcast at 1 Hz; `CanvasModulate` lerp + the already-sketched rotating `wall_shadows.gd` offset; night halves vision radius (shader vignette) and doubles enemy hearing radius; night waves use the `exit_portal` wave code moved into `EnemyDirector`.
- **Renewable nodes**: `loot_container` with `respawn_seconds` instead of the per-expedition lock (`Stats.expedition_looted_containers` stays for one-shot containers).
- **Field crafting**: a `portable` recipe subset usable from the bag (no bench); the **campfire** is a placeable (networked via the existing loot-pickup id pattern, `world.gd:779-802`) that provides warmth, cooking and a 10 s "rest" heal.
- **No base building.** A campfire plus a chest placeable is the ceiling.

---

## 5. Tech foundation (do BEFORE expansion)

### Refactors
1. **`MapDef` Resource registry** (`scenes/maps/map_defs/*.tres`, `MapRegistry` autoload or a static loader): `id, style, tier, display_name, scenes: {room_key: path}, spawn_key, duration_sec, day_length_sec/night_fraction (survival), roster: {EnemyDef: weight}, tier_mix: {bronze,silver,gold}, affix_pool, tokens_per_player, pack_mult, resource_whitelist_tags, loot_tier_shift, container_type_weights, wave_plan, kit_requirements, unlock_requirement, hazards`. Replaces `ZONE_SCENES`, `EXPEDITION_TARGETS` (`world.gd:8-50`) and the 16-slot `LOCATION_SLOTS` (`world_rooms.gd:100-113`) with a dynamic slot allocator keyed by loaded room. Validate every scene path at boot. `broadcast_expedition_seed` → `broadcast_expedition_config(seed, map_id)`; `Stats.current_map` holds the def; all spawners read it.
2. **`RoomNet` utility node** in each room: `room_key`, `occupants()`, `rpc_room(method, args)`. Deduplicates the scoping code copy-pasted in `enemy.gd:1651-1683`, `exit_portal.gd:189-203/351-374`, `loot_container.gd`.
3. **Room join snapshot**: when a peer reports room-ready, the server sends (a) `active_pickups` for that room (key piles by `room_key`), (b) the dynamic enemy roster (wave/night spawns with server-issued unique names `dyn_<counter>`), (c) portal states, (d) campfires/placeables later. Fixes the invisible-death-bag bug and the late-joiner wave crash; prerequisite for 2-hour runs and drop-in.
4. **Persistence v2**: integer `schema_version` + ordered migration functions; atomic write (temp + rename); fix the backup ring index (`save_and_load.gd:9,103-106`); numeric version compare; `overflow`/`materials` in defaults, drop `eggs`; **`save_data.run = {items, equipment, weapons, active_slot, quick_slots}` sub-dict** so the leave-hub wipe is `run = {}` and death clears the same dict — the allowlist trap goes away.
5. **`enemy.gd` split** (1826 lines): `EnemyDef` Resources + `EnemyBrain` FSM + `Perception` + `EnemyDirector` per room (§3). Delete the dormant cast-sequence code (~150 lines listed in the combat audit).
6. **`player.gd` split** (2770 lines) into child components, in this order of payoff: `PlayerLoadout` (inventory/equipment/weapons/quick slots/persistence/death penalty — needed for the `run` sub-dict), `PlayerCombat` (weave input, casting, prediction — needed for the input rework), `PlayerHealth` (hurt/downed/revive/i-frames — needed for the roll), `PlayerMovement` (roll lives here), `PlayerStash` (hub-only), leave net interpolation where it is.
7. **Perf budget** (before survival spawns hundreds): LOS/acquisition time-sliced to 10 Hz; firing-lane check scoped to room; prune hurtbox-keyed dicts on target loss; parent projectiles to their room; cache `world` and `room_key` in `_ready` (≈50 `get_first_node_in_group("world")` sites); enemy sync static props → `ON_CHANGE`; threaded room load (`ResourceLoader.load_threaded_request`) behind the transition screen. Target: 80 live enemies in one room at 60 fps on the host.
8. **Shared damage resolution**: one static `Combat.resolve_hit(hitbox, defender_stats)` replacing the copy in `player.gd:1902-1928` and `enemy.gd:1724-1743`.

### Bug list to fix first (Phase 0, all cheap)
| # | Bug | File |
|---|---|---|
| 1 | Nothing committed since Jul 9; stray `~*.TMP` DLLs; `.gitignore` untracked | repo |
| 2 | Projectiles freed when leaving the *host's* screen → lost damage for distant clients | `scenes/spells/projectile.gd:106-108` |
| 3 | Loot piles never re-sent to peers entering a room (death bags invisible) | `scenes/world_loot.gd:277-280`, `scenes/world_rooms.gd:30,140` |
| 4 | `quick_slots` missing from leave-hub wipe (survive a crash) | `scenes/world.gd:429-440` |
| 5 | Rings/extra slots survive death | `scenes/characters/player.gd:2106-2148` |
| 6 | Death bag fixed 6×6 silently drops overflow; loot piles silently drop | `scenes/world_loot.gd:75,99,266-272` |
| 7 | Village has no exit portal (its only portal is the arrival point) | `scenes/levels/village/village_main.tscn` |
| 8 | `dungeon_room_2.tscn` doesn't exist; `village/room_1` door targets a missing spawn; absolute `Vector2(100,100)` fallback ignores offset | `world.gd:15,19`, `world_rooms.gd:257-262` |
| 9 | Dungeon unreachable from hub | `hub_main.tscn` |
| 10 | Friendly fire between players | `scenes/characters/hitbox.gd:28`, `scenes/spells/projectile.tscn:15` |
| 11 | Server doesn't validate location changes (free extraction) | `world.gd:330-337` |
| 12 | Container seed ignores room key (same rolls across maps) | `scenes/items/container_spawner.gd:29` |
| 13 | Host disconnect mid-run wipes every client's loadout | `world.gd:176, 429-441` |
| 14 | Gear tooltip omits `mana`; `get_def()` silently returns scrap for typos | `scenes/inventory/item_data.gd:348,1069` |
| 15 | `delete_before_export/*` and `_snapshots/` ship in exports; lobby password in plaintext lobby data | `export_presets.cfg`, `singletons/steam.gd:177` |

---

## 6. Phased roadmap

Session = one focused AI coding session (a few hours). "Headless" = verifiable with the parse-check command in the verification-workflow memory; "Live" = needs the designer to play (1 or 2 peers as noted). Every phase ends in a playable build.

### Phase 0 — Safety (1-2 sessions)
**Goal:** nothing can be lost; the core loop can't silently cheat the player.
| Task | Files | Verify |
|---|---|---|
| 0.1 Add `.gitignore`/`.gitattributes`/`.editorconfig`, delete `~*.TMP` DLLs, decide `_snapshots/` (commit it — it is the AI revert reference), commit everything on `main`, push to a remote | repo | headless |
| 0.2 Projectile: remove screen-exit free; rely on `max_distance` + lifetime | `projectile.gd` | headless + live 2p |
| 0.3 Loot re-sync: key `active_pickups` by `room_key`, send the room's piles on room-ready; don't clear hub piles on launch | `world_loot.gd`, `world_rooms.gd`, `world.gd` | live 2p (drop a bag, teammate walks in) |
| 0.4 Persistence trio: add `quick_slots` to the wipe; drop + clear `equipped_gear` on death; death bag grows to fit (spill into a second bag), log pile overflow | `world.gd`, `player.gd`, `world_loot.gd` | headless + live 1p |
| 0.5 Content: add 2 more portals to `village_main` under `doors/portals`; hub door to `dungeon/main`; remove both `room_2` entries and the dev button that targets them; make spawn fallback offset-aware | `village_main.tscn`, `hub_main.tscn`, `world.gd`, `world.tscn`, `world_rooms.gd` | live 1p |
| 0.6 Friendly fire off between players (faction check in `Hitbox.can_hit`) | `hitbox.gd` | live 2p |
| 0.7 Server validates `server_request_location_change` against party state + a door/portal within 400 u; guard dev buttons behind `OS.is_debug_build()` | `world.gd` | headless |
| 0.8 Host-disconnect policy: on `server_disconnected` during EXPEDITION, restore the pre-run save backup (not the player's fault) | `world.gd`, `save_and_load.gd` | live 2p (kill host) |

**Acceptance:** `git log` shows the commit; a 2-peer run where one player dies far from the other and the other recovers the bag; alt-F4 mid-run loses potions; village can be exited.
**Dependencies:** none.

### Phase 1 — "Make it fun" vertical slice (4-6 sessions)
**Goal:** the designer plays E1 (village) and says "this feels good" before any refactor. Everything here is additive and cheap.
| Task | Files | Verify |
|---|---|---|
| 1.1 **Dodge roll** on Space: 0.35 s, 2.5× speed, 0.2 s i-frames, 0.7 s cooldown, short brake; replicate a `rolling` anim flag; **hurt i-frames** 0.4 s with flicker | `player.gd` (movement + `_on_hurtbox_hurt`), `player.tscn` | live 1p |
| 1.2 **Hit-stack**: white flash (modulate tween 0.08 s) on enemy and player; knockback impulse on enemies (150 u); trauma-based camera shake on `player_camera`; 40 ms hitstop on kill/crit by freezing only the enemy's visual (not `time_scale`); low-HP vignette | `enemy.gd`, `player.gd`, `player_camera.tscn` (+ new `camera_shake.gd`) | live 1p |
| 1.3 **Enemy death + impact**: 0.2 s scale-pop + `CPUParticles2D` shatter in element colour; impact puff on projectile free; muzzle flash at spawn offset | `enemy.gd:131-155`, `projectile.gd`, new `scenes/effects/*` | live 1p |
| 1.4 **Audio pass** through `Sounds` autoload: cast (pitch per form), hit, enemy die, player hurt, low HP, roll, tap/complete/fizzle, loot drop, UI click, one hub loop + one dungeon loop. Free packs (Kenney, sfxr). Designer supplies/approves files | `singletons/sounds.gd`, `assets/audio/` | live 1p |
| 1.5 **Bullet legibility**: enemy bullets drawn as dark-rimmed diamonds with a bright core; player shots as elongated streaks; keyed on caster type in `projectile.gd _draw` | `projectile.gd` | live 1p |
| 1.6 **Telegraphs v0** (no FSM yet): a `windup_sec` per archetype honoured before `fire_spell`: square 0.7 s with a `Line2D` laser + rising tone, aim locked; pentagon 0.5 s scale-up; circle/triangle 0.25 s flash. On-screen-rect firing rule replaces `cast_range`. A visible RECOVER tint during burst cooldown | `enemy.gd`, `enemy_body.gd` | live 1p |
| 1.7 **Numbers pass**: bullet speeds 700-1100; damage per §3 table; square 1 shot of 200; pentagon pellet angles ±8/±18; HP cuts; silver ×1.6; advantage crits shown as an "EFFECTIVE" tag + element burst | `enemy.gd ARCHETYPES/TIERS`, `damage_number.gd` | live 1p |
| 1.8 **Stratagem pass**: keep the full code input; call-in = 40% slowed walk (no fire/roll) instead of root; per-form cooldowns + scarce mana (no in-run regen); damage ×4-8 with delivery telegraph + impact juice; rain as a thrown call-down; stratagem HUD panel with cooldown sweep; tap/complete/wrong-tap feedback | `spell_data.gd FORMS`, `player.gd:2281-2310, 2374-2414, 2716-2760`, `spell_list_ui.gd`, `rain_projectile.gd` | live 1p |
| 1.11 **Weapon identity on basic attack**: wand stream / orb heavy+pierce / tome 3-spread; charged basic on hold | `spell_data.gd WEAPONS`, `player.gd attack_check`, `projectile.gd` | live 1p |
| 1.12 **Melee shove** (knockback, cancels dashes, 3 s cooldown) | `player.gd`, new input action | live 1p |
| 1.9 **Camera**: look-ahead 20% toward aim, position smoothing | `player_camera.tscn`, `player.gd` | live 1p |
| 1.10 **Play Solo** button (hosts a silent private lobby) + first-run controls overlay | `main_menu.gd/.tscn`, new `ui/controls_overlay.tscn` | live 1p |

**Acceptance (designer playtest, E1 village, solo then 2p):** you can roll through a pentagon fan; the sniper never hits you from off-screen and you can dodge it on the tone; a triangle dies in 1-2 hits with a shatter and a sound; a full fight is fun with basic attacks + roll alone, and each spell feels like calling in an orbital (you pick the moment, it changes the fight, you can't fire it again for a while); you die in ~10 s if you stand still in a pack and survive 45 s+ rolling. "Too easy / too hard" is replaced by "I died because I rolled late."
**Dependencies:** Phase 0.

### Phase 2 — Foundation (6-8 sessions)
**Goal:** the data model and code structure that map styles, tiers and long runs need. No new player-facing features, but every task leaves the game playable.
| Task | Files | Verify |
|---|---|---|
| 2.1 `MapDef` Resource + registry + dynamic room-slot allocator; `broadcast_expedition_config`; two `.tres` (E1 village, E2 dungeon) reproducing today's behaviour | new `scenes/maps/`, `world.gd`, `world_rooms.gd`, `world_expeditions.gd`, `stats.gd` | headless + live 1p (both maps load) |
| 2.2 Spawners read `Stats.current_map`: roster weights, tier mix, pack mult, container weights, wave plan; room key in container seed | `enemy_spawner.gd`, `container_spawner.gd`, `exit_portal.gd` | headless + live 2p (determinism) |
| 2.3 `RoomNet` node; migrate the three copy-pasted dispatchers | `scenes/net/room_net.gd`, `enemy.gd`, `exit_portal.gd`, `loot_container.gd` | live 2p |
| 2.4 Room join snapshot: dynamic enemy roster with server-issued names + portal state on room-ready (loot already done in 0.3) | `world_rooms.gd`, `world.gd`, `exit_portal.gd`, `enemy_spawner.gd` | live 2p (join a room mid-wave) |
| 2.5 Persistence v2: `run` sub-dict, schema version + migrations, atomic write, backup ring fix, numeric version compare, defaults cleanup | `stats.gd`, `save_and_load.gd`, `world.gd`, `player.gd` | headless + a tiny headless save round-trip test scene |
| 2.6 `EnemyDef` Resources + `EnemyBrain` FSM + `Perception` + `EnemyDirector` (tokens stubbed at ∞); delete dormant cast code; shared `Combat.resolve_hit` | `scenes/enemies/*`, `spell_data.gd`, `player.gd` | headless + live 1p (behaviour parity with Phase 1) |
| 2.7 `player.gd` split: `PlayerLoadout` first, then `PlayerCombat`, `PlayerHealth`, `PlayerMovement` | `scenes/characters/components/*` | headless + live 2p |
| 2.8 Perf budget items (§5.7) + a headless determinism test (spawn a room with a fixed seed twice, compare names/positions) | `enemy.gd`, `enemy.tscn`, `projectile.gd`, `world_rooms.gd`, new `tests/` | headless + live 1p (80-enemy stress room) |
| 2.9 Hygiene: delete `basic_attack.gd`, `os_hub_*`, `sample_room`, deprecated RPCs, `COUNTDOWN`, Steam leaderboard/UGC leftovers, empty `Events`; export excludes; fix stale comments | various | headless |

**Acceptance:** same feel as Phase 1; 2-peer join-in-progress into a room with wave enemies and loot works; a fixed seed yields identical spawns on both peers; alt-F4 loses exactly the `run` dict.
**Dependencies:** Phase 1 (so the refactor preserves a feel that's already good).

### Phase 3 — Combat depth (5-7 sessions)
**Goal:** enemies have roles, difficulty has a dial, elites are visible.
| Task | Files | Verify |
|---|---|---|
| 3.1 Role scripts: Triangle rusher (dash), Circle orbiter, Pentagon advancer, Square anchor with reposition + flee-under-600 | `scenes/enemies/roles/*.gd`, defs | live 1p |
| 3.2 Hexagon lobber (rain-form ground circles) | new def + role, `rain_projectile.gd` reuse | live 1p |
| 3.3 `BulletPattern` Resources + extended pellet RPC (delay, speed) + 5 patterns | `scenes/enemies/patterns/`, `enemy.gd`, `projectile.gd` | live 2p |
| 3.4 Attack tokens in `EnemyDirector`; `MapDef.tokens_per_player`; non-token behaviours (feint, flank) | `enemy_director.gd`, roles | live 1p (feel E1 at 2 vs 4 tokens) |
| 3.5 Affixes: Fast, Shielded (element ring), Splitter, Vampiric, Burning trail; glyph marks; per-map affix pool | `scenes/enemies/affixes/*.gd`, `enemy_body.gd` | live 1p |
| 3.6 Player gunfire noise → `hear_world_noise`; stealth gear trait `quiet_boots` | `world.gd` spell spawn RPC, `enemy.gd`, `item_data.gd` | live 1p |
| 3.7 Extraction wave rework: telegraph direction marker + sound; peak/valley plan; varied composition; cap noise pull-in; waves spawn via `EnemyDirector` | `exit_portal.gd`, `enemy_director.gd` | live 2p |
| 3.8 Blank rune consumable + room `clear_bullets` RPC | `item_data.gd`, `player.gd use_quick_slot`, `RoomNet` | live 2p |
| 3.9 Prism guardian (3 phases) as E2 keyed-portal final wave | new defs, `guardian_brain.gd` | live 2p |

**Acceptance:** E1 pack of 2 triangles + 1 circle + 1 pentagon is a fun 20-30 s fight; E2 feels distinctly harder through tokens/affixes, not through one-shots; Shielded elites teach the wheel (wrong element = chip, right element = pop).
**Dependencies:** Phase 2 (FSM, defs, director).

### Phase 4 — Modes & tiers (5-6 sessions)
**Goal:** the map board exists; E1/E2 play differently; a raid clock exists.
| Task | Files | Verify |
|---|---|---|
| 4.1 Map board item + UI (style tabs, tier cards, lock reasons) replacing the three expedition doors; `save_data.unlocks` | new `scenes/items/map_board.*`, `ui/map_board_ui.*`, `hub_main.tscn`, `stats.gd` | live 2p |
| 4.2 Raid timer: server clock, HUD countdown, T-5 min storm (portals close except one, enemy tier mix shifts), T-0 = death | `world_expeditions.gd`, new `ui/raid_timer_ui`, `exit_portal.gd` | live 2p |
| 4.3 Kit presets: save/load from stash, tag-based `kit_requirements`, Pauper Kit replaces Starter | `expedition_kit_ui.gd`, `PlayerLoadout`, `item_data.gd` tags | live 1p |
| 4.4 Keyed rooms: a locked door type consuming a `key` item; gold-tier container/enemy mix inside; Tier Sigil I in E1's keyed room | `door.gd`, `container_spawner.gd`, `village_main.tscn`, `dungeon_main.tscn` | live 1p |
| 4.5 Post-run summary screen (extracted value, kills, time, sigils) | new `ui/run_summary.*`, `world_expeditions.gd` | live 1p |
| 4.6 E2 `MapDef` tuned per §2 table; darkness pockets hazard | `dungeon` def, `CanvasModulate` zones | live 2p |
| 4.7 S1 skeleton: a survival-style `MapDef` on village with the day clock, portal sealed at night, night waves — **no needs yet** | `world_time` in `world.gd`, `wall_shadows.gd`, `CanvasModulate`, `enemy_director.gd` | live 2p |

**Acceptance:** a new player opens the board, sees E1 and S1 unlocked, E2 locked "needs Tier Sigil I"; an E1 run under the 25-min clock ends in a storm extraction; carrying out the sigil unlocks E2.
**Dependencies:** Phases 2-3.

### Phase 5 — Economy (5-7 sessions)
| Task | Files | Verify |
|---|---|---|
| 5.1 Tags + `mat_tier` + `value` on every def; T1/T2 items added; dust recipes; `get_def()` warns | `item_data.gd` | headless |
| 5.2 Vendor (buy/sell UI, hub NPC) | new `scenes/items/vendor.*`, `ui/vendor_ui.*` | live 1p |
| 5.3 Repair station + Recycler (gear → scrap/dust/component) | new items + UI, `PlayerLoadout` | live 1p |
| 5.4 Bench levels + keystone gating + unlock payoffs (recipe tiers, 3rd form slot, stash tab, kit slot) | `crafting_bench.gd`, `weapon_workbench.gd`, `crafting_ui.gd`, `workbench_ui.gd`, `stats.gd` | live 1p |
| 5.5 Gear for hat/necklace/pants/boots/rings; `is_gear` from `equip_slot`; verb-changing traits (`bolt_pierce`, `ball_split`, `roll_trail`, `weave_free_tap`, `second_wind`) | `item_data.gd`, `PlayerCombat`, `PlayerMovement`, projectile scripts | live 1p |
| 5.6 Loot path unification: fishing + v1 containers → v3 tables; delete `roll_pool_loot`/`spawn_pool_loot`/`ENEMY_LOOT_POOLS`/enemy `loot_pool` exports; `MapDef.loot_tier_shift` + whitelist in `roll_loot_table` context | `world_loot.gd`, `item_data.gd`, `fishing_spot.gd`, `loot_container.gd` | headless + live 1p |
| 5.7 Place fishing spots and more containers in village/dungeon; cemetery retired (or kept as hub fishing pond) | level scenes | live 1p |
| 5.8 Insurance slot (optional) | `expedition_kit_ui.gd`, `PlayerLoadout` | live 1p |

**Acceptance:** gold goes down; a bad rare drop becomes a component; after 3-4 E1/E2 runs the bench hits L2 and the player has one build-defining trait equipped.
**Dependencies:** Phase 4 (map tiers feed the whitelist).

### Phase 6 — Survival (7-10 sessions)
| Task | Files | Verify |
|---|---|---|
| 6.1 Hunger meter + food effects + HUD (survival maps only) | `PlayerHealth` (or new `PlayerNeeds`), `item_data.gd`, `ui/needs_ui` | live 1p |
| 6.2 Renewable nodes (`respawn_seconds`), T1 harvesting with tool gating (axe → wood, pick → stone) | `loot_container.gd`, `container_spawner.gd`, items | live 2p |
| 6.3 Field crafting (portable recipe subset from the bag) | `crafting_ui.gd`, `PlayerLoadout` | live 1p |
| 6.4 Campfire placeable (warmth radius, cook, rest heal) + placeable sync via the pickup-id pattern + join snapshot | new `scenes/items/campfire.*`, `world_loot.gd`-style registry, `RoomNet` | live 2p |
| 6.5 Night hazards: vision vignette, hearing ×2, night-wave scaling by day index | `enemy_director.gd`, `Perception`, shader | live 2p |
| 6.6 Host-owned run snapshot + resume: seed, map, room state, piles, portal/campfire state, players' `run` dicts, `world_time`; "Resume run" on the map board; rejoin path for a dropped client | `world_expeditions.gd`, `stats.gd`, `save_and_load.gd`, `world.gd` | live 2p (quit at day 3, resume) |
| 6.7 S2 `MapDef` + warmth + Survivor's Mark recipe + kit gate (≥3 `camp`) + Prism on the night before extraction | defs, items, `PlayerNeeds` | live 2p |
| 6.8 Survival "hunt" elite pack (tracks loudest player at night) | `enemy_director.gd` | live 2p |

**Acceptance:** a 75-min S1 session with 2 players where the second night is scary, food matters by day 3, and quitting at day 3 resumes at day 3; S2 refuses a kit without camp items.
**Dependencies:** Phases 2, 4, 5.

### Phase 7 — Content & polish (ongoing)
E3 and S3 defs + scenes; more guardians; enemy art polish (glow/outline shaders on the vector glyphs so they match the painted player); rarity drop flourish (beam + sound by tier); training corridor in the hub with dummies; procedural room-graph stitching prototype (only if hand-authored maps run dry); controller pass; Linux/macOS export encryption.

---

## 7. Open decisions for the designer

1. **Spells = Helldivers stratagems (DECIDED by designer): full code input stays, big and powerful, not spammable.** Still open: gate by cooldowns only, or cooldowns + scarce no-regen mana? Default: both. Also: walk speed while inputting (default 40%; 0% = today's root).
2. **Friendly fire.** Default: off between players. (On would need slower player bullets and a visual, and it fights 3-player co-op at 0.75 zoom.)
3. **8-way movement snapping (`snap_to_8_directions`).** It suits the hand-drawn legs but caps precision in a bullet game. Default: keep 8-way for *animation*, use raw analog for *velocity*.
4. **Crash = death on Survival?** Default: no — host run snapshot with resume (Phase 6.6); Extraction keeps crash-equals-death.
5. **Enemy art direction.** Default: commit to polished vector geometry (glow, outline, shatter) rather than sprites — it is the identity and it is cheap. The player sprite style then needs a matching outline/glow treatment, not a repaint.
6. **Pauper kit: free-and-bad (default) vs costs gold.** Free keeps the game playable after a wipe; bad keeps stakes.
7. **Starting tiers.** Default: ship E1 + S1 first, E2 second, S2 fourth. If you'd rather lead with survival, swap Phases 4 and 6 — the foundation (Phase 2) supports either order.
8. **The "blank" (bullet clear) — in or out?** Default: in, as a carried consumable rune (crafted/looted), Phase 3, so it doesn't compete with stratagem input.
9. **Hunger only vs hunger + warmth.** Default: hunger at S1, warmth at S2. Never thirst.
10. **Trust model.** Default: friends-only co-op, no anti-cheat, server validates only what causes *desync* (location changes), not what enables cheating.

---

## 8. Things to cut or defer (scope discipline)

**Cut (don't build):** thirst, sanity, seasons; base building beyond campfire + one chest; host migration (restore-backup policy instead); anti-cheat / server-authoritative inventory; weight/encumbrance; PvP; Discord rich presence polish; Steam leaderboards/UGC leftovers (delete); the 14-form expansion (6 forms + verb-changing gear is plenty); epic/legendary/mythic rarities until gold tier is live and rare is *earned* (keep the enum, zero weights); hub `room_1`/`room_2` and `os_hub_*` scenes (delete the latter, decide the former); the cemetery as an expedition map.

**Defer (after Phase 6):** procedural generation (the hand-authored village + dungeon with per-`MapDef` profiles give 4 distinct maps from 2 scenes); E3/S3; more than one guardian; Linux/macOS export; a shared/networked stash; quests/contracts; multiple hub NPCs (one vendor board is enough).

**Rules of thumb for the solo dev:** no phase longer than ~8 sessions without a playtest; nothing enters `enemy.gd`/`player.gd` directly after Phase 2 (components and Resources only); every new per-run save key goes in `save_data.run`; every per-map number goes in a `MapDef`; every enemy number goes in an `EnemyDef`; commit after every session.

---

## Progress log

*Every item below passed the headless parse check; none has been live-playtested yet.*

**Phase 0 — Safety: done** (ca6d00d … 56255f8). 0.7 (server-validated location changes) and the plaintext lobby password are deferred to Phase 2.

**Phase 1 — Make it fun: done** (668e3c6 … c82d213)
- Dodge roll (Space) with i-frames + post-hit i-frames.
- Juice: hit flash, enemy knockback, death shatter, impact puffs, trauma screen shake (respects the Screen Shake setting), aim look-ahead.
- Enemy bullets drawn as dark-rimmed diamonds; player shots as streaks.
- Telegraphs: wind-up before every burst (body swell; sniper laser + locked aim + stands still), recover window after, enemies only fire from inside your screen.
- Numbers pass (see §3 table; bullet speeds kept ≥ walk speed per designer).
- Stratagems: per-form cooldowns, 4–15× damage, no basic fire while a spell mode is held, code tap/armed/fizzle feedback, burst clears enemy bullets, rain is a 1 s call-down.
- Weapon basics: wand stream / orb heavy / tome 3-spread.
- Melee shove (F), procedural placeholder SFX (`tools/gen_sfx.py`), Play Solo, controls card (F1), EFFECTIVE element-advantage numbers.
- Skipped: charged basic (fights hold-to-autofire; needs a design call).

**Phase 2 — Foundation: partly done**
- Done: hygiene pass, `MapDef` registry (`scenes/maps/`) read by the enemy + container spawners, save hardening (atomic writes, backup ring, numeric versions), firing-lane perf, portal-wave name clash + late-joiner catch-up.
- Deferred until Phase 1 is playtested (refactoring untested behaviour compounds risk): RoomNet, EnemyDef/FSM split, player.gd split, LOS time-slicing, ON_CHANGE sync.

**Pulled forward from Phases 3–4**
- Attack tokens (E1 2 / E2 3 per player).
- Hexagon lobber (E2 only).
- Raid clock (E1 25 min, E2 30 min; death at 0).
- Map board on the expedition doors; E2 unlocks after one extraction from E1.
- Pauper Kit replaces the free Starter Kit (no backpack, 1 potion, bottom-band common weapon).
- Elite affixes (fast / armored / shielded / warder), drawn as glyph marks; pools per MapDef.
- Wave threat pings (edge arrows) + waves drawn from the map roster.
- Post-run summary card (extracted/died, map, time, kills, stacks carried).
- **S1 Homestead** survival skeleton: 15-min days (last third night), night tint, night hunts, portals sealed at night and before day 3, hunger (fish are food; survival loot adds food).

- Independent review of all the above found 9 issues (1 high: host returning to hub desynced map tuning); all fixed in fe5461a.
- Survival foraging: berry bushes + renewable containers (S1 regrows bushes/mining nodes every 150 s); village gets 10 more container markers.
- **Hub vendor** (gold finally spent): sell fish/junk/dusts/crystals/gear, buy potions/food/basic gear, and repair everything.

- **Crafting bench Lv1–3** (keystone junk: Cracked Crucible from silver sources, Runed Anvil from gold); dust → crystal recipes.
- Second independent review: 8 more issues fixed in 3d34ef4.

**Next once the designer has playtested:** tune from feedback, then the deferred Phase 2 refactors (EnemyDef/FSM, player.gd split), then Phase 5 economy (vendor, repair, recycler, bench levels) and the rest of Phase 6 survival (renewable nodes, campfire, field crafting, S2 + bring-a-kit gate, run resume).
