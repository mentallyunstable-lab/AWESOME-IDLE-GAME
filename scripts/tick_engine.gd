extends Node
## tick_engine.gd — Modular tick system.
##
## === GAME LOOP ENTRY POINT ===
## Every frame: game_tick(delta) emitted -> all systems update
## Every ~1s: slow_tick emitted -> event polling, unlock checks
##
## Connected systems:
##   Resources._on_tick(delta) -> recalculates BW, Influence, DR
##   EventSystem._on_game_tick(delta) -> ticks events, spawns new ones
##   Resources._on_slow_tick() -> checks DR thresholds, unlock conditions
##
## Speed multiplier:
##   set_speed(mult) controls game speed (1x/2x/5x/10x)
##   Delta is multiplied before emission — all systems accelerate uniformly

signal game_tick(delta: float)
signal slow_tick  # Fires every ~1 second for event polling, unlock checks

var _slow_accumulator: float = 0.0
var paused: bool = false
var speed_multiplier: float = 1.0

func _process(delta: float) -> void:
	if paused:
		return

	var scaled_delta: float = delta * speed_multiplier

	# Main game tick — fires every frame with scaled delta
	game_tick.emit(scaled_delta)

	# Slow tick — fires roughly every second (real time)
	_slow_accumulator += delta
	if _slow_accumulator >= 1.0:
		_slow_accumulator -= 1.0
		slow_tick.emit()

func set_speed(mult: float) -> void:
	speed_multiplier = maxf(mult, 0.1)
	print("[TickEngine] Speed set to %.1fx" % speed_multiplier)

func get_speed() -> float:
	return speed_multiplier
