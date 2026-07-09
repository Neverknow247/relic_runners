extends CanvasLayer

# Settings overlay: window mode, cursor confinement, and per-bus audio volumes.
# Reads/writes the Utils singleton (which applies each setting live) and persists
# through SaveAndLoad.update_settings() — the same settings.cfg loaded at splash.
# Reusable: instanced by esc_menu (and could be by the main menu); open() shows
# it after syncing the controls to the current saved values.

# Button index -> DisplayServer.WindowMode. Kept small/user-facing. Plain buttons
# rather than an OptionButton: the native dropdown popup is unreliable under this
# project's viewport stretch, and the rest of the UI is button-based anyway.
const WINDOW_MODE_VALUES := [
	DisplayServer.WINDOW_MODE_WINDOWED,
	DisplayServer.WINDOW_MODE_FULLSCREEN,
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
]
const ACTIVE_TINT := Color(1, 1, 0.6)
const INACTIVE_TINT := Color(1, 1, 1)

@onready var windowed_button: Button = $panel_container/margin_container/v_box_container/window_section/window_buttons/windowed_button
@onready var fullscreen_button: Button = $panel_container/margin_container/v_box_container/window_section/window_buttons/fullscreen_button
@onready var exclusive_button: Button = $panel_container/margin_container/v_box_container/window_section/window_buttons/exclusive_button
@onready var mouse_capture_check: CheckButton = $panel_container/margin_container/v_box_container/mouse_row/mouse_capture_check
@onready var master_slider: HSlider = $panel_container/margin_container/v_box_container/master_row/master_slider
@onready var music_slider: HSlider = $panel_container/margin_container/v_box_container/music_row/music_slider
@onready var sounds_slider: HSlider = $panel_container/margin_container/v_box_container/sounds_row/sounds_slider
@onready var voice_slider: HSlider = $panel_container/margin_container/v_box_container/voice_row/voice_slider
@onready var back_button: Button = $panel_container/margin_container/v_box_container/back_button

# Set while pushing saved values into the controls, so their change signals
# don't fire back and re-save on open.
var _syncing := false

func _ready() -> void:
	visible = false
	windowed_button.pressed.connect(func(): _select_window_mode(0))
	fullscreen_button.pressed.connect(func(): _select_window_mode(1))
	exclusive_button.pressed.connect(func(): _select_window_mode(2))
	mouse_capture_check.toggled.connect(_on_mouse_capture_toggled)
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sounds_slider.value_changed.connect(_on_sounds_changed)
	voice_slider.value_changed.connect(_on_voice_changed)
	back_button.pressed.connect(func(): visible = false)

func open() -> void:
	_sync_from_settings()
	visible = true

func _sync_from_settings() -> void:
	_syncing = true
	_refresh_window_mode_highlight()
	mouse_capture_check.button_pressed = Utils.mouse_capture
	master_slider.value = Utils.volume_settings["master_volume"]
	music_slider.value = Utils.volume_settings["music_volume"]
	sounds_slider.value = Utils.volume_settings["sounds_volume"]
	voice_slider.value = Utils.volume_settings["voice_volume"]
	_syncing = false

func _select_window_mode(index: int) -> void:
	# Driven only by an actual button press (never programmatically), so no
	# _syncing guard needed here.
	Utils.window_mode = WINDOW_MODE_VALUES[index]
	SaveAndLoad.update_settings()
	_refresh_window_mode_highlight()

# Tint whichever button matches the current mode so the active choice reads.
func _refresh_window_mode_highlight() -> void:
	var idx := WINDOW_MODE_VALUES.find(Utils.window_mode)
	windowed_button.modulate = ACTIVE_TINT if idx == 0 else INACTIVE_TINT
	fullscreen_button.modulate = ACTIVE_TINT if idx == 1 else INACTIVE_TINT
	exclusive_button.modulate = ACTIVE_TINT if idx == 2 else INACTIVE_TINT

func _on_mouse_capture_toggled(pressed: bool) -> void:
	if _syncing:
		return
	Utils.mouse_capture = pressed
	SaveAndLoad.update_settings()

func _set_volume(key: String, value: float) -> void:
	if _syncing:
		return
	Utils.volume_settings[key] = value
	Utils.set_volume()
	SaveAndLoad.update_settings()

func _on_master_changed(value: float) -> void:
	_set_volume("master_volume", value)

func _on_music_changed(value: float) -> void:
	_set_volume("music_volume", value)

func _on_sounds_changed(value: float) -> void:
	_set_volume("sounds_volume", value)

func _on_voice_changed(value: float) -> void:
	_set_volume("voice_volume", value)
