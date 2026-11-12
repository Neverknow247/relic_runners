extends WeaponMod
# Instrument — Songweaver (combat_redesign_plan §7.4): each basic plays a note from
# your absolute movement direction (still = Rest "N"; diagonals count as their
# horizontal part). Bars of 3; a gap over 0.8 s clears the bar. A matching bar
# plays a song for you + allies within 900 (player.broadcast_song); playing the
# active song again = Encore (tier II). A spell plays the song's Finale and ends it.

const SONGS := {"UUU": "anthem", "DDU": "mending", "LRL": "dirge", "RRL": "staccato", "UDU": "quickstep", "NNN": "fermata"}
const DURATION := {"anthem": [8.0, 12.0], "mending": [6.0, 8.0], "dirge": [5.0, 7.0], "staccato": [8.0, 12.0], "quickstep": [8.0, 12.0], "fermata": [1.0, 1.0]}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func on_basic_fire(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	var now := _now()
	if now - float(s.get("last", 0.0)) > 0.8:
		s["bar"] = ""
	s["last"] = now
	var ax: Vector2 = player.input_axis()
	var note := "N"
	if ax.length() > 0.2:
		if absf(ax.x) > 0.01:
			note = "R" if ax.x > 0.0 else "L"
		else:
			note = "D" if ax.y > 0.0 else "U"
	s["bar"] = String(s.get("bar", "")) + note
	var x: Dictionary = cast.get("x", {})
	x["note"] = note
	cast["x"] = x
	Sounds.play_sfx("tap", player.global_position, -6.0, 0.0)
	if String(s["bar"]).length() >= 3:
		var song: String = SONGS.get(s["bar"], "")
		s["bar"] = ""
		if song == "":
			Sounds.play_sfx("fizzle", player.global_position, -8.0, 0.0)
			return
		var tier := 2 if s.get("song", "") == song and now < float(s.get("song_until", 0.0)) else 1
		s["song"] = song
		s["song_until"] = now + DURATION[song][tier - 1]
		player.broadcast_song(song, tier)
		Sounds.play_sfx("armed", player.global_position, -2.0, 0.0)

func on_spell_cast(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	if s.get("song", "") != "" and _now() < float(s.get("song_until", 0.0)):
		var x: Dictionary = cast.get("x", {})
		x["finale"] = s["song"]
		cast["x"] = x
		s["song"] = ""
		s["song_until"] = 0.0

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	var finale: String = cast.get("x", {}).get("finale", "")
	if finale == "" or !is_spell_sd(proj.spell_data) or proj.spell_data.get("_explosion", false):
		return
	CombatFx.ring(proj.get_tree(), pos, 360.0, Color(0.9, 0.7, 1.0), 0.6, 14.0)
	var me = local_player(proj.get_tree())
	if me == null:
		return
	match finale:
		"mending":
			if me.global_position.distance_to(pos) <= 360.0:
				me.heal_capped(40.0, "mending")
		"anthem", "quickstep":
			var caster = caster_node(proj)
			if caster != null and me.global_position.distance_to(caster.global_position) <= 900.0:
				me._roll_cooldown_timer = 0.0

func on_projectile_hit(proj, hurtbox, cast: Dictionary) -> void:
	if cast.get("x", {}).get("finale", "") == "staccato" and !hurtbox.is_player:
		proj.erase_enemy_bullets(hurtbox.global_position, 220.0)

func on_hit_resolved(defender, hitbox, _damage: float, _adv: bool) -> void:
	if hitbox.cast.get("x", {}).get("finale", "") == "dirge":
		defender.fx_stagger(1.0)

func draw(player, weapon, canvas: CanvasItem) -> void:
	var s := st(player, weapon)
	var bar: String = s.get("bar", "")
	if _now() - float(s.get("last", 0.0)) > 0.8:
		bar = ""
	for i in 3:
		var p := Vector2((i - 1) * 36.0, -150.0)
		var filled := i < bar.length()
		canvas.draw_circle(p, 13.0, Color(0, 0, 0, 0.6))
		canvas.draw_circle(p, 9.0, Color(0.95, 0.8, 1.0) if filled else Color(0.4, 0.35, 0.45))
	if s.get("song", "") != "" and _now() < float(s.get("song_until", 0.0)):
		canvas.draw_arc(Vector2(0, -150.0), 64.0, 0.0, TAU, 32, Color(0.9, 0.7, 1.0, 0.7), 4.0)
