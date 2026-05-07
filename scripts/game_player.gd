extends Node2D
# ── GamePlayer ───────────────────────────────────────────────────
# État et comportement du joueur : position périphérique, PV, input.
# Le joueur est positionné sur le périmètre extérieur de la grille,
# jamais à l'intérieur des cellules.
#
# game.gd définit dans _ready() :
#   player_ctrl.player_node = player_node
#   player_ctrl.hud         = hud
#   player_ctrl.weapons_ref = weapons
# Callbacks que game.gd connecte :
#   player_ctrl.game_over_triggered
#   player_ctrl.next_room_requested

var player_node : Node2D
var hud         : CanvasLayer
var weapons_ref : Node2D

# ── Position périphérique ─────────────────────────────────────────
# player_side  : côté actif "bottom" | "top" | "left" | "right"
# player_edge_index : colonne (bottom/top) ou rangée (left/right)
# player_lane  : colonne effective pour le système d'armes et la détection
#                de coups ; bottom/top → edge_index ; left → 0 ; right → max
var player_side       : String = "bottom"
var player_edge_index : int    = 2
var player_lane       : int    = 2  # compat weapons (toujours dans [0, GRID_COLUMNS-1])

# ── Santé ─────────────────────────────────────────────────────────
var player_hp  : int = 100
var player_max : int = 100

var on_game_over : Callable

signal game_over_triggered
signal next_room_requested

# ── Init ─────────────────────────────────────────────────────────
func init_player(side: String, index: int, hp: int, hp_max: int):
	player_side       = side
	player_edge_index = index
	player_hp         = hp
	player_max        = hp_max
	_update_player_lane()
	player_node.position = BoardGeometry.get_player_perimeter_pos(side, index)

# ── Déplacement périphérique ──────────────────────────────────────
# action : "left" | "right" | "up" | "down"
# Retourne true si le joueur a bougé (changement de position ou de côté).
func move_perimeter(action: String) -> bool:
	var max_idx   : int    = BoardGeometry.get_perimeter_max_index(player_side)
	var new_side  : String = player_side
	var new_index : int    = player_edge_index

	match player_side:
		"bottom":
			match action:
				"left":
					if player_edge_index <= 0:
						return false  # neutre : bord gauche atteint
					new_index = player_edge_index - 1
				"right":
					if player_edge_index >= max_idx:
						return false  # neutre : bord droit atteint
					new_index = player_edge_index + 1
				"up":
					if player_edge_index == 0:
						# Transition coin bas-gauche → côté gauche, ligne basse
						new_side  = "left"
						new_index = BoardGeometry.GRID_ROWS - 1
					else:
						return false  # neutre
				_:
					return false  # neutre

		"left":
			match action:
				"up":
					if player_edge_index <= 0:
						return false  # neutre
					new_index = player_edge_index - 1
				"down":
					if player_edge_index >= max_idx:
						return false  # neutre
					new_index = player_edge_index + 1
				"right":
					if player_edge_index == 0:
						# Transition coin haut-gauche → côté haut, colonne gauche
						new_side  = "top"
						new_index = 0
					else:
						return false  # neutre
				_:
					return false  # neutre

		"top":
			match action:
				"left":
					if player_edge_index <= 0:
						return false  # neutre
					new_index = player_edge_index - 1
				"right":
					if player_edge_index >= max_idx:
						return false  # neutre
					new_index = player_edge_index + 1
				"down":
					if player_edge_index == max_idx:
						# Transition coin haut-droit → côté droit, ligne haute
						new_side  = "right"
						new_index = 0
					else:
						return false  # neutre
				_:
					return false  # neutre

		"right":
			match action:
				"up":
					if player_edge_index <= 0:
						return false  # neutre
					new_index = player_edge_index - 1
				"down":
					if player_edge_index >= max_idx:
						return false  # neutre
					new_index = player_edge_index + 1
				"left":
					if player_edge_index == max_idx:
						# Transition coin bas-droit → côté bas, colonne droite
						new_side  = "bottom"
						new_index = BoardGeometry.GRID_COLUMNS - 1
					else:
						return false  # neutre
				_:
					return false  # neutre

	player_side       = new_side
	player_edge_index = new_index
	_update_player_lane()
	_tween_to(BoardGeometry.get_player_perimeter_pos(player_side, player_edge_index))
	hud.update_lane(player_edge_index + 1)
	if is_instance_valid(weapons_ref):
		weapons_ref.player_lane = player_lane
	return true

# ── Helpers internes ──────────────────────────────────────────────
func _update_player_lane() -> void:
	match player_side:
		"bottom", "top":
			player_lane = player_edge_index
		"left":
			player_lane = 0
		"right":
			player_lane = BoardGeometry.GRID_COLUMNS - 1

func _tween_to(pos: Vector2) -> void:
	var tw = create_tween()
	tw.tween_property(player_node, "position", pos, 0.08)

# ── Dégâts ───────────────────────────────────────────────────────
func hit(dmg: int):
	print("[HIT] Joueur touché -%d PV" % dmg)
	player_hp = max(0, player_hp - dmg)
	hud.update_health(player_hp, player_max)
	player_node.modulate = Color(1, 0.25, 0.25)
	await get_tree().create_timer(0.2).timeout
	player_node.modulate = Color.WHITE
	if player_hp <= 0:
		emit_signal("game_over_triggered")

# ── Input ────────────────────────────────────────────────────────
func handle_input(event: InputEvent, game_over: bool, leveling_up: bool, room_clear: bool):
	if game_over or leveling_up: return
	if event.is_action_pressed("lane_left"):
		move_perimeter("left")
	elif event.is_action_pressed("lane_right"):
		move_perimeter("right")
	elif event.is_action_pressed("move_up"):
		move_perimeter("up")
	elif event.is_action_pressed("move_down"):
		move_perimeter("down")
	elif event.is_action_pressed("next_room") and room_clear:
		emit_signal("next_room_requested")
