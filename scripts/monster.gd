extends Node2D

var hp           : int    = 0
var damage       : int    = 0
var move_speed   : int    = 1
var frozen_ticks : int    = 0
var xp_value     : int    = 0
var monster_type : String = ""
var base_color   : Color  = Color.WHITE

var grid_row  : int = 0
var grid_lane : int = 0

func init(def: Dictionary, mtype: String):
	hp           = def.hp
	damage       = def.damage
	move_speed   = def.move_speed
	xp_value     = def.xp_value
	monster_type = mtype
	base_color   = def.color
	_apply_color()

func _apply_color():
	for child in get_children():
		if child is ColorRect:
			match child.name:
				"Body", "ArmLeft", "ArmRight":
					child.color = base_color
				"Head", "EarLeft", "EarRight":
					child.color = base_color.lightened(0.05)
				"Nose":
					child.color = base_color.darkened(0.2)

func take_damage(amount: int):
	hp -= amount
	modulate = Color(1, 0.2, 0.2)
	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		modulate = Color.WHITE if frozen_ticks == 0 else Color(0.5, 0.8, 1.0)

func freeze(ticks: int):
	frozen_ticks = max(frozen_ticks, ticks)
	modulate = Color(0.5, 0.8, 1.0)

func tick_freeze():
	if frozen_ticks > 0:
		frozen_ticks -= 1
		if frozen_ticks == 0:
			modulate = Color.WHITE
