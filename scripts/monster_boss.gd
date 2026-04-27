extends Monster

var health_bar : ProgressBar

func _ready() -> void:
	is_boss = true
	_apply_type_color()
	_create_health_bar()
	_create_crown()

func _on_damage_taken() -> void:
	update_health_bar()

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
	health_bar.max_value       = hp_max
	health_bar.value           = hp
	health_bar.position        = Vector2(-55, -120)
	health_bar.size            = Vector2(110, 5)
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
	bg_style.bg_color          = Color(0.12, 0.10, 0.08, 0.90)
	bg_style.border_width_left   = 2
	bg_style.border_width_right  = 2
	bg_style.border_width_top    = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color        = Color(0.85, 0.85, 0.85)
	health_bar.add_theme_stylebox_override("background", bg_style)

func _create_crown():
	var crown = Label.new()
	crown.text     = "♛"
	crown.position = Vector2(-14, -88)
	crown.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	crown.add_theme_font_size_override("font_size", 22)
	add_child(crown)

func update_health_bar():
	if is_instance_valid(health_bar):
		health_bar.value = hp
