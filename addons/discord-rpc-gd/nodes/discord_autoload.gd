extends Node

const DISCORD_APP_ID := 1501031502933393578

var start_time: int

func _ready() -> void:
	start_time = Time.get_unix_time_from_system()

	DiscordRPC.app_id = DISCORD_APP_ID
	DiscordRPC.details = "Preparing to Run"
	DiscordRPC.state = "Booting"
	DiscordRPC.large_image = "sir_fallen_icon"
	DiscordRPC.large_image_text = "Relic Runners"
	DiscordRPC.start_timestamp = start_time
	DiscordRPC.refresh()

func _process(_delta):
	DiscordRPC.run_callbacks()

func set_host_presence() -> void:
	DiscordRPC.details = "Waiting for Runners"
	DiscordRPC.state = "Run Hb"
	DiscordRPC.large_image = "sir_fallen_icon"
	DiscordRPC.large_image_text = "Relic Runners"
	DiscordRPC.start_timestamp = start_time
	DiscordRPC.refresh()


func set_level_presence(level_name: String) -> void:
	DiscordRPC.details = "Climbing " + level_name
	DiscordRPC.state = "Solo Run"
	DiscordRPC.large_image = "sir_fallen_logo"
	DiscordRPC.large_image_text = level_name
	DiscordRPC.start_timestamp = start_time
	DiscordRPC.refresh()


func set_multiplayer_presence(level_name: String, players: int, max_players: int) -> void:
	DiscordRPC.details = "Climbing " + level_name
	DiscordRPC.state = "%d/%d Knights" % [players, max_players]
	DiscordRPC.large_image = "sir_fallen_logo"
	DiscordRPC.large_image_text = level_name
	DiscordRPC.start_timestamp = start_time
	DiscordRPC.refresh()


func clear_presence() -> void:
	DiscordRPC.clear()
