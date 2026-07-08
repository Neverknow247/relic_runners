extends CanvasLayer

@onready var health_bar: ProgressBar = $health_bar
@onready var value_label: Label = $health_bar/value_label

func update_health(current: float, max_value: float) -> void:
	health_bar.max_value = max_value
	health_bar.value = current
	value_label.text = "%d/%d" % [roundi(current), roundi(max_value)]
