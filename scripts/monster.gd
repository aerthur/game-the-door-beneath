extends Node2D
class_name Monster

var hp           : int = 0
var hp_max       : int = 0
var damage       : int = 0
var move_speed   : int = 1
var frozen_ticks : int = 0
var xp_value     : int = 0
var monster_type : String = ""
var is_boss      : bool = false
var grid_row     : int = 0
var grid_lane    : int = 0

func take_damage(amount: int) -> void:
	hp -= amount
	_on_damage_taken()
	modulate = Color(1, 0.2, 0.2)
	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		modulate = Color.WHITE if frozen_ticks == 0 else Color(0.5, 0.8, 1.0)

func freeze(ticks: int) -> void:
	frozen_ticks = max(frozen_ticks, ticks)
	modulate = Color(0.5, 0.8, 1.0)

func tick_freeze() -> void:
	if frozen_ticks > 0:
		frozen_ticks -= 1
		if frozen_ticks == 0:
			modulate = Color.WHITE

func setup_from_def(monster_id: String, def: Dictionary) -> void:
	monster_type = monster_id
	hp           = def["hp"]
	hp_max       = def["hp"]
	damage       = def["damage"]
	move_speed   = def["move_speed"]
	xp_value     = def["xp_value"]

func _on_damage_taken() -> void:
	pass
