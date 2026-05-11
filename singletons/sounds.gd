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
