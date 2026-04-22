extends Node2D

var hp           : int = 300
var hp_max       : int = 300
var damage       : int = 25
var move_speed   : int = 1
var frozen_ticks : int = 0
var xp_value     : int = 500
var monster_type : String = "g"
var is_boss      : bool = true

var grid_row  : int = 0
var grid_lane : int = 0

var health_bar : ProgressBar

func _ready():
	_apply_type_color()
	_create_health_bar()
	_create_crown()

func _apply_type_color():
	var main_col : Color
	var dark_col : Color
	var nose_col : Color
	match monster_type:
		"g":
			main_col = Color(0.25, 0.52, 0.14, 1)
			dark_col = Color(0.22, 0.48, 0.12, 1)
			nose_col = Color(0.18, 0.40, 0.10, 1)
		"b":
			main_col = Color(0.22, 0.35, 0.75, 1)
			dark_col = Color(0.18, 0.30, 0.68, 1)
			nose_col = Color(0.15, 0.25, 0.60, 1)
		"r":
			main_col = Color(0.75, 0.18, 0.12, 1)
			dark_col = Color(0.68, 0.15, 0.10, 1)
			nose_col = Color(0.58, 0.12, 0.08, 1)
	$Head.color    = main_col
	$EarLeft.color = main_col
	$EarRight.color = main_col
	$Body.color    = dark_col
	$ArmLeft.color = dark_col
	$ArmRight.color = dark_col
	$Nose.color    = nose_col

func _create_health_bar():
	health_bar = ProgressBar.new()
	health_bar.max_value     = hp_max
	health_bar.value         = hp
	health_bar.position      = Vector2(-180, -115)
	health_bar.size          = Vector2(360, 16)
	health_bar.show_percentage = false
	add_child(health_bar)

	var bar_col : Color
	match monster_type:
		"g": bar_col = Color(0.25, 0.65, 0.14)
		"b": bar_col = Color(0.25, 0.45, 0.90)
		_:   bar_col = Color(0.85, 0.20, 0.15)

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = bar_col
	health_bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.12, 0.10, 0.85)
	health_bar.add_theme_stylebox_override("background", bg_style)

func _create_crown():
	var crown = Label.new()
	crown.text     = "♛"
	crown.position = Vector2(-14, -108)
	crown.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	crown.add_theme_font_size_override("font_size", 22)
	add_child(crown)

func update_health_bar():
	if is_instance_valid(health_bar):
		health_bar.value = hp

func take_damage(amount: int):
	hp -= amount
	update_health_bar()
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
