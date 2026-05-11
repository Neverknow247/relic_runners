extends Node

var rng = RandomNumberGenerator.new()

var dev_mode = false
var transition_time = .25

var new_save_data = {
	"version" : ProjectSettings.get_setting("application/config/version"),
	"stats" : {
		"power_on_count" : 0,
	},
	"items" : {
		
	},
	"eggs" : {
		
	},
}

var save_data = return_new_save_data()

func return_new_save_data():
	var new_data = new_save_data.duplicate(true)
	return new_data

func delete_save():
	save_data = return_new_save_data()
