extends Node
## tick_engine.gd — Modular tick system.
## Drives all game updates at a fixed interval.
## Systems connect to tick signals for their update logic.

signal game_tick(delta: float)
signal slow_tick  # Fires every ~1 second for event polling, unlock checks

var _slow_accumulator: float = 0.0
var paused: bool = false

func _process(delta: float) -> void:
	if paused:
		return

	# Main game tick — fires every frame with delta
	game_tick.emit(delta)

	# Slow tick — fires roughly every second
	_slow_accumulator += delta
	if _slow_accumulator >= 1.0:
		_slow_accumulator -= 1.0
		slow_tick.emit()
