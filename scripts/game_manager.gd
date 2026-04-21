extends Node

var current_floor: int = 1
var score: int = 0
var total_kills: int = 0

@onready var dungeon : Node2D     = $Dungeon
@onready var hud     : CanvasLayer = $HUD
@onready var cam     : Camera2D   = $Camera2D

var player_scene        = preload("res://scenes/player.tscn")
var enemy_slime_scene   = preload("res://scenes/enemy_slime.tscn")
var potion_scene        = preload("res://scenes/item_potion.tscn")
var stairs_scene        = preload("res://scenes/item_stairs.tscn")

var player: CharacterBody2D = null

func _ready():
	add_to_group("game_manager")
	_start_floor(1)

func _start_floor(floor_num: int):
	current_floor = floor_num
	hud.update_floor(current_floor)

	# Nettoyer les entités
	for n in get_tree().get_nodes_in_group("enemies"): n.queue_free()
	for n in get_tree().get_nodes_in_group("items"):   n.queue_free()

	var rooms = dungeon.generate(current_floor)

	# Joueur
	if player == null or not is_instance_valid(player):
		player = player_scene.instantiate()
		player.health_changed.connect(hud.update_health)
		player.player_died.connect(_on_player_died)
		add_child(player)
		cam.reparent(player)

	player.global_position = dungeon.room_center(0)

	# Ennemis
	var enemy_count = 2 + current_floor * 2
	for i in enemy_count:
		var e = enemy_slime_scene.instantiate()
		add_child(e)
		var ri = randi_range(1, rooms.size() - 1) if rooms.size() > 1 else 0
		e.global_position = dungeon.room_center(ri) + Vector2(
			randf_range(-48, 48), randf_range(-48, 48))

	# Potions
	for i in randi_range(1, 3):
		var p = potion_scene.instantiate()
		add_child(p)
		p.global_position = dungeon.random_floor_pos()

	# Escaliers dans la dernière salle
	var stairs = stairs_scene.instantiate()
	add_child(stairs)
	stairs.global_position = dungeon.room_center(rooms.size() - 1)
	stairs.next_floor_reached.connect(_on_next_floor)

func on_enemy_killed(xp: int):
	total_kills += 1
	score += xp * current_floor
	hud.update_score(score)
	hud.update_kills(total_kills)

func _on_next_floor():
	_start_floor(current_floor + 1)

func _on_player_died():
	hud.show_game_over(score, total_kills, current_floor)
