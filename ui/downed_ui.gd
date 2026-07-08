extends CanvasLayer

# Local-only status HUD shown while the owning player is downed — never
# shown for other players' own copies of this node (see player.gd's
# authority-gated _physics_process, the only place that ever calls update()
# or flips visible on).

@onready var time_bar: ProgressBar = $time_bar
@onready var give_up_bar: ProgressBar = $give_up_bar
@onready var give_up_label: Label = $give_up_bar/give_up_label

func update(time_remaining: float, max_time: float, give_up_progress: float, max_give_up: float) -> void:
	time_bar.max_value = max_time
	time_bar.value = time_remaining
	give_up_bar.max_value = max_give_up
	give_up_bar.value = give_up_progress
	give_up_label.text = "Giving Up..." if give_up_progress > 0.0 else "Hold E to Give Up"
