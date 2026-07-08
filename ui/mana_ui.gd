extends CanvasLayer

@onready var mana_bar: ProgressBar = $mana_bar
@onready var value_label: Label = $mana_bar/value_label

func update_mana(current: float, max_value: float) -> void:
	mana_bar.max_value = max_value
	mana_bar.value = current
	value_label.text = "%d/%d" % [roundi(current), roundi(max_value)]
