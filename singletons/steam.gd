extends Node
class_name Steam_Client

var stats = Stats

signal leaderboard_found(result)
signal received_results(result)
@warning_ignore("unused_signal")
signal checked_dlc(result)
signal add_player(id)
signal remove_player(id)
signal show_lobbies(lobbies)
signal multiplayer_ready

#var AppID = "4710080"
var AppID = "2802410"
#var AppID = "480"
var lobby_id = 0
var peer : SteamMultiplayerPeer
var is_host = false
var is_joining = false
var multiplayer_signals_connected = false

var logged_in_id
var logged_in_user
var leaderboard_handle
var level_id_board

var main_level_id
var dlc_level_id

func _init():
	OS.set_environment("SteamAppID",AppID)
	OS.set_environment("SteamGameID",AppID)
	Steam.leaderboard_find_result.connect(_on_leaderboard_find_result)
	Steam.leaderboard_score_uploaded.connect(_on_leaderboard_score_uploaded)
	Steam.leaderboard_scores_downloaded.connect(_on_leaderboard_scores_downloaded)
	Steam.file_write_async_complete.connect(_on_file_write_async_complete)
	Steam.file_share_result.connect(_on_file_share_result)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	#Steam.setLeaderboardDetailsMax(5000)

func _ready():
	Steam.steamInit()
	Steam.initRelayNetworkAccess()
	var isRunning = Steam.isSteamRunning()
	
	if !isRunning:
		print("Error: Steam Not Running")
		return

	print("Steam is Running")
	var id = Steam.getSteamID()
	logged_in_id = id
	var steam_name = Steam.getFriendPersonaName(id)
	print("Username: ", str(steam_name))
	logged_in_user = str(steam_name)
	#stats.logged_in_username = logged_in_user
	Steam.requestCurrentStats()
	Steam.requestGlobalStats(60)
	#stats.steam_time = Steam.getServerRealTime()
	#var date_dict = Time.get_datetime_dict_from_unix_time(stats.steam_time)
	#stats.daily_rng_seed = int(str(date_dict["year"])+str(date_dict["month"])+str(date_dict["day"]))

@warning_ignore("unused_parameter")
func _process(delta):
	Steam.run_callbacks()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave_lobby()

func setAchievement(ach):
	var status = Steam.getAchievement(ach)
	if status["achieved"]:
		print("Already Unlocked")
		return
	Steam.setAchievement(ach)
	Steam.storeStats()
	#print("Unlocked Achievment: ",ach)

func find_leaderboard(handle):
	Steam.findLeaderboard(handle)

func _on_leaderboard_find_result(handle: int, found: int) -> void:
	if found == 1:
		leaderboard_handle = handle
		print("Leaderboard handle found: %s" % leaderboard_handle)
		leaderboard_found.emit(true)
	else:
		print("No handle was found")
		leaderboard_found.emit(false)

@warning_ignore("unused_parameter")
func _on_leaderboard_score_uploaded(success: int, this_handle: int, this_score: Dictionary) -> void:
	if success == 1:
		print("Successfully uploaded scores! Score: ", this_score)
	else:
		print("Failed to upload scores!")

func download_leaderboard(from = 0, to = 10000):
	Steam.downloadLeaderboardEntries(from,to,)

@warning_ignore("unused_parameter")
func _on_leaderboard_scores_downloaded(message,handle,result):
	#print("received_result")
	received_results.emit(result)
	#print(message,handle,result)

func _on_file_write_async_complete(m_eResult):
	#print(m_eResult)
	if m_eResult:
		Steam.fileShare(level_id_board)
	else:
		print("failed")

func _on_file_share_result(m_eResult,m_hFile,m_rgchFilename):
	#print("9999")
	print(m_eResult)
	print(m_hFile)
	print(m_rgchFilename)
	#print("9999")
	Steam.attachLeaderboardUGC(m_hFile)

func _connect_multiplayer_signals_once():
	if multiplayer_signals_connected:
		return
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	multiplayer_signals_connected = true

func get_lobby_owner_peer_id() -> int:
	if lobby_id == 0:
		return 1
	return Steam.getLobbyOwner(lobby_id)

func host_lobby():
	print("Attempting to host")
	Steam.createLobby(Steam.LobbyType.LOBBY_TYPE_PUBLIC, 16)
	#Steam.createLobby(Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY, 16)
	is_host = true

func _on_lobby_created(result: int, lobby_id: int):
	print("Steam lobby created")
	if result == Steam.Result.RESULT_OK:
		self.lobby_id = lobby_id
		
		Steam.setLobbyJoinable(lobby_id,true)
		Steam.setLobbyData(lobby_id, "name", logged_in_user)
		
		peer = SteamMultiplayerPeer.new()
		peer.create_host(0)
		
		multiplayer.multiplayer_peer = peer
		_connect_multiplayer_signals_once()
		#multiplayer.peer_connected.connect(_add_player)
		#multiplayer.peer_disconnected.connect(_remove_player)
		_add_player(multiplayer.get_unique_id())
		multiplayer_ready.emit()
		print("Lobby Created, lobby id: ",lobby_id)

func join_lobby(lobby_id : int):
	is_joining = true
	Steam.joinLobby(lobby_id)

#func _on_lobby_joined(lobby_id : int, permissions : int, locked : bool, response : int):
	#if !is_joining:
		#return
	#self.lobby_id = lobby_id
	#peer = SteamMultiplayerPeer.new()
	#peer.create_client(Steam.getLobbyOwner(lobby_id),0)
	#multiplayer.multiplayer_peer = peer
	#is_joining = false

func _on_lobby_joined(lobby_id: int, permissions: int, locked: bool, response: int):
	if !is_joining:
		return
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("failed to join lobby. Response: ",response)
		is_joining = false
		return
	self.lobby_id = lobby_id
	var host_id = Steam.getLobbyOwner(lobby_id)
	if host_id == Steam.getSteamID():
		print("Cannot join your own lobby with the same Steam account")
		is_joining = false
		return
	peer = SteamMultiplayerPeer.new()
	var err = peer.create_client(host_id,0)
	if err != OK:
		print("Failed to create Steam client peer. Error: ", err)
		is_joining = false
		return
	multiplayer.multiplayer_peer = peer
	_connect_multiplayer_signals_once()
	is_joining = false
	multiplayer_ready.emit()

func leave_lobby():
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false
	is_joining = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer = null

func _add_player(id : int = 1):
	print("Player: ",id)
	add_player.emit(id)

func _remove_player(id : int):
	remove_player.emit(id)

func requestLobbyList():
	Steam.requestLobbyList()

func _on_lobby_match_list(_lobby_list : Array):
	show_lobbies.emit(_lobby_list)

func steam_set_stat_int(stat_name,value):
	Steam.setStatInt(stat_name,value)
	Steam.storeStats()

func steam_get_stat_int(stat_name):
	var get_stat = Steam.getStatInt(stat_name)
	return get_stat

func steam_get_global_stat_int(stat_name):
	var get_stat = Steam.getGlobalStatInt(stat_name)
	return get_stat
