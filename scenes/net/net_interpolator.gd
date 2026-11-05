class_name NetInterpolator
extends RefCounted

# Snapshot interpolation buffer for a remotely-replicated position.
#
# The authority writes its true global_position into a replicated `net_position`
# var; each non-authority copy feeds those values here (only when they actually
# change) and renders ~DELAY_MS behind "now", interpolating between the two
# snapshots that bracket that render time. This absorbs the jitter, reordering
# and dropped packets that used to make remote players/enemies rubberband when
# their position was assigned raw every frame.
#
# Timing uses each peer's OWN local clock (Time.get_ticks_msec) — we only need
# the RELATIVE spacing of snapshots as they arrive, so no cross-peer clock sync
# is required. Good enough and robust for co-op.

# Render this far behind the newest snapshot so there's (almost) always a future
# snapshot to interpolate toward instead of extrapolating. ~2-3x the send
# interval (players send at 30Hz, enemies at 20Hz).
const DELAY_MS := 100.0
# Plenty to cover the delay window at either send rate; oldest are dropped.
const MAX_SNAPSHOTS := 12

var _buf: Array = []  # [{ "t": int_ms, "pos": Vector2 }], oldest first

# Record a freshly-received authoritative position. Call ONLY when the value
# actually changed (a new replicated sample arrived) — calling every frame with
# an unchanged value would collapse the time spacing and break interpolation.
func push(pos: Vector2) -> void:
	_buf.append({"t": Time.get_ticks_msec(), "pos": pos})
	while _buf.size() > MAX_SNAPSHOTS:
		_buf.pop_front()

func has_data() -> bool:
	return not _buf.is_empty()

func latest() -> Vector2:
	return _buf[-1]["pos"] if not _buf.is_empty() else Vector2.ZERO

# Interpolated position for the current frame. Caller should guard with
# has_data() (returns ZERO on an empty buffer).
func sample() -> Vector2:
	var n := _buf.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1:
		return _buf[0]["pos"]
	var render_t := Time.get_ticks_msec() - DELAY_MS
	# Behind our oldest sample (just started / long stall) — hold at the oldest.
	if render_t <= _buf[0]["t"]:
		return _buf[0]["pos"]
	# Ahead of the newest (starved of updates) — hold at the newest rather than
	# extrapolating into the unknown.
	if render_t >= _buf[n - 1]["t"]:
		return _buf[n - 1]["pos"]
	# Find the pair straddling render_t and lerp between them.
	for i in range(n - 1):
		var a: Dictionary = _buf[i]
		var b: Dictionary = _buf[i + 1]
		if render_t >= a["t"] and render_t <= b["t"]:
			var span: float = float(b["t"] - a["t"])
			var f: float = 0.0 if span <= 0.0 else clampf((render_t - a["t"]) / span, 0.0, 1.0)
			return (a["pos"] as Vector2).lerp(b["pos"], f)
	return _buf[n - 1]["pos"]
