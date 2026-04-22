extends Node2D
# ── GamePlayer ───────────────────────────────────────────────────
# État et comportement du joueur (déplacement, PV, input).
# Doit être ajouté comme enfant du nœud Game dans main.tscn.
# game.gd définit dans _ready() :
#   player.player_node = player_node
#   player.hud         = hud
#   player.weapons_ref = weapons       ← pour sync player_lane
# Callbacks que game.gd connecte :
#   player.on_game_over = func(): game_over=true; hud.show_game_over(...)

var player_node : Node2D
var hud         : CanvasLayer
var weapons_ref : Node2D    # pour tenir weapons.player_lane à jour

# État joueur (synchronisé depuis game.gd via init_player)
var player_lane : int = 2
var player_hp   : int = 100
var player_max  : int = 100

var on_game_over : Callable  # défini par game.gd

signal game_over_triggered

# ── Init ─────────────────────────────────────────────────────────
func init_player(lane: int, hp: int, hp_max: int):
	player_lane = lane
	player_hp   = hp
	player_max  = hp_max
	player_node.position = Vector2(
		GameData.GRID_X + player_lane * GameData.LANE_W + GameData.LANE_W * 0.5,
		GameData.PLAYER_Y
	)

# ── Déplacement ──────────────────────────────────────────────────
func move(dir: int):
	player_lane = clamp(player_lane + dir, 0, GameData.LANES - 1)
	var tw = create_tween()
	tw.tween_property(player_node, "position",
		Vector2(GameData.GRID_X + player_lane * GameData.LANE_W + GameData.LANE_W * 0.5,
				GameData.PLAYER_Y), 0.08)
	hud.update_lane(player_lane + 1)
	if is_instance_valid(weapons_ref):
		weapons_ref.player_lane = player_lane

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
		move(-1)
	elif event.is_action_pressed("lane_right"):
		move(1)
	elif event.is_action_pressed("next_room") and room_clear:
		# Signale à game.gd de passer à la salle suivante
		emit_signal("next_room_requested")

signal next_room_requested
