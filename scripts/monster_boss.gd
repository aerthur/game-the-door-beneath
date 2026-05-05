extends Monster

var health_bar : ProgressBar

func _ready() -> void:
	_create_health_bar()
	_create_crown()

func setup_from_def(monster_id: String, def: Dictionary) -> void:
	super.setup_from_def(monster_id, def)
	# is_boss est déjà positionné par Monster.setup_from_def via def["is_boss"]
	# apply_palette est appelé par super et couvre tous les nœuds partagés

func _on_damage_taken() -> void:
	update_health_bar()

func _create_health_bar():
	health_bar = ProgressBar.new()
	health_bar.max_value       = hp_max
	health_bar.value           = hp
	health_bar.position        = Vector2(-42, -60)
	health_bar.size            = Vector2(84, 6)
	health_bar.show_percentage = false
	add_child(health_bar)

	var bar_col : Color = palette.get("main", Color(0.85, 0.20, 0.15))

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = bar_col
	health_bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color            = Color(0.12, 0.10, 0.08, 0.90)
	bg_style.border_width_left   = 2
	bg_style.border_width_right  = 2
	bg_style.border_width_top    = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color        = Color(0.85, 0.85, 0.85)
	health_bar.add_theme_stylebox_override("background", bg_style)

func _create_crown():
	var crown = Label.new()
	crown.text     = "♛"
	crown.position = Vector2(-10, -76)
	crown.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	crown.add_theme_font_size_override("font_size", 22)
	add_child(crown)

func update_health_bar():
	if is_instance_valid(health_bar):
		health_bar.value = hp
