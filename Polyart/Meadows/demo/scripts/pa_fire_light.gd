class_name PAFireLight
extends OmniLight3D
## Flickers the campfire light. Safe to delete: the original prefab is
## particles only.

## How far the energy swings around the light's base value.
@export_range(0.0, 1.0, 0.01) var flicker_amount := 0.25
## Flickers per second.
@export_range(0.1, 20.0, 0.1) var flicker_speed := 6.0

var _base_energy := 1.0
var _seed := 0.0

func _ready() -> void:
	_base_energy = light_energy
	_seed = randf() * 100.0

func _process(delta: float) -> void:
	_seed += delta * flicker_speed
	# Two offset sine waves, for an irregular flicker.
	var f := sin(_seed) * 0.6 + sin(_seed * 2.37 + 1.3) * 0.4
	light_energy = _base_energy * (1.0 + f * flicker_amount)
