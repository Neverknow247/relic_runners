extends Node

var stats = Stats
var utils = Utils

var dev_mode = stats.dev_mode
var backup_num = 10

var default_save_path
var backup_save_path
var SAVE_DATA_PATH
var SAVE_SETTINGS_PATH
var BACKUP_SAVE_DATA_PATH

var default_save_data = stats.return_new_save_data()

func _ready():
	var logged_settings_path
	var dir = DirAccess.open("user://")
	if !dir.dir_exists("save_data"):
		dir.make_dir("save_data")
	if !dir.dir_exists("save_data/additional_resources"):
		dir.make_dir("save_data/additional_resources")
	if dev_mode == true:
		logged_settings_path = "user://settings.cfg"
		default_save_path = "user://save_data/dev_game_save_data.dat"
		backup_save_path = "user://save_data/additional_resources/dev_"
	else:
		logged_settings_path = "user://settings.cfg"
		default_save_path = "user://save_data/game_save_data.dat"
		backup_save_path = "user://save_data/additional_resources/save_"
	SAVE_SETTINGS_PATH = logged_settings_path
	SAVE_DATA_PATH = default_save_path
	BACKUP_SAVE_DATA_PATH = backup_save_path

func save_all():
	update_save_data()
	update_settings()

func update_save_data():
	var save_data = load_data_from_file()
	for stat in stats.save_data:
		save_data[stat] = stats.save_data[stat]
	await SaveAndLoad.save_data_to_file(save_data)
	await SaveAndLoad.save_data_to_backup(save_data)

func load_data_from_file():
	if not FileAccess.file_exists(SAVE_DATA_PATH):
		return default_save_data
	var file = FileAccess.open(SAVE_DATA_PATH, FileAccess.READ)
	var save_data = file.get_var()
	if !save_data:
		push_error("corrupted")
		save_data = check_backups(save_data)
		file.close()
		return save_data
	if str(save_data.version) <= str(default_save_data.version):
		save_data = check_old_data(save_data)
		file.close()
		return save_data
	elif str(save_data.version) > str(default_save_data.version):
		get_tree().change_scene_to_file("res://menus/new_version_screen.tscn")
		file.close()
		return false

func check_backups(save_data):
	var versions = []
	for i in 3:
		if FileAccess.file_exists(BACKUP_SAVE_DATA_PATH+str(i+1)+".dat"):
			var file = FileAccess.open(BACKUP_SAVE_DATA_PATH+str(i+1)+".dat", FileAccess.READ)
			var data = file.get_var()
			if !data:
				pass
			else:
				if versions.size() == 0:
					versions.append({"num":i+1,"modify_time":FileAccess.get_modified_time(BACKUP_SAVE_DATA_PATH+str(i+1)+".dat")})
				else:
					if FileAccess.get_modified_time(BACKUP_SAVE_DATA_PATH+str(i+1)+".dat") > versions[0]["modify_time"]:
						versions.push_front({"num":i+1,"modify_time":FileAccess.get_modified_time(BACKUP_SAVE_DATA_PATH+str(i+1)+".dat")})
	if versions.size() == 0:
		return default_save_data
	else:
		var backup = FileAccess.open(BACKUP_SAVE_DATA_PATH+str(versions[0]["num"])+".dat", FileAccess.READ)
		save_data = check_old_data(backup.get_var())
		return save_data

func check_old_data(save_data):
	var version = default_save_data.version
	update_data(save_data,default_save_data)
	save_data.version = version
	return save_data

func update_data(save_data,default_data):
	for data in default_data:
		if !data in save_data:
				save_data[data] = default_data[data]
		if typeof(save_data[data]) == 27:
			update_data(save_data[data],default_data[data])
	return save_data

func save_data_to_file(save_data):
	var file = FileAccess.open(SAVE_DATA_PATH, FileAccess.WRITE)
	file.store_var(save_data)
	file.close()

func save_data_to_backup(save_data):
	if backup_num >=11:
		backup_num = 1
	var file = FileAccess.open(BACKUP_SAVE_DATA_PATH+str(backup_num)+".dat", FileAccess.WRITE)
	file.store_var(save_data)
	file.close()
	backup_num+=1

func load_data():
	var save_data = load_data_from_file()
	if save_data:
		for stat in save_data:
			if typeof(save_data[stat]) == 27:
				stats["save_data"][stat] = await load_dictionary(save_data[stat])
			else:
				stats["save_data"][stat] = save_data[stat]
		return true
	else:
		return false

func load_dictionary(save_data):
	var stats_save = {}
	for sub_stat in save_data:
		if typeof(save_data[sub_stat]) == 27:
			stats_save[sub_stat] = await load_dictionary(save_data[sub_stat])
		else:
			stats_save[sub_stat] = save_data[sub_stat]
	return stats_save

func update_settings():
	var settings = ConfigFile.new()
	settings.set_value("volume_settings","setting",utils.volume_settings)
	settings.set_value("squash_and_stretch","setting",utils.squash_and_stretch)
	settings.set_value("screen_shake","setting",utils.screen_shake)
	settings.set_value("window_mode","setting",utils.window_mode)
	settings.set_value("seperate_core","setting",utils.seperate_core)
	settings.save(SAVE_SETTINGS_PATH)

func load_settings():
	var settings = ConfigFile.new()
	var err = settings.load(SAVE_SETTINGS_PATH)
	if err != OK:
		return
	for setting in settings.get_sections():
		var single_setting = settings.get_value(setting, "setting")
		utils[setting] = single_setting
