extends Node

var stats = Stats
var utils = Utils

var dev_mode = stats.dev_mode
# Rotating backup slot (1..BACKUP_SLOTS) the NEXT backup write goes to. Set in _ready
# to the slot after the newest existing backup, so a fresh launch doesn't keep
# overwriting the same slot (it used to restart at 10 every launch).
const BACKUP_SLOTS := 10
var backup_num = 1

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
	backup_num = _next_backup_slot()

func _backup_path(slot: int) -> String:
	return BACKUP_SAVE_DATA_PATH + str(slot) + ".dat"

func _next_backup_slot() -> int:
	var newest_slot := 0
	var newest_time := -1
	for slot in range(1, BACKUP_SLOTS + 1):
		if FileAccess.file_exists(_backup_path(slot)):
			var t := FileAccess.get_modified_time(_backup_path(slot))
			# >= : modified times are 1 s resolution, so on a tie prefer the later
			# slot (written later in the ring's order).
			if t >= newest_time:
				newest_time = t
				newest_slot = slot
	return (newest_slot % BACKUP_SLOTS) + 1

# Numeric version compare for "0.000.036"-style strings: -1 / 0 / 1. String compare
# broke as soon as a part outgrew its zero padding ("0.10" < "0.9" as text).
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0

# Write to a temp file, then swap it in, so a crash or power loss mid-write leaves
# the previous good file instead of a truncated one.
func _write_var_atomic(path: String, data) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveAndLoad: can't write %s (%s)" % [tmp, FileAccess.get_open_error()])
		return false
	file.store_var(data)
	file.close()
	# Try a straight replace first; if the platform refuses to rename over an
	# existing file, remove it and retry (a crash in that tiny gap leaves the .tmp,
	# which load_data_from_file recovers).
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("SaveAndLoad: can't move %s into place (%s)" % [tmp, err])
		return false
	return true

func save_all():
	update_save_data()
	update_settings()

func update_save_data():
	await SaveAndLoad.save_data_to_file(stats.save_data)
	await SaveAndLoad.save_data_to_backup(stats.save_data)

func load_data_from_file() -> Variant:
	# A save interrupted mid-swap leaves only the .tmp: recover it.
	if not FileAccess.file_exists(SAVE_DATA_PATH) and FileAccess.file_exists(SAVE_DATA_PATH + ".tmp"):
		DirAccess.rename_absolute(SAVE_DATA_PATH + ".tmp", SAVE_DATA_PATH)
	if not FileAccess.file_exists(SAVE_DATA_PATH):
		return default_save_data
	var file = FileAccess.open(SAVE_DATA_PATH, FileAccess.READ)
	var save_data = file.get_var() if file != null else null
	if file != null:
		file.close()
	if !(save_data is Dictionary) or !save_data.has("version"):
		push_error("SaveAndLoad: save file corrupted; restoring the newest backup")
		return check_backups(save_data)
	if compare_versions(str(save_data.version), str(default_save_data.version)) <= 0:
		return check_old_data(save_data)
	get_tree().change_scene_to_file("res://scenes/menus/new_version_screen.tscn")
	return false

func check_backups(save_data):
	var versions = []
	for i in BACKUP_SLOTS:
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
		if typeof(save_data[data]) == TYPE_DICTIONARY and typeof(default_data[data]) == TYPE_DICTIONARY:
			update_data(save_data[data],default_data[data])
	return save_data

func save_data_to_file(save_data):
	_write_var_atomic(SAVE_DATA_PATH, save_data)

func save_data_to_backup(save_data):
	if backup_num > BACKUP_SLOTS or backup_num < 1:
		backup_num = 1
	_write_var_atomic(_backup_path(backup_num), save_data)
	backup_num += 1

func load_data():
	var save_data = load_data_from_file()
	if save_data:
		for stat in save_data:
			if typeof(save_data[stat]) == TYPE_DICTIONARY:
				stats["save_data"][stat] = await load_dictionary(save_data[stat])
			else:
				stats["save_data"][stat] = save_data[stat]
		return true
	else:
		return false

func load_dictionary(save_data):
	var stats_save = {}
	for sub_stat in save_data:
		if typeof(save_data[sub_stat]) == TYPE_DICTIONARY:
			stats_save[sub_stat] = await load_dictionary(save_data[sub_stat])
		else:
			stats_save[sub_stat] = save_data[sub_stat]
	return stats_save

func update_settings():
	var settings = ConfigFile.new()
	settings.set_value("volume_settings","setting",utils.volume_settings)
	settings.set_value("squash_and_stretch","setting",utils.squash_and_stretch)
	settings.set_value("screen_shake","setting",utils.screen_shake)
	settings.set_value("camera_lookahead","setting",utils.camera_lookahead)
	settings.set_value("window_mode","setting",utils.window_mode)
	settings.set_value("mouse_capture","setting",utils.mouse_capture)
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
