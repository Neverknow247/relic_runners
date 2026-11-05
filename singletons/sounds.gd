extends Node

@onready var music_player = $music
@onready var voice_player = $voice
@onready var sounds_players = $sounds.get_children()

var music_path = "res://assets/audio/music/"
var voice_path = "res://assets/audio/voice/"
var sounds_path = "res://assets/audio/sounds/"

var music = {
	#"" : load(music_path+""),
	}

var voice = {
	#"" : load(voice_path+""),
}

var sounds = {
	"angel_1_1" : load(sounds_path+"angel_1_1.wav"),
	"bark_twice" : load(sounds_path+"bark_twice.wav"),
	"bell_bronze_ring" : load(sounds_path+"bell_bronze_ring.wav"),
	"meow_1" : load(sounds_path+"meow_1.mp3"),
	"smell_this_bread" : load(sounds_path+"smell_this_bread.wav"),
	#"" : load(sounds_path+".wav"),
}

var music_playing = null

# --- Gameplay SFX (assets/audio/sounds/sfx_<name>.wav) ---------------------
# The game calls play_sfx(name) at every one of these moments, but ships with NO
# sound files yet (the designer is making their own). Drop a file named
# sfx_<name>.wav into assets/audio/sounds/ and it plays from then on; any name
# without a file is skipped silently.
const SFX_NAMES := [
	"shoot_wand", "shoot_orb", "shoot_tome", "enemy_shoot", "hit", "enemy_die",
	"player_hurt", "roll", "tap", "armed", "fizzle", "windup", "sniper_windup",
	"spell_cast", "explosion", "shove", "loot", "ui_click",
]
# World sounds fade out linearly to silence at this distance from the local player.
const HEARING_RANGE := 3600.0
# The same sound can't restart within this many ms (stops a 3-pellet shot or a
# burst of hits from stacking into one loud spike).
const REPEAT_GUARD_MS := 35
var sfx := {}
var _last_played := {}

func _ready() -> void:
	for n in SFX_NAMES:
		var path: String = sounds_path + "sfx_%s.wav" % n
		if ResourceLoader.exists(path):
			sfx[n] = load(path)

# Plays a gameplay sound. pos (a world Vector2) makes it positional relative to the
# local player: quieter with distance, skipped beyond HEARING_RANGE. null = UI/2D.
func play_sfx(sfx_name: String, pos = null, volume_db := 0.0, pitch_var := 0.08) -> void:
	var stream = sfx.get(sfx_name)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sfx_name, -100000)) < REPEAT_GUARD_MS:
		return
	var vol := volume_db
	if pos is Vector2:
		var listener = _listener_position()
		if listener is Vector2:
			var d: float = listener.distance_to(pos)
			if d > HEARING_RANGE:
				return
			vol += linear_to_db(clampf(1.0 - d / HEARING_RANGE, 0.05, 1.0))
	_last_played[sfx_name] = now
	for sound_player in sounds_players:
		if !sound_player.playing:
			sound_player.stream = stream
			sound_player.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			sound_player.volume_db = vol
			sound_player.play()
			return

func _listener_position():
	var world = get_tree().get_first_node_in_group("world")
	if world == null or !world.has_method("get_local_player"):
		return null
	var lp = world.get_local_player()
	return lp.global_position if lp != null else null

func play_music(music_string, pitch_scale = 1, volume_db = 0):
	if music_playing != music_string:
		music_player.pitch_scale = pitch_scale
		music_player.volume_db = volume_db
		music_player.stream = music[music_string]
		music_player.play()
		music_playing = music_string

func play_voice(voice_string, pitch_scale = 1, volume_db = 0):
	if voice_player.playing:
		voice_player.stop()
	voice_player.pitch_scale = pitch_scale
	voice_player.volume_db = volume_db
	voice_player.stream = voice[voice_string]
	voice_player.play()

func play_sound(sound_string, pitch_scale = 1, volume_db = 0):
	for sound_player in sounds_players:
		if !sound_player.playing:
			sound_player.pitch_scale = pitch_scale
			sound_player.volume_db = volume_db
			sound_player.stream = sounds[sound_string]
			sound_player.play()
			return
