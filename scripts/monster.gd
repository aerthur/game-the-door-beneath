extends Node2D
class_name Monster

var hp                   : int = 0
var hp_max               : int = 0
var damage               : int = 0
var move_speed           : int = 1
var move_period_ticks    : int = 12  # ticks entre chaque déplacement (12 = 1 case/s à 12 tps)
var move_countdown_ticks : int = 12  # décompte avant le prochain déplacement
var frozen_ticks         : int = 0   # ticks de gel restants (12 ticks = 1 s)
var xp_value             : int = 0
var monster_type         : String = ""
var is_boss              : bool = false
var grid_row             : int = 0
var grid_lane            : int = 0
var behavior             : String = "standard"
var obstacle_behaviors   : Array = [ObstacleBehavior.WAIT]
var behavior_weights     : Dictionary = {}
var obstacle_damage      : int = 10  # dégâts infligés aux obstacles (destroy_obstacle)
var palette              : Dictionary = {}
var tags                 : Array = []

# État de saut multi-ticks (jump_obstacle)
# 0 = libre ; > 0 = saut en cours (move periods restants avant résolution)
var jump_ticks_remaining : int = 0
var jump_target_row      : int = -1
var jump_target_lane     : int = -1

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
	# monster_type peut être surchargé dans la def (ex: boss_g → "g")
	monster_type = def.get("monster_type", monster_id)
	hp           = def["hp"]
	hp_max       = def["hp"]
	damage       = def["damage"]
	move_speed   = def["move_speed"]
	xp_value     = def["xp_value"]
	is_boss             = def.get("is_boss", false)
	behavior            = def.get("behavior", "standard")
	obstacle_behaviors  = def.get("obstacle_behaviors", [ObstacleBehavior.WAIT]).duplicate()
	behavior_weights    = def.get("behavior_weights", {}).duplicate()
	obstacle_damage     = def.get("obstacle_damage", 10)
	tags                = def.get("tags", []).duplicate()
	# Conversion move_speed → période en ticks (12 tps)
	# move_speed 1 → 12 ticks/move (1 case/s) ; move_speed 2 → 6 ticks/move (2 cases/s)
	move_period_ticks    = max(1, GameData.TICKS_PER_SECOND / max(1, move_speed))
	move_countdown_ticks = move_period_ticks
	if def.has("palette"):
		palette = def["palette"].duplicate()
		apply_palette(palette)
	if def.has("sprite_path"):
		_apply_sprite(def["sprite_path"])

# API saut multi-ticks (jump_obstacle) ───────────────────────────

func start_jump(target_row: int, target_lane: int) -> void:
	jump_ticks_remaining = 2
	jump_target_row  = target_row
	jump_target_lane = target_lane

func is_jumping() -> bool:
	return jump_ticks_remaining > 0

# Décrémente le compteur de saut. Appelé à chaque move period pendant le saut.
func tick_jump() -> void:
	if jump_ticks_remaining > 0:
		jump_ticks_remaining -= 1

# Point d'extension comportement — appelé à chaque tick de mouvement.
# Comportements spéciaux (ex: "charge", "split") surchargent cette méthode.
func on_tick() -> void:
	pass

func apply_palette(palette: Dictionary) -> void:
	var main_c = palette.get("main", Color.WHITE)
	var dark_c = palette.get("dark", Color.WHITE)
	var nose_c = palette.get("nose", Color.WHITE)
	var eye_c  = palette.get("eye",  Color(0.85, 0.70, 0.05))
	for node_name in ["Head", "EarLeft", "EarRight"]:
		var n = get_node_or_null(node_name)
		if n: n.color = main_c
	for node_name in ["Body", "ArmLeft", "ArmRight"]:
		var n = get_node_or_null(node_name)
		if n: n.color = dark_c
	var nose_n = get_node_or_null("Nose")
	if nose_n: nose_n.color = nose_c
	for node_name in ["EyeLeft", "EyeRight"]:
		var n = get_node_or_null(node_name)
		if n: n.color = eye_c

func _apply_sprite(path: String) -> void:
	var sprite = get_node_or_null("Sprite")
	if sprite:
		sprite.texture = load(path)

func _on_damage_taken() -> void:
	pass
