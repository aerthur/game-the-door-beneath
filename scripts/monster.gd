extends Node2D

var hp           : int = 1
var damage       : int = 1
var move_speed   : int = 1
var frozen_ticks : int = 0
var xp_value     : int = 1
var monster_type : String = "g"

var is_boss   : bool = false
var grid_row  : int = 0
var grid_lane : int = 0

func _ready():
	_apply_type_color()

func _apply_type_color():
	var main_col : Color
	var dark_col : Color
	var nose_col : Color
	var eye_col  : Color
	match monster_type:
		"g":
			main_col = Color(0.25, 0.52, 0.14, 1)
			dark_col = Color(0.22, 0.48, 0.12, 1)
			nose_col = Color(0.18, 0.40, 0.10, 1)
			eye_col  = Color(0.85, 0.70, 0.05, 1)
		"b":
			main_col = Color(0.18, 0.30, 0.78, 1)
			dark_col = Color(0.15, 0.25, 0.70, 1)
			nose_col = Color(0.12, 0.22, 0.60, 1)
			eye_col  = Color(0.90, 0.90, 0.10, 1)
		"r":
			main_col = Color(0.80, 0.12, 0.08, 1)
			dark_col = Color(0.72, 0.10, 0.08, 1)
			nose_col = Color(0.60, 0.08, 0.06, 1)
			eye_col  = Color(1.00, 0.55, 0.05, 1)
		_:
			return
	$Head.color     = main_col
	$EarLeft.color  = main_col
	$EarRight.color = main_col
	$Body.color     = dark_col
	$ArmLeft.color  = dark_col
	$ArmRight.color = dark_col
	$Nose.color     = nose_col
	$EyeLeft.color  = eye_col
	$EyeRight.color = eye_col

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
