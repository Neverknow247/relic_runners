extends Node

var rng = RandomNumberGenerator.new()

var dev_mode = false
var transition_time = .25

# Set once per expedition launch (server-picked, broadcast to every peer via
# world.gd's broadcast_expedition_seed) so anything that needs randomized-
# but-consistent-across-peers behavior in a freshly loaded room — like
# enemy_spawner.gd's group rolls — has a shared source to seed from.
var expedition_seed: int = 0

# Per-room enemy state for the current expedition instance, keyed by
# "zone/room" (e.g. "dungeon/room_1"), so leaving and re-entering a room
# within the same expedition finds enemies where they were left (dead ones
# stay dead) instead of a fresh roll. Cleared alongside expedition_seed
# whenever a new expedition actually launches — see world.gd's
# broadcast_expedition_seed and enemy_spawner.gd's room_key/save_state().
var expedition_room_state: Dictionary = {}

var new_save_data = {
	"version" : ProjectSettings.get_setting("application/config/version"),
	"stats" : {
		"power_on_count" : 0,
	},
	"items" : {

	},
	"eggs" : {

	},
	"weapons" : [],
}

var save_data = return_new_save_data()

func return_new_save_data():
	var new_data = new_save_data.duplicate(true)
	return new_data

func delete_save():
	save_data = return_new_save_data()
